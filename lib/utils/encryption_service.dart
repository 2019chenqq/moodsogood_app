import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'dart:convert';
import 'dart:typed_data';

class EncryptionService {
  // 假設我們已經有一把 32 bytes (256-bit) 的金鑰
  // (這把金鑰稍後會從手機安全儲存空間拿出來)
  final encrypt_lib.Key key;

  EncryptionService(this.key);

  /// 🔒 將明文加密成密文 (準備上傳 Firebase)
  /// 回傳格式： "IV的Base64字串:加密內容的Base64字串"
  String encryptData(String plainText) {
    // AES-GCM 標準 IV 長度為 12 bytes（96 bits）
    final iv = encrypt_lib.IV.fromSecureRandom(12);
    final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm));

    // 進行加密
    final encrypted = encrypter.encrypt(plainText, iv: iv);

    // 將 IV 和密文組合在一起，用冒號分隔，方便存進資料庫
    return '${iv.base64}:${encrypted.base64}';
  }

  /// 🔓 將 Firebase 下載的密文還原成明文 (顯示在 App 畫面上)
  String decryptData(String combinedText) {
    final result = tryDecryptData(combinedText);
    if (result != null) return result;

    print('解密失敗: 無法使用目前金鑰解密');
    return '無法解密的資料'; // 舊流程相容：保留既有回傳
  }

  /// 安全解密：成功回傳明文，失敗回傳 null。
  String? tryDecryptData(String combinedText) {
    try {
      // 將字串用冒號拆開，找回 IV 和密文
      final parts = combinedText.split(':');
      if (parts.length != 2) return combinedText; // 格式不對可能不是加密資料

      final ivBytes = base64Decode(parts[0]);
      final encryptedText = encrypt_lib.Encrypted.fromBase64(parts[1]);
      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm));

      // 新格式：優先使用 12 bytes IV 解密
      if (ivBytes.length >= 12) {
        try {
          final iv12 = encrypt_lib.IV(Uint8List.fromList(ivBytes.take(12).toList()));
          return encrypter.decrypt(encryptedText, iv: iv12);
        } catch (_) {
          // fallback to legacy 16-byte IV below
        }
      }

      // 舊格式回退：嘗試以 16 bytes IV 解密，確保舊資料仍可讀
      if (ivBytes.length >= 16) {
        final iv16 = encrypt_lib.IV(Uint8List.fromList(ivBytes.take(16).toList()));
        return encrypter.decrypt(encryptedText, iv: iv16);
      }

      // 最後保底：若 IV 長度非 12/16，仍嘗試使用完整 IV
      final iv = encrypt_lib.IV(Uint8List.fromList(ivBytes));
      return encrypter.decrypt(encryptedText, iv: iv);
    } catch (e) {
      print('解密失敗: $e');
      return null;
    }
  }
}