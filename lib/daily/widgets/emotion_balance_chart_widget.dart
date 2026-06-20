import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../emotion_trend_calculator.dart';
import '../../models/daily_record.dart';

int? _wholeNumberX(double value) {
  final rounded = value.round();
  return (value - rounded).abs() < 0.001 ? rounded : null;
}

String _formatChartNumber(double value) => value.toStringAsFixed(1);

({double minY, double maxY}) _yBounds(
  List<LineChartBarData> bars, {
  required double minScaleY,
  required double maxScaleY,
}) {
  final allSpots = bars
      .expand((bar) => bar.spots)
      .where((spot) => spot.isNotNull())
      .toList();

  if (allSpots.isEmpty) {
    return (minY: minScaleY, maxY: maxScaleY);
  }

  final minSpotY = allSpots.map((s) => s.y).reduce(min);
  final maxSpotY = allSpots.map((s) => s.y).reduce(max);
  final bottom = min(minScaleY, minSpotY);
  final top = max(maxScaleY, maxSpotY);
  final padding = max((top - bottom).abs() * 0.08, 0.5);

  return (minY: bottom - padding, maxY: top + padding);
}

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

  ({double minX, double maxX}) _xBounds(List<LineChartBarData> bars) {
    final allSpots = bars
        .expand((bar) => bar.spots)
        .where((spot) => spot.isNotNull())
        .toList();

    if (allSpots.isEmpty) {
      return (minX: -0.5, maxX: 1.0);
    }

    final minSpotX = allSpots.map((s) => s.x).reduce(min);
    final maxSpotX = allSpots.map((s) => s.x).reduce(max);

    return (
      minX: minSpotX - 0.5,
      maxX: maxSpotX + 1.5,
    );
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

    final dates = source.keys.toList()..sort();
    return dates
        .map(
          (date) => FlSpot(
            date.difference(startDate).inDays.toDouble(),
            source[date]!,
          ),
        )
        .toList();
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
    final xBounds = _xBounds(lineBars);
    // X 軸標籤：依資料範圍動態決定顯示頻率，避免重疊
    final labelPositions = <int>{};
    if (sortedDates.isNotEmpty) {
      final maxLabels = totalDays <= 30 ? 4 : 3;
      final step = ((sortedDates.length - 1) / (maxLabels - 1))
          .ceil()
          .clamp(1, sortedDates.length);
      for (var i = 0; i < sortedDates.length; i += step) {
        labelPositions.add(forceMonthlyAverage
            ? i
            : sortedDates[i].difference(startDate).inDays);
      }
      // 確保最後一筆日期有標籤
      final lastPos = forceMonthlyAverage
          ? sortedDates.length - 1
          : sortedDates.last.difference(startDate).inDays;
      if (!labelPositions.contains(lastPos)) {
        labelPositions.add(lastPos);
      }
    }

    // 判斷量表範圍
    final maxScale = records.any((r) => r.moodScale == 10) ? 10 : 5;
    final yBounds = _yBounds(
      lineBars,
      minScaleY: 0,
      maxScaleY: maxScale.toDouble(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 18, bottom: 8),
            child: LineChart(
              LineChartData(
                clipData: const FlClipData.none(),
                minY: yBounds.minY,
                maxY: yBounds.maxY,
                minX: xBounds.minX,
                maxX: xBounds.maxX,
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
                      reservedSize: 34,
                      getTitlesWidget: (value, meta) {
                        if (value < 0 || value > maxScale) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          _formatChartNumber(value),
                          style: TextStyle(
                            color: HealingDesignSystem.adaptiveSecondaryText(
                                context),
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) {
                        final index = _wholeNumberX(value);
                        if (index == null) {
                          return const SizedBox.shrink();
                        }
                        if (!labelPositions.contains(index)) {
                          return const SizedBox.shrink();
                        }
                        if (index < 0 ||
                            index >=
                                (forceMonthlyAverage
                                    ? sortedDates.length
                                    : totalDays)) {
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
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) {
                      return spots.map((spot) {
                        final label = spot.barIndex == 0 ? '正向' : '負向';
                        return LineTooltipItem(
                          '$label ${_formatChartNumber(spot.y)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: lineBars,
              ),
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

class EmotionBalanceTrendChartWidget extends StatelessWidget {
  const EmotionBalanceTrendChartWidget({
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
        if (point.emotionBalance != null) _norm(point.date): point,
    };
  }

  double? _movingAverageFor(
    DateTime targetDate,
    Map<DateTime, DailyEmotionTrendPoint> source,
  ) {
    final end = _norm(targetDate);
    final start = end.subtract(const Duration(days: 6));
    var total = 0.0;
    var count = 0;

    source.forEach((date, point) {
      if (date.isBefore(start) || date.isAfter(end)) return;
      final value = point.emotionBalance;
      if (value == null) return;
      total += value;
      count++;
    });

    if (count == 0) return null;
    return total / count;
  }

  Map<DateTime, double> _dailySeries(
    Map<DateTime, DailyEmotionTrendPoint> visibleSource,
    Map<DateTime, DailyEmotionTrendPoint> fullSource,
  ) {
    final result = <DateTime, double>{};
    final dates = visibleSource.keys.toList()..sort();

    for (final date in dates) {
      final value = useMovingAverage
          ? _movingAverageFor(date, fullSource)
          : visibleSource[date]?.emotionBalance;
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

  ({double minX, double maxX}) _xBounds(List<LineChartBarData> bars) {
    final allSpots = bars
        .expand((bar) => bar.spots)
        .where((spot) => spot.isNotNull())
        .toList();

    if (allSpots.isEmpty) {
      return (minX: -0.5, maxX: 1.0);
    }

    final minSpotX = allSpots.map((s) => s.x).reduce(min);
    final maxSpotX = allSpots.map((s) => s.x).reduce(max);

    return (
      minX: minSpotX - 0.5,
      maxX: maxSpotX + 1.5,
    );
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

    final dates = source.keys.toList()..sort();
    return dates
        .map(
          (date) => FlSpot(
            date.difference(startDate).inDays.toDouble(),
            source[date]!,
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibleSource = _pointMap(records);
    final fullSource = _pointMap(fullRecords);

    var series = _dailySeries(visibleSource, fullSource);
    if (forceMonthlyAverage) {
      series = _monthlyMovingAverage(series);
    }

    final sortedDates = series.keys.toList()..sort();
    if (sortedDates.isEmpty) {
      return Center(
        child: Text(
          '這段時間還沒有足夠的情緒平衡資料',
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
    final lineColor = HealingDesignSystem.adaptiveAccent(context);
    final lineBars = [
      LineChartBarData(
        spots: _spots(
          source: series,
          startDate: startDate,
          totalDays: totalDays,
          sortedDates: sortedDates,
        ),
        isCurved: true,
        color: lineColor,
        barWidth: 3,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(
          show: true,
          color: lineColor.withValues(alpha: 0.08),
        ),
      ),
    ];
    final xBounds = _xBounds(lineBars);
    final yBounds = _yBounds(
      lineBars,
      minScaleY: -5,
      maxScaleY: 5,
    );

    // X 軸標籤：依資料範圍動態決定顯示頻率，避免重疊
    final labelPositions = <int>{};
    if (sortedDates.isNotEmpty) {
      final maxLabels = totalDays <= 30 ? 4 : 3;
      final step = ((sortedDates.length - 1) / (maxLabels - 1))
          .ceil()
          .clamp(1, sortedDates.length);
      for (var i = 0; i < sortedDates.length; i += step) {
        labelPositions.add(forceMonthlyAverage
            ? i
            : sortedDates[i].difference(startDate).inDays);
      }
      // 確保最後一筆日期有標籤
      final lastPos = forceMonthlyAverage
          ? sortedDates.length - 1
          : sortedDates.last.difference(startDate).inDays;
      if (!labelPositions.contains(lastPos)) {
        labelPositions.add(lastPos);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 18, bottom: 8),
            child: LineChart(
              LineChartData(
                clipData: const FlClipData.none(),
                minY: yBounds.minY,
                maxY: yBounds.maxY,
                minX: xBounds.minX,
                maxX: xBounds.maxX,
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: HealingDesignSystem.adaptiveSecondaryText(context)
                          .withValues(alpha: 0.35),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ],
                ),
                gridData: const FlGridData(
                  show: true,
                  horizontalInterval: 2.5,
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
                      interval: 2.5,
                      reservedSize: 34,
                      getTitlesWidget: (value, meta) {
                        if (value < -5 || value > 5) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          _formatChartNumber(value),
                          style: TextStyle(
                            color: HealingDesignSystem.adaptiveSecondaryText(
                                context),
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) {
                        final index = _wholeNumberX(value);
                        if (index == null) {
                          return const SizedBox.shrink();
                        }
                        if (!labelPositions.contains(index)) {
                          return const SizedBox.shrink();
                        }
                        if (index < 0 ||
                            index >=
                                (forceMonthlyAverage
                                    ? sortedDates.length
                                    : totalDays)) {
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
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) {
                      return spots
                          .map(
                            (spot) => LineTooltipItem(
                              '平衡 ${_formatChartNumber(spot.y)}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                          .toList();
                    },
                  ),
                ),
                lineBarsData: lineBars,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '0 以上代表這段時間正向感受平均較高；0 以下代表負向感受平均較高。',
          style: TextStyle(
            color: HealingDesignSystem.adaptiveSecondaryText(context),
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
