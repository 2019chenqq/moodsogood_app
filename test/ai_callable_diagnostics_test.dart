import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
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
        isSignedIn: true,
      ),
      contains('後端不存在'),
    );
    expect(
      aiCallableErrorMessage(
        error('unavailable'),
        functionName: AiCallableEndpoints.diaryDraft,
        isSignedIn: true,
      ),
      contains('網路'),
    );
    expect(
      aiCallableErrorMessage(
        error('permission-denied', message: 'AppCheck token rejected'),
        functionName: AiCallableEndpoints.diaryDraft,
        isSignedIn: true,
      ),
      contains('App Check'),
    );
    expect(
      aiCallableErrorMessage(
        error('deadline-exceeded'),
        functionName: AiCallableEndpoints.diaryDraft,
        isSignedIn: true,
      ),
      contains('逾時'),
    );
  });

  test('unknown callable errors retain their code', () {
    expect(
      aiCallableErrorMessage(
        error('data-loss'),
        functionName: AiCallableEndpoints.chat,
        isSignedIn: true,
      ),
      contains('data-loss'),
    );
  });

  test('unauthenticated distinguishes signed-out and App Check failures', () {
    expect(
      aiCallableErrorMessage(
        error('unauthenticated'),
        functionName: AiCallableEndpoints.chat,
        isSignedIn: false,
      ),
      contains('尚未登入'),
    );
    expect(
      aiCallableErrorMessage(
        error('unauthenticated'),
        functionName: AiCallableEndpoints.chat,
        isSignedIn: true,
      ),
      contains('App Check 驗證失敗'),
    );
  });

  test('Too many attempts is reported as App Check token acquisition failure',
      () {
    expect(
      aiCallableErrorMessage(
        error('unauthenticated', message: 'Too many attempts.'),
        functionName: AiCallableEndpoints.chat,
        isSignedIn: true,
      ),
      contains('Token 取得失敗'),
    );
  });

  test('base Firebase App Check errors are classified as token failures', () {
    expect(
      aiFirebaseErrorMessage(
        FirebaseException(
          plugin: 'firebase_app_check',
          code: 'unknown',
          message: 'Too many attempts.',
        ),
        isSignedIn: true,
      ),
      contains('Token 取得失敗'),
    );
  });
}
