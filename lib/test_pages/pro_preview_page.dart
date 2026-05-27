import 'dart:math' as math;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';

import '../analytics_service.dart';

class ProPreviewPage extends StatefulWidget {
  const ProPreviewPage({super.key});

  static const Color _background = Color(0xFFFAFBFF);
  static const Color _ink = Color(0xFF172033);
  static const Color _mutedInk = Color(0xFF667085);
  static const Color _purple = Color(0xFF9184F5);
  static const Color _blue = Color(0xFF5B74F1);
  static const Color _mint = Color(0xFF49C8BB);
  static const Color _gold = Color(0xFFF7B83A);
  static const Color _border = Color(0xFFE7E8F2);

  @override
  State<ProPreviewPage> createState() => _ProPreviewPageState();
}

class _ProPreviewPageState extends State<ProPreviewPage> {
  static const Color _background = ProPreviewPage._background;
  static const Color _blue = ProPreviewPage._blue;
  static const Color _mint = ProPreviewPage._mint;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('pro_preview_page');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
          children: [
            _Header(onBack: () => Navigator.maybePop(context)),
            const SizedBox(height: 26),
            const _HeroCard(),
            const SizedBox(height: 30),
            const _SectionTitle(),
            const SizedBox(height: 22),
            const _FeatureCard(
              icon: Icons.trending_up_rounded,
              iconColors: [Color(0xFFE8E4FF), Color(0xFFD7DBFF)],
              iconColor: _blue,
              title: '近 7 天情緒變化整理',
              description: '協助你看見最近情緒是否有明顯波動、低落或壓力累積。',
            ),
            const _FeatureCard(
              icon: Icons.nightlight_round,
              iconColors: [Color(0xFFE7EEFF), Color(0xFFD9E0FF)],
              iconColor: _blue,
              title: '睡眠與情緒交叉觀察',
              description: '整理睡眠狀態、症狀與情緒分數之間可能出現的關聯。',
            ),
            const _FeatureCard(
              icon: Icons.edit_note_rounded,
              iconColors: [Color(0xFFE0FAF5), Color(0xFFD2F1ED)],
              iconColor: _mint,
              title: '日記主題分析',
              description: '透過 AI 分析日記內容，提取重點主題與情緒脈絡，幫助你更了解自己。',
            ),
            const SizedBox(height: 10),
            _UnlockBanner(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pro 功能目前仍在規劃中。'),
                  ),
                );
              },
            ),
            const SizedBox(height: 26),
            const _FreePlanNote(),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '提醒：AI 分析僅作為自我覺察與紀錄整理輔助，不取代醫師、心理師或其他專業人員的判斷。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                await FirebaseAnalytics.instance.logEvent(
                  name: 'pro_interest_click',
                  parameters: {
                    'source': 'pro_preview_page',
                  },
                );

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已記錄你的興趣，正式 Pro 功能開放後會優先優化這項功能。'),
                  ),
                );
              },
              icon: const Icon(Icons.favorite_outline),
              label: const Text('我想使用這個功能'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text('先回到日記'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;

  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 34),
              color: ProPreviewPage._ink,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              tooltip: '返回',
            ),
          ),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '心域 ',
                style: TextStyle(
                  color: ProPreviewPage._ink,
                  fontSize: 31,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              _GradientText(
                'Pro',
                style: TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _GradientText(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [
          Color(0xFFF19A66),
          Color(0xFF9A82F5),
          Color(0xFF5E77F5),
        ],
      ).createShader(bounds),
      child: Text(text, style: style),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(minHeight: 282),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E0FF)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF8F0FF),
            Color(0xFFEFEFFF),
            Color(0xFFE9EDFF),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7567E8).withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _HeroBackground()),
          const Positioned(
            top: 52,
            right: 18,
            child: _AnalysisIllustration(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 30, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ProBadge(),
                const SizedBox(height: 26),
                const Text(
                  '深入 AI 分析',
                  style: TextStyle(
                    color: ProPreviewPage._ink,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1.12,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 24),
                const SizedBox(
                  width: 218,
                  child: Text(
                    '不只是回饋今天，\n而是幫你整理一段時間內的\n情緒、睡眠、症狀與日記脈絡。',
                    style: TextStyle(
                      color: ProPreviewPage._mutedInk,
                      fontSize: 18,
                      height: 1.62,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: _HeroBenefit(
                          icon: Icons.verified_user_rounded,
                          title: '資料更完整',
                          subtitle: '洞察更精準',
                        ),
                      ),
                      _DividerLine(),
                      Expanded(
                        child: _HeroBenefit(
                          icon: Icons.psychology_rounded,
                          title: 'AI 深度分析',
                          subtitle: '看見真實狀態',
                        ),
                      ),
                      _DividerLine(),
                      Expanded(
                        child: _HeroBenefit(
                          icon: Icons.lock_outline_rounded,
                          title: '隱私安全',
                          subtitle: '安心使用',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBackground extends StatelessWidget {
  const _HeroBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _HeroBackgroundPainter());
  }
}

class _HeroBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final path = Path()
      ..moveTo(size.width * 0.63, 0)
      ..cubicTo(
        size.width * 0.55,
        size.height * 0.18,
        size.width * 0.64,
        size.height * 0.26,
        size.width * 0.55,
        size.height * 0.45,
      )
      ..cubicTo(
        size.width * 0.48,
        size.height * 0.62,
        size.width * 0.60,
        size.height * 0.83,
        size.width,
        size.height * 0.76,
      );
    canvas.drawPath(path, paint);

    canvas.drawCircle(
      Offset(size.width * 0.86, size.height * 0.12),
      9,
      Paint()..color = Colors.white.withValues(alpha: 0.58),
    );
    canvas.drawCircle(
      Offset(size.width * 0.95, size.height * 0.16),
      7,
      Paint()..color = ProPreviewPage._purple.withValues(alpha: 0.62),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFFA78CF7), Color(0xFF6976F4)],
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 21),
          SizedBox(width: 8),
          Text(
            'Pro',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisIllustration extends StatelessWidget {
  const _AnalysisIllustration();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 15,
      child: Container(
        width: 164,
        height: 164,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white),
          boxShadow: [
            BoxShadow(
              color: ProPreviewPage._blue.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: CustomPaint(painter: _ChartCardPainter()),
      ),
    );
  }
}

class _ChartCardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final linePath = Path()
      ..moveTo(size.width * 0.05, size.height * 0.42)
      ..cubicTo(
        size.width * 0.26,
        size.height * 0.18,
        size.width * 0.35,
        size.height * 0.62,
        size.width * 0.55,
        size.height * 0.44,
      )
      ..cubicTo(
        size.width * 0.73,
        size.height * 0.26,
        size.width * 0.78,
        size.height * 0.56,
        size.width * 0.98,
        size.height * 0.16,
      );

    fill
      ..shader = const LinearGradient(
        colors: [Color(0xFFC18BF3), Color(0xFF4E6CF0)],
      ).createShader(Offset.zero & size)
      ..strokeWidth = 7;
    canvas.drawPath(linePath, fill);

    final dotPaint = Paint()..color = const Color(0xFF6575F3);
    canvas.drawCircle(
        Offset(size.width * 0.98, size.height * 0.16), 8, dotPaint);

    final barPaint = Paint()
      ..color = const Color(0xFFDCD7FF)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 15;
    canvas.drawLine(
      Offset(size.width * 0.05, size.height * 0.70),
      Offset(size.width * 0.86, size.height * 0.70),
      barPaint,
    );
    barPaint.color = const Color(0xFFC8BEFF);
    canvas.drawLine(
      Offset(size.width * 0.05, size.height * 0.90),
      Offset(size.width * 0.55, size.height * 0.90),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DividerLine extends StatelessWidget {
  const _DividerLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      color: const Color(0xFFE3E1F4),
    );
  }
}

class _HeroBenefit extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _HeroBenefit({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: ProPreviewPage._purple, size: 25),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ProPreviewPage._ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ProPreviewPage._mutedInk,
                  fontSize: 13,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text(
          '✨ Pro 專屬功能 ✨',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ProPreviewPage._ink,
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 10),
        Text(
          '解鎖更完整的自我探索體驗',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ProPreviewPage._mutedInk,
            fontSize: 16,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final List<Color> iconColors;
  final Color iconColor;
  final String title;
  final String description;

  const _FeatureCard({
    required this.icon,
    required this.iconColors,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ProPreviewPage._border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: iconColors,
              ),
            ),
            child: Icon(icon, color: iconColor, size: 42),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: ProPreviewPage._ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const _MiniProPill(),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: const TextStyle(
                    color: ProPreviewPage._mutedInk,
                    fontSize: 16,
                    height: 1.5,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF596273),
            size: 34,
          ),
        ],
      ),
    );
  }
}

