import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/daily_record.dart';

class HistoryChartWidget extends StatelessWidget {
  final List<DailyRecord> records;
  final List<DailyRecord> fullRecords;
  final String targetEmotion;
  final bool useMovingAverage;
  final bool forceMonthlyAverage; // 新增
  final Map<DateTime, double> diaryMoodScores;
  final String overallMoodLabel;

  const HistoryChartWidget({
    super.key,
    required this.records,
    required this.fullRecords,
    required this.targetEmotion,
    required this.useMovingAverage,
    this.forceMonthlyAverage = false, // 新增
    this.diaryMoodScores = const <DateTime, double>{},
    this.overallMoodLabel = '整體情緒',
  });

  /// 正規化日期（去除時間部分）
  DateTime _norm(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 建立經期粉紅區塊（依照日期距離 startDate 的天數作為 x 座標，並限制在 minX/maxX 內）
  List<VerticalRangeAnnotation> _buildPeriodRanges(
      List<DailyRecord> sorted, DateTime startDate,
      {int minX = 0, int? maxX}) {
    final List<VerticalRangeAnnotation> list = [];
    int? periodStartDay;

    for (var r in sorted) {
      final dayD = _norm(r.date).difference(startDate).inDays;
      if (r.isPeriod) {
        periodStartDay ??= dayD;
      } else if (periodStartDay != null) {
        double x1 = periodStartDay.toDouble() - 0.5;
        double x2 = (dayD - 1).toDouble() + 0.5;
        // 限制區塊在 minX/maxX 內
        if (maxX != null) {
          x1 = x1.clamp(minX.toDouble(), maxX.toDouble());
          x2 = x2.clamp(minX.toDouble(), maxX.toDouble());
        }
        if (x2 >= x1) {
          list.add(VerticalRangeAnnotation(
            x1: x1,
            x2: x2,
            color: Colors.pink.withValues(alpha: 0.15),
          ));
        }
        periodStartDay = null;
      }
    }
    // 若最後一筆仍為經期
    if (periodStartDay != null && sorted.isNotEmpty) {
      final lastDay = _norm(sorted.last.date).difference(startDate).inDays;
      double x1 = periodStartDay.toDouble() - 0.5;
      double x2 = lastDay.toDouble() + 0.5;
      if (maxX != null) {
        x1 = x1.clamp(minX.toDouble(), maxX.toDouble());
        x2 = x2.clamp(minX.toDouble(), maxX.toDouble());
      }
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
    if (records.isEmpty && (!isOverallMood || diaryMoodScores.isEmpty)) {
      return const Center(child: Text('鞈?銝雲嚗瘜＊蝷箄隅?Ｗ?'));
    }

    // ===== 1儭 ?渡?鞈?嚗??交???嚗遣蝡?????詨潦??扯” =====
    final sorted = List<DailyRecord>.from(records)
      ..sort((a, b) => a.date.compareTo(b.date));

    final Map<DateTime, double> dateValueMap = {};
    final Map<DateTime, double> emptyPointValueMap = {};
    if (isOverallMood) {
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
    final showLine = recordedCount >= 3;

    // ===== 3️⃣ 建立 LineChartBarData =====
    final List<LineChartBarData> barDatas = [];
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
      for (int d = 0; d < totalDays; d++) {
        final date = startDate.add(Duration(days: d));
        final v = effectiveValueMap[_norm(date)];
        solidSpots.add(v != null ? FlSpot(d.toDouble(), v) : FlSpot.nullSpot);
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

    // ===== 4️⃣ 經期粉紅區塊 =====
    final periodRanges = _buildPeriodRanges(
      sorted,
      startDate,
      minX: 0,
      maxX: totalDays > 0 ? totalDays - 1 : 0,
    );

    // ===== 5️⃣ X 軸標籤：只在有紀錄的位置顯示，最多 7 個 =====
    final labelPositions = <int>{};
    if (sortedDates.isNotEmpty) {
      final step =
          ((sortedDates.length - 1) / 6).ceil().clamp(1, sortedDates.length);
      for (int i = 0; i < sortedDates.length; i += step) {
        labelPositions.add(dayIdx(sortedDates[i]));
      }
      labelPositions.add(dayIdx(sortedDates.last));
    }

    // ===== 6️⃣ 繪製折線圖 =====
    final chart = LineChart(
      LineChartData(
        minY: 0,
        maxY: 10,
        minX: 0,
        maxX: (totalDays - 1).toDouble(),
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
              reservedSize: 30,
              getTitlesWidget: (v, m) => Text(v.toInt().toString()),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (val, meta) {
                final d = val.toInt();
                if (!labelPositions.contains(d)) return const SizedBox.shrink();
                final date = startDate.add(Duration(days: d));
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
        lineBarsData: barDatas,
      ),
    );

    // ===== 7️⃣ 組合圖表 + 虛線提示文字 =====
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: chart),
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
