import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/notification_helper.dart';
import 'follow_up_service.dart';

class FollowUpReminderSettings {
  const FollowUpReminderSettings({
    this.reminderDays = 3,
    this.aiCheckInEnabled = false,
    this.reminderHour = 9,
    this.reminderMinute = 0,
  });

  final int reminderDays;
  final bool aiCheckInEnabled;
  final int reminderHour;
  final int reminderMinute;

  FollowUpReminderSettings copyWith({
    int? reminderDays,
    bool? aiCheckInEnabled,
    int? reminderHour,
    int? reminderMinute,
  }) =>
      FollowUpReminderSettings(
        reminderDays: reminderDays ?? this.reminderDays,
        aiCheckInEnabled: aiCheckInEnabled ?? this.aiCheckInEnabled,
        reminderHour: reminderHour ?? this.reminderHour,
        reminderMinute: reminderMinute ?? this.reminderMinute,
      );
}

class FollowUpScheduledReminder {
  const FollowUpScheduledReminder({
    required this.notificationId,
    required this.appointmentDate,
    required this.scheduledAt,
    required this.appointmentLabel,
  });

  final int notificationId;
  final DateTime appointmentDate;
  final DateTime scheduledAt;
  final String appointmentLabel;
}

class FollowUpReminderScheduleResult {
  const FollowUpReminderScheduleResult(this.reminders);

  final List<FollowUpScheduledReminder> reminders;
  int get count => reminders.length;
}

class FollowUpReminderService {
  FollowUpReminderService({NotificationHelper? notificationHelper})
      : _notificationHelper = notificationHelper ?? NotificationHelper();

  static const supportedReminderDays = <int>[1, 3, 7];
  static const _daysKey = 'followUpReminderDays';
  static const _aiCheckInKey = 'followUpAiCheckInEnabled';
  static const _hourKey = 'followUpReminderHour';
  static const _minuteKey = 'followUpReminderMinute';
  static const _notificationIdsKey = 'followUpReminderNotificationIds';
  static const _firstNotificationId = 32000;

  final NotificationHelper _notificationHelper;

  Future<FollowUpReminderSettings> loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    final storedDays = preferences.getInt(_daysKey) ?? 3;
    final storedHour = preferences.getInt(_hourKey) ?? 9;
    final storedMinute = preferences.getInt(_minuteKey) ?? 0;
    return FollowUpReminderSettings(
      reminderDays: supportedReminderDays.contains(storedDays) ? storedDays : 3,
      aiCheckInEnabled: preferences.getBool(_aiCheckInKey) ?? false,
      reminderHour: storedHour >= 0 && storedHour <= 23 ? storedHour : 9,
      reminderMinute:
          storedMinute >= 0 && storedMinute <= 59 ? storedMinute : 0,
    );
  }

  Future<FollowUpReminderScheduleResult> saveAndReschedule({
    required FollowUpReminderSettings settings,
    required List<FollowUpAppointment> appointments,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_daysKey, settings.reminderDays);
    await preferences.setBool(_aiCheckInKey, settings.aiCheckInEnabled);
    await preferences.setInt(_hourKey, settings.reminderHour);
    await preferences.setInt(_minuteKey, settings.reminderMinute);
    return reschedule(settings: settings, appointments: appointments);
  }

  Future<FollowUpReminderScheduleResult> reschedule({
    FollowUpReminderSettings? settings,
    required List<FollowUpAppointment> appointments,
    DateTime? now,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final previousIds =
        preferences.getStringList(_notificationIdsKey) ?? const <String>[];
    for (final value in previousIds) {
      final id = int.tryParse(value);
      if (id != null) await _notificationHelper.cancelNotification(id);
    }

    final activeSettings = settings ?? await loadSettings();
    final current = now ?? DateTime.now();
    final upcoming = appointments
        .where((appointment) => !DateTime(
              appointment.date.year,
              appointment.date.month,
              appointment.date.day,
              23,
              59,
              59,
            ).isBefore(current))
        .toList()
      ..sort((left, right) => left.date.compareTo(right.date));

    final scheduledIds = <String>[];
    final scheduledReminders = <FollowUpScheduledReminder>[];
    for (var index = 0; index < upcoming.length && index < 50; index++) {
      final appointment = upcoming[index];
      final reminderDate = DateTime(
        appointment.date.year,
        appointment.date.month,
        appointment.date.day,
        activeSettings.reminderHour,
        activeSettings.reminderMinute,
      ).subtract(Duration(days: activeSettings.reminderDays));
      if (!reminderDate.isAfter(current)) continue;

      final id = _firstNotificationId + index;
      final label = appointment.label.trim();
      final visitName = label.isEmpty ? '回診' : label;
      final scheduled = await _notificationHelper.scheduleOneTimeNotification(
        id: id,
        title: activeSettings.aiCheckInEnabled ? 'AI 回診前關心' : '回診提醒',
        body: activeSettings.aiCheckInEnabled
            ? '$visitName還有 ${activeSettings.reminderDays} 天，要一起整理近期變化與想討論的重點嗎？'
            : '$visitName還有 ${activeSettings.reminderDays} 天，可以先準備想和醫師討論的事項。',
        scheduledAt: reminderDate,
        payload: NotificationHelper.followUpSummaryPayload,
      );
      if (scheduled) {
        scheduledIds.add(id.toString());
        scheduledReminders.add(
          FollowUpScheduledReminder(
            notificationId: id,
            appointmentDate: appointment.date,
            scheduledAt: reminderDate,
            appointmentLabel: visitName,
          ),
        );
      }
    }
    await preferences.setStringList(_notificationIdsKey, scheduledIds);
    return FollowUpReminderScheduleResult(scheduledReminders);
  }
}
