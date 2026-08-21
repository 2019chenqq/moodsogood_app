import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _defaultProjectId = 'moodsogood-9e45b';
const _collection = 'ai_usage_daily';
const _fields = <String>[
  'eventCount',
  'inputTokens',
  'outputTokens',
  'totalTokens',
  'succeededCount',
  'failedCount',
];

Future<void> main(List<String> arguments) async {
  late final AiUsageOptions options;
  late final DateTime start;
  late final DateTime end;
  try {
    options = parseAiUsageArguments(arguments);
    if (options.help) {
      _printUsage();
      return;
    }

    start = _parseDate(options.startDate, '--startDate');
    end = _parseDate(options.endDate, '--endDate');
    if (start.isAfter(end)) {
      throw const FormatException('--startDate 不可晚於 --endDate。');
    }
  } on FormatException catch (error) {
    stderr.writeln('參數錯誤: ${error.message}');
    _printUsage();
    exitCode = 64;
    return;
  }

  try {
    final token = options.accessToken ??
        Platform.environment['GOOGLE_OAUTH_ACCESS_TOKEN'] ??
        await _applicationDefaultAccessToken();
    final totals = <String, int>{for (final field in _fields) field: 0};
    var documentCount = 0;

    // batchGet is a Firestore read-only RPC. Chunking prevents an excessively
    // large request when the requested range spans many days.
    final names = _documentNames(options.projectId, start, end);
    for (var offset = 0; offset < names.length; offset += 100) {
      final chunkEnd =
          (offset + 100 < names.length) ? offset + 100 : names.length;
      final documents = names.sublist(offset, chunkEnd);
      final uri = Uri.https(
        'firestore.googleapis.com',
        '/v1/projects/${options.projectId}/databases/(default)/documents:batchGet',
      );
      final response = await http.post(
        uri,
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $token',
          HttpHeaders.contentTypeHeader: 'application/json',
        },
        body: jsonEncode({
          'documents': documents,
          'mask': {'fieldPaths': _fields},
        }),
      );
      if (response.statusCode != 200) {
        throw HttpException(
          'Firestore 讀取失敗 (${response.statusCode}): ${response.body}',
          uri: uri,
        );
      }

      for (final item in _decodeBatchGetResponse(response.body)) {
        final found = item['found'] as Map<String, dynamic>?;
        if (found == null) continue;
        documentCount++;
        final fields = found['fields'] as Map<String, dynamic>? ?? const {};
        for (final field in _fields) {
          totals[field] = totals[field]! + _firestoreInteger(fields[field]);
        }
      }
    }

    stdout
      ..writeln('Firestore AI usage 統計')
      ..writeln('collection: $_collection')
      ..writeln('日期範圍: ${_dateKey(start)} ~ ${_dateKey(end)}（含首尾）')
      ..writeln('讀取到的每日文件數: $documentCount');
    for (final field in _fields) {
      stdout.writeln('$field: ${totals[field]}');
    }
  } catch (error) {
    stderr.writeln('執行失敗: $error');
    exitCode = 1;
  }
}

class AiUsageOptions {
  const AiUsageOptions({
    required this.startDate,
    required this.endDate,
    required this.projectId,
    required this.accessToken,
    required this.help,
  });

  final String? startDate;
  final String? endDate;
  final String projectId;
  final String? accessToken;
  final bool help;
}

AiUsageOptions parseAiUsageArguments(List<String> arguments) {
  final values = <String, String>{};
  var help = false;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--help' || argument == '-h') {
      help = true;
      continue;
    }
    if (!argument.startsWith('--')) {
      throw FormatException('無法辨識的參數：$argument');
    }
    final equals = argument.indexOf('=');
    if (equals > 2) {
      values[argument.substring(2, equals)] = argument.substring(equals + 1);
      continue;
    }
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      throw FormatException('$argument 缺少值。');
    }
    values[argument.substring(2)] = arguments[++index];
  }

  const allowed = {'startDate', 'endDate', 'projectId', 'accessToken'};
  final unknown = values.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('無法辨識的參數：--${unknown.first}');
  }
  if (!help && (values['startDate'] == null || values['endDate'] == null)) {
    throw const FormatException('--startDate 與 --endDate 都是必填。');
  }
  return AiUsageOptions(
    startDate: values['startDate'],
    endDate: values['endDate'],
    projectId: values['projectId'] ?? _defaultProjectId,
    accessToken: values['accessToken'],
    help: help,
  );
}

List<Map<String, dynamic>> _decodeBatchGetResponse(String body) {
  final decoded = jsonDecode(body);
  if (decoded is List) {
    return decoded.cast<Map<String, dynamic>>();
  }
  if (decoded is Map<String, dynamic>) return [decoded];
  throw const FormatException('Firestore batchGet 回應不是 JSON 物件或陣列。');
}

DateTime _parseDate(String? value, String option) {
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw FormatException('$option 必須是 yyyy-MM-dd 格式。');
  }
  final date = DateTime.tryParse('${value}T00:00:00Z');
  if (date == null || _dateKey(date) != value) {
    throw FormatException('$option 不是有效日期：$value');
  }
  return date;
}

List<String> _documentNames(String projectId, DateTime start, DateTime end) {
  final prefix =
      'projects/$projectId/databases/(default)/documents/$_collection';
  return [
    for (var date = start;
        !date.isAfter(end);
        date = date.add(const Duration(days: 1)))
      '$prefix/${_dateKey(date)}',
  ];
}

String _dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

int _firestoreInteger(dynamic value) {
  if (value is! Map<String, dynamic>) return 0;
  final integer = value['integerValue'];
  if (integer != null) return int.tryParse(integer.toString()) ?? 0;
  final doubleValue = value['doubleValue'];
  return doubleValue is num ? doubleValue.toInt() : 0;
}

Future<String> _applicationDefaultAccessToken() async {
  ProcessResult result;
  try {
    result = await Process.run(
      Platform.isWindows ? 'gcloud.cmd' : 'gcloud',
      const ['auth', 'application-default', 'print-access-token'],
      runInShell: Platform.isWindows,
    );
  } on ProcessException {
    throw StateError(
      '找不到 gcloud。請先安裝 Google Cloud CLI，或用 '
      '--accessToken / GOOGLE_OAUTH_ACCESS_TOKEN 提供 OAuth access token。',
    );
  }
  if (result.exitCode != 0) {
    throw StateError(
      '無法取得 Application Default Credentials：${result.stderr}\n'
      '請先執行 gcloud auth application-default login。',
    );
  }
  final token = result.stdout.toString().trim();
  if (token.isEmpty) throw StateError('gcloud 回傳空白 access token。');
  return token;
}

void _printUsage() {
  stdout.writeln(
    '用法：dart run tool/sum_ai_usage.dart '
    '--startDate yyyy-MM-dd --endDate yyyy-MM-dd '
    '[--projectId $_defaultProjectId] [--accessToken TOKEN]',
  );
}
