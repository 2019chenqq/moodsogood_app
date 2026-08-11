import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../ai/ai_callable_diagnostics.dart';
import '../../constants/healing_design_system.dart';
import '../../diary/diary_repository.dart';
import '../models/follow_up_ai_summary.dart';
import '../services/follow_up_ai_data_aggregator.dart';
import '../services/follow_up_ai_service.dart';
import '../services/follow_up_service.dart';
import '../../analytics_service.dart';
import 'follow_up_ai_preview_page.dart';
import 'follow_up_summary_detail_page.dart';

/// 可選的主題標籤
const List<FollowUpTopicOption> kTopicOptions = [
  FollowUpTopicOption('mood', '情緒狀況'),
  FollowUpTopicOption('sleep', '睡眠品質'),
  FollowUpTopicOption('medicationSideEffects', '藥物副作用'),
  FollowUpTopicOption('physicalDiscomfort', '身體不適'),
  FollowUpTopicOption('lifeUpdates', '生活近況'),
  FollowUpTopicOption('lifeStress', '生活壓力'),
  FollowUpTopicOption('relationships', '人際關係'),
  FollowUpTopicOption('workOrStudy', '工作／學業'),
  FollowUpTopicOption('exercise', '運動習慣'),
  FollowUpTopicOption(
    'other',
    '其他',
    hint: '請輸入其他想討論的主題與內容',
  ),
];

class FollowUpTopicOption {
  const FollowUpTopicOption(this.type, this.label, {this.hint});

  final String type;
  final String label;
  final String? hint;
}

class FollowUpSummaryPage extends StatefulWidget {
  const FollowUpSummaryPage({super.key, this.aiOutput});

  final FollowUpAiOutput? aiOutput;

  @override
  State<FollowUpSummaryPage> createState() => _FollowUpSummaryPageState();
}

class _FollowUpSummaryPageState extends State<FollowUpSummaryPage> {
  DateTime? _selectedDate;
  final Set<String> _selectedTopics = {};
  final _discussionDetailsController = TextEditingController();
  final _additionalNotesController = TextEditingController();
  final _aggregator = FollowUpAiDataAggregator();
  final _aiService = FollowUpAiService();
  bool _isSaving = false;
  String? _aiError;
  FollowUpAiOutput? _confirmedOutput;
  FollowUpSummaryRecord? _latestFormalSummary;
  Timer? _draftSaveTimer;
  bool _isRestoringDraft = false;
  bool _isLoadingPreparation = true;
  bool _draftDirty = false;
  bool _allowDiaryReference = false;
  int _draftRevision = 0;
  String? _draftStatus;

  @override
  void initState() {
    super.initState();
    _confirmedOutput = widget.aiOutput;
    _discussionDetailsController.addListener(_queueDraftSave);
    _additionalNotesController.addListener(_queueDraftSave);
    AnalyticsService.logPage('follow_up_summary_page');
    _loadSavedPreparation();
    _loadLatestFormalSummary();
  }

