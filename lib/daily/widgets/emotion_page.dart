import 'package:flutter/material.dart';
import '../../widgets/emotion_slider.dart';
import '../models/emotion_item.dart';

/// 情緒分頁
class EmotionPage extends StatelessWidget {
  const EmotionPage({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onChangeValue,
  });

  final List<EmotionItem> items;
  final VoidCallback onAdd;
  final Future<void> Function(int index) onRename;
  final void Function(int index) onDelete;
  final void Function(int index, int value) onChangeValue;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 🔹 情緒清單（Slider 版）
        ...List.generate(items.length, (i) {
          final item = items[i];
          const Map<String, String> emotionDisplayTextMap = {
            '整體情緒': '今天整體過得還好嗎？',
            '焦慮程度': '今天有感到緊繃或不安嗎？',
            '憂鬱程度': '今天心情有比較低落嗎？',
            '空虛程度': '有一種空空的感覺嗎？',
            '無聊程度': '今天有提不起勁嗎？',
            '難過程度': '今天有比較想哭或委屈嗎？',
            '開心程度': '今天有感到一點點開心嗎？',
            '無望感': '有覺得看不到出口嗎？',
            '孤獨感': '今天有覺得自己被落下嗎？',
            '動力': '今天做事有力氣嗎？',
            '自殺意念': '有出現讓你感到害怕的念頭嗎？',
            '食慾': '今天吃東西還順利嗎？',
            '能量': '今天身體的能量還夠嗎？',
            '活動量': '今天有稍微動一動嗎？',
            '疲倦程度': '今天是不是很累了？',
          };

          const emotionRightIconMap = {
            '整體情緒': 'assets/emotion/overall.png',
            '焦慮程度': 'assets/emotion/anxious.png',
            '憂鬱程度': 'assets/emotion/depression.png',
            '空虛程度': 'assets/emotion/absence.png',
            '無聊程度': 'assets/emotion/boring.png',
            '難過程度': 'assets/emotion/sad.png',
            '開心程度': 'assets/emotion/happy.png',
            '無望感': 'assets/emotion/despair.png',
            '孤獨感': 'assets/emotion/loneliness.png',
            '動力': 'assets/emotion/power.png',
            '自殺意念': 'assets/emotion/自殺意念.png',
            '食慾': 'assets/emotion/食慾.png',
            '能量': 'assets/emotion/energy.png',
            '活動量': 'assets/emotion/活動量.png',
            '疲倦程度': 'assets/emotion/tired.png',
          };

          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          emotionDisplayTextMap[item.name] ?? item.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (i != 0)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => onRename(i),
                        ),
                      if (i != 0)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => onDelete(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 🎚️ 情緒 Slider
                  EmotionSlider(
                    label: item.name,
                    value: item.value ?? 1,
                    onChanged: (v) => onChangeValue(i, v),
                    leftIcon: 'assets/emotion/default.png',
                    rightIcon:
                        emotionRightIconMap[item.name] ?? 'assets/emotion/default.png',
                    gradientColors: const [
                      Color(0xFF9AD0EC),
                      Color(0xFFFFE08A),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        // ➕ 新增情緒
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('新增情緒項目'),
        ),
      ],
    );
  }
}
