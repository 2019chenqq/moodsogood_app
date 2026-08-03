import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import '../ai/ai_request_id.dart';

class AiJournalReflectionHttpClient {
  AiJournalReflectionHttpClient({
    http.Client? httpClient,
    String functionName = _defaultFunctionName,
  })  : _httpClient = httpClient ?? http.Client(),
        _functionName = functionName;

  static const String _defaultFunctionName = 'generateAiJournalReflection';
  static const String _region = 'us-central1';

  final http.Client _httpClient;
  final String _functionName;

  Uri get _callableUri {
    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    return Uri.parse(
      'https://$_region-$projectId.cloudfunctions.net/$_functionName',
    );
  }

  Future<Map<String, dynamic>> generate({
    required Map<String, dynamic> payload,
  }) async {
    final sanitizedPayload = Map<String, dynamic>.from(
      sanitizeForJson(payload) as Map,
    );
    sanitizedPayload['requestId'] = createAiRequestId();
    final requestBody = jsonEncode(<String, dynamic>{
      'data': sanitizedPayload,
    });

    try {
      debugPrint(
        'AI HTTP request payload: ${jsonEncode(sanitizedPayload)}',
      );

      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user?.getIdToken();
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        if (idToken != null && idToken.isNotEmpty)
          'Authorization': 'Bearer $idToken',
      };

      final response = await _httpClient
          .post(
            _callableUri,
            headers: headers,
            body: utf8.encode(requestBody),
          )
          .timeout(const Duration(seconds: 60));

      final responseBody = utf8.decode(response.bodyBytes);
      debugPrint('AI HTTP response status: ${response.statusCode}');
      debugPrint('AI HTTP response body: $responseBody');

      final decoded = _decodeResponseBody(responseBody);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiJournalReflectionHttpException(
          'AI HTTP 呼叫失敗：${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
      }

      if (decoded['error'] != null) {
        throw AiJournalReflectionHttpException(
          _extractCallableErrorMessage(decoded['error']),
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
      }

      final result = decoded['result'];
      if (result is! Map) {
        throw const FormatException('AI 回傳格式錯誤：缺少 result');
      }

      return Map<String, dynamic>.from(result);
    } catch (e, stack) {
      debugPrint('AI HTTP exception: $e');
      debugPrint('AI HTTP stackTrace: $stack');
      rethrow;
    }
  }

  Map<String, dynamic> _decodeResponseBody(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) {
        throw const FormatException('AI 回傳格式錯誤：不是 JSON object');
      }
      return Map<String, dynamic>.from(decoded);
    } catch (e, stack) {
      debugPrint('AI HTTP response parse exception: $e');
      debugPrint('AI HTTP response parse stackTrace: $stack');
      rethrow;
    }
  }

  String _extractCallableErrorMessage(dynamic error) {
    if (error is Map) {
      final message = error['message'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
      final status = error['status'];
      if (status != null && status.toString().trim().isNotEmpty) {
        return 'AI HTTP callable error: $status';
      }
    }
    return 'AI HTTP callable error';
  }

  static dynamic sanitizeForJson(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) {
      return value.toIso8601String();
    }

    if (value is List) {
      return value.map(sanitizeForJson).toList();
    }

    if (value is Map) {
      return value.map((key, val) {
        return MapEntry(key.toString(), sanitizeForJson(val));
      });
    }

    return value;
  }
}

class AiJournalReflectionHttpException implements Exception {
  const AiJournalReflectionHttpException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  final String message;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() => message;
}
