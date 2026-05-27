import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

class HomeWidgetSyncService {
  static const String qualifiedAndroidWidgetName =
      'tw.heartsshine.app.MoodWidgetProvider';

  static const String moodTextKey = 'mood_widget_mood_text';
  static const String subtitleKey = 'mood_widget_subtitle';
  static const String updatedAtKey = 'mood_widget_updated_at';

  static Future<void> updateDailyRecord({
    required int streakDays,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final moodText = '連續記錄 $streakDays 天';
    final subtitle = streakDays > 0 ? '今天已完成紀錄' : '今天尚未紀錄';

    try {
      await HomeWidget.saveWidgetData<String>(moodTextKey, moodText);
      await HomeWidget.saveWidgetData<String>(subtitleKey, subtitle);
      await HomeWidget.saveWidgetData<String>(
        updatedAtKey,
        DateFormat('MM/dd HH:mm').format(DateTime.now()),
      );
      await HomeWidget.updateWidget(
        qualifiedAndroidName: qualifiedAndroidWidgetName,
      );
    } catch (error, stackTrace) {
      debugPrint('Home widget sync failed: $error');
      debugPrint('$stackTrace');
    }
  }
}
