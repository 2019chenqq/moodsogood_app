import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics_service.dart';
import '../utils/health_data_encryption_service.dart';
import 'medication_local_db.dart';
import 'medication_checkin_schedule_resolver.dart';
import 'medication_reminder_service.dart';

class MedicationCheckinPage extends StatefulWidget {
  const MedicationCheckinPage({super.key});

  @override
  State<MedicationCheckinPage> createState() => _MedicationCheckinPageState();
}

class _MedicationCheckinPageState extends State<MedicationCheckinPage> {
  static const List<String> _slotOrder = [
    '早上',
    '中午',
    '下午',
    '晚上',
    '睡前',
    '未設定',
    '需要時',
  ];

  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  bool _statsLoading = true;

  _StatsRange _statsRange = _StatsRange.week;
  List<_DailyAdherence> _stats7Days = [];
  List<_DailyAdherence> _stats30Days = [];
  int _targetStreakDays = 0;
  String _mostMissedSlotThisWeek = '—';
  Map<String, TimeOfDay> _slotTimes = {};
  bool _reminderSettingsExpanded = false;

  List<_CheckinItem> _items = [];
  Map<String, _CheckinStatus> _statusByKey = {};
  Map<String, DateTime> _statusAt = {};
  Map<String, double> _actualAmountByKey = {};
  Map<String, List<DateTime>> _prnEventsByKey = {};

  @override
  void initState() {
    super.initState();
    _loadSlotTimes();
    _loadData();
    AnalyticsService.logPage('medication_checkin_page');
  }

  String _docId(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y$m$day';
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _startOfWeek(DateTime d) {
    final date = _dateOnly(d);
    final diff = date.weekday - DateTime.monday;
    return date.subtract(Duration(days: diff));
  }

  String _itemKey(_CheckinItem item) => '${item.medId}::${item.slot}';

  String _slotFromKey(String key) {
    final split = key.split('::');
    return split.length == 2 ? split.last : '';
  }

  bool _isPrnKey(String key) => _slotFromKey(key) == '需要時';

  List<DateTime> _parseDateList(dynamic raw) {
    if (raw is! List) return <DateTime>[];
    final out = <DateTime>[];
    for (final v in raw) {
      if (v is Timestamp) {
        out.add(v.toDate());
      } else if (v is String) {
        final d = DateTime.tryParse(v);
        if (d != null) out.add(d);
      }
    }
    out.sort();
    return out;
  }

  DateTime? _parseAnyDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _loadSlotTimes() async {
    final times = await MedicationReminderService.getAllSlotTimes();
    if (!mounted) return;
    setState(() => _slotTimes = times);
  }

  Future<void> _pickReminderTime(String slot) async {
    final initial = _slotTimes[slot] ??
        MedicationReminderService.kSlotTimes[slot] ??
        const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;

    setState(() => _saving = true);
    try {
      await MedicationReminderService.setSlotTime(slot, picked);
      final count =
          await MedicationReminderService.syncDailyRemindersForActiveMeds();
      if (!mounted) return;
      setState(() => _slotTimes[slot] = picked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('已更新「$slot」提醒時間為 ${_fmtTime(picked)}（重建 $count 個時段提醒）')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新提醒時間失敗，請稍後再試')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _ensureFixedSlotKeys({
    required Map<String, dynamic> checksMap,
    required Map<String, dynamic> statusesMap,
  }) {
    for (final item in _items.where((e) => e.slot != '需要時')) {
      final key = _itemKey(item);
      checksMap.putIfAbsent(key, () => false);
      statusesMap.putIfAbsent(key, () => _CheckinStatus.pending.value);
    }
  }

  String _fmtDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y/$m/$d $hh:$mm';
  }

  Future<void> _loadStats(String uid) async {
    setState(() => _statsLoading = true);

    try {
      final today = _dateOnly(DateTime.now());
      final startDate = today.subtract(const Duration(days: 179));
      final weekStart = _startOfWeek(today);

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medicationCheckins')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .get();

      final byDate = <String, _DailyAdherence>{};
      final missedSlotCount = <String, int>{};
      for (final doc in snap.docs) {
        final data = await HealthDataEncryptionService.decryptData(doc.data());
        final date = _parseAnyDate(data['date']);
        if (date == null) continue;

        final checks =
            Map<String, dynamic>.from(data['checks'] ?? <String, dynamic>{});
        final statuses =
            Map<String, dynamic>.from(data['statuses'] ?? <String, dynamic>{});

        int total;
        int done;
        int missed;

        final filteredStatuses = {
          for (final e in statuses.entries)
            if (!_isPrnKey(e.key)) e.key: e.value,
        };
        final filteredChecks = {
          for (final e in checks.entries)
            if (!_isPrnKey(e.key)) e.key: e.value,
        };

        if (filteredStatuses.isNotEmpty) {
          total = filteredStatuses.length;
          done = filteredStatuses.values
              .where((v) =>
                  v == _CheckinStatus.taken.value ||
                  v == _CheckinStatus.delayed.value)
              .length;
          missed = filteredStatuses.values
              .where((v) => v == _CheckinStatus.missed.value)
              .length;
        } else {
          total = filteredChecks.length;
          done = filteredChecks.values.where((v) => v == true).length;
          missed = 0;
        }

        final rate = total == 0 ? 0.0 : done / total;
        final key = _docId(date);
        final pending = (total - done - missed).clamp(0, total);
        final normalizedDate = _dateOnly(date);

        byDate[key] = _DailyAdherence(
          date: normalizedDate,
          done: done,
          total: total,
          rate: rate,
          missed: missed,
          pending: pending,
          isTarget: total > 0 && done == total,
        );

        if (!normalizedDate.isBefore(weekStart)) {
          final source =
              filteredStatuses.isNotEmpty ? filteredStatuses : filteredChecks;
          for (final entry in source.entries) {
            final k = entry.key;
            final split = k.split('::');
            if (split.length != 2) continue;
            final slot = split.last;
            if (slot == '需要時') continue;

            final isMissed = statuses.isNotEmpty
                ? entry.value == _CheckinStatus.missed.value
                : entry.value == false;
            if (!isMissed) continue;

            missedSlotCount[slot] = (missedSlotCount[slot] ?? 0) + 1;
          }
        }
      }

      List<_DailyAdherence> buildSeries(int days) {
        final points = <_DailyAdherence>[];
        for (var i = days - 1; i >= 0; i--) {
          final date = today.subtract(Duration(days: i));
          final key = _docId(date);
          points.add(
            byDate[key] ??
                _DailyAdherence(
                  date: date,
                  done: 0,
                  total: 0,
                  rate: 0,
                  missed: 0,
                  pending: 0,
                  isTarget: false,
                ),
          );
        }
        return points;
      }

      if (!mounted) return;

      final todayPoint = byDate[_docId(today)];
      final anchor = (todayPoint != null && todayPoint.isTarget)
          ? today
          : today.subtract(const Duration(days: 1));

      var streak = 0;
      for (var i = 0; i < 180; i++) {
        final d = anchor.subtract(Duration(days: i));
        final p = byDate[_docId(d)];
        if (p != null && p.isTarget) {
          streak += 1;
        } else {
          break;
        }
      }

      String mostMissedSlot = '—';
      if (missedSlotCount.isNotEmpty) {
        final sorted = missedSlotCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        mostMissedSlot = '${sorted.first.key}（${sorted.first.value} 次）';
      }

      setState(() {
        _stats7Days = buildSeries(7);
        _stats30Days = buildSeries(30);
        _targetStreakDays = streak;
        _mostMissedSlotThisWeek = mostMissedSlot;
        _statsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _statsLoading = false);
    }
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = [];
        _statusByKey = {};
        _statusAt = {};
        _actualAmountByKey = {};
        _prnEventsByKey = {};
      });
      return;
    }

