// lib/config/subscription_config.dart
import 'package:flutter/foundation.dart';

/// Config central para los flujos de suscripción de pago.
class SubscriptionConfig {
  const SubscriptionConfig._();

  /// Clave publicable (Stripe) inyectada por `--dart-define`.
  static const String stripePublishableKey =
      String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');

  /// (Opcional) Price de Stripe si usas Checkout/Subscriptions.
  static const String stripePriceId = String.fromEnvironment('STRIPE_PRICE_ID');

  /// Nombre que ve el usuario en la hoja de pago.
  static const String merchantDisplayName = String.fromEnvironment(
    'SUBSCRIPTION_MERCHANT_NAME',
    defaultValue: 'CAPFISCAL',
  );

  /// URL de Hosted Checkout (para flujo web).
  static const String stripeCheckoutUrl =
      String.fromEnvironment('STRIPE_CHECKOUT_URL');

  /// URL HTTP de Cloud Function para crear PaymentIntent (mobile).
  static const String stripePaymentIntentUrl =
      String.fromEnvironment('STRIPE_PAYMENT_INTENT_URL');

  /// Package name Android para el enlace de administrar suscripción.
  static const String androidPackageName =
      String.fromEnvironment('ANDROID_PACKAGE_NAME');

  /// Bundle id iOS si necesitas formar links específicos.
  static const String iosBundleId = String.fromEnvironment('IOS_BUNDLE_ID');

  /// ¿Tenemos config suficiente para PaymentSheet (móvil)?
  static bool get hasPaymentSheetConfiguration =>
      stripePublishableKey.isNotEmpty && stripePaymentIntentUrl.isNotEmpty;

  /// ¿Tenemos config suficiente para Checkout Link (web)?
  static bool get hasCheckoutConfiguration => stripeCheckoutUrl.isNotEmpty;

  /// ¿Tenemos link para administrar suscripción en Play Store?
  static String get playStoreManageSubscriptionUrl =>
      androidPackageName.isNotEmpty
          ? 'https://play.google.com/store/account/subscriptions?package=$androidPackageName'
          : '';

  /// URL universal para administrar suscripción en iOS.
  static const String iosManageSubscriptionUrl =
      'https://apps.apple.com/account/subscriptions';

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
