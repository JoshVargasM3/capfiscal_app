import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents the normalized state of a user's paid subscription.
enum SubscriptionState {
  /// The user never configured billing information.
  none,

  /// The subscription is active and grants full access.
  active,

  /// Active due to a grace period (e.g. payment retry).
  grace,

  /// The subscription expired or was cancelled and has no access.
  expired,

  /// The account was explicitly blocked by admins.
  blocked,

  /// Payment received but awaiting manual confirmation.
  pending,
}

/// Parsed subscription information kept in the user document.
class SubscriptionStatus {
  const SubscriptionStatus({
    this.startDate,
    this.endDate,
    this.graceEndsAt,
    this.paymentMethod,
    this.statusOverride,
    this.updatedAt,
    DateTime? checkedAt,
    Map<String, dynamic>? raw,
  })  : checkedAt = checkedAt ?? DateTime.now().toUtc(),
        raw = raw ?? const <String, dynamic>{};

  /// When the subscription started.
  final DateTime? startDate;

  /// When the subscription should end.
  final DateTime? endDate;

  /// Optional grace-period end date configured by admins.
  final DateTime? graceEndsAt;

  /// Stored payment method descriptor (Stripe, transfer, etc.).
  final String? paymentMethod;

  /// Manual override value stored in Firestore (`subscription.status`).
  final String? statusOverride;

  /// Timestamp of the last backend update.
  final DateTime? updatedAt;

  /// Timestamp when this object was materialised.
  final DateTime checkedAt;

  /// Original map for debugging/advanced use.
  final Map<String, dynamic> raw;

  /// Quick factory for empty state (no subscription data).
  factory SubscriptionStatus.empty() => SubscriptionStatus(
        checkedAt: DateTime.now().toUtc(),
      );

  /// Builds the status from a Firestore document snapshot.
  factory SubscriptionStatus.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final Map<String, dynamic> sub =
        (data != null && data['subscription'] is Map<String, dynamic>)
            ? Map<String, dynamic>.from(data['subscription'] as Map)
            : <String, dynamic>{};

    return SubscriptionStatus(
      startDate: _parseDate(sub['startDate']),
      endDate: _parseDate(sub['endDate']),
      graceEndsAt: _parseDate(sub['graceEndsAt'] ?? sub['graceEndDate']),
      paymentMethod: _parseString(sub['paymentMethod']),
      statusOverride: _parseString(sub['status']),
      updatedAt: _parseDate(sub['updatedAt']) ?? _parseDate(data?['updatedAt']),
      raw: sub,
    );
  }

  /// Whether some subscription data exists on the user profile.
  bool get hasData =>
      startDate != null || endDate != null || paymentMethod != null || raw.isNotEmpty;

  /// Normalised override in lowercase.
  String? get _statusLower => statusOverride?.trim().toLowerCase();

  /// Convenience accessor to know if the account has been manually blocked.
  bool get isBlocked => _statusLower == 'blocked';

  /// Whether an admin left the account pending manual approval.
  bool get isPending => _statusLower == 'pending';

  /// Manual switch to grant access without validating dates.
  bool get isManuallyActive =>
      _statusLower == 'manual_active' || _statusLower == 'active';

  /// Current subscription state taking overrides and dates into account.
  SubscriptionState get state {
    if (isBlocked) return SubscriptionState.blocked;
    if (isPending) return SubscriptionState.pending;
    if (isManuallyActive) return SubscriptionState.active;

    if (isActive) return SubscriptionState.active;
    if (isInGrace) return SubscriptionState.grace;
    if (hasData) return SubscriptionState.expired;
    return SubscriptionState.none;
  }

  /// Whether the user can access gated content.
  bool get isAccessGranted =>
      state == SubscriptionState.active || state == SubscriptionState.grace;

  /// The remaining time for active/grace states.
  Duration? get remaining {
    if (state == SubscriptionState.active && endDate != null) {
      final diff = endDate!.difference(DateTime.now().toUtc());
      return diff.isNegative ? Duration.zero : diff;
    }
    if (state == SubscriptionState.grace && graceEndsAt != null) {
      final diff = graceEndsAt!.difference(DateTime.now().toUtc());
      return diff.isNegative ? Duration.zero : diff;
    }
    return null;
  }

  /// Last moment when the subscription grants access.
  DateTime? get accessValidUntil {
    if (state == SubscriptionState.active) return endDate;
    if (state == SubscriptionState.grace) return graceEndsAt ?? endDate;
    return endDate;
  }

  /// Whether the subscription is currently valid.
  bool get isActive =>
      endDate != null && endDate!.isAfter(DateTime.now().toUtc());

  /// Whether the user is still in a configured grace period.
  bool get isInGrace => !isActive &&
      graceEndsAt != null && graceEndsAt!.isAfter(DateTime.now().toUtc());

  /// Friendly helper to render debug information.
  Map<String, Object?> toDebugMap() => <String, Object?>{
        'state': state.toString(),
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'graceEndsAt': graceEndsAt?.toIso8601String(),
        'paymentMethod': paymentMethod,
        'statusOverride': statusOverride,
        'updatedAt': updatedAt?.toIso8601String(),
        'checkedAt': checkedAt.toIso8601String(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SubscriptionStatus) return false;
    return other.startDate == startDate &&
        other.endDate == endDate &&
        other.graceEndsAt == graceEndsAt &&
        other.paymentMethod == paymentMethod &&
        other.statusOverride == statusOverride &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        startDate,
        endDate,
        graceEndsAt,
        paymentMethod,
        statusOverride,
        updatedAt,
      );
}

