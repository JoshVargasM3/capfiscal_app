import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/subscription_config.dart';

/// Minimal helper around the hosted Stripe Checkout experience.
class SubscriptionPaymentService {
  SubscriptionPaymentService._();

  /// Singleton instance used by the UI layer.
  static final SubscriptionPaymentService instance =
      SubscriptionPaymentService._();

  /// Parses the configured checkout URL.
  Uri? get _checkoutUri {
    final url = SubscriptionConfig.stripeCheckoutUrl.trim();
    if (url.isEmpty) return null;
    return Uri.tryParse(url);
  }

  /// Launches the hosted Stripe Checkout page.
  Future<bool> openHostedCheckout() async {
    final uri = _checkoutUri;
    if (uri == null) {
      throw StateError('No encontramos un enlace de pago válido.');
    }

    final mode = kIsWeb
        ? LaunchMode.platformDefault
        : LaunchMode.externalApplication;

    return launchUrl(
      uri,
      mode: mode,
      webOnlyWindowName: kIsWeb ? '_self' : null,
    );
  }
}
