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
    displayName: '能量變化',
    question: '今天的能量和平常相比如何？',
    lowLabel: '明顯降低',
    middleLabel: '和平常差不多',
    highLabel: '明顯增加',
    aliases: ['很有精神', '精神很好', '精神變好', '精力充沛', '沒精神', '沒有力氣', '提不起勁', '精神很差'],
  ),
  DailyStateDimensionDefinition(
    id: 'appetite_change',
    displayName: '食慾變化',
    question: '今天的食慾和平常相比如何？',
    lowLabel: '明顯降低',
    middleLabel: '和平常差不多',
    highLabel: '明顯增加',
    aliases: ['很想吃東西', '一直想吃', '食慾很好', '食慾變大', '沒有胃口', '吃不下', '食慾變差'],
  ),
  DailyStateDimensionDefinition(
    id: 'activity_change',
    displayName: '活動量變化',
    question: '今天的活動量和平常相比如何？',
    lowLabel: '明顯減少',
    middleLabel: '和平常差不多',
    highLabel: '明顯增加',
    aliases: ['一直做事情', '停不下來', '活動變多', '整天躺著', '不想動', '活動變少'],
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
      return dimension.id == 'activity_change' ? '稍微減少' : '稍微降低';
    case 3:
      return dimension.middleLabel;
    case 4:
      return '稍微增加';
    case 5:
      return dimension.highLabel;
    default:
      return '尚未填寫';
  }
}
