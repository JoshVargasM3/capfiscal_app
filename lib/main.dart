import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

// Screens
import 'screens/auth_gate.dart';
import 'screens/login_screen.dart';
import 'screens/biblioteca_legal_screen.dart';
import 'screens/video_screen.dart';
import 'screens/chat.dart';
import 'screens/user_profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // 👇 Iniciamos con el AuthGate: si hay sesión -> app, si no -> Login
      home: const AuthGate(),

      // Rutas nombradas que usa tu app
      routes: {
        '/login': (context) => const LoginScreen(),
        '/biblioteca': (context) => const BibliotecaLegalScreen(),
        '/video': (context) => const VideoScreen(),
        '/chat': (context) => const ChatScreen(),
        '/perfil': (context) => const UserProfileScreen(),
      },
    );
  }
}
