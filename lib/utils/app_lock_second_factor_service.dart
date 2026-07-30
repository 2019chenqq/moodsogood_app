import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

enum AppLockEmailVerificationOutcome {
  success,
  expired,
  invalidLink,
  userMismatch,
  unavailable,
  failed,
}

class AppLockEmailVerificationResult {
  const AppLockEmailVerificationResult(this.outcome);

  final AppLockEmailVerificationOutcome outcome;

  bool get succeeded => outcome == AppLockEmailVerificationOutcome.success;
}

class AppLockSecondFactorService {
  static const _storage = FlutterSecureStorage();
  static final _localAuth = LocalAuthentication();
  static final _appLinks = AppLinks();

  static const _pendingEmailKey = 'app_lock_email_pending_email_v1';
  static const _pendingUidKey = 'app_lock_email_pending_uid_v1';
  static const _pendingChallengeKey = 'app_lock_email_pending_challenge_v1';
  static const _pendingExpiresKey = 'app_lock_email_pending_expires_v1';
  static const _lastSentAtKey = 'app_lock_email_last_sent_at_v1';

  static const verificationLifetime = Duration(minutes: 10);
  static const resendCooldown = Duration(seconds: 60);
  static const _hostingDomain = 'moodsogood-9e45b.firebaseapp.com';

  static Stream<Uri> get emailLinkStream => _appLinks.uriLinkStream;

  static Future<Uri?> getInitialLink() => _appLinks.getInitialLink();

  static Future<bool> hasEnrolledBiometrics() async {
    try {
      return (await _localAuth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> supportsDeviceAuthentication() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: '確認是你本人後，才能重設 App 解鎖密碼',
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateWithDeviceSecurity() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: '使用手機螢幕鎖定確認身分後，才能重設 App 解鎖密碼',
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  static Future<String?> currentVerifiedEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim();
    if (user == null ||
        user.isAnonymous ||
        !user.emailVerified ||
        email == null ||
        email.isEmpty) {
      return null;
    }
    return email;
  }

  static Future<Duration> resendRemaining({DateTime? now}) async {
    final value = await _storage.read(key: _lastSentAtKey);
    final sentAtMs = int.tryParse(value ?? '');
    if (sentAtMs == null) return Duration.zero;
    final currentTime = now ?? DateTime.now();
    final availableAt =
        DateTime.fromMillisecondsSinceEpoch(sentAtMs).add(resendCooldown);
    return availableAt.isAfter(currentTime)
        ? availableAt.difference(currentTime)
        : Duration.zero;
  }

  static Future<DateTime?> sendEmailVerificationLink() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = await currentVerifiedEmail();
    if (user == null || email == null) return null;
    if (await resendRemaining() > Duration.zero) return null;

    final challenge = _randomChallenge();
    final expiresAt = DateTime.now().add(verificationLifetime);
    final continueUrl = Uri.https(
      _hostingDomain,
      '/app-lock-reset',
      {'challenge': challenge},
    );

    await FirebaseAuth.instance.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: ActionCodeSettings(
        url: continueUrl.toString(),
        handleCodeInApp: true,
        androidPackageName: 'tw.heartsshine.app',
        androidInstallApp: false,
        iOSBundleId: 'com.heartshine.app',
      ),
    );

    await Future.wait([
      _storage.write(key: _pendingEmailKey, value: email),
      _storage.write(key: _pendingUidKey, value: user.uid),
      _storage.write(key: _pendingChallengeKey, value: challenge),
      _storage.write(
        key: _pendingExpiresKey,
        value: expiresAt.millisecondsSinceEpoch.toString(),
      ),
      _storage.write(
        key: _lastSentAtKey,
        value: DateTime.now().millisecondsSinceEpoch.toString(),
      ),
    ]);
    return expiresAt;
  }

