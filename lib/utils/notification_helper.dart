import 'dart:io' show Platform;
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationHelper {
  static final NotificationHelper _instance = NotificationHelper._internal();
  factory NotificationHelper() => _instance;
  NotificationHelper._internal();

  static const int kDailyAlarmId = 10001;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  FlutterLocalNotificationsPlugin get notificationsPlugin => _notificationsPlugin;

  bool _isInitialized = false;

  /// 你可以固定用同一個 channel id
  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'daily_reminder_channel',
    '每日提醒',
    channelDescription: '提醒您紀錄日記與心情',
    importance: Importance.max,
    priority: Priority.high,
  );

  Future<void> init() async {
    if (_isInitialized) return;

    // timezone 初始化（你原本只有 initializeTimeZones，建議補 local）
    tz.initializeTimeZones();
    // 若你之前有做 Asia/Taipei 的 setLocalLocation，可以在這裡補回來
    // tz.setLocalLocation(tz.getLocation('Asia/Taipei'));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(settings);
    _isInitialized = true;
  }

  /// =========================
  /// 只負責「顯示通知」
  /// =========================
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();

    // Android 13+ 通知權限（你原本有 requestNotificationsPermission，保留）
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _notificationsPlugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: _androidDetails,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// =========================
  /// iOS（或非 Android）仍用你原本的 zonedSchedule
  /// =========================
  Future<void> scheduleDailyNotificationIOSLike({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    await init();

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      const NotificationDetails(
        android: _androidDetails,
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// =========================
  /// Android：用「鬧鐘」排每日提醒（準時）
  /// =========================
  Future<void> enableDailyAlarmAndroid({
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    await init();

    if (kIsWeb) {
      // Web 不支援鬧鐘
      return;
    }
    if (!Platform.isAndroid) {
      // 非 Android 走原本方式
      await scheduleDailyNotificationIOSLike(
        id: kDailyAlarmId,
        title: title,
        body: body,
        time: time,
      );
      return;
    }

    // 1) 先取消舊的，避免重複
    await AndroidAlarmManager.cancel(kDailyAlarmId);

    // 2) 排「下一次」的 oneShotAt（到點後 callback 會再排下一天）
    final next = _nextOccurrence(time);
    await AndroidAlarmManager.oneShotAt(
      next,
      kDailyAlarmId,
      _dailyAlarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );

    // 3) 建議同時請求 Android exact alarm 權限（你原本有這個函式）
    await requestExactAlarmPermission();
  }

  Future<void> disableDailyAlarm() async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      await AndroidAlarmManager.cancel(kDailyAlarmId);
    }
    await _notificationsPlugin.cancel(kDailyAlarmId);
  }

  static DateTime _nextOccurrence(TimeOfDay time) {
    final now = DateTime.now();
    var candidate = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  /// 鬧鐘觸發：顯示通知 + 排下一天
  @pragma('vm:entry-point')
  static Future<void> _dailyAlarmCallback() async {
    final helper = NotificationHelper();
    await helper.showNow(
      id: kDailyAlarmId,
      title: '心晴提醒',
      body: '記得寫下今天的一點點感受就好。',
    );

    // 排下一天同一時間（這裡要讀你實際儲存的時間）
    // 如果你有用 SharedPreferences 存 time，應在這裡讀出來。
    // 先用固定 21:00 做示範：
    const time = TimeOfDay(hour: 21, minute: 0);
    final next = _nextOccurrence(time);

    await AndroidAlarmManager.oneShotAt(
      next,
      kDailyAlarmId,
      _dailyAlarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  Future<void> requestExactAlarmPermission() async {
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestExactAlarmsPermission();
  }
}
