import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../navigation_service.dart';

import '../app_globals.dart';
import '../daily/daily_record_screen.dart';

const _channelId = 'heartshine_general';
const _channelName = '心晴提醒';
const _channelDescription = '心晴的提醒與每日通知';
const _dailyRecordPayload = 'open_daily_record';

class NotificationHelper {
  static final NotificationHelper _instance = NotificationHelper._internal();
  factory NotificationHelper() => _instance;
  NotificationHelper._internal();

  static const int kDailyAlarmId = 10001;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  FlutterLocalNotificationsPlugin get notificationsPlugin => _notificationsPlugin;

  String? _pendingPayload;

  bool _isInitialized = false;
  bool _exactAlarmAllowed = false;

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

    // timezone 初始化并设置为台北时区
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Taipei'));
    debugPrint('🕐 时区初始化完成：${tz.local.name}');

    // 使用 android 資源名稱 app_icon（請把 assets/icons/app_icon 放到
    // android/app/src/main/res/mipmap-*/ 或 drawable-* 內，名稱為 app_icon）
    const androidSettings = AndroidInitializationSettings('app_icon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      settings,
<<<<<<< HEAD
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            rootNavigatorKey.currentState?.pushNamed(payload);
          } catch (e) {
            debugPrint('🔔 通知點擊導向失敗: $e');
          }
        }
      },
    );
    // 監聽 native 的 WorkManager 點擊事件（onNewIntent 會 invokeMethod("notificationTapped"))
    platform.setMethodCallHandler((call) async {
      if (call.method == 'notificationTapped') {
        final payload = call.arguments as String?;
        if (payload != null && payload.isNotEmpty) {
          try {
            rootNavigatorKey.currentState?.pushNamed(payload);
          } catch (e) {
            debugPrint('🔔 native tapped handler failed: $e');
          }
        }
      }
    });
=======
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final launchDetails =
        await _notificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _pendingPayload = launchDetails?.notificationResponse?.payload;
    }
>>>>>>> 2f952edecc12017aa70b664fa48b808a054ea039
    _isInitialized = true;
  }

  /// 如果 App 是由點擊通知啟動，可以在啟動時呼叫這個方法讀出 payload
  Future<String?> getInitialNotificationPayload() async {
    final details = await _notificationsPlugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      return details?.notificationResponse?.payload;
    }
    // 如果不是透過 flutter_local_notifications 啟動（例如 WorkManager 原生通知），
    // 試著向 native MainActivity 查詢 intent extra。
    try {
      final payload = await platform.invokeMethod<String?>('getInitialPayload');
      return payload;
    } catch (_) {
      return null;
    }
  }

  /// =========================
  /// 只負責「顯示通知」
  /// =========================
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();

    // Android 13+ 通知權限（你原本有 requestNotificationsPermission，保留）
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      icon: 'app_icon',
      enableVibration: true,
      enableLights: true,
      playSound: true,
    );

    await _notificationsPlugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      ),
<<<<<<< HEAD
      payload: payload ?? '/home',
=======
      payload: _dailyRecordPayload,
>>>>>>> 2f952edecc12017aa70b664fa48b808a054ea039
    );
  }

  /// =========================
  /// 確保通知權限
  /// =========================
  Future<bool> _ensurePermissions() async {
    final android = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    
    if (android != null) {
      final enabled = await android.areNotificationsEnabled() ?? false;
      if (!enabled) {
        return await android.requestNotificationsPermission() ?? false;
      }
      return enabled;
    }
    
    final iOS = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    
    if (iOS != null) {
      return await iOS.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      ) ?? false;
    }
    
    return true;
  }

  /// =========================
  /// 每日定時通知
  /// =========================
  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    String? payload,
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
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId, // ✅ 跟測試通知同一個頻道
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.high,
            enableVibration: true,
            enableLights: true,
            playSound: true,
            setAsGroupSummary: false,
            fullScreenIntent: true,
            icon: 'app_icon',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        payload: payload ?? '/home',
        androidScheduleMode: _exactAlarmAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: _dailyRecordPayload,
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

<<<<<<< HEAD
  /// 测试：5秒后跳出通知
  Future<void> scheduleTestNotificationIn5Seconds({String? payload}) async {
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
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      debugPrint('✅ 已排程5秒後的測試通知');
    } catch (e, st) {
      debugPrint('❌ 測試通知排程失敗：$e');
      debugPrint('$st');
    }
  }

=======
>>>>>>> 2f952edecc12017aa70b664fa48b808a054ea039
  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  Future<void> requestExactAlarmPermission() async {
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestExactAlarmsPermission();
  }

  void handleBackgroundNotificationResponse(
      NotificationResponse notificationResponse) {
    _handleNotificationResponse(notificationResponse);
  }

  void _handleNotificationResponse(NotificationResponse? response) {
    final payload = response?.payload;
    if (payload == null) return;

    final handled = _handlePayload(payload);
    if (!handled) {
      _pendingPayload = payload;
    }
  }

  bool _handlePayload(String payload) {
    if (payload == _dailyRecordPayload) {
      return _navigateToDailyRecord();
    }
    return false;
  }

  bool _navigateToDailyRecord() {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return false;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DailyRecordScreen()),
      (_) => false,
    );
    return true;
  }

  /// 在 app 完成 build 後呼叫，確保若是從通知啟動也能導向首頁
  void processPendingNavigation() {
    final payload = _pendingPayload;
    if (payload == null) return;

    if (_handlePayload(payload)) {
      _pendingPayload = null;
    }
  }

  // ========== WorkManager 方法（用於小米等嚴格系統） ==========
  static const platform = MethodChannel('tw.heartsshine.app/workmanager');

  /// 使用 WorkManager 設定每日提醒（適用於小米手機）
  Future<bool> scheduleDailyNotificationWithWorkManager({
    required TimeOfDay time,
    String? payload,
  }) async {
    try {
      final result = await platform.invokeMethod('scheduleDailyNotification', {
        'hour': time.hour,
        'minute': time.minute,
        'payload': payload ?? '/daily',
      });
      debugPrint('✅ WorkManager 每日提醒已設定：${time.hour}:${time.minute}');
      return result == true;
    } catch (e) {
      debugPrint('❌ WorkManager 設定失敗：$e');
      return false;
    }
  }

  /// 取消 WorkManager 的每日提醒
  Future<bool> cancelDailyNotificationWithWorkManager() async {
    try {
      final result = await platform.invokeMethod('cancelDailyNotification');
      debugPrint('✅ WorkManager 每日提醒已取消');
      return result == true;
    } catch (e) {
      debugPrint('❌ WorkManager 取消失敗：$e');
      return false;
    }
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(
    NotificationResponse notificationResponse) {
  NotificationHelper()
      .handleBackgroundNotificationResponse(notificationResponse);
}
