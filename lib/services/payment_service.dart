import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
      : _functions = functions ??
            FirebaseFunctions.instanceFor(
              region: const String.fromEnvironment(
                'FUNCTIONS_REGION',
                defaultValue: 'us-central1',
              ),
            );

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

    // iOS: merchant id para Apple Pay (no afecta PaymentSheet)
    if (!kIsWeb && Platform.isIOS) {
      Stripe.merchantIdentifier = const String.fromEnvironment(
        'STRIPE_MERCHANT_ID',
        defaultValue: 'merchant.com.capfiscal',
      );
    }

    await Stripe.instance.applySettings();
    _stripeReady = true;
  }

  /// 1) Customer  2) Ephemeral key  3) Subscription  4) PaymentSheet
  Future<SubscriptionPaymentResult> startSubscriptionCheckout({
    required String uid,
    required String email,
    String? priceId,
    Map<String, dynamic>? metadata,
    bool allowDelayedPaymentMethods = false,
    ThemeMode appearance = ThemeMode.system,
  }) async {
    await ensureInitialized();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('Debes iniciar sesión nuevamente para continuar con el pago.');
    }

    try {
      await user.getIdToken(true);
    } catch (error) {
      throw StateError(
        'No pudimos validar tu sesión con Firebase. Intenta iniciar sesión de nuevo.',
      );
    }

    // 1) Customer
    final HttpsCallableResult<dynamic> cust =
        await _functions.httpsCallable('createStripeCustomer').call();
    final String? customerId = (cust.data as Map)['customerId'] as String?;

    if (customerId == null || customerId.isEmpty) {
      throw StateError('No se pudo crear/obtener el Customer en Stripe.');
    }

    // 2) Ephemeral key (usa la versión de API del backend)
    final Map<String, dynamic> ekeyParams = <String, dynamic>{
      'api_version': '2024-06-20', // <-- fija para tu versión del backend
    };
    final HttpsCallableResult<dynamic> ekeyRes =
        await _functions.httpsCallable('createEphemeralKey').call(ekeyParams);

    final String? ephemeralKey = (ekeyRes.data as Map)['secret'] as String?;

    if (ephemeralKey == null || ephemeralKey.isEmpty) {
      throw StateError('No se pudo generar el Ephemeral Key.');
    }

    // 3) Crear suscripción (regresa clientSecret del PaymentIntent)
    final HttpsCallableResult<dynamic> sub = await _functions
        .httpsCallable('createSubscription')
        .call(<String, dynamic>{
      if (priceId != null) 'priceId': priceId,
      if (metadata != null) 'metadata': metadata,
    });

    final Map<String, dynamic> subData =
        (sub.data as Map).cast<String, dynamic>();
    final String? clientSecret = subData['clientSecret'] as String?;
    final String? subscriptionId = subData['subscriptionId'] as String?;

    if (clientSecret == null || subscriptionId == null) {
      throw StateError(
        'La función createSubscription no devolvió clientSecret/subscriptionId.',
      );
    }

    // 4) Init PaymentSheet
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

    // Present + confirm
    try {
      await Stripe.instance.presentPaymentSheet();
    } on StripeException catch (e, stack) {
      SubscriptionConfig.debugLog(
        'StripeException: ${e.error.localizedMessage ?? e.toString()}',
      );
      if (e.error.code == FailureCode.Canceled) {
        return SubscriptionPaymentResult.canceled();
      }
      Error.throwWithStackTrace(e, stack);
    }

    // El webhook actualizará Firestore cuando Stripe confirme la suscripción.
    return SubscriptionPaymentResult.completed(subscriptionId!);
  }

  /// (Opcional) portal de facturación
  Future<void> openBillingPortal() async {
    final HttpsCallableResult<dynamic> res =
        await _functions.httpsCallable('createPortalSession').call();
    final String? url = (res.data as Map)['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('No se pudo generar URL del portal de facturación.');
    }
    // Usa url_launcher para abrir:
    // await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
