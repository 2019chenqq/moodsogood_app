import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/sleep_record.dart';
import 'sleep_record_service.dart';

/// Standalone sleep entry backed only by SleepRecord.
class SleepRecordPage extends StatefulWidget {
  const SleepRecordPage({super.key});

  @override
  State<SleepRecordPage> createState() => _SleepRecordPageState();
}

class _SleepRecordPageState extends State<SleepRecordPage> {
  final _noteController = TextEditingController();
  TimeOfDay? _bedTime;
  TimeOfDay? _sleepStart;
  TimeOfDay? _wakeTime;
  TimeOfDay? _activityWakeTime;
  int? _quality;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final record = await SleepRecordService().get(
        userId: uid,
        date: DateTime.now(),
      );
      if (!mounted || record == null) return;
      setState(() {
        _bedTime = record.bedTime;
        _sleepStart = record.sleepStart;
        _wakeTime = record.wakeTime;
        _activityWakeTime = record.activityWakeTime;
        _quality = record.quality;
        _noteController.text = record.note ?? '';
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法載入睡眠紀錄：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(
    TimeOfDay? current,
    ValueChanged<TimeOfDay> onPicked,
  ) async {
    final value = await showTimePicker(
      context: context,
      initialTime: current ?? TimeOfDay.now(),
    );
    if (value != null && mounted) setState(() => onPicked(value));
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先登入再儲存睡眠紀錄')),
      );
      return;
    }
    final record = SleepRecord(
      date: DateTime.now(),
      bedTime: _bedTime,
      sleepStart: _sleepStart,
      wakeTime: _wakeTime,
      activityWakeTime: _activityWakeTime,
      quality: _quality,
      note: _noteController.text,
    );
    if (!record.hasData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少填寫一項睡眠資料')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await SleepRecordService().save(userId: uid, record: record);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('睡眠紀錄已儲存')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('睡眠紀錄儲存失敗：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('睡眠紀錄')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TimeTile(
                  label: '上床時間',
                  value: _bedTime,
                  onTap: () => _pick(_bedTime, (v) => _bedTime = v),
                ),
                _TimeTile(
                  label: '入睡時間',
                  value: _sleepStart,
                  onTap: () => _pick(_sleepStart, (v) => _sleepStart = v),
                ),
                _TimeTile(
                  label: '醒來時間',
                  value: _wakeTime,
                  onTap: () => _pick(_wakeTime, (v) => _wakeTime = v),
                ),
                _TimeTile(
                  label: '起床時間',
                  value: _activityWakeTime,
                  onTap: () => _pick(
                    _activityWakeTime,
                    (v) => _activityWakeTime = v,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _quality,
                  decoration: const InputDecoration(
                    labelText: '睡眠品質',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var value = 1; value <= 5; value++)
                      DropdownMenuItem(
                        value: value,
                        child: Text('$value / 5'),
                      ),
                  ],
                  onChanged: (value) => setState(() => _quality = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '備註',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? '儲存中…' : '儲存睡眠紀錄'),
                ),
              ],
            ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value?.format(context) ?? '尚未填寫'),
      trailing: const Icon(Icons.schedule),
      onTap: onTap,
    );
  }
}
