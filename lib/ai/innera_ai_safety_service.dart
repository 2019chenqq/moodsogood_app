enum AiSafetyLevel {
  normal,
  emotionalDistress,
  possibleSelfHarm,
  imminentDanger,
  possibleHarmToOthers,
  medicalUrgency,
}

class AiSafetyResult {
  const AiSafetyResult({required this.level, this.matchedTerms = const []});

  final AiSafetyLevel level;
  final List<String> matchedTerms;

  bool get shouldStopGeneralReply =>
      level == AiSafetyLevel.imminentDanger ||
      level == AiSafetyLevel.medicalUrgency;
}

class InneraAiSafetyService {
  static const imminentSelfHarmReply = '''
我很擔心你現在可能有立即傷害自己的危險。

請先暫停現在可能傷害自己的行動，並把藥物、刀具或其他危險物品交給身邊可信任的人。

請立即聯絡身邊可以陪你的人，並撥打 119 或前往最近的急診。

台灣也可撥打：
• 1925 安心專線
• 1995 生命線
• 1980 張老師''';

  static const medicalUrgencyReply =
      '你描述的狀況可能需要立即由醫療人員評估。心域 AI 無法排除急症，請撥打 119 或儘快前往急診。';

  static const temporarilySafeReply = '謝謝你告訴我。現在請盡量不要獨處，並聯絡一位可以陪你的人或專業人員。';

  AiSafetyResult assess(String text) {
    final source = text.trim();
    if (source.isEmpty) {
      return const AiSafetyResult(level: AiSafetyLevel.normal);
    }

    final medicalTerms = _medicalUrgencyTerms
        .where((term) => source.contains(term) && !_isNegated(source, term))
        .toList();
    if (medicalTerms.isNotEmpty) {
      return AiSafetyResult(
        level: AiSafetyLevel.medicalUrgency,
        matchedTerms: medicalTerms,
      );
    }

    final selfHarmTerms = _selfHarmTerms
        .where((term) => source.contains(term) && !_isNegated(source, term))
        .toList();
    final hasMethod = _methodTerms.any(source.contains);
    final hasTiming = _timingTerms.any(source.contains);
    final hasPreparation = _preparationTerms.any(source.contains);
    final cannotStaySafe = _unsafeTerms.any(source.contains);

    if (selfHarmTerms.isNotEmpty &&
        (hasMethod || hasTiming || hasPreparation || cannotStaySafe)) {
      return AiSafetyResult(
        level: AiSafetyLevel.imminentDanger,
        matchedTerms: selfHarmTerms,
      );
    }
    if (selfHarmTerms.isNotEmpty) {
      return AiSafetyResult(
        level: AiSafetyLevel.possibleSelfHarm,
        matchedTerms: selfHarmTerms,
      );
    }

    final harmToOthers = _harmToOthersTerms
        .where((term) => source.contains(term) && !_isNegated(source, term))
        .toList();
    if (harmToOthers.isNotEmpty) {
      return AiSafetyResult(
        level: AiSafetyLevel.possibleHarmToOthers,
        matchedTerms: harmToOthers,
      );
    }

    final distress = _distressTerms
        .where((term) => source.contains(term) && !_isNegated(source, term))
        .toList();
    if (distress.isNotEmpty) {
      return AiSafetyResult(
        level: AiSafetyLevel.emotionalDistress,
        matchedTerms: distress,
      );
    }

    return const AiSafetyResult(level: AiSafetyLevel.normal);
  }

  bool _isNegated(String source, String term) {
    final index = source.indexOf(term);
    if (index < 0) return false;
    final start = index - 8 < 0 ? 0 : index - 8;
    final prefix = source.substring(start, index);
    return prefix.contains('沒有') ||
        prefix.contains('並沒有') ||
        prefix.contains('不會') ||
        prefix.contains('不是') ||
        prefix.contains('未曾') ||
        prefix.contains('沒有打算') ||
        prefix.contains('不想要');
  }

  static const _selfHarmTerms = [
    '不想活',
    '想死',
    '活不下去',
    '想消失',
    '傷害自己',
    '自殺',
    '輕生',
    '割腕',
    '跳樓',
    '吞藥',
  ];

  static const _methodTerms = ['割腕', '跳樓', '吞藥', '上吊', '刀', '藥', '工具'];
  static const _timingTerms = ['等一下', '現在就', '今晚', '今天就', '馬上'];
  static const _preparationTerms = ['準備好工具', '工具在身邊', '藥在身邊', '刀在身邊'];
  static const _unsafeTerms = ['不能保證安全', '無法保證安全', '控制不了'];
  static const _harmToOthersTerms = ['想殺人', '殺了他', '殺了她', '想傷害別人', '傷害別人'];
  static const _medicalUrgencyTerms = [
    '吐血',
    '黑便',
    '呼吸困難',
    '胸痛',
    '昏倒',
    '嚴重過敏',
    '意識不清',
    '持續大量出血',
  ];
  static const _distressTerms = ['崩潰', '撐不住', '很絕望', '好痛苦', '受不了了'];
}
