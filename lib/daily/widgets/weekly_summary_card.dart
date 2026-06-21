import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../../models/daily_record.dart';

class WeeklySummaryCard extends StatelessWidget {
  final List<DailyRecord> records;
  final String title;
  final String subtitle;
  final int? totalDays;

  const WeeklySummaryCard({
    super.key,
    required this.records,
    required this.title,
    required this.subtitle,
    required this.totalDays,
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
                  color: HealingDesignSystem.primaryBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: HealingDesignSystem.primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Column(
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
                      color: HealingDesignSystem.adaptiveSecondaryText(context),
                      fontSize: 12,
                    ),
                  ),
                ],
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
        ],
      ),
    );
  }
}
