import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/notification_helper.dart';
import 'medication_local_db.dart';

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

  /// 根據目前啟用中的藥物，自動重建「每日服藥提醒」。
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

    for (final med in activeOralMeds) {
      final name = ((med['name'] ?? med['nameZh'] ?? med['nameEn'] ?? '未命名藥物') as String)
          .trim();
      final times = ((med['times'] as List?) ?? const [])
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      for (final slot in times) {
        if (medsBySlot.containsKey(slot)) {
          medsBySlot[slot]!.add(name.isEmpty ? '未命名藥物' : name);
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

    return scheduledCount;
  }

  static Future<void> cancelAllMedicationReminders() async {
    final helper = NotificationHelper();
    await helper.init();
    for (final id in _slotNotificationIds.values) {
      await helper.cancelNotification(id);
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
