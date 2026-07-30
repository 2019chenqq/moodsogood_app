import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_message.dart';
import 'package:moodsogood_app/ai/widgets/ai_message_bubble.dart';

void main() {
  InneraAiMessage message(InneraAiMessageRole role, String text) {
    return InneraAiMessage(
      id: '${role.name}-$text',
      role: role,
      text: text,
      createdAt: DateTime(2026, 7, 29),
    );
  }

  Widget subject(List<InneraAiMessage> messages) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final item in messages) AiMessageBubble(message: item),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('使用者訊息與頭貼靠右，AI 回覆靠左，文字都靠左', (tester) async {
    const userText = '使用者測試訊息';
    const assistantText = 'AI回覆測試訊息';

    await tester.pumpWidget(
      subject([
        message(InneraAiMessageRole.user, userText),
        message(InneraAiMessageRole.assistant, assistantText),
      ]),
    );

    final userWidget = tester.widget<Text>(find.text(userText));
    final assistantWidget = tester.widget<Text>(find.text(assistantText));
    expect(
      tester.getCenter(find.text(userText)).dx,
      greaterThan(tester.getCenter(find.text(assistantText)).dx),
    );
    expect(userWidget.textAlign, TextAlign.left);
    expect(assistantWidget.textAlign, TextAlign.left);
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets('連續長字串會在訊息框內換行而不溢位', (tester) async {
    final longText = 'https://example.com/${'very-long-segment' * 30}';

    await tester.pumpWidget(
      subject([message(InneraAiMessageRole.user, longText)]),
    );

    expect(find.text(longText), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text(longText)).width, lessThan(400));
  });
}
