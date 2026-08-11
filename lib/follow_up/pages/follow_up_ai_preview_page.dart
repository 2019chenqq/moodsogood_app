import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../models/follow_up_ai_summary.dart';
import '../services/follow_up_ai_service.dart';
import '../widgets/follow_up_sleep_trend_card.dart';

class FollowUpAiPreviewPage extends StatefulWidget {
  const FollowUpAiPreviewPage({
    super.key,
    required this.initialSummary,
    required this.initialAdditionalNotes,
    required this.onRegenerate,
    this.aiInput,
    this.errorMessage,
  });

  final FollowUpAiOutput initialSummary;
  final String initialAdditionalNotes;
  final Future<FollowUpAiOutput> Function(String additionalNotes) onRegenerate;
  final FollowUpAiV1Input? aiInput;
  final String Function(Object error)? errorMessage;

  @override
  State<FollowUpAiPreviewPage> createState() => _FollowUpAiPreviewPageState();
}

class FollowUpAiPreviewResult {
  const FollowUpAiPreviewResult({
    required this.summary,
    required this.additionalNotes,
  });

  final FollowUpAiOutput summary;
  final String additionalNotes;
}

class _FollowUpAiPreviewPageState extends State<FollowUpAiPreviewPage> {
  late FollowUpAiOutput _summary;
  Map<String, List<TextEditingController>> _controllers = {};
  late final TextEditingController _additionalNotesController;
  bool _regenerating = false;
  String? _error;
  final Set<String> _selectedDiaryHighlights = {};

  @override
  void initState() {
    super.initState();
    _additionalNotesController =
        TextEditingController(text: widget.initialAdditionalNotes);
    _replaceSummary(widget.initialSummary);
  }