  Future<void> _loadLatestFormalSummary() async {
    try {
      final summaries = await FollowUpService.listFormalSummaries();
      if (mounted && summaries.isNotEmpty) {
        setState(() {
          _latestFormalSummary = summaries.first;
          _confirmedOutput ??= summaries.first.aiOutput;
        });
      }
    } catch (_) {
      // The preparation flow remains usable if history cannot be loaded.
    }
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    if (_draftDirty) {
      final topics = _discussionTopics;
      final discussionDetails = _discussionDetailsController.text;
      final additionalNotes = _additionalNotesController.text;
      unawaited(
        FollowUpService.saveAiPreparation(
          discussionTopics: topics,
          discussionDetails: discussionDetails,
          additionalNotes: additionalNotes,
          allowDiaryReference: _allowDiaryReference,
        ).catchError((_) {}),
      );
    }
    _discussionDetailsController.dispose();
    _additionalNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPreparation() async {
    final workspace = await FollowUpService.getWorkspace();
    if (!mounted) return;
    _isRestoringDraft = true;
    final selectedTypes = workspace.aiDiscussionTopics.isNotEmpty
        ? workspace.aiDiscussionTopics
            .where((topic) => topic.selected)
            .map((topic) => _normalizedTopicType(topic.type))
            .toSet()
        : kTopicOptions
            .where((topic) => _legacyTopicSelected(
                  topic,
                  workspace.discussionTopics,
                ))
            .map((topic) => topic.type)
            .toSet();
    final migratedTopicNotes = workspace.aiDiscussionTopics
        .where((topic) => topic.note.trim().isNotEmpty)
        .map((topic) => '${topic.label}：${topic.note.trim()}')
        .join('\n');
    _discussionDetailsController.text = workspace.aiDiscussionDetails.isNotEmpty
        ? workspace.aiDiscussionDetails
        : migratedTopicNotes.isNotEmpty
            ? migratedTopicNotes
            : workspace.discussionDetails;
    _additionalNotesController.text = workspace.aiAdditionalNotes;
    setState(() {
      _selectedTopics
        ..clear()
        ..addAll(selectedTypes);
      _isLoadingPreparation = false;
      _allowDiaryReference = workspace.aiAllowDiaryReference;
      _draftStatus = selectedTypes.isNotEmpty ||
              _discussionDetailsController.text.trim().isNotEmpty ||
              _additionalNotesController.text.trim().isNotEmpty
          ? '已載入上次儲存的內容'
          : null;
    });
    _isRestoringDraft = false;
  }

  bool _legacyTopicSelected(
      FollowUpTopicOption option, List<String> savedLabels) {
    final aliases = <String, List<String>>{
      'mood': const ['情緒狀況', '情緒變化'],
      'sleep': const ['睡眠品質', '睡眠狀況'],
      'lifeUpdates': const ['生活近況', '食慾變化'],
      'workOrStudy': const ['工作／學業', '工作/學業'],
    };
    final labels = aliases[option.type] ?? <String>[option.label];
    return labels.any(savedLabels.contains);
  }

  String _normalizedTopicType(String type) =>
      type == 'appetite' ? 'lifeUpdates' : type;

  void _queueDraftSave() {
    if (_isRestoringDraft || !mounted) return;
    _draftDirty = true;
    final revision = ++_draftRevision;
    _draftSaveTimer?.cancel();
    setState(() => _draftStatus = '正在自動儲存…');
    _draftSaveTimer = Timer(
      const Duration(milliseconds: 700),
      () => _persistDraft(revision),
    );
  }

  Future<void> _persistDraft(int revision) async {
    try {
      await FollowUpService.saveAiPreparation(
        discussionTopics: _discussionTopics,
        discussionDetails: _discussionDetailsController.text,
        additionalNotes: _additionalNotesController.text,
        allowDiaryReference: _allowDiaryReference,
      );
      if (!mounted || revision != _draftRevision) return;
      setState(() {
        _draftDirty = false;
        _draftStatus = '已自動儲存';
      });
    } catch (_) {
      if (!mounted || revision != _draftRevision) return;
      setState(() => _draftStatus = '自動儲存失敗，開始整理時會再重試');
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 7)),
      lastDate: DateTime(now.year + 5),
      helpText: '選擇回診日期（可選）',
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  List<FollowUpDiscussionTopicInput> get _discussionTopics => kTopicOptions
      .map((topic) => FollowUpDiscussionTopicInput(
            type: topic.type,
            label: topic.label,
            selected: _selectedTopics.contains(topic.type),
            note: '',
          ))
      .toList();

  Future<List<Map<String, dynamic>>> _loadDiaryContext(
    FollowUpAiV1Input input,
  ) async {
    final entries = await DiaryRepository().listInRange(
      input.statistics.periodStart,
      input.statistics.periodEnd,
    );
    String date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    return entries
        .map((entry) => <String, dynamic>{
              'date': date(entry.date),
              if (entry.title.trim().isNotEmpty) 'title': entry.title.trim(),
              'content': entry.content,
              if ((entry.highlight ?? '').trim().isNotEmpty)
                'highlight': entry.highlight!.trim(),
              if ((entry.proudOf ?? '').trim().isNotEmpty)
                'proudOf': entry.proudOf!.trim(),
              if ((entry.selfCare ?? '').trim().isNotEmpty)
                'selfCare': entry.selfCare!.trim(),
              if ((entry.gratitude ?? '').trim().isNotEmpty)
                'gratitude': entry.gratitude!.trim(),
            })
        .where((entry) => entry.entries.any(
              (field) =>
                  field.key != 'date' && '${field.value}'.trim().isNotEmpty,
            ))
        .toList(growable: false);
  }

  Future<void> _startAiSummary() async {
    if (_selectedTopics.isEmpty &&
        _discussionDetailsController.text.trim().isEmpty &&
        _additionalNotesController.text.trim().isEmpty &&
        !_allowDiaryReference) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少選擇一個主題或輸入想討論的內容')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _aiError = null;
    });

