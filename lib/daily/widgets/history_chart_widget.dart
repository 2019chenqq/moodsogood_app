import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/daily_record.dart';
import '../../models/period_cycle.dart';
import '../emotion_trend_calculator.dart';

class EmotionTrendPointPresentation {
  const EmotionTrendPointPresentation(this.point);

  final DailyEmotionValuePoint point;

  bool get showsRangeIndicator {
    final range = point.quickRecordRange;
    return point.scale == 5 &&
        range != null &&
        range.shouldDisplay &&
        range.min < range.max;
  }

  List<String> tooltipLines({
    required String label,
    required double displayedValue,
    required bool showsTrendValue,
  }) {
    final source = switch (point.source) {
      DailyEmotionMainSource.dailyCheckIn => '每日基準',
      DailyEmotionMainSource.dailyRecord => '每日紀錄',
      DailyEmotionMainSource.quickRecordFallback => '快速記錄平均',
    };
    final lines = <String>[
      '$label：${point.mainValue.toStringAsFixed(1)}/${point.scale}',
      '代表值來源：$source',
    ];
    final range = point.quickRecordRange;
    if (range != null) {
      if (range.shouldDisplay) {
        lines.add(
          '快速記錄範圍：${range.min.toStringAsFixed(1)}–'
          '${range.max.toStringAsFixed(1)}',
        );
      }
      lines.add('快速記錄：${range.count}筆');
    }
    if (showsTrendValue) {
      lines.add('趨勢值：${displayedValue.toStringAsFixed(1)}');
    }
    return lines;
  }
}

class HistoryChartWidget extends StatelessWidget {
  final List<DailyRecord> records;
  final List<DailyRecord> fullRecords;
  final String targetEmotion;
  final bool useMovingAverage;
  final bool forceMonthlyAverage; // 新增
  final Map<DateTime, double> diaryMoodScores;
  final String overallMoodLabel;
  final List<PeriodCycle> periodCycles;
  final List<DailyEmotionValuePoint> dailyEmotionPoints;
  final List<DailyEmotionValuePoint> fullDailyEmotionPoints;

  const HistoryChartWidget({
    super.key,
    required this.records,
    required this.fullRecords,
    required this.targetEmotion,
    required this.useMovingAverage,
    this.forceMonthlyAverage = false, // 新增
    this.diaryMoodScores = const <DateTime, double>{},
    this.overallMoodLabel = '整體情緒',
    this.periodCycles = const <PeriodCycle>[],
    this.dailyEmotionPoints = const <DailyEmotionValuePoint>[],
    this.fullDailyEmotionPoints = const <DailyEmotionValuePoint>[],
  });

  Map<DateTime, DailyEmotionValuePoint> _aggregatePointMap(
    Iterable<DailyEmotionValuePoint> points,
  ) =>
      {
        for (final point in points) _norm(point.date): point,
      };

  /// 正規化日期（去除時間部分）
  DateTime _norm(DateTime d) => DateTime(d.year, d.month, d.day);

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

  int? _wholeNumberX(double value) {
    final rounded = value.round();
    return (value - rounded).abs() < 0.001 ? rounded : null;
  }

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

  /// 建立經期粉紅區塊（依照日期距離 startDate 的天數作為 x 座標，並限制在 minX/maxX 內）
  // ignore: unused_element
  List<VerticalRangeAnnotation> _buildPeriodRanges(
    List<DailyRecord> sorted, {
    required double Function(DateTime date) xForDate,
    required double minX,
    required double maxX,
  }) {
    final List<VerticalRangeAnnotation> list = [];
    double? periodStartX;

    for (var r in sorted) {
      final dayX = xForDate(r.date);
      if (r.isPeriod) {
        periodStartX ??= dayX;
      } else if (periodStartX != null) {
        double x1 = periodStartX - 0.5;
        double x2 =
            xForDate(_norm(r.date).subtract(const Duration(days: 1))) + 0.5;
        // 限制區塊在 minX/maxX 內
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
      }
    }
    // 若最後一筆仍為經期
    if (periodStartX != null && sorted.isNotEmpty) {
      final lastX = xForDate(sorted.last.date);
      double x1 = periodStartX - 0.5;
      double x2 = lastX + 0.5;
      x1 = x1.clamp(minX, maxX);
      x2 = x2.clamp(minX, maxX);
      if (x2 >= x1) {
        list.add(VerticalRangeAnnotation(
          x1: x1,
          x2: x2,
          color: Colors.pink.withValues(alpha: 0.15),
        ));
      }
    }
    return list;
  }

