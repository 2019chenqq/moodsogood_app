import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../../models/daily_record.dart';
import '../../utils/date_helper.dart';

class WeeklySummaryCard extends StatelessWidget {
  final List<DailyRecord> allRecords;
  final int weekStartDay;

  const WeeklySummaryCard({
    super.key,
    required this.allRecords,
    required this.weekStartDay,
  });

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int? _nightSleepMinutes(DailyRecord record) {
    final end = record.sleep.finalWakeTime ?? record.sleep.wakeTime;
    if (record.sleep.sleepTime == null || end == null) return null;
    final minutes =
        DateHelper.calcDurationMinutes(record.sleep.sleepTime!, end);
    return minutes > 0 ? minutes : null;
  }

  DateTimeRange _weekWindow() {
    final today = _dateOnly(DateTime.now());
    final normalizedWeekStart =
        (weekStartDay >= DateTime.monday && weekStartDay <= DateTime.sunday)
            ? weekStartDay
            : DateTime.monday;
    final delta = (today.weekday - normalizedWeekStart + 7) % 7;
    final start = today.subtract(Duration(days: delta));
    final end = start.add(const Duration(days: 6));
    return DateTimeRange(start: start, end: end);
  }

  @override
  Widget build(BuildContext context) {
    final range = _weekWindow();
    final start = _dateOnly(range.start);
    final end = _dateOnly(range.end);

    // 篩選出本週 7 天區間的紀錄
    final weekRecords = allRecords.where((r) {
      final date = _dateOnly(r.date);
      return !date.isBefore(start) && !date.isAfter(end);
    }).toList();

    const totalDays = 7;
    final recordedDays = weekRecords.length;

    final nightSleepMinutesList = <int>[];
    final dailyTotalMinutesList = <int>[];

    for (final record in allRecords) {
      final nightMinutes = _nightSleepMinutes(record);
      if (nightMinutes != null) {
        nightSleepMinutesList.add(nightMinutes);
      }

      final napMinutes = record.sleep.naps
          .fold<int>(0, (sum, nap) => sum + nap.durationMinutes);
      final totalMinutes = (nightMinutes ?? 0) + napMinutes;
      if (totalMinutes > 0) {
        dailyTotalMinutesList.add(totalMinutes);
      }
    }

    final avgNightSleepMinutes = nightSleepMinutesList.isEmpty
        ? null
        : nightSleepMinutesList.reduce((a, b) => a + b) /
            nightSleepMinutesList.length;

    final avgDailySleepMinutes = dailyTotalMinutesList.isEmpty
        ? null
        : dailyTotalMinutesList.reduce((a, b) => a + b) /
            dailyTotalMinutesList.length;

    final nightAvgText = avgNightSleepMinutes == null
        ? '-'
        : DateHelper.formatDurationText(avgNightSleepMinutes.round());
    final dailyAvgText = avgDailySleepMinutes == null
        ? '-'
        : DateHelper.formatDurationText(avgDailySleepMinutes.round());

    // 鼓勵語句
    final String message;
    if (recordedDays == 0) {
      message = '這週還沒有開始記錄，沒關係，可以從今天慢慢來。';
    } else if (recordedDays <= 3) {
      message = '這週已經有 $recordedDays 天留下紀錄了，願意給自己這些時間，很不容易。';
    } else if (recordedDays < 7) {
      message = '這週大部分的日子你都有努力關心自己，已經很棒了。';
    } else {
      message = '這週每天都有陪自己走一下，謝謝你這麼努力地活著。';
    }

    // 紀錄天數進度條比例
    final progress = recordedDays / totalDays;

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
                    '這週小結',
                    style: TextStyle(
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${start.month}/${start.day} – ${end.month}/${end.day}',
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
                '$recordedDays / $totalDays 天',
                style: const TextStyle(
                  color: HealingDesignSystem.primaryBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: HealingDesignSystem.adaptiveCardBorder(context),
              valueColor: const AlwaysStoppedAnimation<Color>(
                  HealingDesignSystem.primaryBlue),
            ),
          ),

          const SizedBox(height: 14),

          // Stats row
          Row(
            children: [
              Expanded(
                child: _WeekStatItem(
                  icon: Icons.nightlight_round,
                  label: '夜眠（累積均）',
                  value: nightAvgText,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _WeekStatItem(
                  icon: Icons.bedtime_outlined,
                  label: '全日睡眠（均）',
                  value: dailyAvgText,
                ),
              ),
            ],
          ),

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

class _WeekStatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WeekStatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: HealingDesignSystem.adaptiveFill(context),
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusS),
        border: Border.all(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: HealingDesignSystem.primaryBlue),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: HealingDesignSystem.adaptivePrimaryText(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
