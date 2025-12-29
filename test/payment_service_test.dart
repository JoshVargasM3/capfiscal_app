import 'package:flutter_test/flutter_test.dart';

import 'package:capfiscal_app/services/payment_service.dart';

void main() {
  test('SubscriptionCheckoutConfirmation flags active and pending states', () {
    const active = SubscriptionCheckoutConfirmation(status: 'active');
    const pending = SubscriptionCheckoutConfirmation(status: 'pending');

    expect(active.isActive, isTrue);
    expect(active.isPending, isFalse);

    expect(pending.isActive, isFalse);
    expect(pending.isPending, isTrue);
  });
}
