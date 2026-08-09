import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import 'med_symptom_compare_models.dart';
import 'medication_local_db.dart';
import 'medication_subjective_reminder_service.dart';
import 'medication_subjective_response.dart';

class MedicationSubjectiveResponsePage extends StatefulWidget {
  MedicationSubjectiveResponsePage({
    super.key,
    required this.medicationId,
    required this.medicationName,
    required this.changeRecordId,
    required this.changeDate,
    required this.adjustmentSummary,
    required this.followUpDay,
  }) {
    if (!MedicationSubjectiveResponse.allowedFollowUpDays.contains(
      followUpDay,
    )) {
      throw ArgumentError.value(
        followUpDay,
        'followUpDay',
        'must be 3, 7, 14, or 28',
      );
    }
  }

  factory MedicationSubjectiveResponsePage.fromAdjustmentEvent({
    Key? key,
    required MedicationAdjustmentEvent event,
    required int followUpDay,
  }) {
    return MedicationSubjectiveResponsePage(
      key: key,
      medicationId: event.medDocId,
      medicationName: event.medName,
      changeRecordId: event.adjustmentId,
      changeDate: event.date,
      adjustmentSummary: MedicationAdjustmentFormatter.detailSummary(event),
      followUpDay: followUpDay,
    );
  }

  final String medicationId;
  final String medicationName;
  final String changeRecordId;
  final DateTime changeDate;
  final String adjustmentSummary;
  final int followUpDay;

  @override
  State<MedicationSubjectiveResponsePage> createState() =>
      _MedicationSubjectiveResponsePageState();
}