  static Future<DateTime?> pendingExpiresAt() async {
    final value = await _storage.read(key: _pendingExpiresKey);
    final milliseconds = int.tryParse(value ?? '');
    return milliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  static Future<AppLockEmailVerificationResult> verifyEmailLink(
    Uri link,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final values = await Future.wait([
        _storage.read(key: _pendingEmailKey),
        _storage.read(key: _pendingUidKey),
        _storage.read(key: _pendingChallengeKey),
        _storage.read(key: _pendingExpiresKey),
      ]);
      final email = values[0]?.trim();
      final pendingUid = values[1];
      final expectedChallenge = values[2];
      final expiresAtMs = int.tryParse(values[3] ?? '');

      if (user == null ||
          email == null ||
          email.isEmpty ||
          pendingUid != user.uid) {
        return const AppLockEmailVerificationResult(
          AppLockEmailVerificationOutcome.userMismatch,
        );
      }
      if (expiresAtMs == null ||
          !DateTime.fromMillisecondsSinceEpoch(expiresAtMs)
              .isAfter(DateTime.now())) {
        return const AppLockEmailVerificationResult(
          AppLockEmailVerificationOutcome.expired,
        );
      }
      if (!FirebaseAuth.instance.isSignInWithEmailLink(link.toString())) {
        return const AppLockEmailVerificationResult(
          AppLockEmailVerificationOutcome.unavailable,
        );
      }
      if (_extractChallenge(link) != expectedChallenge) {
        return const AppLockEmailVerificationResult(
          AppLockEmailVerificationOutcome.invalidLink,
        );
      }

      final credential = EmailAuthProvider.credentialWithLink(
        email: email,
        emailLink: link.toString(),
      );
      final hasEmailProvider = user.providerData
          .any((provider) => provider.providerId == 'password');
      if (hasEmailProvider) {
        await user.reauthenticateWithCredential(credential);
      } else {
        await user.linkWithCredential(credential);
      }
      await clearPendingEmailVerification();
      return const AppLockEmailVerificationResult(
        AppLockEmailVerificationOutcome.success,
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'user-mismatch' ||
          error.code == 'email-already-in-use' ||
          error.code == 'credential-already-in-use') {
        return const AppLockEmailVerificationResult(
          AppLockEmailVerificationOutcome.userMismatch,
        );
      }
      if (error.code == 'invalid-action-code' ||
          error.code == 'expired-action-code' ||
          error.code == 'invalid-credential') {
        return const AppLockEmailVerificationResult(
          AppLockEmailVerificationOutcome.invalidLink,
        );
      }
      return const AppLockEmailVerificationResult(
        AppLockEmailVerificationOutcome.failed,
      );
    } catch (_) {
      return const AppLockEmailVerificationResult(
        AppLockEmailVerificationOutcome.failed,
      );
    }
  }

  static Future<void> clearPendingEmailVerification() async {
    await Future.wait([
      _storage.delete(key: _pendingEmailKey),
      _storage.delete(key: _pendingUidKey),
      _storage.delete(key: _pendingChallengeKey),
      _storage.delete(key: _pendingExpiresKey),
    ]);
  }

  static String? _extractChallenge(Uri link) {
    return _extractChallengeFromUri(link, depth: 0);
  }

  static String? _extractChallengeFromUri(Uri uri, {required int depth}) {
    if (depth > 3) return null;

    final direct = uri.queryParameters['challenge'];
    if (direct != null && direct.isNotEmpty) return direct;

    for (final parameter in [
      'link',
      'continueUrl',
      'continueURL',
      'deep_link_id',
    ]) {
      final nestedText = uri.queryParameters[parameter];
      if (nestedText == null || nestedText.isEmpty) continue;
      final nested = Uri.tryParse(nestedText);
      if (nested == null) continue;
      final challenge = _extractChallengeFromUri(nested, depth: depth + 1);
      if (challenge != null) return challenge;
    }
    return null;
  }

  static String _randomChallenge() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
