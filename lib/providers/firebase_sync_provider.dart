import 'package:flutter/material.dart';
import '../utils/firebase_sync_config.dart';

/// Provider to expose Firebase Sync state
/// 
/// Read-only provider - Firebase sync is controlled by the app,
/// not by user action. Can be used to display sync status in UI if needed.
class FirebaseSyncProvider extends ChangeNotifier {
  late FirebaseSyncConfig _config;

  bool get isEnabled => FirebaseSyncConfig.shouldSync();

  FirebaseSyncProvider() {
    _config = FirebaseSyncConfig();
  }

  /// Initialize the provider
  Future<void> init() async {
    try {
      await _config.init();
    } catch (e) {
      debugPrint('❌ Error initializing FirebaseSyncProvider: $e');
    }

    notifyListeners();
  }

  /// Get sync status as string for display
  String get statusString => isEnabled ? 'Firebase Sync: ON' : 'Firebase Sync: OFF (Local Only)';
}
