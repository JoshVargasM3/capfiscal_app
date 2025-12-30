// lib/services/subscription_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

/// Represents the normalized state of a user's paid subscription.
enum SubscriptionState {
  none,
  active,
  grace,
  expired,
  blocked,
  pending,
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
      createdAt: _parseDate(data['createdAt']),
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

  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? graceEndsAt;

  final String? paymentMethod;

  final bool cancelAtPeriodEnd;
  final DateTime? cancelsAt;

  final String? stripeSubscriptionId;
  final String? stripeCustomerId;

  final List<StoredPaymentMethod> paymentMethods;

  /// Manual override value stored in Firestore (`subscription.status`).
  final String? statusOverride;

  /// Timestamp of the last backend update.
  final DateTime? updatedAt;

  final DateTime checkedAt;
  final Map<String, dynamic> raw;

  factory SubscriptionStatus.empty() =>
      SubscriptionStatus(checkedAt: DateTime.now().toUtc());

  factory SubscriptionStatus.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return _fromMap(data);
  }

  factory SubscriptionStatus.fromUserData(Map<String, dynamic> data) {
    return _fromMap(data);
  }

  static SubscriptionStatus _fromMap(Map<String, dynamic> data) {
    final Map<String, dynamic> sub = (data['subscription'] is Map)
        ? Map<String, dynamic>.from(data['subscription'] as Map)
        : <String, dynamic>{};

    // ✅ PRIORIDAD: SIEMPRE usa el mapa real `subscription.{field}`.
    // Fallback solo si no existe (compat con campos legacy top-level "subscription.endDate", etc.)
    final startDate = _parseDate(sub['startDate']) ??
        _parseDate(data['subscription.startDate']);
    final endDate =
        _parseDate(sub['endDate']) ?? _parseDate(data['subscription.endDate']);

    final graceEndsAt = _parseDate(sub['graceEndsAt'] ?? sub['graceEndDate']) ??
        _parseDate(data['subscription.graceEndsAt'] ??
            data['subscription.graceEndDate']);

    final updatedAt = _parseDate(sub['updatedAt']) ??
        _parseDate(data['subscription.updatedAt']) ??
        _parseDate(data['updatedAt']);

    final paymentMethod = _parseString(sub['paymentMethod']) ??
        _parseString(data['subscription.paymentMethod']);

    final statusOverride = _parseString(sub['status']) ??
        _parseString(data['subscription.status']);

    final cancelAtPeriodEnd = (sub['cancelAtPeriodEnd'] as bool?) ??
        (data['subscription.cancelAtPeriodEnd'] as bool?) ??
        false;

    final cancelsAt =
        _parseDate(sub['cancelsAt'] ?? sub['cancelScheduledAt']) ??
            _parseDate(data['subscription.cancelsAt'] ??
                data['subscription.cancelScheduledAt']);

    final stripeSubscriptionId = _parseString(sub['stripeSubscriptionId']) ??
        _parseString(data['subscription.stripeSubscriptionId']);

    final stripeCustomerId = _parseString(sub['stripeCustomerId']) ??
        _parseString(data['subscription.stripeCustomerId']);

    final paymentMethods = () {
      final parsed = _parsePaymentMethods(sub['paymentMethods']);
      if (parsed.isNotEmpty) return parsed;
      return _parsePaymentMethods(data['subscription.paymentMethods']);
    }();

    return SubscriptionStatus(
      startDate: startDate,
      endDate: endDate,
      graceEndsAt: graceEndsAt,
      paymentMethod: paymentMethod,
      statusOverride: statusOverride,
      updatedAt: updatedAt,
      cancelAtPeriodEnd: cancelAtPeriodEnd,
      cancelsAt: cancelsAt,
      stripeSubscriptionId: stripeSubscriptionId,
      stripeCustomerId: stripeCustomerId,
      paymentMethods: paymentMethods,
      raw: sub,
    );
  }

  bool get hasData =>
      startDate != null ||
      endDate != null ||
      graceEndsAt != null ||
      paymentMethod != null ||
      statusOverride != null ||
      paymentMethods.isNotEmpty;

  String? get _statusLower => statusOverride?.trim().toLowerCase();

  bool get isBlocked => _statusLower == 'blocked';
  bool get isPending => _statusLower == 'pending';

  /// ✅ Override real SOLO para soporte. (No uses "active" como override, porque ignoras endDate)
  bool get isManuallyActive => _statusLower == 'manual_active';

  bool get isActive =>
      endDate != null && endDate!.isAfter(DateTime.now().toUtc());

  bool get isInGrace =>
      !isActive &&
      graceEndsAt != null &&
      graceEndsAt!.isAfter(DateTime.now().toUtc());

  SubscriptionState get state {
    if (isBlocked) return SubscriptionState.blocked;
    if (isPending) return SubscriptionState.pending;

    if (isManuallyActive) return SubscriptionState.active;

    if (isActive) return SubscriptionState.active;
    if (isInGrace) return SubscriptionState.grace;

    if (hasData) return SubscriptionState.expired;
    return SubscriptionState.none;
  }

  bool get isAccessGranted =>
      state == SubscriptionState.active || state == SubscriptionState.grace;

  Duration? get remaining {
    final now = DateTime.now().toUtc();
    if (state == SubscriptionState.active && endDate != null) {
      final diff = endDate!.difference(now);
      return diff.isNegative ? Duration.zero : diff;
    }
    if (state == SubscriptionState.grace && graceEndsAt != null) {
      final diff = graceEndsAt!.difference(now);
      return diff.isNegative ? Duration.zero : diff;
    }
    return null;
  }
}

