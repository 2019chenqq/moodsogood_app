import 'package:flutter/material.dart';

import '../analytics_service.dart';
import '../constants/healing_design_system.dart';
import '../models/follow_up_ai_summary.dart';
import 'trend_review_hub_page.dart';
import '../meds/record_adjustment_page.dart';
import '../services/follow_up_service.dart';
import '../services/follow_up_reminder_service.dart';
import '../widgets/main_drawer.dart';
import 'follow_up_summary_page.dart';
import 'follow_up_summary_history_page.dart';

class FollowUpHubPage extends StatefulWidget {
  const FollowUpHubPage({
    super.key,
    this.promptAddAppointment = false,
    this.aiOutput,
  });

  final bool promptAddAppointment;
  final FollowUpAiOutput? aiOutput;

  @override
  State<FollowUpHubPage> createState() => _FollowUpHubPageState();
}

class _FollowUpHubPageState extends State<FollowUpHubPage> {
  List<FollowUpAppointment> _appointments = const [];
  bool _isLoading = true;
  FollowUpWorkspace _workspace = const FollowUpWorkspace();
  final _instructionsController = TextEditingController();
  final _discussionDetailsController = TextEditingController();
  final _additionalNotesController = TextEditingController();
  final Set<String> _selectedTopics = {};
  List<FollowUpInstructionHistoryItem> _instructionHistory = const [];
  bool _isLoadingWorkspace = true;
  bool _isSavingWorkspace = false;
  bool _isOpeningMedicationAdjustment = false;
  final _reminderService = FollowUpReminderService();
  FollowUpReminderSettings _reminderSettings = const FollowUpReminderSettings();
  bool _isLoadingReminderSettings = true;
  bool _isSavingReminderSettings = false;
  List<FollowUpScheduledReminder> _scheduledReminders = const [];

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('follow_up_hub_page');
    _initializePage();
    if (widget.promptAddAppointment) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addAppointment();
      });
    }
  }

  Future<void> _initializePage() async {
    await Future.wait([_loadAppointments(), _loadWorkspace()]);
    await _loadReminderSettings(reschedule: true);
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    _discussionDetailsController.dispose();
    _additionalNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadAppointments() async {
    final appointments = await FollowUpService.getAppointments();
    if (!mounted) return;
    setState(() {
      _appointments = appointments;
      _isLoading = false;
    });
  }

  Future<void> _loadWorkspace() async {
    final workspace = await FollowUpService.getWorkspace();
    final history = await FollowUpService.getInstructionHistory();
    if (!mounted) return;
    _instructionsController.text = workspace.medicalInstructions;
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
      _workspace = workspace;
      _selectedTopics
        ..clear()
        ..addAll(
          workspace.aiDiscussionTopics.isNotEmpty
              ? workspace.aiDiscussionTopics
                  .where((topic) => topic.selected)
                  .map((topic) => _normalizedTopicType(topic.type))
              : kTopicOptions
                  .where((topic) => _legacyTopicSelected(
                        topic,
                        workspace.discussionTopics,
                      ))
                  .map((topic) => topic.type),
        );
      _instructionHistory = history;
      _isLoadingWorkspace = false;
    });
  }

  bool _legacyTopicSelected(
      FollowUpTopicOption option, List<String> savedLabels) {
    final aliases = <String, List<String>>{
      'mood': const ['情緒狀況', '情緒變化'],
      'sleep': const ['睡眠品質', '睡眠狀況'],
      'medicationSideEffects': const ['藥物副作用', '藥效與劑量'],
      'lifeUpdates': const ['生活近況', '食慾變化'],
      'workOrStudy': const ['工作／學業', '工作/學業'],
    };
    final labels = aliases[option.type] ?? <String>[option.label];
    return labels.any(savedLabels.contains);
  }

  String _normalizedTopicType(String type) =>
      type == 'appetite' ? 'lifeUpdates' : type;

  List<FollowUpDiscussionTopicInput> get _sharedDiscussionTopics =>
      kTopicOptions
          .map(
            (topic) => FollowUpDiscussionTopicInput(
              type: topic.type,
              label: topic.label,
              selected: _selectedTopics.contains(topic.type),
              note: '',
            ),
          )
          .toList();

  Future<void> _loadReminderSettings({bool reschedule = false}) async {
    final settings = await _reminderService.loadSettings();
    if (!mounted) return;
    setState(() {
      _reminderSettings = settings;
      _isLoadingReminderSettings = false;
    });
    if (reschedule) {
      final result = await _reminderService.reschedule(
        settings: settings,
        appointments: _appointments,
      );
      if (mounted) {
        setState(() => _scheduledReminders = result.reminders);
      }
    }
  }

  Future<void> _updateReminderSettings(
      FollowUpReminderSettings settings) async {
    if (_isSavingReminderSettings) return;
    final previous = _reminderSettings;
    setState(() {
      _reminderSettings = settings;
      _isSavingReminderSettings = true;
    });
    try {
      final result = await _reminderService.saveAndReschedule(
        settings: settings,
        appointments: _appointments,
      );
      if (!mounted) return;
      setState(() => _scheduledReminders = result.reminders);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_appointments.isEmpty
              ? '設定已儲存；新增回診日期後會自動建立提醒'
              : '回診提醒已更新（已排程 ${result.count} 筆）'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _reminderSettings = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新回診提醒失敗：$error')),
      );
    } finally {
      if (mounted) setState(() => _isSavingReminderSettings = false);
    }
  }

  Future<void> _pickReminderTime() async {
    if (_isSavingReminderSettings) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _reminderSettings.reminderHour,
        minute: _reminderSettings.reminderMinute,
      ),
      helpText: '選擇回診提醒時間',
      cancelText: '取消',
      confirmText: '確定',
    );
    if (picked == null || !mounted) return;
    await _updateReminderSettings(
      _reminderSettings.copyWith(
        reminderHour: picked.hour,
        reminderMinute: picked.minute,
      ),
    );
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadAppointments(),
      _loadWorkspace(),
    ]);
    await _loadReminderSettings(reschedule: true);
  }

  Future<void> _saveMedicalInstructions() async {
    if (_isSavingWorkspace) return;
    setState(() => _isSavingWorkspace = true);
    final instructions = _instructionsController.text.trim();

    try {
      await FollowUpService.saveMedicalInstructions(instructions);
      final history = await FollowUpService.getInstructionHistory();
      if (!mounted) return;
      setState(() {
        _workspace = _workspace.copyWith(
          medicalInstructions: instructions,
          medicalInstructionsUpdatedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        _instructionHistory = history;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已儲存本次回診醫囑')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存失敗：$e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingWorkspace = false);
    }
  }

  Future<void> _saveDiscussion() async {
    if (_isSavingWorkspace) return;
    setState(() => _isSavingWorkspace = true);
    final details = _discussionDetailsController.text.trim();
    final additionalNotes = _additionalNotesController.text.trim();
    final topics = _sharedDiscussionTopics;

    try {
      await FollowUpService.saveAiPreparation(
        discussionTopics: topics,
        discussionDetails: details,
        additionalNotes: additionalNotes,
      );
      if (!mounted) return;
      setState(() {
        _workspace = _workspace.copyWith(
          aiDiscussionTopics: topics,
          aiDiscussionDetails: details,
          aiAdditionalNotes: additionalNotes,
          updatedAt: DateTime.now(),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已同步至準備回診摘要')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存失敗：$e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingWorkspace = false);
    }
  }

  void _showInstructionHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final currentInstructions = _workspace.medicalInstructions.trim();
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            builder: (context, scrollController) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                Text(
                  '歷次回診醫囑與叮嚀',
                  style: HealingDesignSystem.titleLarge.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                const SizedBox(height: 16),
                if (currentInstructions.isNotEmpty)
                  _InstructionHistoryCard(
                    title: '目前版本',
                    instructions: currentInstructions,
                    date: _workspace.medicalInstructionsUpdatedAt,
                    isCurrent: true,
                  ),
                if (currentInstructions.isNotEmpty &&
                    _instructionHistory.isNotEmpty)
                  const SizedBox(height: 12),
                ..._instructionHistory.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _InstructionHistoryCard(
                      title: '過往版本',
                      instructions: item.medicalInstructions,
                      date: item.recordedAt ?? item.archivedAt,
                    ),
                  ),
                ),
                if (currentInstructions.isEmpty && _instructionHistory.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        '還沒有儲存過醫囑或叮嚀',
                        style: HealingDesignSystem.bodyMedium.copyWith(
                          color: HealingDesignSystem.adaptiveSecondaryText(
                            context,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addAppointment() async {
    final appointment = await _showAppointmentEditor();
    if (appointment == null) return;
    await FollowUpService.addAppointment(appointment);
    await _loadAppointments();
    final result = await _reminderService.reschedule(
      settings: _reminderSettings,
      appointments: _appointments,
    );
    if (mounted) setState(() => _scheduledReminders = result.reminders);
  }

  Future<void> _editAppointment(FollowUpAppointment existing) async {
    final appointment = await _showAppointmentEditor(existing: existing);
    if (appointment == null) return;
    await FollowUpService.updateAppointment(appointment);
    await _loadAppointments();
    final result = await _reminderService.reschedule(
      settings: _reminderSettings,
      appointments: _appointments,
    );
    if (mounted) setState(() => _scheduledReminders = result.reminders);
  }

  Future<void> _deleteAppointment(FollowUpAppointment appointment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除回診日期？'),
        content: Text('確定要刪除 ${_formatDate(appointment.date)}'
            '${appointment.label.isEmpty ? '' : '・${appointment.label}'} 嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: HealingDesignSystem.dangerRed,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FollowUpService.deleteAppointment(appointment.id);
    await _loadAppointments();
    final result = await _reminderService.reschedule(
      settings: _reminderSettings,
      appointments: _appointments,
    );
    if (mounted) setState(() => _scheduledReminders = result.reminders);
  }

  Future<FollowUpAppointment?> _showAppointmentEditor({
    FollowUpAppointment? existing,
  }) async {
    return showDialog<FollowUpAppointment>(
      context: context,
      builder: (_) => _AppointmentEditorDialog(existing: existing),
    );
  }

  Future<void> _openMedicationAdjustment() async {
    if (_isOpeningMedicationAdjustment) return;
    setState(() => _isOpeningMedicationAdjustment = true);
    try {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const RecordAdjustmentPage()),
      );
    } finally {
      if (mounted) {
        setState(() => _isOpeningMedicationAdjustment = false);
      }
    }
  }

  void _openRecentTrends() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TrendReviewHubPage(),
      ),
    );
  }

  Future<void> _openFollowUpSummary() async {
    if (_isLoadingWorkspace) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在載入共同主題，請稍候再試')),
      );
      return;
    }
    try {
      await FollowUpService.saveAiPreparation(
        discussionTopics: _sharedDiscussionTopics,
        discussionDetails: _discussionDetailsController.text,
        additionalNotes: _additionalNotesController.text,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('同步共同主題失敗：$error')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowUpSummaryPage(aiOutput: widget.aiOutput),
      ),
    );
    if (mounted) await _loadWorkspace();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      drawer: const MainDrawer(),
      appBar: AppBar(
        backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
        foregroundColor: HealingDesignSystem.adaptiveAppBarForeground(context),
        surfaceTintColor: Colors.transparent,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '回診專區',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(width: 8),
            _BetaBadge(),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
          children: [
            Text(
              '把想告訴醫師的事，慢慢整理在這裡。',
              style: HealingDesignSystem.bodyMedium.copyWith(
                color: HealingDesignSystem.adaptiveSecondaryText(context),
              ),
            ),
            const SizedBox(height: 16),
            FollowUpAiHighlightsCard(
              output: widget.aiOutput,
              onTap: _openFollowUpSummary,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FollowUpSummaryHistoryPage(),
                ),
              ),
              icon: const Icon(Icons.history_rounded),
              label: const Text('歷次回診摘要'),
            ),
            const SizedBox(height: 16),
            _buildAppointmentsSection(context),
            const SizedBox(height: 16),
            _buildReminderSettingsSection(context),
            const SizedBox(height: 16),
            _buildMedicationAdjustmentSection(context),
            const SizedBox(height: 16),
            _buildMedicalInstructionsSection(context),
            const SizedBox(height: 16),
            _buildDiscussionSection(context),
            const SizedBox(height: 16),
            _buildRecentTrendsSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentsSection(BuildContext context) {
    final upcoming = _appointments
        .where((appointment) => appointment.daysUntil >= 0)
        .toList();
    final past = _appointments
        .where((appointment) => appointment.daysUntil < 0)
        .toList();

    return _FollowUpSection(
      icon: Icons.event_note_rounded,
      title: '回診日期',
      subtitle: upcoming.isEmpty
          ? '新增下一次回診，讓準備更有餘裕'
          : '下一次回診還有 ${upcoming.first.daysUntil} 天',
      trailing: IconButton(
        tooltip: '新增回診',
        onPressed: _addAppointment,
        icon: const Icon(Icons.add_circle_outline_rounded),
        color: HealingDesignSystem.adaptiveAccent(context),
      ),
      child: _isLoading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : _appointments.isEmpty
              ? _EmptyAppointment(onTap: _addAppointment)
              : Column(
                  children: [
                    ...upcoming.map(_buildAppointmentTile),
                    if (past.isNotEmpty)
                      ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                        childrenPadding: EdgeInsets.zero,
                        title: Text(
                          '過往回診（${past.length}）',
                          style: HealingDesignSystem.bodySmall.copyWith(
                            color: HealingDesignSystem.adaptiveSecondaryText(
                                context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        children: past.map(_buildAppointmentTile).toList(),
                      ),
                  ],
                ),
    );
  }

  Widget _buildAppointmentTile(FollowUpAppointment appointment) {
    final days = appointment.daysUntil;
    final status = days == 0
        ? '今天'
        : days > 0
            ? '$days 天後'
            : '${-days} 天前';
    final accent = days < 0
        ? HealingDesignSystem.mutedText
        : days == 0
            ? HealingDesignSystem.successGreen
            : HealingDesignSystem.primaryBlue;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 14, right: 4),
        leading: Icon(Icons.calendar_month_rounded, color: accent),
        title: Text(
          _formatDate(appointment.date),
          style: HealingDesignSystem.bodyMedium.copyWith(
            color: HealingDesignSystem.adaptivePrimaryText(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          [
            if (appointment.label.isNotEmpty) appointment.label,
            status,
            if (appointment.note?.isNotEmpty == true) appointment.note!,
          ].join('・'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: HealingDesignSystem.bodySmall.copyWith(
            color: HealingDesignSystem.adaptiveSecondaryText(context),
          ),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: '回診選項',
          onSelected: (value) {
            if (value == 'edit') _editAppointment(appointment);
            if (value == 'delete') _deleteAppointment(appointment);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('編輯')),
            PopupMenuItem(value: 'delete', child: Text('刪除')),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderSettingsSection(BuildContext context) {
    return _FollowUpSection(
      icon: Icons.notifications_active_outlined,
      title: '回診前提醒',
      subtitle: '設定提醒時間，也可以開啟 AI 回診前關心',
      child: _isLoadingReminderSettings
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '回診前多久提醒',
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('前 1 天')),
                      ButtonSegment(value: 3, label: Text('前 3 天')),
                      ButtonSegment(value: 7, label: Text('前 7 天')),
                    ],
                    selected: {_reminderSettings.reminderDays},
                    onSelectionChanged: _isSavingReminderSettings
                        ? null
                        : (selection) => _updateReminderSettings(
                              _reminderSettings.copyWith(
                                reminderDays: selection.first,
                              ),
                            ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  key: const ValueKey('follow-up-reminder-time'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: _isSavingReminderSettings ? null : _pickReminderTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: HealingDesignSystem.adaptiveFill(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: HealingDesignSystem.adaptiveCardBorder(context),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule_rounded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '提醒時間',
                                style: HealingDesignSystem.bodySmall.copyWith(
                                  color:
                                      HealingDesignSystem.adaptiveSecondaryText(
                                          context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                TimeOfDay(
                                  hour: _reminderSettings.reminderHour,
                                  minute: _reminderSettings.reminderMinute,
                                ).format(context),
                                style: HealingDesignSystem.titleSmall.copyWith(
                                  color:
                                      HealingDesignSystem.adaptivePrimaryText(
                                          context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('開啟回診前 AI 關心'),
                  subtitle: const Text('提醒時邀請你直接進入 AI 回診整理'),
                  secondary: const Icon(Icons.auto_awesome_rounded),
                  value: _reminderSettings.aiCheckInEnabled,
                  onChanged: _isSavingReminderSettings
                      ? null
                      : (value) => _updateReminderSettings(
                            _reminderSettings.copyWith(
                              aiCheckInEnabled: value,
                            ),
                          ),
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text('已排程 ${_scheduledReminders.length} 筆通知'),
                  subtitle: const Text('展開查看通知時間與對應回診'),
                  children: _scheduledReminders.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                            child: Text(
                              _appointments.isEmpty
                                  ? '尚未新增未來回診日期。'
                                  : '目前沒有可排程通知；可能是所選提醒日期與時間已經過去。',
                              style: HealingDesignSystem.bodySmall.copyWith(
                                color:
                                    HealingDesignSystem.adaptiveSecondaryText(
                                        context),
                              ),
                            ),
                          ),
                        ]
                      : _scheduledReminders
                          .map(
                            (reminder) => ListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              leading: const Icon(
                                Icons.notifications_none_rounded,
                                size: 20,
                              ),
                              title: Text(
                                '通知：${_formatDateTime(reminder.scheduledAt)}',
                              ),
                              subtitle: Text(
                                '回診：${_formatDate(reminder.appointmentDate)}'
                                '・${reminder.appointmentLabel}',
                              ),
                            ),
                          )
                          .toList(),
                ),
                if (_isSavingReminderSettings)
                  const LinearProgressIndicator(minHeight: 2),
              ],
            ),
    );
  }

  Widget _buildMedicationAdjustmentSection(BuildContext context) {
    return _FollowUpSection(
      icon: Icons.medication_liquid_rounded,
      title: '記錄本次回診調藥',
      subtitle: '記下新增、停用、劑量或服用時間的調整',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '完成後會更新藥物紀錄，之後可與症狀及情緒趨勢一起比較。',
            style: HealingDesignSystem.bodyMedium.copyWith(
              color: HealingDesignSystem.adaptiveSecondaryText(context),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isOpeningMedicationAdjustment
                  ? null
                  : _openMedicationAdjustment,
              icon: _isOpeningMedicationAdjustment
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_note_rounded),
              label: const Text('記錄這次調藥'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalInstructionsSection(BuildContext context) {
    final instructionCount = _instructionHistory.length +
        (_workspace.medicalInstructions.trim().isEmpty ? 0 : 1);
    return _FollowUpSection(
      icon: Icons.assignment_turned_in_outlined,
      title: '本次回診醫囑與醫師叮嚀',
      subtitle: '保存醫師交代的用藥、生活與觀察事項',
      child: _isLoadingWorkspace
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              children: [
                TextField(
                  controller: _instructionsController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: _followUpInputDecoration(
                    context,
                    '例如：睡前藥改為半顆；若白天嗜睡持續一週，提前聯絡診所。',
                  ),
                ),
                const SizedBox(height: 12),
                _buildSaveButton(
                  label: '儲存醫囑與叮嚀',
                  onPressed: _saveMedicalInstructions,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _showInstructionHistory,
                    icon: const Icon(Icons.history_rounded),
                    label: Text(
                      '查看歷次醫囑'
                      '${instructionCount == 0 ? '' : '（$instructionCount）'}',
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDiscussionSection(BuildContext context) {
    return _FollowUpSection(
      icon: Icons.checklist_rounded,
      title: '想跟醫師討論的主題',
      subtitle: '與準備回診摘要共用主題與補充內容',
      child: _isLoadingWorkspace
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        HealingDesignSystem.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('此處與「準備回診摘要」共用，任一處儲存後都會同步。'),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: kTopicOptions.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    mainAxisExtent: 44,
                  ),
                  itemBuilder: (context, index) {
                    final topic = kTopicOptions[index];
                    final selected = _selectedTopics.contains(topic.type);
                    return SizedBox.expand(
                      child: FilterChip(
                        key: ValueKey('hub-topic-${topic.type}'),
                        label: SizedBox(
                          width: double.infinity,
                          child: Text(topic.label, textAlign: TextAlign.center),
                        ),
                        selected: selected,
                        showCheckmark: true,
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              _selectedTopics.add(topic.type);
                            } else {
                              _selectedTopics.remove(topic.type);
                            }
                          });
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Divider(
                  color: HealingDesignSystem.adaptiveCardBorder(context),
                ),
                const SizedBox(height: 8),
                Text(
                  '想討論的內容（可選）',
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('hub-discussion-details'),
                  controller: _discussionDetailsController,
                  minLines: 3,
                  maxLines: 7,
                  decoration: _followUpInputDecoration(
                    context,
                    '統一補充上述主題想和醫師討論的內容',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '其他想討論的事（可選）',
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '可補充未包含在上方主題中的事情，內容會原樣保留。',
                  style: HealingDesignSystem.bodySmall.copyWith(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('hub-additional-notes'),
                  controller: _additionalNotesController,
                  minLines: 3,
                  maxLines: 7,
                  decoration: _followUpInputDecoration(
                    context,
                    '例如：近期生活事件、開心的事，或其他想讓醫師知道的內容',
                  ),
                ),
                const SizedBox(height: 12),
                _buildSaveButton(
                  label: '儲存共同主題內容',
                  onPressed: _saveDiscussion,
                ),
              ],
            ),
    );
  }

  Widget _buildRecentTrendsSection(BuildContext context) {
    return _FollowUpSection(
      icon: Icons.insights_rounded,
      title: '近期趨勢',
      subtitle: '集中查看情緒、睡眠、症狀與調藥後的變化',
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _openRecentTrends,
          icon: const Icon(Icons.insights_rounded),
          label: const Text('前往趨勢回顧'),
        ),
      ),
    );
  }

  Widget _buildSaveButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isSavingWorkspace ? null : onPressed,
        icon: _isSavingWorkspace
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save_outlined),
        label: Text(label),
      ),
    );
  }

  InputDecoration _followUpInputDecoration(
    BuildContext context,
    String hintText,
  ) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: HealingDesignSystem.adaptiveSecondaryText(context),
      ),
      filled: true,
      fillColor: HealingDesignSystem.adaptiveFill(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
    );
  }
}

class _InstructionHistoryCard extends StatelessWidget {
  const _InstructionHistoryCard({
    required this.title,
    required this.instructions,
    this.date,
    this.isCurrent = false,
  });

  final String title;
  final String instructions;
  final DateTime? date;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final accent = isCurrent
        ? HealingDesignSystem.successGreen
        : HealingDesignSystem.primaryBlue;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCurrent
                    ? Icons.check_circle_outline_rounded
                    : Icons.history_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
              ),
              if (date != null)
                Text(
                  _formatDateTime(date!),
                  style: HealingDesignSystem.bodySmall.copyWith(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            instructions,
            style: HealingDesignSystem.bodyMedium.copyWith(
              color: HealingDesignSystem.adaptivePrimaryText(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowUpSection extends StatelessWidget {
  const _FollowUpSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: HealingDesignSystem.primaryGradient(),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: HealingDesignSystem.titleMedium.copyWith(
                        color: HealingDesignSystem.adaptivePrimaryText(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: HealingDesignSystem.bodySmall.copyWith(
                        color:
                            HealingDesignSystem.adaptiveSecondaryText(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EmptyAppointment extends StatelessWidget {
  const _EmptyAppointment({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        decoration: BoxDecoration(
          color: HealingDesignSystem.adaptiveFill(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: HealingDesignSystem.adaptiveCardBorder(context),
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              color: HealingDesignSystem.adaptiveAccent(context),
            ),
            const SizedBox(height: 8),
            Text(
              '新增第一個回診日期',
              style: HealingDesignSystem.bodyMedium.copyWith(
                color: HealingDesignSystem.adaptivePrimaryText(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentEditorDialog extends StatefulWidget {
  const _AppointmentEditorDialog({this.existing});

  final FollowUpAppointment? existing;

  @override
  State<_AppointmentEditorDialog> createState() =>
      _AppointmentEditorDialogState();
}

class _AppointmentEditorDialogState extends State<_AppointmentEditorDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _noteController;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.existing?.date;
    _labelController = TextEditingController(
      text: widget.existing?.label ?? '',
    );
    _noteController = TextEditingController(
      text: widget.existing?.note ?? '',
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: '選擇回診日期',
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDate = picked);
  }

  void _submit() {
    final selectedDate = _selectedDate;
    if (selectedDate == null) return;
    final note = _noteController.text.trim();
    Navigator.pop(
      context,
      FollowUpAppointment(
        id: widget.existing?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        date: selectedDate,
        label: _labelController.text.trim(),
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return AlertDialog(
      title: Text(isEditing ? '編輯回診' : '新增回診'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '回診日期',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(
                  _selectedDate == null ? '請選擇日期' : _formatDate(_selectedDate!),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: '科別／院所（可選）',
                hintText: '例如：身心科、○○診所',
                prefixIcon: Icon(Icons.local_hospital_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _noteController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '備註（可選）',
                hintText: '例如：抽血、看報告、記得帶藥袋',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedDate == null ? null : _submit,
          child: Text(isEditing ? '儲存' : '新增'),
        ),
      ],
    );
  }
}

class _BetaBadge extends StatelessWidget {
  const _BetaBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:
            HealingDesignSystem.adaptiveAccent(context).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Beta',
        style: HealingDesignSystem.bodySmall.copyWith(
          color: HealingDesignSystem.adaptiveAccent(context),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}/$month/$day';
}

String _formatDateTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${_formatDate(date)} $hour:$minute';
}
