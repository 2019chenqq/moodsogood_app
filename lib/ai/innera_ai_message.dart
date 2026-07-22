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
