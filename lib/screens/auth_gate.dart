import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/subscription_service.dart';
import '../widgets/subscription_scope.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'subscription_required_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Mientras conecta con FirebaseAuth
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Si hay usuario autenticado -> Home
        if (snapshot.hasData) {
          final user = snapshot.data!;
          return _SubscriptionGate(user: user);
        }

        // Si NO hay usuario -> Login
        return const LoginScreen();
      },
    );
  }
}

class _SubscriptionGate extends StatefulWidget {
  const _SubscriptionGate({required this.user});

  final User user;

  @override
  State<_SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<_SubscriptionGate> {
  final SubscriptionService _service = SubscriptionService();
  late Stream<SubscriptionStatus> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _service.watchSubscriptionStatus(widget.user.uid);
  }

  @override
  void didUpdateWidget(covariant _SubscriptionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _stream = _service.watchSubscriptionStatus(widget.user.uid);
    }
  }

  Future<SubscriptionStatus> _refresh() {
    return _service.refreshSubscriptionStatus(widget.user.uid);
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SubscriptionStatus>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return SubscriptionRequiredScreen(
            status: SubscriptionStatus.empty(),
            onRefresh: _refresh,
            onSignOut: _signOut,
            errorMessage: 'No pudimos verificar tu suscripción: ${snapshot.error}',
          );
        }

        final status = snapshot.data ?? SubscriptionStatus.empty();

        if (status.isAccessGranted) {
          return SubscriptionScope(
            status: status,
            onRefresh: _refresh,
            child: const HomeScreen(),
          );
        }

        return SubscriptionRequiredScreen(
          status: status,
          onRefresh: _refresh,
          onSignOut: _signOut,
        );
      },
    );
  }
}
