import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;

class KeyManager {
  
  /// 將用戶輸入的 6 位數 PIN 碼，轉換成 32 Bytes 的 AES 金鑰
  /// [pin]: 用戶輸入的密碼 (如 "123456")
  /// [salt]: 專屬這個用戶的隨機亂碼 (要存放在 Firebase 上)
  static encrypt_lib.Key deriveKey(String pin, String salt) {
    // 1. 將密碼與鹽值結合
    List<int> bytes = utf8.encode(pin + salt);

    // 2. 進行 10,000 次的 SHA-256 雜湊運算 (刻意增加運算成本，防禦暴力破解)
    for (int i = 0; i < 10000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }

    // 3. 轉換成 AES 專用的 Key 格式 (剛好 32 bytes)
    return encrypt_lib.Key(Uint8List.fromList(bytes));
  }
}
String generateSecureSalt() {
  final random = Random.secure();
  final values = List<int>.generate(16, (i) => random.nextInt(256));
  return base64UrlEncode(values);
}