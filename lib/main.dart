import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

// Screens
import 'screens/auth_gate.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
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

      // ✅ Siempre arrancamos en '/', que muestra el AuthGate
      initialRoute: '/',

      routes: {
        '/': (context) => const AuthGate(), // raíz controlada por AuthGate
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
