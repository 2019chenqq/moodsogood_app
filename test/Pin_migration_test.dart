// 📁 存放位置：test/pin_migration_test.dart
// 執行方式：flutter test test/pin_migration_test.dart
//
// 測試範圍：
//   1. 舊 KDF（SHA-256 × 10,000）與新 KDF（PBKDF2）產生不同金鑰
//   2. verifier 用舊金鑰加密，新金鑰無法解開（確認問題確實存在）
//   3. verifier 用舊金鑰加密，舊金鑰可以解開（遷移的前提成立）
//   4. 遷移後的密文，新金鑰可以正確解密
//   5. _isAlreadyEncrypted() 不被含冒號的明文誤判
//   6. 完整的遷移流程模擬（舊 → 新 → 驗證）

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:pointycastle/export.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── 從主程式複製過來的兩個 KDF，方便獨立測試 ───

/// 舊版 KDF（SHA-256 × 10,000）
encrypt_lib.Key deriveKeyLegacy(String pin, String salt) {
  List<int> bytes = utf8.encode(pin + salt);
  for (int i = 0; i < 10000; i++) {
    bytes = sha256.convert(bytes).bytes;
  }
  return encrypt_lib.Key(Uint8List.fromList(bytes));
}

/// 新版 KDF（PBKDF2-HMAC-SHA256 × 200,000）
encrypt_lib.Key deriveKeyNew(String pin, String salt) {
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  final params = Pbkdf2Parameters(
    Uint8List.fromList(utf8.encode(salt)),
    200000,
    32,
  );
  pbkdf2.init(params);
  return encrypt_lib.Key(pbkdf2.process(Uint8List.fromList(utf8.encode(pin))));
}

// ─── 從 EncryptionService 複製過來的加解密邏輯 ───

String encryptData(encrypt_lib.Key key, String plainText) {
  final iv = encrypt_lib.IV.fromSecureRandom(12);
  final encrypter = encrypt_lib.Encrypter(
    encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm),
  );
  final encrypted = encrypter.encrypt(plainText, iv: iv);
  return '${iv.base64}:${encrypted.base64}';
}

String? tryDecryptData(encrypt_lib.Key key, String combinedText) {
  try {
    final parts = combinedText.split(':');
    if (parts.length != 2) return combinedText;

    final ivBytes = base64Decode(parts[0]);
    final encryptedText = encrypt_lib.Encrypted.fromBase64(parts[1]);
    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm),
    );

    if (ivBytes.length >= 12) {
      try {
        final iv12 = encrypt_lib.IV(Uint8List.fromList(ivBytes.take(12).toList()));
        return encrypter.decrypt(encryptedText, iv: iv12);
      } catch (_) {}
    }

    if (ivBytes.length >= 16) {
      final iv16 = encrypt_lib.IV(Uint8List.fromList(ivBytes.take(16).toList()));
      return encrypter.decrypt(encryptedText, iv: iv16);
    }

    final iv = encrypt_lib.IV(Uint8List.fromList(ivBytes));
    return encrypter.decrypt(encryptedText, iv: iv);
  } catch (e) {
    return null;
  }
}

/// 從 pin_setup_screen.dart 複製的 _isAlreadyEncrypted
bool isAlreadyEncrypted(String text) {
  final parts = text.split(':');
  if (parts.length != 2) return false;
  final base64Pattern = RegExp(r'^[A-Za-z0-9+/=_-]+$');
  return base64Pattern.hasMatch(parts[0]) &&
      base64Pattern.hasMatch(parts[1]) &&
      parts[0].length >= 16;
}

const verifierPlaintext = 'moodsogood-e2e-key-check-v1';

// ─── 測試開始 ───

