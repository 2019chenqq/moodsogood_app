import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

enum AppLockAuthProvider {
  google,
  apple;

  String get label => switch (this) {
        AppLockAuthProvider.google => 'Google',
        AppLockAuthProvider.apple => 'Apple',
      };
}

enum AppLockReauthenticationOutcome {
  success,
  canceled,
  networkError,
  noSignedInUser,
  unsupportedProvider,
  failed,
}

class AppLockReauthenticationResult {
  const AppLockReauthenticationResult(this.outcome);

  final AppLockReauthenticationOutcome outcome;

  bool get succeeded => outcome == AppLockReauthenticationOutcome.success;
}

class AppLockReauthenticationService {
  static List<AppLockAuthProvider> providersFromIds(
    Iterable<String> providerIds,
  ) {
    final ids = providerIds.toSet();
    return [
      if (ids.contains('google.com')) AppLockAuthProvider.google,
      if (ids.contains('apple.com')) AppLockAuthProvider.apple,
    ];
  }

  static Future<List<AppLockAuthProvider>> availableProviders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const [];
    final providers = providersFromIds(
      user.providerData.map((provider) => provider.providerId),
    );
    if (providers.contains(AppLockAuthProvider.apple)) {
      try {
        if (!await SignInWithApple.isAvailable()) {
          providers.remove(AppLockAuthProvider.apple);
        }
      } catch (_) {
        providers.remove(AppLockAuthProvider.apple);
      }
    }
    return providers;
  }

  static Future<AppLockReauthenticationResult> reauthenticate(
    AppLockAuthProvider provider,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const AppLockReauthenticationResult(
        AppLockReauthenticationOutcome.noSignedInUser,
      );
    }

    try {
      final credential = switch (provider) {
        AppLockAuthProvider.google => await _googleCredential(),
        AppLockAuthProvider.apple => await _appleCredential(),
      };
      if (credential == null) {
        return const AppLockReauthenticationResult(
          AppLockReauthenticationOutcome.canceled,
        );
      }

      await user
          .reauthenticateWithCredential(credential)
          .timeout(const Duration(seconds: 30));
      return const AppLockReauthenticationResult(
        AppLockReauthenticationOutcome.success,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        return const AppLockReauthenticationResult(
          AppLockReauthenticationOutcome.canceled,
        );
      }
      return const AppLockReauthenticationResult(
        AppLockReauthenticationOutcome.failed,
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'network-request-failed') {
        return const AppLockReauthenticationResult(
          AppLockReauthenticationOutcome.networkError,
        );
      }
      return const AppLockReauthenticationResult(
        AppLockReauthenticationOutcome.failed,
      );
    } on TimeoutException {
      return const AppLockReauthenticationResult(
        AppLockReauthenticationOutcome.networkError,
      );
    } catch (_) {
      return const AppLockReauthenticationResult(
        AppLockReauthenticationOutcome.failed,
      );
    }
  }

  static Future<AuthCredential?> _googleCredential() async {
    final googleSignIn = GoogleSignIn();
    await googleSignIn.signOut();
    final account = await googleSignIn.signIn();
    if (account == null) return null;

    final authentication = await account.authentication;
    return GoogleAuthProvider.credential(
      accessToken: authentication.accessToken,
      idToken: authentication.idToken,
    );
  }

  static Future<AuthCredential> _appleCredential() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: const [],
      nonce: hashedNonce,
    ).timeout(const Duration(seconds: 30));
    final identityToken = appleCredential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      throw FirebaseAuthException(code: 'invalid-credential');
    }

    return OAuthProvider('apple.com').credential(
      idToken: identityToken,
      accessToken: appleCredential.authorizationCode,
      rawNonce: rawNonce,
    );
  }

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }
}
