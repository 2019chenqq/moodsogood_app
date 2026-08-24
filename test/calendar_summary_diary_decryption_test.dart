import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/services/calendar_summary_service.dart';

void main() {
  test('encrypted diary title is decrypted before display', () {
    final title = CalendarSummaryService.decodeDiaryFieldForDisplay(
      'ciphertext',
      isEncrypted: true,
      decrypt: (_) => '今天的日記',
    );

    expect(title, '今天的日記');
  });

  test('encrypted diary ciphertext is hidden when key is unavailable', () {
    final title = CalendarSummaryService.decodeDiaryFieldForDisplay(
      '+T6KfDOUaLkKh5vT:oNdRJ2iEaktkzriImRu2yFJgoDCDvpcLEETcag==',
      isEncrypted: true,
    );

    expect(title, isNull);
  });

  test('legacy plaintext diary title remains readable', () {
    final title = CalendarSummaryService.decodeDiaryFieldForDisplay(
      '舊版日記',
      isEncrypted: false,
    );

    expect(title, '舊版日記');
  });

  test('failed diary decryption never exposes ciphertext', () {
    final title = CalendarSummaryService.decodeDiaryFieldForDisplay(
      'ciphertext',
      isEncrypted: true,
      decrypt: (_) => null,
    );

    expect(title, isNull);
  });
}
