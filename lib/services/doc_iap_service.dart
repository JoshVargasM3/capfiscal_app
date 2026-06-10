import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Maneja compras por documento/bundle NO consumibles.
/// En producción, lo ideal es validar recibos/tokens en backend.
class DocIapService {
  DocIapService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final InAppPurchase _iap = InAppPurchase.instance;

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  final Map<String, ProductDetails> _products = {};
  Map<String, ProductDetails> get products => Map.unmodifiable(_products);

  /// Para diagnóstico visible desde la pantalla si lo necesitas.
  final Set<String> lastRequestedIds = <String>{};
  final Set<String> lastFoundIds = <String>{};
  final Set<String> lastNotFoundIds = <String>{};
  String? lastStoreError;

  Future<void> loadProducts(Set<String> productIds) async {
    lastRequestedIds
      ..clear()
      ..addAll(productIds);

    lastFoundIds.clear();
    lastNotFoundIds.clear();
    lastStoreError = null;

    debugPrint('🧾 IAP requested productIds: $productIds');

    _isAvailable = await _iap.isAvailable();
    debugPrint('🧾 IAP Store available: $_isAvailable');

    if (!_isAvailable) {
      lastStoreError =
          'StoreKit/Billing no está disponible en este dispositivo.';
      debugPrint('❌ IAP unavailable');
      return;
    }

    if (productIds.isEmpty) {
      lastStoreError = 'No hay productIds para consultar.';
      debugPrint('⚠️ IAP productIds vacío');
      return;
    }

    final response = await _iap.queryProductDetails(productIds);

    if (response.error != null) {
      lastStoreError =
          '${response.error!.code}: ${response.error!.message} ${response.error!.details ?? ''}';
      debugPrint('❌ IAP query error: $lastStoreError');
      return;
    }

    lastNotFoundIds
      ..clear()
      ..addAll(response.notFoundIDs);

    _products
      ..clear()
      ..addEntries(response.productDetails.map((p) => MapEntry(p.id, p)));

    lastFoundIds
      ..clear()
      ..addAll(_products.keys);

    debugPrint('✅ IAP found products: $lastFoundIds');
    debugPrint('⚠️ IAP notFoundIDs: $lastNotFoundIds');

    for (final p in response.productDetails) {
      debugPrint(
        '✅ IAP product loaded => id: ${p.id}, title: ${p.title}, price: ${p.price}, currency: ${p.currencyCode}',
      );
    }
  }

  Future<void> buyNonConsumable(String productId) async {
    debugPrint('🛒 Intentando comprar productId: $productId');
    debugPrint('🛒 Productos cargados disponibles: ${_products.keys.toList()}');

    final product = _products[productId];

    if (product == null) {
      final details = '''
Producto IAP no encontrado: $productId

Requested IDs: ${lastRequestedIds.join(', ')}
Found IDs: ${lastFoundIds.join(', ')}
Not Found IDs: ${lastNotFoundIds.join(', ')}
Store Error: ${lastStoreError ?? 'Sin error de StoreKit'}
''';

      debugPrint('❌ $details');

      throw Exception(
        'Producto IAP no encontrado: $productId. Revisa que el Product ID exista exactamente igual en App Store Connect.',
      );
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    debugPrint('🔄 Restaurando compras...');
    await _iap.restorePurchases();
  }

  Future<Set<String>> loadPurchasedProductIds() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return <String>{};

    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('doc_purchases')
        .get();

    final ids = snap.docs.map((d) => d.id).toSet();
    debugPrint('✅ Compras guardadas en Firestore para usuario $uid: $ids');

    return ids;
  }

  Future<void> grantEntitlement(PurchaseDetails purchase) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    debugPrint('✅ Otorgando entitlement: ${purchase.productID}');

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('doc_purchases')
        .doc(purchase.productID)
        .set({
      'productId': purchase.productID,
      'status': purchase.status.name,
      'purchaseID': purchase.purchaseID,
      'transactionDate': purchase.transactionDate,
      'source': purchase.verificationData.source,
      'verificationData': purchase.verificationData.serverVerificationData,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
