import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../config/subscription_config.dart';

/// Result of a subscription checkout flow.
class SubscriptionPaymentResult {
  const SubscriptionPaymentResult._(this.status, {this.subscriptionId});

  final SubscriptionPaymentStatus status;
  final String? subscriptionId;

  factory SubscriptionPaymentResult.completed(String subscriptionId) =>
      SubscriptionPaymentResult._(
        SubscriptionPaymentStatus.completed,
        subscriptionId: subscriptionId,
      );

  factory SubscriptionPaymentResult.canceled() =>
      const SubscriptionPaymentResult._(SubscriptionPaymentStatus.canceled);
}

/// Possible final states after requesting payment from the user.
enum SubscriptionPaymentStatus { completed, canceled }

/// Thin client around Stripe Payment Sheet driven by Cloud Functions.
class SubscriptionPaymentService {
  SubscriptionPaymentService._({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  static final SubscriptionPaymentService instance =
      SubscriptionPaymentService._();

  final FirebaseFunctions _functions;
  bool _stripeReady = false;

  /// Ensures the Stripe SDK has been configured with the publishable key.
  Future<void> ensureInitialized() async {
    if (_stripeReady) return;
    if (!SubscriptionConfig.hasStripeConfiguration) {
      throw StateError(
        'Configura STRIPE_PUBLISHABLE_KEY y STRIPE_PRICE_ID con --dart-define.',
      );
    }

    Stripe.publishableKey = SubscriptionConfig.stripePublishableKey;
    if (!kIsWeb && Platform.isIOS) {
      Stripe.merchantIdentifier = const String.fromEnvironment(
        'STRIPE_MERCHANT_ID',
        defaultValue: 'merchant.com.capfiscal',
      );
    }
    await Stripe.instance.applySettings();
    _stripeReady = true;
  }

  /// Launches the payment flow using data provided by a backend Cloud Function.
  ///
  /// The backend function must create a Stripe subscription for the provided
  /// [priceId] and return the client secret + ephemeral key to drive the
  /// PaymentSheet locally.
  Future<SubscriptionPaymentResult> startSubscriptionCheckout({
    required String uid,
    required String email,
    String? priceId,
    Map<String, dynamic>? metadata,
    bool allowDelayedPaymentMethods = true,
    ThemeMode appearance = ThemeMode.dark,
  }) async {
    await ensureInitialized();

    final callable =
        _functions.httpsCallable('createStripeSubscriptionIntent');
    final response = await callable.call<Map<String, dynamic>>({
      'uid': uid,
      'email': email,
      'priceId': priceId ?? SubscriptionConfig.stripePriceId,
      'metadata': metadata ?? const <String, dynamic>{},
    });

    final data = response.data;
    final clientSecret = data['paymentIntentClientSecret'] as String?;
    final customerId = data['customerId'] as String?;
    final ephemeralKey = data['customerEphemeralKeySecret'] as String?;
    final subscriptionId = data['subscriptionId'] as String?;

    if (clientSecret == null ||
        customerId == null ||
        ephemeralKey == null ||
        subscriptionId == null) {
      throw StateError(
        'La función createStripeSubscriptionIntent no devolvió datos válidos.',
      );
    }

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        style: appearance,
        merchantDisplayName: SubscriptionConfig.merchantDisplayName,
        customerId: customerId,
        customerEphemeralKeySecret: ephemeralKey,
        paymentIntentClientSecret: clientSecret,
        allowsDelayedPaymentMethods: allowDelayedPaymentMethods,
      ),
    );

    try {
      await Stripe.instance.presentPaymentSheet();
    } on StripeException catch (e, stack) {
      SubscriptionConfig.debugLog('StripeException: ${e.error.localizedMessage}');
      if (e.error.code == FailureCode.Canceled) {
        return SubscriptionPaymentResult.canceled();
      }
      Error.throwWithStackTrace(e, stack);
    }

    try {
      await _functions.httpsCallable('finalizeStripeSubscription').call({
        'uid': uid,
        'subscriptionId': subscriptionId,
      });
    } catch (e, stack) {
      SubscriptionConfig.debugLog(
          'finalizeStripeSubscription fallback failed: $e');
      Error.throwWithStackTrace(e, stack);
    }

    return SubscriptionPaymentResult.completed(subscriptionId);
  }
}
