import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _channelId = 'heartshine_general';
const _channelName = '心晴提醒';
const _channelDescription = '心晴的提醒與每日通知';

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
    final hasPermission = await _ensurePermissions();
    if (!hasPermission) {
      debugPrint('❌ 沒有通知權限，無法建立排程');
      return;
    }
    debugPrint('🔔 準備建立每日通知…');

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // 要求精準鬧鐘權限
    final android = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      _exactAlarmAllowed = await android.requestExactAlarmsPermission() ?? false;
      debugPrint('🔔 精準鬧鐘權限: $_exactAlarmAllowed');
    }

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
            enableVibration: true,
            enableLights: true,
            playSound: true,
            setAsGroupSummary: false,
            fullScreenIntent: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        androidScheduleMode: _exactAlarmAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
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

  /// 测试：5秒后跳出通知
  Future<void> scheduleTestNotificationIn5Seconds() async {
    await init();
    final hasPermission = await _ensurePermissions();
    if (!hasPermission) {
      debugPrint('❌ 沒有通知權限');
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    final scheduledDate = now.add(const Duration(seconds: 5));

    debugPrint('🧪 測試：5秒後跳出通知');
    debugPrint('📅 現在時間：$now');
    debugPrint('📅 排程時間：$scheduledDate');

    try {
      await _notificationsPlugin.zonedSchedule(
        2,
        '測試定時通知 🧪',
        '如果你看到這個，代表定時通知系統正常運作',
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.high,
            enableVibration: true,
            enableLights: true,
            playSound: true,
            fullScreenIntent: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      debugPrint('✅ 已排程5秒後的測試通知');
    } catch (e, st) {
      debugPrint('❌ 測試通知排程失敗：$e');
      debugPrint('$st');
    }
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
