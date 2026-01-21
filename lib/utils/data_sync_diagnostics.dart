import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../daily/daily_record_repository.dart';
import '../models/daily_record.dart';

/// 數據同步診斷和修復工具
class DataSyncDiagnostics {
  /// 檢查本地和 Firebase 的數據一致性
  static Future<SyncDiagnosisResult> diagnoseSync() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return SyncDiagnosisResult(
        isHealthy: false,
        message: '未登入，無法診斷',
        localRecordCount: 0,
        firebaseRecordCount: 0,
      );
    }

    try {
      // 1. 獲取本地記錄數量
      final repo = DailyRecordRepository();
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 90));

      final localRecords = await repo.getDailyRecordsByDateRange(
        userId: uid,
        startDate: startDate,
        endDate: endDate,
      );

      // 2. 獲取 Firebase 記錄數量
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyRecords')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      // 3. 比較差異
      final localIds =
          localRecords.map((r) => r['id'] as String).toSet();
      final firebaseIds =
          snapshot.docs.map((doc) => doc.id).toSet();

      final onlyInLocal = localIds.difference(firebaseIds);
      final onlyInFirebase = firebaseIds.difference(localIds);
      final inBoth = localIds.intersection(firebaseIds);

      final isHealthy =
          onlyInLocal.isEmpty && onlyInFirebase.isEmpty;

      return SyncDiagnosisResult(
        isHealthy: isHealthy,
        message: isHealthy ? '✅ 數據同步健康' : '⚠️ 發現數據不一致',
        localRecordCount: localRecords.length,
        firebaseRecordCount: snapshot.docs.length,
        commonRecords: inBoth.length,
        onlyLocalRecords: onlyInLocal.length,
        onlyFirebaseRecords: onlyInFirebase.length,
        discrepancyDetails: isHealthy
            ? null
            : '本地有 ${onlyInLocal.length} 筆、'
                'Firebase 有 ${onlyInFirebase.length} 筆、'
                '重複的有 ${inBoth.length} 筆',
      );
    } catch (e) {
      return SyncDiagnosisResult(
        isHealthy: false,
        message: '診斷失敗：$e',
        localRecordCount: 0,
        firebaseRecordCount: 0,
      );
    }
  }

  /// 修復同步問題 - 將本地未同步的數據上傳到 Firebase
  static Future<SyncRepairResult> repairSync() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return SyncRepairResult(
        success: false,
        message: '未登入，無法修復',
      );
    }

    try {
      final repo = DailyRecordRepository();
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 90));

      final localRecords = await repo.getDailyRecordsByDateRange(
        userId: uid,
        startDate: startDate,
        endDate: endDate,
      );

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyRecords')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      final firebaseIds = snapshot.docs.map((doc) => doc.id).toSet();
      int uploadedCount = 0;

      for (var localRecord in localRecords) {
        final docId = localRecord['id'] as String;
        if (!firebaseIds.contains(docId)) {
          // 這筆紀錄只在本地，需要上傳到 Firebase
          await _uploadLocalRecordToFirebase(uid, docId, localRecord);
          uploadedCount++;
        }
      }

      return SyncRepairResult(
        success: true,
        message: '✅ 修復完成，上傳了 $uploadedCount 筆紀錄到 Firebase',
        recordsRepaired: uploadedCount,
      );
    } catch (e) {
      return SyncRepairResult(
        success: false,
        message: '修復失敗：$e',
      );
    }
  }

  /// 將本地紀錄上傳到 Firebase
  static Future<void> _uploadLocalRecordToFirebase(
    String uid,
    String docId,
    Map<String, dynamic> localRecord,
  ) async {
    try {
      final emotions = _parseJsonIfString(localRecord['emotions']);
      final sleep = _parseJsonIfString(localRecord['sleep']);
      final symptoms = _parseJsonIfString(localRecord['bodySymptoms']) as List?;

      final payload = <String, dynamic>{
        'date': Timestamp.fromDate(DateTime.parse(localRecord['date'] as String)),
        'emotions': emotions is Map
            ? (emotions as Map).entries
                .map((e) => {'name': e.key, 'value': e.value})
                .toList()
            : [],
        'symptoms': symptoms ?? [],
        'sleep': sleep ?? {},
        'uploadedFromLocal': true,
        'uploadedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyRecords')
          .doc(docId)
          .set(payload, SetOptions(merge: true));

      debugPrint('✅ Uploaded local record $docId to Firebase');
    } catch (e) {
      debugPrint('❌ Failed to upload record $docId: $e');
    }
  }

  static dynamic _parseJsonIfString(dynamic value) {
    if (value is String) {
      try {
        return jsonDecode(value);
      } catch (e) {
        return value;
      }
    }
    return value;
  }

  /// 清除本地數據庫（用於測試）
  static Future<bool> clearLocalDatabase() async {
    try {
      final repo = DailyRecordRepository();
      await repo.clearAllRecords();
      return true;
    } catch (e) {
      debugPrint('❌ Failed to clear local database: $e');
      return false;
    }
  }

  /// 導出所有數據為 JSON（用於備份）
  static Future<String> exportDataAsJson() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return '{}';

    try {
      final repo = DailyRecordRepository();
      final endDate = DateTime.now();
      final startDate = DateTime(2020, 1, 1); // 導出所有數據

      final records = await repo.getDailyRecordsByDateRange(
        userId: uid,
        startDate: startDate,
        endDate: endDate,
      );

      final json = {
        'exportDate': DateTime.now().toIso8601String(),
        'userId': uid,
        'recordCount': records.length,
        'records': records,
      };

      return jsonEncode(json);
    } catch (e) {
      debugPrint('❌ Export failed: $e');
      return '{}';
    }
  }
}

/// 診斷結果
class SyncDiagnosisResult {
  final bool isHealthy;
  final String message;
  final int localRecordCount;
  final int firebaseRecordCount;
  final int commonRecords;
  final int onlyLocalRecords;
  final int onlyFirebaseRecords;
  final String? discrepancyDetails;

  SyncDiagnosisResult({
    required this.isHealthy,
    required this.message,
    required this.localRecordCount,
    required this.firebaseRecordCount,
    this.commonRecords = 0,
    this.onlyLocalRecords = 0,
    this.onlyFirebaseRecords = 0,
    this.discrepancyDetails,
  });
}

/// 修復結果
class SyncRepairResult {
  final bool success;
  final String message;
  final int recordsRepaired;

  SyncRepairResult({
    required this.success,
    required this.message,
    this.recordsRepaired = 0,
  });
}
