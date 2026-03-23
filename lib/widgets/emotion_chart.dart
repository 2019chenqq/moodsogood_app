// lib/widgets/emotion_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/daily_record.dart';
import '../models/period_cycle.dart';

class EmotionChart extends StatelessWidget {
  final List<DailyRecord> records;
  final List<PeriodCycle> periods;

  const EmotionChart({
    super.key, 
    required this.records,
    this.periods = const [], // 預設為空
  });
  
  @override
  Widget build(BuildContext context) {
    // 1. 資料轉換：DailyRecord -> FlSpot
    // 我們需要把資料「倒過來」排序 (舊 -> 新)，這樣折線圖才會從左畫到右
    final sortedRecords = List<DailyRecord>.from(records)
      ..sort((a, b) => a.date.compareTo(b.date));

    // 過濾出有分數的資料
    final validData = sortedRecords
        .where((r) => r.overallMood != null)
        .toList();

    // 如果資料太少，顯示提示文字
    if (validData.length < 2) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('累積 2 筆以上情緒紀錄後，\n這裡就會出現趨勢圖喔！', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
      );
    }

    // 產生座標點 (X: 索引, Y: 分數)
    final spots = validData.asMap().entries.map((e) {
      final index = e.key;
      final record = e.value;
      return FlSpot(index.toDouble(), record.overallMood!);
    }).toList();
// 🔥【第一部分：計算邏輯貼在這裡】🔥
    // (放在 validData 定義之後，return Container 之前)
    final periodRanges = <VerticalRangeAnnotation>[];

    for (int i = 0; i < validData.length; i++) {
      final recordDate = validData[i].date;
      
      // 檢查這一天是否在任何一個 PeriodCycle 內
      final isPeriodDay = periods.any((p) => p.containsDate(recordDate));

      if (isPeriodDay) {
        periodRanges.add(
          VerticalRangeAnnotation(
            x1: i - 0.5,
            x2: i + 0.5,
            color: const Color(0xFFFFE0E6), // 淡淡的粉紅色背景
          ),
        );
      }
    }
    return Container(
      height: 180, // 圖表高度
      padding: const EdgeInsets.only(right: 24, left: 12, top: 24, bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: LineChart(
        LineChartData(
          // 🔥【第二部分：設定參數貼在這裡】🔥
          // (放在 LineChartData 的開頭)
          rangeAnnotations: RangeAnnotations(
            verticalRangeAnnotations: periodRanges,
          ),
          // 2. 設定座標範圍 (0-10分)
          minY: 0,
          maxY: 10,
          minX: 0,
          maxX: (validData.length - 1).toDouble(),
          
          // 3. 格線設定
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false, // 不畫垂直線，比較清爽
            horizontalInterval: 2,   // 每 2 分畫一條水平線
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withValues(alpha: 0.2), strokeWidth: 1),
          ),

          // 4. 邊框設定 (不顯示邊框)
          borderData: FlBorderData(show: false),

          // 5. 座標軸標籤設定
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // 右邊不顯示
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),   // 上面不顯示
            
            // 左邊 (Y軸) 標籤
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 2,
                getTitlesWidget: (value, meta) {
                  return Text(value.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 12));
                },
                reservedSize: 30,
              ),
            ),

            // 下面 (X軸) 日期標籤
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1, // 每個點都嘗試標記 (可以用邏輯控制間隔)
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= validData.length) return const SizedBox.shrink();
                  
                  // 為了避免標籤擠在一起，我們只顯示頭、尾、跟中間
                  // 或者簡單一點：如果資料少於 7 筆全顯示，多於 7 筆顯示間隔
                  if (validData.length > 7 && index % 2 != 0) {
                     return const SizedBox.shrink();
                  }

                  final date = validData[index].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      '${date.month}/${date.day}', 
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),

          // 6. 線條樣式設定
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true, // 圓滑曲線
              color: Colors.teal, // 線條顏色 (可依你的主題色調整)
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true), // 顯示數據點
              belowBarData: BarAreaData(
                show: true,
                color: Colors.teal.withValues(alpha: 0.1), // 線下方的填充顏色
              ),
            ),
          ],
        ),
      ),
    );
  }
}