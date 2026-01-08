class EmotionItem {
  final String name;
  final int? value; // 0~10
  EmotionItem(this.name, {this.value});

  EmotionItem copyWith({String? name, int? value}) =>
      EmotionItem(name ?? this.name, value: value ?? this.value);
}
