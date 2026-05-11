import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

// 記得匯入我們前面寫好的兩個小幫手
import '../utils/key_manager.dart';
import '../utils/secure_storage_service.dart';
import 'main.dart';
import '../utils/encryption_service.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String _statusMessage = '請輸入 6 位數隱私密碼，以保護您的心理健康紀錄。';

  bool _understandNoRecovery = false;
  bool _understandDifferentPassword = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submitPin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密碼必須剛好是 6 位數字喔！')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('用戶未登入');

      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final userDoc = await userDocRef.get();

      String salt;
      String verifier = '';

      // 🔍 判斷情境：是新用戶還是舊用戶換手機？
      if (userDoc.exists && userDoc.data()!.containsKey('encryptionSalt')) {
        // 【情境 A：舊用戶換新手機】
        // 從 Firebase 抓取他專屬的 Salt (但不抓密碼，因為雲端沒有密碼)
        salt = userDoc.data()!['encryptionSalt'];
        verifier = (userDoc.data()!['encryptionVerifier'] as String?)?.trim() ?? '';
        print('從雲端取得既有的 Salt');
      } else {
        // 【情境 B：新用戶第一次設定】
        // 1. 在手機端隨機產生一組全新的 Salt
        salt = KeyManager.generateSecureSalt();
        // 2. 將這個 Salt 存上 Firebase (注意：這裡絕對沒有上傳 PIN 碼！)
        await userDocRef.set({'encryptionSalt': salt}, SetOptions(merge: true));
        print('產生全新 Salt 並上傳至雲端');
      }

      // 🔐 核心加密轉換 (利用我們寫好的 KeyManager)
      // 使用 PBKDF2-HMAC-SHA256（200,000 次迭代），Loading 屬正常現象
      final aesKey = await KeyManager.deriveKey(pin, salt);

      if (verifier.isNotEmpty &&
          !SecureStorageService.verifyKeyWithVerifier(
            key: aesKey,
            verifier: verifier,
          )) {
        // 新 KDF 對不上 → 試試舊 KDF（SHA-256 × 10,000）
        final oldKey = _deriveKeyLegacy(pin, salt);
        final oldKeyMatches = SecureStorageService.verifyKeyWithVerifier(
          key: oldKey,
          verifier: verifier,
        );

        if (oldKeyMatches) {
          // ✅ 舊 KDF 正確 → 自動把所有舊日記用新金鑰重新加密
          print('⚠️ 偵測到舊 KDF，開始自動遷移...');
          await _migrateFromLegacyKey(user.uid, oldKey, aesKey);
          // aesKey 繼續往下用，流程不中斷
        } else {
          // 新舊 KDF 都對不上 → 才是真的密碼錯誤
          throw Exception('PIN 驗證失敗：與既有加密資料不匹配');
        }
      }

      // 🧷 使用安全儲存保存 PIN（而非明文 SharedPreferences）
      await SecureStorageService.savePin(pin);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('e2eSalt', salt);
      await prefs.setBool('e2eConfigured', true);

      // 確保雲端存在 verifier，供未來重裝/換機時做金鑰正確性檢查。
      final verifierToSave = SecureStorageService.buildKeyVerifier(aesKey);
      await userDocRef.set({
        'encryptionVerifier': verifierToSave,
      }, SetOptions(merge: true));
      await prefs.setString('e2eVerifier', verifierToSave);

      // 📥 把算出來的 AES 金鑰鎖進手機的硬體保險箱
      await SecureStorageService.saveKey(aesKey);

      // ✅ 寫入後立即驗證一次，避免後續流程拿不到金鑰
      final storedKey = await SecureStorageService.getKey();
      if (storedKey == null) {
        throw Exception('金鑰寫入失敗，請再試一次');
      }

      await _encryptOldData(user.uid, aesKey);

      // 🎉 成功！導航到 App 的首頁或日記列表頁
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保險箱解鎖成功！')),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }

    } catch (e) {
      print('設定密碼發生錯誤: $e');
      if (mounted) {
        final message = switch (e.toString()) {
          String s when s.contains('PIN 驗證失敗') => '密碼與原本設定的不同，請重新確認。',
          String s when s.contains('未登入')       => '登入狀態異常，請重新登入。',
          String s when s.contains('金鑰寫入失敗') => '裝置安全儲存異常，請重新嘗試。',
          _                                        => '發生未知錯誤，請稍後再試。',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isAlreadyEncrypted(String text) {
    // 加密格式為兩段 base64 字串以冒號分隔：iv:ciphertext
    final parts = text.split(':');
    if (parts.length != 2) return false;

    final base64Pattern = RegExp(r'^[A-Za-z0-9+/=_-]+$');
    return base64Pattern.hasMatch(parts[0]) &&
        base64Pattern.hasMatch(parts[1]) &&
        parts[0].length >= 16; // IV 至少 12 bytes，base64 至少約 16 字元
  }

  // 舊版 KDF（只用來遷移，不對外開放）
  encrypt_lib.Key _deriveKeyLegacy(String pin, String salt) {
    List<int> bytes = utf8.encode(pin + salt);
    for (int i = 0; i < 10000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return encrypt_lib.Key(Uint8List.fromList(bytes));
  }

  // 把所有舊日記從舊金鑰重新加密成新金鑰
  Future<void> _migrateFromLegacyKey(
    String uid,
    encrypt_lib.Key oldKey,
    encrypt_lib.Key newKey,
  ) async {
    final oldService = EncryptionService(oldKey);
    final newService = EncryptionService(newKey);

    final diariesRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('diary');

    final snapshot = await diariesRef.get();
    final fieldsToMigrate = [
      'title', 'content', 'themeSong', 'highlight',
      'metaphor', 'conceited', 'proudOf', 'selfCare'
    ];

    final batch = FirebaseFirestore.instance.batch();

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final updates = <String, dynamic>{};

      for (final field in fieldsToMigrate) {
        final text = (data[field] ?? '') as String;
        if (text.isEmpty) continue;

        // 用舊金鑰解密，再用新金鑰加密
        final plain = oldService.tryDecryptData(text);
        if (plain != null && plain != text) {
          updates[field] = newService.encryptData(plain);
        }
      }

      if (updates.isNotEmpty) {
        batch.update(doc.reference, updates);
      }
    }

    await batch.commit();
    print('✅ 遷移完成：${snapshot.docs.length} 篇日記已升級到新 KDF');
  }

// 🧹 背景大掃除：把 Firebase 上原本是明文的舊日記「所有欄位」全部加密
  Future<void> _encryptOldData(String uid, encrypt_lib.Key key) async { 
    try {
      print('開始為舊資料進行全面加密升級...');
      
      final encryptionService = EncryptionService(key);

      // 注意：確定你的資料表叫做 'diary'
      final diariesRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('diary'); 

      final snapshot = await diariesRef.get();

      // 📝 這裡列出你所有需要加密的「文字欄位」名稱
      final fieldsToEncrypt = [
        'title', 
        'content', 
        'themeSong', 
        'highlight', 
        'metaphor', 
        'conceited', 
        'proudOf', 
        'selfCare'
      ];

      // 迴圈檢查每一篇舊日記
      for (var doc in snapshot.docs) {
        final data = doc.data();
        bool needsUpdate = false;
        Map<String, dynamic> updates = {}; // 用來收集需要更新的加密欄位
        
        // 逐一檢查每一個需要加密的欄位
        for (String field in fieldsToEncrypt) {
          if (data.containsKey(field)) {
            final oldText = (data[field] ?? '') as String;
            
            // 如果裡面有文字，而且還沒有被加密格式識別
            if (oldText.isNotEmpty && !_isAlreadyEncrypted(oldText)) {
              // 把明文加密成亂碼，並放進更新包裡
              updates[field] = encryptionService.encryptData(oldText);
              needsUpdate = true;
            }
          }
        }

        // 如果這篇日記有任何欄位被加密了，就整包推上 Firebase 更新
        if (needsUpdate) {
          updates['isEncrypted'] = true; // 加上標籤
          await doc.reference.update(updates);
          print('🔐 全面加密了一篇舊日記！ID: ${doc.id}');
        }
      }
      print('✨ 所有舊資料全面加密升級完成！');
    } catch (e) {
      print('舊資料加密失敗: $e');
    }
  }

  Widget _buildSafeDial(int pinLength) {
    final turns = (_isLoading ? 2.2 : 0.0) + (pinLength * 0.07);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: turns),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Transform.rotate(
          angle: value * 2 * pi,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE6EEF5), Color(0xFF95AABC)],
                  ),
                  border: Border.all(color: const Color(0xFFF5FAFF), width: 1.4),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 14,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
              ),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF607D94), Color(0xFF2E4355)],
                  ),
                  border: Border.all(color: const Color(0xFFB6C8D6), width: 1.2),
                ),
                child: const Icon(Icons.lock_rounded, color: Colors.white, size: 42),
              ),
              ...List.generate(8, (i) {
                final angle = i * (pi / 4);
                return Transform.translate(
                  offset: Offset(cos(angle) * 62, sin(angle) * 62),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFD8E4EE),
                      border: Border.all(color: const Color(0xFFA6B8C7)),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPinBars(int pinLength) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final active = index < pinLength;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 24,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: active
                ? const Color(0xFF73E5BE)
                : const Color(0xFF9AB1C0).withValues(alpha: 0.35),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pinLength = _pinController.text.trim().length;
    final canSubmit = _understandNoRecovery && _understandDifferentPassword && !_isLoading;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0F1F2B), Color(0xFF0A131B)],
              ),
            ),
          ),
          Positioned(
            top: -90,
            left: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x223D9CC1),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -30,
            child: Container(
              width: 260,
              height: 260,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x224A7B9C),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      color: const Color(0xAA1E3342),
                      border: Border.all(color: const Color(0x66E6F0F7)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
  onPressed: () {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      FirebaseAuth.instance.signOut();
    }
  },
  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
),
                            const SizedBox(width: 8),
                            const Text(
                              '設定保險箱安全碼',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Center(child: _buildSafeDial(pinLength)),
                        const SizedBox(height: 16),
                        const Center(
                          child: Text(
                            '打造您的專屬保險箱',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _statusMessage,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.9),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _buildPinBars(pinLength),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _pinController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: (_) => setState(() {}),
                          maxLength: 6,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white, letterSpacing: 3),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.1),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0x66EAF2F8)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0x66EAF2F8)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0xFF9BD7EA), width: 1.3),
                            ),
                            labelText: '請設定 6 位數安全碼 (PIN)',
                            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.86)),
                            prefixIcon: const Icon(Icons.dialpad_rounded, color: Colors.white),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: const Color(0xFF7DD8FF),
                            checkColor: const Color(0xFF0F1F2B),
                            value: _understandDifferentPassword,
                            onChanged: (value) => setState(() => _understandDifferentPassword = value!),
                            title: Text(
                              '我了解這與帳號登入密碼不同，這是專門用來解鎖日記的安全碼。',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0x22FF6B6B),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: const Color(0xFFFF8E8E),
                            value: _understandNoRecovery,
                            onChanged: (value) => setState(() => _understandNoRecovery = value!),
                            title: const Text(
                              '我了解若遺失此安全碼，系統客服也無法復原任何加密資料。',
                              style: TextStyle(
                                color: Color(0xFFFFB6B6),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: canSubmit ? _submitPin : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5FB8D9),
                              foregroundColor: const Color(0xFF0C1A23),
                              disabledBackgroundColor: Colors.grey.shade500,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text(
                                    '確認並啟用保險箱',
                                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} // 這是 _PinSetupScreenState 的結尾大括號