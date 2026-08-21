import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_safety_service.dart';

void main() {
  final service = InneraAiSafetyService();

  group('InneraAiSafetyService self-harm safety layer', () {
    test('detects direct wish not to live', () {
      final result = service.assess('我今天真的不想活了');

      expect(result.level, AiSafetyLevel.possibleSelfHarm);
      expect(result.matchedTerms, contains('不想活了'));
    });

    test('detects recurring thoughts of death', () {
      final result = service.assess('最近一直有想死的念頭');

      expect(result.level, AiSafetyLevel.possibleSelfHarm);
      expect(result.matchedTerms, contains('想死'));
    });

    test('detects simple evasion spelling', () {
      final result = service.assess('我想自S');

      expect(result.level, AiSafetyLevel.possibleSelfHarm);
      expect(result.matchedTerms, contains('想自s'));
    });

    test('does not flag an explicit negation', () {
      final result = service.assess('我沒有想死，只是今天很累');

      expect(result.level, AiSafetyLevel.normal);
    });

    test('does not treat a third person statement as the user intent', () {
      final result = service.assess('我朋友最近一直說他想自殺');

      expect(result.level, AiSafetyLevel.normal);
    });

    test('does not flag a general prevention hotline question', () {
      final result = service.assess('自殺防治專線是多少？');

      expect(result.level, AiSafetyLevel.normal);
    });

    test('handles spaces and letter case in simple evasion spelling', () {
      final result = service.assess('我 想 自 s');

      expect(result.level, AiSafetyLevel.possibleSelfHarm);
    });

    test('handles full-width letter evasion spelling', () {
      final result = service.assess('我想自Ｓ');

      expect(result.level, AiSafetyLevel.possibleSelfHarm);
    });

    test('raises urgent level when immediate timing is present', () {
      final result = service.assess('我現在就想傷害自己');

      expect(result.level, AiSafetyLevel.imminentDanger);
    });
  });
}
