import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_functions/cloud_functions.dart'; // 👈 para callable ping

import 'firebase_options.dart';
import 'config/subscription_config.dart';

// Screens
import 'screens/auth_gate.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/biblioteca_legal_screen.dart';
import 'screens/video_screen.dart';
import 'screens/chat.dart';
import 'screens/user_profile_screen.dart';
import 'screens/offline_screen.dart';
import 'screens/offline_home_screen.dart';
import 'services/connectivity_service.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ✅ Inicializa Firebase ANTES de runApp (evita I-COR000005).
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // 👇 Log de diagnóstico: confirma a qué proyecto apunta el cliente
    final o = Firebase.app().options;
    debugPrint('[FIREBASE] projectId=${o.projectId} appId=${o.appId}');

    // 🔐 Activa App Check en desarrollo para silenciar los avisos del Storage.
    await _configureFirebaseAppCheck();
    await _configureStripeSdk();

    // Handler global: evita que errores burbujeen y cierren la app.
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      // TODO: enviar a Crashlytics/Sentry si lo deseas
      return true;
    };

    runApp(const MyApp());
  }, (error, stack) {
    // TODO: log centralizado si lo deseas
  });
}

Future<void> _configureFirebaseAppCheck() async {
  if (kIsWeb) {
    return;
  }

  final appCheck = FirebaseAppCheck.instance;
  if (kDebugMode || kProfileMode) {
    await appCheck.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.debug,
    );
  } else {
    await appCheck.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.deviceCheck,
    );
  }
}

Future<void> _configureStripeSdk() async {
  final publishableKey = SubscriptionConfig.stripePublishableKey;
  if (publishableKey.isEmpty) {
    debugPrint(
      '[Stripe] STRIPE_PUBLISHABLE_KEY no configurado. '
      'Ejecuta la app con --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...',
    );
    return;
  }

  Stripe.publishableKey = publishableKey;

  try {
    await Stripe.instance.applySettings();
  } catch (err) {
    debugPrint('[Stripe] No se pudieron aplicar los ajustes: $err');
  }

  SubscriptionConfig.debugLog('[Stripe] SDK inicializado');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const BootstrapGate(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/biblioteca': (context) => const BibliotecaLegalScreen(),
        '/video': (context) => const VideoScreen(),
        '/chat': (context) => const ChatScreen(),
        '/perfil': (context) => const UserProfileScreen(),

        // 🧪 Ruta de diagnóstico para probar la callable `ping`
        '/_ping': (context) => const DebugPingScreen(),
      },
    );
  }
}

/// Puerta de arranque segura con timeout/retry y modo recuperación.
class BootstrapGate extends StatefulWidget {
  const BootstrapGate({super.key});

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate> {
  final ConnectivityService _connectivity = ConnectivityService();
  StreamSubscription<ConnectivityStatus>? _subscription;
  ConnectivityStatus _status = ConnectivityStatus.online;
  bool _offlineMode = false;

  @override
  void initState() {
    super.initState();
    _subscription = _connectivity.watchStatus().listen((status) {
      if (!mounted) return;
      setState(() {
        _status = status;
        if (status == ConnectivityStatus.online) {
          _offlineMode = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  bool get _isOffline => _status == ConnectivityStatus.offline;

  Future<void> _retryConnection() async {
    final status = await _connectivity.currentStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      if (status == ConnectivityStatus.online) {
        _offlineMode = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isOffline && !_offlineMode) {
      return OfflineScreen(
        onRetry: _retryConnection,
        onContinueOffline: () {
          setState(() {
            _offlineMode = true;
          });
        },
      );
    }

    return FutureBuilder<bool>(
      future: _safeInit(skipNetwork: _isOffline),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        if (snap.hasError || snap.data != true) {
          return const _RecoveryScreen();
        }
        if (_offlineMode) {
          return OfflineHomeScreen(
            onRetryOnline: _retryConnection,
          );
        }
        return const AuthGate();
      },
    );
  }

  Future<bool> _safeInit({required bool skipNetwork}) async {
    final prefs = await SharedPreferences.getInstance();

    final wasUnclean = prefs.getBool('boot_unclean') ?? false;
    await prefs.setBool('boot_unclean', true);

    try {
      if (wasUnclean) {
        await _safeCleanup(prefs);
      }

      if (!skipNetwork) {
        await _retry(() async {
          if (Firebase.apps.isEmpty) {
            await Firebase.initializeApp(
              options: DefaultFirebaseOptions.currentPlatform,
            );
          }
          // Aquí otras inits ligeras (Remote Config, etc.)
        }, attempts: 3, delayMs: 300)
            .timeout(const Duration(seconds: 10));
      }

      await prefs.setBool('boot_unclean', false);
      return true;
    } catch (_) {
      if (skipNetwork) {
        await prefs.setBool('boot_unclean', false);
        return true;
      }
      return false;
    }
  }

  Future<void> _safeCleanup(SharedPreferences prefs) async {
    // Limpiezas puntuales si lo necesitas (prefs.remove('clave'), etc.)
  }

  Future<T> _retry<T>(
    Future<T> Function() op, {
    int attempts = 2,
    int delayMs = 250,
  }) async {
    var i = 0;
    while (true) {
      try {
        return await op();
      } catch (_) {
        i++;
        if (i >= attempts) rethrow;
        await Future.delayed(Duration(milliseconds: delayMs * i));
      }
    }
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator()),
    );
    // Si usas flutter_native_splash, este splash apenas se verá.
  }
}

class _RecoveryScreen extends StatelessWidget {
  const _RecoveryScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              'Hubo un problema iniciando.\nIntentando recuperar…',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                (context as Element).reassemble(); // reintento rápido
              },
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// ====== 🧪 Pantalla de diagnóstico para probar la callable `ping` ======
/// Navega manualmente a '/_ping' (solo queda registrada la ruta; no hay botón visible)
class DebugPingScreen extends StatefulWidget {
  const DebugPingScreen({super.key});

  @override
  State<DebugPingScreen> createState() => _DebugPingScreenState();
}

class _DebugPingScreenState extends State<DebugPingScreen> {
  String _result = 'Presiona "Probar ping"';

  Future<void> _runPing() async {
    setState(() => _result = 'Llamando…');
    try {
      final functions = FirebaseFunctions.instanceFor(
        app: Firebase.app(), // 👈 MISMO app
        region: 'us-central1',
      );
      final res = await functions.httpsCallable('ping').call();
      setState(() => _result = 'OK: ${res.data}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PING => ${res.data}')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() => _result = 'Error: ${e.code}: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.code}: ${e.message}')),
        );
      }
    } catch (e) {
      setState(() => _result = 'Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = Firebase.app().options;
    return Scaffold(
      appBar: AppBar(title: const Text('Debug Ping')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Proyecto: ${o.projectId}\nAppId: ${o.appId}'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _runPing,
              icon: const Icon(Icons.cloud),
              label: const Text('Probar ping'),
            ),
            const SizedBox(height: 12),
            Text(
              _result,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Esperado: { uid: "<tu uid>", appCheck: true/false }',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
