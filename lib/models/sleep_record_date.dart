import 'package:cloud_firestore/cloud_firestore.dart';

/// Internal sleep-read date policy. Never uses the clock, createdAt or updatedAt.
/// A valid explicit date wins; only a strict calendar document ID is fallback.
DateTime? sleepRecordDocumentDate(dynamic value, String documentId) =>
    parseSleepRecordDate(value) ??
    (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(documentId)
        ? parseSleepRecordDate(documentId)
        : null);

DateTime? parseSleepRecordDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is! String) return null;
  // DateTime.tryParse accepts overflowing dates/times (e.g. February 30).
  // Validate the original calendar components before parsing any zone offset.
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(?:[Zz]|[+-](\d{2}):?(\d{2}))?)?$',
  ).firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  if (year < 1 || month < 1 || month > 12 || day < 1) return null;
  final checked = DateTime.utc(year, month, day);
  if (checked.year != year || checked.month != month || checked.day != day) {
    return null;
  }
  for (final (index, maximum) in [
    (4, 23),
    (5, 59),
    (6, 59),
    (7, 23),
    (8, 59)
  ]) {
    if (match[index] != null && int.parse(match[index]!) > maximum) return null;
  }
  return DateTime.tryParse(value);
}
