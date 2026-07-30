import 'package:shared_preferences/shared_preferences.dart';

enum HealthStorageMode {
  localOnly,
  encryptedCloudSync,
}

extension HealthStorageModeText on HealthStorageMode {
  String get storageLabel => switch (this) {
        HealthStorageMode.localOnly => '只存本機',
        HealthStorageMode.encryptedCloudSync => '加密雲端同步',
      };

  String get retentionLabel => switch (this) {
        HealthStorageMode.localOnly => '資料只保留在這台裝置',
        HealthStorageMode.encryptedCloudSync => '本機保留副本，密文同步至雲端',
      };
}

class FirebaseSyncConfig {
  static final FirebaseSyncConfig _instance = FirebaseSyncConfig._internal();

  factory FirebaseSyncConfig() => _instance;

  FirebaseSyncConfig._internal();

  static const _modeKeyPrefix = 'healthStorageMode.';
  static const _choiceVersionKeyPrefix = 'healthStorageChoiceVersion.';
  static const currentChoiceVersion = 1;

  static HealthStorageMode _mode = HealthStorageMode.encryptedCloudSync;
  static bool _hasExplicitChoice = false;
  static String? _activeUid;

  static HealthStorageMode get mode => _mode;
  static bool get hasExplicitChoice => _hasExplicitChoice;
  static String? get activeUid => _activeUid;

  static void setProStatusCallback(bool Function() callback) {}

  /// Kept for the existing startup call. User-specific state is loaded after
  /// authentication through [loadForUser].
  Future<void> init() async {}

  static Future<void> loadForUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('$_modeKeyPrefix$uid');
    _activeUid = uid;
    _mode = _parse(stored) ?? HealthStorageMode.encryptedCloudSync;
    _hasExplicitChoice =
        prefs.getInt('$_choiceVersionKeyPrefix$uid') == currentChoiceVersion;
  }

  static Future<void> saveModeForUser(
    String uid,
    HealthStorageMode mode,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_modeKeyPrefix$uid', mode.name);
    await prefs.setInt(
      '$_choiceVersionKeyPrefix$uid',
      currentChoiceVersion,
    );
    _activeUid = uid;
    _mode = mode;
    _hasExplicitChoice = true;
  }

  static void clearActiveUser() {
    _activeUid = null;
    _mode = HealthStorageMode.encryptedCloudSync;
    _hasExplicitChoice = false;
  }

  static bool shouldSync() => _mode == HealthStorageMode.encryptedCloudSync;

  static String getStorageType() => _mode.storageLabel;

  static String getDataRetention() => _mode.retentionLabel;

  static HealthStorageMode? _parse(String? value) {
    for (final mode in HealthStorageMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }
}