  void _replaceSummary(FollowUpAiOutput value) {
    final previousControllers = _controllers;
    _summary = value;
    _selectedDiaryHighlights.clear();
    final discussionItems = FollowUpSummaryTextFormatter.safeDiscussionItems([
      if (widget.aiInput?.discussionDetails.trim().isNotEmpty == true)
        widget.aiInput!.discussionDetails,
      ...value.discussionItems,
      ...value.discussionPriorities,
    ]);
    _controllers = {
      'keyChanges': _make(value.keyChanges),
      'discussionItems': _make(discussionItems),
      'timelineRelations': _make(value.timelineRelations),
      'userSharedNotes': _make(value.userSharedNotes),
      'dataLimitations': _make(value.dataLimitations),
    };
    if (previousControllers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _disposeControllerMap(previousControllers);
      });
    }
  }

  List<TextEditingController> _make(List<String> values) =>
      values.map((value) => TextEditingController(text: value)).toList();

  void _disposeControllerMap(
    Map<String, List<TextEditingController>> controllers,
  ) {
    for (final list in controllers.values) {
      for (final controller in list) {
        controller.dispose();
      }
    }
  }

  @override
  void dispose() {
    _disposeControllerMap(_controllers);
    _additionalNotesController.dispose();
    super.dispose();
  }

  FollowUpAiOutput _editedSummary() => FollowUpAiOutput(
        keyChanges: _texts('keyChanges'),
        discussionPriorities: const [],
        discussionItems: _texts('discussionItems'),
        followUpResponses: _summary.followUpResponses,
        timelineRelations: _texts('timelineRelations'),
        medicationSubjectiveSummaries: _summary.medicationSubjectiveSummaries,
        recordEvidenceHighlights: _summary.recordEvidenceHighlights,
        userSharedNotes: _texts('userSharedNotes'),
        userReportedConcerns: _summary.userReportedConcerns,
        diaryHighlights: _summary.diaryHighlights
            .where((item) => _selectedDiaryHighlights.contains(
                  _diaryHighlightKey(item),
                ))
            .toList(growable: false),
        dataLimitations: _texts('dataLimitations'),
        generatedAt: _summary.generatedAt,
        usedFallback: _summary.usedFallback,
      );

  List<String> _texts(String key) => _controllers[key]!
      .map((controller) => controller.text.trim())
      .where((text) => text.isNotEmpty)
      .toList();

  Future<void> _regenerate() async {
    setState(() {
      _regenerating = true;
      _error = null;
    });
    try {
      final next = await widget.onRegenerate(
        _additionalNotesController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _replaceSummary(next);
        _regenerating = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _regenerating = false;
        _error = '重新生成失敗：${widget.errorMessage?.call(error) ?? error}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        title: const Text('AI 回診摘要預覽'),
        backgroundColor: HealingDesignSystem.primaryBlue,
        actions: [
          TextButton.icon(
            onPressed: _regenerating ? null : _regenerate,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新生成'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _regenerating
              ? null
              : () => Navigator.pop(
                    context,
                    FollowUpAiPreviewResult(
                      summary: _editedSummary(),
                      additionalNotes: _additionalNotesController.text.trim(),
                    ),
                  ),
          icon: const Icon(Icons.check_rounded),
          label: const Text('確認摘要'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (_summary.usedFallback) ...[
            Material(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'AI 整理暫時未完成，以下先依 App 紀錄建立摘要，可稍後重新生成。',
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            '可直接修改內容，或用垃圾桶刪除不需要的項目。確認前不會覆蓋已儲存摘要。',
            style: HealingDesignSystem.bodyMedium.copyWith(
              color: HealingDesignSystem.adaptiveSecondaryText(context),
            ),
          ),
          if (_regenerating) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: _error!, onRetry: _regenerate),
          ],
          const SizedBox(height: 12),
          _basicInfoSection(),
          _discussionSection(),
          _section('主要變化', 'keyChanges', showWhenEmpty: true),
          if (widget.aiInput != null)
            FollowUpSleepTrendCard(input: widget.aiInput!),
          if (widget.aiInput != null) ...[
            _readOnlySection('身體症狀', _symptomItems(),
                emptyText: '此摘要沒有可顯示的症狀資料'),
            _readOnlySection('身體測量', _bodyMeasurementItems(),
                emptyText: '此摘要沒有可顯示的體重、體脂率或腰圍資料'),
          ] else ...[
            _readOnlySection('身體症狀', const [], emptyText: '此摘要沒有可顯示的症狀資料'),
            _readOnlySection('身體測量', const [],
                emptyText: '此摘要沒有可顯示的體重、體脂率或腰圍資料'),
          ],
          _diaryHighlightsSection(),
          _medicationTimelineSection(),
          _additionalNotesSection(),
          _readOnlySection(
            '主觀用藥感受',
            _summary.medicationSubjectiveSummaries,
            emptyText: '此摘要期間沒有主觀用藥感受回報',
          ),
          _section('資料限制', 'dataLimitations', showWhenEmpty: true),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _basicInfoSection() {
    final statistics = widget.aiInput?.statistics;
    if (statistics == null) {
      return _readOnlySection('基本資訊', const [], emptyText: '尚無基本資訊');
    }
    String date(DateTime value) =>
        '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
    return _readOnlySection('基本資訊', [
      '統計期間：${date(statistics.periodStart)}～${date(statistics.periodEnd)}',
      '有效紀錄天數：${statistics.validRecordDays} 天',
    ]);
  }

  List<String> _symptomItems() {
    final input = widget.aiInput;
    if (input == null) return const [];
    String compact(dynamic value) {
      final number = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (number == null) return value?.toString().trim() ?? '';
      return number == number.roundToDouble()
          ? number.toInt().toString()
          : number.toStringAsFixed(1);
    }

    final symptoms = input.highFrequencySymptoms.take(5).map((symptom) {
      final name = symptom['name']?.toString().trim() ?? '';
      final days = (symptom['occurrenceDays'] as num?)?.toInt();
      final events = (symptom['eventCount'] as num?)?.toInt();
      final severity = symptom['averageSeverity'];
      final maxSeverity = symptom['maxSeverity'];
      return [
        name,
        if (days != null) '出現 $days 天',
        if (events != null && events > 0) '快速記錄 $events 次',
        if (severity is num) '平均程度 ${compact(severity)}',
        if (maxSeverity is num) '最高程度 ${compact(maxSeverity)}/5',
      ].where((part) => part.isNotEmpty).join('，');
    }).where((item) => item.trim().isNotEmpty);
    return FollowUpSummaryTextFormatter.sentences(symptoms);
  }

  List<String> _bodyMeasurementItems() {
    final input = widget.aiInput;
    if (input == null) return const [];
    String compact(dynamic value) {
      final number = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (number == null) return value?.toString().trim() ?? '';
      return number == number.roundToDouble()
          ? number.toInt().toString()
          : number.toStringAsFixed(1);
    }

    final measurements = input.bodyMeasurements.map((measurement) {
      final name = measurement['name']?.toString().trim() ?? '';
      final unit = measurement['unit']?.toString().trim() ?? '';
      final change = compact(measurement['change']);
      if (name.isEmpty) return '';
      final changeNum = double.tryParse(change);
      if (changeNum == null || changeNum == 0) {
        return '$name：無明顯變化';
      }
      final direction = changeNum > 0 ? '增加' : '減少';
      final absChange = changeNum.abs().toString();
      return '$name：$direction $absChange$unit';
    }).where((item) => item.trim().isNotEmpty);
    return FollowUpSummaryTextFormatter.sentences(measurements);
  }

  Widget _medicationTimelineSection() {
    final items = widget.aiInput?.medicationTimeline
            .map(FollowUpAiService.formatMedicationTimelineEvent)
            .where((item) => item.isNotEmpty)
            .toList() ??
        const <String>[];
    return _readOnlySection('藥物調整時間軸', items, emptyText: '此摘要沒有藥物調整紀錄');
  }

  String _diaryHighlightKey(FollowUpDiaryHighlight item) =>
      '${item.date}|${item.category}|${item.summary}';

  Widget _diaryHighlightsSection() {
    if (_summary.diaryHighlights.isEmpty) return const SizedBox.shrink();
    const labels = {
      'life_event': '重要生活事件',
      'subjective_feeling': '主觀感受',
      'sleep_note': '睡眠補充',
      'symptom_note': '症狀補充',
      'share_with_doctor': '想告訴醫師的事情',
    };
    return Card(
      elevation: 0,
      color: HealingDesignSystem.adaptiveSurface(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('來自日記的候選重點', style: HealingDesignSystem.titleSmall),
            const SizedBox(height: 6),
            Text(
              '只有勾選的摘要會加入正式摘要；日記原文不會放入 QR Code 或 PDF。',
              style: HealingDesignSystem.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final item in _summary.diaryHighlights)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _selectedDiaryHighlights.contains(
                  _diaryHighlightKey(item),
                ),
                title: Text(item.summary),
                subtitle: Text(
                  '${item.date}・${labels[item.category] ?? item.category}',
                ),
                onChanged: (selected) {
                  setState(() {
                    final key = _diaryHighlightKey(item);
                    if (selected == true) {
                      _selectedDiaryHighlights.add(key);
                    } else {
                      _selectedDiaryHighlights.remove(key);
                    }
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _additionalNotesSection() => Card(
        elevation: 0,
        color: HealingDesignSystem.adaptiveSurface(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('其他想跟醫師說的內容', style: HealingDesignSystem.titleSmall),
              const SizedBox(height: 6),
              Text(
                '可補充未包含在上方主題中的事情，內容會原樣保留。',
                style: HealingDesignSystem.bodySmall.copyWith(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('preview-additional-notes'),
                controller: _additionalNotesController,
                minLines: 3,
                maxLines: 7,
                decoration: const InputDecoration(
                  hintText: '例如：近期生活事件、開心的事，或其他想讓醫師知道的內容',
                  border: OutlineInputBorder(),
                ),
              ),
              for (var index = 0;
                  index < _controllers['userSharedNotes']!.length;
                  index++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Text('•'),
                      ),
                      Expanded(
                        child: TextField(
                          key: ValueKey('userSharedNotes-$index'),
                          controller: _controllers['userSharedNotes']![index],
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _readOnlySection(
    String title,
    List<String> items, {
    String emptyText = '尚無資料',
  }) =>
      Card(
        elevation: 0,
        color: HealingDesignSystem.adaptiveSurface(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: HealingDesignSystem.titleSmall),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Text(emptyText, style: HealingDesignSystem.bodySmall)
              else
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                        '• ${FollowUpSummaryTextFormatter.sentence(item)}'),
                  ),
            ],
          ),
        ),
      );

  Widget _section(
    String title,
    String key, {
    bool showWhenEmpty = false,
  }) {
    final controllers = _controllers[key]!;
    if (controllers.isEmpty && !showWhenEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      elevation: 0,
      color: HealingDesignSystem.adaptiveSurface(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: HealingDesignSystem.titleSmall),
            const SizedBox(height: 8),
            if (controllers.isEmpty)
              Text('尚無資料', style: HealingDesignSystem.bodySmall),
            for (var index = 0; index < controllers.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 12, right: 8),
                      child: Text('•'),
                    ),
                    Expanded(
                      child: TextField(
                        key: ValueKey('$key-$index'),
                        controller: controllers[index],
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('$key-delete-$index'),
                      tooltip: '刪除',
                      onPressed: () {
                        final removed = controllers.removeAt(index);
                        setState(() {});
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          removed.dispose();
                        });
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _discussionSection() {
    final input = widget.aiInput;
    final labels = input?.discussionTopics
            .where((topic) => topic.selected)
            .map((topic) => topic.label)
            .toList() ??
        const <String>[];
    final discussionItems = _controllers['discussionItems']!;
    if (labels.isEmpty && discussionItems.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      elevation: 0,
      color: HealingDesignSystem.adaptiveSurface(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('想跟醫師討論的事', style: HealingDesignSystem.titleSmall),
          if (labels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  labels.map((label) => Chip(label: Text(label))).toList(),
            ),
          ],
          for (var index = 0; index < discussionItems.length; index++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 12, right: 8),
                  child: Text('•'),
                ),
                Expanded(
                  child: TextField(
                    key: ValueKey('discussionItems-$index'),
                    controller: discussionItems[index],
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: Text(message)),
              TextButton(onPressed: onRetry, child: const Text('重試')),
            ],
          ),
        ),
      );
}
