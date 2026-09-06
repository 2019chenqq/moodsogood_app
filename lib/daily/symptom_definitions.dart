class CanonicalSymptomDefinition {
  const CanonicalSymptomDefinition({
    required this.id,
    required this.displayName,
    required this.category,
  });

  final String id;
  final String displayName;
  final String category;
}

const List<CanonicalSymptomDefinition> kCanonicalSymptoms = [
  CanonicalSymptomDefinition(
    id: 'palpitation',
    displayName: '心悸',
    category: 'cardiovascular',
  ),
  CanonicalSymptomDefinition(
    id: 'tremor',
    displayName: '手抖',
    category: 'neuromuscular',
  ),
  CanonicalSymptomDefinition(
    id: 'nausea',
    displayName: '噁心反胃',
    category: 'digestive',
  ),
  CanonicalSymptomDefinition(
    id: 'abdominal_pain',
    displayName: '胃痛',
    category: 'digestive',
  ),
  CanonicalSymptomDefinition(
    id: 'headache',
    displayName: '頭痛',
    category: 'head',
  ),
  CanonicalSymptomDefinition(
    id: 'dizziness',
    displayName: '頭暈',
    category: 'head',
  ),
  CanonicalSymptomDefinition(
    id: 'chest_tightness',
    displayName: '胸悶',
    category: 'cardiovascular',
  ),
  CanonicalSymptomDefinition(
    id: 'fatigue',
    displayName: '疲倦',
    category: 'general',
  ),
  CanonicalSymptomDefinition(
    id: 'daytime_sleepiness',
    displayName: '白天嗜睡',
    category: 'general',
  ),
];

final Map<String, CanonicalSymptomDefinition> kCanonicalSymptomsById = {
  for (final concept in kCanonicalSymptoms) concept.id: concept,
};

final Map<String, CanonicalSymptomDefinition> kCanonicalSymptomsByDisplayName =
    {
  for (final concept in kCanonicalSymptoms) concept.displayName: concept,
};

CanonicalSymptomDefinition? resolveCanonicalSymptom(String value) {
  final text = value.trim();
  return kCanonicalSymptomsById[text] ?? kCanonicalSymptomsByDisplayName[text];
}

String? resolveCanonicalSymptomId(String value) =>
    resolveCanonicalSymptom(value)?.id;

const Map<String, List<String>> kSymptomCategories = {
  '心血管與呼吸': ['心悸', '胸悶', '胸痛', '呼吸困難', '過度換氣'],
  '消化系統': [
    '胃食道逆流',
    '胃痛',
    '腹痛',
    '腹瀉',
    '便秘',
    '噁心反胃',
    '嘔吐',
    '脹氣',
    '容易飢餓',
    '一直想吃東西',
    '吃完仍不滿足',
    '食慾降低',
    '很快就飽',
  ],
  '頭部': ['頭暈', '頭痛', '頭脹'],
  '眼睛與耳朵': ['眼睛乾澀', '眼睛疲勞', '視力模糊', '不斷流淚', '耳鳴'],
  '口腔與咽喉': ['口乾舌燥', '味覺失調', '口腔苦澀', '咽喉異物感'],
  '四肢與肌肉': ['顫抖', '發麻', '手汗變多', '肌肉緊繃', '肌肉抽搐'],
  '全身狀態': ['疲倦', '白天嗜睡', '身體沉重', '四肢無力', '頭重腳輕', '動力不足'],
};

final Set<String> kPresetSymptoms =
    kSymptomCategories.values.expand((items) => items).toSet();

const Map<String, String> kLegacySymptomAliases = {
  '呼吸不順': '呼吸困難',
  '食慾不振': '食慾降低',
  '食慾下降': '食慾降低',
  '睏倦': '白天嗜睡',
  '嗜睡': '白天嗜睡',
  '肌肉抽蓄': '肌肉抽搐',
  '肌肉不自主抽動': '肌肉抽搐',
  '想吐': '噁心反胃',
  '食慾增加': '一直想吃東西',
};

String normalizeSymptomName(String name) {
  final trimmed = name.trim();
  return kLegacySymptomAliases[trimmed] ?? trimmed;
}
