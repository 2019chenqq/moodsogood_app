import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/notification_helper.dart';
import 'medication_local_db.dart';
import 'medication_subjective_reminder_payload.dart';
import 'medication_subjective_response.dart';
import 'medication_subjective_tracking_cycle.dart';

class MedicationSubjectiveScheduledReminder {
  const MedicationSubjectiveScheduledReminder({
    required this.notificationId,
    required this.cycleId,
    required this.medicationId,
    required this.changeRecordId,
    required this.followUpDay,
    required this.scheduledAt,
    required this.payload,
  });

  final int notificationId;
  final String cycleId;
  final String medicationId;
  final String changeRecordId;
  final int followUpDay;
  final DateTime scheduledAt;
  final String payload;
}

class MedicationSubjectiveReminderPlanner {
  const MedicationSubjectiveReminderPlanner._();

  static const int reminderHour = 20;
  static const int reminderMinute = 0;
  static const int _notificationIdBase = 400000000;
  static const int _notificationIdRange = 1400000000;

  static List<MedicationSubjectiveScheduledReminder> build({
    required Iterable<MedicationSubjectiveTrackingCycle> cycles,
    required Iterable<MedicationSubjectiveResponse> responses,
    required DateTime now,
  }) {
    final completed = responses
        .map(
          (response) => _completionKey(
            response.medicationId,
            response.changeRecordId,
            response.followUpDay,
          ),
        )
        .toSet();
    final usedIds = <int>{};
    final reminders = <MedicationSubjectiveScheduledReminder>[];
    final activeCycles = cycles.where((cycle) => cycle.active).toList()
      ..sort((left, right) {
        final byDate = left.changeDate.compareTo(right.changeDate);
        return byDate != 0 ? byDate : left.id.compareTo(right.id);
      });

    for (final cycle in activeCycles) {
      for (final entry in cycle.followUpDates.entries) {
        final day = entry.key;
        if (completed.contains(
          _completionKey(cycle.medicationId, cycle.changeRecordId, day),
        )) {
          continue;
        }
        final date = entry.value;
        final scheduledAt = DateTime(
          date.year,
          date.month,
          date.day,
          reminderHour,
          reminderMinute,
        );
        if (!scheduledAt.isAfter(now)) continue;

        final payload = MedicationSubjectiveReminderPayload(
          cycleId: cycle.id,
          medicationId: cycle.medicationId,
          changeRecordId: cycle.changeRecordId,
          followUpDay: day,
        ).encode();
        var notificationId = notificationIdFor(
          cycleId: cycle.id,
          medicationId: cycle.medicationId,
          changeRecordId: cycle.changeRecordId,
          followUpDay: day,
        );
        while (!usedIds.add(notificationId)) {
          notificationId = _notificationIdBase +
              ((notificationId - _notificationIdBase + 1) %
                  _notificationIdRange);
        }
        reminders.add(
          MedicationSubjectiveScheduledReminder(
            notificationId: notificationId,
            cycleId: cycle.id,
            medicationId: cycle.medicationId,
            changeRecordId: cycle.changeRecordId,
            followUpDay: day,
            scheduledAt: scheduledAt,
            payload: payload,
          ),
        );
      }
    }
    return reminders;
  }

  static int notificationIdFor({
    required String cycleId,
    required String medicationId,
    required String changeRecordId,
    required int followUpDay,
  }) {
    final key = '$cycleId|$medicationId|$changeRecordId|$followUpDay';
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return _notificationIdBase + (hash % _notificationIdRange);
  }

  static String _completionKey(
    String medicationId,
    String changeRecordId,
    int followUpDay,
  ) =>
      '$medicationId|$changeRecordId|$followUpDay';
}

class MedicationSubjectiveReminderService {
  MedicationSubjectiveReminderService({
    NotificationHelper? notificationHelper,
    MedicationLocalDB? localDb,
  })  : _notificationHelper = notificationHelper ?? NotificationHelper(),
        _localDb = localDb ?? MedicationLocalDB();

  static const _scheduledIdsKey = 'medicationSubjectiveReminderNotificationIds';

  final NotificationHelper _notificationHelper;
  final MedicationLocalDB _localDb;

  Future<int> syncForCurrentUser({
    String? uid,
    DateTime? now,
  }) async {
    final resolvedUid = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (resolvedUid == null || resolvedUid.isEmpty) return 0;

    final preferences = await SharedPreferences.getInstance();
    final previousIds =
        preferences.getStringList(_scheduledIdsKey) ?? const <String>[];
    for (final value in previousIds) {
      final id = int.tryParse(value);
      if (id != null) await _notificationHelper.cancelNotification(id);
    }
    await preferences.remove(_scheduledIdsKey);

    final results = await Future.wait([
      _localDb.getSubjectiveTrackingCycles(uid: resolvedUid),
      _localDb.getAllSubjectiveResponses(resolvedUid),
    ]);
    final reminders = MedicationSubjectiveReminderPlanner.build(
      cycles: results[0] as List<MedicationSubjectiveTrackingCycle>,
      responses: results[1] as List<MedicationSubjectiveResponse>,
      now: now ?? DateTime.now(),
    );

    final scheduledIds = <String>[];
    for (final reminder in reminders) {
      final scheduled = await _notificationHelper.scheduleOneTimeNotification(
        id: reminder.notificationId,
        title: '用藥感受回報',
        body: '距離這次用藥調整已 ${reminder.followUpDay} 天，記錄一下最近的感受。',
        scheduledAt: reminder.scheduledAt,
        payload: reminder.payload,
      );
      if (scheduled) scheduledIds.add(reminder.notificationId.toString());
    }
    await preferences.setStringList(_scheduledIdsKey, scheduledIds);
    return scheduledIds.length;
  }
}
