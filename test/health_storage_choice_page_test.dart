import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/privacy/health_storage_choice_page.dart';
import 'package:moodsogood_app/utils/firebase_sync_config.dart';

void main() {
  testWidgets('explains both storage choices and confirms selection',
      (tester) async {
    HealthStorageMode? confirmedMode;
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HealthStorageChoicePage(
          onConfirm: (mode) async {
            confirmedMode = mode;
          },
        ),
      ),
    );

    expect(find.text('只存本機'), findsOneWidget);
    expect(find.text('加密雲端同步'), findsOneWidget);
    expect(find.textContaining('未來可以改用加密雲端同步'), findsOneWidget);
    expect(find.textContaining('PIN 與復原金鑰'), findsOneWidget);
    expect(find.textContaining('使用 AI 前會另外詢問'), findsOneWidget);

    await tester.tap(find.byKey(const Key('local_storage_option')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('confirm_storage_mode')));
    await tester.tap(find.byKey(const Key('confirm_storage_mode')));
    await tester.pumpAndSettle();

    expect(confirmedMode, HealthStorageMode.localOnly);
  });
}
