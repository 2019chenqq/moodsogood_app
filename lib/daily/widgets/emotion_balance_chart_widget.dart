import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../emotion_trend_calculator.dart';
import '../../models/daily_record.dart';

class EmotionBalanceChartWidget extends StatelessWidget {
  const EmotionBalanceChartWidget({
    super.key,
    required this.records,
    required this.fullRecords,
    required this.useMovingAverage,
    this.forceMonthlyAverage = false,
  });

  final List<DailyRecord> records;
  final List<DailyRecord> fullRecords;
  final bool useMovingAverage;
  final bool forceMonthlyAverage;

  DateTime _norm(DateTime d) => DateTime(d.year, d.month, d.day);

  Map<DateTime, DailyEmotionTrendPoint> _pointMap(List<DailyRecord> source) {
    final points = EmotionTrendCalculator.calculate(source);
    return {
      for (final point in points)
        if (point.hasClassifiedData) _norm(point.date): point,
    };
  }

  double? _averageFor(
    DateTime date,
    bool positive,
    Map<DateTime, DailyEmotionTrendPoint> source,
  ) {
    final point = source[_norm(date)];
    return positive ? point?.positiveAverage : point?.negativeAverage;
  }

  double? _movingAverageFor(
    DateTime targetDate,
    bool positive,
    Map<DateTime, DailyEmotionTrendPoint> source,
  ) {
    final end = _norm(targetDate);
    final start = end.subtract(const Duration(days: 6));
    var total = 0.0;
    var count = 0;

    source.forEach((date, point) {
      if (date.isBefore(start) || date.isAfter(end)) return;
      final value = positive ? point.positiveAverage : point.negativeAverage;
      if (value == null) return;
      total += value;
      count++;
    });

    if (count == 0) return null;
    return total / count;
  }

  Map<DateTime, double> _dailySeries(
    bool positive,
    Map<DateTime, DailyEmotionTrendPoint> visibleSource,
    Map<DateTime, DailyEmotionTrendPoint> fullSource,
  ) {
    final result = <DateTime, double>{};
    final dates = visibleSource.keys.toList()..sort();

    for (final date in dates) {
      final value = useMovingAverage
          ? _movingAverageFor(date, positive, fullSource)
          : _averageFor(date, positive, visibleSource);
      if (value != null) {
        result[date] = value;
      }
    }

    return result;
  }

  Map<DateTime, double> _monthlyMovingAverage(Map<DateTime, double> source) {
    final buckets = <DateTime, List<double>>{};
    source.forEach((date, value) {
      (buckets[DateTime(date.year, date.month, 1)] ??= <double>[]).add(value);
    });

    final monthKeys = buckets.keys.toList()..sort();
    final monthlyAverage = <DateTime, double>{};
    for (final month in monthKeys) {
      final values = buckets[month]!;
      monthlyAverage[month] = values.reduce((a, b) => a + b) / values.length;
    }

    final result = <DateTime, double>{};
    for (var i = 0; i < monthKeys.length; i++) {
      final start = (i - 2).clamp(0, i);
      final window = monthKeys.sublist(start, i + 1);
      final values = window.map((month) => monthlyAverage[month]!).toList();
      result[monthKeys[i]] = values.reduce((a, b) => a + b) / values.length;
    }
    return result;
  }

  List<FlSpot> _spots({
    required Map<DateTime, double> source,
    required DateTime startDate,
    required int totalDays,
    required List<DateTime> sortedDates,
  }) {
    if (forceMonthlyAverage) {
      return sortedDates
          .where(source.containsKey)
          .map((date) =>
              FlSpot(sortedDates.indexOf(date).toDouble(), source[date]!))
          .toList();
    }

    return List.generate(totalDays, (index) {
      final date = startDate.add(Duration(days: index));
      final value = source[_norm(date)];
      return value == null ? FlSpot.nullSpot : FlSpot(index.toDouble(), value);
    });
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleSource = _pointMap(records);
    final fullSource = _pointMap(fullRecords);

    var positiveSeries = _dailySeries(true, visibleSource, fullSource);
    var negativeSeries = _dailySeries(false, visibleSource, fullSource);

    if (forceMonthlyAverage) {
      positiveSeries = _monthlyMovingAverage(positiveSeries);
      negativeSeries = _monthlyMovingAverage(negativeSeries);
    }

    final sortedDates = {
      ...positiveSeries.keys,
      ...negativeSeries.keys,
    }.toList()
      ..sort();

    if (sortedDates.isEmpty) {
      return Center(
        child: Text(
          '這段時間還沒有足夠的正向 / 負向感受資料',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: HealingDesignSystem.adaptiveSecondaryText(context),
            fontSize: 13,
          ),
        ),
      );
    }

    final startDate = sortedDates.first;
    final endDate = sortedDates.last;
    final totalDays = forceMonthlyAverage
        ? sortedDates.length
        : endDate.difference(startDate).inDays + 1;

    final positiveColor = HealingDesignSystem.primaryBlue;
    final negativeColor = Colors.deepOrange.shade300;

    final lineBars = <LineChartBarData>[
      if (positiveSeries.isNotEmpty)
        LineChartBarData(
          spots: _spots(
            source: positiveSeries,
            startDate: startDate,
            totalDays: totalDays,
            sortedDates: sortedDates,
          ),
          isCurved: true,
          color: positiveColor,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: positiveColor.withValues(alpha: 0.08),
          ),
        ),
      if (negativeSeries.isNotEmpty)
        LineChartBarData(
          spots: _spots(
            source: negativeSeries,
            startDate: startDate,
            totalDays: totalDays,
            sortedDates: sortedDates,
          ),
          isCurved: true,
          color: negativeColor,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: negativeColor.withValues(alpha: 0.08),
          ),
        ),
    ];

    final labelPositions = <int>{};
    final step =
        ((sortedDates.length - 1) / 6).ceil().clamp(1, sortedDates.length);
    for (var i = 0; i < sortedDates.length; i += step) {
      labelPositions.add(forceMonthlyAverage
          ? i
          : sortedDates[i].difference(startDate).inDays);
    }
    labelPositions.add(forceMonthlyAverage
        ? sortedDates.length - 1
        : sortedDates.last.difference(startDate).inDays);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: 10,
              minX: 0,
              maxX: (totalDays - 1).toDouble(),
              gridData: const FlGridData(
                show: true,
                horizontalInterval: 2,
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 2,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) => Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color:
                            HealingDesignSystem.adaptiveSecondaryText(context),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (!labelPositions.contains(index)) {
                        return const SizedBox.shrink();
                      }
                      final date = forceMonthlyAverage
                          ? sortedDates[index]
                          : startDate.add(Duration(days: index));
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          forceMonthlyAverage
                              ? '${date.year}/${date.month.toString().padLeft(2, '0')}'
                              : '${date.month}/${date.day}',
                          style: TextStyle(
                            color: HealingDesignSystem.adaptiveSecondaryText(
                                context),
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: lineBars,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _legendDot(positiveColor),
                const SizedBox(width: 6),
                Text(
                  '正向感受',
                  style: TextStyle(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _legendDot(negativeColor),
                const SizedBox(width: 6),
                Text(
                  '負向感受',
                  style: TextStyle(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
