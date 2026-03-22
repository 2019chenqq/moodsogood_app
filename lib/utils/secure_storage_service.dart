import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'key_manager.dart';

class SecureStorageService {
  // 拿掉容易在模擬器出錯的專屬設定，回歸最穩定的預設值
  static const _storage = FlutterSecureStorage();
  
  static const _keyAlias = 'user_aes_encryption_key';

  /// 📥 存入金鑰 (加入防崩潰與自動修復機制)
  static Future<void> saveKey(encrypt_lib.Key key) async {
    try {
      await _storage.write(key: _keyAlias, value: key.base64);
      print("🔑 [保險箱] 金鑰已成功寫入！");
    } catch (e) {
      print("🚨 [保險箱] 寫入失敗，嘗試強制修復: $e");
      // 如果遇到模擬器舊資料殘留導致的 Bug，強制把保險箱炸掉重蓋
      await _storage.deleteAll();
      await _storage.write(key: _keyAlias, value: key.base64);
      print("🛠️ [保險箱] 強制修復並寫入成功！");
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
    final existing = await getKey();
    if (existing != null) return existing;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('🚨 [保險箱] 無法重建金鑰：目前未登入');
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final pin = (prefs.getString('appLockPin') ?? prefs.getString('e2ePin') ?? '').trim();
      if (pin.isEmpty) {
        print('🚨 [保險箱] 無法重建金鑰：找不到本地 PIN');
        return null;
      }

      // 先用本地快取的 salt（避免每次啟動都依賴網路）
      String salt = (prefs.getString('e2eSalt') ?? '').trim();

      // 本地沒有再去雲端抓
      if (salt.isEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        salt = (userDoc.data()?['encryptionSalt'] as String?)?.trim() ?? '';

        // 抓到後回寫本地快取
        if (salt.isNotEmpty) {
          await prefs.setString('e2eSalt', salt);
        }
      }

      if (salt.isEmpty) {
        print('🚨 [保險箱] 無法重建金鑰：找不到雲端 salt');
        return null;
      }

      final recoveredKey = KeyManager.deriveKey(pin, salt);
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
}