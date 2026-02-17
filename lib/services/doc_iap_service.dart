import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Maneja compras por documento (NO consumibles) vía StoreKit / Google Play Billing.
/// IMPORTANTE: En producción debes validar recibos/tokens en backend.
/// Esto es un MVP funcional (recomendado endurecer después).
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

  /// Cache de productos
  final Map<String, ProductDetails> _products = {};
  Map<String, ProductDetails> get products => Map.unmodifiable(_products);

  /// Carga productos IAP en base a productIds (debes crearlos en stores).
  Future<void> loadProducts(Set<String> productIds) async {
    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) return;

    if (productIds.isEmpty) return;

    final response = await _iap.queryProductDetails(productIds);
    if (response.error != null) {
      // En MVP: solo dejamos vacío.
      return;
    }

    _products
      ..clear()
      ..addEntries(response.productDetails.map((p) => MapEntry(p.id, p)));
  }

  /// Compra NO consumible (un documento).
  Future<void> buyNonConsumable(String productId) async {
    final product = _products[productId];
    if (product == null) {
      throw Exception('Producto IAP no encontrado: $productId');
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Restaura compras (muy importante en iOS).
  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  /// Entitlements: guardamos qué docs compró el usuario en Firestore.
  /// Colección sugerida:
  /// users/{uid}/doc_purchases/{productId}
  Future<Set<String>> loadPurchasedProductIds() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return <String>{};

    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('doc_purchases')
        .get();

    return snap.docs.map((d) => d.id).toSet();
  }

  /// Entrega la compra (marca purchased) cuando el store reporte PURCHASED/RESTORED.
  /// En producción: aquí deberías llamar un Cloud Function para validar recibo/token.
  Future<void> grantEntitlement(PurchaseDetails purchase) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

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
      // Guardamos el payload; en producción no lo uses como “verdad” sin validar.
      'verificationData': purchase.verificationData.serverVerificationData,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
