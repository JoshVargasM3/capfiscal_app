import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

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
  SubscriptionStatus({
    this.startDate,
    this.endDate,
    this.graceEndsAt,
    this.paymentMethod,
    this.statusOverride,
    this.updatedAt,
    this.cancelAtPeriodEnd = false,
    this.cancelsAt,
    this.stripeSubscriptionId,
    this.stripeCustomerId,
    this.paymentMethods = const <StoredPaymentMethod>[],
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

  /// Whether a cancellation at period end is scheduled.
  final bool cancelAtPeriodEnd;

  /// When the access should be revoked if cancellation is scheduled.
  final DateTime? cancelsAt;

  /// Stripe subscription identifier (if backend stores it).
  final String? stripeSubscriptionId;

  /// Stripe customer identifier (if backend stores it).
  final String? stripeCustomerId;

  /// Known payment methods retrieved from Firestore.
  final List<StoredPaymentMethod> paymentMethods;

  /// Manual override value stored in Firestore (`subscription.status`).
  final String? statusOverride;

  /// Timestamp of the last backend update.
  final DateTime? updatedAt;

  /// Timestamp when this object was materialised.
  final DateTime checkedAt;

  /// Original map for debugging/advanced use.
  final Map<String, dynamic> raw;

  /// Quick factory for empty state (no subscription data).
  factory SubscriptionStatus.empty() =>
      SubscriptionStatus(checkedAt: DateTime.now().toUtc());

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
      cancelAtPeriodEnd: (sub['cancelAtPeriodEnd'] as bool?) ?? false,
      cancelsAt: _parseDate(sub['cancelsAt'] ?? sub['cancelScheduledAt']),
      stripeSubscriptionId: _parseString(sub['stripeSubscriptionId']),
      stripeCustomerId: _parseString(sub['stripeCustomerId']),
      paymentMethods:
          _parsePaymentMethods(sub['paymentMethods'] as List<dynamic>?),
      raw: sub,
    );
  }

  /// Builds a status from an already loaded user document map.
  factory SubscriptionStatus.fromUserData(Map<String, dynamic> data) {
    final sub = (data['subscription'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    return SubscriptionStatus(
      startDate: _parseDate(sub['startDate']),
      endDate: _parseDate(sub['endDate']),
      graceEndsAt: _parseDate(sub['graceEndsAt'] ?? sub['graceEndDate']),
      paymentMethod: _parseString(sub['paymentMethod']),
      statusOverride: _parseString(sub['status']),
      updatedAt: _parseDate(sub['updatedAt']) ?? _parseDate(data['updatedAt']),
      cancelAtPeriodEnd: (sub['cancelAtPeriodEnd'] as bool?) ?? false,
      cancelsAt: _parseDate(sub['cancelsAt'] ?? sub['cancelScheduledAt']),
      stripeSubscriptionId: _parseString(sub['stripeSubscriptionId']),
      stripeCustomerId: _parseString(sub['stripeCustomerId']),
      paymentMethods:
          _parsePaymentMethods(sub['paymentMethods'] as List<dynamic>?),
      raw: sub,
    );
  }

  /// Whether some subscription data exists on the user profile.
  bool get hasData =>
      startDate != null ||
      endDate != null ||
      graceEndsAt != null ||
      paymentMethod != null ||
      statusOverride != null;

  /// Normalised override in lowercase.
  String? get _statusLower => statusOverride?.trim().toLowerCase();

  /// Convenience accessor to know if the account has been manually blocked.
  bool get isBlocked => _statusLower == 'blocked';

  /// Whether an admin left the account pending manual approval.
  bool get isPending => _statusLower == 'pending';

  /// Manual switch to grant access without validating dates.
  bool get isManuallyActive =>
      _statusLower == 'manual_active' || _statusLower == 'active';

  /// Whether there is an upcoming cancellation that should be shown to the user.
  bool get isCancellationScheduled =>
      cancelAtPeriodEnd ||
      (cancelsAt != null && cancelsAt!.isAfter(DateTime.now().toUtc()));

  /// Convenience accessor for the default payment method object.
  StoredPaymentMethod? get primaryPaymentMethod {
    if (paymentMethods.isEmpty) return null;
    final preferred = paymentMethods
        .firstWhere((m) => m.isDefault, orElse: () => paymentMethods.first);
    return preferred;
  }

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

  /// Human readable moment when the cancellation will take effect.
  DateTime? get cancellationEffectiveDate =>
      cancelsAt ?? accessValidUntil;

  /// Whether the subscription is currently valid.
  bool get isActive =>
      endDate != null && endDate!.isAfter(DateTime.now().toUtc());

  /// Whether the user is still in a configured grace period.
  bool get isInGrace =>
      !isActive &&
      graceEndsAt != null &&
      graceEndsAt!.isAfter(DateTime.now().toUtc());

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
        other.cancelAtPeriodEnd == cancelAtPeriodEnd &&
        other.cancelsAt == cancelsAt &&
        other.stripeSubscriptionId == stripeSubscriptionId &&
        other.stripeCustomerId == stripeCustomerId &&
        _listEquals(other.paymentMethods, paymentMethods) &&
        other.statusOverride == statusOverride &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        startDate,
        endDate,
        graceEndsAt,
        paymentMethod,
        cancelAtPeriodEnd,
        cancelsAt,
        stripeSubscriptionId,
        stripeCustomerId,
        Object.hashAll(paymentMethods),
        statusOverride,
        updatedAt,
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class StoredPaymentMethod {
  const StoredPaymentMethod({
    required this.id,
    required this.label,
    required this.brand,
    required this.last4,
    required this.isDefault,
    this.createdAt,
  });

  final String id;
  final String label;
  final String brand;
  final String last4;
  final bool isDefault;
  final DateTime? createdAt;

  factory StoredPaymentMethod.fromMap(Map<String, dynamic> data) {
    return StoredPaymentMethod(
      id: _parseString(data['id']) ?? _parseString(data['label']) ?? '',
      label: _parseString(data['label']) ?? 'Método de pago',
      brand: _parseString(data['brand']) ?? 'tarjeta',
      last4: _parseString(data['last4']) ?? '----',
      isDefault: (data['isDefault'] as bool?) ?? false,
      createdAt: _parseDate(data['createdAt']) ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'label': label,
        'brand': brand,
        'last4': last4,
        'isDefault': isDefault,
        'createdAt': createdAt?.toIso8601String(),
      };

  StoredPaymentMethod copyWith({bool? isDefault}) => StoredPaymentMethod(
        id: id,
        label: label,
        brand: brand,
        last4: last4,
        isDefault: isDefault ?? this.isDefault,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StoredPaymentMethod) return false;
    return other.id == id &&
        other.label == label &&
        other.brand == brand &&
        other.last4 == last4 &&
        other.isDefault == isDefault;
  }

  @override
  int get hashCode => Object.hash(id, label, brand, last4, isDefault);
}

/// Centralised helper to interact with the subscription metadata stored in
/// Firestore. It wraps read/update helpers so UI widgets do not need to deal
/// with raw maps or timestamp conversions.
class SubscriptionService {
  SubscriptionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// ====== NUEVO (opción B): asegurar users/{uid} sin campos protegidos ======
  ///
  /// Llama esto apenas tengas al usuario autenticado (p. ej. en AuthGate).
  /// No escribe `subscription`, `status` ni `updatedAt` (cumple tus reglas).
  static Future<void> ensureUserDoc(User user) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'email': user.email,
        'displayName': user.displayName ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

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

  /// ====== NUEVO (opción B): parche local tras PaymentSheet exitoso ======
  ///
  /// Escribe únicamente `subscription.*` y `updatedAt` (merge),
  /// cumpliendo tus reglas de seguridad para el "client patch".
  Future<void> applyLocalPaymentSuccess(
    String uid, {
    String paymentMethod = 'Stripe PaymentSheet',
    int durationDays = 30,
    DateTime? startAtUtc,
  }) async {
    final start = (startAtUtc ?? DateTime.now().toUtc());
    final end = start.add(Duration(days: durationDays));

    await updateSubscription(
      uid,
      startDate: start,
      endDate: end,
      paymentMethod: paymentMethod,
      status: 'active', // valores permitidos por tus reglas
      cancelAtPeriodEnd: false,
    );
  }

  /// También puedes marcar 'pending' si el cargo queda en revisión.
  Future<void> applyLocalPaymentPending(
    String uid, {
    String paymentMethod = 'Stripe PaymentSheet',
    int durationDays = 30,
    DateTime? startAtUtc,
  }) async {
    final start = (startAtUtc ?? DateTime.now().toUtc());
    final end = start.add(Duration(days: durationDays));

    await updateSubscription(
      uid,
      startDate: start,
      endDate: end,
      paymentMethod: paymentMethod,
      status: 'pending',
      cancelAtPeriodEnd: false,
    );
  }

  /// Updates subscription fields. Pass `null` values to CLEAR fields (delete).
  Future<void> updateSubscription(
    String uid, {
    DateTime? startDate,
    DateTime? endDate,
    DateTime? graceEndsAt,
    String? paymentMethod,
    String? status,
    bool? cancelAtPeriodEnd,
    DateTime? cancelsAt,
    List<StoredPaymentMethod>? paymentMethods,
    String? stripeSubscriptionId,
    String? stripeCustomerId,
  }) async {
    final updates = <String, Object?>{};

    if (startDate != null) {
      updates['subscription.startDate'] = Timestamp.fromDate(startDate.toUtc());
    } else {
      updates['subscription.startDate'] = FieldValue.delete();
    }

    if (endDate != null) {
      updates['subscription.endDate'] = Timestamp.fromDate(endDate.toUtc());
    } else {
      updates['subscription.endDate'] = FieldValue.delete();
    }

    if (graceEndsAt != null) {
      updates['subscription.graceEndsAt'] =
          Timestamp.fromDate(graceEndsAt.toUtc());
    } else {
      updates['subscription.graceEndsAt'] = FieldValue.delete();
    }

    if (paymentMethod != null) {
      updates['subscription.paymentMethod'] = paymentMethod;
    } else {
      updates['subscription.paymentMethod'] = FieldValue.delete();
    }

    if (status != null) {
      updates['subscription.status'] = status;
    } else {
      updates['subscription.status'] = FieldValue.delete();
    }

    if (cancelAtPeriodEnd != null) {
      updates['subscription.cancelAtPeriodEnd'] = cancelAtPeriodEnd;
    }

    if (cancelsAt != null) {
      updates['subscription.cancelsAt'] =
          Timestamp.fromDate(cancelsAt.toUtc());
    } else if (cancelAtPeriodEnd == false) {
      updates['subscription.cancelsAt'] = FieldValue.delete();
    }

    if (paymentMethods != null) {
      updates['subscription.paymentMethods'] =
          paymentMethods.map((m) => m.toMap()).toList();
    }

    if (stripeSubscriptionId != null) {
      updates['subscription.stripeSubscriptionId'] =
          stripeSubscriptionId.isEmpty
              ? FieldValue.delete()
              : stripeSubscriptionId;
    }

    if (stripeCustomerId != null) {
      updates['subscription.stripeCustomerId'] = stripeCustomerId.isEmpty
          ? FieldValue.delete()
          : stripeCustomerId;
    }

    // Estos dos timestamps cumplen tu regla de "solo subscription y/o updatedAt".
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
    return parsed?.toUtc();
  }
  return null;
}

String? _parseString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

List<StoredPaymentMethod> _parsePaymentMethods(List<dynamic>? raw) {
  if (raw == null || raw.isEmpty) return const <StoredPaymentMethod>[];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(StoredPaymentMethod.fromMap)
      .toList();
}
