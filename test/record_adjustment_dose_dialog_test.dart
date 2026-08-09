import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/record_adjustment_page.dart';

void main() {
  testWidgets('oral dose dialog owns controllers through route teardown',
      (tester) async {
    MedicationOralDoseEditResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showDialog<MedicationOralDoseEditResult>(
                  context: context,
                  builder: (_) => const MedicationOralDoseEditorDialog(
                    initialDosePerUnit: 50,
                    initialPillCount: 1,
                    initialUnit: 'mg',
                  ),
                );
              },
              child: const Text('開啟口服劑量'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('開啟口服劑量'));
    await tester.pumpAndSettle();
    expect(find.text('調整後用量'), findsOneWidget);
    expect(find.text('每次總量：50 mg × 1 顆 = 50 mg'), findsOneWidget);

    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result?.dosePerUnit, 50);
    expect(result?.pillCount, 1);
    expect(result?.unit, 'mg');
  });

  testWidgets('general dose dialog can cancel without lifecycle errors',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<MedicationDoseEditResult>(
                context: context,
                builder: (_) => const MedicationDoseEditorDialog(
                  initialDose: 0.5,
                  initialUnit: 'mg',
                ),
              ),
              child: const Text('開啟一般劑量'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('開啟一般劑量'));
    await tester.pumpAndSettle();
    expect(find.text('輸入調整後劑量'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('輸入調整後劑量'), findsNothing);
  });
}
