import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class IAPService {
  IAPService._privateConstructor();
  static final IAPService instance = IAPService._privateConstructor();

  static const String proMonthlyProductId = 'heartshine_pro_monthly';

  final InAppPurchase _iap = InAppPurchase.instance;
  final StreamController<bool> _proStatusController =
      StreamController<bool>.broadcast();

  List<ProductDetails> products = [];
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _initialized = false;
  bool _storeAvailable = false;
  bool _isPro = false;

  Stream<bool> get proStatusStream => _proStatusController.stream;
  bool get isStoreAvailable => _storeAvailable;
  bool get isPro => _isPro;

  // 初始化 IAP
  Future<void> init() async {
    if (!_initialized) {
      listenToPurchase();
      _initialized = true;
    }

    try {
      await refreshProStatusFromCloud();
      await loadProducts();
    } catch (e) {
      debugPrint('❌ IAP init error: $e');
    }
  }

  // 查詢商品清單
  Future<void> loadProducts() async {
    const Set<String> ids = {
      proMonthlyProductId,
    };

    try {
      _storeAvailable = await _iap.isAvailable();
      if (!_storeAvailable) {
        products = [];
        debugPrint('⚠️ Store is not available on this device.');
        return;
      }

      final response = await _iap.queryProductDetails(ids);

      if (response.error != null) {
        debugPrint("商品查詢錯誤：${response.error}");
      }

      products = response.productDetails;
      debugPrint("已取得商品數量：${products.length}");
    } catch (e) {
      debugPrint('❌ Error querying products: $e');
    }
  }

  // 發起購買
  Future<void> buy(ProductDetails product) async {
    if (!_storeAvailable) {
      await loadProducts();
    }

    if (!_storeAvailable) {
      throw Exception('商店服務不可用，請稍後再試。');
    }

    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restorePurchases() async {
    if (!_storeAvailable) {
      await loadProducts();
    }

    if (!_storeAvailable) {
      throw Exception('商店服務不可用，無法恢復購買。');
    }

    await _iap.restorePurchases();
  }

  Future<bool> refreshProStatusFromCloud() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _setProStatus(false);
      return _isPro;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data();

      final isProFromCloud = data != null &&
          ((data['pro'] == true) || (data['isPro'] == true));

      _setProStatus(isProFromCloud);
    } catch (e) {
      debugPrint('⚠️ refreshProStatusFromCloud failed: $e');
    }

    return _isPro;
  }

  // 監聽購買結果
  void listenToPurchase() {
    _subscription = _iap.purchaseStream.listen((purchases) async {
      for (var p in purchases) {
        switch (p.status) {
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            await _verifyAndGrant(p);
            break;
          case PurchaseStatus.error:
            debugPrint("購買錯誤：${p.error}");
            break;
          case PurchaseStatus.canceled:
            debugPrint("使用者取消購買流程");
            break;
          case PurchaseStatus.pending:
            debugPrint("購買流程等待中");
            break;
        }

        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
      }
    });
  }

  // 驗證 + 解鎖付費功能
  Future<void> _verifyAndGrant(PurchaseDetails purchase) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // 先本地解鎖，避免 UI 需等待遠端寫入完成
    _setProStatus(true);

    if (uid == null) {
      debugPrint('⚠️ purchase succeeded but no logged-in user');
      return;
    }

    final store = defaultTargetPlatform == TargetPlatform.iOS
        ? 'app_store'
        : 'google_play';

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({
      'pro': true,
      'isPro': true,
      'proProductId': purchase.productID,
      'proPurchaseId': purchase.purchaseID,
      'proStore': store,
      'proUpdatedAt': FieldValue.serverTimestamp(),
      'purchaseVerificationData':
          purchase.verificationData.serverVerificationData,
    }, SetOptions(merge: true));

    debugPrint("付費成功：已解鎖 Pro 功能");
  }

  void _setProStatus(bool value) {
    if (_isPro == value) return;
    _isPro = value;
    _proStatusController.add(_isPro);
  }

  void dispose() {
    _subscription?.cancel();
    _proStatusController.close();
  }
}
