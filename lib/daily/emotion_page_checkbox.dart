import 'package:flutter/material.dart';
import 'daily_record_helpers.dart';

/// 新版：勾選 + 分數（0~10）
/// - 未勾選：`value == null`
/// - 勾選：顯示 Slider，分數 0~10（預設 5）
class EmotionPageCheckbox extends StatelessWidget {
  const EmotionPageCheckbox({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onToggleChecked,
    required this.onChangeValue,
  });

  final List<EmotionItem> items;
  final VoidCallback onAdd;
  final Future<void> Function(int index) onRename;
  final void Function(int index) onDelete;
  final void Function(int index, bool checked) onToggleChecked;
  final void Function(int index, int value) onChangeValue;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...List.generate(items.length, (i) {
          final item = items[i];
          final checked = item.value != null;

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
                      Checkbox(
                        value: checked,
                        onChanged: (v) {
                          onToggleChecked(i, v == true);
                        },
                      ),
                      Expanded(
                        child: Text(
                          item.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.info_outline),
                        tooltip: '評分說明',
                        onPressed: () async {
                          // 顯示簡單提醒
                          await showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('分數說明'),
                              content: const Text('0 代表程度低，10 代表程度高'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('知道了'),
                                ),
                              ],
                            ),
                          );
                        },
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

                  if (checked) ...[
                    const SizedBox(height: 8),
                    Text(
                      '0 代表程度低，10 代表程度高',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.7),
                          ),
                    ),
                    Slider(
                      value: (item.value ?? 5).toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      label: '${item.value ?? 5}',
                      onChanged: (v) => onChangeValue(i, v.round()),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('新增情緒項目'),
        ),
      ],
    );
  }
}
