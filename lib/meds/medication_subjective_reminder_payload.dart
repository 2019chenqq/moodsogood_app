import 'dart:convert';

class MedicationSubjectiveReminderPayload {
  const MedicationSubjectiveReminderPayload({
    required this.cycleId,
    required this.medicationId,
    required this.changeRecordId,
    required this.followUpDay,
  });

  static const String type = 'medication_subjective_response';

  final String cycleId;
  final String medicationId;
  final String changeRecordId;
  final int followUpDay;

  String encode() => jsonEncode({
        'type': type,
        'cycleId': cycleId,
        'medicationId': medicationId,
        'changeRecordId': changeRecordId,
        'followUpDay': followUpDay,
      });

  static MedicationSubjectiveReminderPayload? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['type'] != type) return null;
      final cycleId = decoded['cycleId']?.toString().trim() ?? '';
      final medicationId = decoded['medicationId']?.toString().trim() ?? '';
      final changeRecordId = decoded['changeRecordId']?.toString().trim() ?? '';
      final followUpDay = decoded['followUpDay'] is int
          ? decoded['followUpDay'] as int
          : int.tryParse(decoded['followUpDay']?.toString() ?? '');
      if (cycleId.isEmpty ||
          medicationId.isEmpty ||
          changeRecordId.isEmpty ||
          followUpDay == null ||
          !const {3, 7, 14, 28}.contains(followUpDay)) {
        return null;
      }
      return MedicationSubjectiveReminderPayload(
        cycleId: cycleId,
        medicationId: medicationId,
        changeRecordId: changeRecordId,
        followUpDay: followUpDay,
      );
    } catch (_) {
      return null;
    }
  }
}
