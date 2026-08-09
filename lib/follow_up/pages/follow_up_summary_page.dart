import 'package:flutter/material.dart';

import '../../analytics_service.dart';
import '../../constants/healing_design_system.dart';
import '../models/follow_up_ai_summary.dart';
import '../services/follow_up_ai_data_aggregator.dart';
import '../services/follow_up_ai_service.dart';
import '../services/follow_up_service.dart';
import 'follow_up_ai_preview_page.dart';
import 'follow_up_summary_detail_page.dart';
import 'follow_up_summary_history_page.dart';

const _topicOptions = <({String type, String label})>[
  (type: 'mood', label: '情緒狀況'),
  (type: 'sleep', label: '睡眠品質'),
  (type: 'medicationSideEffects', label: '藥物副作用'),
  (type: 'physicalDiscomfort', label: '身體不適'),
  (type: 'lifeUpdates', label: '生活近況'),
  (type: 'lifeStress', label: '生活壓力'),
  (type: 'relationships', label: '人際關係'),
  (type: 'workSchool', label: '工作／學業'),
  (type: 'exercise', label: '運動習慣'),
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
    final upcoming = appointments
        .where((item) => !item.date.isBefore(
              DateTime(today.year, today.month, today.day),
            ))
        .toList()
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

  Future<void> _pickAppointmentDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _appointmentDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (date != null && mounted) setState(() => _appointmentDate = date);
  }

  Future<void> _generate() async {
    if (_selectedTypes.isEmpty && _additionalNotes.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少選擇一個主題，或填寫其他想討論的事。')),
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
              output =
                  await _ai.generateSummary(input, followUpAnswers: answers);
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
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        backgroundColor: HealingDesignSystem.adaptiveSurface(dialogContext),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 想先確認幾件事',
                  style: HealingDesignSystem.titleLarge.copyWith(
                    color:
                        HealingDesignSystem.adaptivePrimaryText(dialogContext),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '可留白；AI 不會重問紀錄中已有的資訊。',
                  style: HealingDesignSystem.bodyMedium.copyWith(
                    color: HealingDesignSystem.adaptiveSecondaryText(
                        dialogContext),
                  ),
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < questions.length; i++) ...[
                          Text(
                            '${i + 1}. ${questions[i]}',
                            style: HealingDesignSystem.bodyLarge.copyWith(
                              color: HealingDesignSystem.adaptivePrimaryText(
                                  dialogContext),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: ValueKey('follow-up-answer-$i'),
                            controller: controllers[i],
                            minLines: 2,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: '補充回答（可留白）',
                              filled: true,
                              fillColor: HealingDesignSystem.adaptiveFill(
                                  dialogContext),
                              contentPadding: const EdgeInsets.all(16),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color:
                                      HealingDesignSystem.adaptiveSecondaryText(
                                          dialogContext),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: HealingDesignSystem.primaryBlue,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          if (i < questions.length - 1)
                            const SizedBox(height: 18),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF526CA8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => Navigator.pop(dialogContext, {
                        for (var i = 0; i < questions.length; i++)
                          if (controllers[i].text.trim().isNotEmpty)
                            questions[i]: controllers[i].text.trim(),
                      }),
                      child: const Text('產生摘要'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (final controller in controllers) {
      controller.dispose();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final foreground = HealingDesignSystem.adaptivePrimaryText(context);
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        title: const Text('準備回診摘要'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
        foregroundColor: HealingDesignSystem.adaptiveAppBarForeground(context),
        actions: [
          IconButton(
            tooltip: '摘要紀錄',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const FollowUpSummaryHistoryPage()),
            ),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: SizedBox(
          height: 58,
          child: FilledButton.icon(
            key: const ValueKey('generate-follow-up-summary'),
            onPressed: _loading || _generating ? null : _generate,
            style: FilledButton.styleFrom(
              backgroundColor: HealingDesignSystem.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            icon: _generating
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(
              _generating ? '正在整理本次回診期間紀錄⋯' : '讓 AI 幫我整理',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              children: [
                _AiIntroCard(foreground: foreground),
                const SizedBox(height: 18),
                _SectionCard(
                  icon: Icons.calendar_today_outlined,
                  title: '回診日期（可選）',
                  child: InkWell(
                    key: const ValueKey('appointment-date-field'),
                    onTap: _pickAppointmentDate,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 68,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(
                        color: HealingDesignSystem.adaptiveFill(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: HealingDesignSystem.adaptiveCardBorder(
                                context)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _appointmentDate == null
                                  ? '點擊選擇日期（不填也沒關係）'
                                  : '${_appointmentDate!.year}/${_appointmentDate!.month.toString().padLeft(2, '0')}/${_appointmentDate!.day.toString().padLeft(2, '0')}',
                              style: HealingDesignSystem.bodyLarge.copyWith(
                                color: _appointmentDate == null
                                    ? HealingDesignSystem.adaptiveSecondaryText(
                                        context)
                                    : foreground,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: HealingDesignSystem.adaptiveSecondaryText(
                                  context)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  icon: Icons.topic_outlined,
                  title: '想跟醫師討論的主題',
                  child: Column(
                    children: [
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _topicOptions.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 3.1,
                        ),
                        itemBuilder: (context, index) {
                          final option = _topicOptions[index];
                          final selected = _selectedTypes.contains(option.type);
                          return InkWell(
                            key: ValueKey('topic-${option.type}'),
                            onTap: () => setState(() {
                              if (selected) {
                                _selectedTypes.remove(option.type);
                              } else {
                                _selectedTypes.add(option.type);
                              }
                            }),
                            borderRadius: BorderRadius.circular(14),
                            child: AnimatedContainer(
                              duration: HealingDesignSystem.animationFast,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFDDE5FF)
                                    : HealingDesignSystem.adaptiveFill(context),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF9AACE0)
                                      : HealingDesignSystem.adaptiveCardBorder(
                                          context),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (selected) ...[
                                    const Icon(Icons.check_rounded,
                                        size: 20, color: Color(0xFF52617A)),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: Text(
                                      option.label,
                                      textAlign: TextAlign.center,
                                      style: HealingDesignSystem.bodyMedium
                                          .copyWith(color: foreground),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      for (final option in _topicOptions)
                        if (_selectedTypes.contains(option.type)) ...[
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('${option.label}想討論的內容（可選）',
                                style: HealingDesignSystem.titleSmall
                                    .copyWith(color: foreground)),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: ValueKey('topic-note-${option.type}'),
                            controller: _topicNotes[option.type],
                            minLines: 3,
                            maxLines: 5,
                            decoration: _inputDecoration(
                              context,
                              '例如：最近的變化、發生頻率，或想問醫師的問題……',
                            ),
                          ),
                        ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  icon: Icons.notes_rounded,
                  title: '其他想討論的事（可選）',
                  child: TextField(
                    key: const ValueKey('additional-follow-up-notes'),
                    controller: _additionalNotes,
                    minLines: 4,
                    maxLines: 7,
                    decoration: _inputDecoration(
                      context,
                      '例如：近期生活事件、開心的事，或其他想讓醫師知道的內容……',
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
    );
  }

  InputDecoration _inputDecoration(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      alignLabelWithHint: true,
      filled: true,
      fillColor: HealingDesignSystem.adaptiveFill(context),
      contentPadding: const EdgeInsets.all(18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: HealingDesignSystem.adaptiveCardBorder(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: HealingDesignSystem.primaryBlue, width: 2),
      ),
    );
  }
}

class _AiIntroCard extends StatelessWidget {
  const _AiIntroCard({required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: HealingDesignSystem.primaryBlue,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.description_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('讓 AI 幫你整理',
                    style: HealingDesignSystem.titleMedium
                        .copyWith(color: foreground)),
                const SizedBox(height: 5),
                Text(
                  '先選取想跟醫師討論的主題；AI 整理功能將於後續階段提供。',
                  style: HealingDesignSystem.bodyMedium.copyWith(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.icon, required this.title, required this.child});

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  color: HealingDesignSystem.adaptiveAccent(context), size: 23),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: HealingDesignSystem.titleMedium.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

/// 首頁用的 AI 回診摘要入口卡片。
class FollowUpAiHighlightsCard extends StatelessWidget {
  const FollowUpAiHighlightsCard({super.key, this.onTap});

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
        side:
            BorderSide(color: HealingDesignSystem.adaptiveCardBorder(context)),
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
                  child:
                      const Text('準備中', style: HealingDesignSystem.bodySmall),
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
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
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
