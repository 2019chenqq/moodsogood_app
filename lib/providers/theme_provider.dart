import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system; // 預設跟隨系統

  ThemeMode get themeMode => _themeMode;

  // 1. 初始化：讀取之前的設定
  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('themeMode');
    
    if (savedTheme == 'light') {
      _themeMode = ThemeMode.light;
    } else if (savedTheme == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners(); // 通知 App 更新畫面
  }

  // 2. 切換主題
  Future<void> setTheme(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners(); // 通知 App 更新畫面

    // 存檔
    final prefs = await SharedPreferences.getInstance();
    String value = 'system';
    if (mode == ThemeMode.light) value = 'light';
    if (mode == ThemeMode.dark) value = 'dark';
    await prefs.setString('themeMode', value);
  }
}
