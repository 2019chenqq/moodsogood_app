import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTutorialService {
  static const String hasSeenDailyRecordTutorial = 'hasSeenDailyRecordTutorial';

  const AppTutorialService._();

  static Future<bool> shouldShowDailyRecordTutorial() async {
    if (!kReleaseMode) return true;

    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(hasSeenDailyRecordTutorial) ?? false);
  }

  static Future<void> markDailyRecordTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(hasSeenDailyRecordTutorial, true);
  }

  static Future<void> resetDailyRecordTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(hasSeenDailyRecordTutorial);
  }
}