class _MedicationSubjectiveResponsePageState
    extends State<MedicationSubjectiveResponsePage> {
  static const _overallOptions = <MedicationOverallResponse, String>{
    MedicationOverallResponse.better: '有改善',
    MedicationOverallResponse.worse: '變差',
    MedicationOverallResponse.mixed: '好壞都有',
    MedicationOverallResponse.noChange: '沒明顯變化',
    MedicationOverallResponse.unsure: '不確定',
  };

  static const _changedAreaOptions = <String>[
    '情緒',
    '焦慮',
    '睡眠',
    '精神／活動力',
    '食慾',
    '身體不適',
    '其他',
  ];

  static const _relationOptions = <MedicationPerceivedRelation, String>{
    MedicationPerceivedRelation.veryLikely: '很可能有關',
    MedicationPerceivedRelation.likely: '可能有關',
    MedicationPerceivedRelation.unsure: '不確定',
    MedicationPerceivedRelation.unlikely: '可能無關',
    MedicationPerceivedRelation.veryUnlikely: '幾乎無關',
  };

  static const _otherFactorOptions = <String>[
    '情緒狀態變化',
    '睡眠改變',
    '生活事件',
    '生理期',
    '身體狀況',
    '其他藥物調整',
    '其他',
    '不確定',
  ];

  final _noteController = TextEditingController();
  final _changedAreas = <String>{};
  final _otherFactors = <String>{};
  MedicationOverallResponse? _overallResponse;
  MedicationPerceivedRelation? _perceivedRelation;
  bool _saving = false;

  bool get _canSave =>
      !_saving && _overallResponse != null && _perceivedRelation != null;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請先登入帳號')));
      return;
    }

    setState(() => _saving = true);
    try {
      final response = MedicationSubjectiveResponse(
        id: _responseId(
          widget.changeRecordId,
          widget.medicationId,
          widget.followUpDay,
        ),
        medicationId: widget.medicationId,
        medicationName: widget.medicationName,
        changeRecordId: widget.changeRecordId,
        changeDate: widget.changeDate,
        followUpDay: widget.followUpDay,
        recordedAt: DateTime.now(),
        overallResponse: _overallResponse!,
        changedAreas: _changedAreas.toList(),
        perceivedRelation: _perceivedRelation!,
        otherFactors: _otherFactors.toList(),
        note: _noteController.text.trim(),
      );
      await MedicationLocalDB().saveSubjectiveResponse(uid, response);
      try {
        await MedicationSubjectiveReminderService()
            .syncForCurrentUser(uid: uid);
      } catch (error) {
        debugPrint('Medication subjective reminder sync deferred: $error');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已儲存主觀用藥感受')));
      Navigator.of(context).pop(response);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('儲存失敗：$error')));
    }
  }

  static String _responseId(
    String changeRecordId,
    String medicationId,
    int followUpDay,
  ) {
    final change = Uri.encodeComponent(changeRecordId.trim());
    final medication = Uri.encodeComponent(medicationId.trim());
    return '${change}_${medication}_day$followUpDay';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
        foregroundColor: HealingDesignSystem.adaptiveAppBarForeground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '主觀用藥感受',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            _AdjustmentCard(
              medicationName: widget.medicationName,
              adjustmentSummary: widget.adjustmentSummary,
              changeDate: widget.changeDate,
              followUpDay: widget.followUpDay,
            ),
            const SizedBox(height: 14),
            _QuestionCard(
              title: '1. 整體感受',
              child: _SingleChoiceWrap<MedicationOverallResponse>(
                options: _overallOptions,
                selected: _overallResponse,
                onSelected: (value) => setState(() => _overallResponse = value),
              ),
            ),
            const SizedBox(height: 12),
            _QuestionCard(
              title: '2. 哪些方面有變化？',
              optional: true,
              child: _MultiChoiceWrap(
                options: _changedAreaOptions,
                selected: _changedAreas,
                onChanged: () => setState(() {}),
              ),
            ),
            const SizedBox(height: 12),
            _QuestionCard(
              title: '3. 你覺得這些變化和這次用藥調整有關嗎？',
              child: _SingleChoiceWrap<MedicationPerceivedRelation>(
                options: _relationOptions,
                selected: _perceivedRelation,
                onSelected: (value) =>
                    setState(() => _perceivedRelation = value),
              ),
            ),
            const SizedBox(height: 12),
            _QuestionCard(
              title: '4. 其他可能影響因素',
              optional: true,
              child: _MultiChoiceWrap(
                options: _otherFactorOptions,
                selected: _otherFactors,
                onChanged: () => setState(() {}),
              ),
            ),
            const SizedBox(height: 12),
            _QuestionCard(
              title: '補充說明',
              optional: true,
              child: TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: '想補充的感受或情況',
                  filled: true,
                  fillColor: HealingDesignSystem.adaptiveFill(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _canSave ? _save : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: HealingDesignSystem.primaryBlue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _saving
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  '儲存',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}

class _AdjustmentCard extends StatelessWidget {
  const _AdjustmentCard({
    required this.medicationName,
    required this.adjustmentSummary,
    required this.changeDate,
    required this.followUpDay,
  });

  final String medicationName;
  final String adjustmentSummary;
  final DateTime changeDate;
  final int followUpDay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: HealingDesignSystem.adaptiveFill(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.medication_rounded,
              color: HealingDesignSystem.primaryBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        medicationName,
                        style: TextStyle(
                          color: HealingDesignSystem.adaptivePrimaryText(
                            context,
                          ),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: HealingDesignSystem.adaptiveFill(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Day $followUpDay',
                        style: const TextStyle(
                          color: HealingDesignSystem.primaryBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  adjustmentSummary,
                  style: TextStyle(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '調整日期 ${_dateText(changeDate)}',
                  style: TextStyle(
                    color: HealingDesignSystem.adaptiveMutedText(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dateText(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}';
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.title,
    required this.child,
    this.optional = false,
  });

  final String title;
  final Widget child;
  final bool optional;

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
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (optional)
                Text(
                  '可略過',
                  style: TextStyle(
                    color: HealingDesignSystem.adaptiveMutedText(context),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SingleChoiceWrap<T> extends StatelessWidget {
  const _SingleChoiceWrap({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final Map<T, String> options;
  final T? selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries
          .map(
            (entry) => ChoiceChip(
              label: Text(entry.value),
              selected: selected == entry.key,
              onSelected: (_) => onSelected(entry.key),
            ),
          )
          .toList(),
    );
  }
}

class _MultiChoiceWrap extends StatelessWidget {
  const _MultiChoiceWrap({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final Set<String> selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options
          .map(
            (option) => FilterChip(
              label: Text(option),
              selected: selected.contains(option),
              onSelected: (value) {
                value ? selected.add(option) : selected.remove(option);
                onChanged();
              },
            ),
          )
          .toList(),
    );
  }
}
