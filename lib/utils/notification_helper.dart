import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../app_globals.dart';
import '../pages/hub_pages.dart';
import '../meds/medication_checkin_page.dart';
import '../meds/medication_local_db.dart';
import '../meds/medication_subjective_reminder_payload.dart';
import '../meds/medication_subjective_response_page.dart';
import '../meds/medication_subjective_tracking_cycle.dart';

const _channelId = 'heartshine_general';
const _channelName = '心域提醒';
const _channelDescription = '心域的提醒與每日通知';
const _dailyRecordPayload = 'open_daily_record';
const _medicationCheckinPayload = 'open_medication_checkin';

class NotificationHelper {
  static final NotificationHelper _instance = NotificationHelper._internal();
  factory NotificationHelper() => _instance;
  NotificationHelper._internal();

  static const int kDailyAlarmId = 10001;
  static const String medicationCheckinPayload = _medicationCheckinPayload;
  static const String followUpSummaryPayload = 'open_follow_up_summary';

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  FlutterLocalNotificationsPlugin get notificationsPlugin =>
      _notificationsPlugin;

  String? _pendingPayload;

  bool _isInitialized = false;
  bool _exactAlarmAllowed = false;
  bool _exactAlarmPermissionChecked = false;
  bool _healthDataNavigationReady = false;

