import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../models/follow_up_ai_summary.dart';
import '../widgets/follow_up_sleep_trend_card.dart';

enum FollowUpShareActionType { pdf, qr }

class FollowUpSharePreviewResult {
  const FollowUpSharePreviewResult({required this.type, required this.options});
  final FollowUpShareActionType type;
  final FollowUpSummaryShareOptions options;
}

class FollowUpSharePreviewPage extends StatefulWidget {
  const FollowUpSharePreviewPage({super.key, required this.summary});
  final FollowUpSummaryRecord summary;

  @override
  State<FollowUpSharePreviewPage> createState() =>
      _FollowUpSharePreviewPageState();
}

class _FollowUpSharePreviewPageState extends State<FollowUpSharePreviewPage> {
  FollowUpSummaryShareOptions _options = FollowUpSummaryShareOptions.none;

  void _finish(FollowUpShareActionType type) {
    if (!_options.hasSelection) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少選擇一項要分享的內容。')),
      );
      return;
    }
    Navigator.pop(
      context,
      FollowUpSharePreviewResult(type: type, options: _options),
    );
  }

  @override
  Widget build(BuildContext context) {
    final display = FollowUpSummaryDisplayModel.fromRecord(
      widget.summary,
      options: _options,
    );
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        title: const Text('分享給醫師'),
        backgroundColor: HealingDesignSystem.primaryBlue,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('選擇分享內容', style: HealingDesignSystem.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    '預設不分享任何原文。姓名、帳號與內部識別資訊永遠不會包含在分享版本中。',
                    style: HealingDesignSystem.bodySmall.copyWith(
                      color: HealingDesignSystem.adaptiveSecondaryText(context),
                    ),
                  ),
                  _check('討論主題', _options.discussionTopics,
                      (value) => _options.copyWith(discussionTopics: value)),
                  _check('睡眠圖表', _options.sleep,
                      (value) => _options.copyWith(sleep: value)),
                  _check('情緒症狀', _options.emotionsAndSymptoms,
                      (value) => _options.copyWith(emotionsAndSymptoms: value)),
                  _check('身體測量（體重、體脂率、腰圍）', _options.bodyMeasurements,
                      (value) => _options.copyWith(bodyMeasurements: value)),
                  _check(
                      '藥物調整',
                      _options.medicationAdjustments,
                      (value) =>
                          _options.copyWith(medicationAdjustments: value)),
                  _check('生活近況', _options.lifeUpdates,
                      (value) => _options.copyWith(lifeUpdates: value)),
                  _check('資料限制', _options.dataLimitations,
                      (value) => _options.copyWith(dataLimitations: value)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('去識別化分享預覽', style: HealingDesignSystem.titleMedium),
          _card('基本資訊', display.visitInfo, bullets: false),
          if (_options.discussionTopics)
            _discussionCard(display.topicLabels, display.discussionItems),
          if (_options.emotionsAndSymptoms) ...[
            _card('主要變化', display.keyChanges),
          ],
          if (_options.sleep)
            FollowUpSleepTrendCard.fromRecord(record: widget.summary),
          if (_options.emotionsAndSymptoms)
            _card('身體症狀', display.symptoms, emptyText: '此摘要沒有可顯示的症狀資料'),
          if (_options.emotionsAndSymptoms &&
              display.recordEvidenceHighlights.isNotEmpty)
            _card('紀錄重點', display.recordEvidenceHighlights),
          if (_options.bodyMeasurements)
            _card('身體測量', display.bodyMeasurements,
                emptyText: '此摘要沒有可顯示的體重、體脂率或腰圍資料'),
          if (_options.medicationAdjustments)
            _card('藥物調整時間軸', display.medicationTimeline,
                emptyText: '此摘要沒有藥物調整紀錄'),
          if (_options.medicationAdjustments &&
              display.medicationSubjectiveSummaries.isNotEmpty)
            _card('主觀用藥感受', display.medicationSubjectiveSummaries),
          if (_options.lifeUpdates)
            _card('其他想跟醫師說的內容', display.userSharedNotes,
                emptyText: '沒有其他想跟醫師說的內容'),
          if (_options.dataLimitations) _card('資料限制', display.dataLimitations),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('摘要僅供回診溝通參考，不取代醫師判斷。'),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: () => _finish(FollowUpShareActionType.pdf),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('匯出分享版 PDF'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _finish(FollowUpShareActionType.qr),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('產生限時 QR Code'),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _check(
    String label,
    bool value,
    FollowUpSummaryShareOptions Function(bool value) update,
  ) =>
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        title: Text(label),
        onChanged: (next) => setState(() => _options = update(next ?? false)),
      );

  Widget _card(String title, List<String> items,
          {bool bullets = true, String emptyText = '尚無資料'}) =>
      Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: HealingDesignSystem.titleSmall),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Text(emptyText,
                  style: TextStyle(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                  ))
            else
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(bullets ? '• $item' : item,
                        style: const TextStyle(height: 1.45)),
                  )),
          ]),
        ),
      );

  Widget _discussionCard(List<String> labels, List<String> items) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('想跟醫師討論的事', style: HealingDesignSystem.titleSmall),
            if (labels.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    labels.map((label) => Chip(label: Text(label))).toList(),
              ),
            if (labels.isEmpty && items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('尚無資料'),
              )
            else
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('• $item'),
                  )),
          ]),
        ),
      );
}
