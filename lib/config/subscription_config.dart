// lib/config/subscription_config.dart
import 'package:flutter/foundation.dart';

/// Config central para los flujos de suscripción de pago.
class SubscriptionConfig {
  const SubscriptionConfig._();

  /// Intenta leer STRIPE_PUBLISHABLE_KEY desde --dart-define.
  /// Si está vacío, usamos un fallback de prueba (solo para desarrollo).
  ///
  /// >>> RECUERDA: en producción NO dejes llaves en el repo. Usa --dart-define.
  static const String _envPublishable =
      String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');

  // Clave pública de prueba (fallback). Reemplázala o déjala vacía si lo prefieres.
  // Valor proporcionado por el usuario:
  static const String _devFallbackPublishable =
      'pk_test_51SHsjBCWjByjrRQ6KqxiY0jov0pGv3f2cKWy03CMSdrKitwVFki6ytGRVpWpI1zKM3siN6qKsqAbFkwdSvzcteOR00ni6F5Ipg';

  /// Clave publicable resultante (lee env, si no existe usa fallback).
  static String get stripePublishableKey =>
      _envPublishable.isNotEmpty ? _envPublishable : _devFallbackPublishable;

  /// (Opcional) Price de Stripe si usas Checkout/Subscriptions.
  static const String stripePriceId = String.fromEnvironment('STRIPE_PRICE_ID');

  /// Nombre que ve el usuario en la hoja de pago.
  static const String merchantDisplayName = String.fromEnvironment(
      'SUBSCRIPTION_MERCHANT_NAME',
      defaultValue: 'CAPFISCAL');

  /// URL de Hosted Checkout (para flujo web).
  static const String stripeCheckoutUrl = String.fromEnvironment(
    'STRIPE_CHECKOUT_URL',
    // Puedes cambiar esta URL por tu enlace real:
    defaultValue: 'https://buy.stripe.com/test_9B6cN425Hgck9Zm7n94Vy00',
  );

  /// ¿Tenemos config suficiente para PaymentSheet (móvil)?
  static bool get hasPaymentSheetConfiguration =>
      stripePublishableKey.isNotEmpty;

  /// ¿Tenemos config suficiente para Checkout Link (web)?
  static bool get hasCheckoutConfiguration => stripeCheckoutUrl.isNotEmpty;

  /// (Histórico) ¿ambas llaves para flujos antiguos?
  static bool get hasStripeConfiguration =>
      stripePublishableKey.isNotEmpty && stripePriceId.isNotEmpty;

  /// Log en debug.
  static void debugLog(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SubscriptionConfig] $message');
    }
  }
}
