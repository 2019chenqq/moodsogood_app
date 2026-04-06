import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 🚧 開發/測試用開關：設為 true 時，所有使用者都能使用 Pro features
/// 📌 正式上線前請改為 false
const bool kDebugUnlockAllProFeatures = true;
const bool kAppStoreReviewScreenshotMode =
  bool.fromEnvironment('APP_STORE_REVIEW_SCREENSHOT_MODE', defaultValue: false);

bool get isReviewScreenshotModeEnabled =>
    kAppStoreReviewScreenshotMode || kDebugMode;

typedef OnProUpgradeCallback = Future<void> Function();
const String kRevenueCatEntitlementId = 'premium';

class ProProvider extends ChangeNotifier {
  bool _loading = true;
  OnProUpgradeCallback? _onUpgradeCallback;
  bool _isMigrating = false;
  bool _remoteIsPro = false; // Firestore / 訂閱同步來的
  bool? _debugOverrideIsPro; // null = 不覆蓋
  bool? _reviewOverrideIsPro; // App Store 審核截圖模式專用

  /// 檢查使用者是否為 Pro
  /// 如果 kDebugUnlockAllProFeatures = true，則所有人都是 Pro
  bool get isPro => kDebugUnlockAllProFeatures
      ? true
      : (isReviewScreenshotModeEnabled
          ? (_reviewOverrideIsPro ?? _debugOverrideIsPro ?? _remoteIsPro)
          : (_debugOverrideIsPro ?? _remoteIsPro));
  
  bool get loading => _loading;
  bool get isMigrating => _isMigrating;

  /// 設置升級回調（用於數據遷移）
  void setOnUpgradeCallback(OnProUpgradeCallback callback) {
    _onUpgradeCallback = callback;
  }

  Future<void> init() async {
    _loading = true;
    notifyListeners();

    await refreshFromRevenueCat();

    Purchases.addCustomerInfoUpdateListener((customerInfo) async {
      final wasPro = _remoteIsPro;
      _remoteIsPro = _isEntitlementActive(customerInfo);
      await _syncProStatusToFirestore(_remoteIsPro);
      notifyListeners();

      if (!wasPro && _remoteIsPro && _onUpgradeCallback != null) {
        await _onUpgradeCallback!();
      }
    });

    _loading = false;
    notifyListeners();
  }

  bool _isEntitlementActive(CustomerInfo info) {
    return info.entitlements.all[kRevenueCatEntitlementId]?.isActive ?? false;
  }

  Future<void> _syncProStatusToFirestore(bool isProNow) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'pro': isProNow,
      'isPro': isProNow,
      'proStore': 'revenuecat',
      'proUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> refreshFromRevenueCat() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _remoteIsPro = _isEntitlementActive(info);
      await _syncProStatusToFirestore(_remoteIsPro);
    } catch (_) {
      // Keep previous state on transient SDK/network failures.
    }
    notifyListeners();
  }

  Future<void> refreshFromServer() async {
    await refreshFromRevenueCat();
    notifyListeners();
  }

  /// Debug / 測試用（之後可刪）
  /// 升級時觸發數據遷移
  Future<void> debugUnlock() async {
    _isMigrating = true;
    notifyListeners();

    try {
      // 觸發數據遷移回調
      if (_onUpgradeCallback != null) {
        await _onUpgradeCallback!();
      }

      _debugOverrideIsPro = true;
      notifyListeners();
    } catch (e) {
      print('升級失敗：$e');
      _isMigrating = false;
      notifyListeners();
      rethrow;
    }

    _isMigrating = false;
    notifyListeners();
  }

  void lock() {
    _debugOverrideIsPro = false;
    notifyListeners();
  }

  // App Store 截圖流程：可用 dart-define 暫時切換 Pro/免費畫面。
  void setReviewPreviewProStatus(bool isPro) {
    if (!isReviewScreenshotModeEnabled) return;
    _reviewOverrideIsPro = isPro;
    notifyListeners();
  }

  void clearReviewPreviewStatus() {
    if (!isReviewScreenshotModeEnabled) return;
    _reviewOverrideIsPro = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}

