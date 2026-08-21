import '../models/follow_up_ai_summary.dart';

enum FollowUpSummarySectionId {
  basicInfo,
  discussion,
  keyChanges,
  sleep,
  cooccurrence,
  bodyMeasurements,
  medicationTimeline,
  additionalNotes,
  dataLimitations,
}

class FollowUpSummarySection {
  const FollowUpSummarySection({
    required this.id,
    required this.title,
    required this.items,
    this.labels = const [],
  });

  final FollowUpSummarySectionId id;
  final String title;
  final List<String> items;
  final List<String> labels;
}

class FollowUpSummarySectionBuilder {
  const FollowUpSummarySectionBuilder._();

  static List<FollowUpSummarySection> fromDisplay(
    FollowUpSummaryDisplayModel display,
  ) {
    final candidates = <FollowUpSummarySection>[
      FollowUpSummarySection(
        id: FollowUpSummarySectionId.basicInfo,
        title: '基本資訊',
        items: display.visitInfo,
      ),
      FollowUpSummarySection(
        id: FollowUpSummarySectionId.discussion,
        title: '想跟醫師討論的事',
        items: display.discussionItems,
        labels: display.topicLabels,
      ),
      FollowUpSummarySection(
        id: FollowUpSummarySectionId.keyChanges,
        title: '主要變化',
        items: display.keyChanges,
      ),
      FollowUpSummarySection(
        id: FollowUpSummarySectionId.sleep,
        title: '睡眠趨勢',
        items: display.sleepSummaryItems,
      ),
      FollowUpSummarySection(
        id: FollowUpSummarySectionId.cooccurrence,
        title: '症狀與情緒共現模式',
        items: display.symptoms,
      ),
      FollowUpSummarySection(
        id: FollowUpSummarySectionId.bodyMeasurements,
        title: '身體測量',
        items: display.bodyMeasurements,
      ),
      FollowUpSummarySection(
        id: FollowUpSummarySectionId.medicationTimeline,
        title: '藥物調整時間軸',
        items: display.medicationTimeline,
      ),
      FollowUpSummarySection(
        id: FollowUpSummarySectionId.additionalNotes,
        title: '其他想跟醫師說的內容',
        items: display.userSharedNotes,
      ),
      FollowUpSummarySection(
        id: FollowUpSummarySectionId.dataLimitations,
        title: '資料限制',
        items: display.dataLimitations,
      ),
    ];
    return candidates
        .where((section) =>
            section.id == FollowUpSummarySectionId.basicInfo ||
            section.items.isNotEmpty ||
            section.labels.isNotEmpty ||
            (section.id == FollowUpSummarySectionId.sleep &&
                display.sleepTrend.isNotEmpty))
        .toList(growable: false);
  }

  static List<String> cooccurrenceItems(
    Iterable<Map<String, dynamic>> values,
  ) {
    String compact(num value) => value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    final items = values
        .map((value) {
          final names = value['items'] is Iterable
              ? (value['items'] as Iterable)
                  .map((item) => item.toString().trim())
                  .where((item) => item.isNotEmpty)
                  .toList()
              : const <String>[];
          final count = value['coOccurrenceCount'];
          if (names.length < 2 || count is! num || count <= 0) return '';
          final averages = value['averageValues'] is Map
              ? Map<String, dynamic>.from(value['averageValues'] as Map)
              : const <String, dynamic>{};
          final details = names
              .where((name) => averages[name] is num)
              .map((name) => '$name平均 ${compact(averages[name] as num)}/5')
              .join('、');
          return _sentence(
            '${names.join('與')}共同記錄 ${count.toInt()} 次'
            '${details.isEmpty ? '' : '（$details）'}',
          );
        })
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
    if (items.isNotEmpty) {
      items.add('共現僅代表同次記錄中共同出現，不代表因果關係。');
    }
    return items;
  }

  static String _sentence(String value) =>
      RegExp(r'[。！？；]$').hasMatch(value.trim())
          ? value.trim()
          : '${value.trim()}。';
}
