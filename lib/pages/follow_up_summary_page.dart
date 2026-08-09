import 'package:flutter/material.dart';

import '../analytics_service.dart';
import '../constants/healing_design_system.dart';
import '../models/follow_up_ai_summary.dart';
import '../services/follow_up_ai_data_aggregator.dart';
import '../services/follow_up_ai_service.dart';
import '../services/follow_up_service.dart';
import 'follow_up_ai_preview_page.dart';
import 'follow_up_summary_detail_page.dart';
import 'follow_up_summary_history_page.dart';

const _topicOptions = <({String type, String label})>[
  (type: 'mood', label: '情緒變化'),
  (type: 'sleep', label: '睡眠狀況'),
  (type: 'medicationEffect', label: '藥效與劑量'),
  (type: 'medicationSideEffects', label: '藥物副作用'),
  (type: 'physicalDiscomfort', label: '身體不適'),
  (type: 'appetite', label: '食慾變化'),
  (type: 'lifeUpdates', label: '生活近況'),
  (type: 'other', label: '其他'),
];

class FollowUpSummaryPage extends StatefulWidget {
  const FollowUpSummaryPage({super.key});

  @override
  State<FollowUpSummaryPage> createState() => _FollowUpSummaryPageState();
}

class _FollowUpSummaryPageState extends State<FollowUpSummaryPage> {
  final _additionalNotes = TextEditingController();
  final Map<String, TextEditingController> _topicNotes = {};
  final Set<String> _selectedTypes = {};
  final _aggregator = FollowUpAiDataAggregator();
  final _ai = FollowUpAiService();
  bool _loading = true;
  bool _generating = false;
  DateTime? _appointmentDate;
  String? _error;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('follow_up_summary_page');
    for (final option in _topicOptions) {
      _topicNotes[option.type] = TextEditingController();
    }
    _restorePreparation();
  }

  Future<void> _restorePreparation() async {
    final results = await Future.wait<dynamic>([
      FollowUpService.getWorkspace(),
      FollowUpService.getAppointments(),
    ]);
    if (!mounted) return;
    final workspace = results[0] as FollowUpWorkspace;
    final appointments = results[1] as List<FollowUpAppointment>;
    final today = DateTime.now();
    final upcoming = appointments.where((item) => !item.date.isBefore(
          DateTime(today.year, today.month, today.day),
        )).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final topic in workspace.aiDiscussionTopics) {
      if (topic.selected) _selectedTypes.add(topic.type);
      _topicNotes[topic.type]?.text = topic.note;
    }
    _additionalNotes.text = workspace.aiAdditionalNotes;
    setState(() {
      _appointmentDate = upcoming.isEmpty ? null : upcoming.first.date;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _additionalNotes.dispose();
    for (final controller in _topicNotes.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<FollowUpDiscussionTopicInput> get _topics => _topicOptions
      .map((option) => FollowUpDiscussionTopicInput(
            type: option.type,
            label: option.label,
            selected: _selectedTypes.contains(option.type),
            note: _topicNotes[option.type]!.text.trim(),
          ))
      .toList();

  Future<void> _generate() async {
    if (_selectedTypes.isEmpty && _additionalNotes.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少選擇一個主題，或填寫補充內容。')),
      );
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final topics = _topics;
      await FollowUpService.saveAiPreparation(
        topics: topics,
        additionalNotes: _additionalNotes.text,
      );
      var input = await _aggregator.build(
        discussionTopics: topics,
        discussionDetails: topics
            .where((topic) => topic.selected && topic.note.isNotEmpty)
            .map((topic) => '${topic.label}：${topic.note}')
            .join('\n'),
        additionalNotes: _additionalNotes.text,
        currentAppointmentDate: _appointmentDate,
      );
      final questions = await _ai.generateFollowUpQuestions(input);
      if (!mounted) return;
      final answers = questions.isEmpty
          ? const <String, String>{}
          : await _collectAnswers(questions);
      if (!mounted || answers == null) return;
      var output = await _ai.generateSummary(input, followUpAnswers: answers);
      if (!mounted) return;
      final preview = await Navigator.push<FollowUpAiPreviewResult>(
        context,
        MaterialPageRoute(
          builder: (_) => FollowUpAiPreviewPage(
            initialSummary: output,
            initialAdditionalNotes: input.additionalNotes,
            aiInput: input,
            onRegenerate: (notes) async {
              input = input.copyWith(additionalNotes: notes);
              output = await _ai.generateSummary(input, followUpAnswers: answers);
              return output;
            },
          ),
        ),
      );
      if (!mounted || preview == null) return;
      input = input.copyWith(additionalNotes: preview.additionalNotes);
      final now = DateTime.now();
      final record = FollowUpSummaryRecord(
        id: now.microsecondsSinceEpoch.toString(),
        createdAt: now,
        updatedAt: now,
        confirmedAt: now,
        appointmentDate: _appointmentDate,
        periodStart: input.statistics.periodStart,
        periodEnd: input.statistics.periodEnd,
        validRecordDays: input.statistics.validRecordDays,
        selectedTopics: input.discussionTopics
            .where((topic) => topic.selected)
            .map((topic) => topic.toJson())
            .toList(),
        discussionDetails: input.discussionDetails,
        additionalNotes: preview.additionalNotes,
        aiOutput: preview.summary,
        sleepSummary: input.sleep,
        sleepTrend: (input.sleep['dailyTrend'] as List?)
                ?.whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList() ??
            const [],
        medicationTimeline: input.medicationTimeline,
      );
      await FollowUpService.updateFormalSummary(record);
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FollowUpSummaryDetailPage(summary: record),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '產生摘要失敗：$error');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<Map<String, String>?> _collectAnswers(List<String> questions) async {
    final controllers = questions.map((_) => TextEditingController()).toList();
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('生成前再確認幾件事'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('不確定或不想回答的題目可以留白。'),
              const SizedBox(height: 12),
              for (var i = 0; i < questions.length; i++) ...[
                TextField(
                  controller: controllers[i],
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: questions[i]),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              for (var i = 0; i < questions.length; i++)
                if (controllers[i].text.trim().isNotEmpty)
                  questions[i]: controllers[i].text.trim(),
            }),
            child: const Text('繼續生成'),
          ),
        ],
      ),
    );
    for (final controller in controllers) {
      controller.dispose();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        title: const Text('準備 AI 回診摘要'),
        backgroundColor: HealingDesignSystem.primaryBlue,
        actions: [
          IconButton(
            tooltip: '歷次摘要',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const FollowUpSummaryHistoryPage(),
              ),
            ),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _loading || _generating ? null : _generate,
          icon: _generating
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_rounded),
          label: Text(_generating ? '正在整理紀錄…' : '產生回診摘要'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                Text(
                  '選擇想討論的主題。AI 只會根據 App 中已有的近期紀錄與你填寫的內容整理，不會提供診斷或調藥建議。',
                  style: HealingDesignSystem.bodyMedium,
                ),
                if (_appointmentDate != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '預計回診：${_appointmentDate!.year}/${_appointmentDate!.month}/${_appointmentDate!.day}',
                  ),
                ],
                const SizedBox(height: 16),
                for (final option in _topicOptions)
                  Card(
                    child: Column(
                      children: [
                        CheckboxListTile(
                          title: Text(option.label),
                          value: _selectedTypes.contains(option.type),
                          onChanged: (selected) => setState(() {
                            if (selected == true) {
                              _selectedTypes.add(option.type);
                            } else {
                              _selectedTypes.remove(option.type);
                            }
                          }),
                        ),
                        if (_selectedTypes.contains(option.type))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: TextField(
                              controller: _topicNotes[option.type],
                              decoration: const InputDecoration(
                                hintText: '有什麼特別想討論的？（選填）',
                              ),
                              minLines: 1,
                              maxLines: 3,
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _additionalNotes,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '其他想跟醫師說的內容（選填）',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
    );
  }
}

/// 標示「AI 回診重點」的提示卡片；目前為準備中狀態。
class FollowUpAiHighlightsCard extends StatelessWidget {
  const FollowUpAiHighlightsCard({super.key, this.onTap});

  /// 準備中狀態的說明文字。
  static const String unavailableMessage = 'AI 回診摘要準備中，將在近期提供';

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: HealingDesignSystem.adaptiveSurface(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
        side: BorderSide(
            color: HealingDesignSystem.adaptiveCardBorder(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: HealingDesignSystem.adaptiveFill(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      size: 16, color: HealingDesignSystem.primaryBlue),
                ),
                const SizedBox(width: 8),
                Text('AI 回診重點', style: HealingDesignSystem.titleSmall),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: HealingDesignSystem.adaptiveFill(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('準備中',
                      style: HealingDesignSystem.bodySmall),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              unavailableMessage,
              style: HealingDesignSystem.bodyMedium.copyWith(
                color: HealingDesignSystem.adaptiveSecondaryText(context),
              ),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: const [
                    Expanded(child: Text('開始準備 AI 回診摘要')),
                    Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
