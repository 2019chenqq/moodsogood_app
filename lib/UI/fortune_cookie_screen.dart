import 'dart:ui';
import 'package:flutter/material.dart';
import '../quotes.dart';
import '../analytics_service.dart';

class FortuneCookieScreen extends StatefulWidget {
  const FortuneCookieScreen({
    super.key,
    required this.onEnterApp,
  });

  final VoidCallback onEnterApp;

  @override
  State<FortuneCookieScreen> createState() => _FortuneCookieScreenState();
}

class _FortuneCookieScreenState extends State<FortuneCookieScreen> {
  bool _showQuote = false;

  late final String _quote;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('fortune_cookie_screen');
    _quote = QuotesTitle.randomQuote();
  }

  void _onTapCookie() {
    if (_showQuote) return;
    setState(() => _showQuote = true);
  }

  void _onTapBackground() {
    if (_showQuote) widget.onEnterApp();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      body: GestureDetector(
        onTap: _onTapBackground,
        child: Stack(
          children: [
            // ===== 背景（霧面）=====
            Positioned.fill(
              child: Container(
                color: const Color(0xFFF6E08E),
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(
                  color: const Color(0xFFF6E08E).withOpacity(0.25),
                ),
              ),
            ),

            // ===== 中央內容：餅乾 + 紙條 =====
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: size.width * 0.72,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ===== 幸運餅乾 =====
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _showQuote ? null : _onTapCookie,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 160),
                        scale: _showQuote ? 0.96 : 1.0,
                        child: Image.asset(
                          'assets/UI/fortune_cookie.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ===== 紙條（點擊後才出現）=====
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 260),
                      opacity: _showQuote ? 1 : 0,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        offset: _showQuote ? Offset.zero : const Offset(0, 0.15),
                        child: _showQuote
                            ? _QuoteStrip(
                                text: _quote,
                                onEnter: widget.onEnterApp,
                                showEnterButton: true,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ===== 小提示 =====
            Positioned(
              left: 0,
              right: 0,
              bottom: 36,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _showQuote ? 0 : 1,
                  child: Text(
                    '點一下幸運餅乾',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF9C7A2F),
                          letterSpacing: 0.5,
                          fontFamily: 'Iansui',
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteStrip extends StatelessWidget {
  const _QuoteStrip({
    required this.text,
    required this.onEnter,
    required this.showEnterButton,
  });

  final String text;
  final VoidCallback onEnter;
  final bool showEnterButton;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9EDB7),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE0C86A).withOpacity(0.6),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  height: 1.35,
                  color: const Color(0xFF6B4F1D),
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Iansui',
                ),
          ),
          const SizedBox(height: 10),
          if (showEnterButton)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onEnter,
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('進入 App'),
              ),
            ),
        ],
      ),
    );
  }
}