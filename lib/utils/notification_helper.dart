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

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  FlutterLocalNotificationsPlugin get notificationsPlugin =>
      _notificationsPlugin;

  bool _isInitialized = false;
  bool _exactAlarmAllowed = false; // 記錄是否拿到「精準鬧鐘」權限

  Future<bool> _ensurePermissions() async {
    var granted = true;

    // Android：確認並要求通知與精準鬧鐘權限（13+ 需要 POST_NOTIFICATIONS，12+ 需要精準鬧鐘）
    final android = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final enabled = await android.areNotificationsEnabled() ?? false;
      if (!enabled) {
        granted = await android.requestNotificationsPermission() ?? false;
      }

      // 精準鬧鐘權限（有拿到就用 exact 模式，沒有就退回 inexact）
      _exactAlarmAllowed = await android.requestExactAlarmsPermission() ?? false;
      debugPrint('🔔 Android permission: notif=$granted exact=$_exactAlarmAllowed');
    }

    // iOS：主動要權限，否則在前景時不會跳通知
    final ios = _notificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final iosGranted = await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      granted = granted && iosGranted;
      debugPrint('🍎 iOS permission: notif=$iosGranted');
    }

    if (!granted) {
      debugPrint('⚠️ 使用者尚未允許通知，已略過');
    }

    return granted;
  }

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
    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('🔔 notification tapped, payload=${response.payload}');
      },
    );

    // Create Android notification channel to ensure channel exists (Android 8+)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Request runtime notification permission on Android 13+
    await _notificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

    await _ensurePermissions();

    _isInitialized = true;
  }

  /// 立刻跳出測試通知
  Future<void> showTestNotification() async {
    await init();
    if (!await _ensurePermissions()) return;

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
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
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
    final hasPermission = await _ensurePermissions();
    if (!hasPermission) {
      debugPrint('❌ 沒有通知權限，無法建立排程');
      return;
    }
    debugPrint('🔔 準備建立每日通知…');

    // 要求通知權限（Android 13+）
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
}
