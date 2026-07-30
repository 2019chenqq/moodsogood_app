import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../../models/daily_record.dart';
import '../../models/weekly_record.dart';

class WeeklySummaryCard extends StatelessWidget {
  final List<DailyRecord> records;
  final String title;
  final String subtitle;
  final int? totalDays;
  final bool currentWeekHasNoDailyRecords;
  final WeeklyRecord? currentWeeklyRecord;
  final VoidCallback? onStartWeeklyReview;

  const WeeklySummaryCard({
    super.key,
    required this.records,
    required this.title,
    required this.subtitle,
    required this.totalDays,
    this.currentWeekHasNoDailyRecords = false,
    this.currentWeeklyRecord,
    this.onStartWeeklyReview,
  });

  @override
  Widget build(BuildContext context) {
    final recordedDays = records.length;

    // 鼓勵語句
    final String message;
    if (recordedDays == 0) {
      message = '這段期間還沒有開始記錄，沒關係，可以從今天慢慢來。';
    } else if (recordedDays <= 3) {
      message = '這段期間已經有 $recordedDays 天留下紀錄了，願意給自己這些時間，很不容易。';
    } else if (totalDays != null && recordedDays < totalDays!) {
      message = '這段期間有一些日子你有停下來關心自己，已經很棒了。';
    } else {
      message = '這段期間你持續陪自己走了一段路，謝謝你這麼努力地活著。';
    }

    // 紀錄天數進度條比例
    final progress =
        totalDays == null ? null : (recordedDays / totalDays!).clamp(0.0, 1.0);

    return Container(
      decoration: HealingDesignSystem.adaptiveCardDecoration(context),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      HealingDesignSystem.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: HealingDesignSystem.primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: HealingDesignSystem.adaptivePrimaryText(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color:
                            HealingDesignSystem.adaptiveSecondaryText(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Progress bar
          Row(
            children: [
              Text(
                '紀錄天數',
                style: TextStyle(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                totalDays == null
                    ? '$recordedDays 天'
                    : '$recordedDays / $totalDays 天',
                style: const TextStyle(
                  color: HealingDesignSystem.primaryBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor:
                    HealingDesignSystem.adaptiveCardBorder(context),
                valueColor: const AlwaysStoppedAnimation<Color>(
                    HealingDesignSystem.primaryBlue),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Encouraging message
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: HealingDesignSystem.adaptiveFill(context),
              borderRadius: BorderRadius.circular(HealingDesignSystem.radiusS),
              border: Border.all(
                color: HealingDesignSystem.adaptiveCardBorder(context),
              ),
            ),
            child: Text(
              message,
              style: TextStyle(
                color: HealingDesignSystem.adaptivePrimaryText(context),
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ),
          if (currentWeeklyRecord != null) ...[
            const SizedBox(height: 12),
            _WeeklyRecordSummary(record: currentWeeklyRecord!),
          ] else if (onStartWeeklyReview != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: HealingDesignSystem.primaryBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(
                  HealingDesignSystem.radiusM,
                ),
                border: Border.all(
                  color:
                      HealingDesignSystem.primaryBlue.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentWeekHasNoDailyRecords
                        ? '沒有每天記，也可以留下一個這週。'
                        : '把這週整理成一筆週紀錄。',
                    style: TextStyle(
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentWeekHasNoDailyRecords
                        ? '不用補登，只回答一個必填問題；其他都可以跳過。'
                        : '每日紀錄保留細節，週回顧留下可用於趨勢與回診摘要的整體輪廓。',
                    style: TextStyle(
                      color: HealingDesignSystem.adaptiveSecondaryText(context),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: const Key('start_weekly_review_button'),
                    onPressed: onStartWeeklyReview,
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: const Text('開始 3 分鐘每週回顧'),
                    style: FilledButton.styleFrom(
                      backgroundColor: HealingDesignSystem.primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeeklyRecordSummary extends StatelessWidget {
  const _WeeklyRecordSummary({required this.record});

  final WeeklyRecord record;

  static const _stateLabels = ['很辛苦', '有些低落', '普通', '還不錯', '很好'];

  @override
  Widget build(BuildContext context) {
    final stateIndex = record.overallState.clamp(1, 5) - 1;
    final details = <String>[
      if (record.comparison != null) '較上週${record.comparison}',
      if (record.emotions.isNotEmpty) '情緒 ${record.emotions.take(3).join('、')}',
      if (record.sleepQuality != null) '睡眠 ${record.sleepQuality}/5',
      if (record.energyLevel != null) '力氣 ${record.energyLevel}/5',
      if (record.emotions.isEmpty && record.feeling != null) record.feeling!,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HealingDesignSystem.primaryBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        border: Border.all(
          color: HealingDesignSystem.primaryBlue.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: HealingDesignSystem.successGreen,
                size: 20,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '本週已留下週紀錄：${_stateLabels[stateIndex]}',
                  style: TextStyle(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details.join(' · '),
              style: TextStyle(
                color: HealingDesignSystem.adaptiveSecondaryText(context),
                fontSize: 12,
              ),
            ),
          ],
          if (record.emotions.isNotEmpty ||
              record.sleepQuality != null ||
              record.symptoms.isNotEmpty ||
              record.functionImpacts.isNotEmpty ||
              record.majorChanges.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              record.visitSummary,
              style: TextStyle(
                color: HealingDesignSystem.adaptivePrimaryText(context),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          if (record.note != null) ...[
            const SizedBox(height: 8),
            Text(
              record.note!,
              style: TextStyle(
                color: HealingDesignSystem.adaptivePrimaryText(context),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
