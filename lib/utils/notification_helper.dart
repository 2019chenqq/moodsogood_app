import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/scheduler.dart' as fl_scheduler;

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
  final String _prefsKey = 'scheduled_notifications_v1';
  WidgetsBindingObserver? _lifecycleObserver;

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

    // Register lifecycle observer to reschedule on app resume (handles manual time changes)
    _registerLifecycleObserver();

    _isInitialized = true;
  }

  void _registerLifecycleObserver() {
    if (_lifecycleObserver != null) return;
    _lifecycleObserver = _LifecycleHandler(this);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
  }

  /// Reschedule saved notifications (used when app resumes or time changed)
  Future<void> rescheduleAllSavedNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? <String>[];
    if (list.isEmpty) return;

    // Parse and reschedule (do not persist again)
    for (final s in list) {
      try {
        final m = json.decode(s) as Map<String, dynamic>;
        final id = m['id'] as int;
        final title = m['title'] as String;
        final body = m['body'] as String;
        final hour = m['hour'] as int;
        final minute = m['minute'] as int;

        await scheduleDailyNotification(
          id: id,
          title: title,
          body: body,
          time: TimeOfDay(hour: hour, minute: minute),
          persist: false,
        );
      } catch (e) {
        debugPrint('❌ 讀取或重排通知失敗：$e');
      }
    }
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
    bool persist = true,
  }) async {
    await init();
    final hasPermission = await _ensurePermissions();
    if (!hasPermission) return;
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
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: _exactAlarmAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
              );
      debugPrint('✅ 已成功建立每日排程：$scheduledDate');

              // Persist scheduled notification so we can reschedule on app resume/time change
              if (persist) {
                try {
                  final prefs = await SharedPreferences.getInstance();
                  final list = prefs.getStringList(_prefsKey) ?? <String>[];
                  final entry = json.encode({
                    'id': id,
                    'title': title,
                    'body': body,
                    'hour': time.hour,
                    'minute': time.minute,
                  });

                  // replace if exists
                  final idx = list.indexWhere((e) {
                    try {
                      final m = json.decode(e) as Map<String, dynamic>;
                      return (m['id'] as int) == id;
                    } catch (_) {
                      return false;
                    }
                  });
                  if (idx >= 0) {
                    list[idx] = entry;
                  } else {
                    list.add(entry);
                  }
                  await prefs.setStringList(_prefsKey, list);
                } catch (e) {
                  debugPrint('❌ 儲存排程資訊失敗：$e');
                }
              }

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
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsKey) ?? <String>[];
      list.removeWhere((e) {
        try {
          final m = json.decode(e) as Map<String, dynamic>;
          return (m['id'] as int) == id;
        } catch (_) {
          return false;
        }
      });
      await prefs.setStringList(_prefsKey, list);
    } catch (e) {
      debugPrint('❌ 刪除儲存排程失敗：$e');
    }
  }
}

class _LifecycleHandler extends WidgetsBindingObserver {
  final NotificationHelper _helper;
  _LifecycleHandler(this._helper);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // When app resumes, reschedule saved notifications to handle manual time changes
      fl_scheduler.SchedulerBinding.instance.addPostFrameCallback((_) {
        _helper.rescheduleAllSavedNotifications();
      });
    }
  }
}
