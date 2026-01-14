import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class InAppPurchaseService {
  InAppPurchaseService({InAppPurchase? iap})
      : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  Future<bool> isAvailable() => _iap.isAvailable();

  Future<ProductDetailsResponse> loadProducts(Set<String> ids) {
    return _iap.queryProductDetails(ids);
  }

  Future<void> buySubscription(ProductDetails product) async {
    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> completePurchaseIfNeeded(PurchaseDetails details) async {
    if (details.pendingCompletePurchase) {
      await _iap.completePurchase(details);
    }
  }

  String formatStoreLabel(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return 'Google Play';
      case TargetPlatform.iOS:
        return 'App Store';
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return 'tienda';
    }
  }
}
