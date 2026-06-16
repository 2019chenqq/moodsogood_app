class FirebaseSyncConfig {
  static final FirebaseSyncConfig _instance = FirebaseSyncConfig._internal();

  factory FirebaseSyncConfig() => _instance;

  FirebaseSyncConfig._internal();

  static void setProStatusCallback(bool Function() callback) {}

  Future<void> init() async {}

  static bool shouldSync() => true;

  static String getStorageType() => '雲端儲存';

  static String getDataRetention() => '依帳號雲端保存';
}
