import 'package:flutter/material.dart';

/// 🚧 開發/測試用開關：設為 true 時，所有使用者都能使用 Pro features
/// 📌 正式上線前請改為 false
const bool kDebugUnlockAllProFeatures = true;

class ProProvider extends ChangeNotifier {
  bool _isPro = false;
  bool _loading = true;

  /// 檢查使用者是否為 Pro
  /// 如果 kDebugUnlockAllProFeatures = true，則所有人都是 Pro
  bool get isPro => kDebugUnlockAllProFeatures || _isPro;
  
  bool get loading => _loading;

  Future<void> init() async {
    _loading = true;
    notifyListeners();

    // TODO：之後接 Google Play 訂閱檢查
    // 現在先預設 false（不付費）
    await Future.delayed(const Duration(milliseconds: 500));

    _isPro = false;
    _loading = false;
    notifyListeners();
  }

  /// Debug / 測試用（之後可刪）
  void debugUnlock() {
    _isPro = true;
    notifyListeners();
  }

  void lock() {
    _isPro = false;
    notifyListeners();
  }
}
