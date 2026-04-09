import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'firebase_options.dart';

// ✅ THEME / COLORS
import 'theme/cap_theme.dart';
import 'theme/cap_colors.dart';

// Screens
import 'screens/auth_gate.dart'; // ✅ SOLO AUTH (sin suscripción)
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

    ui.PlatformDispatcher.instance.onError = (error, stack) {
      // evita crash global por errores no capturados
      return true;
    };

    runApp(const MyApp());
  }, (error, stack) {
    // opcional: enviar a Crashlytics
  });
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Widget _auth(Widget child) => AuthGate(child: child);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: CapTheme.dark,
      darkTheme: CapTheme.dark,
      themeMode: ThemeMode.dark,
      initialRoute: '/',
      routes: {
        '/': (context) => const BootstrapGate(),
        '/login': (context) => const LoginScreen(),

        // ✅ Rutas protegidas SOLO por AuthGate (sin suscripción)
        '/home': (context) => _auth(const HomeScreen()),
        '/biblioteca': (context) => _auth(const BibliotecaLegalScreen()),
        '/video': (context) => _auth(const VideoScreen()),
        '/chat': (context) => _auth(const ChatScreen()),
        '/perfil': (context) => _auth(const UserProfileScreen()),

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
      future: _safeInit(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        if (snap.hasError || snap.data != true) {
          return const _RecoveryScreen();
        }

        // ✅ Offline mode: permite entrar SOLO para ver lo que ya esté disponible.
        // Las compras por documento NO funcionarán offline.
        if (_offlineMode) {
          return AuthGate(
            child: OfflineHomeScreen(onRetryOnline: _retryConnection),
          );
        }

        // ✅ Entrada normal
        return const AuthGate(child: HomeScreen());
      },
    );
  }

  Future<bool> _safeInit() async {
    final prefs = await SharedPreferences.getInstance();

    final wasUnclean = prefs.getBool('boot_unclean') ?? false;
    await prefs.setBool('boot_unclean', true);

    try {
      if (wasUnclean) {
        await _safeCleanup(prefs);
      }
      await prefs.setBool('boot_unclean', false);
      return true;
    } catch (_) {
      await prefs.setBool('boot_unclean', false);
      return true; // mantenemos “arranque tolerante”
    }
  }

  Future<void> _safeCleanup(SharedPreferences prefs) async {
    // Aquí puedes limpiar flags viejos si quieres (ej: llaves de suscripción),
    // pero no es obligatorio para compilar.
    // Ejemplo opcional:
    // await prefs.remove('sub_end_ms');
    // await prefs.remove('sub_state');
    // await prefs.remove('sub_grace_end_ms');
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
