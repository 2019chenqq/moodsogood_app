import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/healing_design_system.dart';
import '../utils/firebase_sync_config.dart';
import '../utils/health_data_encryption_service.dart';
import 'medication_local_db.dart';
import 'medication_reminder_service.dart';
import 'medication_dose_units.dart';
import 'medication_adjustment_service.dart';
import 'medication_dose_editor_dialog.dart';
import '../analytics_service.dart';

// 你已經有的新增藥物頁（路徑依你的專案調整）
import 'add_medication_page.dart';
import 'record_adjustment_history_page.dart';

/// 劑量編輯對話框由 [medication_dose_editor_dialog] 提供，
/// 透過 export 直接對外輸出，供測試與外部頁面使用。
export 'medication_dose_editor_dialog.dart'
    show
        MedicationDoseEditResult,
        MedicationDoseEditorDialog,
        MedicationOralDoseEditResult,
        MedicationOralDoseEditorDialog;

enum MedChangeType {
  unchanged,
  added,
  injected,
  doseChanged,
  scheduleChanged,
  stopped,
  resumed
}

const List<String> kAdjustmentTimeSlots = ['早上', '中午', '下午', '晚上', '睡前', '需要時'];

class RecordAdjustmentPage extends StatefulWidget {
  const RecordAdjustmentPage({super.key});

  @override
  State<RecordAdjustmentPage> createState() => _RecordAdjustmentPageState();
}

class _RecordAdjustmentPageState extends State<RecordAdjustmentPage> {
  DateTime _date = DateTime.now();
  final _noteCtrl = TextEditingController();
  Future<List<Map<String, dynamic>>> _medsFuture =
      Future.value(<Map<String, dynamic>>[]);

