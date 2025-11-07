import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Result of creating a hosted checkout session in Stripe.
class SubscriptionCheckoutSession {
  const SubscriptionCheckoutSession({
    required this.sessionId,
    required this.url,
  });

  final String sessionId;
  final Uri url;
}

/// Confirmation payload returned after Stripe validates a session.
class SubscriptionCheckoutConfirmation {
  const SubscriptionCheckoutConfirmation({
    required this.status,
    this.message,
    this.subscriptionId,
  });

  final String status;
  final String? message;
  final String? subscriptionId;

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
}

/// Helper around the Firebase callable functions that orchestrate Stripe.
class SubscriptionPaymentService {
  SubscriptionPaymentService._({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(
              app: Firebase.app(),
              region: const String.fromEnvironment(
                'FUNCTIONS_REGION',
                defaultValue: 'us-central1',
              ),
            );

  static final SubscriptionPaymentService instance =
      SubscriptionPaymentService._();

  final FirebaseFunctions _functions;

  /// Requests the backend to create a hosted checkout session in Stripe.
  Future<SubscriptionCheckoutSession> createHostedCheckout({
    String? priceId,
    Map<String, dynamic>? metadata,
    String? successUrl,
    String? cancelUrl,
  }) async {
    final res = await _call(
      'createCheckoutSession',
      data: <String, dynamic>{
        if (priceId != null) 'priceId': priceId,
        if (metadata != null) 'metadata': metadata,
        if (successUrl != null) 'successUrl': successUrl,
        if (cancelUrl != null) 'cancelUrl': cancelUrl,
        if (!kIsWeb && Platform.isAndroid)
          'client': 'android',
        if (!kIsWeb && Platform.isIOS)
          'client': 'ios',
        if (kIsWeb) 'client': 'web',
      },
    ) as Map?;

    final String? sessionId = res?['sessionId'] as String?;
    final String? urlStr = res?['url'] as String?;
    if (sessionId == null || sessionId.isEmpty || urlStr == null || urlStr.isEmpty) {
      throw StateError('No se pudo generar el enlace de pago de Stripe.');
    }

    final Uri? uri = Uri.tryParse(urlStr);
    if (uri == null) {
      throw StateError('Stripe devolvió una URL inválida.');
    }

    return SubscriptionCheckoutSession(sessionId: sessionId, url: uri);
  }

  /// Confirms the hosted checkout session and synchronises Firestore server-side.
  Future<SubscriptionCheckoutConfirmation> confirmHostedCheckout(
    String sessionId,
  ) async {
    if (sessionId.isEmpty) {
      throw ArgumentError('sessionId requerido para confirmar el pago.');
    }

    final res = await _call(
      'confirmCheckoutSession',
      data: <String, dynamic>{'sessionId': sessionId},
    ) as Map?;

    final String status = (res?['status'] as String? ?? 'pending').toLowerCase();
    final String? message = res?['message'] as String?;
    final String? subscriptionId = res?['subscriptionId'] as String?;

    return SubscriptionCheckoutConfirmation(
      status: status,
      message: message,
      subscriptionId: subscriptionId,
    );
  }

  Future<dynamic> _call(String name, {Map<String, dynamic>? data}) async {
    final auth = FirebaseAuth.instance;

    User? user = auth.currentUser;
    if (user == null) {
      try {
        user = await auth
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        user = null;
      }
    }

    if (user == null) {
      throw FirebaseException(
        plugin: 'cloud_functions',
        code: 'unauthenticated',
        message: 'Inicia sesión para continuar',
      );
    }

    await user.getIdToken(true);

    final callable = _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );

    try {
      final res = await callable.call(data ?? const <String, dynamic>{});
      return res.data;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') {
        await user.getIdToken(true);
        final res = await callable.call(data ?? const <String, dynamic>{});
        return res.data;
      }
      rethrow;
    }
  }
}
