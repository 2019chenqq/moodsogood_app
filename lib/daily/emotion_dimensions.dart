class EmotionDimensionDefinition {
  const EmotionDimensionDefinition({
    required this.id,
    required this.displayName,
    this.aliases = const [],
    this.isCustom = false,
    this.isLegacy = false,
  });

  final String id;
  final String displayName;
  final List<String> aliases;
  final bool isCustom;
  final bool isLegacy;
}

/// The single source of truth for emotion choices used by new daily records.
const Map<String, List<String>> kEmotionCheckboxCategories = {
  '喜悅': [
    '快樂',
    '興奮',
    '愉悅',
    '滿足',
    '自在',
    '平靜',
    '放鬆',
    '安心',
    '期待',
    '自信',
    '感恩',
    '幸福',
    '有希望'
  ],
  '厭惡': ['厭倦', '無聊', '反感', '煩悶', '排斥', '討厭'],
  '悲傷': ['低落', '憂鬱', '孤單', '絕望', '沮喪', '難過', '失落', '空虛', '無助', '麻木'],
  '恐懼': ['緊張', '擔心', '惶恐', '焦慮', '害怕', '警覺', '恐懼', '忐忑不安'],
  '憤怒': ['生氣', '憤怒', '暴躁', '忌妒', '煩躁', '不耐煩', '惱羞成怒'],
  '危險警訊': ['自殺意念'],
};

const Map<String, List<String>> kEmotionDimensionAliases = {
  '興奮': ['很嗨', '亢奮'],
  '無聊': ['好無聊', '無趣'],
  '空虛': ['很空', '心裡空空的', '心中空空的'],
  '焦慮': ['坐立難安'],
  '難過': ['傷心', '想哭'],
  '孤單': ['孤獨', '沒有人陪'],
  '煩躁': ['很煩'],
};

final List<EmotionDimensionDefinition> kEmotionDimensions = List.unmodifiable(
  kEmotionCheckboxCategories.values.expand(
    (names) => names.map(
      (name) => EmotionDimensionDefinition(
        id: name,
        displayName: name,
        aliases: kEmotionDimensionAliases[name] ?? const [],
      ),
    ),
  ),
);

final List<String> kEmotionCheckboxNames = List.unmodifiable(
  kEmotionDimensions.map((dimension) => dimension.displayName),
);

final Map<String, EmotionDimensionDefinition> kEmotionDimensionsById = {
  for (final dimension in kEmotionDimensions) dimension.id: dimension,
};

final Map<String, EmotionDimensionDefinition> kEmotionDimensionsByName = {
  for (final dimension in kEmotionDimensions) dimension.displayName: dimension,
};

EmotionDimensionDefinition? resolveEmotionDimension(String rawText) {
  final text = rawText.trim();
  final exact = kEmotionDimensionsByName[text];
  if (exact != null) return exact;
  for (final dimension in kEmotionDimensions) {
    if (dimension.aliases.contains(text)) return dimension;
  }
  return null;
}

/// Read-only compatibility for records created before the current dimensions.
/// AI extraction and new-record writes must never use this map.
const Map<String, String?> kLegacyEmotionDimensionMap = {
  '空虛程度': '空虛',
  '無聊程度': '無聊',
  '難過程度': '難過',
  '開心程度': '快樂',
  '焦慮程度': '焦慮',
  '憂鬱程度': '憂鬱',
  '無望感': '絕望',
  '孤獨感': '孤單',
  '興奮程度': '興奮',
  '疲憊程度': null,
  '動力': null,
  '能量': null,
};
