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
