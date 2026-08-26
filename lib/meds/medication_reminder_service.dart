import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/notification_helper.dart';
import 'medication_local_db.dart';
import 'medication_checkin_schedule_resolver.dart';

class MedicationReminderService {
  MedicationReminderService._();

  static const Map<String, TimeOfDay> kSlotTimes = {
    '早上': TimeOfDay(hour: 8, minute: 0),
    '中午': TimeOfDay(hour: 12, minute: 30),
    '下午': TimeOfDay(hour: 18, minute: 0),
    '晚上': TimeOfDay(hour: 20, minute: 0),
    '睡前': TimeOfDay(hour: 22, minute: 30),
  };

  static const Map<String, int> _slotNotificationIds = {
    '早上': 21101,
    '中午': 21102,
    '下午': 21103,
    '晚上': 21104,
    '睡前': 21105,
  };
  static const int _weeklyNotificationBase = 21200;
  static const int _intervalNotificationBase = 21300;
  static const int _intervalNotificationLimit = 40;

  static String _prefKey(String slot) => 'med_reminder_${slot}_time';

  static Future<TimeOfDay> getSlotTime(String slot) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey(slot));
    if (saved == null || saved.isEmpty) {
      return kSlotTimes[slot] ?? const TimeOfDay(hour: 8, minute: 0);
    }

    final parts = saved.split(':');
    if (parts.length != 2) {
      return kSlotTimes[slot] ?? const TimeOfDay(hour: 8, minute: 0);
    }

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) {
      return kSlotTimes[slot] ?? const TimeOfDay(hour: 8, minute: 0);
    }

    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  static Future<Map<String, TimeOfDay>> getAllSlotTimes() async {
    final result = <String, TimeOfDay>{};
    for (final slot in kSlotTimes.keys) {
      result[slot] = await getSlotTime(slot);
    }
    return result;
  }

  static Future<void> setSlotTime(String slot, TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    await prefs.setString(_prefKey(slot), '$h:$m');
  }

  /// 根據目前啟用中的藥物，自動重建每日、每週與間隔服藥提醒。
  ///
  /// 回傳：實際建立的提醒數量。
  static Future<int> syncDailyRemindersForActiveMeds() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 0;

    final helper = NotificationHelper();
    await helper.init();

    final meds = await MedicationLocalDB().getMedicationsForDisplay(uid);
    final activeOralMeds = meds.where((m) {
      final isActive = (m['isActive'] as bool?) ?? true;
      final isInjection = (m['type'] as String?) == 'injection';
      return isActive && !isInjection;
    }).toList();

    final Map<String, List<String>> medsBySlot = {
      for (final key in kSlotTimes.keys) key: <String>[],
    };
    final weeklyByDayAndSlot = <String, List<String>>{};
    final intervalMeds = <Map<String, dynamic>>[];

    for (final med in activeOralMeds) {
      final name =
          ((med['name'] ?? med['nameZh'] ?? med['nameEn'] ?? '未命名藥物') as String)
              .trim();
      final times = ((med['times'] as List?) ?? const [])
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      final displayName = name.isEmpty ? '未命名藥物' : name;
      switch ((med['scheduleType'] ?? 'daily').toString()) {
        case 'weekdays':
          final weekdays = ((med['weekdays'] as List?) ?? const [])
              .whereType<num>()
              .map((value) => value.toInt())
              .where((value) => value >= 1 && value <= 7);
          for (final weekday in weekdays) {
            for (final slot in times.where(medsBySlot.containsKey)) {
              weeklyByDayAndSlot
                  .putIfAbsent('$weekday::$slot', () => <String>[])
                  .add(displayName);
            }
          }
          break;
        case 'intervalDays':
          intervalMeds.add(med);
          break;
        default:
          for (final slot in times) {
            if (medsBySlot.containsKey(slot)) {
              medsBySlot[slot]!.add(displayName);
            }
          }
      }
    }

    var scheduledCount = 0;
    final slotTimes = await getAllSlotTimes();

    for (final entry in _slotNotificationIds.entries) {
      final slot = entry.key;
      final id = entry.value;
      final names = medsBySlot[slot] ?? const <String>[];

      await helper.cancelNotification(id);

      if (names.isEmpty) continue;

      final title = '服藥提醒｜$slot';
      final body = _buildReminderBody(names);
      await helper.scheduleDailyNotification(
        id: id,
        title: title,
        body: body,
        time: slotTimes[slot] ?? kSlotTimes[slot]!,
        payload: NotificationHelper.medicationCheckinPayload,
      );
      scheduledCount += 1;
    }

    final slotNames = kSlotTimes.keys.toList(growable: false);
    for (var weekday = 1; weekday <= 7; weekday++) {
      for (var slotIndex = 0; slotIndex < slotNames.length; slotIndex++) {
        final slot = slotNames[slotIndex];
        final id = _weeklyNotificationBase + weekday * 10 + slotIndex;
        await helper.cancelNotification(id);
        final names = weeklyByDayAndSlot['$weekday::$slot'] ?? const <String>[];
        if (names.isEmpty) continue;
        await helper.scheduleWeeklyNotification(
          id: id,
          title: '服藥提醒｜$slot',
          body: _buildReminderBody(names),
          weekday: weekday,
          time: slotTimes[slot]!,
          payload: NotificationHelper.medicationCheckinPayload,
        );
        scheduledCount++;
      }
    }

    for (var index = 0; index < _intervalNotificationLimit; index++) {
      await helper.cancelNotification(_intervalNotificationBase + index);
    }
    final now = DateTime.now();
    final occurrences = <({DateTime at, String slot, String name})>[];
    for (var offset = 0; offset <= 60; offset++) {
      final day =
          DateTime(now.year, now.month, now.day).add(Duration(days: offset));
      for (final med in intervalMeds) {
        if (!MedicationCheckinScheduleResolver.isScheduledOn(med, day))
          continue;
        final name = (med['name'] ?? med['nameZh'] ?? med['nameEn'] ?? '未命名藥物')
            .toString();
        for (final slot
            in ((med['times'] as List?) ?? const []).whereType<String>()) {
          final time = slotTimes[slot];
          if (time == null) continue;
          final at =
              DateTime(day.year, day.month, day.day, time.hour, time.minute);
          if (at.isAfter(now))
            occurrences.add((at: at, slot: slot, name: name));
        }
      }
    }
    occurrences.sort((a, b) => a.at.compareTo(b.at));
    for (var index = 0;
        index < occurrences.length && index < _intervalNotificationLimit;
        index++) {
      final occurrence = occurrences[index];
      final didSchedule = await helper.scheduleOneTimeNotification(
        id: _intervalNotificationBase + index,
        title: '服藥提醒｜${occurrence.slot}',
        body: _buildReminderBody([occurrence.name]),
        scheduledAt: occurrence.at,
        payload: NotificationHelper.medicationCheckinPayload,
      );
      if (didSchedule) scheduledCount++;
    }

    return scheduledCount;
  }

  static Future<void> cancelAllMedicationReminders() async {
    final helper = NotificationHelper();
    await helper.init();
    for (final id in _slotNotificationIds.values) {
      await helper.cancelNotification(id);
    }
    for (var weekday = 1; weekday <= 7; weekday++) {
      for (var slotIndex = 0; slotIndex < kSlotTimes.length; slotIndex++) {
        await helper.cancelNotification(
          _weeklyNotificationBase + weekday * 10 + slotIndex,
        );
      }
    }
    for (var index = 0; index < _intervalNotificationLimit; index++) {
      await helper.cancelNotification(_intervalNotificationBase + index);
    }
  }

  static String _buildReminderBody(List<String> names) {
    final unique = names.toSet().toList();
    if (unique.length <= 2) {
      return '請記得服用：${unique.join('、')}';
    }
    final preview = unique.take(2).join('、');
    return '請記得服用：$preview 等 ${unique.length} 種藥物';
  }
}
