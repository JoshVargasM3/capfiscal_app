import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'biblioteca_legal_screen.dart';
import 'login_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data != null) {
          return const BibliotecaLegalScreen(); // logueado
        }
        return const LoginScreen(); // no logueado
      },
    );
  }
}
