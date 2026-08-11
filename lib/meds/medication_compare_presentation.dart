import 'med_symptom_compare_models.dart';
import 'medication_subjective_response.dart';

/// UI-only formatting for an already calculated medication comparison.
/// No health records or events are counted here.
class MedicationCompareMetricPresentation {
  const MedicationCompareMetricPresentation(this.result);

  final CompareMetricResult result;

  String get primaryOccurrenceLine =>
      '調整前 ${_days(result.beforePresentDays, result.beforeRecordedDays)}'
      ' → 調整後 ${_days(result.afterPresentDays, result.afterRecordedDays)}';

  List<String> get symptomDetailLines {
    if (result.kind != CompareMetricKind.symptom) return const [];
    final lines = <String>[
      '發生率：${_percent(result.beforeOccurrenceRate)} → '
          '${_percent(result.afterOccurrenceRate)}',
    ];
    if (result.beforeEventCount > 0 || result.afterEventCount > 0) {
      lines.add(
        '快速記錄：${result.beforeEventCount}次 → ${result.afterEventCount}次',
      );
    }
    if (_hasScore(result.beforeAverageScore) ||
        _hasScore(result.afterAverageScore)) {
      lines.add(
        '平均強度：${_severity(result.beforeAverageScore)} → '
        '${_severity(result.afterAverageScore)}',
      );
    }
    if (_hasScore(result.beforeMaximumScore) ||
        _hasScore(result.afterMaximumScore)) {
      lines.add(
        '最高強度：${_severity(result.beforeMaximumScore)} → '
        '${_severity(result.afterMaximumScore)}',
      );
    }
    return lines;
  }

  static bool _hasScore(double? value) => value != null && value.isFinite;

  static String _days(int occurrenceDays, int recordedDays) =>
      recordedDays > 0 ? '$occurrenceDays/$recordedDays 天' : '資料不足';

  static String _severity(double? value) =>
      _hasScore(value) ? '${value!.toStringAsFixed(1)}/5' : '未記錄';

  static String _percent(double? value) =>
      value != null && value.isFinite ? '${value.toStringAsFixed(1)}%' : '資料不足';
}

class MedicationSubjectiveResponsePresentation {
  const MedicationSubjectiveResponsePresentation(this.response);

  final MedicationSubjectiveResponse response;

  String get title => 'Day ${response.followUpDay}｜$overallLabel';

  String get overallLabel => switch (response.overallResponse) {
        MedicationOverallResponse.better => '感覺較好',
        MedicationOverallResponse.worse => '感覺較差',
        MedicationOverallResponse.mixed => '好壞皆有',
        MedicationOverallResponse.noChange => '沒有明顯變化',
        MedicationOverallResponse.unsure => '不確定',
      };

  List<String> get detailLines => [
        if (response.changedAreas.isNotEmpty)
          '主觀變化：${response.changedAreas.join('、')}',
        if (response.otherFactors.isNotEmpty)
          '其他可能影響因素：${response.otherFactors.join('、')}',
        if (response.note.trim().isNotEmpty) '備註：${response.note.trim()}',
      ];
}