    setState(() => _loading = true);

    try {
      final meds = await MedicationLocalDB().getMedicationsForDisplay(uid);
      final adjustments = await MedicationLocalDB().getAdjustmentRecords(uid);
      final activeMeds = meds
          .where((m) =>
              (m['type'] as String?) != 'injection' &&
              (((m['isActive'] as bool?) ?? true) ||
                  MedicationCheckinScheduleResolver.resolve(
                    medication: m,
                    adjustmentRecords: adjustments,
                    selectedDate: _selectedDate,
                  ).isNotEmpty))
          .toList();

      final items = <_CheckinItem>[];
      for (final med in activeMeds) {
        final medId = (med['id'] ?? '').toString();
        if (medId.isEmpty) continue;

        final name = ((med['name'] ?? med['nameZh'] ?? med['nameEn'] ?? '未命名藥物')
                as String)
            .trim();
        final type = (med['type'] ?? 'tablet').toString();
        final isCompound =
            (med['compoundType'] ?? '').toString().contains('複') ||
                RegExp(r'(\s*\+\s*|[;\n\r])')
                    .hasMatch((med['nameEn'] ?? '').toString());
        final plannedUnit = type == 'drops' ? 'mL' : '顆';
        final schedules = MedicationCheckinScheduleResolver.resolve(
          medication: med,
          adjustmentRecords: adjustments,
          selectedDate: _selectedDate,
        );
        for (final schedule in schedules) {
          final plannedAmount = type == 'drops'
              ? ((med['intakeMl'] is num)
                  ? (med['intakeMl'] as num).toDouble()
                  : 1.0)
              : ((schedule.pillCount is num)
                  ? (schedule.pillCount as num).toDouble()
                  : 1.0);
          final doseText = _buildCheckinDoseText(
            dose: schedule.dose,
            dosePerUnit: schedule.dosePerUnit,
            pillCount: schedule.pillCount,
            unit: schedule.unit,
            type: type,
            isCompound: isCompound,
          );
          items.add(
            _CheckinItem(
              medId: medId,
              medName: name.isEmpty ? '未命名藥物' : name,
              doseText: doseText,
              slot: schedule.slot,
              plannedAmount: plannedAmount,
              plannedUnit: plannedUnit,
            ),
          );
        }
      }

      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medicationCheckins')
          .doc(_docId(_selectedDate));

      final snap = await ref.get();
      final data = snap.data() == null
          ? <String, dynamic>{}
          : await HealthDataEncryptionService.decryptData(snap.data()!);

      final checksMap =
          Map<String, dynamic>.from(data['checks'] ?? <String, dynamic>{});
      final statusesMap =
          Map<String, dynamic>.from(data['statuses'] ?? <String, dynamic>{});
      final takenAtMap =
          Map<String, dynamic>.from(data['takenAt'] ?? <String, dynamic>{});
      final actualAmountMap = Map<String, dynamic>.from(
          data['actualAmount'] ?? <String, dynamic>{});
      final prnEventsMap =
          Map<String, dynamic>.from(data['prnEvents'] ?? <String, dynamic>{});

      final statusByKey = <String, _CheckinStatus>{};
      final statusAt = <String, DateTime>{};
      final actualAmountByKey = <String, double>{};
      final prnEventsByKey = <String, List<DateTime>>{};

      for (final item in items) {
        final key = _itemKey(item);

        final statusRaw = statusesMap[key]?.toString();
        if (statusRaw != null) {
          statusByKey[key] = _statusFromValue(statusRaw);
        } else {
          statusByKey[key] = checksMap[key] == true
              ? _CheckinStatus.taken
              : _CheckinStatus.pending;
        }

        final rawTakenAt = takenAtMap[key];
        if (rawTakenAt is Timestamp) {
          statusAt[key] = rawTakenAt.toDate();
        } else if (rawTakenAt is String) {
          final parsed = DateTime.tryParse(rawTakenAt);
          if (parsed != null) statusAt[key] = parsed;
        }

        final rawActual = actualAmountMap[key];
        if (rawActual is num) {
          actualAmountByKey[key] = rawActual.toDouble();
        } else if (rawActual is String) {
          final parsed = double.tryParse(rawActual);
          if (parsed != null) actualAmountByKey[key] = parsed;
        }

        if (item.slot == '需要時') {
          prnEventsByKey[key] = _parseDateList(prnEventsMap[key]);
        }
      }

      final beforeCount = statusesMap.length + checksMap.length;
      _ensureFixedSlotKeys(checksMap: checksMap, statusesMap: statusesMap);
      final afterCount = statusesMap.length + checksMap.length;
      if (afterCount != beforeCount) {
        await HealthDataEncryptionService.setEncrypted(
          ref,
          {
            'date': Timestamp.fromDate(_dateOnly(_selectedDate)),
            'statuses': statusesMap,
            'checks': checksMap,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _statusByKey = statusByKey;
        _statusAt = statusAt;
        _actualAmountByKey = actualAmountByKey;
        _prnEventsByKey = prnEventsByKey;
        _loading = false;
      });

      await _loadStats(uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('載入服藥打卡資料失敗')),
      );
    }
  }

  _CheckinStatus _statusFromValue(String value) {
    switch (value) {
      case 'taken':
        return _CheckinStatus.taken;
      case 'delayed':
        return _CheckinStatus.delayed;
      case 'missed':
        return _CheckinStatus.missed;
      default:
        return _CheckinStatus.pending;
    }
  }

  Future<_TakenEditResult?> _showTakenEditDialog({
    required _CheckinItem item,
    required _CheckinStatus status,
  }) async {
    final key = _itemKey(item);
    DateTime selectedAt = _statusAt[key] ??
        DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          TimeOfDay.now().hour,
          TimeOfDay.now().minute,
        );

    final amountCtrl = TextEditingController(
      text: (_actualAmountByKey[key] ?? item.safePlannedAmount)
          .toStringAsFixed(1),
    );

    _TakenEditResult? result;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title:
                  Text(status == _CheckinStatus.taken ? '設定已服用紀錄' : '設定延後服用紀錄'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '預計：${item.safePlannedAmount.toStringAsFixed(1)} ${item.safePlannedUnit}'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '實際服用',
                      suffixText: item.plannedUnit,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('服用時間'),
                    subtitle: Text(_fmtDateTime(selectedAt)),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedAt,
                        firstDate:
                            _selectedDate.subtract(const Duration(days: 7)),
                        lastDate: _selectedDate.add(const Duration(days: 7)),
                      );
                      if (pickedDate == null) return;
                      final pickedTime = await showTimePicker(
                        context: dialogContext,
                        initialTime: TimeOfDay.fromDateTime(selectedAt),
                      );
                      if (pickedTime == null) return;

                      setDialogState(() {
                        selectedAt = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '可補打跨日時間，例如 4/30 的睡前藥可記成 5/1 00:05。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final amount = double.tryParse(
                        amountCtrl.text.trim().replaceAll(',', '.'));
                    if (amount == null || amount <= 0) return;
                    result = _TakenEditResult(
                      takenAt: selectedAt,
                      actualAmount: amount,
                    );
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('確定'),
                ),
              ],
            );
          },
        );
      },
    );

    return result;
  }

  Future<void> _setStatus(
    _CheckinItem item,
    _CheckinStatus nextStatus, {
    DateTime? takenAt,
    double? actualAmount,
  }) async {
    if (item.slot == '需要時') return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final key = _itemKey(item);
    final prev = _statusByKey[key] ?? _CheckinStatus.pending;
    final prevStatusAt = _statusAt[key];
    final prevAmount = _actualAmountByKey[key];

    if (prev != nextStatus) {
      await HapticFeedback.selectionClick();
    }

    setState(() {
      _saving = true;
      _statusByKey[key] = nextStatus;
      if (nextStatus == _CheckinStatus.taken ||
          nextStatus == _CheckinStatus.delayed) {
        _statusAt[key] = takenAt ?? DateTime.now();
        _actualAmountByKey[key] = actualAmount ?? item.safePlannedAmount;
      } else {
        _statusAt.remove(key);
        _actualAmountByKey.remove(key);
      }
    });

    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medicationCheckins')
          .doc(_docId(_selectedDate));

      final snap = await ref.get();
      final data = snap.data() == null
          ? <String, dynamic>{}
          : await HealthDataEncryptionService.decryptData(snap.data()!);

      final checksMap =
          Map<String, dynamic>.from(data['checks'] ?? <String, dynamic>{});
      final statusesMap =
          Map<String, dynamic>.from(data['statuses'] ?? <String, dynamic>{});
      final takenAtMap =
          Map<String, dynamic>.from(data['takenAt'] ?? <String, dynamic>{});
      final actualAmountMap = Map<String, dynamic>.from(
          data['actualAmount'] ?? <String, dynamic>{});

      _ensureFixedSlotKeys(checksMap: checksMap, statusesMap: statusesMap);

      statusesMap[key] = nextStatus.value;
      checksMap[key] = nextStatus == _CheckinStatus.taken ||
          nextStatus == _CheckinStatus.delayed;

      if (nextStatus == _CheckinStatus.taken ||
          nextStatus == _CheckinStatus.delayed) {
        takenAtMap[key] = Timestamp.fromDate(_statusAt[key]!);
        actualAmountMap[key] =
            _actualAmountByKey[key] ?? item.safePlannedAmount;
      } else {
        takenAtMap.remove(key);
        actualAmountMap.remove(key);
      }

      await HealthDataEncryptionService.setEncrypted(
        ref,
        {
          'date': Timestamp.fromDate(_dateOnly(_selectedDate)),
          'statuses': statusesMap,
          'checks': checksMap,
          'takenAt': takenAtMap,
          'actualAmount': actualAmountMap,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      await _loadStats(uid);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusByKey[key] = prev;
        if (prevStatusAt != null) {
          _statusAt[key] = prevStatusAt;
        } else {
          _statusAt.remove(key);
        }
        if (prevAmount != null) {
          _actualAmountByKey[key] = prevAmount;
        } else {
          _actualAmountByKey.remove(key);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('打卡儲存失敗，請稍後再試')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _savePrnEvents(
      _CheckinItem item, List<DateTime> nextEvents) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final key = _itemKey(item);
    final prev =
        List<DateTime>.from(_prnEventsByKey[key] ?? const <DateTime>[]);

    setState(() {
      _saving = true;
      _prnEventsByKey[key] = List<DateTime>.from(nextEvents)..sort();
    });

    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medicationCheckins')
          .doc(_docId(_selectedDate));

      final snap = await ref.get();
      final data = snap.data() == null
          ? <String, dynamic>{}
          : await HealthDataEncryptionService.decryptData(snap.data()!);

      final checksMap =
          Map<String, dynamic>.from(data['checks'] ?? <String, dynamic>{});
      final statusesMap =
          Map<String, dynamic>.from(data['statuses'] ?? <String, dynamic>{});
      final takenAtMap =
          Map<String, dynamic>.from(data['takenAt'] ?? <String, dynamic>{});
      final prnEventsMap =
          Map<String, dynamic>.from(data['prnEvents'] ?? <String, dynamic>{});

      final normalized = List<DateTime>.from(nextEvents)..sort();
      prnEventsMap[key] = normalized.map((e) => Timestamp.fromDate(e)).toList();

      if (normalized.isNotEmpty) {
        statusesMap[key] = _CheckinStatus.taken.value;
        checksMap[key] = true;
        takenAtMap[key] = Timestamp.fromDate(normalized.last);
      } else {
        statusesMap[key] = _CheckinStatus.pending.value;
        checksMap[key] = false;
        takenAtMap.remove(key);
      }

      await HealthDataEncryptionService.setEncrypted(
        ref,
        {
          'date': Timestamp.fromDate(_dateOnly(_selectedDate)),
          'statuses': statusesMap,
          'checks': checksMap,
          'takenAt': takenAtMap,
          'prnEvents': prnEventsMap,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      await _loadStats(uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _prnEventsByKey[key] = prev);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要時服藥紀錄失敗，請稍後再試')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _addPrnEvent(_CheckinItem item) async {
    await HapticFeedback.selectionClick();
    final key = _itemKey(item);
    final current =
        List<DateTime>.from(_prnEventsByKey[key] ?? const <DateTime>[]);
    current.add(DateTime.now());
    await _savePrnEvents(item, current);
  }

  Future<void> _removePrnEventAt(_CheckinItem item, int index) async {
    await HapticFeedback.selectionClick();
    final key = _itemKey(item);
    final current =
        List<DateTime>.from(_prnEventsByKey[key] ?? const <DateTime>[]);
    if (index < 0 || index >= current.length) return;
    current.removeAt(index);
    await _savePrnEvents(item, current);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 180)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _loadData();
  }

  Future<void> _syncReminder() async {
    setState(() => _saving = true);
    try {
      final count =
          await MedicationReminderService.syncDailyRemindersForActiveMeds();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已更新服藥提醒（$count 個時段）')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新提醒失敗，請檢查通知權限')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _cancelReminder() async {
    setState(() => _saving = true);
    try {
      await MedicationReminderService.cancelAllMedicationReminders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清除所有服藥提醒')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清除提醒失敗')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _handleRefresh() async {
    await HapticFeedback.lightImpact();
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<_CheckinItem>>{};
    for (final item in _items) {
      grouped.putIfAbsent(item.slot, () => <_CheckinItem>[]).add(item);
    }
    final sortedSlots = grouped.keys.toList()
      ..sort((a, b) {
        final aIndex = _slotOrder.indexOf(a);
        final bIndex = _slotOrder.indexOf(b);
        final normalizedA = aIndex == -1 ? _slotOrder.length : aIndex;
        final normalizedB = bIndex == -1 ? _slotOrder.length : bIndex;
        return normalizedA.compareTo(normalizedB);
      });

    final fixedItems = _items.where((i) => i.slot != '需要時').toList();
    final total = fixedItems.length;
    final done = fixedItems.where((i) {
      final status = _statusByKey[_itemKey(i)] ?? _CheckinStatus.pending;
      return status == _CheckinStatus.taken || status == _CheckinStatus.delayed;
    }).length;
    var prnTakenCount = 0;
    for (final item in _items.where((i) => i.slot == '需要時')) {
      prnTakenCount +=
          (_prnEventsByKey[_itemKey(item)] ?? const <DateTime>[]).length;
    }

    final avg7 = _averageRate(_stats7Days);
    final avg30 = _averageRate(_stats30Days);
    final chartData =
        _statsRange == _StatsRange.week ? _stats7Days : _stats30Days;
    final colorScheme = Theme.of(context).colorScheme;
    final progress = total == 0 ? 0.0 : done / total;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        title: const Text('服藥打卡'),
        actions: [
          IconButton(
            tooltip: '重新載入',
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                colorScheme.primary.withOpacity(0.07),
                colorScheme.surface,
              ),
              Color.alphaBlend(
                colorScheme.secondary.withOpacity(0.05),
                colorScheme.surface,
              ),
              Color.alphaBlend(
                colorScheme.tertiary.withOpacity(0.04),
                colorScheme.surface,
              ),
            ],
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _handleRefresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  children: [
                    Card(
                      elevation: 4,
                      shadowColor: colorScheme.primary.withOpacity(0.16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              colorScheme.surface,
                              colorScheme.primaryContainer.withOpacity(0.22),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color:
                                          colorScheme.primary.withOpacity(0.14),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.event_available_outlined,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${_selectedDate.year}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.day.toString().padLeft(2, '0')}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: _pickDate,
                                    child: const Text('切換日期'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                total == 0
                                    ? '今日固定時段：無'
                                    : '今日固定時段完成：$done / $total',
                              ),
                              if (prnTakenCount > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('需要時今日已服用：$prnTakenCount 次'),
                                ),
                              const SizedBox(height: 10),
                              TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0, end: progress),
                                duration: const Duration(milliseconds: 450),
                                curve: Curves.easeOutCubic,
                                builder: (context, animatedProgress, child) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      minHeight: 9,
                                      value: animatedProgress,
                                      backgroundColor:
                                          colorScheme.primary.withOpacity(0.12),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                        opacity: animation, child: child);
                                  },
                                  child: Text(
                                    '${(progress * 100).toStringAsFixed(0)}%',
                                    key:
                                        ValueKey<int>((progress * 100).round()),
                                    style:
                                        Theme.of(context).textTheme.labelMedium,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: _saving ? null : _syncReminder,
                                    icon: const Icon(
                                        Icons.notifications_active_outlined),
                                    label: const Text('更新每日提醒'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _saving ? null : _cancelReminder,
                                    icon: const Icon(
                                        Icons.notifications_off_outlined),
                                    label: const Text('清除提醒'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Card(
                                margin: EdgeInsets.zero,
                                elevation: 0,
                                color: colorScheme.surfaceContainerHighest
                                    .withOpacity(0.34),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ExpansionTile(
                                  initiallyExpanded: _reminderSettingsExpanded,
                                  onExpansionChanged: (expanded) {
                                    setState(() =>
                                        _reminderSettingsExpanded = expanded);
                                  },
                                  leading: const Icon(Icons.alarm_outlined),
                                  title: const Text('提醒時間設定'),
                                  subtitle: Text(
                                    MedicationReminderService.kSlotTimes.keys
                                        .map((slot) =>
                                            '$slot ${_fmtTime(_slotTimes[slot] ?? MedicationReminderService.kSlotTimes[slot]!)}')
                                        .join('  ·  '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  childrenPadding:
                                      const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                  children: [
                                    ...MedicationReminderService.kSlotTimes.keys
                                        .map((slot) {
                                      final time = _slotTimes[slot] ??
                                          MedicationReminderService
                                              .kSlotTimes[slot]!;
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        leading: const Icon(Icons.access_time),
                                        title: Text(slot),
                                        subtitle: Text('每日 ${_fmtTime(time)}'),
                                        trailing: TextButton(
                                          onPressed: _saving
                                              ? null
                                              : () => _pickReminderTime(slot),
                                          child: const Text('調整'),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_items.isEmpty)
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('目前沒有可打卡藥物（請先新增「目前服用中」的口服藥）'),
                        ),
                      ),
                    ...sortedSlots.map((slot) {
                      final entryItems =
                          grouped[slot] ?? const <_CheckinItem>[];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 4, top: 8, bottom: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                slot,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          Card(
                            elevation: 2,
                            shadowColor: colorScheme.primary.withOpacity(0.12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              children: entryItems.map((item) {
                                if (item.slot == '需要時') {
                                  final key = _itemKey(item);
                                  final events = List<DateTime>.from(
                                    _prnEventsByKey[key] ?? const <DateTime>[],
                                  )..sort();

                                  return Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 12, 12, 8),
                                      decoration: BoxDecoration(
                                        color: colorScheme.secondaryContainer
                                            .withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: colorScheme.secondary
                                              .withOpacity(0.22),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.medName,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                              '${item.doseText} · 今日 ${events.length} 次'),
                                          const SizedBox(height: 8),
                                          FilledButton.tonalIcon(
                                            onPressed: _saving
                                                ? null
                                                : () => _addPrnEvent(item),
                                            icon: const Icon(
                                                Icons.add_circle_outline),
                                            label: const Text('＋ 記錄服用一次'),
                                          ),
                                          const SizedBox(height: 8),
                                          if (events.isEmpty)
                                            const Text('今天尚未記錄服用')
                                          else
                                            Wrap(
                                              alignment:
                                                  WrapAlignment.spaceBetween,
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: List.generate(
                                                  events.length, (idx) {
                                                final d = events[idx];
                                                final text =
                                                    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                                                return InputChip(
                                                  label: Text(text),
                                                  onDeleted: _saving
                                                      ? null
                                                      : () => _removePrnEventAt(
                                                          item, idx),
                                                );
                                              }),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }

                                final key = _itemKey(item);
                                final currentStatus =
                                    _statusByKey[key] ?? _CheckinStatus.pending;
                                final statusAt = _statusAt[key];
                                final actualAmount = _actualAmountByKey[key];
                                final timeText = statusAt == null
                                    ? '尚未打卡'
                                    : '時間 ${_fmtDateTime(statusAt)}';
                                final statusColor = switch (currentStatus) {
                                  _CheckinStatus.taken =>
                                    const Color.fromARGB(255, 46, 125, 50),
                                  _CheckinStatus.delayed =>
                                    const Color.fromARGB(255, 239, 108, 0),
                                  _CheckinStatus.missed =>
                                    const Color.fromARGB(255, 198, 40, 40),
                                  _CheckinStatus.pending =>
                                    colorScheme.onSurface.withOpacity(0.66),
                                };

                                return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    width: double.infinity,
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 12, 12, 8),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer
                                          .withOpacity(0.22),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: statusColor.withOpacity(0.28),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.medName,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                    milliseconds: 220),
                                                curve: Curves.easeOut,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: statusColor
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                ),
                                                child: AnimatedSwitcher(
                                                  duration: const Duration(
                                                      milliseconds: 180),
                                                  transitionBuilder:
                                                      (child, animation) {
                                                    return FadeTransition(
                                                      opacity: animation,
                                                      child: child,
                                                    );
                                                  },
                                                  child: Text(
                                                    currentStatus.label,
                                                    key: ValueKey<String>(
                                                        currentStatus.value),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelMedium
                                                        ?.copyWith(
                                                            color: statusColor),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${item.doseText} · 預計 ${item.safePlannedAmount.toStringAsFixed(1)} ${item.safePlannedUnit}'
                                          '${actualAmount == null ? '' : ' · 實際 ${actualAmount.toStringAsFixed(1)} ${item.safePlannedUnit}'}'
                                          ' · $timeText',
                                        ),
                                        const SizedBox(height: 8),
                                        SegmentedButton<_CheckinStatus>(
                                          multiSelectionEnabled: false,
                                          emptySelectionAllowed: true,
                                          showSelectedIcon: false,
                                          segments: const [
                                            ButtonSegment(
                                              value: _CheckinStatus.taken,
                                              label: Text('已服用'),
                                              icon: Icon(
                                                  Icons.check_circle_outline),
                                            ),
                                            ButtonSegment(
                                              value: _CheckinStatus.delayed,
                                              label: Text('延後'),
                                              icon: Icon(Icons.schedule),
                                            ),
                                            ButtonSegment(
                                              value: _CheckinStatus.missed,
                                              label: Text('漏服'),
                                              icon: Icon(Icons.cancel_outlined),
                                            ),
                                          ],
                                          selected: {
                                            if (currentStatus !=
                                                _CheckinStatus.pending)
                                              currentStatus,
                                          },
                                          onSelectionChanged: _saving
                                              ? null
                                              : (v) async {
                                                  if (v.isEmpty) {
                                                    await _setStatus(item,
                                                        _CheckinStatus.pending);
                                                    return;
                                                  }

                                                  final pickedStatus = v.first;
                                                  if (pickedStatus ==
                                                          _CheckinStatus
                                                              .taken ||
                                                      pickedStatus ==
                                                          _CheckinStatus
                                                              .delayed) {
                                                    await _setStatus(
                                                      item,
                                                      pickedStatus,
                                                      takenAt: _statusAt[key] ??
                                                          DateTime.now(),
                                                      actualAmount:
                                                          _actualAmountByKey[
                                                                  key] ??
                                                              item.safePlannedAmount,
                                                    );
                                                    return;
                                                  }

                                                  await _setStatus(
                                                      item, pickedStatus);
                                                },
                                        ),
                                        if (currentStatus ==
                                                _CheckinStatus.taken ||
                                            currentStatus ==
                                                _CheckinStatus.delayed)
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton.icon(
                                              onPressed: _saving
                                                  ? null
                                                  : () async {
                                                      final edit =
                                                          await _showTakenEditDialog(
                                                        item: item,
                                                        status: currentStatus,
                                                      );
                                                      if (edit == null) return;
                                                      await _setStatus(
                                                        item,
                                                        currentStatus,
                                                        takenAt: edit.takenAt,
                                                        actualAmount:
                                                            edit.actualAmount,
                                                      );
                                                    },
                                              icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 16),
                                              label: const Text('修改劑量 / 時間'),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      );
                    }),
                    if (_items.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildStatsCard(
                        context,
                        avg7: avg7,
                        avg30: avg30,
                        chartData: chartData,
                        streakDays: _targetStreakDays,
                        missedSlot: _mostMissedSlotThisWeek,
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStatsCard(
    BuildContext context, {
    required double avg7,
    required double avg30,
    required List<_DailyAdherence> chartData,
    required int streakDays,
    required String missedSlot,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
        elevation: 3,
        shadowColor: colorScheme.primary.withOpacity(0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surface,
                colorScheme.tertiaryContainer.withOpacity(0.2),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.monitor_heart_outlined),
                    const SizedBox(width: 8),
                    Text('服藥率趨勢',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildMetricTile('近 7 日平均', avg7)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMetricTile('近 30 日平均', avg30)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoTile('連續達標天數', '$streakDays 天'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildInfoTile('本週最常漏服時段', missedSlot),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SegmentedButton<_StatsRange>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _StatsRange.week, label: Text('7 天')),
                    ButtonSegment(
                        value: _StatsRange.month, label: Text('30 天')),
                  ],
                  selected: {_statsRange},
                  onSelectionChanged: (v) {
                    setState(() => _statsRange = v.first);
                  },
                ),
                const SizedBox(height: 10),
                if (_statsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 26),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  SizedBox(
                    height: 190,
                    child: BarChart(
                      BarChartData(
                        minY: 0,
                        maxY: 100,
                        alignment: BarChartAlignment.spaceAround,
                        gridData: FlGridData(
                          show: true,
                          horizontalInterval: 25,
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final point = chartData[group.x.toInt()];
                              final dateLabel =
                                  '${point.date.month}/${point.date.day.toString().padLeft(2, '0')}';
                              final pct = (point.rate * 100).toStringAsFixed(0);
                              return BarTooltipItem(
                                '$dateLabel\n$pct% (${point.done}/${point.total})',
                                Theme.of(context).textTheme.bodySmall!,
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              interval: 25,
                              getTitlesWidget: (value, _) =>
                                  Text('${value.toInt()}%'),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 26,
                              getTitlesWidget: (value, _) {
                                final idx = value.toInt();
                                if (idx < 0 || idx >= chartData.length) {
                                  return const SizedBox.shrink();
                                }

                                final date = chartData[idx].date;
                                final shouldShow =
                                    _statsRange == _StatsRange.week
                                        ? (idx % 2 == 0 ||
                                            idx == chartData.length - 1)
                                        : (date.day == 1 ||
                                            idx == 0 ||
                                            idx == chartData.length - 1);

                                if (!shouldShow) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('${date.month}/${date.day}'),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: List.generate(chartData.length, (idx) {
                          final point = chartData[idx];
                          return BarChartGroupData(
                            x: idx,
                            barRods: [
                              BarChartRodData(
                                toY: point.rate * 100,
                                width: _statsRange == _StatsRange.week ? 18 : 8,
                                borderRadius: BorderRadius.circular(4),
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ));
  }

  Widget _buildMetricTile(String title, double rate) {
    final pct = (rate * 100).toStringAsFixed(0);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.primaryContainer.withOpacity(0.32),
        border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('$pct%', style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String title, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.secondaryContainer.withOpacity(0.28),
        border: Border.all(color: colorScheme.secondary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  double _averageRate(List<_DailyAdherence> items) {
    if (items.isEmpty) return 0;
    var sum = 0.0;
    for (final item in items) {
      sum += item.rate;
    }
    return sum / items.length;
  }

  // ── 修正：正確顯示「每顆劑量 × 顆數 = 總量」 ──────────────────────────
  // 解決「回診調藥後打卡只顯示總量、無法看出是幾顆」的 bug。
  // 資料來源為藥物卡（dosePerUnit / pillCount / dose），確保與卡片同步。
  static String _buildCheckinDoseText({
    required dynamic dose,
    required dynamic dosePerUnit,
    required dynamic pillCount,
    required String unit,
    required String type,
    bool isCompound = false,
  }) {
    String numStr(dynamic v) {
      if (v is num)
        return v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
      return v?.toString() ?? '?';
    }

    double? asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final perUnit = asDouble(dosePerUnit);
    final count = asDouble(pillCount);
    final totalDose = asDouble(dose);

    if (isCompound && (perUnit == null || perUnit <= 0)) {
      if (count != null && count > 0) return '每次 ${numStr(count)}顆';
      return '劑量依複方成分';
    }

    // 口服藥：以「Xmg × Y顆」格式顯示，不自動計算總量。
    if (type == 'tablet' && perUnit != null && count != null) {
      if ((count - 1.0).abs() < 0.0001) {
        return '${numStr(perUnit)} $unit';
      }
      return '${numStr(perUnit)} $unit × ${numStr(count)}顆';
    }

    if (type == 'tablet' && perUnit != null) {
      return '${numStr(perUnit)} $unit';
    }

    if (totalDose == null) return '劑量未填';

    // 一般（滴劑 / 注射）：直接顯示總量
    return '${numStr(totalDose)} $unit';
  }
}

class _CheckinItem {
  final String medId;
  final String medName;
  final String doseText;
  final String slot;
  final double? plannedAmount;
  final String? plannedUnit;

  double get safePlannedAmount => plannedAmount ?? 1.0;
  String get safePlannedUnit {
    final v = (plannedUnit ?? '').trim();
    return v.isEmpty ? '顆' : v;
  }

  const _CheckinItem({
    required this.medId,
    required this.medName,
    required this.doseText,
    required this.slot,
    this.plannedAmount,
    this.plannedUnit,
  });
}

class _TakenEditResult {
  final DateTime takenAt;
  final double actualAmount;

  const _TakenEditResult({
    required this.takenAt,
    required this.actualAmount,
  });
}

enum _StatsRange { week, month }

class _DailyAdherence {
  final DateTime date;
  final int done;
  final int total;
  final double rate;
  final int missed;
  final int pending;
  final bool isTarget;

  const _DailyAdherence({
    required this.date,
    required this.done,
    required this.total,
    required this.rate,
    required this.missed,
    required this.pending,
    required this.isTarget,
  });
}

enum _CheckinStatus {
  pending('pending', '未打卡'),
  taken('taken', '已服用'),
  delayed('delayed', '延後服用'),
  missed('missed', '漏服');

  final String value;
  final String label;
  const _CheckinStatus(this.value, this.label);
}
