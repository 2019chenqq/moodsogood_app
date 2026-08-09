import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AiCallableEndpoints {
  const AiCallableEndpoints._();

  static const region = 'us-central1';
  static const chat = 'generateInneraAiChat';
  static const diaryDraft = 'generateInneraDiaryDraft';
  static const recommendSongs = 'recommendInneraSongs';
  static const searchSongs = 'searchInneraSongs';
}

String mapAiErrorType(Object error) {
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'deadline-exceeded':
        return 'timeout';
      case 'unavailable':
        return 'network';
      case 'resource-exhausted':
        return 'quota';
      default:
        return 'api_error';
    }
  }
  if (error is TimeoutException) return 'timeout';
  if (error is FormatException) return 'parse_error';
  return 'unknown';
}

void logAiCallableFailure({
  required String functionName,
  required FirebaseFunctionsException error,
  StackTrace? stackTrace,
}) {
  final projectId = Firebase.apps.isEmpty
      ? '<firebase-not-initialized>'
      : Firebase.app().options.projectId;
  debugPrint(
    'AI callable failed: '
    'projectId=$projectId, '
    'function=$functionName, '
    'region=${AiCallableEndpoints.region}, '
    'code=${error.code}, '
    'message=${error.message}, '
    'details=${_safeDetails(error.details)}',
  );
  if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
}

String aiCallableErrorMessage(
  FirebaseFunctionsException error, {
  required String functionName,
}) {
  switch (error.code) {
    case 'not-found':
      return functionName == AiCallableEndpoints.diaryDraft
          ? 'AI 日記整理後端不存在。請確認函式已部署到目前專案，且名稱與地區一致。'
          : 'AI 對話後端不存在。請確認函式名稱、Firebase 專案與部署地區。';
    case 'unavailable':
      return '目前無法連線到 AI 服務，可能是網路或 Firebase Functions 暫時不可用，請稍後再試。';
    case 'unauthenticated':
      return '登入狀態已失效，請重新登入後再試。';
    case 'permission-denied':
      return 'AI 服務拒絕此請求，請確認帳號權限與 Firebase App Check 設定。';
    case 'deadline-exceeded':
      return 'AI 回應逾時，請稍後再試；目前草稿已保留。';
    case 'resource-exhausted':
      return 'AI 使用額度或服務容量已達限制，請稍後再試。';
    case 'failed-precondition':
      return error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : 'AI 後端設定尚未完成，請稍後再試。';
    case 'invalid-argument':
      return error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : '送出的 AI 整理資料格式不正確。';
    case 'internal':
      return 'AI 後端執行時發生錯誤，請稍後再試；目前草稿已保留。';
    case 'cancelled':
      return 'AI 請求已取消，目前草稿已保留。';
    default:
      return 'AI 服務發生錯誤（${error.code}），請稍後再試；目前草稿已保留。';
  }
}

String _safeDetails(dynamic value, {int depth = 0}) {
  if (value == null) return 'null';
  if (depth > 2) return '<nested>';
  if (value is num || value is bool) return value.toString();
  if (value is String) {
    final redacted = value
        .replaceAll(
            RegExp(r'Bearer\s+\S+', caseSensitive: false), 'Bearer <redacted>')
        .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]+\b'), '<redacted-api-key>');
    return redacted.length <= 300 ? redacted : '${redacted.substring(0, 300)}…';
  }
  if (value is Map) {
    final safe = <String, String>{};
    for (final entry in value.entries.take(20)) {
      final key = entry.key.toString();
      if (RegExp(
        r'key|token|secret|authorization|content|conversation|diary|userMessage',
        caseSensitive: false,
      ).hasMatch(key)) {
        safe[key] = '<redacted>';
      } else {
        safe[key] = _safeDetails(entry.value, depth: depth + 1);
      }
    }
    return safe.toString();
  }
  if (value is Iterable) {
    return value
        .take(10)
        .map((item) => _safeDetails(item, depth: depth + 1))
        .toList()
        .toString();
  }
  return '<${value.runtimeType}>';
}
