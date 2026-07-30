import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_storage_service.dart';

class AppLockStatus {
  const AppLockStatus({
    required this.failedAttempts,
    required this.lockedUntil,
  });

  final int failedAttempts;
  final DateTime? lockedUntil;

  Duration remaining(DateTime now) {
    final until = lockedUntil;
    if (until == null || !until.isAfter(now)) return Duration.zero;
    return until.difference(now);
  }
}

class AppLockPinService {
  static const _storage = FlutterSecureStorage();
  static const _legacyPreferenceKey = 'appLockPin';
  static const _verifierKey = 'app_lock_pin_verifier_v2';
  static const _attemptStateKey = 'app_lock_attempt_state_v1';
  static const _resetAttemptStateKey = 'app_lock_reset_attempt_state_v1';
  static const _emailAttemptStateKey = 'app_lock_email_attempt_state_v1';
  static const _version = 2;
  static const _iterations = 200000;
  static const _saltLength = 16;
  static const _derivedKeyLength = 32;
  static const _failureThreshold = 5;
  static const _baseLockoutSeconds = 30;
  static const _maximumLockoutSeconds = 15 * 60;
  static const _resetFailureThreshold = 3;
  static const _resetBaseLockoutSeconds = 60;

  /// Ensures existing users are migrated before the legacy plaintext PIN is
  /// removed. The old PIN is retained only in secure storage as a temporary
  /// E2E-key recovery fallback.
  static Future<bool> ensureMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyPin = (prefs.getString(_legacyPreferenceKey) ?? '').trim();
    var verifier = await _storage.read(key: _verifierKey);

    if ((verifier == null || verifier.isEmpty) && legacyPin.isNotEmpty) {
      verifier = buildVerifier(legacyPin);
      await _storage.write(key: _verifierKey, value: verifier);
    }

    if (legacyPin.isNotEmpty) {
      await SecureStorageService.saveLegacyAppLockRecoveryPin(legacyPin);
      await prefs.remove(_legacyPreferenceKey);
    }

