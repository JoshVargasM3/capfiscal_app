import 'package:flutter/widgets.dart';

import '../services/subscription_service.dart';

/// Provides the current [SubscriptionStatus] down the widget tree so screens
/// can react to changes without fetching Firestore again.
class SubscriptionScope extends InheritedWidget {
  const SubscriptionScope({
    required this.status,
    required this.onRefresh,
    required super.child,
    super.key,
  });

  final SubscriptionStatus status;
  final Future<SubscriptionStatus> Function() onRefresh;

  static SubscriptionScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<SubscriptionScope>();
    assert(scope != null, 'SubscriptionScope.of() called outside its context');
    return scope!;
  }

  static SubscriptionScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SubscriptionScope>();
  }

  @override
  bool updateShouldNotify(covariant SubscriptionScope oldWidget) {
    return oldWidget.status != status;
  }
}
