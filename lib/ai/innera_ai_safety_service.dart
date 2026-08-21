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
      level == AiSafetyLevel.possibleSelfHarm ||
      level == AiSafetyLevel.imminentDanger ||
      level == AiSafetyLevel.medicalUrgency;
}

class InneraAiSafetyService {
  static const concernSelfHarmReply =
      '謝謝你願意說出來。這些念頭值得先被好好接住。請先不要獨處，聯絡一位你信任、能陪在身邊的人；如果你擔心自己可能會立刻行動，請優先撥打 119 或 110。';

  static const imminentSelfHarmReply = '''
你現在的安全最重要。請先暫停任何可能傷害自己的行動，並離開危險物品附近。

請立即聯絡身邊可以陪你的人，並撥打 119、110，或前往最近的急診。

台灣也可撥打：
• 1925 安心專線
• 1995 生命線
• 1980 張老師''';

  static const medicalUrgencyReply =
      '你描述的狀況可能需要立即由醫療人員評估。心域 AI 無法排除急症，請撥打 119 或儘快前往急診。';

  static const temporarilySafeReply = '謝謝你告訴我。現在請盡量不要獨處，並聯絡一位可以陪你的人或專業人員。';

  AiSafetyResult assess(String text) {
    final source = _normalize(text);
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

    final selfHarmTerms = <String>[];
    for (final clause in source.split(RegExp(r'[，。！？!?；;\n]'))) {
      if (_isGeneralDiscussion(clause) ||
          _isClearlyAboutAnotherPerson(clause)) {
        continue;
      }
      for (final term in safetyKeywords) {
        if (clause.contains(term) && !_isNegated(clause, term)) {
          selfHarmTerms.add(term);
        }
      }
    }
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
    final start = index - 12 < 0 ? 0 : index - 12;
    final prefix = source.substring(start, index);
    return prefix.contains('沒有') ||
        prefix.contains('沒想') ||
        prefix.contains('沒要') ||
        prefix.contains('並沒有') ||
        prefix.contains('並不') ||
        prefix.contains('不會') ||
        prefix.contains('不是') ||
        prefix.contains('未曾') ||
        prefix.contains('沒有打算') ||
        prefix.contains('不想要');
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\u200B-\u200D\uFEFF_－—-]+'), '')
      .replaceAll('ｓ', 's');

  bool _isGeneralDiscussion(String clause) => const [
        '防治專線',
        '專線是多少',
        '電話是多少',
        '新聞',
        '報導',
        '文章',
        '研究',
        '討論',
        '議題',
      ].any(clause.contains);

  bool _isClearlyAboutAnotherPerson(String clause) {
    final hasOtherSubject = _otherSubjectTerms.any(clause.contains);
    if (!hasOtherSubject) return false;
    final hasUserIntent = const [
      '我也',
      '我自己',
      '我有想',
      '我想死',
      '我想自殺',
      '我想自s',
      '我不想活',
      '我想傷害自己',
    ].any(clause.contains);
    return !hasUserIntent;
  }

  static const safetyKeywords = [
    '不想活了',
    '不想活',
    '好想死',
    '想死',
    '去死',
    '不想醒來',
    '希望不要醒來',
    '活不下去',
    '想消失',
    '想結束生命',
    '結束自己',
    '想自殺',
    '傷害自己',
    '自殺',
    '想自s',
    '自s',
    '自傷',
    '自殘',
    '割自己',
    '輕生',
    '割腕',
    '跳樓',
    '吞藥',
  ];

  static const _otherSubjectTerms = [
    '朋友',
    '同學',
    '同事',
    '家人',
    '爸爸',
    '媽媽',
    '弟弟',
    '妹妹',
    '哥哥',
    '姐姐',
    '姊姊',
    '男友',
    '女友',
    '伴侶',
    '他說',
    '她說',
    '他想',
    '她想',
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
