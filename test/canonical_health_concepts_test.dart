import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_health_event_draft.dart';
import 'package:moodsogood_app/daily/emotion_dimensions.dart';
import 'package:moodsogood_app/daily/symptom_definitions.dart';

void main() {
  test('canonical symptom ids and display names are unique', () {
    expect(
      kCanonicalSymptoms.map((item) => item.id).toSet(),
      hasLength(kCanonicalSymptoms.length),
    );
    expect(
      kCanonicalSymptoms.map((item) => item.displayName).toSet(),
      hasLength(kCanonicalSymptoms.length),
    );
  });

  test('legacy canonical symptom name resolves to its canonical id', () {
    final draft = InneraAiHealthEventDraft.fromMap({
      'id': 'legacy',
      'symptoms': [
        {'name': '心悸', 'severity': 3},
      ],
    });
    final symptom = (draft.toMap()['symptoms'] as List).single as Map;

    expect(draft.symptoms, ['心悸']);
    expect(symptom['canonicalId'], 'palpitation');
    expect(symptom['displayName'], '心悸');
    expect(symptom['severity'], 3);
  });

  test('unknown legacy symptom remains readable and unresolved', () {
    final draft = InneraAiHealthEventDraft.fromMap({
      'id': 'legacy-unknown',
      'symptoms': [
        {'name': '未知症狀', 'severity': null},
      ],
    });
    final symptom = (draft.toMap()['symptoms'] as List).single as Map;

    expect(draft.symptoms, ['未知症狀']);
    expect(symptom['name'], '未知症狀');
    expect(symptom['canonicalId'], isNull);
    expect(symptom['displayName'], isNull);
  });

  test('canonical registry does not resolve natural-language aliases', () {
    expect(resolveCanonicalSymptomId('嗜睡'), isNull);
    expect(resolveCanonicalSymptomId('很睏'), isNull);
  });

  test('canonical emotions reuse the existing formal dimensions', () {
    expect(identical(kCanonicalEmotionRegistry, kEmotionDimensions), isTrue);
    expect(
      kCanonicalEmotionRegistry.map((item) => item.id).toList(),
      kEmotionDimensions.map((item) => item.id).toList(),
    );
    expect(
      kCanonicalEmotionRegistry.map((item) => item.displayName).toList(),
      kEmotionDimensions.map((item) => item.displayName).toList(),
    );
  });
}