  /// 將每日點轉為「月移動平均」點（key 為每月 1 日）
  List<VerticalRangeAnnotation> _buildVisiblePeriodRanges(
    List<PeriodCycle> cycles, {
    required double Function(DateTime date) xForDate,
    required double minX,
    required double maxX,
  }) {
    final list = <VerticalRangeAnnotation>[];
    final periodDays = cycles
        .expand((cycle) sync* {
          final start = _norm(cycle.startDate);
          final end = _norm(cycle.endDate ?? DateTime.now());
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
        : (completedDurations.reduce((a, b) => a + b) /
                completedDurations.length)
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

  Map<DateTime, double> _toMonthlyMovingAverage(Map<DateTime, double> source) {
    final buckets = <DateTime, List<double>>{};

    source.forEach((date, value) {
      final monthKey = DateTime(date.year, date.month, 1);
      (buckets[monthKey] ??= <double>[]).add(value);
    });

    final monthlyAverage = <DateTime, double>{};
    final keys = buckets.keys.toList()..sort((a, b) => a.compareTo(b));

    for (final k in keys) {
      final vals = buckets[k]!;
      monthlyAverage[k] = vals.reduce((a, b) => a + b) / vals.length;
    }

    final result = <DateTime, double>{};
    for (int i = 0; i < keys.length; i++) {
      final start = (i - 2).clamp(0, i);
      final windowKeys = keys.sublist(start, i + 1);
      final values = windowKeys.map((k) => monthlyAverage[k]!).toList();
      result[keys[i]] = values.reduce((a, b) => a + b) / values.length;
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isOverallMood = targetEmotion == overallMoodLabel;
    final hasAggregatePoints = dailyEmotionPoints.isNotEmpty;
    if (!hasAggregatePoints &&
        records.isEmpty &&
        (!isOverallMood || diaryMoodScores.isEmpty)) {
      return const Center(child: Text('此情緒目前沒有數據'));
    }

    // ===== 1儭 ?渡?鞈?嚗??交???嚗遣蝡?????詨潦??扯” =====
    final sorted = List<DailyRecord>.from(records)
      ..sort((a, b) => a.date.compareTo(b.date));

    final Map<DateTime, double> dateValueMap = {};
    final Map<DateTime, double> emptyPointValueMap = {};
    final aggregatePointMap = _aggregatePointMap(dailyEmotionPoints);
    final fullAggregatePoints = fullDailyEmotionPoints.isEmpty
        ? dailyEmotionPoints
        : fullDailyEmotionPoints;
    if (hasAggregatePoints) {
      final visibleRawValues = <DateTime, double>{};
      final fullRawValues = <DateTime, double>{};
      if (isOverallMood) {
        for (final entry in diaryMoodScores.entries) {
          visibleRawValues[_norm(entry.key)] = entry.value;
          fullRawValues[_norm(entry.key)] = entry.value;
        }
      }
      for (final point in fullAggregatePoints) {
        fullRawValues[_norm(point.date)] = point.mainValue;
      }
      for (final point in dailyEmotionPoints) {
        visibleRawValues[_norm(point.date)] = point.mainValue;
      }

      final visibleDates = visibleRawValues.keys.toList()..sort();
      for (final d in visibleDates) {
        if (useMovingAverage) {
          final start = d.subtract(const Duration(days: 6));
          final values = fullRawValues.entries
              .where((entry) =>
                  !entry.key.isBefore(start) && !entry.key.isAfter(d))
              .map((entry) => entry.value)
              .toList();
          if (values.isNotEmpty) {
            final value = values.reduce((a, b) => a + b) / values.length;
            final filledDays = values.length;
            if (filledDays >= 3) {
              dateValueMap[d] = value;
            } else if (filledDays > 0) {
              emptyPointValueMap[d] = value;
            }
          }
        } else {
          dateValueMap[d] = visibleRawValues[d]!;
        }
      }
    } else if (isOverallMood) {
      final sortedDiaryDates = diaryMoodScores.keys.toList()..sort();
      for (final rawDate in sortedDiaryDates) {
        final d = _norm(rawDate);

        if (useMovingAverage) {
          final filledDays = _countDiaryFilledIn7Days(d);
          final v = _calcDiaryMA7(d, precomputedCount: filledDays);
          if (v != null) {
            if (filledDays >= 3) {
              dateValueMap[d] = v;
            } else if (filledDays > 0) {
              emptyPointValueMap[d] = v;
            }
          }
        } else {
          final v = diaryMoodScores[rawDate] ?? diaryMoodScores[d];
          if (v != null) {
            dateValueMap[d] = v;
          }
        }
      }
    } else {
      for (var r in sorted) {
        final d = _norm(r.date);

        if (useMovingAverage) {
          final filledDays = _countFilledIn7Days(r.date);
          final v = _calcMA7(r.date, precomputedCount: filledDays);

          if (v != null) {
            if (filledDays >= 3) {
              dateValueMap[d] = v;
            } else if (filledDays > 0) {
              emptyPointValueMap[d] = v;
            }
          }
        } else {
          final v = _getValue(r);
          if (v != null) {
            dateValueMap[d] = v;
          }
        }
      }
    }
    if (dateValueMap.isEmpty && emptyPointValueMap.isNotEmpty) {
      // For shorter ranges like 30 days, show available points even when
      // there are fewer than 3 filled days for a stable moving average line.
      dateValueMap.addAll(emptyPointValueMap);
      emptyPointValueMap.clear();
    }

    if (dateValueMap.isEmpty && emptyPointValueMap.isEmpty) {
      return const Center(child: Text('此情緒目前沒有數據'));
    }

    final Map<DateTime, double> effectiveValueMap = forceMonthlyAverage
        ? _toMonthlyMovingAverage(dateValueMap)
        : dateValueMap;
    final Map<DateTime, double> effectiveEmptyMap =
        forceMonthlyAverage ? <DateTime, double>{} : emptyPointValueMap;

    final sortedDates = {
      ...effectiveValueMap.keys,
      ...effectiveEmptyMap.keys,
    }.toList()
      ..sort();
    final recordedCount = sortedDates.length;
    final startDate = sortedDates.first;
    final endDate = sortedDates.last;
    final totalDays = forceMonthlyAverage
        ? sortedDates.length
        : endDate.difference(startDate).inDays + 1;

    // x 軸值 = 距離第一個有紀錄日期的天數
    int dayIdx(DateTime d) => forceMonthlyAverage
        ? sortedDates.indexOf(_norm(d))
        : _norm(d).difference(startDate).inDays;

    final lineColor = useMovingAverage ? Colors.orange : Colors.teal;

    // ≥ 3 天才畫折線；否則只顯示圓點
    final showLine = recordedCount >= 2;

    // ===== 3️⃣ 建立 LineChartBarData =====
    final List<LineChartBarData> barDatas = [];
    final Set<int> rangeBarIndexes = <int>{};
    bool hasDashedSegments = false;

    double? pointY(DateTime d) => effectiveValueMap[d] ?? effectiveEmptyMap[d];

    if (!showLine) {
      // 📍 圓點模式（< 3 天）：只顯示圓點，無連線
      barDatas.add(LineChartBarData(
        spots: effectiveValueMap.keys
            .map((d) => FlSpot(dayIdx(d).toDouble(), effectiveValueMap[d]!))
            .toList(),
        isCurved: false,
        barWidth: 0,
        color: Colors.transparent,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: 6,
            color: lineColor,
            strokeWidth: 2,
            strokeColor: lineColor.withValues(alpha: 0.4),
          ),
        ),
        belowBarData: BarAreaData(show: false),
      ));

      // MA 視窗不足（<3 天）時顯示空心點
      if (effectiveEmptyMap.isNotEmpty) {
        hasDashedSegments = true;
        barDatas.add(LineChartBarData(
          spots: effectiveEmptyMap.keys
              .map((d) => FlSpot(dayIdx(d).toDouble(), effectiveEmptyMap[d]!))
              .toList(),
          isCurved: false,
          barWidth: 0,
          color: Colors.transparent,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 5,
              color: Colors.white,
              strokeWidth: 2,
              strokeColor: lineColor.withValues(alpha: 0.8),
            ),
          ),
          belowBarData: BarAreaData(show: false),
        ));
      }
    } else {
      // 📈 折線模式（≥ 3 天）
      // 實線：在有資料的位置連線，缺漏天插入 nullSpot 使線段斷開
      final solidSpots = <FlSpot>[];
      if (forceMonthlyAverage) {
        for (final date in sortedDates) {
          final v = effectiveValueMap[_norm(date)];
          solidSpots.add(
            v != null ? FlSpot(dayIdx(date).toDouble(), v) : FlSpot.nullSpot,
          );
        }
      } else {
        for (int d = 0; d < totalDays; d++) {
          final date = startDate.add(Duration(days: d));
          final v = effectiveValueMap[_norm(date)];
          solidSpots.add(v != null ? FlSpot(d.toDouble(), v) : FlSpot.nullSpot);
        }
      }
      barDatas.add(LineChartBarData(
        spots: solidSpots,
        isCurved: true,
        color: lineColor,
        barWidth: 3,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: 4,
            color: lineColor,
            strokeWidth: 0,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          color: lineColor.withValues(alpha: 0.12),
        ),
      ));

      // MA 視窗不足（<3 天）時顯示空心點
      if (effectiveEmptyMap.isNotEmpty) {
        hasDashedSegments = true;
        barDatas.add(LineChartBarData(
          spots: effectiveEmptyMap.keys
              .map((d) => FlSpot(dayIdx(d).toDouble(), effectiveEmptyMap[d]!))
              .toList(),
          isCurved: false,
          barWidth: 0,
          color: Colors.transparent,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 5,
              color: Colors.white,
              strokeWidth: 2,
              strokeColor: lineColor.withValues(alpha: 0.8),
            ),
          ),
          belowBarData: BarAreaData(show: false),
        ));
      }

      // 虛線：跨越「缺漏天」或「空心點」的連線段
      for (int i = 0; i < sortedDates.length - 1; i++) {
        final d1 = sortedDates[i];
        final d2 = sortedDates[i + 1];
        final y1 = pointY(d1);
        final y2 = pointY(d2);
        if (y1 == null || y2 == null) continue;

        final bool hasMissingCalendar = d2.difference(d1).inDays > 1;
        final bool includeEmptyPoint = effectiveEmptyMap.containsKey(d1) ||
            effectiveEmptyMap.containsKey(d2);

        if (hasMissingCalendar || includeEmptyPoint) {
          hasDashedSegments = true;
          barDatas.add(LineChartBarData(
            spots: [
              FlSpot(dayIdx(d1).toDouble(), y1),
              FlSpot(dayIdx(d2).toDouble(), y2),
            ],
            isCurved: false,
            color: lineColor.withValues(alpha: 0.5),
            barWidth: 2,
            dashArray: [6, 5],
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ));
        }
      }
    }

    // Range bars consume the already-aggregated QuickRecord min/max values.
    // They are visual evidence only and never enter the trend/MA calculation.
    if (!forceMonthlyAverage) {
      for (final point in dailyEmotionPoints) {
        final presentation = EmotionTrendPointPresentation(point);
        final range = point.quickRecordRange;
        final day = _norm(point.date);
        if (!presentation.showsRangeIndicator ||
            range == null ||
            (!effectiveValueMap.containsKey(day) &&
                !effectiveEmptyMap.containsKey(day))) {
          continue;
        }
        rangeBarIndexes.add(barDatas.length);
        barDatas.add(LineChartBarData(
          spots: [
            FlSpot(dayIdx(day).toDouble(), range.min),
            FlSpot(dayIdx(day).toDouble(), range.max),
          ],
          isCurved: false,
          color: lineColor.withValues(alpha: 0.38),
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ));
      }
    }

    final xBounds = _xBounds(barDatas);

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

    // ===== 4️⃣ 經期粉紅區塊 =====
    final periodRanges = _buildVisiblePeriodRanges(
      periodCycles,
      xForDate: xForDate,
      minX: xBounds.minX,
      maxX: xBounds.maxX,
    );

    // ===== 5️⃣ 判斷量表範圍：5 點量表 max=5，10 點量表 max=10 =====
    final maxScale = dailyEmotionPoints.any((point) => point.scale == 10) ||
            records.any((r) => r.moodScale == 10)
        ? 10
        : 5;

    // ===== 6️⃣ X 軸標籤：依資料點間距動態決定顯示頻率，避免重疊 =====
    final labelPositions = <int>{};
    if (sortedDates.isNotEmpty) {
      // 根據資料範圍長度決定顯示多少標籤
      final maxLabels = totalDays <= 30 ? 5 : 7;
      final step = ((sortedDates.length - 1) / (maxLabels - 1))
          .ceil()
          .clamp(1, sortedDates.length);
      for (int i = 0; i < sortedDates.length; i += step) {
        labelPositions.add(dayIdx(sortedDates[i]));
      }
      // 確保最後一筆日期有標籤
      if (!labelPositions.contains(dayIdx(sortedDates.last))) {
        labelPositions.add(dayIdx(sortedDates.last));
      }
    }

    DateTime dateForX(int x) {
      if (forceMonthlyAverage) {
        return sortedDates[x.clamp(0, sortedDates.length - 1)];
      }
      return startDate.add(Duration(days: x));
    }

    // ===== 7️⃣ 繪製折線圖 =====
    final yBounds = _yBounds(
      barDatas,
      minScaleY: 0,
      maxScaleY: maxScale.toDouble(),
    );

    final chart = LineChart(
      LineChartData(
        clipData: const FlClipData.none(),
        minY: yBounds.minY,
        maxY: yBounds.maxY,
        minX: xBounds.minX,
        maxX: xBounds.maxX,
        rangeAnnotations: RangeAnnotations(
          verticalRangeAnnotations: periodRanges,
        ),
        gridData: FlGridData(
          show: true,
          horizontalInterval: 2,
          drawVerticalLine: false,
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 2,
              reservedSize: 34,
              getTitlesWidget: (v, m) {
                if (v < 0 || v > maxScale) return const SizedBox.shrink();
                return Text(v.toInt().toString());
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 36,
              getTitlesWidget: (val, meta) {
                final d = _wholeNumberX(val);
                if (d == null) return const SizedBox.shrink();
                if (!labelPositions.contains(d)) return const SizedBox.shrink();
                if (d < 0 ||
                    d >=
                        (forceMonthlyAverage
                            ? sortedDates.length
                            : totalDays)) {
                  return const SizedBox.shrink();
                }
                final date = dateForX(d);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    forceMonthlyAverage
                        ? '${date.year}/${date.month.toString().padLeft(2, '0')}'
                        : '${date.month}/${date.day}',
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((spot) {
              if (rangeBarIndexes.contains(spot.barIndex)) return null;
              final date = dateForX(spot.x.round());
              final point =
                  forceMonthlyAverage ? null : aggregatePointMap[_norm(date)];
              final lines = <String>['${date.year}/${date.month}/${date.day}'];
              if (point == null) {
                lines.add(
                  '$targetEmotion：${spot.y.toStringAsFixed(1)}/$maxScale',
                );
              } else {
                lines.addAll(
                  EmotionTrendPointPresentation(point).tooltipLines(
                    label: isOverallMood ? overallMoodLabel : targetEmotion,
                    displayedValue: spot.y,
                    showsTrendValue: useMovingAverage,
                  ),
                );
              }
              return LineTooltipItem(
                lines.join('\n'),
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: barDatas,
      ),
    );

    // ===== 7️⃣ 組合圖表 + 虛線提示文字 =====
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 18, bottom: 6),
            child: chart,
          ),
        ),
        if (hasDashedSegments)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 36),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 14,
                  child: CustomPaint(
                    painter: _DashedLegendPainter(
                        color: lineColor.withValues(alpha: 0.6)),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '虛線代表當日無紀錄',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // 取得單日特定情緒數值

  double? _getValue(DailyRecord r) {
    if (targetEmotion.isEmpty || targetEmotion == overallMoodLabel) {
      return null;
    }

    try {
      final e =
          r.emotions.firstWhere((element) => element.name == targetEmotion);
      return e.value?.toDouble();
    } catch (_) {
      return null;
    }
  }

  // 計算 targetDate 往前 7 天內有幾天有可用數值
  // 計算 targetDate 往前 7 天（含當天）中，有填值的天數
  int _countDiaryFilledIn7Days(DateTime targetDate) {
    final windowStart = _norm(targetDate).subtract(const Duration(days: 6));
    int count = 0;
    diaryMoodScores.forEach((rawDate, value) {
      final date = _norm(rawDate);
      if (!date.isAfter(targetDate) && !date.isBefore(windowStart)) {
        count++;
      }
    });
    return count;
  }

  double? _calcDiaryMA7(DateTime targetDate, {int? precomputedCount}) {
    final windowStart = _norm(targetDate).subtract(const Duration(days: 6));
    double total = 0;
    int count = 0;
    diaryMoodScores.forEach((rawDate, value) {
      final date = _norm(rawDate);
      if (!date.isAfter(targetDate) && !date.isBefore(windowStart)) {
        total += value;
        count++;
      }
    });

    final effectiveCount = precomputedCount ?? count;
    if (effectiveCount == 0) return null;
    return total / effectiveCount;
  }

  int _countFilledIn7Days(DateTime targetDate) {
    final windowStart =
        DateTime(targetDate.year, targetDate.month, targetDate.day)
            .subtract(const Duration(days: 6));
    final windowRecords = fullRecords.where((r) {
      return !r.date.isAfter(targetDate) && !r.date.isBefore(windowStart);
    }).toList();

    int count = 0;
    for (var r in windowRecords) {
      if (_getValue(r) != null) {
        count++;
      }
    }
    return count;
  }

  // 計算 7 日移動平均
  double? _calcMA7(DateTime targetDate, {int? precomputedCount}) {
    final windowStart =
        DateTime(targetDate.year, targetDate.month, targetDate.day)
            .subtract(const Duration(days: 6));
    final windowRecords = fullRecords.where((r) {
      return !r.date.isAfter(targetDate) && !r.date.isBefore(windowStart);
    }).toList();
    if (windowRecords.isEmpty) return null;

    double total = 0;
    int count = 0;
    for (var r in windowRecords) {
      final v = _getValue(r);
      if (v != null) {
        total += v;
        count++;
      }
    }

    // 若外部已有算過填值天數，優先使用，避免重複邏輯差異
    final effectiveCount = precomputedCount ?? count;
    if (effectiveCount == 0) return null;
    return total / effectiveCount;
  }
}

/// 虛線圖例畫筆（用於圖表下方的圖例小線條）
class _DashedLegendPainter extends CustomPainter {
  final Color color;
  _DashedLegendPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      final end = (x + dashWidth).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLegendPainter oldDelegate) =>
      oldDelegate.color != color;
}

// 列舉與 DateFilter 定義保持不變
