import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart'; // 替換成你的 AuthGate 所在路徑
import 'analytics_service.dart';

class RecoveryKeyDisplayScreen extends StatefulWidget {
  /// 備援金鑰字串，格式為 12 個單字以破折號串接
  /// 例如："MOON-FIRE-TREE-BLUE-JAZZ-WIND-ROSE-GOLD-LAKE-STAR-DAWN-RAIN"
  final String recoveryKey;

  const RecoveryKeyDisplayScreen({
    super.key,
    required this.recoveryKey,
  });

  @override
  State<RecoveryKeyDisplayScreen> createState() =>
      _RecoveryKeyDisplayScreenState();
}

class _RecoveryKeyDisplayScreenState extends State<RecoveryKeyDisplayScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('recovery_key_display_screen');
  }

  bool _savedConfirmed = false;
  bool _riskConfirmed = false;
  bool _copied = false;

  List<String> get _words => widget.recoveryKey.split('-');

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.recoveryKey));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _proceed() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canProceed = _savedConfirmed && _riskConfirmed;

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
                            const Icon(
                              Icons.key_rounded,
                              color: Color(0xFF73E5BE),
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              '備援金鑰',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            // 複製按鈕
                            GestureDetector(
                              onTap: _copyToClipboard,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _copied
                                      ? const Color(0x3373E5BE)
                                      : const Color(0x225FB8D9),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _copied
                                        ? const Color(0xFF73E5BE)
                                        : const Color(0x665FB8D9),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _copied
                                          ? Icons.check_rounded
                                          : Icons.copy_rounded,
                                      color: _copied
                                          ? const Color(0xFF73E5BE)
                                          : const Color(0xFF9BD7EA),
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _copied ? '已複製' : '複製',
                                      style: TextStyle(
                                        color: _copied
                                            ? const Color(0xFF73E5BE)
                                            : const Color(0xFF9BD7EA),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // ── 說明文字 ──
                        Text(
                          '請將以下 12 個單字依序抄寫在紙上，或截圖保存到安全的地方。',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.88),
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── 警告方塊 ──
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
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
                              const Text('⚠️', style: TextStyle(fontSize: 15)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '這是唯一的備份方式。遺失備援金鑰且忘記安全碼，所有加密日記將永久無法還原。',
                                  style: const TextStyle(
                                    color: Color(0xFFFFB6B6),
                                    fontSize: 13,
                                    height: 1.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── 12 個單字格子 ──
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 3.2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _words.length,
                          itemBuilder: (context, i) {
                            return Container(
                              decoration: BoxDecoration(
                                color: const Color(0x1A5FB8D9),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0x4D5FB8D9),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '${i + 1}.',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.45),
                                      fontSize: 11,
                                      fontFamily: 'Iansui',
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    i < _words.length ? _words[i] : '',
                                    style: const TextStyle(
                                      color: Color(0xFF9BD7EA),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Iansui',
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // ── 確認 Checkbox 1：我已抄好 ──
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: const Color(0xFF7DD8FF),
                            checkColor: const Color(0xFF0F1F2B),
                            value: _savedConfirmed,
                            onChanged: (v) =>
                                setState(() => _savedConfirmed = v!),
                            title: Text(
                              '我已截圖或抄下這 12 個備援單字，並保存在安全的地方。',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // ── 確認 Checkbox 2：了解風險 ──
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0x22FF6B6B),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: const Color(0xFFFF8E8E),
                            value: _riskConfirmed,
                            onChanged: (v) =>
                                setState(() => _riskConfirmed = v!),
                            title: const Text(
                              '我了解這是唯一的備份，遺失後系統無法協助還原。',
                              style: TextStyle(
                                color: Color(0xFFFFB6B6),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── 完成按鈕 ──
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: canProceed ? _proceed : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5FB8D9),
                              foregroundColor: const Color(0xFF0C1A23),
                              disabledBackgroundColor: Colors.grey.shade600,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              '我已保存，進入保險箱 →',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
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
