import 'package:flutter/foundation.dart';

/// 🔧 Firebase Sync Control Configuration
/// 
/// This controls whether data is synced to Firebase or stored locally only.
/// Configured by the app, not controlled by users.
/// 
/// Useful for:
/// - Testing/development without Firebase writes
/// - Environment-specific behavior (debug vs release)
class FirebaseSyncConfig {
  static final FirebaseSyncConfig _instance =
      FirebaseSyncConfig._internal();

  factory FirebaseSyncConfig() => _instance;
  FirebaseSyncConfig._internal();

  /// 🔧 Control Firebase sync behavior:
  /// - Set to false for development/testing (no Firebase quota usage)
  /// - Set to true for production (cloud sync enabled)
  /// 📌 Change this based on your build configuration
  static const bool kEnableFirebaseSync = true;

  bool get isEnabled => kEnableFirebaseSync;

  /// Initialize sync config (mainly for logging)
  Future<void> init() async {
    try {
      debugPrint(
          '📡 Firebase Sync: ${kEnableFirebaseSync ? 'ENABLED' : 'DISABLED'}');
    } catch (e) {
      debugPrint('❌ Error initializing Firebase Sync Config: $e');
    }
  }

  /// Check if a Firebase operation should proceed
  /// Returns true if sync is enabled, false if local-only mode
  static bool shouldSync() => kEnableFirebaseSync;
}
