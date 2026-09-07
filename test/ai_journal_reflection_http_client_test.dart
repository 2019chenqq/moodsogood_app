import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodsogood_app/services/ai_journal_reflection_http_client.dart';

void main() {
  test('sends Auth and App Check with callable payload', () async {
    final client = AiJournalReflectionHttpClient(
      idTokenProvider: () async => 'auth-token',
      appCheckTokenProvider: () async => 'app-check-token',
      httpClient: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer auth-token');
        expect(request.headers['X-Firebase-AppCheck'], 'app-check-token');
        final data = (jsonDecode(request.body) as Map)['data'] as Map;
        expect(data['requestId'], isNotEmpty);
        expect(data['date'], '2026-09-06T00:00:00.000');
        return http.Response(
            jsonEncode({
              'result': {'summary': 'ok'}
            }),
            200);
      }),
    );
    expect(await client.generate(payload: {'date': DateTime(2026, 9, 6)}),
        {'summary': 'ok'});
  });

  for (final missing in ['auth', 'appCheck', 'appCheckError']) {
    test('does not send an unverified request: $missing', () async {
      final client = AiJournalReflectionHttpClient(
        idTokenProvider: () async => missing == 'auth' ? null : 'auth',
        appCheckTokenProvider: () async {
          if (missing == 'appCheckError') throw StateError('unavailable');
          return null;
        },
        httpClient: MockClient((_) async {
          fail('Unverified requests must not reach the backend');
        }),
      );
      await expectLater(
          client.generate(payload: {}),
          throwsA(isA<AiJournalReflectionHttpException>()
              .having((e) => e.statusCode, 'statusCode', 401)));
    });
  }

  test('preserves HTTP 401 even when response is not JSON', () async {
    final client = AiJournalReflectionHttpClient(
      idTokenProvider: () async => 'auth',
      appCheckTokenProvider: () async => 'appCheck',
      httpClient: MockClient((_) async => http.Response('Unauthorized', 401)),
    );
    await expectLater(
        client.generate(payload: {}),
        throwsA(isA<AiJournalReflectionHttpException>()
            .having((e) => e.statusCode, 'statusCode', 401)));
  });
}
