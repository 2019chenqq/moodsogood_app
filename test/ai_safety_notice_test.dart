import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_safety_service.dart';
import 'package:moodsogood_app/ai/widgets/ai_safety_notice.dart';

void main() {
  testWidgets('concern safety card shows every support phone number',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiSafetyNotice(
              level: AiSafetyLevel.possibleSelfHarm,
              onTemporarilySafe: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('撥打 1925 安心專線'), findsOneWidget);
    expect(find.text('119 緊急救護'), findsOneWidget);
    expect(find.text('110 警察'), findsOneWidget);
    expect(find.text('1925 安心專線'), findsOneWidget);
    expect(find.text('1995 生命線'), findsOneWidget);
    expect(find.text('1980 張老師'), findsOneWidget);
    expect(find.textContaining('1985'), findsNothing);
  });

  testWidgets('urgent safety card prioritizes emergency help', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiSafetyNotice(
              level: AiSafetyLevel.imminentDanger,
              onTemporarilySafe: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('撥打 119 緊急救護'), findsOneWidget);
    expect(find.text('110 警察'), findsOneWidget);
  });
}
