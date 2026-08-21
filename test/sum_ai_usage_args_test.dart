import 'package:flutter_test/flutter_test.dart';

import '../tool/sum_ai_usage.dart';

void main() {
  group('parseAiUsageArguments', () {
    test('accepts space-separated values', () {
      final options = parseAiUsageArguments([
        '--startDate',
        '2026-08-01',
        '--endDate',
        '2026-08-17',
      ]);

      expect(options.startDate, '2026-08-01');
      expect(options.endDate, '2026-08-17');
      expect(options.projectId, 'moodsogood-9e45b');
      expect(options.accessToken, isNull);
    });

    test('accepts equals-separated values and optional arguments', () {
      final options = parseAiUsageArguments([
        '--startDate=2026-08-01',
        '--endDate=2026-08-17',
        '--projectId=test-project',
        '--accessToken=test-token',
      ]);

      expect(options.startDate, '2026-08-01');
      expect(options.endDate, '2026-08-17');
      expect(options.projectId, 'test-project');
      expect(options.accessToken, 'test-token');
    });

    test('requires startDate', () {
      expect(
        () => parseAiUsageArguments(['--endDate', '2026-08-17']),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires endDate', () {
      expect(
        () => parseAiUsageArguments(['--startDate=2026-08-01']),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
