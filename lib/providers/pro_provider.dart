import 'package:flutter/material.dart';
import '../service/iap_service.dart';
import 'dart:async';

/// 🚧 開發/測試用開關：設為 true 時，所有使用者都能使用 Pro features
/// 📌 正式上線前請改為 false
const bool kDebugUnlockAllProFeatures = false;
const bool kAppStoreReviewScreenshotMode =
  bool.fromEnvironment('APP_STORE_REVIEW_SCREENSHOT_MODE', defaultValue: false);

typedef OnProUpgradeCallback = Future<void> Function();

class ProProvider extends ChangeNotifier {
  bool _loading = true;
  OnProUpgradeCallback? _onUpgradeCallback;
  bool _isMigrating = false;
  bool _remoteIsPro = false; // Firestore / 訂閱同步來的
  bool? _debugOverrideIsPro; // null = 不覆蓋
  bool? _reviewOverrideIsPro; // App Store 審核截圖模式專用
  StreamSubscription<bool>? _proStatusSubscription;

  /// 檢查使用者是否為 Pro
  /// 如果 kDebugUnlockAllProFeatures = true，則所有人都是 Pro
  bool get isPro => kDebugUnlockAllProFeatures
      ? true
      : (kAppStoreReviewScreenshotMode
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

    await IAPService.instance.init();
    _remoteIsPro = await IAPService.instance.refreshProStatusFromCloud();

    _proStatusSubscription?.cancel();
    _proStatusSubscription = IAPService.instance.proStatusStream.listen(
      (isPro) async {
        final wasPro = _remoteIsPro;
        _remoteIsPro = isPro;
        notifyListeners();

        if (!wasPro && isPro && _onUpgradeCallback != null) {
          await _onUpgradeCallback!();
        }
      },
    );

    _loading = false;
    notifyListeners();
  }

  Future<void> refreshFromServer() async {
    _remoteIsPro = await IAPService.instance.refreshProStatusFromCloud();
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
    if (!kAppStoreReviewScreenshotMode) return;
    _reviewOverrideIsPro = isPro;
    notifyListeners();
  }

  void clearReviewPreviewStatus() {
    if (!kAppStoreReviewScreenshotMode) return;
    _reviewOverrideIsPro = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _proStatusSubscription?.cancel();
    super.dispose();
  }
}

