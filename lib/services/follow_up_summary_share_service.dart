import 'package:cloud_functions/cloud_functions.dart';

import '../models/follow_up_ai_summary.dart';

class FollowUpShareSession {
  const FollowUpShareSession({
    required this.shareId,
    required this.url,
    required this.expiresAt,
  });

  final String shareId;
  final String url;
  final DateTime expiresAt;

  Duration remainingAt(DateTime now) =>
      expiresAt.isAfter(now) ? expiresAt.difference(now) : Duration.zero;
}

class FollowUpSummaryShareService {
  FollowUpSummaryShareService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<FollowUpShareSession> create(
    FollowUpSummaryRecord record, {
    required FollowUpSummaryShareOptions options,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('createFollowUpSummaryShare')
          .call(<String, dynamic>{
        'summaryId': record.id,
        'summarySnapshot': record.toDeidentifiedSnapshot(options: options),
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final shareId = data['shareId']?.toString() ?? '';
      final url = data['url']?.toString() ?? '';
      final expiresAt = DateTime.tryParse(data['expiresAt']?.toString() ?? '');
      if (shareId.isEmpty || !url.startsWith('https://') || expiresAt == null) {
        throw const FollowUpShareException('分享服務回傳格式不完整。');
      }
      return FollowUpShareSession(
        shareId: shareId,
        url: url,
        expiresAt: expiresAt,
      );
    } on FirebaseFunctionsException catch (error) {
      throw FollowUpShareException.fromFirebase(error);
    }
  }

  Future<Set<String>> activeSummaryIds(Iterable<String> summaryIds) async {
    return (await activeShares(summaryIds)).keys.toSet();
  }

  Future<Map<String, FollowUpShareSession>> activeShares(
      Iterable<String> summaryIds) async {
    final ids = summaryIds.where((id) => id.isNotEmpty).take(100).toList();
    if (ids.isEmpty) return const {};
    try {
      final result = await _functions
          .httpsCallable('getFollowUpShareStatuses')
          .call(<String, dynamic>{'summaryIds': ids});
      final data = Map<String, dynamic>.from(result.data as Map);
      final active = data['activeShares'];
      if (active is! List) return const {};
      final sessions = <String, FollowUpShareSession>{};
      for (final raw in active.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        final summaryId = item['summaryId']?.toString() ?? '';
        final shareId = item['shareId']?.toString() ?? '';
        final expiresAt =
            DateTime.tryParse(item['expiresAt']?.toString() ?? '');
        if (summaryId.isNotEmpty && shareId.isNotEmpty && expiresAt != null) {
          sessions[summaryId] = FollowUpShareSession(
            shareId: shareId,
            url: '',
            expiresAt: expiresAt,
          );
        }
      }
      return sessions;
    } on FirebaseFunctionsException catch (error) {
      throw FollowUpShareException.fromFirebase(error);
    }
  }

  Future<void> revoke(FollowUpShareSession session) async {
    try {
      await _functions.httpsCallable('revokeFollowUpShare').call({
        'shareId': session.shareId,
      });
    } on FirebaseFunctionsException catch (error) {
      throw FollowUpShareException.fromFirebase(error);
    }
  }
}

class FollowUpShareException implements Exception {
  const FollowUpShareException(this.message, {this.shareStopped = false});

  factory FollowUpShareException.fromFirebase(
    FirebaseFunctionsException error,
  ) {
    switch (error.code) {
      case 'unauthenticated':
        return const FollowUpShareException('請先登入後再管理分享。');
      case 'not-found':
        return const FollowUpShareException(
          '找不到這筆分享，可能已失效。',
          shareStopped: true,
        );
      case 'permission-denied':
        return const FollowUpShareException('你沒有權限停止這筆分享。');
      case 'failed-precondition':
        return const FollowUpShareException('分享已經停止。', shareStopped: true);
      case 'unavailable':
      case 'deadline-exceeded':
        return const FollowUpShareException('網路連線不穩定，請稍後重試。');
      default:
        return FollowUpShareException(
          error.message ?? '停止分享失敗，請稍後重試。',
        );
    }
  }

  final String message;
  final bool shareStopped;

  @override
  String toString() => message;
}