    try {
      final topics = _discussionTopics;
      await FollowUpService.saveAiPreparation(
        discussionTopics: topics,
        discussionDetails: _discussionDetailsController.text,
        additionalNotes: _additionalNotesController.text,
        allowDiaryReference: _allowDiaryReference,
      );
      _draftSaveTimer?.cancel();
      _draftDirty = false;
      if (mounted) setState(() => _draftStatus = '已自動儲存');
      var input = await _aggregator.build(
        discussionTopics: topics,
        discussionDetails: _discussionDetailsController.text,
        additionalNotes: _additionalNotesController.text,
        currentAppointmentDate: _selectedDate,
      );
      if (_allowDiaryReference) {
        input = input.copyWith(
          diaryContext: await _loadDiaryContext(input),
        );
      }
      if (!mounted) return;
      final questions = await _aiService.generateFollowUpQuestions(input);
      if (!mounted) return;
      final answers = questions.isEmpty
          ? const <String, String>{}
          : await _showFollowUpQuestions(questions);
      if (!mounted || answers == null) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }
      final summary = await _aiService.generateSummary(
        input,
        followUpAnswers: answers,
      );
      if (!mounted) return;
      setState(() => _isSaving = false);
      final confirmed = await Navigator.push<FollowUpAiPreviewResult>(
        context,
        MaterialPageRoute(
          builder: (_) => FollowUpAiPreviewPage(
            initialSummary: summary,
            initialAdditionalNotes: _additionalNotesController.text.trim(),
            aiInput: input,
            onRegenerate: (additionalNotes) => _aiService.generateSummary(
              input.copyWith(additionalNotes: additionalNotes),
              followUpAnswers: answers,
            ),
            errorMessage: _errorMessage,
          ),
        ),
      );
      if (!mounted || confirmed == null) return;
      setState(() {
        _confirmedOutput = confirmed.summary;
        _additionalNotesController.text = confirmed.additionalNotes;
      });
      await FollowUpService.saveAiPreparation(
        discussionTopics: topics,
        discussionDetails: _discussionDetailsController.text,
        additionalNotes: confirmed.additionalNotes,
        allowDiaryReference: _allowDiaryReference,
      );
      await FollowUpService.saveAiSummary(
        confirmed.summary,
        additionalNotes: confirmed.additionalNotes,
      );
      final formalSummary = await FollowUpService.createFormalSummary(
        input: input.copyWith(additionalNotes: confirmed.additionalNotes),
        output: confirmed.summary,
        appointmentDate: _selectedDate,
      );
      _latestFormalSummary = formalSummary;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 回診摘要已確認並儲存')),
      );
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FollowUpSummaryDetailPage(summary: formalSummary),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _aiError = _errorMessage(error);
      });
    }
  }

  Future<Map<String, String>?> _showFollowUpQuestions(
      List<String> questions) async {
    final controllers = [for (final _ in questions) TextEditingController()];
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 想先確認幾件事'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('可留白；AI 不會重問紀錄中已有的資訊。'),
              const SizedBox(height: 12),
              for (var index = 0; index < questions.length; index++) ...[
                Text('${index + 1}. ${questions[index]}'),
                const SizedBox(height: 6),
                TextField(
                  controller: controllers[index],
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: '補充回答（可留白）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, {
              for (var index = 0; index < questions.length; index++)
                questions[index]: controllers[index].text.trim(),
            }),
            child: const Text('產生摘要'),
          ),
        ],
      ),
    );
    // Navigator.pop completes before the dialog's reverse transition has fully
    // removed its TextFields. Keep their controllers alive until that route is
    // detached to avoid disposing dependencies that are still mounted.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    for (final controller in controllers) {
      controller.dispose();
    }
    return result;
  }

  String _errorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      return aiCallableErrorMessage(
        error,
        functionName: AiCallableEndpoints.chat,
        isSignedIn: FirebaseAuth.instance.currentUser != null,
      );
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        backgroundColor: HealingDesignSystem.primaryBlue,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(
            color: HealingDesignSystem.adaptivePrimaryText(context)),
        title: Text(
          '準備回診摘要',
          style: TextStyle(
            color: HealingDesignSystem.adaptivePrimaryText(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          FollowUpAiHighlightsCard(
            output: _confirmedOutput,
            onTap: _latestFormalSummary == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FollowUpSummaryDetailPage(
                          summary: _latestFormalSummary!,
                        ),
                      ),
                    ),
          ),
          const SizedBox(height: 16),
          // 說明卡片
          Container(
            padding: const EdgeInsets.all(18),
            decoration: HealingDesignSystem.adaptiveCardDecoration(
              context,
              radius: HealingDesignSystem.radiusL,
              shadows: [
                HealingDesignSystem.shadowMedium(
                    color: HealingDesignSystem.primaryBlue)
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: HealingDesignSystem.primaryGradient(),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child:
                      const Icon(Icons.summarize_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '讓 AI 幫你整理',
                        style: HealingDesignSystem.titleMedium.copyWith(
                          color:
                              HealingDesignSystem.adaptivePrimaryText(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '選取主題並補充內容，AI 會自動整理上次到本次回診期間的紀錄。',
                        style: TextStyle(
                          color: HealingDesignSystem.adaptiveSecondaryText(
                              context),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 回診日期（可選）
          _SectionCard(
            title: '回診日期（可選）',
            icon: Icons.calendar_today_outlined,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: HealingDesignSystem.adaptiveFill(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: HealingDesignSystem.adaptiveCardBorder(context)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedDate == null
                            ? '選擇摘要對應日期（不會新增回診排程）'
                            : '${_selectedDate!.year}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: _selectedDate == null
                              ? HealingDesignSystem.adaptiveSecondaryText(
                                  context)
                              : HealingDesignSystem.adaptivePrimaryText(
                                  context),
                        ),
                      ),
                    ),
                    if (_selectedDate != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _selectedDate = null),
                      ),
                    Icon(Icons.chevron_right,
                        color:
                            HealingDesignSystem.adaptiveSecondaryText(context)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 想討論的主題
          _SectionCard(
            title: '想跟醫師討論的主題',
            icon: Icons.topic_outlined,
            child: _isLoadingPreparation
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : Builder(builder: (context) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: kTopicOptions.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            mainAxisExtent: 44,
                          ),
                          itemBuilder: (context, index) {
                            final topic = kTopicOptions[index];
                            final selected =
                                _selectedTopics.contains(topic.type);
                            return SizedBox.expand(
                              child: FilterChip(
                                key: ValueKey('topic-${topic.type}'),
                                selected: selected,
                                showCheckmark: true,
                                label: SizedBox(
                                  width: double.infinity,
                                  child: Text(
                                    topic.label,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                onSelected: (value) {
                                  setState(() {
                                    if (value) {
                                      _selectedTopics.add(topic.type);
                                    } else {
                                      _selectedTopics.remove(topic.type);
                                    }
                                  });
                                  _queueDraftSave();
                                },
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Divider(
                          color:
                              HealingDesignSystem.adaptiveCardBorder(context),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '想討論的內容（可選）',
                          style: HealingDesignSystem.titleSmall.copyWith(
                            color: HealingDesignSystem.adaptivePrimaryText(
                                context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          key: const ValueKey('discussion-details'),
                          controller: _discussionDetailsController,
                          minLines: 3,
                          maxLines: 7,
                          decoration: InputDecoration(
                            hintText: '統一補充上述主題想和醫師討論的內容',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor:
                                HealingDesignSystem.adaptiveFill(context),
                          ),
                        ),
                      ],
                    );
                  }),
          ),
          const SizedBox(height: 12),

          // 自由填寫
          _SectionCard(
            title: '其他想討論的事（可選）',
            icon: Icons.notes_outlined,
            child: TextField(
              key: const ValueKey('additional-notes'),
              controller: _additionalNotesController,
              enabled: !_isLoadingPreparation,
              minLines: 3,
              maxLines: 6,
              style: TextStyle(
                color: HealingDesignSystem.adaptivePrimaryText(context),
              ),
              decoration: InputDecoration(
                hintText: '例如：近期生活事件、開心的事，或其他想讓醫師知道的內容',
                helperText: '可補充未包含在上方主題中的事情，內容會原樣保留。',
                helperMaxLines: 2,
                hintStyle: TextStyle(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: HealingDesignSystem.adaptiveFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: HealingDesignSystem.adaptiveCardBorder(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: HealingDesignSystem.adaptiveCardBorder(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: HealingDesignSystem.primaryBlue, width: 1.4),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '日記內容',
            icon: Icons.auto_stories_outlined,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('允許 AI 參考本次回診期間的日記內容'),
              subtitle: const Text(
                '預設關閉；只讀取本次統計期間，產生的候選重點需由你勾選後才會加入摘要。',
              ),
              value: _allowDiaryReference,
              onChanged: _isLoadingPreparation
                  ? null
                  : (value) {
                      setState(() => _allowDiaryReference = value);
                      _queueDraftSave();
                    },
            ),
          ),
          if (_draftStatus != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  _draftStatus == '已自動儲存'
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_sync_outlined,
                  size: 15,
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                ),
                const SizedBox(width: 5),
                Text(
                  _draftStatus!,
                  style: HealingDesignSystem.bodySmall.copyWith(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),

          if (_aiError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(_aiError!)),
                  TextButton(
                    onPressed: _isSaving ? null : _startAiSummary,
                    child: const Text('重試'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // AI 整理按鈕
          FilledButton.icon(
            onPressed: _isSaving ? null : _startAiSummary,
            style: FilledButton.styleFrom(
              backgroundColor: HealingDesignSystem.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(
              _isSaving ? '正在整理本次回診期間紀錄⋯' : '開始 AI 回診整理',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class FollowUpAiHighlightsCard extends StatelessWidget {
  const FollowUpAiHighlightsCard({
    super.key,
    this.output,
    this.onTap,
  });

  static const unavailableMessage = '完成足夠紀錄後，可由 AI 整理近期主要變化與回診討論重點。';

  final FollowUpAiOutput? output;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
      child: Card(
        elevation: 0,
        color: HealingDesignSystem.adaptiveSurface(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
          side: BorderSide(
            color: HealingDesignSystem.primaryBlue.withValues(alpha: 0.28),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: HealingDesignSystem.primaryBlue
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 19,
                      color: HealingDesignSystem.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AI 回診重點',
                      style: HealingDesignSystem.titleMedium.copyWith(
                        color: HealingDesignSystem.adaptivePrimaryText(context),
                      ),
                    ),
                  ),
                  _AiStatusBadge(isReady: output != null),
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: HealingDesignSystem.adaptiveSecondaryText(context),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              if (output == null)
                Text(
                  unavailableMessage,
                  style: HealingDesignSystem.bodyMedium.copyWith(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                    height: 1.5,
                  ),
                )
              else
                Text(
                  '最新摘要已完成',
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
              if (onTap != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('open-follow-up-ai-summary'),
                    onPressed: onTap,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      output == null ? '開始準備 AI 回診摘要' : '查看／重新整理 AI 回診摘要',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AiStatusBadge extends StatelessWidget {
  const _AiStatusBadge({required this.isReady});

  final bool isReady;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: HealingDesignSystem.adaptiveFill(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isReady ? '已整理' : '準備中',
        style: HealingDesignSystem.bodySmall.copyWith(
          color: HealingDesignSystem.adaptiveSecondaryText(context),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// Kept for compatibility with callers that may restore the expanded card.
// ignore: unused_element
class _AiOutputContent extends StatelessWidget {
  const _AiOutputContent({required this.output});

  final FollowUpAiOutput output;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AiOutputSection(title: '主要變化', items: output.keyChanges),
        _AiOutputSection(
          title: '紀錄證據摘要',
          items: output.recordEvidenceHighlights,
        ),
        _AiOutputSection(
          title: '主觀用藥感受',
          items: output.medicationSubjectiveSummaries,
        ),
        _AiOutputSection(
          title: '其他想跟醫師說的內容',
          items: output.userSharedNotes,
        ),
        _AiOutputSection(title: '資料限制', items: output.dataLimitations),
        Text(
          '整理時間：${output.generatedAt.toLocal().year}/'
          '${output.generatedAt.toLocal().month.toString().padLeft(2, '0')}/'
          '${output.generatedAt.toLocal().day.toString().padLeft(2, '0')}',
          style: HealingDesignSystem.bodySmall.copyWith(
            color: HealingDesignSystem.adaptiveSecondaryText(context),
          ),
        ),
      ],
    );
  }
}

class _AiOutputSection extends StatelessWidget {
  const _AiOutputSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: HealingDesignSystem.titleSmall.copyWith(
              color: HealingDesignSystem.adaptivePrimaryText(context),
            ),
          ),
          const SizedBox(height: 4),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '• $item',
                style: HealingDesignSystem.bodyMedium.copyWith(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

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
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
                  child: Icon(icon,
                      size: 16, color: HealingDesignSystem.primaryBlue),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
