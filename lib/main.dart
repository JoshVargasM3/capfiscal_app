import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';

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

    // 🔐 Activa App Check en desarrollo para silenciar los avisos del Storage.
    if (!kIsWeb) {
      if (kDebugMode || kProfileMode) {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.debug,
          appleProvider: AppleProvider.debug,
        );
      } else {
        await FirebaseAppCheck.instance.activate();
      }
    }

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