    return verifier != null && verifier.isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError.value(
          pin, 'pin', 'PIN must contain exactly 6 digits');
    }
    await ensureMigrated();
    await _storage.write(key: _verifierKey, value: buildVerifier(pin));
    await resetFailedAttempts();
  }

  static Future<bool> verifyPin(String pin) async {
    await ensureMigrated();
    final encoded = await _storage.read(key: _verifierKey);
    if (encoded == null || encoded.isEmpty) return false;
    return verifyEncoded(pin, encoded);
  }

  static Future<void> deletePin() async {
    await ensureMigrated();
    await _storage.delete(key: _verifierKey);
    await resetFailedAttempts();
  }

  static Future<bool> hasPin() async {
    await ensureMigrated();
    final encoded = await _storage.read(key: _verifierKey);
    return encoded != null && encoded.isNotEmpty;
  }

  static String buildVerifier(
    String pin, {
    Uint8List? salt,
    int iterations = _iterations,
  }) {
    final verifierSalt = salt ?? _secureRandomBytes(_saltLength);
    final derived = _derive(pin, verifierSalt, iterations);
    return jsonEncode({
      'version': _version,
      'algorithm': 'PBKDF2-HMAC-SHA256',
      'iterations': iterations,
      'salt': base64Encode(verifierSalt),
      'hash': base64Encode(derived),
    });
  }

  static bool verifyEncoded(String pin, String encoded) {
    try {
      final data = jsonDecode(encoded);
      if (data is! Map<String, dynamic> ||
          data['version'] != _version ||
          data['algorithm'] != 'PBKDF2-HMAC-SHA256') {
        return false;
      }

      final iterations = data['iterations'];
      final saltText = data['salt'];
      final expectedText = data['hash'];
      if (iterations is! int ||
          iterations < 10000 ||
          saltText is! String ||
          expectedText is! String) {
        return false;
      }

      final salt = base64Decode(saltText);
      final expected = base64Decode(expectedText);
      final actual = _derive(pin, Uint8List.fromList(salt), iterations);
      return _constantTimeEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }

  static Future<AppLockStatus> getStatus({DateTime? now}) async {
    final currentTime = now ?? DateTime.now();
    final encoded = await _storage.read(key: _attemptStateKey);
    if (encoded == null || encoded.isEmpty) {
      return const AppLockStatus(failedAttempts: 0, lockedUntil: null);
    }

    try {
      final data = jsonDecode(encoded);
      if (data is! Map<String, dynamic>) {
        return const AppLockStatus(failedAttempts: 0, lockedUntil: null);
      }
      final attempts = data['failedAttempts'];
      final lockedUntilMs = data['lockedUntilMs'];
      final lockedUntil = lockedUntilMs is int
          ? DateTime.fromMillisecondsSinceEpoch(lockedUntilMs)
          : null;
      return AppLockStatus(
        failedAttempts: attempts is int && attempts >= 0 ? attempts : 0,
        lockedUntil: lockedUntil != null && lockedUntil.isAfter(currentTime)
            ? lockedUntil
            : null,
      );
    } catch (_) {
      return const AppLockStatus(failedAttempts: 0, lockedUntil: null);
    }
  }

  static Future<AppLockStatus> recordFailedAttempt({DateTime? now}) async {
    final currentTime = now ?? DateTime.now();
    final current = await getStatus(now: currentTime);
    if (current.remaining(currentTime) > Duration.zero) return current;

    final attempts = current.failedAttempts + 1;
    DateTime? lockedUntil;
    if (attempts >= _failureThreshold) {
      final exponent = min(attempts - _failureThreshold, 5);
      final seconds = min(
        _baseLockoutSeconds * pow(2, exponent).toInt(),
        _maximumLockoutSeconds,
      );
      lockedUntil = currentTime.add(Duration(seconds: seconds));
    }

    await _storage.write(
      key: _attemptStateKey,
      value: jsonEncode({
        'failedAttempts': attempts,
        'lockedUntilMs': lockedUntil?.millisecondsSinceEpoch,
      }),
    );
    return AppLockStatus(
      failedAttempts: attempts,
      lockedUntil: lockedUntil,
    );
  }

  static Future<void> resetFailedAttempts() {
    return _storage.delete(key: _attemptStateKey);
  }

  static Future<AppLockStatus> getResetStatus({DateTime? now}) {
    return _readAttemptStatus(_resetAttemptStateKey, now: now);
  }

  static Future<AppLockStatus> recordResetFailure({DateTime? now}) {
    return _recordAttemptFailure(
      _resetAttemptStateKey,
      threshold: _resetFailureThreshold,
      baseLockoutSeconds: _resetBaseLockoutSeconds,
      now: now,
    );
  }

  static Future<void> resetResetFailures() {
    return _storage.delete(key: _resetAttemptStateKey);
  }

  static Future<AppLockStatus> getEmailVerificationStatus({DateTime? now}) {
    return _readAttemptStatus(_emailAttemptStateKey, now: now);
  }

  static Future<AppLockStatus> recordEmailVerificationFailure({
    DateTime? now,
  }) {
    return _recordAttemptFailure(
      _emailAttemptStateKey,
      threshold: 5,
      baseLockoutSeconds: 60 * 60,
      maximumLockoutSeconds: 60 * 60,
      now: now,
    );
  }

  static Future<void> resetEmailVerificationFailures() {
    return _storage.delete(key: _emailAttemptStateKey);
  }

  static Future<AppLockStatus> _readAttemptStatus(
    String key, {
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();
    final encoded = await _storage.read(key: key);
    if (encoded == null || encoded.isEmpty) {
      return const AppLockStatus(failedAttempts: 0, lockedUntil: null);
    }

    try {
      final data = jsonDecode(encoded);
      if (data is! Map<String, dynamic>) {
        return const AppLockStatus(failedAttempts: 0, lockedUntil: null);
      }
      final attempts = data['failedAttempts'];
      final lockedUntilMs = data['lockedUntilMs'];
      final lockedUntil = lockedUntilMs is int
          ? DateTime.fromMillisecondsSinceEpoch(lockedUntilMs)
          : null;
      return AppLockStatus(
        failedAttempts: attempts is int && attempts >= 0 ? attempts : 0,
        lockedUntil: lockedUntil != null && lockedUntil.isAfter(currentTime)
            ? lockedUntil
            : null,
      );
    } catch (_) {
      return const AppLockStatus(failedAttempts: 0, lockedUntil: null);
    }
  }

  static Future<AppLockStatus> _recordAttemptFailure(
    String key, {
    required int threshold,
    required int baseLockoutSeconds,
    int maximumLockoutSeconds = _maximumLockoutSeconds,
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();
    final current = await _readAttemptStatus(key, now: currentTime);
    if (current.remaining(currentTime) > Duration.zero) return current;

    final attempts = current.failedAttempts + 1;
    DateTime? lockedUntil;
    if (attempts >= threshold) {
      final exponent = min(attempts - threshold, 5);
      final seconds = min(
        baseLockoutSeconds * pow(2, exponent).toInt(),
        maximumLockoutSeconds,
      );
      lockedUntil = currentTime.add(Duration(seconds: seconds));
    }

    await _storage.write(
      key: key,
      value: jsonEncode({
        'failedAttempts': attempts,
        'lockedUntilMs': lockedUntil?.millisecondsSinceEpoch,
      }),
    );
    return AppLockStatus(
      failedAttempts: attempts,
      lockedUntil: lockedUntil,
    );
  }

  static Uint8List _derive(String pin, Uint8List salt, int iterations) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _derivedKeyLength));
    return derivator.process(Uint8List.fromList(utf8.encode(pin)));
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
