import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/ai_callable_diagnostics.dart';

void main() {
  FirebaseFunctionsException error(String code, {String message = ''}) =>
      FirebaseFunctionsException(code: code, message: message);

  test('callable errors are not all reported as undeployed', () {
    expect(
      aiCallableErrorMessage(
        error('not-found'),
        functionName: AiCallableEndpoints.diaryDraft,
      ),
      contains('後端不存在'),
    );
    expect(
      aiCallableErrorMessage(
        error('unavailable'),
        functionName: AiCallableEndpoints.diaryDraft,
      ),
      contains('網路'),
    );
    expect(
      aiCallableErrorMessage(
        error('permission-denied'),
        functionName: AiCallableEndpoints.diaryDraft,
      ),
      contains('App Check'),
    );
    expect(
      aiCallableErrorMessage(
        error('deadline-exceeded'),
        functionName: AiCallableEndpoints.diaryDraft,
      ),
      contains('逾時'),
    );
  });

  test('unknown callable errors retain their code', () {
    expect(
      aiCallableErrorMessage(
        error('data-loss'),
        functionName: AiCallableEndpoints.chat,
      ),
      contains('data-loss'),
    );
  });
}
