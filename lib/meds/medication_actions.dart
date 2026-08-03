import 'package:flutter/material.dart';
import 'edit_medication_page.dart';
import 'medication_local_db.dart';
import 'medication_reminder_service.dart';
import 'medication_adjustment_service.dart';

Future<void> showMedicationMoreSheet({
  required BuildContext context,
  required String uid,
  required String medId,
  required Map<String, dynamic> data,
}) async {
  final name = (data['nameZh'] ?? data['name'] ?? '未命名藥物').toString();

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final isActive = (data['isActive'] as bool?) ?? true;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('編輯藥物資料'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            if (isActive)
              ListTile(
                leading: const Icon(Icons.pause_circle_outline),
                title: const Text('停藥（標記為已停用）'),
                onTap: () => Navigator.pop(ctx, 'deactivate'),
              )
            else
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('恢復使用'),
                onTap: () => Navigator.pop(ctx, 'activate'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('刪除（永久）'),
              subtitle: const Text('不可復原，建議先用停用'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      );
    },
  );

  if (action == null) return;

  try {
    if (action == 'edit') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EditMedicationPage(docId: medId, initialData: data),
        ),
      );
      return;
    }
    if (action == 'deactivate') {
      await _setMedicationActive(
        uid: uid,
        medId: medId,
        data: data,
        isActive: false,
      );
      await MedicationReminderService.syncDailyRemindersForActiveMeds();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已停用：$name')),
      );
      return;
    }

    if (action == 'activate') {
      await _setMedicationActive(
        uid: uid,
        medId: medId,
        data: data,
        isActive: true,
      );
      await MedicationReminderService.syncDailyRemindersForActiveMeds();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已恢復使用：$name')),
      );
      return;
    }

    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('確認刪除？'),
          content: Text('確定要永久刪除「$name」嗎？\n此操作不可復原。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('刪除')),
          ],
        ),
      );

      if (ok != true) return;

      await _deleteMedication(uid: uid, medId: medId);
      await MedicationReminderService.syncDailyRemindersForActiveMeds();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已刪除：$name')),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('操作失敗：$e')),
    );
  }
}

Future<void> _setMedicationActive({
  required String uid,
  required String medId,
  required Map<String, dynamic> data,
  required bool isActive,
}) async {
  final now = DateTime.now();
  await MedicationLocalDB().updateMedicationStatus(
    uid,
    medId,
    isActive: isActive,
    updatedAt: now.toIso8601String(),
    lastChangeAt: now.toIso8601String(),
  );
  await MedicationAdjustmentService().recordDetectedChanges(
    uid: uid,
    medDocId: medId,
    before: data,
    after: {...data, 'isActive': isActive},
    effectiveDate: now,
    source: 'medicationMoreSheet',
    note: isActive ? '恢復使用' : '停藥',
  );
}

Future<void> _deleteMedication(
    {required String uid, required String medId}) async {
  await MedicationLocalDB().deleteMedication(uid, medId);
}

Future<bool> _confirmDeleteMedication(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('確認刪除？'),
        content: Text('你確定要永久刪除「$name」嗎？\n\n此操作不可復原。建議若只是暫停使用，改用「停用」。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('永久刪除'),
          ),
        ],
      );
    },
  );
  return result == true;
}
