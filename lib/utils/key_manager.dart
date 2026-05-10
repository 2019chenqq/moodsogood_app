import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter/foundation.dart';

// 新增一個頂層 function（compute 需要頂層或 static）
encrypt_lib.Key _deriveKeyIsolate(List<String> args) {
  return KeyManager._deriveKeySync(args[0], args[1]);
}

class KeyManager {
  // 原本的同步邏輯改為私有
  static encrypt_lib.Key _deriveKeySync(String pin, String salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    final params = Pbkdf2Parameters(
      Uint8List.fromList(utf8.encode(salt)),
      200000,
      32,
    );
    pbkdf2.init(params);
    return encrypt_lib.Key(pbkdf2.process(Uint8List.fromList(utf8.encode(pin))));
  }

  /// ✅ 使用 PBKDF2-HMAC-SHA256 將用戶輸入的 6 位數 PIN 碼，轉換成 32 Bytes 的 AES 金鑰
  /// [pin]: 用戶輸入的密碼 (如 "123456")
  /// [salt]: 專屬這個用戶的隨機亂碼 (要存放在 Firebase 上)
  /// 安全性提升：
  /// - 從簡單 SHA-256 迴圈升級到工業標準 PBKDF2
  /// - iteration 數提高到 200,000（GPU 暴力破解成本大幅增加）
  /// - 首次衍生會耗時 1-2 秒（已在 PinSetupScreen 顯示 Loading）
  /// - 在背景隔離線程執行，不會卡住 UI
  static Future<encrypt_lib.Key> deriveKey(String pin, String salt) async {
    return compute(_deriveKeyIsolate, [pin, salt]);
  }

  static String generateSecureSalt() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64UrlEncode(values);
  }
}