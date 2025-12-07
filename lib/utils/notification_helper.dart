import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

const _channelId = 'heartshine_general';
const _channelName = '心晴提醒';
const _channelDescription = '心晴的提醒與每日通知';

class NotificationHelper {
  static final NotificationHelper _instance = NotificationHelper._internal();
  factory NotificationHelper() => _instance;
  NotificationHelper._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  FlutterLocalNotificationsPlugin get notificationsPlugin =>
      _notificationsPlugin;

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    // 1. 時區（固定用台北）
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Taipei'));
    debugPrint('🕐 時區初始化完成：${tz.local.name}');

    // 2. 初始化通知
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notificationsPlugin.initialize(settings);

    _isInitialized = true;
  }

  /// 立刻跳出測試通知
  Future<void> showTestNotification() async {
    await init();

    await _notificationsPlugin.show(
      999,
      '測試通知',
      '如果你看到這個，代表通知系統是好的 👍',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// 每日固定時間提醒
  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    await init();
    debugPrint('🔔 準備建立每日通知…');

    // 要求通知權限（Android 13+）
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
      debugPrint('📅 設定時間已過，改排明天：$scheduledDate');
    } else {
      debugPrint('📅 排在今天：$scheduledDate');
    }

    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,          // ✅ 跟測試通知同一個頻道
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // ✅ 用 inexact 模式，不再要求「精準鬧鐘」權限
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('✅ 已成功建立每日排程：$scheduledDate');

      final pending =
          await _notificationsPlugin.pendingNotificationRequests();
      debugPrint('📌 目前排隊中的通知數量：${pending.length}');
      for (final p in pending) {
        debugPrint('  ▶ id=${p.id}, title=${p.title}, body=${p.body}');
      }
    } catch (e, st) {
      debugPrint('❌ 建立每日通知失敗：$e');
      debugPrint('$st');
    }
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }
}
