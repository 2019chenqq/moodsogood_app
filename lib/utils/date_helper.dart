import 'package:flutter/material.dart';

class DateHelper {
  // 私有建構子，避免被實例化
  DateHelper._();

  /// ------------------------------------------------
  /// 日期格式化區
  /// ------------------------------------------------

  /// 轉成 Firestore Document ID 格式：yyyy-MM-dd
  /// 用途：存檔時作為 key
  static String toId(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// 轉成顯示格式：yyyy/MM/dd
  /// 用途：UI 顯示
  static String toDisplay(DateTime d) {
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  /// ------------------------------------------------
  /// 時間 (TimeOfDay) 格式化區
  /// ------------------------------------------------

  /// 轉成顯示格式：HH:mm (若為 null 則回傳 '-')
  static String formatTime(TimeOfDay? t) {
    if (t == null) return '-';
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 解析 HH:mm 字串回 TimeOfDay (若失敗回傳 null)
  static TimeOfDay? parseTime(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    final parts = s.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        return TimeOfDay(hour: h, minute: m);
      }
    }
    return null;
  }

  /// ------------------------------------------------
  /// 計算邏輯區
  /// ------------------------------------------------

  /// 計算兩個時間的分鐘差 (支援跨日)
  /// 如果 end 比 start 小，視為隔天
  static int calcDurationMinutes(TimeOfDay start, TimeOfDay end) {
    final s = start.hour * 60 + start.minute;
    final e = end.hour * 60 + end.minute;
    // 跨日邏輯：例如 23:00 (1380) 到 01:00 (60)
    // 60 < 1380 => 60 + 1440 - 1380 = 120 分鐘
    return (e >= s) ? (e - s) : (e + 24 * 60 - s);
  }

  /// 將分鐘數轉為易讀字串：X小時Y分
  static String formatDurationText(int totalMinutes) {
    if (totalMinutes <= 0) return '0分';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    
    if (h > 0 && m > 0) return '$h小時$m分';
    if (h > 0) return '$h小時';
    return '$m分';
  }
}