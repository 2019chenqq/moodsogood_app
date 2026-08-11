import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../emotion_trend_calculator.dart';
import '../../models/daily_record.dart';
import '../../models/period_cycle.dart';

int? _wholeNumberX(double value) {
  final rounded = value.round();
  return (value - rounded).abs() < 0.001 ? rounded : null;
}

String _formatChartNumber(double value) => value.toStringAsFixed(1);

const double _sameDayTooltipTouchThreshold = 18;
const double _singleLineTooltipTouchThreshold = double.infinity;

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

DateTime _normDate(DateTime d) => DateTime(d.year, d.month, d.day);

List<VerticalRangeAnnotation> _buildPeriodRanges(
  List<PeriodCycle> cycles, {
  required double Function(DateTime date) xForDate,
  required double minX,
  required double maxX,
}) {
  final list = <VerticalRangeAnnotation>[];
  final periodDays = cycles
      .expand((cycle) sync* {
        final start = _normDate(cycle.startDate);
        final end = _normDate(cycle.endDate ?? DateTime.now());
        for (var day = start;
            !day.isAfter(end);
            day = day.add(const Duration(days: 1))) {
          yield day;
        }
      })
      .toSet()
      .toList()
    ..sort();
  if (periodDays.isEmpty) return list;

  final completedDurations = cycles
      .where((cycle) => cycle.endDate != null)
      .map((cycle) => cycle.durationDays)
      .where((days) => days > 0 && days <= 14)
      .toList();
  final averageDuration = completedDurations.isEmpty
      ? 7
      : (completedDurations.reduce((a, b) => a + b) / completedDurations.length)
          .round();
  final bridgeGapDays = max(7, averageDuration).clamp(1, 14);
  double? periodStartX;
  DateTime? previousPeriodDate;

  void addRange(DateTime endDate) {
    if (periodStartX == null) return;
    final rawX1 = periodStartX! - 0.5;
    final rawX2 = xForDate(endDate) + 0.5;
    if (rawX2 < minX || rawX1 > maxX) {
      periodStartX = null;
      previousPeriodDate = null;
      return;
    }
    double x1 = rawX1;
    double x2 = rawX2;
    x1 = x1.clamp(minX, maxX);
    x2 = x2.clamp(minX, maxX);
    if (x2 >= x1) {
      list.add(VerticalRangeAnnotation(
        x1: x1,
        x2: x2,
        color: Colors.pink.withValues(alpha: 0.15),
      ));
    }
    periodStartX = null;
    previousPeriodDate = null;
  }

  for (final day in periodDays) {
    if (previousPeriodDate != null &&
        day.difference(previousPeriodDate!).inDays > bridgeGapDays) {
      addRange(previousPeriodDate!);
    }
    periodStartX ??= xForDate(day);
    previousPeriodDate = day;
  }

  if (previousPeriodDate != null) {
    addRange(previousPeriodDate!);
  }
  return list;
}

FlDotData _dotDataForSpots(List<FlSpot> spots, Color color) {
  if (spots.length != 1) {
    return const FlDotData(show: false);
  }

  return FlDotData(
    show: true,
    getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
      radius: 4,
      color: color,
      strokeWidth: 0,
    ),
  );
}

List<LineTooltipItem?> _sameDayTooltipItems(
  List<LineBarSpot> spots, {
  required Color positiveColor,
  required DateTime Function(LineBarSpot spot) dateForSpot,
}) {
  if (spots.isEmpty) {
    return const [];
  }

  final targetSpot = spots.reduce((current, next) {
    final currentDistance =
        current is TouchLineBarSpot ? current.distance : 0.0;
    final nextDistance = next is TouchLineBarSpot ? next.distance : 0.0;
    return nextDistance < currentDistance ? next : current;
  });
  final targetDate = dateForSpot(targetSpot);
  final dateLabel = '${targetDate.month}/${targetDate.day}';

  return spots.map((spot) {
    if (dateForSpot(spot) != targetDate) {
      return null;
    }

    final label = spot.bar.color == positiveColor ? '正向' : '負向';
    return LineTooltipItem(
      '$dateLabel $label ${_formatChartNumber(spot.y)}',
      const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    );
  }).toList();
}

class EmotionBalanceChartWidget extends StatelessWidget {
  const EmotionBalanceChartWidget({
    super.key,
    required this.records,
    required this.fullRecords,
    required this.useMovingAverage,
    this.forceMonthlyAverage = false,
    this.periodCycles = const <PeriodCycle>[],
    this.aggregatePoints = const <DailyEmotionTrendPoint>[],
    this.fullAggregatePoints = const <DailyEmotionTrendPoint>[],
  });

  final List<DailyRecord> records;
  final List<DailyRecord> fullRecords;
  final bool useMovingAverage;
  final bool forceMonthlyAverage;
  final List<PeriodCycle> periodCycles;
  final List<DailyEmotionTrendPoint> aggregatePoints;
  final List<DailyEmotionTrendPoint> fullAggregatePoints;

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
    final visibleSource = aggregatePoints.isEmpty
        ? _pointMap(records)
        : {
            for (final point in aggregatePoints)
              if (point.hasClassifiedData) _norm(point.date): point,
          };
    final fullSource = fullAggregatePoints.isEmpty
        ? _pointMap(fullRecords)
        : {
            for (final point in fullAggregatePoints)
              if (point.hasClassifiedData) _norm(point.date): point,
          };

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
    final positiveSpots = positiveSeries.isEmpty
        ? <FlSpot>[]
        : _spots(
            source: positiveSeries,
            startDate: startDate,
            totalDays: totalDays,
            sortedDates: sortedDates,
          );
    final positiveDates = positiveSeries.keys.toList()..sort();
    final negativeSpots = negativeSeries.isEmpty
        ? <FlSpot>[]
        : _spots(
            source: negativeSeries,
            startDate: startDate,
            totalDays: totalDays,
            sortedDates: sortedDates,
          );
    final negativeDates = negativeSeries.keys.toList()..sort();

