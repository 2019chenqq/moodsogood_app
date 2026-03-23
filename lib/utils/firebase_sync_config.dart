import 'package:flutter/foundation.dart';

/// 🔧 Firebase Sync Control Configuration (基於訂閱狀態)
/// 
/// 存儲策略：
/// - 免費版：本地存儲（SQLite 只有 2 年）
/// - 付費版（Pro）：Firebase 雲端存儲（永久保存 + 多設備同步）
class FirebaseSyncConfig {
  static final FirebaseSyncConfig _instance =
      FirebaseSyncConfig._internal();
  
  // 用於動態更新 Pro 狀態的回調
  static bool Function()? _getProStatusCallback;

  factory FirebaseSyncConfig() => _instance;
  FirebaseSyncConfig._internal();

  /// 設定 Pro 狀態取得方法
  /// 在應用啟動時調用，例如在 main.dart 中
  static void setProStatusCallback(bool Function() callback) {
    _getProStatusCallback = callback;
    debugPrint('📡 Firebase Sync Config: Pro status callback registered');
  }

  /// 檢查使用者是否為 Pro
  static bool _isPro() {
    return _getProStatusCallback?.call() ?? false;
  }

  /// 初始化同步配置（主要用於日誌）
  Future<void> init() async {
    try {
      final syncStatus = shouldSync() ? '✅ 啟用（Pro 用戶）' : '❌ 禁用（免費用戶）';
      debugPrint('📡 Firebase Sync: $syncStatus');
    } catch (e) {
      debugPrint('❌ Error initializing Firebase Sync Config: $e');
    }
  }

  /// 檢查是否應該同步到 Firebase
  /// - Pro 用戶：true（雲端備份）
  /// - 免費用戶：false（本地存儲）
  static bool shouldSync() => _isPro();

  /// 獲取當前存儲類型描述
  static String getStorageType() {
    return _isPro() ? '☁️ 雲端存儲（Pro）' : '💾 本地存儲（免費）';
  }

  /// 獲取數據保留期描述
  static String getDataRetention() {
    return _isPro() ? '永久保存（雲端備份）' : '最近 2 年';
  }
}
