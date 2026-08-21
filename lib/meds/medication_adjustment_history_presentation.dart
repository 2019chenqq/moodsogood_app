import 'med_symptom_compare_models.dart';

class MedicationAdjustmentHistoryEntry {
  const MedicationAdjustmentHistoryEntry({
    required this.record,
    required this.events,
  });

  final Map<String, dynamic> record;
  final List<MedicationAdjustmentEvent> events;

  DateTime get date => events.first.effectiveDateTime;
  String get dateLabel => events.first.dateLabel;
}

/// Converts persisted records to display entries and always sorts newest first.
/// Date labels intentionally omit time while ordering retains timestamp precision.
List<MedicationAdjustmentHistoryEntry> buildMedicationAdjustmentHistory(
  Iterable<Map<String, dynamic>> records,
) {
  final entries = <MedicationAdjustmentHistoryEntry>[];
  for (final record in records) {
    final events = MedicationAdjustmentEvent.fromRecord(record);
    if (events.isEmpty) continue;
    entries.add(MedicationAdjustmentHistoryEntry(
      record: record,
      events: events,
    ));
  }
  entries.sort((left, right) {
    final byDate = right.date.compareTo(left.date);
    if (byDate != 0) return byDate;
    return (right.record['id'] ?? '')
        .toString()
        .compareTo((left.record['id'] ?? '').toString());
  });
  return entries;
}
