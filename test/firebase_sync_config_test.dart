import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/utils/firebase_sync_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FirebaseSyncConfig.clearActiveUser();
  });

  test('uses encrypted cloud sync as the legacy-safe default', () async {
    await FirebaseSyncConfig.loadForUser('user-a');

    expect(FirebaseSyncConfig.mode, HealthStorageMode.encryptedCloudSync);
    expect(FirebaseSyncConfig.shouldSync(), isTrue);
    expect(FirebaseSyncConfig.hasExplicitChoice, isFalse);
  });

  test('persists local-only choice separately for each user', () async {
    await FirebaseSyncConfig.saveModeForUser(
      'user-a',
      HealthStorageMode.localOnly,
    );

    expect(FirebaseSyncConfig.shouldSync(), isFalse);
    expect(FirebaseSyncConfig.hasExplicitChoice, isTrue);

    FirebaseSyncConfig.clearActiveUser();
    await FirebaseSyncConfig.loadForUser('user-a');
    expect(FirebaseSyncConfig.mode, HealthStorageMode.localOnly);

    await FirebaseSyncConfig.loadForUser('user-b');
    expect(FirebaseSyncConfig.mode, HealthStorageMode.encryptedCloudSync);
    expect(FirebaseSyncConfig.hasExplicitChoice, isFalse);
  });
}