  void setHealthDataNavigationReady(bool ready) {
    _healthDataNavigationReady = ready;
    if (ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        processPendingNavigation();
      });
    }
  }

  /// 你可以固定用同一個 channel id

  Future<void> init() async {
    if (_isInitialized) return;

    // timezone 初始化并设置为台北时区
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Taipei'));
    debugPrint('🕐 时区初始化完成：${tz.local.name}');

    // 使用現成的啟動 icon，避免缺少自訂資源導致 invalid_icon 錯誤
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
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    // 監聽 native 的 WorkManager 點擊事件（onNewIntent 會 invokeMethod("notificationTapped"))
    platform.setMethodCallHandler((call) async {
      if (call.method == 'notificationTapped') {
        final payload = call.arguments as String?;
        if (payload != null && payload.isNotEmpty) {
          _pendingPayload = payload;
          _handlePayload(payload);
        }
      }
    });

    final launchDetails =
        await _notificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _pendingPayload = launchDetails?.notificationResponse?.payload;
    }
    _isInitialized = true;
  }

  /// 如果 App 是由點擊通知啟動，可以在啟動時呼叫這個方法讀出 payload
  Future<String?> getInitialNotificationPayload() async {
    final details =
        await _notificationsPlugin.getNotificationAppLaunchDetails();
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
      icon: '@mipmap/ic_launcher',
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
      payload: payload ?? _dailyRecordPayload,
    );
  }

  /// =========================
  /// 確保通知權限
  /// =========================
  Future<bool> _ensurePermissions() async {
    final android = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (android != null) {
      final enabled = await android.areNotificationsEnabled() ?? false;
      debugPrint('🔔 [確保權限] Android 通知狀態: $enabled');

      if (!enabled) {
        debugPrint('🔔 [確保權限] 請求 Android 通知權限...');
        final result = await android.requestNotificationsPermission() ?? false;
        debugPrint('🔔 [確保權限] Android 權限請求結果: $result');

        // 等待系統處理
        await Future.delayed(const Duration(milliseconds: 500));

        // 再檢查一次
        final recheckEnabled = await android.areNotificationsEnabled() ?? false;
        debugPrint('🔔 [確保權限] Android 重新檢查結果: $recheckEnabled');
        return recheckEnabled;
      }
      return enabled;
    }

    final iOS = _notificationsPlugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    if (iOS != null) {
      debugPrint('🔔 [確保權限] 請求 iOS 通知權限...');
      final result = await iOS.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      debugPrint('🔔 [確保權限] iOS 權限請求結果: $result');
      return result;
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
    final android = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      _exactAlarmPermissionChecked = true;
      _exactAlarmAllowed =
          await android.requestExactAlarmsPermission() ?? false;
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
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        androidScheduleMode: _exactAlarmAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload ?? _dailyRecordPayload,
      );
      debugPrint('✅ 已成功建立每日排程：$scheduledDate');

      final pending = await _notificationsPlugin.pendingNotificationRequests();
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

  Future<void> cancelNotification(int id) async {
    await init();
    await _notificationsPlugin.cancel(id);
  }

  /// 排程一筆「單次」通知（例如回診前提醒），回傳是否排程成功。
  Future<bool> scheduleOneTimeNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    String? payload,
  }) async {
    try {
      await init();
      final hasPermission = await _ensurePermissions();
      if (!hasPermission) return false;
      final android = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null && !_exactAlarmPermissionChecked) {
        _exactAlarmPermissionChecked = true;
        _exactAlarmAllowed =
            await android.requestExactAlarmsPermission() ?? false;
      }
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledAt, tz.local),
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
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: _exactAlarmAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
      debugPrint('✅ 單次通知已排程（id=$id）：$title');
      return true;
    } catch (e) {
      debugPrint('❌ 單次通知排程失敗：$e');
      return false;
    }
  }

  Future<void> requestExactAlarmPermission() async {
    final androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    _exactAlarmPermissionChecked = true;
    _exactAlarmAllowed =
        await androidImplementation?.requestExactAlarmsPermission() ?? false;
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
    if (payload == _medicationCheckinPayload) {
      return _navigateToMedicationCheckin();
    }
    final subjectivePayload =
        MedicationSubjectiveReminderPayload.tryDecode(payload);
    if (subjectivePayload != null) {
      return _navigateToMedicationSubjectiveResponse(subjectivePayload);
    }
    return false;
  }

  bool _navigateToMedicationSubjectiveResponse(
    MedicationSubjectiveReminderPayload payload,
  ) {
    if (!_healthDataNavigationReady ||
        FirebaseAuth.instance.currentUser == null) {
      return false;
    }
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return false;
    _openMedicationSubjectiveResponse(navigator, payload);
    return true;
  }

  Future<void> _openMedicationSubjectiveResponse(
    NavigatorState navigator,
    MedicationSubjectiveReminderPayload payload,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _pendingPayload = payload.encode();
      return;
    }
    try {
      final cycle = await MedicationLocalDB().getSubjectiveTrackingCycle(
        uid,
        payload.cycleId,
      );
      if (cycle == null ||
          cycle.medicationId != payload.medicationId ||
          cycle.changeRecordId != payload.changeRecordId) {
        throw StateError('Tracking cycle is unavailable.');
      }
      navigator.push(
        MaterialPageRoute(
          builder: (_) => MedicationSubjectiveResponsePage(
            medicationId: cycle.medicationId,
            medicationName: cycle.medicationName,
            changeRecordId: cycle.changeRecordId,
            changeDate: cycle.changeDate,
            adjustmentSummary: _trackingChangeSummary(cycle),
            followUpDay: payload.followUpDay,
          ),
        ),
      );
    } catch (error) {
      debugPrint('Unable to open medication subjective response: $error');
      rootMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('目前無法開啟這筆用藥感受問卷')),
      );
    }
  }

  String _trackingChangeSummary(MedicationSubjectiveTrackingCycle cycle) {
    switch (cycle.changeType) {
      case MedicationTrackingChangeType.added:
        return '新增藥物';
      case MedicationTrackingChangeType.resumed:
        return '重新開始使用';
      case MedicationTrackingChangeType.doseIncreased:
      case MedicationTrackingChangeType.doseDecreased:
        final unit = cycle.doseUnit?.trim() ?? '';
        final oldDose = cycle.oldDose;
        final newDose = cycle.newDose;
        if (oldDose != null && newDose != null) {
          return '${_doseText(oldDose)}$unit → ${_doseText(newDose)}$unit';
        }
        return cycle.changeType == MedicationTrackingChangeType.doseIncreased
            ? '增加劑量'
            : '減少劑量';
    }
  }

  String _doseText(double dose) =>
      dose == dose.roundToDouble() ? dose.toInt().toString() : dose.toString();

  bool _navigateToDailyRecord() {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return false;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RecordHubPage()),
      (_) => false,
    );
    return true;
  }

  bool _navigateToMedicationCheckin() {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return false;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MedicationCheckinPage()),
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
void notificationTapBackground(NotificationResponse notificationResponse) {
  NotificationHelper()
      .handleBackgroundNotificationResponse(notificationResponse);
}
