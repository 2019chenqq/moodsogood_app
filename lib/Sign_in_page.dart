import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';


import 'legal_markdown_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    debugPrint('📝 SignInPage loaded - User needs to sign in');
  }

  Future<void> _handleGoogleSignIn() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      // Google Sign-In
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _loading = false);
        return; // 使用者取消
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      // 登入成功後不需手動跳頁，讓 AuthGate 依 authStateChanges 自動切換
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登入失敗：$e')),
      );
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // 背景：清新藍綠漸層
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF72E0D2), // 淺綠藍
                  Color(0xFF4BB0C6), // 藍綠
                ],
              ),
            ),
          ),
          // 柔光圓暈
          Positioned(
            top: -80,
            right: -40,
            child: _blurBall(200, const Color(0x66FFFFFF)),
          ),
          Positioned(
            bottom: -60,
            left: -30,
            child: _blurBall(240, const Color(0x55FFFFFF)),
          ),

          // 內容
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      width: 520,
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 圓形 app icon
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/icons/app_icon.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '心晴 heart shine',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '記錄情緒・睡眠・症狀，讓每天更安心\n一起邁向更好的情緒照護',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.90),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // 登入按鈕
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _loading ? null : _handleGoogleSignIn,
                              icon: _loading
                                  ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                                  : const Icon(Icons.login_rounded),
                              label: Text(_loading ? '正在登入…' : '使用 Google 登入'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                backgroundColor: const Color(0xFF2E8F9E),
                                foregroundColor: Colors.white,
                                elevation: 0,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),
// 低調的條款區
Opacity(
  opacity: 0.85,
  child: Wrap(
    alignment: WrapAlignment.center,
    spacing: 6,
    children: [
      Text(
        '登入即代表同意',
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white),
      ),
      _link('服務條款', () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const LegalMarkdownPage(
            title: '服務條款',
            assetPath: 'assets/legal/心晴_服務條款_zh-TW.md',
          ),
        ));
      }),
      Text('與', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white)),
      _link('隱私權政策', () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const LegalMarkdownPage(
            title: '隱私權政策',
            assetPath: 'assets/legal/心晴_隱私權政策_zh-TW.md',
          ),
        ));
      }),
    ],
  ),
),
                        ],
                      ),
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

  // 小元件：白字的文字按鈕
Widget _link(String text, VoidCallback onTap) {
  return InkWell(
    onTap: onTap,
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            decoration: TextDecoration.underline,
            color: Colors.white, // 你目前底色為深，維持白字
            fontWeight: FontWeight.w600,
          ),
    ),
  );
}
  // 柔光圓形
  Widget _blurBall(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
