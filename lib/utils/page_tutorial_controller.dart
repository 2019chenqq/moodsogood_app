import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/interactive_tutorial.dart';

/// 頁面導覽控制器
class PageTutorialController {
  static const String _keyDailyRecordPageTutorial = 'seen_daily_record_page_tutorial';
  static const String _keyDiaryPageTutorial = 'seen_diary_page_tutorial';
  static const String _keyStatisticsPageTutorial = 'seen_statistics_page_tutorial';

  /// 檢查是否需要顯示每日紀錄頁面導覽
  static Future<bool> shouldShowDailyRecordPageTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_keyDailyRecordPageTutorial) ?? false);
  }

  /// 檢查是否需要顯示日記頁面導覽
  static Future<bool> shouldShowDiaryPageTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_keyDiaryPageTutorial) ?? false);
  }

  /// 檢查是否需要顯示統計頁面導覽
  static Future<bool> shouldShowStatisticsPageTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_keyStatisticsPageTutorial) ?? false);
  }

  /// 標記已看過每日紀錄頁面導覽
  static Future<void> markDailyRecordPageTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDailyRecordPageTutorial, true);
  }

  /// 標記已看過日記頁面導覽
  static Future<void> markDiaryPageTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDiaryPageTutorial, true);
  }

  /// 標記已看過統計頁面導覽
  static Future<void> markStatisticsPageTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStatisticsPageTutorial, true);
  }

  /// 重置所有頁面導覽
  static Future<void> resetAllPageTutorials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDailyRecordPageTutorial);
    await prefs.remove(_keyDiaryPageTutorial);
    await prefs.remove(_keyStatisticsPageTutorial);
  }

  /// 在頁面上顯示導覽覆蓋層
  static Future<void> showPageTutorial(
    BuildContext context,
    List<TutorialStep> steps,
  ) async {
    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => InteractivePageTutorial(
        steps: steps,
        onComplete: () {
          // 完成時的回調
        },
      ),
    );
  }
}
