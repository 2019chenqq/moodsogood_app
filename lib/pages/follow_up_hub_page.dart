import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr/qr.dart';

import '../analytics_service.dart';
import '../constants/healing_design_system.dart';
import '../daily/daily_record_helpers.dart';
import 'trend_review_hub_page.dart';
import '../meds/med_symptom_compare_page.dart';
import '../meds/medication_local_db.dart';
import '../meds/record_adjustment_page.dart';
import '../services/follow_up_service.dart';
import '../widgets/main_drawer.dart';
import 'export_report_page.dart';
import 'follow_up_summary_history_page.dart';
import 'follow_up_summary_page.dart';

const _discussionTopicOptions = [
  '情緒變化',
  '睡眠狀況',
  '藥效與劑量',
  '藥物副作用',
  '身體不適',
  '食慾變化',
  '生活壓力',
  '工作／學業',
  '人際關係',
  '其他',
];

class FollowUpHubPage extends StatefulWidget {
  const FollowUpHubPage({super.key});

  @override
  State<FollowUpHubPage> createState() => _FollowUpHubPageState();
}

class _FollowUpHubPageState extends State<FollowUpHubPage> {
  List<FollowUpAppointment> _appointments = const [];
  bool _isLoading = true;
  FollowUpWorkspace _workspace = const FollowUpWorkspace();
  final _instructionsController = TextEditingController();
  final _discussionDetailsController = TextEditingController();
  final Set<String> _selectedTopics = {};
  List<FollowUpInstructionHistoryItem> _instructionHistory = const [];
  bool _isLoadingWorkspace = true;
  bool _isSavingWorkspace = false;
  bool _isPreparingReport = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('follow_up_hub_page');
    _loadAppointments();
    _loadWorkspace();
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    _discussionDetailsController.dispose();
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
    _discussionDetailsController.text = workspace.discussionDetails;
    setState(() {
      _workspace = workspace;
      _selectedTopics
        ..clear()
        ..addAll(workspace.discussionTopics);
      _instructionHistory = history;
      _isLoadingWorkspace = false;
    });
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadAppointments(),
      _loadWorkspace(),
    ]);
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
    final topics = _discussionTopicOptions
        .where(_selectedTopics.contains)
        .toList(growable: false);
    final details = _discussionDetailsController.text.trim();

    try {
      await FollowUpService.saveDiscussion(
        topics: topics,
        details: details,
      );
      if (!mounted) return;
      setState(() {
        _workspace = _workspace.copyWith(
          discussionTopics: topics,
          discussionDetails: details,
          updatedAt: DateTime.now(),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已儲存下次回診想討論的問題')),
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
  }

  Future<void> _editAppointment(FollowUpAppointment existing) async {
    final appointment = await _showAppointmentEditor(existing: existing);
    if (appointment == null) return;
    await FollowUpService.updateAppointment(appointment);
    await _loadAppointments();
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
  }

  Future<FollowUpAppointment?> _showAppointmentEditor({
    FollowUpAppointment? existing,
  }) async {
    DateTime? selectedDate = existing?.date;
    final labelController = TextEditingController(text: existing?.label ?? '');
    final noteController = TextEditingController(text: existing?.note ?? '');

    final result = await showDialog<FollowUpAppointment>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '新增回診' : '編輯回診'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          selectedDate ?? now.add(const Duration(days: 30)),
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 5),
                      helpText: '選擇回診日期',
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '回診日期',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(
                      selectedDate == null
                          ? '請選擇日期'
                          : _formatDate(selectedDate!),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: '科別／院所（可選）',
                    hintText: '例如：身心科、○○診所',
                    prefixIcon: Icon(Icons.local_hospital_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: selectedDate == null
                  ? null
                  : () {
                      Navigator.pop(
                        dialogContext,
                        FollowUpAppointment(
                          id: existing?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          date: selectedDate!,
                          label: labelController.text.trim(),
                          note: noteController.text.trim().isEmpty
                              ? null
                              : noteController.text.trim(),
                        ),
                      );
                    },
              child: Text(existing == null ? '新增' : '儲存'),
            ),
          ],
        ),
      ),
    );

    labelController.dispose();
    noteController.dispose();
    return result;
  }

  void _openMedicationAdjustment() {
    Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RecordAdjustmentPage()),
    );
  }

  void _openRecentTrends() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TrendReviewHubPage(),
      ),
    );
  }

  void _openMedicationTrends() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MedSymptomComparePage()),
    );
  }

  Future<void> _openPdfReport() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _isPreparingReport) return;
    setState(() => _isPreparingReport = true);

    try {
      final results = await Future.wait<dynamic>([
        loadAllRecords(uid),
        MedicationLocalDB().getMedicationsForDisplay(uid),
      ]);
      final records = results[0] as List;
      final medicationMaps = results[1] as List<Map<String, dynamic>>;
      final medications = medicationMaps
          .where((medication) => medication['isActive'] != false)
          .map(_formatMedication)
          .where((medication) => medication.isNotEmpty)
          .toList();

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExportReportPage(
            records: records.cast(),
            medications: medications,
            followUpNotes: _buildReportLines(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('準備報告失敗：$e')),
      );
    } finally {
      if (mounted) setState(() => _isPreparingReport = false);
    }
  }

  String _formatMedication(Map<String, dynamic> medication) {
    final name = (medication['name'] ?? '').toString().trim();
    if (name.isEmpty) return '';
    final dose = medication['dose'];
    final unit = (medication['unit'] ?? '').toString().trim();
    final times = (medication['times'] as List?)
            ?.map((time) => time.toString())
            .where((time) => time.isNotEmpty)
            .join('、') ??
        '';
    return [
      name,
      if (dose != null) '$dose$unit',
      if (times.isNotEmpty) times,
    ].join('・');
  }

  List<String> _buildReportLines() {
    final nextAppointments = _appointments
        .where((appointment) => appointment.daysUntil >= 0)
        .toList();
    return [
      if (nextAppointments.isNotEmpty) ...[
        '【下次回診】',
        '${_formatDate(nextAppointments.first.date)}'
            '${nextAppointments.first.label.isEmpty ? '' : '・${nextAppointments.first.label}'}',
        '',
      ],
      '【本次回診醫囑與醫師叮嚀】',
      _instructionsController.text.trim().isEmpty
          ? '尚未填寫'
          : _instructionsController.text.trim(),
      '',
      '【下次回診想討論的議題】',
      _selectedTopics.isEmpty ? '尚未選擇' : _selectedTopics.join('、'),
      '',
      '【詳細記錄】',
      _discussionDetailsController.text.trim().isEmpty
          ? '尚未填寫'
          : _discussionDetailsController.text.trim(),
    ];
  }

  String _buildQrPayload() {
    final fullText = _buildReportLines().join('\n');
    return _truncateForQr(fullText, 800);
  }

  void _showQrReport() {
    final payload = _buildQrPayload();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('回診摘要 QR Code'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 220,
                  child: CustomPaint(painter: _QrCodePainter(payload)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '掃描後可查看回診日期、醫囑與待討論問題。QR Code 只包含目前畫面上的文字，不會公開雲端資料。',
                style: HealingDesignSystem.bodySmall.copyWith(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    );
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
            _buildAppointmentsSection(context),
            const SizedBox(height: 16),
            _buildMedicationAdjustmentSection(context),
            const SizedBox(height: 16),
            _buildMedicalInstructionsSection(context),
            const SizedBox(height: 16),
            _buildDiscussionSection(context),
            const SizedBox(height: 16),
            _buildRecentTrendsSection(context),
            const SizedBox(height: 16),
            _buildReportSection(context),
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
              onPressed: _openMedicationAdjustment,
              icon: const Icon(Icons.edit_note_rounded),
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
      title: '下次回診想跟醫師討論的問題',
      subtitle: '先勾選議題，再補充你觀察到的細節',
      child: _isLoadingWorkspace
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _discussionTopicOptions.map((topic) {
                    final selected = _selectedTopics.contains(topic);
                    return FilterChip(
                      label: Text(topic),
                      selected: selected,
                      showCheckmark: true,
                      onSelected: (value) {
                        setState(() {
                          if (value) {
                            _selectedTopics.add(topic);
                          } else {
                            _selectedTopics.remove(topic);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  '詳細記錄',
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _discussionDetailsController,
                  minLines: 5,
                  maxLines: 10,
                  decoration: _followUpInputDecoration(
                    context,
                    '例如：換藥後第三天開始比較難入睡，想確認是否需要調整服藥時間。',
                  ),
                ),
                const SizedBox(height: 12),
                _buildSaveButton(
                  label: '儲存待討論問題',
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
      subtitle: '回顧情緒、睡眠、症狀與調藥後的變化',
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openRecentTrends,
              icon: const Icon(Icons.show_chart_rounded),
              label: const Text('查看情緒與睡眠趨勢'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openMedicationTrends,
              icon: const Icon(Icons.medication_outlined),
              label: const Text('比較調藥與症狀趨勢'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportSection(BuildContext context) {
    return _FollowUpSection(
      icon: Icons.auto_awesome_outlined,
      title: '回診摘要',
      subtitle: '整理近期紀錄，準備與醫師討論',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'AI 會整理近期情緒、睡眠、症狀、用藥變化與想和醫師討論的重點；確認後才會儲存為正式摘要。',
            style: HealingDesignSystem.bodyMedium.copyWith(
              color: HealingDesignSystem.adaptiveSecondaryText(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FollowUpSummaryPage(),
                  ),
                ),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('產生 AI 回診摘要'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FollowUpSummaryHistoryPage(),
                  ),
                ),
                icon: const Icon(Icons.history_rounded),
                label: const Text('查看歷次摘要'),
              ),
            ),
            const SizedBox(height: 8),
          Text(
            '回診專區目前免費開放測試；內容僅供整理與溝通參考，不取代醫師診斷。',
            style: HealingDesignSystem.bodySmall.copyWith(
              color: HealingDesignSystem.adaptiveSecondaryText(context),
            ),
          ),
        ],
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

String _truncateForQr(String value, int maxLength) {
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength)}…';
}

class _QrCodePainter extends CustomPainter {
  _QrCodePainter(String data)
      : _image = QrImage(
          QrCode.fromData(
            data: data,
            errorCorrectLevel: QrErrorCorrectLevel.L,
          ),
        );

  final QrImage _image;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, background);

    const quietZone = 4;
    final totalModules = _image.moduleCount + quietZone * 2;
    final moduleSize = size.shortestSide / totalModules;
    final darkPaint = Paint()..color = Colors.black;

    for (var row = 0; row < _image.moduleCount; row++) {
      for (var column = 0; column < _image.moduleCount; column++) {
        if (!_image.isDark(row, column)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (column + quietZone) * moduleSize,
            (row + quietZone) * moduleSize,
            moduleSize + 0.1,
            moduleSize + 0.1,
          ),
          darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrCodePainter oldDelegate) {
    return false;
  }
}
