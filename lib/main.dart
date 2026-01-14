import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'firebase_options.dart';
import 'config/subscription_config.dart';

// ✅ THEME / COLORS
import 'theme/cap_theme.dart';
import 'theme/cap_colors.dart';

// Screens
import 'screens/auth_gate.dart'; // ✅ aquí vive SubscriptionGate
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/biblioteca_legal_screen.dart';
import 'screens/video_screen.dart';
import 'screens/chat.dart';
import 'screens/user_profile_screen.dart';
import 'screens/offline_screen.dart';
import 'screens/offline_home_screen.dart';

import 'services/connectivity_service.dart';
import 'services/subscription_service.dart'; // para enum en offline gate

// ✅ NUEVO: Scope global
import 'widgets/subscription_scope_host.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    if (kDebugMode) {
      final o = Firebase.app().options;
      debugPrint('[FIREBASE] projectId=${o.projectId} appId=${o.appId}');
    }

    await _configureFirebaseAppCheck();
    await _configureStripeSdk();

    ui.PlatformDispatcher.instance.onError = (error, stack) {
      return true;
    };

    runApp(const MyApp());
  }, (error, stack) {});
}

Future<void> _configureFirebaseAppCheck() async {
  if (kIsWeb) return;

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

  await appCheck.setTokenAutoRefreshEnabled(true);
}

Future<void> _configureStripeSdk() async {
  final publishableKey = SubscriptionConfig.stripePublishableKey;
  if (publishableKey.isEmpty) return;

  Stripe.publishableKey = publishableKey;

  try {
    await Stripe.instance.applySettings();
  } catch (_) {}
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // ✅ CAPFISCAL THEME
      theme: CapTheme.dark,
      darkTheme: CapTheme.dark,
      themeMode: ThemeMode.dark,

      // ✅ NUEVO: pone SubscriptionScope arriba de TODAS las rutas/pantallas
      builder: (context, child) {
        return SubscriptionScopeHost(
          child: child ?? const SizedBox.shrink(),
        );
      },

      initialRoute: '/',
      routes: {
        '/': (context) => const BootstrapGate(),
        '/login': (context) => const LoginScreen(),

        // ✅ TODO protegido
        '/home': (context) => const SubscriptionGate(child: HomeScreen()),
        '/biblioteca': (context) =>
            const SubscriptionGate(child: BibliotecaLegalScreen()),
        '/video': (context) => const SubscriptionGate(child: VideoScreen()),
        '/chat': (context) => const SubscriptionGate(child: ChatScreen()),
        '/perfil': (context) =>
            const SubscriptionGate(child: UserProfileScreen()),

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

        // ✅ offline mode: NO dejar entrar si ya venció según cache
        if (_offlineMode) {
          return _OfflineSubscriptionGate(
            onRetryOnline: _retryConnection,
            child: OfflineHomeScreen(onRetryOnline: _retryConnection),
          );
        }

        // ✅ Entry normal protegido
        return const SubscriptionGate(child: HomeScreen());
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

  Future<void> _safeCleanup(SharedPreferences prefs) async {}

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
      backgroundColor: CapColors.bgTop,
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(CapColors.gold),
        ),
      ),
    );
  }
}

class _RecoveryScreen extends StatelessWidget {
  const _RecoveryScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CapColors.bgTop,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(CapColors.gold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Hubo un problema iniciando.\nIntentando recuperar…',
              textAlign: TextAlign.center,
              style: TextStyle(color: CapColors.textMuted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                (context as Element).reassemble();
              },
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ Bloqueo offline basado en cache (sub_end_ms + sub_state)
class _OfflineSubscriptionGate extends StatelessWidget {
  const _OfflineSubscriptionGate({
    required this.child,
    required this.onRetryOnline,
  });

  final Widget child;
  final Future<void> Function() onRetryOnline;

  Future<bool> _isStillValidOffline() async {
    final prefs = await SharedPreferences.getInstance();

    final endMs = prefs.getInt('sub_end_ms');
    final state = prefs.getString('sub_state') ?? '';

    if (endMs == null) return false;

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final notExpired = now < endMs;

    // strict: solo ACTIVE
    final stateOk = state == SubscriptionState.active.name;

    return stateOk && notExpired;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isStillValidOffline(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: CapColors.bgTop,
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(CapColors.gold),
              ),
            ),
          );
        }

        if (snap.data == true) return child;

        return Scaffold(
          backgroundColor: CapColors.bgTop,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    color: CapColors.gold,
                    size: 60,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Suscripción vencida',
                    style: TextStyle(
                      color: CapColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Sin conexión no podemos validar/renovar tu acceso.\nConéctate para pagar y reactivar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: CapColors.textMuted, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async => onRetryOnline(),
                    child: const Text('Reintentar conexión'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ====== 🧪 Pantalla de diagnóstico para probar la callable `ping` ======
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
        app: Firebase.app(),
        region: 'us-central1',
      );
      final res = await functions.httpsCallable('ping').call();
      setState(() => _result = 'OK: ${res.data}');
    } on FirebaseFunctionsException catch (e) {
      setState(() => _result = 'Error: ${e.code}: ${e.message}');
    } catch (e) {
      setState(() => _result = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = Firebase.app().options;
    return Scaffold(
      backgroundColor: CapColors.bgTop,
      appBar: AppBar(title: const Text('Debug Ping')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Proyecto: ${o.projectId}\nAppId: ${o.appId}',
              style: const TextStyle(color: CapColors.text),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _runPing,
              icon: const Icon(Icons.cloud),
              label: const Text('Probar ping'),
            ),
            const SizedBox(height: 12),
            Text(
              _result,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: CapColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
