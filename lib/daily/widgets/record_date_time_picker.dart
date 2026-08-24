import 'package:flutter/material.dart';

class RecordDateTimePicker extends StatelessWidget {
  const RecordDateTimePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final initialDate = value.isAfter(now) ? now : value;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: '選擇紀錄日期',
      confirmText: '確定',
      cancelText: '取消',
    );
    if (picked == null) return;
    onChanged(DateTime(
      picked.year,
      picked.month,
      picked.day,
      value.hour,
      value.minute,
    ));
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
      helpText: '選擇紀錄時間',
      confirmText: '確定',
      cancelText: '取消',
    );
    if (picked == null) return;
    onChanged(DateTime(
      value.year,
      value.month,
      value.day,
      picked.hour,
      picked.minute,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final date = '${value.year}/${value.month.toString().padLeft(2, '0')}/'
        '${value.day.toString().padLeft(2, '0')}';
    final time = '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickDate(context),
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(date),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickTime(context),
            icon: const Icon(Icons.schedule_outlined),
            label: Text(time),
          ),
        ),
      ],
    );
  }
}
