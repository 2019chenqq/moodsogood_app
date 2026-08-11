/// Canonical state-change keys shared by day-level and event-level records.
const Map<String, String> legacyStateChangeKeys = {
  'energy': 'energy_change',
  'appetite': 'appetite_change',
  'activity': 'activity_change',
};

String normalizeStateChangeKey(String key) {
  final trimmed = key.trim();
  return legacyStateChangeKeys[trimmed] ?? trimmed;
}

Map<String, int> normalizeStateChanges(dynamic raw) {
  if (raw is! Map) return const {};
  final result = <String, int>{};
  for (final entry in raw.entries) {
    final value = entry.value is num ? (entry.value as num).toInt() : null;
    if (value == null || value < 1 || value > 5) continue;
    final rawKey = entry.key.toString().trim();
    final key = normalizeStateChangeKey(rawKey);
    if (rawKey != key && raw.containsKey(key)) continue;
    if (key.isNotEmpty) result[key] = value;
  }
  return result;
}
