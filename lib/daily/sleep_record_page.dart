import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import '../models/daily_record.dart';
import '../models/sleep_record.dart';
import 'daily_record_helpers.dart';
import 'sleep_record_service.dart';
import 'widgets/night_awakening_editor.dart';
import 'widgets/record_date_time_picker.dart';
import 'widgets/sleep_page.dart';

/// Standalone sleep entry backed only by SleepRecord.
class SleepRecordPage extends StatefulWidget {
  const SleepRecordPage({super.key});

  @override
  State<SleepRecordPage> createState() => _SleepRecordPageState();
}

class _SleepRecordPageState extends State<SleepRecordPage> {
  final _medicationNameController = TextEditingController();
  final _medicationDoseController = TextEditingController();

  TimeOfDay? _bedTime;
  TimeOfDay? _sleepStart;
  TimeOfDay? _wakeTime;
  TimeOfDay? _activityWakeTime;
  int? _quality;
  String _note = '';
  final Set<SleepFlag> _flags = {};
  final List<NightAwakeningItem> _nightAwakenings = [];
  final List<NapItem> _naps = [];
  bool _tookSleepMedication = false;
  bool _loading = true;
  bool _saving = false;
  DateTime _recordedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _medicationNameController.dispose();
    _medicationDoseController.dispose();
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
        date: _recordedAt,
      );
      if (!mounted) return;
      if (record == null) {
        setState(() {
          _bedTime = null;
          _sleepStart = null;
          _wakeTime = null;
          _activityWakeTime = null;
          _quality = null;
          _note = '';
          _flags.clear();
          _nightAwakenings.clear();
          _naps.clear();
          _tookSleepMedication = false;
          _medicationNameController.clear();
          _medicationDoseController.clear();
          _loading = false;
        });
        return;
      }
      setState(() {
        _recordedAt = record.date;
        _bedTime = record.bedTime;
        _sleepStart = record.sleepStart;
        _wakeTime = record.wakeTime;
        _activityWakeTime = record.activityWakeTime;
        _quality = record.quality;
        _flags
          ..clear()
          ..addAll(_parseFlags(record.sleepConditions));
        _nightAwakenings
          ..clear()
          ..addAll(record.nightAwakenings);
        _naps
          ..clear()
          ..addAll(record.naps);
        _tookSleepMedication = record.sleepMedication.taken;
        _medicationNameController.text = record.sleepMedication.name ?? '';
        _medicationDoseController.text = record.sleepMedication.dose ?? '';
        _note = record.note ?? '';
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法載入睡眠紀錄：$error')),
        );
      }
    }
  }

  Future<void> _changeDateTime(DateTime value) async {
    final dayChanged = value.year != _recordedAt.year ||
        value.month != _recordedAt.month ||
        value.day != _recordedAt.day;
    setState(() {
      _recordedAt = value;
      if (dayChanged) _loading = true;
    });
    if (dayChanged) await _load();
  }

  Iterable<SleepFlag> _parseFlags(List<String> names) sync* {
    for (final name in names) {
      for (final flag in SleepFlag.values) {
        if (flag.name == name) {
          yield flag;
          break;
        }
      }
    }
  }

  Future<void> _pick(
    TimeOfDay? current,
    ValueChanged<TimeOfDay> onPicked, {
    String? helpText,
  }) async {
    final value = await showTimePicker(
      context: context,
      initialTime: current ?? TimeOfDay.now(),
      helpText: helpText,
      confirmText: '確定',
      cancelText: '取消',
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
      date: _recordedAt,
      bedTime: _bedTime,
      sleepStart: _sleepStart,
      wakeTime: _wakeTime,
      activityWakeTime: _activityWakeTime,
      quality: _quality,
      sleepConditions: _flags.map((flag) => flag.name).toList(),
      nightAwakenings: List.unmodifiable(_nightAwakenings),
      naps: List.unmodifiable(_naps),
      sleepMedication: SleepMedication(
        taken: _tookSleepMedication,
        name: _tookSleepMedication ? _medicationNameController.text : null,
        dose: _tookSleepMedication ? _medicationDoseController.text : null,
      ),
      note: _note,
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

  Future<void> _addNightAwakening() async {
    final item = await showNightAwakeningEditor(context);
    if (item != null && mounted) {
      setState(() => _nightAwakenings.add(item));
    }
  }

  Future<void> _editNightAwakening(int index) async {
    final item = await showNightAwakeningEditor(
      context,
      initial: _nightAwakenings[index],
    );
    if (item != null && mounted) {
      setState(() => _nightAwakenings[index] = item);
    }
  }

  Future<void> _addNap() async {
    final item = await _pickNap();
    if (item != null && mounted) {
      setState(() => _naps.add(item));
    }
  }

  Future<void> _editNap(int index) async {
    final item = await _pickNap(initial: _naps[index]);
    if (item != null && mounted) {
      setState(() => _naps[index] = item);
    }
  }

  Future<NapItem?> _pickNap({NapItem? initial}) async {
    final start = await showTimePicker(
      context: context,
      initialTime: initial?.start ?? TimeOfDay.now(),
      helpText: '小睡開始時間',
      confirmText: '確定',
      cancelText: '取消',
    );
    if (start == null || !mounted) return null;

    final end = await showTimePicker(
      context: context,
      initialTime: initial?.end ?? start,
      helpText: '小睡結束時間',
      confirmText: '確定',
      cancelText: '取消',
    );
    if (end == null) return null;

    if (start.hour == end.hour && start.minute == end.minute) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('開始與結束時間不可相同')),
        );
      }
      return null;
    }
    return NapItem(start: start, end: end);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        title: const Text('睡眠紀錄'),
        backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
        foregroundColor: HealingDesignSystem.adaptiveAppBarForeground(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: RecordDateTimePicker(
                    value: _recordedAt,
                    onChanged: _changeDateTime,
                  ),
                ),
                Expanded(
                  child: SleepPage(
                    sleepTime: _bedTime,
                    estimatedSleepTime: _sleepStart,
                    wakeTime: _activityWakeTime,
                    onPickSleepTime: () => _pick(
                      _bedTime,
                      (value) => _bedTime = value,
                      helpText: '準備睡覺時間',
                    ),
                    onPickEstimatedSleepTime: () => _pick(
                      _sleepStart,
                      (value) => _sleepStart = value,
                      helpText: '自覺入睡時間',
                    ),
                    onPickWakeTime: () => _pick(
                      _activityWakeTime,
                      (value) => _activityWakeTime = value,
                      helpText: '離床活動時間',
                    ),
                    finalWakeTime: _wakeTime,
                    onPickFinalWakeTime: () => _pick(
                      _wakeTime,
                      (value) => _wakeTime = value,
                      helpText: '甦醒時間',
                    ),
                    nightAwakenings: _nightAwakenings,
                    onAddNightAwakening: _addNightAwakening,
                    onEditNightAwakening: _editNightAwakening,
                    onDeleteNightAwakening: (index) =>
                        setState(() => _nightAwakenings.removeAt(index)),
                    legacyMidWakeText: '',
                    flags: _flags,
                    onToggleFlag: (flag) {
                      setState(() {
                        if (_flags.contains(flag)) {
                          _flags.remove(flag);
                        } else {
                          _flags.add(flag);
                        }
                      });
                    },
                    sleepNote: _note,
                    onChangeNote: (value) => setState(() => _note = value),
                    sleepQuality: _quality,
                    onPickValue: () async {},
                    naps: _naps,
                    onAddNap: _addNap,
                    onEditNap: _editNap,
                    onDeleteNap: (index) =>
                        setState(() => _naps.removeAt(index)),
                    tookHypnotic: _tookSleepMedication,
                    onToggleHypnotic: (value) {
                      setState(() {
                        _tookSleepMedication = value;
                        if (!value) {
                          _medicationNameController.clear();
                          _medicationDoseController.clear();
                        }
                      });
                    },
                    hypnoticName: _medicationNameController.text,
                    onChangeHypnoticName: (_) => setState(() {}),
                    hypnoticDose: _medicationDoseController.text,
                    onChangeHypnoticDose: (_) => setState(() {}),
                    hypnoticNameCtrl: _medicationNameController,
                    hypnoticDoseCtrl: _medicationDoseController,
                    onChangeSleepQuality: (value) =>
                        setState(() => _quality = value),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? '儲存中…' : '儲存睡眠紀錄'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
