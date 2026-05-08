import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;

class KeyManager {
  
  /// ✅ 使用 PBKDF2-HMAC-SHA256 將用戶輸入的 6 位數 PIN 碼，轉換成 32 Bytes 的 AES 金鑰
  /// [pin]: 用戶輸入的密碼 (如 "123456")
  /// [salt]: 專屬這個用戶的隨機亂碼 (要存放在 Firebase 上)
  /// 安全性提升：
  /// - 從簡單 SHA-256 迴圈升級到工業標準 PBKDF2
  /// - iteration 數提高到 200,000（GPU 暴力破解成本大幅增加）
  /// - 首次衍生會耗時 1-2 秒（已在 PinSetupScreen 顯示 Loading）
  static encrypt_lib.Key deriveKey(String pin, String salt) {
    // 使用 PBKDF2-HMAC-SHA256 安全衍生金鑰
    // 參數說明：
    // - HMac(SHA256Digest(), 64): 使用 SHA-256 作為底層 Hash，block size 64
    // - salt: 專屬用戶的隨機鹽值
    // - 200,000: iteration count（足以防禦 GPU 暴力破解）
    // - 32: 輸出金鑰長度（AES-256 需要 32 bytes）
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    final params = Pbkdf2Parameters(
      Uint8List.fromList(utf8.encode(salt)),
      200000, // iteration count
      32,     // key length in bytes
    );
    pbkdf2.process(Uint8List.fromList(utf8.encode(pin)));
    final keyBytes = pbkdf2.process(utf8.encode(pin) as Uint8List);
    return encrypt_lib.Key(keyBytes);
  }

  static String generateSecureSalt() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64UrlEncode(values);
  }
}