import 'package:flutter/material.dart';

/// 🚧 開發/測試用開關：設為 true 時，所有使用者都能使用 Pro features
/// 📌 正式上線前請改為 false
const bool kDebugUnlockAllProFeatures = true;

typedef OnProUpgradeCallback = Future<void> Function();

class ProProvider extends ChangeNotifier {
  bool _isPro = true;
  bool _loading = true;
  OnProUpgradeCallback? _onUpgradeCallback;
  bool _isMigrating = false;
bool _remoteIsPro = true;   // Firestore / 登入同步來的
bool? _debugOverrideIsPro;  // null = 不覆蓋

  /// 檢查使用者是否為 Pro
  /// 如果 kDebugUnlockAllProFeatures = true，則所有人都是 Pro
  bool get isPro => kDebugUnlockAllProFeatures
      ? true
      : (_debugOverrideIsPro ?? _remoteIsPro);
  
  bool get loading => _loading;
  bool get isMigrating => _isMigrating;

  /// 設置升級回調（用於數據遷移）
  void setOnUpgradeCallback(OnProUpgradeCallback callback) {
    _onUpgradeCallback = callback;
  }

  Future<void> init() async {
    _loading = true;
    notifyListeners();

    // TODO：之後接 Google Play 訂閱檢查
    // 全域開啟 Pro 權限
    await Future.delayed(const Duration(milliseconds: 200));

    _remoteIsPro = true;
    _isPro = true;
    _loading = false;
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

      _isPro = true;
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
}

