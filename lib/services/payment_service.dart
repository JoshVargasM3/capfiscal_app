// lib/services/payment_service.dart
import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart'; // 👈 necesario para Firebase.app()
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../config/subscription_config.dart';

/// Resultado del flujo de checkout de suscripción.
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

/// Posibles estados finales tras pedir el pago.
enum SubscriptionPaymentStatus { completed, canceled }

/// Capa fina alrededor de Stripe Payment Sheet impulsada por Cloud Functions.
class SubscriptionPaymentService {
  SubscriptionPaymentService._({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(
              app: Firebase.app(), // 👈 fuerza el MISMO app inicializado
              region: const String.fromEnvironment(
                'FUNCTIONS_REGION',
                defaultValue: 'us-central1',
              ),
            );

  static final SubscriptionPaymentService instance =
      SubscriptionPaymentService._();

  final FirebaseFunctions _functions;
  bool _stripeReady = false;

  /// Configura la SDK de Stripe con la publishable key.
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

    // --- Todos los callables pasan por _call(), que garantiza auth fresh ---
    // 1) Customer
    final cust = await _call('createStripeCustomer') as Map?;
    final String? customerId = cust?['customerId'] as String?;
    if (customerId == null || customerId.isEmpty) {
      throw StateError('No se pudo crear/obtener el Customer en Stripe.');
    }

    // 2) Ephemeral key
    final ekeyRes = await _call(
      'createEphemeralKey',
      data: const {'api_version': '2024-06-20'},
    ) as Map?;
    final String? ephemeralKey = ekeyRes?['secret'] as String?;
    if (ephemeralKey == null || ephemeralKey.isEmpty) {
      throw StateError('No se pudo generar el Ephemeral Key.');
    }

    // 3) Crear suscripción: regresa clientSecret del PaymentIntent
    final sub = await _call(
      'createSubscription',
      data: <String, dynamic>{
        if (priceId != null) 'priceId': priceId,
        if (metadata != null) 'metadata': metadata,
      },
    ) as Map?;

    final String? clientSecret = sub?['clientSecret'] as String?;
    final String? subscriptionId = sub?['subscriptionId'] as String?;
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
    return SubscriptionPaymentResult.completed(subscriptionId);
  }

  /// (Opcional) portal de facturación
  Future<void> openBillingPortal() async {
    final res = await _call('createPortalSession') as Map?;
    final String? url = res?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('No se pudo generar URL del portal de facturación.');
    }
    // Usa url_launcher para abrir:
    // await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // ======================================================================
  // Helper centralizado: GARANTIZA usuario listo + ID token fresco + reintento
  // ======================================================================
  Future<dynamic> _call(String name, {Map<String, dynamic>? data}) async {
    final auth = FirebaseAuth.instance;

    // 1) Espera a que Firebase restituya la sesión si aún no está lista.
    User? user = auth.currentUser;
    if (user == null) {
      try {
        user = await auth
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // seguirá nulo y caerá en el throw de abajo
      }
    }
    if (user == null) {
      throw FirebaseException(
        plugin: 'cloud_functions',
        code: 'unauthenticated',
        message: 'Inicia sesión para continuar',
      );
    }

    // 2) Llamada con posible reintento si el backend responde unauthenticated.
    final callable = _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );

    Future<dynamic> invoke() async {
      final token = await user!.getIdToken(true);
      final payload = <String, dynamic>{
        '__authToken': token,
        if (data != null) ...data,
      };
      final res = await callable.call(payload);
      return res.data;
    }

    try {
      return await invoke();
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') {
        // Fuerza refresh y reintenta 1 vez por si el token expiró en tránsito
        return await invoke();
      }
      rethrow;
    }
  }
}
