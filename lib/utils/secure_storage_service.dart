import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'key_manager.dart';
import 'encryption_service.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  static const _keyAlias = 'user_aes_encryption_key';
  static const _pinAlias = 'user_e2e_pin';
  static const _legacyAppLockRecoveryPinAlias =
      'legacy_app_lock_pin_for_e2e_recovery';
  static const _verifierField = 'encryptionVerifier';
  static const _verifierPlaintext = 'moodsogood-e2e-key-check-v1';
  static const _localVerifierKey = 'e2eVerifier';
  static const _recoveryWrappedKeyField = 'recoveryWrappedKey';

  // ─────────────────────────────────────────
  //  金鑰驗證工具
  // ─────────────────────────────────────────

  static String buildKeyVerifier(encrypt_lib.Key key) {
    return EncryptionService(key).encryptData(_verifierPlaintext);
  }

  static bool verifyKeyWithVerifier({
    required encrypt_lib.Key key,
    required String verifier,
  }) {
    final plain = EncryptionService(key).tryDecryptData(verifier);
    return plain == _verifierPlaintext;
  }

  // ─────────────────────────────────────────
  //  AES 金鑰讀寫
  // ─────────────────────────────────────────

  static Future<void> saveKey(encrypt_lib.Key key) async {
    try {
      await _storage.write(key: _keyAlias, value: key.base64);
      print('🔑 [保險箱] 金鑰已成功寫入！');
    } catch (e) {
      print('🚨 [保險箱] 寫入失敗，嘗試刪除後重寫: $e');
      await _storage.delete(key: _keyAlias);
      await _storage.write(key: _keyAlias, value: key.base64);
      print('🛠️ [保險箱] 重寫成功！');
    }
  }

  static Future<encrypt_lib.Key?> getKey() async {
    try {
      final keyString = await _storage.read(key: _keyAlias);
      if (keyString == null) {
        print('🚨 [保險箱] 裡面是空的！(找不到金鑰)');
        return null;
      }
      print('🔑 [保險箱] 成功讀取金鑰！');
      return encrypt_lib.Key.fromBase64(keyString);
    } catch (e) {
      print('🚨 [保險箱] 讀取時發生嚴重錯誤 (可能金鑰損毀): $e');
      return null;
    }
  }

  static Future<void> deleteKey() async {
    await _storage.delete(key: _keyAlias);
    print('🗑️ [保險箱] 金鑰已銷毀');
  }

  // ─────────────────────────────────────────
  //  PIN 讀寫
  // ─────────────────────────────────────────

  static Future<void> savePin(String pin) async {
    try {
      await _storage.write(key: _pinAlias, value: pin);
      print('🔑 [保險箱] PIN 已安全儲存');
    } catch (e) {
      print('🚨 [保險箱] PIN 儲存失敗: $e');
      rethrow;
    }
  }

  static Future<String?> getPin() async {
    try {
      return await _storage.read(key: _pinAlias);
    } catch (e) {
      print('🚨 [保險箱] 讀取 PIN 失敗: $e');
      return null;
    }
  }

  static Future<void> deletePin() async {
    try {
      await _storage.delete(key: _pinAlias);
      print('🗑️ [保險箱] PIN 已刪除');
    } catch (e) {
      print('🚨 [保險箱] 刪除 PIN 失敗: $e');
    }
  }

  static Future<void> saveLegacyAppLockRecoveryPin(String pin) async {
    await _storage.write(key: _legacyAppLockRecoveryPinAlias, value: pin);
  }

  static Future<String?> getLegacyAppLockRecoveryPin() {
    return _storage.read(key: _legacyAppLockRecoveryPinAlias);
  }

  static Future<void> deleteLegacyAppLockRecoveryPin() {
    return _storage.delete(key: _legacyAppLockRecoveryPinAlias);
  }

  // ─────────────────────────────────────────
  //  備援金鑰雜湊（新增）
  // ─────────────────────────────────────────

  /// 將備援金鑰的 SHA-256 雜湊儲存到 Firebase。
  /// 只存雜湊，不存明文，即使 Firebase 被洩漏也無法反推原始單字。
  static Future<void> saveRecoveryKeyHash({
    required String uid,
    required String recoveryKey,
  }) async {
    final hash = KeyManager.hashRecoveryKey(recoveryKey);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'recoveryKeyHash': hash}, SetOptions(merge: true));
    print('🔑 [保險箱] 備援金鑰雜湊已存入 Firebase');
  }

  /// 使用 recoveryKey 派生出的 KEK 加密「原始 AES key.base64」後，
  /// 儲存到 users/{uid}.recoveryWrappedKey。
  static Future<void> saveRecoveryWrappedKey({
    required String uid,
    required String recoveryKey,
    required String salt,
    required encrypt_lib.Key aesKey,
  }) async {
    final recoveryKeyEncryptionKey =
        await KeyManager.deriveKeyFromRecoveryKey(recoveryKey, salt);
    final wrappedKey =
        EncryptionService(recoveryKeyEncryptionKey).encryptData(aesKey.base64);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({_recoveryWrappedKeyField: wrappedKey}, SetOptions(merge: true));

    print('🔐 [保險箱] recoveryWrappedKey 已存入 Firebase');
  }

  /// 使用 recoveryKey 解開 users/{uid}.recoveryWrappedKey，回復原始 AES key。
  static Future<encrypt_lib.Key?> recoverOriginalAesKeyFromRecoveryKey({
    required String recoveryKey,
    required String salt,
    required String wrappedKey,
  }) async {
    final recoveryKeyEncryptionKey =
        await KeyManager.deriveKeyFromRecoveryKey(recoveryKey, salt);
    final decryptedBase64 =
        EncryptionService(recoveryKeyEncryptionKey).tryDecryptData(wrappedKey);

    if (decryptedBase64 == null || decryptedBase64.isEmpty) {
      return null;
    }

    try {
      return encrypt_lib.Key.fromBase64(decryptedBase64);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────
  //  金鑰自動重建（換機/重裝時使用）
  // ─────────────────────────────────────────

  static Future<encrypt_lib.Key?> getOrRecoverKey() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('🚨 [保險箱] 無法重建金鑰：目前未登入');
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final e2ePin = (await getPin() ?? '').trim();
      final legacySecureAppLockPin =
          (await getLegacyAppLockRecoveryPin() ?? '').trim();
      final legacyPreferenceAppLockPin =
          (prefs.getString('appLockPin') ?? '').trim();

      final existing = await getKey();
      String verifier = (prefs.getString(_localVerifierKey) ?? '').trim();

      DocumentSnapshot<Map<String, dynamic>>? userDoc;
      Future<void> loadUserDocIfNeeded() async {
        if (userDoc != null) return;
        userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
      }

      if (verifier.isEmpty) {
        await loadUserDocIfNeeded();
        verifier = (userDoc?.data()?[_verifierField] as String?)?.trim() ?? '';
        if (verifier.isNotEmpty) {
          await prefs.setString(_localVerifierKey, verifier);
        }
      }

      if (existing != null) {
        if (verifier.isEmpty ||
            verifyKeyWithVerifier(key: existing, verifier: verifier)) {
          return existing;
        }
        print('🚨 [保險箱] 現有金鑰與 verifier 不匹配，清除後改走重建流程');
        await deleteKey();
      }

      String salt = (prefs.getString('e2eSalt') ?? '').trim();
      if (salt.isEmpty) {
        await loadUserDocIfNeeded();
        salt = (userDoc?.data()?['encryptionSalt'] as String?)?.trim() ?? '';
        if (salt.isNotEmpty) await prefs.setString('e2eSalt', salt);
      }

      if (salt.isEmpty) {
        print('🚨 [保險箱] 無法重建金鑰：找不到雲端 salt');
        return null;
      }

      final candidatePins = <String>[];
      if (e2ePin.isNotEmpty) candidatePins.add(e2ePin);
      if (legacySecureAppLockPin.isNotEmpty &&
          !candidatePins.contains(legacySecureAppLockPin)) {
        candidatePins.add(legacySecureAppLockPin);
      }
      if (legacyPreferenceAppLockPin.isNotEmpty &&
          !candidatePins.contains(legacyPreferenceAppLockPin)) {
        candidatePins.add(legacyPreferenceAppLockPin);
      }

      if (candidatePins.isEmpty) {
        print('🚨 [保險箱] 無法重建金鑰：找不到本地 PIN');
        return null;
      }

      encrypt_lib.Key? recoveredKey;

      if (verifier.isNotEmpty) {
        for (final candidate in candidatePins) {
          final key = await KeyManager.deriveKey(candidate, salt);
          if (verifyKeyWithVerifier(key: key, verifier: verifier)) {
            recoveredKey = key;
            break;
          }
        }
        if (recoveredKey == null) {
          print('🚨 [保險箱] 金鑰驗證失敗：PIN 與歷史加密資料不匹配');
          return null;
        }
      } else {
        if (e2ePin.isEmpty) {
          print('🚨 [保險箱] 缺少 e2ePin 且無 verifier，停止自動重建');
          return null;
        }
        recoveredKey = await KeyManager.deriveKey(e2ePin, salt);
      }

      await saveKey(recoveredKey);
      final verified = await getKey();
      if (verified != null) {
        await deleteLegacyAppLockRecoveryPin();
        print('🛠️ [保險箱] 已用 PIN + salt 重建金鑰成功');
      }
      return verified;
    } catch (e) {
      print('🚨 [保險箱] 自動重建金鑰失敗: $e');
      return null;
    }
  }
}
