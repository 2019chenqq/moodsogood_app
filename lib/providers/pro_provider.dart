import 'package:flutter/material.dart';

class ProProvider extends ChangeNotifier {
  bool _isPro = false;
  bool _loading = true;

  bool get isPro => _isPro;
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
