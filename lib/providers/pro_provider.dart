import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 🚧 開發/測試用開關：正式版必須維持 false，避免所有人直接解鎖 Pro。
const bool kDebugUnlockAllProFeatures = false;
const bool kAppStoreReviewScreenshotMode = bool.fromEnvironment(
    'APP_STORE_REVIEW_SCREENSHOT_MODE',
    defaultValue: false);
const String kRevenueCatAndroidApiKey = String.fromEnvironment(
  'REVENUECAT_ANDROID_API_KEY',
  defaultValue: 'goog_XQOPKtoNIDcbyNCNCqDADwSfPKW',
);
const String kRevenueCatIosApiKey = String.fromEnvironment(
  'REVENUECAT_IOS_API_KEY',
  defaultValue: 'appl_ixKmvQvQMnrhkqjDhTuaHcHHXXG',
);

bool get isReviewScreenshotModeEnabled =>
    kAppStoreReviewScreenshotMode || kDebugMode;

typedef OnProUpgradeCallback = Future<void> Function();
const String kRevenueCatEntitlementId = 'premium';
bool _isRevenueCatConfigured = false;
String? _revenueCatInitializationError;
String? _revenueCatUserId;
StreamSubscription<User?>? _revenueCatAuthSubscription;

bool get isRevenueCatConfigured => _isRevenueCatConfigured;
String? get revenueCatInitializationError => _revenueCatInitializationError;

Future<void> initializeRevenueCat() async {
  if (kIsWeb || _isRevenueCatConfigured) return;

  final apiKey = switch (defaultTargetPlatform) {
    TargetPlatform.android => kRevenueCatAndroidApiKey,
    TargetPlatform.iOS => kRevenueCatIosApiKey,
    _ => '',
  };
  if (apiKey.trim().isEmpty) {
    _revenueCatInitializationError = 'RevenueCat API key 為空';
    return;
  }

  try {
    if (await Purchases.isConfigured) {
      _isRevenueCatConfigured = true;
      _revenueCatInitializationError = null;
      return;
    }

    if (kDebugMode) {
      await Purchases.setLogLevel(LogLevel.debug);
    }

    User? currentUser;
    try {
      currentUser = FirebaseAuth.instance.currentUser;
    } catch (_) {
      // Billing must still initialize if Firebase Auth is temporarily unavailable.
    }

    final configuration = PurchasesConfiguration(apiKey);
    configuration.appUserID = currentUser?.uid;
    await Purchases.configure(configuration);
    _isRevenueCatConfigured = await Purchases.isConfigured;
    _revenueCatInitializationError = null;
    _revenueCatUserId = currentUser?.uid;

    try {
      _revenueCatAuthSubscription ??=
          FirebaseAuth.instance.authStateChanges().listen((user) {
        unawaited(_syncRevenueCatUser(user));
      });
    } catch (_) {
      // RevenueCat remains usable without Firebase identity synchronization.
    }
  } catch (error) {
    _isRevenueCatConfigured = false;
    _revenueCatInitializationError = error.toString();
    rethrow;
  }
}

Future<void> _syncRevenueCatUser(User? user) async {
  if (!isRevenueCatConfigured) return;

  try {
    if (user != null && user.uid != _revenueCatUserId) {
      await Purchases.logIn(user.uid);
      _revenueCatUserId = user.uid;
      return;
    }

    if (user == null && _revenueCatUserId != null) {
      await Purchases.logOut();
      _revenueCatUserId = null;
    }
  } catch (error, stackTrace) {
    debugPrint('RevenueCat user sync failed: $error');
    debugPrint('$stackTrace');
  }
}

class ProProvider extends ChangeNotifier {
  bool _loading = true;
  OnProUpgradeCallback? _onUpgradeCallback;
  bool _isMigrating = false;
  bool _remoteIsPro = false; // Firestore / 訂閱同步來的
  bool? _debugOverrideIsPro; // null = 不覆蓋
  bool? _reviewOverrideIsPro; // App Store 審核截圖模式專用
  late final CustomerInfoUpdateListener _customerInfoListener =
      _handleCustomerInfoUpdate;
  bool _isListeningToCustomerInfo = false;

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

    if (isRevenueCatConfigured) {
      Purchases.addCustomerInfoUpdateListener(_customerInfoListener);
      _isListeningToCustomerInfo = true;
      await refreshFromRevenueCat();
    }
    _loading = false;
    notifyListeners();
  }

  bool _isEntitlementActive(CustomerInfo info) {
    return info.entitlements.all[kRevenueCatEntitlementId]?.isActive ?? false;
  }

  void _handleCustomerInfoUpdate(CustomerInfo info) {
    _remoteIsPro = _isEntitlementActive(info);
    unawaited(_syncProStatusToFirestore(_remoteIsPro));
    notifyListeners();
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
    if (!isRevenueCatConfigured) return;
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
      debugPrint('升級失敗：$e');
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
    if (_isListeningToCustomerInfo) {
      Purchases.removeCustomerInfoUpdateListener(_customerInfoListener);
    }
    super.dispose();
  }
}
