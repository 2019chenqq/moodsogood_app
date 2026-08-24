import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/period_cycle.dart';
import 'period_cycle_service.dart';
import 'period_feature_visibility_service.dart';
import 'widgets/symptom_page.dart';

class PeriodCalendarPage extends StatefulWidget {
  const PeriodCalendarPage({super.key});

  @visibleForTesting
  static PeriodCalendarPresentation buildPresentation(
    Iterable<PeriodCycle> source, {
    required DateTime asOf,
  }) {
    final cycles = source.toList()
      ..sort((left, right) => left.startDate.compareTo(right.startDate));
    final starts = cycles.map((cycle) => _dateOnly(cycle.startDate)).toList();
    final intervals = <int>[];
    for (var index = 1; index < starts.length; index++) {
      final days = starts[index].difference(starts[index - 1]).inDays;
      if (days > 0) intervals.add(days);
    }
    final cycleLength = intervals.isEmpty
        ? 28
        : (intervals.reduce((a, b) => a + b) / intervals.length).round();
    final marked = <DateTime>{};
    final today = _dateOnly(asOf);
    for (final cycle in cycles) {
      final start = _dateOnly(cycle.startDate);
      final firstSevenEnd = start.add(const Duration(days: 6));
      final openEnd = today.isAfter(firstSevenEnd) ? today : firstSevenEnd;
      final end = _dateOnly(cycle.endDate ?? openEnd);
      for (var date = start;
          !date.isAfter(end);
          date = date.add(const Duration(days: 1))) {
        marked.add(date);
      }
    }
    final next =
        starts.isEmpty ? null : starts.last.add(Duration(days: cycleLength));
    return PeriodCalendarPresentation(
      markedDays: marked,
      cycleLength: cycleLength,
      nextExpectedStart: next,
    );
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  State<PeriodCalendarPage> createState() => _PeriodCalendarPageState();
}

class _PeriodCalendarPageState extends State<PeriodCalendarPage> {
  DateTime _focusedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  Set<DateTime> _markedDays = const {};
  int _cycleLength = 28;
  DateTime? _nextExpectedStart;
  bool _loading = true;
  bool _updating = false;
  bool _allowed = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  Future<void> _load() async {
    final allowed =
        await PeriodFeatureVisibilityService().shouldShowForCurrentUser();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!allowed || uid == null) {
      if (!mounted) return;
      setState(() {
        _allowed = allowed;
        _loading = false;
      });
      return;
    }

    try {
      final cycles = await PeriodCycleService().getUnifiedCycles(uid);
      final presentation =
          PeriodCalendarPage.buildPresentation(cycles, asOf: DateTime.now());
      if (!mounted) return;
      setState(() {
        _markedDays = presentation.markedDays;
        _cycleLength = presentation.cycleLength;
        _nextExpectedStart = presentation.nextExpectedStart;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '生理期資料載入失敗，請稍後再試。';
      });
    }
  }

  String _dateText(DateTime date) => '${date.month}/${date.day}';

  Future<void> _onTapDate(DateTime value) async {
    if (_updating) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final date = _day(value);
    final marked = _markedDays.contains(date);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(marked ? '取消這次經期？' : '記錄月經開始？'),
        content: Text(
          marked
              ? '將取消包含 ${_dateText(date)} 的這次經期。快速記錄不會被刪除。'
              : '將 ${_dateText(date)} 設為月經開始日，月曆會先顯示 7 天。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(marked ? '取消這次經期' : '記錄開始'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _updating = true);
    try {
      final service = PeriodCycleService();
      if (marked) {
        final deleted = await service.cancelCycleForDate(uid, date);
        if (!deleted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('這是尚未轉換的舊紀錄，目前無法從月曆取消。')),
          );
        }
      } else {
        await service.apply(
          userId: uid,
          date: date,
          action: PeriodQuickAction.start,
        );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新生理期資料失敗：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('生理期月曆')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : !_allowed
                ? const Center(child: Text('此帳號未顯示生理期功能。'))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _load,
                              child: const Text('重新載入'),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          PeriodCalendarCard(
                            markedDays: _markedDays,
                            focusedMonth: _focusedMonth,
                            isTodayPeriod:
                                _markedDays.contains(_day(DateTime.now())),
                            onTapDate: _onTapDate,
                            onChangeMonth: (month) => setState(() {
                              _focusedMonth =
                                  DateTime(month.year, month.month, 1);
                            }),
                            cycleLength: _cycleLength,
                            nextExpectedStart: _nextExpectedStart,
                            busy: _updating,
                            initiallyExpanded: true,
                            footerText: '點日期可記錄月經開始；點已亮日期可取消該次經期。',
                          ),
                        ],
                      ),
      ),
    );
  }
}

class PeriodCalendarPresentation {
  const PeriodCalendarPresentation({
    required this.markedDays,
    required this.cycleLength,
    required this.nextExpectedStart,
  });

  final Set<DateTime> markedDays;
  final int cycleLength;
  final DateTime? nextExpectedStart;
}