class _MiniProPill extends StatelessWidget {
  const _MiniProPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAE7FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'Pro',
        style: TextStyle(
          color: ProPreviewPage._purple,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _UnlockBanner extends StatelessWidget {
  final VoidCallback onPressed;

  const _UnlockBanner({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFE8C5)),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFCF8), Color(0xFFFFF4DF)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 350;
          final content = Row(
            children: [
              const _CrownIcon(),
              const SizedBox(width: 18),
              const Expanded(child: _UnlockCopy()),
              if (!compact) ...[
                const SizedBox(width: 12),
                _UpgradeButton(onPressed: onPressed),
              ],
            ],
          );

          if (!compact) return content;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              content,
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: _UpgradeButton(onPressed: onPressed),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CrownIcon extends StatelessWidget {
  const _CrownIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFFFF0C7),
      ),
      child: const Icon(
        Icons.workspace_premium_rounded,
        color: ProPreviewPage._gold,
        size: 50,
      ),
    );
  }
}

class _UnlockCopy extends StatelessWidget {
  const _UnlockCopy();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '更多 Pro 功能持續解鎖中',
          style: TextStyle(
            color: ProPreviewPage._ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.25,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '陪你更深入理解自己，成為更好的自己。',
          style: TextStyle(
            color: ProPreviewPage._mutedInk,
            fontSize: 15,
            height: 1.45,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _UpgradeButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _UpgradeButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ).copyWith(
        backgroundColor: WidgetStateProperty.all(Colors.transparent),
      ),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFFA687F5), Color(0xFF5B74F1)],
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 13,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '升級 Pro',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 25,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreePlanNote extends StatelessWidget {
  const _FreePlanNote();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text(
          '目前為免費方案，可免費使用基本功能',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ProPreviewPage._mutedInk,
            fontSize: 14,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '了解更多方案',
              style: TextStyle(
                color: ProPreviewPage._blue,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: ProPreviewPage._blue,
              size: 20,
            ),
          ],
        ),
      ],
    );
  }
}
