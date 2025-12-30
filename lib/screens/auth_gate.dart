import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/subscription_service.dart';
import 'home_screen.dart';
import 'login_screen.dart' as login;
import 'subscription_required_screen.dart' as sub;

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return const SubscriptionGate(child: HomeScreen());
  }
}

class SubscriptionGate extends StatefulWidget {
  const SubscriptionGate({super.key, required this.child});
  final Widget child;

  @override
  State<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<SubscriptionGate>
    with WidgetsBindingObserver {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  late final SubscriptionService _subs = SubscriptionService(firestore: _db);

  Timer? _expiryTimer;
  DateTime? _scheduledFor;

  // ✅ estrictísimo: solo ACTIVE
  bool _canAccess(SubscriptionStatus s) => s.state == SubscriptionState.active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ✅ cada vez que regresa la app, fuerza refresh desde server
    if (state == AppLifecycleState.resumed) {
      final u = _auth.currentUser;
      if (u != null) {
        unawaited(_refreshServer(u.uid));
      }
    }
  }

  void _scheduleRecheck(SubscriptionStatus status) {
    final now = DateTime.now().toUtc();
    DateTime? next;

    // Fin de acceso: endDate o graceEndsAt
    final candidates = <DateTime?>[
      status.endDate,
      status.graceEndsAt,
      status.cancelsAt,
    ];

    for (final d in candidates) {
      if (d == null) continue;
      if (d.isAfter(now)) {
        if (next == null || d.isBefore(next)) next = d;
      }
    }

    if (next == null) {
      _expiryTimer?.cancel();
      _scheduledFor = null;
      return;
    }

    if (_scheduledFor != null && next.isAtSameMomentAs(_scheduledFor!)) return;

    _scheduledFor = next;
    _expiryTimer?.cancel();

    final delay = next.difference(now) + const Duration(seconds: 2);
    _expiryTimer = Timer(delay, () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _cacheForOffline(SubscriptionStatus st) async {
    final prefs = await SharedPreferences.getInstance();
    final end = st.endDate?.millisecondsSinceEpoch;
    final grace = st.graceEndsAt?.millisecondsSinceEpoch;

    if (end != null) {
      await prefs.setInt('sub_end_ms', end);
    } else {
      await prefs.remove('sub_end_ms');
    }

    if (grace != null) {
      await prefs.setInt('sub_grace_end_ms', grace);
    } else {
      await prefs.remove('sub_grace_end_ms');
    }

    await prefs.setString('sub_state', st.state.name);
    await prefs.setInt(
        'sub_cached_at_ms', DateTime.now().millisecondsSinceEpoch);
  }

  Future<SubscriptionStatus> _refreshServer(String uid) async {
    final s = await _subs.refreshSubscriptionStatus(uid);
    _scheduleRecheck(s);
    unawaited(_cacheForOffline(s));
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final user = authSnap.data;
        if (user == null) {
          return const login.LoginScreen();
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('users')
              .doc(user.uid)
              .snapshots(includeMetadataChanges: true),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            if (userSnap.data?.exists != true) {
              unawaited(SubscriptionService.ensureUserDoc(user));
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            final status = SubscriptionStatus.fromSnapshot(userSnap.data!);

            _scheduleRecheck(status);
            unawaited(_cacheForOffline(status));

            if (_canAccess(status)) {
              return widget.child;
            }

            return sub.SubscriptionRequiredScreen(
              status: status,
              onRefresh: () => _refreshServer(user.uid),
              onSignOut: () async => _auth.signOut(),
              errorMessage: userSnap.hasError
                  ? 'No pudimos validar tu suscripción.'
                  : null,
            );
          },
        );
      },
    );
  }
}
