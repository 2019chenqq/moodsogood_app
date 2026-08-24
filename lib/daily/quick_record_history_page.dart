import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/healing_design_system.dart';
import '../models/health_event.dart';
import 'health_event_repository.dart';
import 'quick_record_editor.dart';

class QuickRecordHistoryPage extends StatefulWidget {
  const QuickRecordHistoryPage({super.key});

  @override
  State<QuickRecordHistoryPage> createState() => _QuickRecordHistoryPageState();
}

class _QuickRecordHistoryPageState extends State<QuickRecordHistoryPage> {
  late Future<List<HealthEvent>> _future;
  DateTimeRange? _selectedRange;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<HealthEvent>> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const <HealthEvent>[];
    final repo = HealthEventRepository();
    if (_selectedRange != null) {
      return repo.getByDateRange(
        userId: uid,
        start: _selectedRange!.start,
        end: _selectedRange!.end,
      );
    }
    return repo.getRecent(userId: uid, limit: 500);
  }

  Future<void> _refresh() async {
    final newFuture = _load();
    if (!mounted) return;
    setState(() {
      _future = newFuture;
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _selectedRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 29)),
            end: now,
          ),
      helpText: '選擇日期區間',
      confirmText: '確認',
      cancelText: '取消',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedRange = DateTimeRange(
        start:
            DateTime(picked.start.year, picked.start.month, picked.start.day),
        // 結束日要含到當天最後一刻，避免排除結束日當天的記錄。
        end: DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999),
      );
    });
    await _refresh();
  }

  Future<void> _clearRange() async {
    if (!mounted) return;
    setState(() => _selectedRange = null);
    await _refresh();
  }

  Future<void> _openEditor(HealthEvent? event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuickRecordEditor(initial: event),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _confirmDelete(HealthEvent event) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除這筆快速記錄？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await HealthEventRepository().delete(
        userId: uid,
        eventId: event.id,
      );
      await _refresh();
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('快速記錄歷史'),
        actions: [
          IconButton(
            icon: Icon(_selectedRange == null
                ? Icons.date_range_outlined
                : Icons.clear),
            tooltip: '日期區間',
            onPressed: _selectedRange == null ? _pickRange : _clearRange,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: FutureBuilder<List<HealthEvent>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }

            final events = snapshot.data ?? const <HealthEvent>[];
            final grouped = <String, List<HealthEvent>>{};
            final dateFmt = DateFormat('yyyy-MM-dd');
            for (final e in events) {
              final key = dateFmt.format(DateTime(
                  e.timestamp.year, e.timestamp.month, e.timestamp.day));
              grouped.putIfAbsent(key, () => []).add(e);
            }
            final sortedKeys = grouped.keys.toList()
              ..sort((a, b) => b.compareTo(a));

            if (sortedKeys.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_rounded,
                          size: 64, color: HealingDesignSystem.mutedText),
                      const SizedBox(height: 16),
                      Text(
                        _selectedRange == null ? '目前沒有快速記錄' : '所選區間沒有快速記錄',
                        style: HealingDesignSystem.titleSmall
                            .copyWith(color: HealingDesignSystem.mutedText),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '點擊首頁的「快速記錄現在狀況」開始記錄。',
                        style: HealingDesignSystem.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sortedKeys.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final key = sortedKeys[index];
                final list = grouped[key]!;
                return _DateGroup(
                  dateKey: key,
                  events: list,
                  onTap: _openEditor,
                  onDelete: _confirmDelete,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _DateGroup extends StatelessWidget {
  const _DateGroup({
    required this.dateKey,
    required this.events,
    required this.onTap,
    required this.onDelete,
  });

  final String dateKey;
  final List<HealthEvent> events;
  final ValueChanged<HealthEvent?> onTap;
  final ValueChanged<HealthEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final dateLabel = _weekdayLabel(dateKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$dateKey （$dateLabel）',
          style: HealingDesignSystem.labelMedium.copyWith(
            color: HealingDesignSystem.adaptiveSecondaryText(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...events.map((event) =>
            _EventTile(event: event, onTap: onTap, onDelete: onDelete)),
      ],
    );
  }

  static String _weekdayLabel(String yyyyMMdd) {
    final parts = yyyyMMdd.split('-');
    final d =
        DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    const labels = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return labels[d.weekday - DateTime.monday];
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.onTap,
    required this.onDelete,
  });

  final HealthEvent event;
  final ValueChanged<HealthEvent?> onTap;
  final ValueChanged<HealthEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final time = event.timestamp;
    final timeText =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final parts = <String>[
      if (event.emotions.isNotEmpty)
        '情緒：${event.emotions.map((e) => '${e.name}(${e.intensity})').join('、')}',
      if (event.symptoms.isNotEmpty)
        '症狀：${event.symptoms.map((s) => s.severity == null ? s.name : '${s.name}(${s.severity})').join('、')}',
      if (event.context != null && event.context!.trim().isNotEmpty)
        '情境：${event.context!.trim()}',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: HealingDesignSystem.adaptiveFill(context),
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        child: InkWell(
          borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
          onTap: () => onTap(event),
          child: Padding(
            padding: const EdgeInsets.all(HealingDesignSystem.paddingM),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HealingDesignSystem.paddingS,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        HealingDesignSystem.primaryBlue.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(HealingDesignSystem.radiusS),
                  ),
                  child: Text(
                    timeText,
                    style: HealingDesignSystem.labelMedium.copyWith(
                      color: HealingDesignSystem.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: HealingDesignSystem.paddingM),
                Expanded(
                  child: parts.isEmpty
                      ? Text(
                          '(只有時間的紀錄)',
                          style: HealingDesignSystem.bodySmall,
                        )
                      : Text(
                          parts.join(' ・ '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: HealingDesignSystem.bodySmall.copyWith(
                            color: HealingDesignSystem.adaptivePrimaryText(
                                context),
                          ),
                        ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onDelete(event),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: HealingDesignSystem.dangerRed,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
