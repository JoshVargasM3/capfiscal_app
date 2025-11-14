import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Confirmation payload returned after Stripe validates a session.
class SubscriptionCheckoutConfirmation {
  const SubscriptionCheckoutConfirmation({
    required this.status,
    this.message,
    this.subscriptionId,
    this.cancelsAt,
  });

  final String status;
  final String? message;
  final String? subscriptionId;
  final DateTime? cancelsAt;

  bool get isActive =>
      status == 'active' || status == 'manual_active' || status == 'grace';
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

  /// Activates the subscription in Firestore after the hosted checkout flow finishes.
  Future<SubscriptionCheckoutConfirmation> activateHostedCheckout({
    int durationDays = 30,
    String? paymentMethod,
    String? statusOverride,
  }) async {
    final res = await _call(
      'activateSubscriptionAccess',
      data: <String, dynamic>{
        'durationDays': durationDays,
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
        if (statusOverride != null) 'status': statusOverride,
        if (kIsWeb) 'client': 'web',
      },
    ) as Map?;

    final String status = (res?['status'] as String? ?? 'pending').toLowerCase();
    final String? message = res?['message'] as String?;
    final String? subscriptionId = res?['subscriptionId'] as String?;

    return SubscriptionCheckoutConfirmation(
      status: status,
      message: message,
      subscriptionId: subscriptionId,
      cancelsAt: _parseDate(res?['cancelsAt']),
    );
  }

  /// Marks the subscription to cancel at the end of the current period.
  Future<SubscriptionCheckoutConfirmation> scheduleCancellation(
      {String? subscriptionId}) async {
    final res = await _call(
      'scheduleSubscriptionCancellation',
      data: {
        if (subscriptionId != null) 'subscriptionId': subscriptionId,
      },
    ) as Map?;
    final status = (res?['status'] as String? ?? 'pending').toLowerCase();
    return SubscriptionCheckoutConfirmation(
      status: status,
      message: res?['message'] as String?,
      subscriptionId: res?['subscriptionId'] as String? ?? subscriptionId,
      cancelsAt: _parseDate(res?['cancelsAt']),
    );
  }

  /// Re-enables recurring billing if the user changed their mind.
  Future<SubscriptionCheckoutConfirmation> resumeCancellation() async {
    final res = await _call('resumeSubscriptionCancellation') as Map?;
    final status = (res?['status'] as String? ?? 'active').toLowerCase();
    return SubscriptionCheckoutConfirmation(
      status: status,
      message: res?['message'] as String?,
      subscriptionId: res?['subscriptionId'] as String?,
      cancelsAt: _parseDate(res?['cancelsAt']),
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

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}