/// Centralised helper to interact with subscription metadata stored in Firestore.
class SubscriptionService {
  SubscriptionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static Future<void> ensureUserDoc(User user) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'email': user.email ?? '',
        'name': user.displayName ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Stream<SubscriptionStatus> watchSubscriptionStatus(String uid) {
    return _userDoc(uid).snapshots().map(SubscriptionStatus.fromSnapshot);
  }

  Future<SubscriptionStatus> refreshSubscriptionStatus(String uid) async {
    final snapshot =
        await _userDoc(uid).get(const GetOptions(source: Source.server));
    if (!snapshot.exists) {
      throw StateError('El perfil de usuario no existe en la base de datos.');
    }
    return SubscriptionStatus.fromSnapshot(snapshot);
  }

  /// Patch local tras pago exitoso.
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
      status: 'active',
      cancelAtPeriodEnd: false,
      touchUpdatedAt: true,
    );
  }

  /// Patch local tras pago pendiente.
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
      touchUpdatedAt: true,
    );
  }

  /// Updates ONLY provided fields (nested under subscription.*)
  /// + Limpia campos legacy top-level cuyo nombre literal incluye punto.
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
    bool clearStartDate = false,
    bool clearEndDate = false,
    bool clearGraceEndsAt = false,
    bool clearPaymentMethod = false,
    bool clearStatus = false,
    bool clearCancelsAt = false,
    bool clearStripeSubscriptionId = false,
    bool clearStripeCustomerId = false,
    bool touchUpdatedAt = true,
  }) async {
    final ref = _userDoc(uid);

    // ✅ update() permite keys String (paths) y FieldPath (para borrar legacy).
    final updates = <Object, Object?>{};

    if (startDate != null) {
      updates['subscription.startDate'] = Timestamp.fromDate(startDate.toUtc());
    } else if (clearStartDate) {
      updates['subscription.startDate'] = FieldValue.delete();
    }

    if (endDate != null) {
      updates['subscription.endDate'] = Timestamp.fromDate(endDate.toUtc());
    } else if (clearEndDate) {
      updates['subscription.endDate'] = FieldValue.delete();
    }

    if (graceEndsAt != null) {
      updates['subscription.graceEndsAt'] =
          Timestamp.fromDate(graceEndsAt.toUtc());
    } else if (clearGraceEndsAt) {
      updates['subscription.graceEndsAt'] = FieldValue.delete();
    }

    if (paymentMethod != null) {
      updates['subscription.paymentMethod'] = paymentMethod;
    } else if (clearPaymentMethod) {
      updates['subscription.paymentMethod'] = FieldValue.delete();
    }

    if (status != null) {
      updates['subscription.status'] = status;
    } else if (clearStatus) {
      updates['subscription.status'] = FieldValue.delete();
    }

    if (cancelAtPeriodEnd != null) {
      updates['subscription.cancelAtPeriodEnd'] = cancelAtPeriodEnd;
    }

    if (cancelsAt != null) {
      updates['subscription.cancelsAt'] = Timestamp.fromDate(cancelsAt.toUtc());
    } else if (clearCancelsAt) {
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
    } else if (clearStripeSubscriptionId) {
      updates['subscription.stripeSubscriptionId'] = FieldValue.delete();
    }

    if (stripeCustomerId != null) {
      updates['subscription.stripeCustomerId'] =
          stripeCustomerId.isEmpty ? FieldValue.delete() : stripeCustomerId;
    } else if (clearStripeCustomerId) {
      updates['subscription.stripeCustomerId'] = FieldValue.delete();
    }

    if (touchUpdatedAt) {
      updates['subscription.updatedAt'] = FieldValue.serverTimestamp();
      updates['updatedAt'] = FieldValue.serverTimestamp();
    }

    // ✅ Limpieza de legacy fields (TOP-LEVEL) cuyo nombre literal incluye punto.
    // En consola se ven como:  subscription.endDate  (no dentro del mapa subscription)
    void _delLegacy(String literal) {
      updates[FieldPath([literal])] = FieldValue.delete();
    }

    _delLegacy('subscription.startDate');
    _delLegacy('subscription.endDate');
    _delLegacy('subscription.graceEndsAt');
    _delLegacy('subscription.graceEndDate');
    _delLegacy('subscription.paymentMethod');
    _delLegacy('subscription.status');
    _delLegacy('subscription.cancelAtPeriodEnd');
    _delLegacy('subscription.cancelsAt');
    _delLegacy('subscription.cancelScheduledAt');
    _delLegacy('subscription.paymentMethods');
    _delLegacy('subscription.stripeSubscriptionId');
    _delLegacy('subscription.stripeCustomerId');
    _delLegacy('subscription.updatedAt');

    if (updates.isEmpty) return;

    try {
      await ref.update(updates);
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        // ✅ FIX: set() solo acepta Map<String,dynamic> y NO soporta FieldPath keys.
        // Creamos el doc con un set mínimo y luego aplicamos el update real.
        await ref.set(
          <String, dynamic>{
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        await ref.update(updates);
      } else {
        rethrow;
      }
    }
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

List<StoredPaymentMethod> _parsePaymentMethods(dynamic raw) {
  if (raw is! List) return const <StoredPaymentMethod>[];
  final out = <StoredPaymentMethod>[];
  for (final item in raw) {
    if (item is Map) {
      out.add(StoredPaymentMethod.fromMap(Map<String, dynamic>.from(item)));
    }
  }
  return out;
}