  // 每顆藥的暫存變動
  final Map<String, _MedDraft> _draftByDocId = {};
  final Set<String> _sessionNewlyAddedDocIds = <String>{};

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('record_adjustment_page');
    // 初始化時從 Firebase 同步最新藥物到本地
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _medsFuture = _loadMeds(uid);
      _syncFromFirebase(uid).then((_) {
        if (!mounted) return;
        setState(() {
          _medsFuture = _loadMeds(uid);
        });
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadMeds(String uid) async {
    final meds = await _getMedsForAdjustment(uid);
    meds.sort((a, b) {
      DateTime? parseDt(dynamic v) {
        if (v is String) return DateTime.tryParse(v);
        if (v is Timestamp) return v.toDate();
        return null;
      }

      final aCreated = parseDt(a['createdAt']);
      final bCreated = parseDt(b['createdAt']);
      if (aCreated != null && bCreated != null) {
        final byCreated = aCreated.compareTo(bCreated);
        if (byCreated != 0) return byCreated;
      }

      final aName = (a['name'] ?? '').toString();
      final bName = (b['name'] ?? '').toString();
      final byName = aName.compareTo(bName);
      if (byName != 0) return byName;

      return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
    });
    return meds;
  }

  Future<void> _syncFromFirebase(String uid) async {
    try {
      final docs = await HealthDataEncryptionService.getEncrypted(
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('medications'),
      );

      for (final doc in docs) {
        final data = doc.data;
        final startTs = data['startDate'];
        DateTime? startDate;
        if (startTs is Timestamp) startDate = startTs.toDate();
        if (startTs is String) startDate = DateTime.tryParse(startTs);

        final mapped = {
          'id': doc.id,
          'name': data['name'],
          'dose': data['dose'],
          'dosePerUnit': data['dosePerUnit'],
          'pillCount': data['pillCount'],
          'concentrationMg': data['concentrationMg'],
          'concentrationMl': data['concentrationMl'],
          'intakeMl': data['intakeMl'],
          'unit': data['unit'],
          'type': data['type'],
          'intervalDays': data['intervalDays'],
          'times': (data['times'] as List?)?.cast<String>() ?? <String>[],
          'purposes': (data['purposes'] as List?)?.cast<String>() ?? <String>[],
          'note': data['note'],
          'startDate': startDate?.toString(),
          'isActive': data['isActive'] ?? true,
          'bodySymptoms':
              (data['bodySymptoms'] as List?)?.cast<String>() ?? <String>[],
          'purposeOther': data['purposeOther'],
          'createdAt': DateTime.now().toString(),
          'updatedAt': DateTime.now().toString(),
          'lastChangeAt': (data['lastChangeAt'] is Timestamp)
              ? (data['lastChangeAt'] as Timestamp).toDate().toString()
              : data['lastChangeAt']?.toString(),
        };

        await MedicationLocalDB().addMedication(uid, mapped);
      }
    } catch (e) {
      debugPrint('紀錄調整頁同步 Firebase 失敗：$e');
    }
  }

  Future<List<Map<String, dynamic>>> _getMedsForAdjustment(String uid) async {
    final all = await MedicationLocalDB().getMedicationsForDisplay(uid);
    return all;
  }

  String _timesLabel(List<String> times) {
    if (times.isEmpty) return '未設定';
    return times.join('、');
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        backgroundColor: HealingDesignSystem.adaptiveBackground(context),
        appBar: AppBar(
          backgroundColor: HealingDesignSystem.primaryBlue,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            '紀錄調整',
            style: TextStyle(
              color: HealingDesignSystem.adaptivePrimaryText(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: const Center(child: Text('請先登入後使用')),
      );
    }

    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        backgroundColor: HealingDesignSystem.primaryBlue,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(
            color: HealingDesignSystem.adaptivePrimaryText(context)),
        title: Text(
          '紀錄調整',
          style: TextStyle(
            color: HealingDesignSystem.adaptivePrimaryText(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '調藥時間線',
            icon: Icon(Icons.timeline,
                color: HealingDesignSystem.adaptivePrimaryText(context)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const RecordAdjustmentHistoryPage()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _addNewMedication,
        icon: const Icon(Icons.add),
        label: const Text('新增這次新開的藥'),
        backgroundColor: HealingDesignSystem.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _medsFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorView(message: '讀取藥物失敗：${snap.error}');
            }

            final docs = snap.data ?? [];
            if (docs.isEmpty) {
              return _EmptyMedsView(
                onAdd: _addNewMedication,
              );
            }

            // 確保 draft 有初始化
            for (final med in docs) {
              final docId = med['id'] as String? ?? '';
              _draftByDocId.putIfAbsent(docId, () => _MedDraft.fromMap(med));
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
              children: [
                _SoftHeaderCard(
                  title: '回診 / 調藥記錄',
                  subtitle: '沒有變動就不用改。只把這次有調整的藥標出來，之後可和症狀趨勢做比對。',
                ),
                const SizedBox(height: 12),

                _SectionCard(
                  title: '新處方從何時開始？',
                  icon: Icons.event,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_fmtDateTime(_date)),
                        subtitle: Text(
                          '新處方會從這個時間起套用',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _pickDate,
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final slot in docs
                              .expand((med) =>
                                  (med['times'] as List?)
                                      ?.whereType<String>() ??
                                  const <String>[])
                              .where((slot) => MedicationReminderService
                                  .kSlotTimes
                                  .containsKey(slot))
                              .toSet())
                            ActionChip(
                              label: Text(slot),
                              onPressed: () => _pickExistingSlot(slot),
                            ),
                          ActionChip(
                            label: const Text('明天開始'),
                            onPressed: _pickTomorrow,
                          ),
                          ActionChip(
                            label: const Text('自訂日期／時間'),
                            onPressed: _pickDate,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                _SectionCard(
                  title: '備註（可選）',
                  icon: Icons.notes_outlined,
                  child: TextField(
                    controller: _noteCtrl,
                    minLines: 2,
                    maxLines: 5,
                    style: TextStyle(
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    ),
                    decoration: _inputDeco(context, '例如：醫師交代、調藥原因、觀察重點…'),
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  '逐顆藥物標註（預設：維持原劑量）',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),

                // ── 使用中藥物 ──
                ...docs.where((m) => (m['isActive'] ?? true) == true).map(
                    (med) => _buildMedCard(context, med,
                        _draftByDocId[med['id'] as String? ?? '']!)),

                // ── 已停用藥物（可恢復） ──
                if (docs.any((m) => (m['isActive'] ?? true) == false))
                  ..._buildInactiveMedSection(context, docs, cs),

                const SizedBox(height: 14),

                FilledButton(
                  onPressed: _saving ? null : () => _save(uid),
                  style: FilledButton.styleFrom(
                    backgroundColor: HealingDesignSystem.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          '儲存這次調整',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildInactiveMedSection(
    BuildContext context,
    List<Map<String, dynamic>> docs,
    ColorScheme cs,
  ) {
    final inactive =
        docs.where((m) => (m['isActive'] ?? true) == false).toList();
    return [
      const SizedBox(height: 8),
      Row(
        children: [
          Text('已停用藥物——可在此次回診中恢復使用',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: HealingDesignSystem.mutedText,
                  )),
        ],
      ),
      const SizedBox(height: 6),
      ...inactive.map((med) {
        final docId = (med['id'] as String?) ?? '';
        final name = (med['name'] as String?) ?? '未命名藥物';
        final draft =
            _draftByDocId.putIfAbsent(docId, () => _MedDraft.fromMap(med));
        final isResumed = draft.type == MedChangeType.resumed;
        return Card(
          key: ValueKey('inactive-med-$docId'),
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: HealingDesignSystem.lineColor),
          ),
          surfaceTintColor: Colors.transparent,
          color: isResumed
              ? HealingDesignSystem.primaryBlue.withValues(alpha: 0.12)
              : HealingDesignSystem.adaptiveSurface(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.medication_outlined,
                  size: 18,
                  color: HealingDesignSystem.primaryBlue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: HealingDesignSystem.adaptivePrimaryText(
                                  context),
                            ),
                      ),
                      Text('已停用',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: HealingDesignSystem.mutedText)),
                    ],
                  ),
                ),
                if (isResumed) ...[
                  Text('恢復使用 ✓',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: HealingDesignSystem.primaryBlue)),
                  const SizedBox(width: 8),
                ],
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      draft.type = isResumed
                          ? MedChangeType.unchanged
                          : MedChangeType.resumed;
                    });
                  },
                  style: isResumed
                      ? OutlinedButton.styleFrom(
                          foregroundColor: cs.error,
                          side: BorderSide(
                              color: cs.error.withValues(alpha: 0.6)),
                        )
                      : null,
                  child: Text(isResumed ? '取消' : '恢復使用'),
                ),
              ],
            ),
          ),
        );
      }),
    ];
  }

  Widget _buildMedCard(
    BuildContext context,
    Map<String, dynamic> med,
    _MedDraft draft,
  ) {
    final cs = Theme.of(context).colorScheme;
    final docId = (med['id'] as String?) ?? '';

    final name = (med['name'] as String?) ?? '未命名藥物';
    final unit = draft.unit;
    final dose = med['dose'];
    final medType = (med['type'] ?? '').toString();
    final usesPillDose = medType != 'drops' && medType != 'injection';
    final doseStr = usesPillDose
        ? '${_formatNumber(draft.oldDosePerUnit)} $unit × '
            '${_formatNumber(draft.oldPillCount)} 顆 = '
            '${_doseToString(dose, unit)}'
        : _doseToString(dose, unit);

    final times = (med['times'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final isActive = (med['isActive'] as bool?) ?? true;
    final isInjectionMed = medType == 'injection';

    // 卡片視覺：有變動就稍微凸顯
    final changed = draft.type != MedChangeType.unchanged;

    return Card(
      key: ValueKey('adj-med-$docId'),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: HealingDesignSystem.adaptiveSurface(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side:
            BorderSide(color: HealingDesignSystem.adaptiveCardBorder(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題列
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: HealingDesignSystem.adaptiveFill(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.medication_outlined,
                    size: 16,
                    color: HealingDesignSystem.primaryBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: HealingDesignSystem.adaptivePrimaryText(
                                  context),
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$doseStr${times.isNotEmpty ? ' · ${times.join('、')}' : ''}${!isActive ? ' · 已停用' : ''}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: HealingDesignSystem.mutedText),
                      ),
                    ],
                  ),
                ),
                if (changed)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: HealingDesignSystem.primaryBlue
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _typeLabel(draft.type),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: HealingDesignSystem.adaptivePrimaryText(
                                context),
                          ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // 三段切換
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 8,
              children: [
                _choiceChip(
                  context,
                  label: '維持原劑量',
                  selected: draft.type == MedChangeType.unchanged,
                  onTap: () => setState(() {
                    draft.type = MedChangeType.unchanged;
                    draft.newDose = null;
                    draft.newDosePerUnit = draft.oldDosePerUnit;
                    draft.newPillCount = draft.oldPillCount;
                    draft.newTimes = List<String>.from(draft.oldTimes);
                    draft.stopReason = null;
                  }),
                ),
                _choiceChip(
                  context,
                  label: '劑量調整',
                  selected: draft.type == MedChangeType.doseChanged,
                  onTap: () => setState(() {
                    draft.type = MedChangeType.doseChanged;
                    // 預設帶入目前劑量
                    draft.newDose ??= _doseToDouble(dose);
                    draft.newDosePerUnit ??= draft.oldDosePerUnit;
                    draft.newPillCount ??= draft.oldPillCount;
                    draft.newTimes ??= List<String>.from(draft.oldTimes);
                  }),
                ),
                if (!isInjectionMed)
                  _choiceChip(
                    context,
                    label: '時間調整',
                    selected: draft.type == MedChangeType.scheduleChanged,
                    onTap: () => setState(() {
                      draft.type = MedChangeType.scheduleChanged;
                      draft.newDose = null;
                      draft.newTimes ??= List<String>.from(draft.oldTimes);
                      draft.stopReason = null;
                    }),
                  ),
                if (isInjectionMed)
                  _choiceChip(
                    context,
                    label: '已施打',
                    selected: draft.type == MedChangeType.injected,
                    onTap: () => setState(() {
                      draft.type = MedChangeType.injected;
                      draft.newDose = null;
                      draft.newTimes = null;
                      draft.stopReason = null;
                    }),
                  ),
                _choiceChip(
                  context,
                  label: '停藥',
                  selected: draft.type == MedChangeType.stopped,
                  onTap: () => setState(() {
                    draft.type = MedChangeType.stopped;
                    draft.newDose = null;
                    draft.newTimes = null;
                  }),
                ),
              ],
            ),

            // 劑量調整展開
            if (draft.type == MedChangeType.doseChanged) ...[
              const SizedBox(height: 10),
              _InlineEditRow(
                title: usesPillDose ? '調整後用量' : '新劑量',
                valueText: usesPillDose
                    ? _oralDoseSummary(draft, unit)
                    : draft.newDose == null
                        ? '點擊輸入'
                        : _doseToString(draft.newDose, unit),
                onTap: () => usesPillDose
                    ? _editOralDose(
                        docId: med['id'] as String? ?? '',
                        unit: unit,
                      )
                    : _editDose(
                        docId: med['id'] as String? ?? '',
                        unit: unit,
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                usesPillDose
                    ? '請填調整後的每顆劑量與一次顆數，系統會自動計算總劑量。'
                    : '建議填「調整後」的劑量（支援 0.5 / 1.25 這類小數）',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],

            if (draft.type == MedChangeType.scheduleChanged &&
                !isInjectionMed) ...[
              const SizedBox(height: 10),
              _InlineEditRow(
                title: '服藥時間',
                valueText: _timesLabel(draft.newTimes ?? draft.oldTimes),
                onTap: () => _editTimes(docId: med['id'] as String? ?? ''),
              ),
              const SizedBox(height: 8),
              Text(
                '例如把「早上」改成「早上、晚上」。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],

            // 停藥展開
            if (draft.type == MedChangeType.stopped) ...[
              const SizedBox(height: 10),
              TextField(
                style: TextStyle(
                  color: HealingDesignSystem.adaptivePrimaryText(context),
                ),
                onChanged: (v) =>
                    draft.stopReason = v.trim().isEmpty ? null : v.trim(),
                decoration: _inputDeco(context, '停藥原因（可選）例如：副作用、療程結束、醫師建議…'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _choiceChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? HealingDesignSystem.primaryBlue.withValues(alpha: 0.16)
              : HealingDesignSystem.adaptiveFill(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? HealingDesignSystem.primaryBlue.withValues(alpha: 0.35)
                : HealingDesignSystem.lineColor,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: HealingDesignSystem.adaptivePrimaryText(context),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
        ),
      ),
    );
  }

  Future<void> _editDose({
    required String docId,
    required String unit,
  }) async {
    final draft = _draftByDocId[docId]!;
    final result = await showDialog<MedicationDoseEditResult>(
      context: context,
      builder: (_) => MedicationDoseEditorDialog(
        initialDose: draft.newDose,
        initialUnit: unit,
      ),
    );
    if (!mounted || result == null) return;

    setState(() {
      draft.newDose = result.dose;
      draft.unit = result.unit;
    });
  }

  // Kept temporarily for source-history comparison while the dedicated dialog
  // implementation is exercised in production.
  // ignore: unused_element
  Future<void> _editDoseLegacy({
    required String docId,
    required String unit,
  }) async {
    final draft = _draftByDocId[docId]!;

    final initText = draft.newDose == null
        ? ''
        : (draft.newDose! % 1 == 0
            ? draft.newDose!.toInt().toString()
            : draft.newDose!.toString());

    final ctrl = TextEditingController(text: initText);
    double? picked;
    var pickedUnit = kMedicationDoseUnits.contains(unit) ? unit : 'mg';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final raw = ctrl.text.trim().replaceAll(',', '.');
            final v = double.tryParse(raw);
            if (v == null || v < 0) return;
            picked = v;
            Navigator.of(dialogContext).pop();
          }

          return AlertDialog(
            title: const Text('輸入調整後劑量'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    suffixText: pickedUnit,
                    hintText: '例如 0.5、1.25、25',
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: pickedUnit,
                  decoration: const InputDecoration(labelText: '劑量單位'),
                  items: kMedicationDoseUnits
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => pickedUnit = value);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: submit,
                child: const Text('確定'),
              ),
            ],
          );
        },
      ),
    );

    if (picked == null) return;

    setState(() {
      draft.newDose = picked;
      draft.unit = pickedUnit;
    });
  }

  Future<void> _editOralDose({
    required String docId,
    required String unit,
  }) async {
    final draft = _draftByDocId[docId]!;
    final result = await showDialog<MedicationOralDoseEditResult>(
      context: context,
      builder: (_) => MedicationOralDoseEditorDialog(
        initialDosePerUnit: draft.newDosePerUnit ?? draft.oldDosePerUnit,
        initialPillCount: draft.newPillCount ?? draft.oldPillCount,
        initialUnit: unit,
      ),
    );
    if (!mounted || result == null) return;

    setState(() {
      draft.newDosePerUnit = result.dosePerUnit;
      draft.newPillCount = result.pillCount;
      draft.newDose = _round1(result.dosePerUnit * result.pillCount);
      draft.unit = result.unit;
    });
  }

  // ignore: unused_element
  Future<void> _editOralDoseLegacy({
    required String docId,
    required String unit,
  }) async {
    final draft = _draftByDocId[docId]!;
    final dosePerUnitController = TextEditingController(
      text: _formatNumber(draft.newDosePerUnit ?? draft.oldDosePerUnit),
    );
    final pillCountController = TextEditingController(
      text: _formatNumber(draft.newPillCount ?? draft.oldPillCount),
    );
    double? pickedDosePerUnit;
    double? pickedPillCount;
    var pickedUnit = kMedicationDoseUnits.contains(unit) ? unit : 'mg';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          double? readNumber(TextEditingController controller) {
            return double.tryParse(
              controller.text.trim().replaceAll(',', '.'),
            );
          }

          final dosePerUnit = readNumber(dosePerUnitController);
          final pillCount = readNumber(pillCountController);
          final isValid = dosePerUnit != null &&
              dosePerUnit >= 0 &&
              pillCount != null &&
              pillCount > 0;
          final totalDose = isValid ? _round1(dosePerUnit * pillCount) : null;

          void submit() {
            if (!isValid) return;
            pickedDosePerUnit = dosePerUnit;
            pickedPillCount = pillCount;
            Navigator.pop(dialogContext);
          }

          return AlertDialog(
            title: const Text('調整後用量'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: dosePerUnitController,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: '每顆劑量',
                    hintText: '例如 25',
                    suffixText: pickedUnit,
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: pickedUnit,
                  decoration: const InputDecoration(labelText: '劑量單位'),
                  items: kMedicationDoseUnits
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => pickedUnit = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: pillCountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (_) => submit(),
                  decoration: const InputDecoration(
                    labelText: '一次顆數',
                    hintText: '例如 0.5、1、2',
                    suffixText: '顆',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  totalDose == null
                      ? '請輸入有效的劑量與顆數'
                      : '每次總量：${_formatNumber(dosePerUnit!)} $pickedUnit × '
                          '${_formatNumber(pillCount!)} 顆 = '
                          '${_formatNumber(totalDose)} $pickedUnit',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: totalDose == null
                            ? Theme.of(context).colorScheme.error
                            : HealingDesignSystem.adaptivePrimaryText(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: isValid ? submit : null,
                child: const Text('確定'),
              ),
            ],
          );
        },
      ),
    );

    dosePerUnitController.dispose();
    pillCountController.dispose();
    if (pickedDosePerUnit == null || pickedPillCount == null) return;

    setState(() {
      draft.newDosePerUnit = pickedDosePerUnit;
      draft.newPillCount = pickedPillCount;
      draft.newDose = _round1(pickedDosePerUnit! * pickedPillCount!);
      draft.unit = pickedUnit;
    });
  }

  String _oralDoseSummary(_MedDraft draft, String unit) {
    final dosePerUnit = draft.newDosePerUnit;
    final pillCount = draft.newPillCount;
    if (dosePerUnit == null || pillCount == null) return '點擊輸入';
    final totalDose = _round1(dosePerUnit * pillCount);
    return '${_formatNumber(dosePerUnit)} $unit × '
        '${_formatNumber(pillCount)} 顆 = '
        '${_formatNumber(totalDose)} $unit';
  }

  String _formatNumber(double value) {
    if (value % 1 == 0) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Future<void> _editTimes({
    required String docId,
  }) async {
    final draft = _draftByDocId[docId]!;
    final selected = <String>{...(draft.newTimes ?? draft.oldTimes)};
    List<String>? picked;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('調整服藥時間'),
              content: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kAdjustmentTimeSlots.map((slot) {
                    return FilterChip(
                      selected: selected.contains(slot),
                      label: Text(slot),
                      onSelected: (on) {
                        setDialogState(() {
                          if (on) {
                            selected.add(slot);
                          } else {
                            selected.remove(slot);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final ordered =
                        kAdjustmentTimeSlots.where(selected.contains).toList();
                    picked = ordered;
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('確定'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null) return;
    setState(() {
      draft.newTimes = picked;
    });
  }

  Future<void> _addNewMedication() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final before = await _getMedsForAdjustment(uid);
    if (!mounted) return;
    final beforeIds = before
        .map((m) => (m['id'] as String?) ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddMedicationPage(
          initialStartDate: _date,
          adjustmentEventSource: 'adjustmentRecord',
        ),
      ),
    );

    if (added != true) return;

    final after = await _getMedsForAdjustment(uid);
    if (!mounted) return;
    final afterMap = <String, Map<String, dynamic>>{
      for (final m in after)
        if (((m['id'] as String?) ?? '').isNotEmpty) (m['id'] as String): m,
    };
    final afterIds = afterMap.keys.toSet();
    final newIds = afterIds.difference(beforeIds);

    setState(() {
      _sessionNewlyAddedDocIds.addAll(newIds);

      for (final id in newIds) {
        final med = afterMap[id];
        if (med == null) continue;

        final draft =
            _draftByDocId.putIfAbsent(id, () => _MedDraft.fromMap(med));
        draft.type = MedChangeType.added;
        draft.newDose = draft.oldDose;
      }

      _medsFuture = _loadMeds(uid);
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: '選擇調藥生效時間',
    );
    if (pickedTime == null || !mounted) return;
    setState(() => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          pickedTime.hour,
          pickedTime.minute,
        ));
  }

  Future<void> _pickExistingSlot(String slot) async {
    final time = await MedicationReminderService.getSlotTime(slot);
    if (!mounted) return;
    final now = DateTime.now();
    var selected =
        DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (selected.isBefore(now)) {
      selected = selected.add(const Duration(days: 1));
    }
    setState(() => _date = selected);
  }

  void _pickTomorrow() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    setState(
        () => _date = DateTime(tomorrow.year, tomorrow.month, tomorrow.day));
  }

  Future<void> _save(String uid) async {
    if (_saving) return;

    debugPrint('🔄 開始保存調整記錄...');
    debugPrint('📍 調整日期：${_fmtYmd(_date)}');
    debugPrint('📝 備註：${_noteCtrl.text}');

    // 只取有變動的 items（無變化的不寫入）
    final changed = _draftByDocId.entries
        .where((e) =>
            e.value.type != MedChangeType.unchanged ||
            _sessionNewlyAddedDocIds.contains(e.key))
        .toList();

    debugPrint('🔍 檢查變動：${_draftByDocId.length} 顆藥物，${changed.length} 顆有變動');

    if (changed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前沒有任何變動。請至少選一顆藥做「新增／調整／停藥」。')),
      );
      return;
    }

    // 檢查：劑量調整一定要有 newDose
    for (final e in changed) {
      final d = e.value;
      if (d.type == MedChangeType.doseChanged && d.newDose == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('有藥物選了「劑量調整」，但尚未填入新劑量。')),
        );
        return;
      }
      if (d.type == MedChangeType.doseChanged &&
          d.usesPillDose &&
          (d.newDosePerUnit == null ||
              d.newDosePerUnit! < 0 ||
              d.newPillCount == null ||
              d.newPillCount! <= 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請填入調整後的每顆劑量與一次顆數。')),
        );
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final items = changed.map((e) {
        final docId = e.key;
        final d = e.value;
        final isAddedThisSession = d.type == MedChangeType.added ||
            _sessionNewlyAddedDocIds.contains(docId);

        final itemType =
            isAddedThisSession ? MedChangeType.added.name : d.type.name;

        return <String, dynamic>{
          'medDocId': docId,
          'name': d.name,
          'type': itemType, // added/injected/doseChanged/stopped/resumed
          'oldDose': isAddedThisSession ? null : d.oldDose,
          'newDose': isAddedThisSession ? (d.newDose ?? d.oldDose) : d.newDose,
          'oldDosePerUnit': isAddedThisSession ? null : d.oldDosePerUnit,
          'newDosePerUnit': isAddedThisSession
              ? (d.newDosePerUnit ?? d.oldDosePerUnit)
              : d.newDosePerUnit,
          'oldPillCount': isAddedThisSession ? null : d.oldPillCount,
          'newPillCount': isAddedThisSession
              ? (d.newPillCount ?? d.oldPillCount)
              : d.newPillCount,
          'oldTimes': isAddedThisSession ? null : d.oldTimes,
          'newTimes': d.newTimes,
          'unit': d.unit,
          'oldUnit': isAddedThisSession ? null : d.oldUnit,
          'newUnit': d.unit,
          'stopReason': d.stopReason,
        };
      }).toList();

      // 1) 寫入調整紀錄到本地 DB（一定要寫入）
      final dateStr = _fmtYmd(DateTime(_date.year, _date.month, _date.day));
      debugPrint('📋 準備保存調整記錄 - date: $dateStr, items 數量: ${items.length}');

      try {
        await MedicationAdjustmentService().recordItems(
          uid: uid,
          effectiveDate: _date,
          adjustmentDateTime: DateTime.now(),
          source: 'adjustmentRecord',
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          items: items,
        );
        debugPrint('✅ 本地調整記錄已保存');
      } catch (e) {
        debugPrint('❌ 本地調整記錄保存失敗：$e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('本地保存失敗：$e')),
        );
        return;
      }

      // 2) 寫入調整紀錄到 Firebase
      // 3) 同步更新藥物主檔（只更新有變動的）
      // 先讀取本地舊資料，讓「總劑量」可同步換算為「每顆劑量 x 顆數」。
      final localMedById = <String, Map<String, dynamic>>{};
      for (final e in changed) {
        final local = await MedicationLocalDB().getMedication(uid, e.key);
        if (local != null) {
          localMedById[e.key] = local;
        }
      }

      // 4️⃣ 先更新本地端藥物（一定要更新）
      for (final e in changed) {
        final medDocId = e.key;
        final d = e.value;

        final localMed = localMedById[medDocId] ??
            await MedicationLocalDB().getMedication(uid, medDocId);
        if (localMed != null) {
          final updated = Map<String, dynamic>.from(localMed);
          updated['updatedAt'] = DateTime.now().toString();
          updated['lastChangeAt'] = _date.toIso8601String();

          if (d.type == MedChangeType.doseChanged) {
            updated.addAll(
              _buildDoseFieldsForDoseChanged(
                draft: d,
              ),
            );
            if (d.newTimes != null) {
              updated['times'] = d.newTimes;
            }
            updated['isActive'] = true;
          } else if (d.type == MedChangeType.scheduleChanged) {
            if (d.newTimes != null) {
              updated['times'] = d.newTimes;
            }
            updated['isActive'] = true;
          } else if (d.type == MedChangeType.injected) {
            updated['isActive'] = true;
          } else if (d.type == MedChangeType.added) {
            if (d.newTimes != null) {
              updated['times'] = d.newTimes;
            }
            updated['isActive'] = true;
          } else if (d.type == MedChangeType.stopped) {
            updated['isActive'] = false;
          } else if (d.type == MedChangeType.resumed) {
            updated['isActive'] = true;
            updated['resumedAt'] = _date.toIso8601String();
          }

          try {
            await MedicationLocalDB().updateMedication(uid, medDocId, updated);
          } catch (e) {
            debugPrint('⚠️ 更新藥物 $medDocId 失敗：$e');
          }
        }
      }
      debugPrint('✅ 本地藥物已更新');

      // 調藥完成後立即重建每日提醒，避免停藥/時段調整後提醒內容延遲。
      try {
        await MedicationReminderService.syncDailyRemindersForActiveMeds();
      } catch (e) {
        debugPrint('⚠️ 重建服藥提醒失敗：$e');
      }

      // 5️⃣ 再上傳 Firebase（如果啟用同步）
      if (FirebaseSyncConfig.shouldSync()) {
        try {
          // MedicationLocalDB committed the encrypted adjustment and updates.
          debugPrint('🔥 Firebase 調整已同步');
        } catch (e) {
          debugPrint('⚠️ Firebase 同步失敗：$e');
        }
      }

      if (!mounted) {
        debugPrint('❌ Widget 已卸載，無法返回');
        return;
      }

      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已儲存本次調整')),
      );
    } catch (e) {
      debugPrint('❌ 儲存異常：$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('儲存失敗：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmtYmd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  String _fmtDateTime(DateTime dt) =>
      '${_fmtYmd(dt)} ${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  static InputDecoration _inputDeco(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: HealingDesignSystem.adaptiveSecondaryText(context),
        fontSize: 14,
      ),
      filled: true,
      fillColor: HealingDesignSystem.adaptiveFill(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: HealingDesignSystem.adaptiveCardBorder(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: HealingDesignSystem.adaptiveCardBorder(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
            color: HealingDesignSystem.primaryBlue, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  String _typeLabel(MedChangeType t) {
    switch (t) {
      case MedChangeType.unchanged:
        return '維持原劑量';
      case MedChangeType.added:
        return '新增';
      case MedChangeType.injected:
        return '已施打';
      case MedChangeType.doseChanged:
        return '調整';
      case MedChangeType.scheduleChanged:
        return '時間調整';
      case MedChangeType.stopped:
        return '停藥';
      case MedChangeType.resumed:
        return '恢復使用';
    }
  }

  double _doseToDouble(dynamic dose) {
    if (dose is int) return dose.toDouble();
    if (dose is double) return dose;
    return 0;
  }

  double _round1(double v) => double.parse(v.toStringAsFixed(1));

  Map<String, dynamic> _buildDoseFieldsForDoseChanged({
    required _MedDraft draft,
  }) {
    if (draft.newDose == null) return const <String, dynamic>{};

    final normalizedDose = _round1(draft.newDose!);

    final out = <String, dynamic>{
      'dose': normalizedDose,
      'unit': draft.unit,
    };

    if (draft.usesPillDose &&
        draft.newDosePerUnit != null &&
        draft.newPillCount != null) {
      out['dosePerUnit'] = _round1(draft.newDosePerUnit!);
      out['pillCount'] = _round1(draft.newPillCount!);
    }

    return out;
  }

  String _doseToString(dynamic dose, String unit) {
    final v = (dose is int) ? dose.toDouble() : (dose is double ? dose : 0.0);
    if (v % 1 == 0) return '${v.toInt()} $unit';
    return '${v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')} $unit';
  }
}

class _MedDraft {
  String name;
  String oldUnit;
  String unit;
  String medType;
  double oldDose;
  double oldDosePerUnit;
  double oldPillCount;
  List<String> oldTimes;
  MedChangeType type;
  double? newDose;
  double? newDosePerUnit;
  double? newPillCount;
  List<String>? newTimes;
  String? stopReason;

  bool get usesPillDose => medType != 'drops' && medType != 'injection';

  _MedDraft({
    required this.name,
    required this.oldUnit,
    required this.unit,
    required this.medType,
    required this.oldDose,
    required this.oldDosePerUnit,
    required this.oldPillCount,
    required this.oldTimes,
    required this.type,
    this.newDose,
    this.newDosePerUnit,
    this.newPillCount,
    this.newTimes,
  });

  factory _MedDraft.fromMap(Map<String, dynamic> m) {
    final name = (m['name'] as String?) ?? '未命名藥物';
    final unit = (m['unit'] as String?) ?? 'mg';
    final medType = (m['type'] ?? '').toString();
    final dose = m['dose'];
    final oldDose =
        (dose is int) ? dose.toDouble() : (dose is double ? dose : 0.0);
    final rawPillCount = m['pillCount'];
    final parsedPillCount = rawPillCount is num
        ? rawPillCount.toDouble()
        : double.tryParse(rawPillCount?.toString() ?? '');
    final oldPillCount =
        parsedPillCount != null && parsedPillCount > 0 ? parsedPillCount : 1.0;
    final rawDosePerUnit = m['dosePerUnit'];
    final parsedDosePerUnit = rawDosePerUnit is num
        ? rawDosePerUnit.toDouble()
        : double.tryParse(rawDosePerUnit?.toString() ?? '');
    final oldDosePerUnit = parsedDosePerUnit ?? (oldDose / oldPillCount);
    final oldTimes =
        (m['times'] as List?)?.whereType<String>().toList() ?? <String>[];

    return _MedDraft(
      name: name,
      oldUnit: unit,
      unit: unit,
      medType: medType,
      oldDose: oldDose,
      oldDosePerUnit: oldDosePerUnit,
      oldPillCount: oldPillCount,
      oldTimes: oldTimes,
      type: MedChangeType.unchanged,
      newDose: oldDose,
      newDosePerUnit: oldDosePerUnit,
      newPillCount: oldPillCount,
      newTimes: List<String>.from(oldTimes),
    );
  }
}

/* ====== 小元件：沿用你新增頁的風格 ====== */

class _SoftHeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SoftHeaderCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
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
            child: const Icon(Icons.playlist_add_check, color: Colors.white),
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
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                    fontSize: 12,
                    height: 1.4,
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
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard(
      {required this.title, required this.icon, required this.child});

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

class _InlineEditRow extends StatelessWidget {
  final String title;
  final String valueText;
  final VoidCallback onTap;

  const _InlineEditRow({
    required this.title,
    required this.valueText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: HealingDesignSystem.adaptiveFill(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: HealingDesignSystem.adaptiveCardBorder(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$title：$valueText',
                style: TextStyle(
                  color: HealingDesignSystem.adaptivePrimaryText(context),
                ),
              ),
            ),
            const Icon(
              Icons.edit,
              size: 16,
              color: HealingDesignSystem.mutedText,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMedsView extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyMedsView({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: HealingDesignSystem.adaptiveFill(context),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.medication_outlined,
                size: 36,
                color: HealingDesignSystem.primaryBlue,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '先建立你的藥物清單',
              style: TextStyle(
                color: HealingDesignSystem.adaptivePrimaryText(context),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '先新增至少一顆藥，才可以開始「紀錄調整」。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: HealingDesignSystem.mutedText,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('新增第一顆藥'),
              style: FilledButton.styleFrom(
                backgroundColor: HealingDesignSystem.primaryBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
        child:
            Padding(padding: const EdgeInsets.all(16), child: Text(message)));
  }
}

class MedChangeDraft {
  MedChangeType type;
  double? newDose;
  String? stopReason;

  MedChangeDraft({
    this.type = MedChangeType.unchanged,
    this.newDose,
    this.stopReason,
  });
}