    final lineBars = <LineChartBarData>[
      if (positiveSeries.isNotEmpty)
        LineChartBarData(
          spots: positiveSpots,
          isCurved: false,
          color: positiveColor,
          barWidth: 3,
          dotData: _dotDataForSpots(positiveSpots, positiveColor),
          belowBarData: BarAreaData(
            show: true,
            color: positiveColor.withValues(alpha: 0.08),
          ),
        ),
      if (negativeSeries.isNotEmpty)
        LineChartBarData(
          spots: negativeSpots,
          isCurved: false,
          color: negativeColor,
          barWidth: 3,
          dotData: _dotDataForSpots(negativeSpots, negativeColor),
          belowBarData: BarAreaData(
            show: true,
            color: negativeColor.withValues(alpha: 0.08),
          ),
        ),
    ];
    final xBounds = _xBounds(lineBars);
    double xForDate(DateTime date) {
      if (forceMonthlyAverage) {
        final month = DateTime(date.year, date.month, 1);
        final index = sortedDates.indexOf(month);
        if (index >= 0) return index.toDouble();

        final insertionIndex = sortedDates.indexWhere((d) => d.isAfter(month));
        if (insertionIndex >= 0) return insertionIndex.toDouble();
        return (sortedDates.length - 1).toDouble();
      }

      return _norm(date).difference(startDate).inDays.toDouble();
    }

    final periodRanges = _buildPeriodRanges(
      periodCycles,
      xForDate: xForDate,
      minX: xBounds.minX,
      maxX: xBounds.maxX,
    );

    DateTime dateForSpot(LineBarSpot spot) {
      final dates = spot.barIndex == 0 ? positiveDates : negativeDates;
      final index = spot.spotIndex;
      if (index < 0 || index >= dates.length) {
        return startDate;
      }
      return dates[index];
    }

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
    final yMin = 0.0;
    final yMax = maxScale.toDouble();
    final yInterval = maxScale == 5 ? 1.0 : 2.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 18, bottom: 8),
            child: LineChart(
              LineChartData(
                clipData: const FlClipData.none(),
                minY: yMin,
                maxY: yMax,
                minX: xBounds.minX,
                maxX: xBounds.maxX,
                rangeAnnotations: RangeAnnotations(
                  verticalRangeAnnotations: periodRanges,
                ),
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: yInterval,
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
                      interval: yInterval,
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
                  touchSpotThreshold: _sameDayTooltipTouchThreshold,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => _sameDayTooltipItems(
                      spots,
                      positiveColor: positiveColor,
                      dateForSpot: dateForSpot,
                    ),
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
    this.periodCycles = const <PeriodCycle>[],
    this.aggregatePoints = const <DailyEmotionTrendPoint>[],
    this.fullAggregatePoints = const <DailyEmotionTrendPoint>[],
  });

  final List<DailyRecord> records;
  final List<DailyRecord> fullRecords;
  final bool useMovingAverage;
  final bool forceMonthlyAverage;
  final List<PeriodCycle> periodCycles;
  final List<DailyEmotionTrendPoint> aggregatePoints;
  final List<DailyEmotionTrendPoint> fullAggregatePoints;

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
    final visibleSource = aggregatePoints.isEmpty
        ? _pointMap(records)
        : {
            for (final point in aggregatePoints)
              if (point.emotionBalance != null) _norm(point.date): point,
          };
    final fullSource = fullAggregatePoints.isEmpty
        ? _pointMap(fullRecords)
        : {
            for (final point in fullAggregatePoints)
              if (point.emotionBalance != null) _norm(point.date): point,
          };

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
    final balanceSpots = _spots(
      source: series,
      startDate: startDate,
      totalDays: totalDays,
      sortedDates: sortedDates,
    );
    final balanceDates = series.keys.toList()..sort();
    final lineBars = [
      LineChartBarData(
        spots: balanceSpots,
        isCurved: false,
        color: lineColor,
        barWidth: 3,
        dotData: _dotDataForSpots(balanceSpots, lineColor),
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
    double xForDate(DateTime date) {
      if (forceMonthlyAverage) {
        final month = DateTime(date.year, date.month, 1);
        final index = sortedDates.indexOf(month);
        if (index >= 0) return index.toDouble();

        final insertionIndex = sortedDates.indexWhere((d) => d.isAfter(month));
        if (insertionIndex >= 0) return insertionIndex.toDouble();
        return (sortedDates.length - 1).toDouble();
      }

      return _norm(date).difference(startDate).inDays.toDouble();
    }

    final periodRanges = _buildPeriodRanges(
      periodCycles,
      xForDate: xForDate,
      minX: xBounds.minX,
      maxX: xBounds.maxX,
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
                rangeAnnotations: RangeAnnotations(
                  verticalRangeAnnotations: periodRanges,
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: HealingDesignSystem.adaptiveSecondaryText(context)
                          .withValues(alpha: 0.35),
                      strokeWidth: 1,
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
                  touchSpotThreshold: _singleLineTooltipTouchThreshold,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) {
                      return spots
                          .map(
                            (spot) => LineTooltipItem(
                              '${balanceDates[spot.spotIndex].month}/${balanceDates[spot.spotIndex].day} 平衡 ${_formatChartNumber(spot.y)}',
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
