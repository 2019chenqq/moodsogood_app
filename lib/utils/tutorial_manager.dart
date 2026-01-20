import 'package:shared_preferences/shared_preferences.dart';

/// 教學狀態管理器
class TutorialManager {
  static const String _keyDailyRecordTutorial = 'seen_daily_record_tutorial';
  static const String _keyDiaryTutorial = 'seen_diary_tutorial';
  static const String _keyStatisticsTutorial = 'seen_statistics_tutorial';
  static const String _keyOnboarding = 'has_seen_onboarding';

  /// 檢查是否已看過每日紀錄教學
  static Future<bool> hasSeenDailyRecordTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDailyRecordTutorial) ?? false;
  }

  /// 檢查是否已看過日記教學
  static Future<bool> hasSeenDiaryTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDiaryTutorial) ?? false;
  }

  /// 檢查是否已看過統計教學
  static Future<bool> hasSeenStatisticsTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyStatisticsTutorial) ?? false;
  }

  /// 檢查是否已看過初次使用導覽
  static Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboarding) ?? false;
  }

  /// 標記已看過每日紀錄教學
  static Future<void> markDailyRecordTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDailyRecordTutorial, true);
  }

  /// 標記已看過日記教學
  static Future<void> markDiaryTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDiaryTutorial, true);
  }

  /// 標記已看過統計教學
  static Future<void> markStatisticsTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStatisticsTutorial, true);
  }

  /// 標記已看過初次使用導覽
  static Future<void> markOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboarding, true);
  }

  /// 重置所有教學（用於測試）
  static Future<void> resetAllTutorials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDailyRecordTutorial);
    await prefs.remove(_keyDiaryTutorial);
    await prefs.remove(_keyStatisticsTutorial);
    await prefs.remove(_keyOnboarding);
  }
}
