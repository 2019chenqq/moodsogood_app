import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import '../models/health_event.dart';
import 'health_event_repository.dart';
import 'quick_record_editor.dart';
import 'quick_record_history_page.dart';

/// 首頁的「快速記錄現在狀況」入口卡片。
///
/// 顯示：
/// - 醒目的「＋ 快速記錄現在狀況」按鈕（新增）
/// - 今天已記錄幾筆
/// - 最近 3 筆快速記錄，點擊可編輯／刪除
class QuickRecordHomeCard extends StatefulWidget {
  const QuickRecordHomeCard({super.key});

  @override
  State<QuickRecordHomeCard> createState() => _QuickRecordHomeCardState();
}

class _QuickRecordHomeCardState extends State<QuickRecordHomeCard> {
  late Future<(List<HealthEvent>, List<HealthEvent>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<HealthEvent>, List<HealthEvent>)> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return (const <HealthEvent>[], const <HealthEvent>[]);
    }
    final repo = HealthEventRepository();
    final today = await repo.getToday(userId: uid);
    final recent = await repo.getRecent(userId: uid, limit: 3);
    return (today, recent);
  }

  Future<void> _refresh() async {
    final newFuture = _load();
    if (!mounted) return;
    setState(() {
      _future = newFuture;
    });
  }

  Future<void> _openEditor({HealthEvent? event}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => QuickRecordEditor(initial: event)),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<HealthEvent>, List<HealthEvent>)>(
      future: _future,
      builder: (context, snapshot) {
        final today = snapshot.data?.$1 ?? const <HealthEvent>[];
        final recent = snapshot.data?.$2 ?? const <HealthEvent>[];
        final loading = snapshot.connectionState == ConnectionState.waiting;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
          decoration: HealingDesignSystem.adaptiveCardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    color: HealingDesignSystem.warningOrange,
                  ),
                  const SizedBox(width: HealingDesignSystem.paddingS),
                  Expanded(
                    child: Text(
                      '快速記錄現在狀況',
                      style: HealingDesignSystem.titleSmall.copyWith(
                        color: HealingDesignSystem.adaptivePrimaryText(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HealingDesignSystem.paddingS),
              Text(
                '一天可多次，隨時記下當下的情緒、症狀與狀態',
                style: HealingDesignSystem.bodySmall,
              ),
              const SizedBox(height: HealingDesignSystem.paddingL),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text(' 快速記錄現在狀況'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: HealingDesignSystem.paddingL),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Text(
                      '今天已記錄 ${today.length} 筆',
                      style: HealingDesignSystem.labelMedium.copyWith(
                        color: HealingDesignSystem.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const QuickRecordHistoryPage(),
                          ),
                        );
                        await _refresh();
                      },
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('查看歷史'),
                    ),
                  ],
                ),
                const SizedBox(height: HealingDesignSystem.paddingM),
                if (recent.isEmpty)
                  Text(
                    '還沒有快速記錄，點上方按鈕開始。',
                    style: HealingDesignSystem.bodySmall,
                  )
                else
                  ...recent.map((event) => _eventTile(context, event)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _eventTile(BuildContext context, HealthEvent event) {
    final parts = <String>[
      if (event.emotions.isNotEmpty)
        '情緒：${event.emotions.map((e) => '${e.name}(${e.intensity})').join('、')}',
      if (event.symptoms.isNotEmpty)
        '症狀：${event.symptoms.map((s) => '${s.name}(${s.severity})').join('、')}',
      if (event.context != null) '情境：${event.context}',
      if (event.note != null) '${event.note}',
    ];
    final time = event.timestamp;
    final timeText = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: HealingDesignSystem.paddingM),
      child: Material(
        color: HealingDesignSystem.adaptiveFill(context),
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        child: InkWell(
          borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
          onTap: () => _openEditor(event: event),
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
                  onTap: () => _confirmDelete(event),
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
      await HealthEventRepository().delete(userId: uid, eventId: event.id);
      await _refresh();
    } catch (_) {
      // 忽略刪除失敗，讓使用者稍後再試
    }
  }
}
