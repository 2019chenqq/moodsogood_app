import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class IAPService {
  IAPService._privateConstructor();
  static final IAPService instance = IAPService._privateConstructor();

  final InAppPurchase _iap = InAppPurchase.instance;
  List<ProductDetails> products = [];
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // 初始化 IAP
  Future<void> init() async {
    listenToPurchase();
    try {
      await loadProducts().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ IAP loadProducts timeout - likely running on emulator without Play Services');
        },
      );
    } catch (e) {
      debugPrint('❌ IAP init error: $e');
    }
  }

  // 查詢商品清單
  Future<void> loadProducts() async {
    const Set<String> ids = {
      'heartshine_pro_monthly',
      'themes_pack',
    };

    try {
      final response = await _iap.queryProductDetails(ids);

      if (response.error != null) {
        debugPrint("商品查詢錯誤：${response.error}");
      }

      products = response.productDetails;
      debugPrint("已取得商品：$products");
    } catch (e) {
      debugPrint('❌ Error querying products: $e');
    }
  }

  // 發起購買
  Future<void> buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  // 監聽購買結果
  void listenToPurchase() {
    _subscription = _iap.purchaseStream.listen((purchases) {
      for (var p in purchases) {
        switch (p.status) {
          case PurchaseStatus.purchased:
            _verifyAndGrant(p);
            break;
          case PurchaseStatus.error:
            debugPrint("購買錯誤：${p.error}");
            break;
          default:
            break;
        }

        if (p.pendingCompletePurchase) {
          _iap.completePurchase(p);
        }
      }
    });
  }

  // 驗證 + 解鎖付費功能
  Future<void> _verifyAndGrant(PurchaseDetails purchase) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'pro': true}, SetOptions(merge: true));

    debugPrint("付費成功：已解鎖 Pro 功能");
  }

  void dispose() {
    _subscription?.cancel();
  }
}
