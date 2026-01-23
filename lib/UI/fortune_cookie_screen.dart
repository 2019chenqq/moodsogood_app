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
  bool _tapLocked = false;

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
  final v = _vc.value;
  if (!v.isInitialized) return;

  if (_isPlaying && v.isCompleted && !_showQuote) {
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

  // ✅ 防止連點造成 seek/play 重入，最常見的卡死原因
  if (_tapLocked) return;
  _tapLocked = true;

  debugPrint('🍪 tap cookie');

  try {
    // 先切到播放狀態（讓 UI 先顯示 VideoPlayer）
    if (mounted) setState(() => _isPlaying = true);

    await _initVideoFuture;
    if (!_vc.value.isInitialized) {
      debugPrint('❌ still not initialized');
      if (mounted) setState(() => _isPlaying = false);
      return;
    }

    // 如果目前已經在播，就不要重播（避免卡）
    if (_vc.value.isPlaying) {
      debugPrint('ℹ️ already playing');
      return;
    }

    await _vc.seekTo(Duration.zero);
    await _vc.play();

    debugPrint('▶ playing...');
  } catch (e, st) {
    debugPrint('❌ play error: $e');
    debugPrint('$st');
    if (mounted) setState(() => _isPlaying = false);
  } finally {
    // ✅ 稍微延遲解鎖，避免連點太快
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _tapLocked = false;
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
    color: const Color(0xFFF6E08E), // 幸運餅乾頁主背景色
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
                // ===== 幸運餅乾（可點；未初始化先顯示載入中）=====
FutureBuilder<void>(
  future: _initVideoFuture,
  builder: (context, snap) {
    final ready = snap.connectionState == ConnectionState.done &&
        _vc.value.isInitialized;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: (ready && !_isPlaying) ? _onTapCookie : null,
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
  color: const Color(0xFF9C7A2F),
  letterSpacing: 0.5,
),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildCookieVisual() {
  final showVideo = _vc.value.isInitialized && (_vc.value.isPlaying || _isPlaying);

  if (showVideo) {
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