/// Centralised helper to interact with the subscription metadata stored in
/// Firestore. It wraps read/update helpers so UI widgets do not need to deal
/// with raw maps or timestamp conversions.
class SubscriptionService {
  SubscriptionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Watches the subscription document for a given user.
  Stream<SubscriptionStatus> watchSubscriptionStatus(String uid) {
    final ref = _userDoc(uid);
    return ref.snapshots().map(SubscriptionStatus.fromSnapshot);
  }

  /// Forces a server roundtrip to obtain the latest subscription status.
  Future<SubscriptionStatus> refreshSubscriptionStatus(String uid) async {
    final snapshot =
        await _userDoc(uid).get(const GetOptions(source: Source.server));
    if (!snapshot.exists) {
      throw StateError('El perfil de usuario no existe en la base de datos.');
    }
    return SubscriptionStatus.fromSnapshot(snapshot);
  }

  /// Updates subscription fields. Pass `null` values to clear data.
  Future<void> updateSubscription(
    String uid, {
    DateTime? startDate,
    DateTime? endDate,
    DateTime? graceEndsAt,
    String? paymentMethod,
    String? status,
  }) async {
    final updates = <String, Object?>{};
    if (startDate != null) {
      updates['subscription.startDate'] = Timestamp.fromDate(startDate.toUtc());
    } else {
      updates['subscription.startDate'] = null;
    }
    if (endDate != null) {
      updates['subscription.endDate'] = Timestamp.fromDate(endDate.toUtc());
    } else {
      updates['subscription.endDate'] = null;
    }
    if (graceEndsAt != null) {
      updates['subscription.graceEndsAt'] =
          Timestamp.fromDate(graceEndsAt.toUtc());
    } else {
      updates['subscription.graceEndsAt'] = null;
    }
    updates['subscription.paymentMethod'] = paymentMethod;
    updates['subscription.status'] = status;
    updates['subscription.updatedAt'] = FieldValue.serverTimestamp();
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _userDoc(uid).set(updates, SetOptions(merge: true));
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  if (value is String && value.isNotEmpty) {
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : parsed.toUtc();
  }
  return null;
}

String? _parseString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}
