List<String> normalizeFollowUpQuestions(Iterable<String> values) {
  final questions = <String>[];
  final seen = <String>{};
  final splitPattern = RegExp(
    r'(?:\r?\n)+|(?=\s*\d{1,2}\s*(?:[.)]\s+|[、．]\s*))',
  );
  final prefixPattern = RegExp(
    r'^(?:[-*•]\s*|\d{1,2}\s*(?:[.)]\s+|[、．]\s*))',
  );

  for (final value in values) {
    for (final part in value.split(splitPattern)) {
      final question = part.trim().replaceFirst(prefixPattern, '').trim();
      if (!_isQuestion(question) || !seen.add(question)) continue;
      questions.add(question);
    }
  }
  return questions;
}

bool _isQuestion(String value) =>
    value.isNotEmpty && (value.endsWith('？') || value.endsWith('?'));
