import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'key_manager.dart';
import 'encryption_service.dart';

class SecureStorageService {
  // 拿掉容易在模擬器出錯的專屬設定，回歸最穩定的預設值
  static const _storage = FlutterSecureStorage();
  
  static const _keyAlias = 'user_aes_encryption_key';
  static const _verifierField = 'encryptionVerifier';
  static const _verifierPlaintext = 'moodsogood-e2e-key-check-v1';
  static const _localVerifierKey = 'e2eVerifier';

  /// 產生「金鑰驗證字串」並存到雲端，用來驗證 PIN 是否推導出同一把金鑰。
  static String buildKeyVerifier(encrypt_lib.Key key) {
    return EncryptionService(key).encryptData(_verifierPlaintext);
  }

  /// 驗證密文 verifier 是否可用目前金鑰正確解開。
  static bool verifyKeyWithVerifier({
    required encrypt_lib.Key key,
    required String verifier,
  }) {
    final plain = EncryptionService(key).tryDecryptData(verifier);
    return plain == _verifierPlaintext;
  }

  /// 📥 存入金鑰 (加入防崩潰與自動修復機制)
  static Future<void> saveKey(encrypt_lib.Key key) async {
    try {
      await _storage.write(key: _keyAlias, value: key.base64);
      print("🔑 [保險箱] 金鑰已成功寫入！");
    } catch (e) {
      print("🚨 [保險箱] 寫入失敗，嘗試刪除後重寫: $e");
      await _storage.delete(key: _keyAlias);
      await _storage.write(key: _keyAlias, value: key.base64);
      print("🛠️ [保險箱] 重寫成功！");
    }
  }

  /// 📤 讀取金鑰 (加入錯誤捕捉)
  static Future<encrypt_lib.Key?> getKey() async {
    try {
      final keyString = await _storage.read(key: _keyAlias);
      if (keyString == null) {
        print("🚨 [保險箱] 裡面是空的！(找不到金鑰)");
        return null;
      }
      print("🔑 [保險箱] 成功讀取金鑰！");
      return encrypt_lib.Key.fromBase64(keyString);
    } catch (e) {
      print("🚨 [保險箱] 讀取時發生嚴重錯誤 (可能金鑰損毀): $e");
      // 遇到錯誤直接回傳 null，讓系統把用戶導回「重新設定密碼」的畫面
      return null;
    }
  }

  /// 🧩 嘗試取得金鑰；若保險箱是空的，會用 PIN + 雲端 salt 自動重建
  static Future<encrypt_lib.Key?> getOrRecoverKey() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('🚨 [保險箱] 無法重建金鑰：目前未登入');
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      // 從安全儲存讀取 E2E PIN（而非明文 SharedPreferences）
      final e2ePin = (await getPin() ?? '').trim();
      final appLockPin = (prefs.getString('appLockPin') ?? '').trim();
      if (e2ePin.isEmpty && appLockPin.isEmpty) {
        print('🚨 [保險箱] 無法重建金鑰：找不到本地 PIN');
        return null;
      }

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

      // verifier 本地沒有時才去雲端抓
      if (verifier.isEmpty) {
        await loadUserDocIfNeeded();
        verifier = (userDoc?.data()?[_verifierField] as String?)?.trim() ?? '';
        if (verifier.isNotEmpty) {
          await prefs.setString(_localVerifierKey, verifier);
        }
      }

      // 先驗證現有本機金鑰，避免誤用舊/錯金鑰造成整頁解密失敗。
      if (existing != null) {
        if (verifier.isEmpty || verifyKeyWithVerifier(key: existing, verifier: verifier)) {
          return existing;
        }

        print('🚨 [保險箱] 現有金鑰與 verifier 不匹配，清除後改走重建流程');
        await deleteKey();
      }

      // 先用本地快取的 salt（避免每次啟動都依賴網路）
      String salt = (prefs.getString('e2eSalt') ?? '').trim();

      // 本地沒有 salt 才去雲端抓
      if (salt.isEmpty) {
        await loadUserDocIfNeeded();
        salt = (userDoc?.data()?['encryptionSalt'] as String?)?.trim() ?? '';

        // 抓到後回寫本地快取
        if (salt.isNotEmpty) {
          await prefs.setString('e2eSalt', salt);
        }
      }

      if (salt.isEmpty) {
        print('🚨 [保險箱] 無法重建金鑰：找不到雲端 salt');
        return null;
      }

      final candidatePins = <String>[];
      if (e2ePin.isNotEmpty) candidatePins.add(e2ePin);
      if (appLockPin.isNotEmpty && appLockPin != e2ePin) {
        candidatePins.add(appLockPin);
      }

      encrypt_lib.Key? recoveredKey;

      // 有 verifier 時，逐一驗證候選 PIN；比對成功才可用。
      if (verifier.isNotEmpty) {
        for (final candidate in candidatePins) {
          final key = KeyManager.deriveKey(candidate, salt);
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
        // 無 verifier 的舊資料只允許 e2ePin，避免誤用 appLockPin 產生錯誤金鑰。
        if (e2ePin.isEmpty) {
          print('🚨 [保險箱] 缺少 e2ePin 且無 verifier，為避免錯誤解密已停止自動重建');
          return null;
        }
        // e2ePin 已從安全儲存讀取，可直接使用
        recoveredKey = KeyManager.deriveKey(e2ePin, salt);
      }

      await saveKey(recoveredKey);

      final verified = await getKey();
      if (verified != null) {
        print('🛠️ [保險箱] 已用 PIN + salt 重建金鑰成功');
      }
      return verified;
    } catch (e) {
      print('🚨 [保險箱] 自動重建金鑰失敗: $e');
      return null;
    }
  }

  /// 🗑️ 刪除金鑰
  static Future<void> deleteKey() async {
    await _storage.delete(key: _keyAlias);
    print("🗑️ [保險箱] 金鑰已銷毀");
  }

  // ============ PIN 安全儲存方法 ============
  static const _pinAlias = 'user_e2e_pin';

  /// 🔒 使用加密安全儲存 PIN
  static Future<void> savePin(String pin) async {
    try {
      await _storage.write(key: _pinAlias, value: pin);
      print("🔑 [保險箱] PIN 已安全儲存");
    } catch (e) {
      print("🚨 [保險箱] PIN 儲存失敗: $e");
      rethrow;
    }
  }

  /// 🔓 讀取已保護的 PIN
  static Future<String?> getPin() async {
    try {
      return await _storage.read(key: _pinAlias);
    } catch (e) {
      print("🚨 [保險箱] 讀取 PIN 失敗: $e");
      return null;
    }
  }

  /// 🗑️ 刪除保存的 PIN
  static Future<void> deletePin() async {
    try {
      await _storage.delete(key: _pinAlias);
      print("🗑️ [保險箱] PIN 已刪除");
    } catch (e) {
      print("🚨 [保險箱] 刪除 PIN 失敗: $e");
    }
  }
}