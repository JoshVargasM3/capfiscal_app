import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capfiscal_app/services/subscription_service.dart';

void main() {
  test('SubscriptionStatus.fromUserData detects active subscription', () {
    final now = DateTime.utc(2024, 1, 1);
    final data = {
      'subscription': {
        'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
        'endDate': Timestamp.fromDate(now.add(const Duration(days: 29))),
        'status': 'active',
      },
      'updatedAt': Timestamp.fromDate(now),
    };

    final status = SubscriptionStatus.fromUserData(data);

    expect(status.state, SubscriptionState.active);
    expect(status.isAccessGranted, isTrue);
    expect(status.remaining, isNotNull);
  });

  test('SubscriptionStatus handles pending override', () {
    final data = {
      'subscription': {
        'status': 'pending',
      },
    };

    final status = SubscriptionStatus.fromUserData(data);

    expect(status.state, SubscriptionState.pending);
    expect(status.isAccessGranted, isFalse);
  });
}
