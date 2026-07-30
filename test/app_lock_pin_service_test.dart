import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/utils/app_lock_pin_service.dart';
import 'package:moodsogood_app/utils/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('AppLockPinService verifier', () {
    test('accepts the correct PIN and rejects an incorrect PIN', () {
      final encoded = AppLockPinService.buildVerifier(
        '123456',
        salt: Uint8List.fromList(List<int>.generate(16, (index) => index)),
        iterations: 10000,
      );

      expect(AppLockPinService.verifyEncoded('123456', encoded), isTrue);
      expect(AppLockPinService.verifyEncoded('654321', encoded), isFalse);
    });

    test('stores a versioned salted verifier instead of the PIN', () {
      final encoded = AppLockPinService.buildVerifier(
        '123456',
        salt: Uint8List(16),
        iterations: 10000,
      );
      final data = jsonDecode(encoded) as Map<String, dynamic>;

      expect(data['version'], 2);
      expect(data['algorithm'], 'PBKDF2-HMAC-SHA256');
      expect(data['hash'], isNot(contains('123456')));
      expect(encoded, isNot(contains('123456')));
    });

    test('rejects malformed or unsupported verifier data', () {
      expect(AppLockPinService.verifyEncoded('123456', 'not-json'), isFalse);
      expect(
        AppLockPinService.verifyEncoded(
          '123456',
          jsonEncode({'version': 1}),
        ),
        isFalse,
      );
    });
  });

  test('migrates the legacy preference and removes its plaintext value',
      () async {
    SharedPreferences.setMockInitialValues({'appLockPin': '123456'});

    expect(await AppLockPinService.ensureMigrated(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('appLockPin'), isNull);
    expect(
      await SecureStorageService.getLegacyAppLockRecoveryPin(),
      '123456',
    );
  });

  test('locks after five failures and increases the next cooldown', () async {
    final start = DateTime(2026, 7, 30, 12);
    AppLockStatus status =
        const AppLockStatus(failedAttempts: 0, lockedUntil: null);

    for (var attempt = 0; attempt < 5; attempt++) {
      status = await AppLockPinService.recordFailedAttempt(now: start);
    }

    expect(status.failedAttempts, 5);
    expect(status.remaining(start), const Duration(seconds: 30));

    final afterFirstCooldown = start.add(const Duration(seconds: 31));
    status = await AppLockPinService.recordFailedAttempt(
      now: afterFirstCooldown,
    );
    expect(status.failedAttempts, 6);
    expect(status.remaining(afterFirstCooldown), const Duration(seconds: 60));
  });

  test('limits repeated identity-verification failures', () async {
    final start = DateTime(2026, 7, 30, 12);

    await AppLockPinService.recordResetFailure(now: start);
    await AppLockPinService.recordResetFailure(now: start);
    final status = await AppLockPinService.recordResetFailure(now: start);

    expect(status.failedAttempts, 3);
    expect(status.remaining(start), const Duration(minutes: 1));

    await AppLockPinService.resetResetFailures();
    final cleared = await AppLockPinService.getResetStatus(now: start);
    expect(cleared.failedAttempts, 0);
    expect(cleared.lockedUntil, isNull);
  });

  test('locks email verification for one hour after five failures', () async {
    final start = DateTime(2026, 7, 30, 12);
    AppLockStatus status =
        const AppLockStatus(failedAttempts: 0, lockedUntil: null);

    for (var attempt = 0; attempt < 5; attempt++) {
      status = await AppLockPinService.recordEmailVerificationFailure(
        now: start,
      );
    }

    expect(status.failedAttempts, 5);
    expect(status.remaining(start), const Duration(hours: 1));
  });
}
