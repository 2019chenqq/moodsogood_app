import 'package:flutter/material.dart';
import '../daily/models/local_record.dart';

class TrendRangeOption {
  final int? days;
  final String label;

  const TrendRangeOption({required this.days, required this.label});
}

const kTrendRangeOptions = [
  TrendRangeOption(days: 7,   label: '近 7 天'),
  TrendRangeOption(days: 30,  label: '近 30 天'),
  TrendRangeOption(days: 90,  label: '近 90 天'),
  TrendRangeOption(days: null, label: '全部'),
];

class TrendRangeSelector extends StatelessWidget {
  final int? selectedDays;
  final ValueChanged<int?> onChanged;

  const TrendRangeSelector({
    super.key,
    required this.selectedDays,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: kTrendRangeOptions.map((opt) {
          final isSelected = selectedDays == opt.days;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(opt.label),
              selected: isSelected,
              onSelected: (_) => onChanged(opt.days),
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).textTheme.bodyMedium?.color,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 計算圖表用的資料點
/// - 7 天：每日原始分數
/// - 其他：7 天移動平均
List<MapEntry<DateTime, double>> buildChartData(
  List<LocalRecord> records,
  int? days,
) {
  final filtered = records
      .where((r) => r.overallMood != null)
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  if (filtered.isEmpty) return [];

  if (days == 7) {
    return filtered
        .map((r) => MapEntry(r.date, r.overallMood!))
        .toList();
  }

  const windowSize = 7;
  final result = <MapEntry<DateTime, double>>[];

  for (int i = 0; i < filtered.length; i++) {
    final start = i - windowSize + 1 < 0 ? 0 : i - windowSize + 1;
    final window = filtered.sublist(start, i + 1);
    final avg = window.map((r) => r.overallMood!).reduce((a, b) => a + b) /
        window.length;
    result.add(MapEntry(filtered[i].date, avg));
  }

  return result;
}