void main() {
  const testPin  = '123456';
  const testSalt = 'testSaltABCDEFGH';

  group('【測試 1】兩種 KDF 產生不同金鑰', () {
    test('相同 PIN + salt，舊新 KDF 金鑰不一樣', () {
      final oldKey = deriveKeyLegacy(testPin, testSalt);
      final newKey = deriveKeyNew(testPin, testSalt);

      expect(oldKey.base64, isNot(equals(newKey.base64)),
          reason: '升級 KDF 後，同一組 PIN+salt 應產生不同金鑰');
      print('✅ 舊金鑰: ${oldKey.base64.substring(0, 10)}...');
      print('✅ 新金鑰: ${newKey.base64.substring(0, 10)}...');
    });
  });

  group('【測試 2】verifier 相容性（確認問題確實存在）', () {
    test('舊 KDF 產生的 verifier，新 KDF 無法解開', () {
      final oldKey = deriveKeyLegacy(testPin, testSalt);
      final newKey = deriveKeyNew(testPin, testSalt);

      final verifier = encryptData(oldKey, verifierPlaintext);
      final result = tryDecryptData(newKey, verifier);

      expect(result, isNot(equals(verifierPlaintext)),
          reason: '這確認了問題的根本原因：舊 verifier 無法用新 KDF 驗證');
      print('✅ 新金鑰解密結果: $result（預期不是 "$verifierPlaintext"）');
    });

    test('舊 KDF 產生的 verifier，舊 KDF 可以解開', () {
      final oldKey = deriveKeyLegacy(testPin, testSalt);
      final verifier = encryptData(oldKey, verifierPlaintext);
      final result = tryDecryptData(oldKey, verifier);

      expect(result, equals(verifierPlaintext),
          reason: '舊金鑰應能解開自己產生的 verifier，這是遷移的前提');
      print('✅ 舊金鑰解密成功: $result');
    });
  });

  group('【測試 3】遷移流程', () {
    test('遷移後密文，新金鑰可正確解密', () {
      final oldKey = deriveKeyLegacy(testPin, testSalt);
      final newKey = deriveKeyNew(testPin, testSalt);

      final originalText = '今天心情很好，去公園散步了。';
      final oldCipherText = encryptData(oldKey, originalText);

      final plain = tryDecryptData(oldKey, oldCipherText);
      expect(plain, equals(originalText));

      final newCipherText = encryptData(newKey, plain!);
      final result = tryDecryptData(newKey, newCipherText);
      expect(result, equals(originalText));
      print('✅ 遷移後解密: $result');
    });

    test('遷移後，舊金鑰無法解密新密文（確認遷移有效）', () {
      final oldKey = deriveKeyLegacy(testPin, testSalt);
      final newKey = deriveKeyNew(testPin, testSalt);

      final originalText = '私密日記內容';
      final oldCipherText = encryptData(oldKey, originalText);
      final plain = tryDecryptData(oldKey, oldCipherText)!;
      final newCipherText = encryptData(newKey, plain);

      final result = tryDecryptData(oldKey, newCipherText);
      expect(result, isNot(equals(originalText)));
      print('✅ 舊金鑰嘗試解新密文，失敗（預期行為）');
    });
  });

  group('【測試 4】_isAlreadyEncrypted() 判斷正確性', () {
    test('正常加密格式應被識別為已加密', () {
      final key = deriveKeyNew(testPin, testSalt);
      final cipherText = encryptData(key, '測試文字');
      expect(isAlreadyEncrypted(cipherText), isTrue);
    });

    test('含冒號的明文不應被誤判為已加密', () {
      expect(isAlreadyEncrypted('下午 3:30 去看醫生'), isFalse);
      print('✅ "下午 3:30 去看醫生" 被正確識別為明文');
    });

    test('URL 不應被誤判為已加密', () {
      expect(isAlreadyEncrypted('https://example.com'), isFalse);
    });

    test('中文冒號不應被誤判', () {
      expect(isAlreadyEncrypted('他說：你好'), isFalse);
    });

    test('空字串不應被誤判', () {
      expect(isAlreadyEncrypted(''), isFalse);
    });
  });

  group('【測試 5】完整登入遷移模擬', () {
    test('升級前設定 PIN，升級後仍可登入（完整流程）', () {
      final salt = 'randomSaltForThisUser123';
      const userPin = '654321';

      // 第一階段：升級前（舊 App）
      final oldKey = deriveKeyLegacy(userPin, salt);
      final verifier = encryptData(oldKey, verifierPlaintext);
      final diary1 = encryptData(oldKey, '第一篇日記：天氣晴');
      final diary2 = encryptData(oldKey, '第二篇：14:30 去健身');

      // 第二階段：升級後，新 KDF 驗證失敗
      final newKey = deriveKeyNew(userPin, salt);
      final newVerify = tryDecryptData(newKey, verifier);
      expect(newVerify, isNot(equals(verifierPlaintext)),
          reason: '確認問題存在');

      // 改用舊 KDF 驗證成功 → 觸發遷移
      final oldVerify = tryDecryptData(oldKey, verifier);
      expect(oldVerify, equals(verifierPlaintext),
          reason: 'PIN 正確，可以開始遷移');

      // 第三階段：遷移日記
      final plain1 = tryDecryptData(oldKey, diary1);
      final plain2 = tryDecryptData(oldKey, diary2);
      expect(plain1, equals('第一篇日記：天氣晴'));
      expect(plain2, equals('第二篇：14:30 去健身'));

      final migrated1 = encryptData(newKey, plain1!);
      final migrated2 = encryptData(newKey, plain2!);

      // 第四階段：驗證遷移後正常使用
      expect(tryDecryptData(newKey, migrated1), equals('第一篇日記：天氣晴'));
      expect(tryDecryptData(newKey, migrated2), equals('第二篇：14:30 去健身'));

      print('✅ 完整遷移流程通過！');
    });
  });
}