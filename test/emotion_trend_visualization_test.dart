import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/emotion_trend_calculator.dart';
import 'package:moodsogood_app/daily/widgets/history_chart_widget.dart';

void main() {
  group('EmotionTrendPointPresentation', () {
    test('shows a multi-event 5-point range and complete tooltip', () {
      final presentation = EmotionTrendPointPresentation(
        _point(
          mainValue: 3,
          source: DailyEmotionMainSource.dailyCheckIn,
          range: const QuickRecordEmotionRange(min: 2, max: 5, count: 3),
        ),
      );

      expect(presentation.showsRangeIndicator, isTrue);
      expect(
        presentation.tooltipLines(
          label: '整體情緒',
          displayedValue: 3,
          showsTrendValue: false,
        ),
        containsAll(<String>[
          '整體情緒：3.0/5',
          '代表值來源：每日基準',
          '快速記錄範圍：2.0–5.0',
          '快速記錄：3筆',
        ]),
      );
    });

    test('identifies a QuickRecord-only fallback value', () {
      final presentation = EmotionTrendPointPresentation(
        _point(
          mainValue: 3,
          source: DailyEmotionMainSource.quickRecordFallback,
          range: const QuickRecordEmotionRange(min: 2, max: 4, count: 2),
        ),
      );

      expect(presentation.showsRangeIndicator, isTrue);
      expect(
        presentation.tooltipLines(
          label: '平靜',
          displayedValue: 3,
          showsTrendValue: false,
        ),
        contains('代表值來源：快速記錄平均'),
      );
    });

    test('single event keeps its count but suppresses the range line', () {
      final presentation = EmotionTrendPointPresentation(
        _point(
          mainValue: 4,
          range: const QuickRecordEmotionRange(min: 4, max: 4, count: 1),
        ),
      );

      expect(presentation.showsRangeIndicator, isFalse);
      final lines = presentation.tooltipLines(
        label: '平靜',
        displayedValue: 4,
        showsTrendValue: false,
      );
      expect(lines, contains('快速記錄：1筆'));
      expect(lines.where((line) => line.contains('快速記錄範圍')), isEmpty);
    });

    test('equal min and max suppress an abnormal zero-height line', () {
      final presentation = EmotionTrendPointPresentation(
        _point(
          mainValue: 3,
          range: const QuickRecordEmotionRange(min: 3, max: 3, count: 2),
        ),
      );

      expect(presentation.showsRangeIndicator, isFalse);
    });

    test('10-point presentation never draws a QuickRecord range', () {
      final presentation = EmotionTrendPointPresentation(
        _point(
          mainValue: 8,
          scale: 10,
          range: const QuickRecordEmotionRange(min: 2, max: 5, count: 3),
        ),
      );

      expect(presentation.showsRangeIndicator, isFalse);
    });

    test('moving-average tooltip keeps main and trend values separate', () {
      final presentation = EmotionTrendPointPresentation(
        _point(mainValue: 4),
      );

      expect(
        presentation.tooltipLines(
          label: '平靜',
          displayedValue: 3.5,
          showsTrendValue: true,
        ),
        contains('趨勢值：3.5'),
      );
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('chart renders in ${brightness.name} theme with range data',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 320,
              child: HistoryChartWidget(
                records: const [],
                fullRecords: const [],
                useMovingAverage: false,
                dailyEmotionPoints: [
                  _point(
                    mainValue: 3,
                    range: const QuickRecordEmotionRange(
                      min: 2,
                      max: 5,
                      count: 3,
                    ),
                  ),
                ],
                fullDailyEmotionPoints: [
                  _point(
                    mainValue: 3,
                    range: const QuickRecordEmotionRange(
                      min: 2,
                      max: 5,
                      count: 3,
                    ),
                  ),
                ],
                targetEmotion: '平靜',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(HistoryChartWidget), findsOneWidget);
    });
  }
}

DailyEmotionValuePoint _point({
  required double mainValue,
  int scale = 5,
  DailyEmotionMainSource source = DailyEmotionMainSource.dailyRecord,
  QuickRecordEmotionRange? range,
}) =>
    DailyEmotionValuePoint(
      date: DateTime(2026, 8, 11),
      emotionName: '平靜',
      mainValue: mainValue,
      scale: scale,
      source: source,
      quickRecordRange: range,
    );
