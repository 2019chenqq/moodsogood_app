import 'package:flutter/material.dart';
import '../constants/emotion_scale_guide.dart';

// ============================================================
// Dialog & Picker Functions
// ============================================================

Future<int?> showSliderPicker({
  required BuildContext context,
  required int initial,
  required int min,
  required int max,
  required String title,
}) async {
  int tempValue = initial;

  return showDialog<int>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: tempValue.toDouble(),
                  min: min.toDouble(),
                  max: max.toDouble(),
                  divisions: max - min,
                  label: tempValue.toString(),
                  onChanged: (v) {
                    setState(() => tempValue = v.round());
                  },
                ),
                Text('$tempValue / $max'),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, tempValue),
            child: const Text('確定'),
          ),
        ],
      );
    },
  );
}

Future<String?> showTextDialog(
    BuildContext context, String title, String hint) async {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content:
          TextField(controller: c, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('確定')),
      ],
    ),
  );
}

void showEmotionScaleGuideDialog(BuildContext context, String keyName) {
  final guide = emotionScaleGuides[keyName];
  if (guide == null) return;

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(guide.question),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('0 分代表：', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(guide.zero),
            const SizedBox(height: 12),
            const Text('10 分代表：', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(guide.ten),
            if (guide.isSensitive) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                '如果你此刻覺得自己不安全，請優先尋求身邊可信任的人或緊急協助。',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
