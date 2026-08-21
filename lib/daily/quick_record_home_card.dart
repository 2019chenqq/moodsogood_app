import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import '../models/health_event.dart';
import 'daily_state_dimensions.dart';
import 'health_event_repository.dart';
import 'quick_record_editor.dart';
import 'quick_record_history_page.dart';

List<String> healthEventTimelineSummary(HealthEvent event) => <String>[
      if (event.emotions.isNotEmpty)
        '${event.emotions.first.name} ${event.emotions.first.intensity}/5',
      if (event.symptoms.isNotEmpty)
        '${event.symptoms.first.name} ${event.symptoms.first.severity}/5',
      ...event.stateChanges.entries.take(2).map((entry) {
        final dimension = kDailyStateDimensionsById[entry.key];
        return dimension == null
            ? null
            : '${dimension.displayName}：${dailyStateValueLabel(dimension, entry.value)}';
      }).whereType<String>(),
    ];

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
  late Future<List<HealthEvent>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<HealthEvent>> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const <HealthEvent>[];
    }
    final repo = HealthEventRepository();
    final today = await repo.getToday(userId: uid);
    today.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return today;
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
    return FutureBuilder<List<HealthEvent>>(
      future: _future,
      builder: (context, snapshot) {
        final today = snapshot.data ?? const <HealthEvent>[];
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
                  const Icon(Icons.timeline_rounded),
                  const SizedBox(width: HealingDesignSystem.paddingS),
                  Expanded(
                    child: Text(
                      '今日時間軸',
                      style: HealingDesignSystem.titleSmall.copyWith(
                        color: HealingDesignSystem.adaptivePrimaryText(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HealingDesignSystem.paddingS),
              Text(
                '一天可以有多個狀態，每筆都會保留實際時間。',
                style: HealingDesignSystem.bodySmall,
              ),
              const SizedBox(height: HealingDesignSystem.paddingM),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('新增現在的狀態'),
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
                if (today.isEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '今天還沒有留下狀態。',
                        style: HealingDesignSystem.bodyMedium.copyWith(
                          color:
                              HealingDesignSystem.adaptivePrimaryText(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '有變化時，隨時記下一個時間點。',
                        style: HealingDesignSystem.bodySmall.copyWith(
                          color: HealingDesignSystem.adaptiveSecondaryText(
                            context,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  ...today.map((event) => _eventTile(context, event)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _eventTile(BuildContext context, HealthEvent event) {
    final parts = healthEventTimelineSummary(event);
    final time = event.timestamp;
    final timeText = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: HealingDesignSystem.timelineNodeDiameter,
                  height: HealingDesignSystem.timelineNodeDiameter,
                  decoration: HealingDesignSystem.timelineNodeDecoration(),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: HealingDesignSystem.adaptiveCardBorder(context),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.only(bottom: HealingDesignSystem.paddingM),
              child: Material(
                color: HealingDesignSystem.adaptiveFill(context),
                borderRadius:
                    BorderRadius.circular(HealingDesignSystem.radiusM),
                child: InkWell(
                  borderRadius:
                      BorderRadius.circular(HealingDesignSystem.radiusM),
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
                            color: HealingDesignSystem.primaryBlue
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                                HealingDesignSystem.radiusS),
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
                                    color:
                                        HealingDesignSystem.adaptivePrimaryText(
                                            context),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: '刪除這筆紀錄',
                          onPressed: () => _confirmDelete(event),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: HealingDesignSystem.adaptiveSecondaryText(
                              context,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
