import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/subscription_service.dart';
import 'subscription_scope.dart';

/// Envuelve toda la app con SubscriptionScope y lo mantiene sincronizado
/// con Firestore (ideal si tu source of truth es Stripe->webhooks->Firestore).
class SubscriptionScopeHost extends StatefulWidget {
  const SubscriptionScopeHost({
    super.key,
    required this.child,
    this.service,
    this.auth,
  });

  final Widget child;
  final SubscriptionService? service;
  final FirebaseAuth? auth;

  @override
  State<SubscriptionScopeHost> createState() => _SubscriptionScopeHostState();
}

class _SubscriptionScopeHostState extends State<SubscriptionScopeHost> {
  late final SubscriptionService _service;
  late final FirebaseAuth _auth;

  StreamSubscription<SubscriptionStatus>? _sub;
  SubscriptionStatus _status = SubscriptionStatus.empty();
  String? _currentUid;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SubscriptionService();
    _auth = widget.auth ?? FirebaseAuth.instance;

    _auth.authStateChanges().listen((user) {
      _bindForUser(user?.uid);
    });

    _bindForUser(_auth.currentUser?.uid);
  }

  void _bindForUser(String? uid) {
    if (_currentUid == uid) return;
    _currentUid = uid;

    _sub?.cancel();
    _sub = null;

    if (uid == null) {
      setState(() => _status = SubscriptionStatus.empty());
      return;
    }

    _sub = _service.watchSubscriptionStatus(uid).listen(
      (s) {
        if (!mounted) return;
        setState(() => _status = s);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _status = SubscriptionStatus.empty());
      },
    );
  }

  Future<SubscriptionStatus> _refresh() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      _status = SubscriptionStatus.empty();
      return _status;
    }

    final refreshed = await _service.refreshSubscriptionStatus(uid);
    if (mounted) setState(() => _status = refreshed);
    return refreshed;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SubscriptionScope(
      status: _status,
      onRefresh: _refresh,
      child: widget.child,
    );
  }
}
