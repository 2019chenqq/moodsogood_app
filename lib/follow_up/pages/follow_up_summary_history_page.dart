import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../models/follow_up_ai_summary.dart';
import '../services/follow_up_service.dart';
import '../qr/follow_up_summary_share_service.dart';
import '../widgets/follow_up_feedback_dialog.dart';
import 'follow_up_summary_access_guard.dart';
import 'follow_up_summary_detail_page.dart';

class FollowUpSummaryHistoryPage extends StatefulWidget {
  const FollowUpSummaryHistoryPage({super.key});

  @override
  State<FollowUpSummaryHistoryPage> createState() =>
      _FollowUpSummaryHistoryPageState();
}

class _FollowUpSummaryHistoryPageState
    extends State<FollowUpSummaryHistoryPage> {
  late Future<_HistoryData> _future;
  bool _openingFeedback = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() => setState(() {
        _future = _load();
      });

  Future<_HistoryData> _load() async {
    final summaries = await FollowUpService.listFormalSummaries();
    try {
      final activeIds = await FollowUpSummaryShareService()
          .activeSummaryIds(summaries.map((item) => item.id));
      return _HistoryData(summaries: summaries, activeShareIds: activeIds);
    } catch (_) {
      return _HistoryData(summaries: summaries);
    }
  }

  Future<void> _open(FollowUpSummaryRecord summary) async {
    final verified = await FollowUpSummaryAccessGuard.ensureVerified(context);
    if (!mounted || !verified) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FollowUpSummaryDetailPage(summary: summary),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _giveFeedback(
    FollowUpSummaryRecord summary,
    _HistoryData data,
  ) async {
    if (_openingFeedback || summary.feedback != null) return;
    setState(() => _openingFeedback = true);
    try {
      final verified = await FollowUpSummaryAccessGuard.ensureVerified(context);
      if (!mounted || !verified) return;
      final feedback = await showFollowUpFeedbackDialog(
        context,
        summaryId: summary.id,
      );
      if (!mounted || feedback == null) return;
      setState(() {
        _future = Future.value(_HistoryData(
          summaries: data.summaries
              .map((item) => item.id == summary.id
                  ? item.copyWith(feedback: feedback)
                  : item)
              .toList(),
          activeShareIds: data.activeShareIds,
        ));
      });
    } finally {
      if (mounted) setState(() => _openingFeedback = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        title: const Text('歷次回診摘要'),
        backgroundColor: HealingDesignSystem.primaryBlue,
      ),
      body: FutureBuilder<_HistoryData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _StateMessage(
              icon: Icons.error_outline,
              message: '讀取摘要失敗',
              action: TextButton(onPressed: _reload, child: const Text('重試')),
            );
          }
          final data = snapshot.data ?? const _HistoryData(summaries: []);
          final summaries = data.summaries;
          if (summaries.isEmpty) {
            return const _StateMessage(
              icon: Icons.description_outlined,
              message: '尚無已確認的回診摘要',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: summaries.length,
              itemBuilder: (context, index) {
                final summary = summaries[index];
                final topics = summary.selectedTopics
                    .map((item) => item['label']?.toString() ?? '')
                    .where((item) => item.isNotEmpty)
                    .join('、');
                final hasActiveShare =
                    data.activeShareIds?.contains(summary.id);
                return Card(
                  elevation: 0,
                  color: HealingDesignSystem.adaptiveSurface(context),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.description_outlined,
                              color: HealingDesignSystem.primaryBlue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              summary.appointmentDate == null
                                  ? '建立日期 ${_date(summary.createdAt)}'
                                  : '回診日期 ${_date(summary.appointmentDate!)}',
                              style: HealingDesignSystem.titleSmall,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                            '統計期間 ${_date(summary.periodStart)}～${_date(summary.periodEnd)}'),
                        Text('有效紀錄天數 ${summary.validRecordDays} 天'),
                        if (topics.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: topics
                                .split('、')
                                .map((topic) => Chip(label: Text(topic)))
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          const Chip(label: Text('已完成')),
                          Chip(
                            avatar: Icon(
                              hasActiveShare == true
                                  ? Icons.link_rounded
                                  : Icons.link_off_rounded,
                              size: 18,
                            ),
                            label: Text(hasActiveShare == null
                                ? 'QR 狀態暫時無法確認'
                                : hasActiveShare
                                    ? 'QR 分享有效'
                                    : '無有效 QR 分享'),
                          ),
                        ]),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: () => _open(summary),
                                icon: const Icon(Icons.lock_open_rounded),
                                label: const Text('查看摘要'),
                              ),
                              if (summary.feedback == null)
                                OutlinedButton.icon(
                                  onPressed: _openingFeedback
                                      ? null
                                      : () => _giveFeedback(summary, data),
                                  icon: const Icon(Icons.chat_bubble_outline),
                                  label: const Text('回診後回饋'),
                                )
                              else
                                const Chip(
                                  avatar: Icon(Icons.check_circle_outline,
                                      size: 18),
                                  label: Text('已回饋'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
}

class _HistoryData {
  const _HistoryData({required this.summaries, this.activeShareIds});
  final List<FollowUpSummaryRecord> summaries;
  final Set<String>? activeShareIds;
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 44,
              color: HealingDesignSystem.adaptiveSecondaryText(context)),
          const SizedBox(height: 10),
          Text(message),
          if (action != null) action!,
        ]),
      );
}
