import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/health_event.dart';
import '../utils/health_data_encryption_service.dart';

/// 快速事件（快速記錄現在狀況）的讀寫 Repository。
///
/// Firestore 結構：users/{uid}/healthEvents/{eventId}
/// - eventId 使用 Firestore 自動 id，一天可有多筆。
/// - 資料（symptoms/emotions/stateChanges/context/note）會透過
///   [HealthDataEncryptionService] 加密；timestamp 保留為查詢欄位。
class HealthEventRepository {
  static final HealthEventRepository _instance = HealthEventRepository._();

  factory HealthEventRepository() => _instance;

  HealthEventRepository._();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _events(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('healthEvents');
  }

  String _requireUserId() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('需先登入才能存取快速紀錄');
    }
    return uid;
  }

  /// 新增一筆快速事件，回傳新產生的事件 id。
  Future<String> create({
    required String userId,
    required HealthEvent event,
  }) async {
    final ref = _events(userId).doc();
    final data = <String, dynamic>{
      ...event.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await HealthDataEncryptionService.setEncrypted(ref, data, merge: false);
    return ref.id;
  }

  /// 更新既有快速事件。
  Future<void> update({
    required String userId,
    required HealthEvent event,
  }) async {
    if (event.id.isEmpty) {
      throw ArgumentError('更新快速事件必須提供 event.id');
    }
    final ref = _events(userId).doc(event.id);
    final data = <String, dynamic>{
      ...event.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await HealthDataEncryptionService.setEncrypted(ref, data);
  }

  /// 刪除一筆快速事件。
  Future<void> delete({
    required String userId,
    required String eventId,
  }) async {
    await _events(userId).doc(eventId).delete();
  }

  /// 取得某時段（含頭尾）內、依 timestamp 由新到舊排序的所有快速事件。
  Future<List<HealthEvent>> getByDateRange({
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final docs = await HealthDataEncryptionService.getEncrypted(
      _events(userId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .orderBy('timestamp', descending: true),
    );
    return docs
        .map((d) => HealthEvent.fromMap(d.id, d.data))
        .toList(growable: false);
  }

  /// 取得今天所有快速事件（依 timestamp 由新到舊）。
  Future<List<HealthEvent>> getToday({required String userId}) async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final start = day;
    final end = day
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    return getByDateRange(userId: userId, start: start, end: end);
  }

  /// 取得最近 n 筆快速事件（依 timestamp 由新到舊）。
  Future<List<HealthEvent>> getRecent({
    required String userId,
    int limit = 3,
  }) async {
    final docs = await HealthDataEncryptionService.getEncrypted(
      _events(userId).orderBy('timestamp', descending: true).limit(limit),
    );
    return docs
        .map((d) => HealthEvent.fromMap(d.id, d.data))
        .toList(growable: false);
  }
}
