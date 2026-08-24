import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_service.dart';

void main() {
  test('does not append the exact same follow-up twice', () {
    expect(
      inneraAiDisplayText('這大約是什麼時候發生的？', '這大約是什麼時候發生的？'),
      '這大約是什麼時候發生的？',
    );
  });

  test('does not append a semantically duplicate topic question', () {
    expect(
      inneraAiDisplayText('當時大概有多痛？', '如果用 1～5 分表示，程度大約幾分？'),
      '當時大概有多痛？',
    );
  });

  test('keeps one distinct follow-up when reply contains no question', () {
    expect(
      inneraAiDisplayText('我先幫你把下午頭痛這件事保留下來。', '大概是幾點開始的？'),
      '我先幫你把下午頭痛這件事保留下來。\n\n大概是幾點開始的？',
    );
  });
}
