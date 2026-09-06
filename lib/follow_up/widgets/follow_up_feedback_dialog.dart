import 'package:flutter/material.dart';
import '../../constants/healing_design_system.dart';
import '../models/follow_up_summary_feedback.dart';
import '../services/follow_up_service.dart';

Future<FollowUpSummaryFeedback?> showFollowUpFeedbackDialog(
        BuildContext context,
        {required String summaryId}) =>
    showDialog<FollowUpSummaryFeedback>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FollowUpFeedbackDialog(
        onSubmit: (feedback) =>
            FollowUpService.saveSummaryFeedback(summaryId, feedback),
      ),
    );

class FollowUpFeedbackDialog extends StatefulWidget {
  const FollowUpFeedbackDialog({super.key, required this.onSubmit});
  final Future<void> Function(FollowUpSummaryFeedback) onSubmit;
  @override
  State<FollowUpFeedbackDialog> createState() => _FollowUpFeedbackDialogState();
}

class _FollowUpFeedbackDialogState extends State<FollowUpFeedbackDialog> {
  bool? _shown;
  FollowUpFeedbackAnswer? _forgotten;
  FollowUpFeedbackAnswer? _deeper;
  FollowUpDoctorAnswer? _again;
  bool _saving = false;
  String? _error;
  bool get _complete =>
      _shown == false ||
      (_shown == true &&
          _forgotten != null &&
          _deeper != null &&
          _again != null);

  Future<void> _submit() async {
    if (_saving || !_complete) return;
    final feedback = FollowUpSummaryFeedback(
      shownToDoctor: _shown!,
      surfacedForgottenInfo: _forgotten,
      hadDeeperDiscussion: _deeper,
      doctorRequestedAgain: _again,
      submittedAt: DateTime.now(),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(feedback);
      if (mounted) Navigator.pop(context, feedback);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '回饋尚未送出，請稍後重試。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          backgroundColor: HealingDesignSystem.adaptiveSurface(context),
          title: const Text('這次回診有使用摘要嗎？'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('回饋選項將提供給心域團隊，用於改善摘要功能，不包含你的摘要內容。'),
                ),
                _question<bool>(
                    '這次有把回診摘要給醫師看嗎？', const {true: '有', false: '沒有'}, _shown,
                    (value) {
                  _shown = value;
                  if (!value) {
                    _forgotten = null;
                    _deeper = null;
                    _again = null;
                  }
                }),
                if (_shown == true) ...[
                  _question('摘要有沒有幫你談到原本可能忘記說的重要事情？', _answers, _forgotten,
                      (value) => _forgotten = value),
                  _question('這次有沒有進一步談到生活事件、症狀原因、睡眠或用藥反應？', _answers, _deeper,
                      (value) => _deeper = value),
                  _question(
                      '醫師有沒有表示下次可以再帶這份摘要？',
                      const {
                        FollowUpDoctorAnswer.yes: '有',
                        FollowUpDoctorAnswer.no: '沒有',
                        FollowUpDoctorAnswer.notMentioned: '沒有提到'
                      },
                      _again,
                      (value) => _again = value),
                ],
                if (_saving) const LinearProgressIndicator(),
                if (_error != null) Text(_error!),
              ],
            )),
          ),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('略過')),
            FilledButton(
                onPressed: _saving || !_complete ? null : _submit,
                child: const Text('送出')),
          ],
        ),
      );
  static const _answers = {
    FollowUpFeedbackAnswer.yes: '有',
    FollowUpFeedbackAnswer.no: '沒有',
    FollowUpFeedbackAnswer.unsure: '不確定'
  };
  Widget _question<T>(String title, Map<T, String> options, T? selected,
          ValueChanged<T> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title),
          const SizedBox(height: 6),
          Wrap(
              spacing: 8,
              runSpacing: 4,
              children: options.entries
                  .map((entry) => ChoiceChip(
                        label: Text(entry.value),
                        selected: selected == entry.key,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() => onChanged(entry.key)),
                      ))
                  .toList()),
        ]),
      );
}
