import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../models/follow_up_ai_summary.dart';
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
    final duration = _map(sleep['durationHours']);
    final quality = _map(sleep['quality']);
    final valuesByDate = <DateTime, double>{};
    for (final item in _list(duration['dailyTrend'])) {
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
    final recordedDays = _integer(duration['recordedDays']);
    final average = _number(duration['average']);
    final minimum = _number(duration['minimum']);
    final maximum = _number(duration['maximum']);
    final naps = _map(sleep['naps']);
    final summary = SleepPeriodSummary(
      periodDays: points.length,
      recordDays: recordedDays,
      validNightDays: recordedDays,
      napDays: _integer(naps['days']),
      napCount: _integer(naps['count']),
      hypnoticDays: 0,
      qualityDays: _integer(quality['recordedDays']),
      averageNightMinutes: average == null ? null : average * 60,
      averageTotalMinutes: average == null ? null : average * 60,
      averageQuality: _number(quality['average']),
      shortestNightMinutes: minimum == null ? null : (minimum * 60).round(),
      longestNightMinutes: maximum == null ? null : (maximum * 60).round(),
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
            if (recordedDays == 0)
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
              ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _Metric(label: '有效紀錄', value: '$recordedDays 天'),
              _Metric(label: '平均', value: _hours(average)),
              _Metric(label: '最短', value: _hours(minimum)),
              _Metric(label: '最長', value: _hours(maximum)),
              _Metric(
                  label: '入睡困難',
                  value: '${_occurrences(sleep['sleepOnsetDifficulty'])} 天'),
              _Metric(
                  label: '早醒',
                  value: '${_occurrences(sleep['earlyAwakening'])} 天'),
              _Metric(
                  label: '夜間中斷',
                  value: '${_occurrences(sleep['nightInterruption'])} 天'),
              _Metric(label: '小睡', value: '${_integer(naps['days'])} 天'),
            ]),
          ],
        ),
      ),
    );
  }

  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
  static List<Map<String, dynamic>> _list(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : const [];
  static double? _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  static int _integer(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
  static int _occurrences(dynamic value) =>
      _integer(_map(value)['occurrenceDays']);
  static String _hours(double? value) =>
      value == null ? '無資料' : '${value.toStringAsFixed(1)} 小時';
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
