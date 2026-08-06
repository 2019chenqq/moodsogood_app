import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/pages/trend_review_hub_page.dart';

void main() {
  testWidgets('trend review groups the three analysis tools', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: TrendReviewHubPage()),
    );

    expect(find.text('趨勢回顧'), findsOneWidget);
    expect(find.text('睡眠洞察'), findsOneWidget);
    expect(find.text('情緒趨勢'), findsOneWidget);
    expect(find.text('症狀比對'), findsOneWidget);
  });
}
