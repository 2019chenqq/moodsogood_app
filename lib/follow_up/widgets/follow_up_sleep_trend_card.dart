import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../models/follow_up_ai_summary.dart';
import '../models/follow_up_sleep_summary_view_model.dart';
import '../../sleep_insights/models/sleep_insight_models.dart';
import '../../sleep_insights/widgets/sleep_insights_view.dart';

class FollowUpSleepTrendCard extends StatelessWidget {
  FollowUpSleepTrendCard({super.key, required FollowUpAiV1Input input})
      : periodStart = input.statistics.periodStart,
        periodEnd = input.statistics.periodEnd,
        sleep = input.sleep;

  FollowUpSleepTrendCard.fromRecord({
    super.key,
    required FollowUpSummaryRecord record,
  })  : periodStart = record.periodStart,
        periodEnd = record.periodEnd,
        sleep = {
          ...record.sleepSummary,
          'durationHours': {
            ..._map(record.sleepSummary['durationHours']),
            'dailyTrend': record.sleepTrend,
          },
        };

  final DateTime periodStart;
  final DateTime periodEnd;
  final Map<String, dynamic> sleep;

  @override
  Widget build(BuildContext context) {
    final viewModel = FollowUpSleepSummaryViewModel.fromData(sleep);
    final valuesByDate = <DateTime, double>{};
    for (final item in viewModel.trend) {
      final date = DateTime.tryParse(item['date']?.toString() ?? '');
      final value = _number(item['value']);
      if (date != null && value != null) {
        valuesByDate[DateTime(date.year, date.month, date.day)] = value;
      }
    }
    final points = <SleepTrendPoint>[];
    for (var date = periodStart;
        !date.isAfter(periodEnd);
        date = date.add(const Duration(days: 1))) {
      final day = DateTime(date.year, date.month, date.day);
      final hours = valuesByDate[day];
      points.add(SleepTrendPoint(
        date: day,
        nightMinutes: hours == null ? null : (hours * 60).round(),
        napMinutes: 0,
        napCount: 0,
        flags: const [],
        symptoms: const [],
        emotions: const [],
        isPeriod: false,
        usedEstimatedSleepTime: false,
        hasSleepRecord: hours != null,
      ));
    }
    final summary = SleepPeriodSummary(
      periodDays: points.length,
      recordDays: viewModel.recordedDays,
      validNightDays: viewModel.recordedDays,
      napDays: 0,
      napCount: 0,
      hypnoticDays: 0,
      qualityDays: viewModel.qualityDays,
      averageNightMinutes:
          viewModel.averageHours == null ? null : viewModel.averageHours! * 60,
      averageTotalMinutes:
          viewModel.averageHours == null ? null : viewModel.averageHours! * 60,
      averageQuality: viewModel.averageQuality,
      shortestNightMinutes: viewModel.minimumHours == null
          ? null
          : (viewModel.minimumHours! * 60).round(),
      longestNightMinutes: viewModel.maximumHours == null
          ? null
          : (viewModel.maximumHours! * 60).round(),
      averageNapMinutes: null,
      averageBedtimeMinutes: null,
      averageWakeMinutes: null,
    );

    return Card(
      elevation: 0,
      color: HealingDesignSystem.adaptiveSurface(context),
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.nightlight_round,
                  color: HealingDesignSystem.primaryBlue),
              const SizedBox(width: 8),
              Text('睡眠趨勢', style: HealingDesignSystem.titleSmall),
            ]),
            const SizedBox(height: 12),
            if (viewModel.recordedDays == 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                alignment: Alignment.center,
                child: Text(
                  '統計期間內沒有可用的睡眠時數紀錄',
                  style: HealingDesignSystem.bodyMedium.copyWith(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                  ),
                ),
              )
            else
              SleepTrendChart(
                points: points,
                summary: summary,
                showTotalSeries: false,
                showPointDetails: false,
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: viewModel.metrics
                  .map((metric) =>
                      _Metric(label: metric.label, value: metric.value))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
  static double? _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 104),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: HealingDesignSystem.adaptiveFill(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: HealingDesignSystem.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: HealingDesignSystem.titleSmall),
        ]),
      );
}
