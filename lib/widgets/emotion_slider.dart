import 'package:flutter/material.dart';

class EmotionSlider extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String leftIcon;
  final String rightIcon;
  final List<Color> gradientColors;
  final Color? thumbBadgeColor;

  const EmotionSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.leftIcon,
    required this.rightIcon,
    required this.gradientColors,
    this.thumbBadgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),

        Row(
          children: [
            Image.asset(leftIcon, width: 36),

            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 🌈 漸層底條
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(colors: gradientColors),
                    ),
                  ),

                  // 🎚 Slider（只當操作層）
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 10,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: const Color.fromARGB(255, 108, 234, 234),
                      overlayColor: Colors.transparent,
                      thumbShape: NumberThumbShape(value),
                    ),
                    child: Slider(
                      value: value.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      onChanged: (v) => onChanged(v.round()),
                    ),
                  ),
                ],
              ),
            ),

            Image.asset(rightIcon, width: 36),
          ],
        ),
      ],
    );
  }
}

class NumberThumbShape extends SliderComponentShape {
  final int displayValue; 
    NumberThumbShape(this.displayValue);

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(36, 36);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;

    // 藍綠色圓圈
    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? const Color(0xFF6FDAD3)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 15, paint);

    // 中間的數字
    final textPainter = TextPainter(
      text: TextSpan(
        text: displayValue.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: textDirection,
    )..layout();

    final offset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - textPainter.height / 2,
    );

    textPainter.paint(canvas, offset);
  }
}