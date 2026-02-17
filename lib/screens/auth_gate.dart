import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/cap_colors.dart';
import 'email_verification_screen.dart';
import 'login_screen.dart' as login;

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String? _ensuredUid;
  Future<void>? _ensureFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cuando vuelve la app, recarga el usuario para refrescar emailVerified.
    if (state == AppLifecycleState.resumed) {
      final u = _auth.currentUser;
      if (u != null) {
        unawaited(u.reload().then((_) {
          if (mounted) setState(() {});
        }));
      }
    }
  }

  Future<void> _ensureUserDoc(User user) async {
    // evita repetir en cada rebuild
    if (_ensuredUid == user.uid && _ensureFuture != null) return _ensureFuture!;
    _ensuredUid = user.uid;

    final ref = _db.collection('users').doc(user.uid);

    _ensureFuture = () async {
      final snap = await ref.get();
      if (snap.exists) {
        // opcional: actualizar lastLoginAt sin pisar createdAt
        await ref.set(
          {'lastLoginAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
        return;
      }

      // Crea el doc mínimo. Ajusta campos según lo que use tu app.
      await ref.set({
        'uid': user.uid,
        'email': (user.email ?? '').trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }();

    return _ensureFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _GateLoading();
        }

        final user = authSnap.data;
        if (user == null) {
          return const login.LoginScreen();
        }

        // 1) Exigir email verificado
        if (!user.emailVerified) {
          return EmailVerificationScreen(
            email: (user.email ?? '').trim(),
            onVerified: () async {
              await _auth.currentUser?.reload();
              if (mounted) setState(() {});
            },
            onResend: () async {
              await _auth.currentUser?.sendEmailVerification();
            },
            onSignOut: () async {
              await _auth.signOut();
            },
          );
        }

        // 2) Asegurar users/{uid} y luego entrar a child
        return FutureBuilder<void>(
          future: _ensureUserDoc(user),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _GateLoading();
            }

            if (snap.hasError) {
              return Scaffold(
                backgroundColor: CapColors.bgTop,
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'No pudimos inicializar tu cuenta.',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${snap.error}',
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          onPressed: () => setState(() {
                            // fuerza reintento real
                            _ensuredUid = null;
                            _ensureFuture = null;
                          }),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CapColors.gold,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Reintentar'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => _auth.signOut(),
                          child: const Text(
                            'Cerrar sesión',
                            style: TextStyle(color: CapColors.gold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return widget.child;
          },
        );
      },
    );
  }
}

class _GateLoading extends StatelessWidget {
  const _GateLoading();

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
