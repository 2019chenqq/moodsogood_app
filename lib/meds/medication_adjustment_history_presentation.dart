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
  Iterable<Map<String, dynamic>> records, {
  Iterable<Map<String, dynamic>> medications = const [],
}) {
  final entries = <MedicationAdjustmentHistoryEntry>[];
  final persistedEvents = <MedicationAdjustmentEvent>[];
  for (final record in records) {
    final events = MedicationAdjustmentEvent.fromRecord(record);
    if (events.isEmpty) continue;
    persistedEvents.addAll(events);
    entries.add(MedicationAdjustmentHistoryEntry(
      record: record,
      events: events,
    ));
  }
  for (final event in buildSyntheticAddedEvents(medications, persistedEvents)) {
    entries.add(MedicationAdjustmentHistoryEntry(
      record: <String, dynamic>{
        'id': event.adjustmentId,
        'source': event.source,
        'note': event.inferenceReason,
        'inferred': true,
      },
      events: <MedicationAdjustmentEvent>[event],
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
