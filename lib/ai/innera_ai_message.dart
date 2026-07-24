import 'innera_ai_safety_service.dart';

enum InneraAiMessageRole { user, assistant, system }

class AiContextSource {
  const AiContextSource({
    required this.label,
    required this.dateRange,
    required this.count,
  });

  final String label;
  final String dateRange;
  final int count;

  Map<String, dynamic> toMap() => {
        'label': label,
        'dateRange': dateRange,
        'count': count,
      };

  factory AiContextSource.fromMap(Map<String, dynamic> map) => AiContextSource(
        label: (map['label'] ?? '').toString(),
        dateRange: (map['dateRange'] ?? '').toString(),
        count: (map['count'] as num?)?.toInt() ?? 0,
      );
}

class InneraAiMessage {
  const InneraAiMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.sources = const [],
    this.safetyLevel = AiSafetyLevel.normal,
    this.isLoading = false,
    this.isError = false,
    this.canRetry = false,
  });

  final String id;
  final InneraAiMessageRole role;
  final String text;
  final DateTime createdAt;
  final List<AiContextSource> sources;
  final AiSafetyLevel safetyLevel;
  final bool isLoading;
  final bool isError;
  final bool canRetry;

  bool get canPersist => !isLoading && !isError && text.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'id': id,
        'role': role.name,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'sources': sources.map((source) => source.toMap()).toList(),
        'safetyLevel': safetyLevel.name,
      };

  static InneraAiMessage? tryFromMap(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString().trim();
    final text = (map['text'] ?? '').toString().trim();
    final createdAt = DateTime.tryParse((map['createdAt'] ?? '').toString());
    final roleName = map['role']?.toString();
    if (id.isEmpty || text.isEmpty || createdAt == null) return null;
    final role = InneraAiMessageRole.values.firstWhere(
      (value) => value.name == roleName,
      orElse: () => InneraAiMessageRole.assistant,
    );
    if (role == InneraAiMessageRole.system) return null;
    return InneraAiMessage(
      id: id,
      role: role,
      text: text,
      createdAt: createdAt,
      sources: (map['sources'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => AiContextSource.fromMap(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((source) => source.label.isNotEmpty)
              .toList() ??
          const [],
      safetyLevel: AiSafetyLevel.values.firstWhere(
        (value) => value.name == map['safetyLevel']?.toString(),
        orElse: () => AiSafetyLevel.normal,
      ),
    );
  }

  InneraAiMessage copyWith({
    String? text,
    List<AiContextSource>? sources,
    AiSafetyLevel? safetyLevel,
    bool? isLoading,
    bool? isError,
    bool? canRetry,
  }) {
    return InneraAiMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      createdAt: createdAt,
      sources: sources ?? this.sources,
      safetyLevel: safetyLevel ?? this.safetyLevel,
      isLoading: isLoading ?? this.isLoading,
      isError: isError ?? this.isError,
      canRetry: canRetry ?? this.canRetry,
    );
  }
}
