import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import '../ai/ai_request_id.dart';

class AiJournalReflectionHttpClient {
  AiJournalReflectionHttpClient({
    http.Client? httpClient,
    String functionName = _defaultFunctionName,
    Future<String?> Function()? idTokenProvider,
    Future<String?> Function()? appCheckTokenProvider,
  })  : _httpClient = httpClient ?? http.Client(),
        _functionName = functionName,
        _idTokenProvider = idTokenProvider ?? _getIdToken,
        _appCheckTokenProvider = appCheckTokenProvider ?? _getAppCheckToken;

  static const String _defaultFunctionName = 'generateAiJournalReflection';
  static const String _region = 'us-central1';

  final http.Client _httpClient;
  final String _functionName;
  final Future<String?> Function() _idTokenProvider;
  final Future<String?> Function() _appCheckTokenProvider;

  static Future<String?> _getIdToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  static Future<String?> _getAppCheckToken() =>
      FirebaseAppCheck.instance.getToken();

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
      final idToken = await _idTokenProvider();
      if (idToken == null || idToken.isEmpty) {
        throw const AiJournalReflectionHttpException(
          '登入狀態已失效，請重新登入後再試。',
          statusCode: 401,
        );
      }
      // Raw HTTP must supply App Check explicitly. Use Firebase token caching.
      final String? appCheckToken;
      try {
        appCheckToken = await _appCheckTokenProvider();
      } catch (_) {
        throw const AiJournalReflectionHttpException(
          '無法完成裝置驗證，請確認網路連線並重新開啟 App 後再試。',
          statusCode: 401,
        );
      }
      if (appCheckToken == null || appCheckToken.isEmpty) {
        throw const AiJournalReflectionHttpException(
          '裝置驗證尚未完成，請重新開啟 App 後再試。',
          statusCode: 401,
        );
      }
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        'Authorization': 'Bearer $idToken',
        'X-Firebase-AppCheck': appCheckToken,
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

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiJournalReflectionHttpException(
          response.statusCode == 401
              ? '登入或裝置驗證未通過，請重新登入並重新開啟 App 後再試。'
              : 'AI HTTP 呼叫失敗：${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
      }

      final decoded = _decodeResponseBody(responseBody);
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
