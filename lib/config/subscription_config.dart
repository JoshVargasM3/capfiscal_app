import 'package:flutter/foundation.dart';

/// Central configuration for paid subscription flows.
///
/// The values are resolved through `--dart-define` so secrets never end up in
/// source control. In debug/profile builds fallback values can be provided to
/// make local testing easier.
class SubscriptionConfig {
  const SubscriptionConfig._();

  /// Stripe publishable key used by the mobile SDK (legacy PaymentSheet).
  static const String stripePublishableKey =
      String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');

  /// Default Stripe price to use when creating a subscription checkout.
  static const String stripePriceId =
      String.fromEnvironment('STRIPE_PRICE_ID');

  /// Optional merchant name shown on the payment sheet.
  static const String merchantDisplayName =
      String.fromEnvironment('SUBSCRIPTION_MERCHANT_NAME',
          defaultValue: 'CAPFISCAL');

  /// URL where Stripe redirects the user after a successful payment.
  static const String stripeCheckoutSuccessUrl =
      String.fromEnvironment('STRIPE_CHECKOUT_SUCCESS_URL');

  /// URL where Stripe redirects the user after cancelling the payment.
  static const String stripeCheckoutCancelUrl =
      String.fromEnvironment('STRIPE_CHECKOUT_CANCEL_URL');

  /// Whether the Stripe keys appear to be configured.
  static bool get hasStripeConfiguration =>
      stripePublishableKey.isNotEmpty && stripePriceId.isNotEmpty;

  /// Whether the checkout return URLs are configured.
  static bool get hasCheckoutReturnUrls =>
      stripeCheckoutSuccessUrl.isNotEmpty && stripeCheckoutCancelUrl.isNotEmpty;

  /// Whether the new Checkout flow has all the required configuration.
  static bool get hasCheckoutConfiguration =>
      stripePriceId.isNotEmpty && hasCheckoutReturnUrls;

  /// Helper log to keep noisy prints behind debug mode.
  static void debugLog(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SubscriptionConfig] $message');
    }
  }
}
