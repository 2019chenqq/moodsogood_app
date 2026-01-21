import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../quotes.dart';

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
  late final VideoPlayerController _vc;
  late final Future<void> _initVideoFuture;

  bool _isPlaying = false;
  bool _showQuote = false;
  bool _initialized = false;

  late final String _quote;

 @override
void initState() {
  super.initState();

  _quote = QuotesTitle.randomQuote();

  _vc = VideoPlayerController.asset('assets/UI/fortune_cookie.mp4') // <-- 改成你真正的路徑
    ..setLooping(false);

  _initVideoFuture = _vc.initialize().then((_) {
    debugPrint('✅ video initialized: size=${_vc.value.size}, dur=${_vc.value.duration}');
    if (mounted) setState(() => _initialized = true);
  }).catchError((e, st) {
    debugPrint('❌ video initialize failed: $e');
    debugPrint('$st');
    if (mounted) setState(() => _initialized = false);
  });

  _vc.addListener(_onVideoTick);
}

  void _onVideoTick() {
    final value = _vc.value;
    if (!value.isInitialized || value.duration == Duration.zero) return;

    // 播放到接近結尾 → 顯示紙條
    final isAtEnd = value.position >= value.duration - const Duration(milliseconds: 80);
    if (_isPlaying && isAtEnd && !_showQuote) {
      _vc.pause();
      if (!mounted) return;
      setState(() {
        _showQuote = true;
        _isPlaying = false;
      });
    }
  }

  @override
  void dispose() {
    _vc.removeListener(_onVideoTick);
    _vc.dispose();
    super.dispose();
  }

  Future<void> _onTapCookie() async {
  if (_showQuote) return;

  try {
    debugPrint('🍪 tap cookie');

   // ✅ 等待初始化（避免一直被擋掉）
await _initVideoFuture;
if (!_vc.value.isInitialized) {
  debugPrint('❌ video still not initialized after await');
  return;
}

    setState(() => _isPlaying = true);

    await _vc.seekTo(Duration.zero);
    await _vc.play();

    debugPrint('▶ video play started');
  } catch (e, st) {
    debugPrint('❌ _onTapCookie error: $e');
    debugPrint('$st');

    if (mounted) {
      setState(() => _isPlaying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('動畫載入失敗，請檢查 mp4 資產路徑/宣告')),
      );
    }
  }
}

  void _onTapBackground() {
    // 顯示紙條後，點背景可進入 App（或你想改成點紙條/按鈕也行）
    if (_showQuote) widget.onEnterApp();
  }

  @override
Widget build(BuildContext context) {
  final size = MediaQuery.sizeOf(context);

  return Scaffold(
    body: Stack(
      children: [
        // ===== 背景（霧面）=====
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F172A), // 深藍灰
                  Color(0xFF111827), // 深灰藍
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              color: Colors.black.withOpacity(0.25),
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
                // ===== 幸運餅乾（可點；未初始化先顯示載入中）=====
FutureBuilder<void>(
  future: _initVideoFuture,
  builder: (context, snap) {
    final ready = snap.connectionState == ConnectionState.done &&
        _vc.value.isInitialized;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: ready ? _onTapCookie : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedScale(
            duration: const Duration(milliseconds: 160),
            scale: _isPlaying ? 0.96 : 1.0,
            child: _buildCookieVisual(),
          ),
          if (!ready)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('載入動畫中…', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
        ],
      ),
    );
  },
),

                const SizedBox(height: 18),

                // ===== 紙條（播完才出現；只放一次）=====
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

        // ===== 小提示（未播完前）=====
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
                      color: Colors.white.withOpacity(0.72),
                      letterSpacing: 0.5,
                    ),
              ),
            ),
          ),
        ),

        // =====（可選）紙條出現後才允許「點背景進入 App」=====
        if (_showQuote)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTapBackground,
              child: const SizedBox.shrink(),
            ),
          ),
      ],
    ),
  );
}

  Widget _buildCookieVisual() {
  if (_isPlaying && _vc.value.isInitialized) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: _vc.value.aspectRatio == 0 ? 1 : _vc.value.aspectRatio,
        child: VideoPlayer(_vc),
      ),
    );
  }

  return Image.asset(
    'assets/UI/fortune_cookie.png',
    fit: BoxFit.contain,
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
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            spreadRadius: 0,
            color: Colors.black.withOpacity(0.18),
            offset: const Offset(0, 10),
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
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
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
