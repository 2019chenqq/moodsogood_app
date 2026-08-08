import 'package:cloud_firestore/cloud_firestore.dart';

/// 一筆快速事件紀錄（快速記錄現在狀況）。
///
/// 與 DailyRecord 完全獨立：一天可有多筆，每筆保留精確的 [timestamp]，
/// 供之後做症狀／情緒共現分析。結構化資料（症狀、情緒、狀態、context、note）
/// 皆透過 HealthDataEncryptionService 加密儲存，只有 timestamp / createdAt /
/// updatedAt 保留在密文外作為查詢欄位。
class HealthEvent {
  final String id;
  final DateTime timestamp;
  final List<HealthEventSymptom> symptoms;
  final List<HealthEventEmotion> emotions;
  final Map<String, int> stateChanges; // keys: energy / appetite / activity
  final String? context;
  final String? note;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const HealthEvent({
    required this.id,
    required this.timestamp,
    this.symptoms = const [],
    this.emotions = const [],
    this.stateChanges = const {},
    this.context,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp,
      'symptoms': symptoms.map((e) => e.toMap()).toList(),
      'emotions': emotions.map((e) => e.toMap()).toList(),
      if (stateChanges.isNotEmpty) 'stateChanges': Map.of(stateChanges),
      if (context != null && context!.trim().isNotEmpty)
        'context': context!.trim(),
      if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
    };
  }

  factory HealthEvent.fromMap(String id, Map<String, dynamic> map) {
    final timestamp = DateTime.tryParse(map['timestamp']?.toString() ?? '');
    return HealthEvent(
      id: id,
      timestamp: timestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
      symptoms: _parseSymptoms(map['symptoms']),
      emotions: _parseEmotions(map['emotions']),
      stateChanges: _parseStateChanges(map['stateChanges']),
      context: map['context']?.toString(),
      note: map['note']?.toString(),
      createdAt: _asDate(map['createdAt']),
      updatedAt: _asDate(map['updatedAt']),
    );
  }

  static List<HealthEventSymptom> _parseSymptoms(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => HealthEventSymptom.fromMap(m.cast<String, dynamic>()))
        .where((s) => s.name.trim().isNotEmpty)
        .toList();
  }

  static List<HealthEventEmotion> _parseEmotions(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => HealthEventEmotion.fromMap(m.cast<String, dynamic>()))
        .where((e) => e.name.trim().isNotEmpty)
        .toList();
  }

  static Map<String, int> _parseStateChanges(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, int>{};
    for (final entry in raw.entries) {
      final value = entry.value is num ? (entry.value as num).toInt() : null;
      if (value != null && value >= 1 && value <= 5) {
        result[entry.key.toString()] = value;
      }
    }
    return result;
  }

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  HealthEvent copyWith({
    String? id,
    DateTime? timestamp,
    List<HealthEventSymptom>? symptoms,
    List<HealthEventEmotion>? emotions,
    Map<String, int>? stateChanges,
    String? context,
    bool clearContext = false,
    String? note,
    bool clearNote = false,
  }) {
    return HealthEvent(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      symptoms: symptoms ?? this.symptoms,
      emotions: emotions ?? this.emotions,
      stateChanges: stateChanges ?? this.stateChanges,
      context: clearContext ? null : (context ?? this.context),
      note: clearNote ? null : (note ?? this.note),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// 症狀：name + severity(1~5)。
class HealthEventSymptom {
  final String name;
  final int severity;

  const HealthEventSymptom({required this.name, required this.severity});

  Map<String, dynamic> toMap() => {'name': name, 'severity': severity};

  factory HealthEventSymptom.fromMap(Map<String, dynamic> map) {
    final severity = (map['severity'] as num?)?.toInt();
    return HealthEventSymptom(
      name: (map['name'] ?? '').toString(),
      severity:
          severity != null && severity >= 1 && severity <= 5 ? severity : 3,
    );
  }

  HealthEventSymptom copyWith({String? name, int? severity}) =>
      HealthEventSymptom(
        name: name ?? this.name,
        severity: severity ?? this.severity,
      );
}

/// 情緒：name + intensity(1~5)。
class HealthEventEmotion {
  final String name;
  final int intensity;

  const HealthEventEmotion({required this.name, required this.intensity});

  Map<String, dynamic> toMap() => {'name': name, 'intensity': intensity};

  factory HealthEventEmotion.fromMap(Map<String, dynamic> map) {
    final intensity = (map['intensity'] as num?)?.toInt();
    return HealthEventEmotion(
      name: (map['name'] ?? '').toString(),
      intensity:
          intensity != null && intensity >= 1 && intensity <= 5 ? intensity : 3,
    );
  }

  HealthEventEmotion copyWith({String? name, int? intensity}) =>
      HealthEventEmotion(
        name: name ?? this.name,
        intensity: intensity ?? this.intensity,
      );
}
