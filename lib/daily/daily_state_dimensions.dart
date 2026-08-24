class DailyStateDimensionDefinition {
  const DailyStateDimensionDefinition({
    required this.id,
    required this.displayName,
    required this.question,
    required this.lowLabel,
    required this.middleLabel,
    required this.highLabel,
    this.aliases = const [],
  });

  final String id;
  final String displayName;
  final String question;
  final String lowLabel;
  final String middleLabel;
  final String highLabel;
  final List<String> aliases;
}

const List<DailyStateDimensionDefinition> kDailyStateDimensions = [
  DailyStateDimensionDefinition(
    id: 'energy_change',
    displayName: '能量',
    question: '當時的能量程度如何？',
    lowLabel: '非常低',
    middleLabel: '中等',
    highLabel: '非常高',
    aliases: [
      '能量變化',
      '很有精神',
      '精神很好',
      '精神變好',
      '精力充沛',
      '沒精神',
      '沒有力氣',
      '提不起勁',
      '精神很差'
    ],
  ),
  DailyStateDimensionDefinition(
    id: 'appetite_change',
    displayName: '食慾',
    question: '當時的食慾程度如何？',
    lowLabel: '非常低',
    middleLabel: '中等',
    highLabel: '非常高',
    aliases: ['食慾變化', '很想吃東西', '一直想吃', '食慾很好', '食慾變大', '沒有胃口', '吃不下', '食慾變差'],
  ),
  DailyStateDimensionDefinition(
    id: 'activity_change',
    displayName: '活動量',
    question: '當時的活動量程度如何？',
    lowLabel: '非常低',
    middleLabel: '中等',
    highLabel: '非常高',
    aliases: ['活動量變化', '一直做事情', '停不下來', '活動變多', '整天躺著', '不想動', '活動變少'],
  ),
];

final Map<String, DailyStateDimensionDefinition> kDailyStateDimensionsById = {
  for (final dimension in kDailyStateDimensions) dimension.id: dimension,
};

DailyStateDimensionDefinition? resolveDailyStateDimension(String rawText) {
  final text = rawText.trim();
  for (final dimension in kDailyStateDimensions) {
    if (dimension.id == text ||
        dimension.displayName == text ||
        dimension.aliases.contains(text)) {
      return dimension;
    }
  }
  return null;
}

String dailyStateValueLabel(
    DailyStateDimensionDefinition dimension, int value) {
  switch (value) {
    case 1:
      return dimension.lowLabel;
    case 2:
      return '偏低';
    case 3:
      return dimension.middleLabel;
    case 4:
      return '偏高';
    case 5:
      return dimension.highLabel;
    default:
      return '尚未填寫';
  }
}
