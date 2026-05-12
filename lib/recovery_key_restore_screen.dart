import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
 
import '../utils/key_manager.dart';
import '../utils/secure_storage_service.dart';
import 'main.dart'; // 替換成你的 AuthGate 所在路徑
 
class RecoveryKeyRestoreScreen extends StatefulWidget {
  const RecoveryKeyRestoreScreen({super.key});
 
  @override
  State<RecoveryKeyRestoreScreen> createState() =>
      _RecoveryKeyRestoreScreenState();
}
 
class _RecoveryKeyRestoreScreenState
    extends State<RecoveryKeyRestoreScreen> {
  // 12 個輸入格的 controller
  final List<TextEditingController> _controllers =
      List.generate(12, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(12, (_) => FocusNode());
 
  bool _isLoading = false;
  String? _errorMessage;
 
  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }
 
  // 組合用戶輸入的 12 個單字成完整備援金鑰字串
  String get _enteredKey =>
      _controllers.map((c) => c.text.trim().toUpperCase()).join('-');
 
  // 確認 12 格都有填
  bool get _allFilled =>
      _controllers.every((c) => c.text.trim().isNotEmpty);
 
  // 輸入格更新時自動跳到下一格
  void _onWordChanged(int index, String value) {
    setState(() => _errorMessage = null);
 
    // 偵測到空白或破折號時，自動跳下一格
    if (value.contains(' ') || value.contains('-')) {
      _controllers[index].text =
          value.replaceAll(' ', '').replaceAll('-', '').toUpperCase();
      _controllers[index].selection = TextSelection.fromPosition(
        TextPosition(offset: _controllers[index].text.length),
      );
      if (index < 11) {
        _focusNodes[index + 1].requestFocus();
      }
    } else {
      _controllers[index].text = value.toUpperCase();
      _controllers[index].selection = TextSelection.fromPosition(
        TextPosition(offset: _controllers[index].text.length),
      );
    }
    setState(() {});
  }
 
  Future<void> _verify() async {
    if (!_allFilled) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
 
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('用戶未登入');
 
      // 從 Firebase 取得用戶的 salt 與 recoveryKeyHash
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
 
      final salt = (userDoc.data()?['encryptionSalt'] as String?)?.trim() ?? '';
      final storedHash =
          (userDoc.data()?['recoveryKeyHash'] as String?)?.trim() ?? '';
 
      if (salt.isEmpty) {
        throw Exception('找不到加密資料，請確認帳號是否正確。');
      }
 
      if (storedHash.isEmpty) {
        throw Exception('此帳號尚未設定備援金鑰，無法使用此方式還原。');
      }
 
      // 驗證用戶輸入的備援金鑰是否與雲端雜湊吻合
      final inputKey = _enteredKey;
      final isValid = KeyManager.verifyRecoveryKey(inputKey, storedHash);
 
      if (!isValid) {
        setState(() => _errorMessage = '備援金鑰不正確，請確認單字的順序和拼寫。');
        return;
      }
 
      // ✅ 驗證成功 → 用備援金鑰推導 AES 金鑰
      final aesKey = await KeyManager.deriveKeyFromRecoveryKey(inputKey, salt);
 
      // 驗證金鑰是否能解開 verifier（二次確認）
      final verifier =
          (userDoc.data()?['encryptionVerifier'] as String?)?.trim() ?? '';
      if (verifier.isNotEmpty &&
          !SecureStorageService.verifyKeyWithVerifier(
            key: aesKey,
            verifier: verifier,
          )) {
        setState(() => _errorMessage = '備援金鑰驗證失敗，可能資料已損毀，請聯絡客服。');
        return;
      }
 
      // 把重建的金鑰存回保險箱
      await SecureStorageService.saveKey(aesKey);
 
      // 清除本地快取的舊 verifier，讓系統重新從雲端抓取
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('e2eSalt', salt);
 
      if (mounted) {
        // 導向重設 PIN 的提示，讓用戶設定新安全碼
        _showResetPinDialog();
      }
    } catch (e) {
      print('備援金鑰驗證失敗: $e');
      if (mounted) {
        final msg = switch (e.toString()) {
          String s when s.contains('尚未設定備援金鑰') =>
            '此帳號尚未設定備援金鑰，無法使用此方式還原。',
          String s when s.contains('找不到加密資料') =>
            '找不到帳號的加密資料，請確認是否登入正確帳號。',
          String s when s.contains('未登入') => '登入狀態異常，請重新登入。',
          _ => '驗證時發生錯誤，請稍後再試。',
        };
        setState(() => _errorMessage = msg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
 
  void _showResetPinDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E3342),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF73E5BE), size: 24),
            SizedBox(width: 8),
            Text(
              '備援金鑰驗證成功',
              style: TextStyle(color: Colors.white, fontSize: 17),
            ),
          ],
        ),
        content: Text(
          '金鑰已重建完成。\n\n請重新設定一組新的 6 位數安全碼來保護您的日記。',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 14,
            height: 1.6,
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                // 回到 PinSetupScreen 重設新 PIN
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5FB8D9),
                foregroundColor: const Color(0xFF0C1A23),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '重新設定安全碼',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    final filledCount = _controllers.where((c) => c.text.trim().isNotEmpty).length;
 
    return Scaffold(
      body: Stack(
        children: [
          // ── 背景漸層 ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0F1F2B), Color(0xFF0A131B)],
              ),
            ),
          ),
 
          // ── 背景裝飾圓形 ──
          Positioned(
            top: -90, left: -40,
            child: Container(
              width: 220, height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x223D9CC1),
              ),
            ),
          ),
          Positioned(
            bottom: -100, right: -30,
            child: Container(
              width: 260, height: 260,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x224A7B9C),
              ),
            ),
          ),
 
          // ── 主內容 ──
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      color: const Color(0xAA1E3342),
                      border: Border.all(color: const Color(0x66E6F0F7)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
 
                        // ── 標題列 ──
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              '備援金鑰還原',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
 
                        // ── 說明文字 ──
                        Text(
                          '請依序輸入您當初保存的 12 個備援單字。全部填完才能驗證。',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.85),
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 20),
 
                        // ── 進度條 ──
                        Row(
                          children: [
                            Text(
                              '$filledCount / 12',
                              style: const TextStyle(
                                color: Color(0xFF9BD7EA),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: filledCount / 12,
                                  backgroundColor:
                                      const Color(0x335FB8D9),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF5FB8D9),
                                  ),
                                  minHeight: 6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
 
                        // ── 12 個輸入格 ──
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 2.8,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: 12,
                          itemBuilder: (context, i) {
                            final isFilled =
                                _controllers[i].text.trim().isNotEmpty;
                            return Container(
                              decoration: BoxDecoration(
                                color: isFilled
                                    ? const Color(0x1A5FB8D9)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isFilled
                                      ? const Color(0x665FB8D9)
                                      : const Color(0x33FFFFFF),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '${i + 1}.',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.4),
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: TextField(
                                      controller: _controllers[i],
                                      focusNode: _focusNodes[i],
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      onChanged: (v) => _onWordChanged(i, v),
                                      textInputAction: i < 11
                                          ? TextInputAction.next
                                          : TextInputAction.done,
                                      onSubmitted: (_) {
                                        if (i < 11) {
                                          _focusNodes[i + 1].requestFocus();
                                        }
                                      },
                                      style: const TextStyle(
                                        color: Color(0xFF9BD7EA),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'monospace',
                                        letterSpacing: 0.8,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'WORD',
                                        hintStyle: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.2),
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                        counterText: '',
                                      ),
                                      maxLength: 12,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
 
                        // ── 錯誤訊息 ──
                        if (_errorMessage != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x22FF6B6B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0x55FF6B6B),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '❌',
                                  style: TextStyle(fontSize: 14),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: Color(0xFFFFB6B6),
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
 
                        if (_errorMessage != null) const SizedBox(height: 16),
 
                        // ── 驗證按鈕 ──
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed:
                                (_allFilled && !_isLoading) ? _verify : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5FB8D9),
                              foregroundColor: const Color(0xFF0C1A23),
                              disabledBackgroundColor: Colors.grey.shade600,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF0C1A23),
                                    ),
                                  )
                                : Text(
                                    '驗證並還原 ($filledCount/12)',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
 
                        const SizedBox(height: 14),
 
                        // ── 提示：聯絡客服 ──
                        Center(
                          child: Text(
                            '備援金鑰也遺失了？請聯絡客服協助處理。',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12,
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
}