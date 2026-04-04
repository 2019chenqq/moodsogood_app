import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'legal_markdown_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _loading = false;
  bool _appleAvailable = false;
  bool _supportsAppleSignIn = false;
  String? _loadingProvider;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('📝 SignInPage loaded - User needs to sign in');
    _prepareAppleSignIn();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;

      if (user != null) {
        debugPrint('✅ SignInPage observed auth success: ${user.uid}');
        setState(() {
          _loading = false;
          _loadingProvider = null;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true)
              .popUntil((route) => route.isFirst);
        });
        return;
      }

      // Keep the loading state controlled by each sign-in flow's try/catch/finally.
      // Resetting it here on null can allow accidental re-entry and duplicate attempts.
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _prepareAppleSignIn() async {
    // Apple ID 登入按鈕在 Apple 平台固定顯示，避免被可用性檢查完全隱藏。
    final isApplePlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (!mounted) return;
    setState(() => _supportsAppleSignIn = isApplePlatform);
    if (!isApplePlatform) return;

    try {
      final available = await SignInWithApple.isAvailable();
      if (!mounted) return;
      setState(() => _appleAvailable = available);
    } catch (_) {
      if (!mounted) return;
      setState(() => _appleAvailable = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadingProvider = 'google';
    });
    try {
      // Google Sign-In
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() {
          _loading = false;
          _loadingProvider = null;
        });
        return; // 使用者取消
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);

      // 登入成功後不需手動跳頁，讓 AuthGate 依 authStateChanges 自動切換
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登入失敗：$e')),
      );
      setState(() {
        _loading = false;
        _loadingProvider = null;
      });
    }
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  Future<void> _handleAppleSignIn() async {
    if (_loading) return;

    if (!_appleAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('此裝置目前無法使用 Apple ID 登入，請確認 iOS Apple ID 與 App 能力設定。'),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _loadingProvider = 'apple';
    });

    var authSucceeded = false;

    try {
      debugPrint('🍎 Apple login start');

      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      debugPrint('🍎 rawNonce generated: $rawNonce');
      debugPrint('🍎 hashed nonce generated: $nonce');

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      ).timeout(const Duration(seconds: 20));

      debugPrint('🍎 Apple credential received');
      debugPrint('🍎 userIdentifier: ${appleCredential.userIdentifier}');
      debugPrint('🍎 email: ${appleCredential.email}');
      debugPrint('🍎 givenName: ${appleCredential.givenName}');
      debugPrint('🍎 familyName: ${appleCredential.familyName}');
      debugPrint(
        '🍎 identityToken exists: ${appleCredential.identityToken != null && appleCredential.identityToken!.isNotEmpty}',
      );
      debugPrint(
        '🍎 authorizationCode exists: ${appleCredential.authorizationCode.isNotEmpty}',
      );

      final identityToken = appleCredential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'apple-signin-failed',
          message: 'Apple identity token is empty.',
        );
      }

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: identityToken,
        accessToken: appleCredential.authorizationCode,
        rawNonce: rawNonce,
      );

      debugPrint('🍎 Firebase OAuth credential created');

      final userCredential = await FirebaseAuth.instance
          .signInWithCredential(oauthCredential)
          .timeout(const Duration(seconds: 20));

      debugPrint(
        '🍎 Firebase credential sign-in success: ${userCredential.user?.uid}',
      );

      authSucceeded = true;

      final givenName = appleCredential.givenName?.trim() ?? '';
      final familyName = appleCredential.familyName?.trim() ?? '';
      final fullName = '$givenName $familyName'.trim();
        final currentDisplayName = userCredential.user?.displayName?.trim() ?? '';

      if (fullName.isNotEmpty &&
          currentDisplayName.isEmpty) {
        await userCredential.user?.updateDisplayName(fullName);
        debugPrint('🍎 Display name updated: $fullName');
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
    } on SignInWithAppleAuthorizationException catch (e) {
      debugPrint('🍎 Apple authorization exception: ${e.code} / ${e.message}');

      if (!mounted) return;

      String message;
      switch (e.code) {
        case AuthorizationErrorCode.canceled:
          message = '你已取消 Apple 登入';
          break;
        case AuthorizationErrorCode.failed:
          message = 'Apple 登入失敗：${e.message ?? '授權失敗'}';
          break;
        case AuthorizationErrorCode.invalidResponse:
          message = 'Apple 回傳資料無效，請稍後再試';
          break;
        case AuthorizationErrorCode.notHandled:
          message = 'Apple 登入要求未被處理';
          break;
        case AuthorizationErrorCode.notInteractive:
          message = '目前無法互動式登入 Apple ID';
          break;
        case AuthorizationErrorCode.unknown:
        default:
          message = 'Apple 登入失敗：${e.message ?? '未知錯誤'}';
          break;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('🍎 FirebaseAuthException code: ${e.code}');
      debugPrint('🍎 FirebaseAuthException message: ${e.message}');

      if (!mounted) return;

      String message;
      switch (e.code) {
        case 'invalid-credential':
          message =
              'Apple 憑證無效：請確認 Apple Sign In 能力、Firebase Apple 供應商設定，並重裝 App 後再試。';
          break;
        case 'missing-or-invalid-nonce':
          message = 'Apple nonce 驗證失敗，請重試；若持續發生請重新安裝 App 並更新到最新版本。';
          break;
        case 'account-exists-with-different-credential':
          message = '此 Email 已綁定其他登入方式，請改用原本方式登入。';
          break;
        case 'network-request-failed':
          message = '網路連線異常，請稍後再試。';
          break;
        case 'apple-signin-failed':
          message = e.message ?? 'Apple identity token 為空';
          break;
        default:
          message = 'Apple 登入失敗：${e.message ?? e.code}';
          break;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on TimeoutException {
      debugPrint('🍎 Apple sign-in timeout');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apple 登入逾時，請稍後再試')),
      );
    } catch (e, st) {
      debugPrint('🍎 Unknown Apple sign-in error: $e');
      debugPrint('$st');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Apple 登入失敗：$e')),
      );
    } finally {
      if (!mounted) return;
      if (!authSucceeded) {
        setState(() {
          _loading = false;
          _loadingProvider = null;
        });
      }
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
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35)),
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
                                'assets/icons/app_logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '心域',
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

                          // 登入按鈕區
                          _authButton(
                            label: '使用 Google 登入',
                            icon: Icons.g_mobiledata_rounded,
                            onTap: _handleGoogleSignIn,
                            loading: _loading && _loadingProvider == 'google',
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0xFF2E8F9E),
                            borderColor: Colors.transparent,
                          ),

                          if (_supportsAppleSignIn) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Divider(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    height: 1,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  child: Text(
                                    '或',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.92),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    height: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _authButton(
                              label: _appleAvailable
                                  ? '使用 Apple ID 登入'
                                  : 'Apple ID 暫時不可用',
                              icon: Icons.apple_rounded,
                              onTap: _handleAppleSignIn,
                              loading: _loading && _loadingProvider == 'apple',
                              foregroundColor: const Color(0xFF111315),
                              backgroundColor: Colors.white,
                              borderColor: Colors.white.withValues(alpha: 0.85),
                            ),
                          ],

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
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: Colors.white),
                                ),
                                _link('服務條款', () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => const LegalMarkdownPage(
                                      title: '服務條款',
                                      assetPath:
                                          'assets/legal/心域_服務條款_zh-TW.md',
                                    ),
                                  ));
                                }),
                                Text('與',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: Colors.white)),
                                _link('隱私權政策', () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => const LegalMarkdownPage(
                                      title: '隱私權政策',
                                      assetPath:
                                          'assets/legal/心域_隱私權政策_zh-TW.md',
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

  Widget _authButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool loading,
    required Color foregroundColor,
    required Color backgroundColor,
    required Color borderColor,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _loading ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foregroundColor,
                    ),
                  )
                else
                  Icon(icon, color: foregroundColor, size: 20),
                const SizedBox(width: 10),
                Text(
                  loading ? '正在登入…' : label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                ),
              ],
            ),
          ),
        ),
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
