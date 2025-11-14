import 'package:capfiscal_app/services/subscription_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubscriptionStatus', () {
    test('detecta estado activo y acceso permitido', () {
      final now = DateTime.now().toUtc();
      final status = SubscriptionStatus(
        startDate: now.subtract(const Duration(days: 5)),
        endDate: now.add(const Duration(days: 10)),
      );

      expect(status.state, SubscriptionState.active);
      expect(status.isAccessGranted, isTrue);
      expect(status.remaining, isNotNull);
    });

    test('respeta periodo de gracia cuando la fecha terminó', () {
      final now = DateTime.now().toUtc();
      final status = SubscriptionStatus(
        endDate: now.subtract(const Duration(days: 1)),
        graceEndsAt: now.add(const Duration(days: 3)),
      );

      expect(status.state, SubscriptionState.grace);
      expect(status.isInGrace, isTrue);
      expect(status.accessValidUntil, isNotNull);
    });

    test('marca cancelación programada y fecha efectiva', () {
      final now = DateTime.now().toUtc();
      final cancels = now.add(const Duration(days: 7));
      final status = SubscriptionStatus(
        endDate: now.add(const Duration(days: 5)),
        cancelAtPeriodEnd: true,
        cancelsAt: cancels,
      );

      expect(status.isCancellationScheduled, isTrue);
      expect(status.cancellationEffectiveDate, cancels);
    });

    test('elige el método de pago principal correcto', () {
      final status = SubscriptionStatus(
        paymentMethods: [
          StoredPaymentMethod(
            id: 'pm_alt',
            label: 'Alterno',
            brand: 'visa',
            last4: '1111',
            isDefault: false,
          ),
          StoredPaymentMethod(
            id: 'pm_main',
            label: 'Principal',
            brand: 'mastercard',
            last4: '2222',
            isDefault: true,
          ),
        ],
      );

      expect(status.primaryPaymentMethod?.id, 'pm_main');
      expect(status.paymentMethods.length, 2);
    });

    test('fromUserData parsea campos nuevos', () {
      final now = DateTime.now();
      final data = {
        'subscription': {
          'startDate': now,
          'endDate': now.add(const Duration(days: 30)),
          'cancelAtPeriodEnd': true,
          'cancelsAt': now.add(const Duration(days: 35)),
          'paymentMethods': [
            {
              'id': 'pm_test',
              'label': 'Alias',
              'brand': 'visa',
              'last4': '9999',
              'isDefault': true,
            }
          ],
        }
      };

      final status = SubscriptionStatus.fromUserData(data);
      expect(status.cancelAtPeriodEnd, isTrue);
      expect(status.paymentMethods, isNotEmpty);
      expect(status.primaryPaymentMethod?.label, 'Alias');
    });
  });
}
