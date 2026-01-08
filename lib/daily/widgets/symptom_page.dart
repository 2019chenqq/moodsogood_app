import 'package:flutter/material.dart';
import '../models/symptom_item.dart';

/// 症狀分頁
class SymptomPage extends StatelessWidget {
  const SymptomPage({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.isPeriod,
    required this.onTogglePeriod,
  });

  final List<SymptomItem> items;
  final VoidCallback onAdd;
  final Future<void> Function(int index) onRename;
  final void Function(int index) onDelete;
  final bool isPeriod;
  final ValueChanged<bool> onTogglePeriod;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = Colors.pinkAccent;
    final activeBg = isDark
        ? Colors.pinkAccent.withValues(alpha: 0.15)
        : Colors.pink.withValues(alpha: 0.1);
    final inactiveColor = isDark ? Colors.pink.shade200 : Colors.pink.shade200;
    final inactiveBg = isDark
        ? const Color(0xFF2A1C20)
        : const Color(0xFFFFF5F7);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. 生理期卡片
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isPeriod
                  ? activeColor
                  : inactiveColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          color: isPeriod ? activeBg : inactiveBg,
          child: SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isPeriod
                    ? Colors.pink.withValues(alpha: 0.08)
                    : Colors.blueGrey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset(
                'assets/icons/粉色水滴.png',
                width: 28,
                height: 28,
                fit: BoxFit.contain,
              ),
            ),
            title: Text(
              isPeriod ? '生理期中 🩸' : '生理期來了嗎？',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isPeriod ? Colors.pink : colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              isPeriod ? '紀錄中...' : '紀錄週期，預測下次經期',
              style: TextStyle(
                color: isPeriod ? Colors.pink.shade300 : Colors.grey,
              ),
            ),
            value: isPeriod,
            onChanged: onTogglePeriod,
          ),
        ),
        const SizedBox(height: 24),
        // 2. 提醒卡
        Card(
          elevation: 0,
          color: const Color(0xFFFFF1CC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.amber.withValues(alpha: 0.35), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.amber.shade700),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('溫柔提醒', style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: 6),
                      Text(
                        '不用很完整，想到什麼寫什麼就好。\n'
                        '也可以先寫一個最明顯的感覺：例如「心悸」「胸悶」「頭痛」。',
                        style: TextStyle(color: Colors.black54, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // 3. 症狀卡列表
        ...List.generate(items.length, (i) {
          final s = items[i];
          final isEmpty = s.name.trim().isEmpty;
          final subtitleText = (i == 0)
              ? '今天身體或心裡，哪裡怪怪的嗎？'
              : (isEmpty ? '點一下可以修改' : null);

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: Colors.black.withValues(alpha: 0.06), width: 1),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                title: Text(
                  isEmpty
                      ? (i == 0 ? '例如：手抖、疲倦、嗜睡…' : '症狀 ${i + 1}')
                      : s.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isEmpty
                        ? Colors.black.withValues(alpha: 0.45)
                        : Colors.black.withValues(alpha: 0.9),
                  ),
                ),
                subtitle: subtitleText == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          subtitleText,
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.45),
                            height: 1.3,
                          ),
                        ),
                      ),
                onTap: () => onRename(i),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete(i),
                ),
              ),
            ),
          );
        }),
        // 4. 新增按鈕
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('新增症狀'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}
