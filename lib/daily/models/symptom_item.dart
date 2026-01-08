class SymptomItem {
  final String name;

  SymptomItem({required this.name});

  SymptomItem copyWith({String? name}) => SymptomItem(name: name ?? this.name);
}
