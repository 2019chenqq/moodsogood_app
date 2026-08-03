import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/daily_record.dart';
import '../../utils/date_helper.dart';

Future<NightAwakeningItem?> showNightAwakeningEditor(
  BuildContext context, {
  NightAwakeningItem? initial,
}) async {
  var start = initial?.start ?? TimeOfDay.now();
  TimeOfDay? end = initial?.end;
  var errorText = '';
  final durationController = TextEditingController(
    text: initial?.estimatedDurationMinutes?.toString() ?? '',
  );
  final noteController = TextEditingController(text: initial?.note ?? '');

  final result = await showDialog<NightAwakeningItem>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        Future<void> pickStart() async {
          final picked = await showTimePicker(
            context: context,
            initialTime: start,
          );
          if (picked != null) setDialogState(() => start = picked);
        }

        Future<void> pickEnd() async {
          final picked = await showTimePicker(
            context: context,
            initialTime: end ?? start,
          );
          if (picked != null) {
            setDialogState(() {
              end = picked;
              durationController.clear();
              errorText = '';
            });
          }
        }

        void save() {
          final durationText = durationController.text.trim();
          final duration =
              durationText.isEmpty ? null : int.tryParse(durationText);
          if (durationText.isNotEmpty &&
              (duration == null || duration < 1 || duration > 720)) {
            setDialogState(
              () => errorText = '推估時長請輸入 1～720 分鐘',
            );
            return;
          }
          if (end != null &&
              end!.hour == start.hour &&
              end!.minute == start.minute) {
            setDialogState(() => errorText = '再次睡著時間不能與醒來時間相同');
            return;
          }
          Navigator.of(dialogContext).pop(
            NightAwakeningItem(
              start: start,
              end: end,
              estimatedDurationMinutes: end == null ? duration : null,
              note: noteController.text.trim().isEmpty
                  ? null
                  : noteController.text.trim(),
            ),
          );
        }

        return AlertDialog(
          title: Text(initial == null ? '新增夜間醒來' : '編輯夜間醒來'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.nightlight_outlined),
                  title: const Text('醒來時間（必填）'),
                  trailing: Text(DateHelper.formatTime(start)),
                  onTap: pickStart,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bedtime_outlined),
                  title: const Text('再次睡著時間（選填）'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(end == null ? '未填寫' : DateHelper.formatTime(end)),
                      if (end != null)
                        IconButton(
                          tooltip: '清除再次睡著時間',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setDialogState(() => end = null),
                        ),
                    ],
                  ),
                  onTap: pickEnd,
                ),
                TextField(
                  controller: durationController,
                  enabled: end == null,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '或填推估清醒時長（分鐘）',
                    helperText: '若已填再次睡著時間，將由系統自動計算',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '備註（選填）',
                    hintText: '例如：做夢、上廁所、被聲音吵醒',
                  ),
                ),
                if (errorText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      errorText,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(onPressed: save, child: const Text('儲存')),
          ],
        );
      },
    ),
  );

  durationController.dispose();
  noteController.dispose();
  return result;
}
