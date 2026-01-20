import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/daily_record.dart';
import '../daily/daily_record_repository.dart';

/// 數據遷移工具 - 處理免費版到 Pro 版的升級
class DataMigration {
  static final DataMigration _instance = DataMigration._internal();

  factory DataMigration() {
    return _instance;
  }

  DataMigration._internal();

  /// 遷移結果
  Future<MigrationResult> migrateLocalToFirebase({
    required String userId,
    required DailyRecordRepository repository,
  }) async {
    try {
      // 1. 從本地 SQLite 讀取所有數據
      final recordMaps = await repository.getDailyRecordsByDateRange(
        userId: userId,
        startDate: DateTime(2000, 1, 1),
        endDate: DateTime.now(),
      );

      if (recordMaps.isEmpty) {
        return MigrationResult(
          success: true,
          recordsCount: 0,
          message: '沒有本地數據需要遷移',
        );
      }

      // 2. 上傳到 Firebase
      final uploadedCount = await _uploadToFirebase(userId, recordMaps);

      // 3. 驗證上傳
      final remoteRecords = await _getRemoteRecordCount(userId);

      if (remoteRecords >= recordMaps.length * 0.9) {
        // 至少上傳了 90% 的記錄
        return MigrationResult(
          success: true,
          recordsCount: recordMaps.length,
          message: '成功遷移 $uploadedCount 條記錄到雲端',
        );
      } else {
        return MigrationResult(
          success: false,
          recordsCount: uploadedCount,
          message: '部分記錄遷移失敗，請重試',
        );
      }
    } catch (e) {
      return MigrationResult(
        success: false,
        recordsCount: 0,
        message: '遷移失敗：$e',
      );
    }
  }

  /// 從本地獲取所有記錄
  Future<List<Map<String, dynamic>>> _getAllLocalRecords(
    String userId,
    DailyRecordRepository repository,
  ) async {
    try {
      // 查詢所有本地記錄（無時間限制）
      final records = await repository.getDailyRecordsByDateRange(
        userId: userId,
        startDate: DateTime(2000, 1, 1),
        endDate: DateTime.now(),
      );
      return records;
    } catch (e) {
      throw Exception('無法讀取本地記錄：$e');
    }
  }

  /// 上傳記錄到 Firebase
  Future<int> _uploadToFirebase(
    String userId,
    List<Map<String, dynamic>> recordMaps,
  ) async {
    int uploadedCount = 0;

    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      int batchCount = 0;

      for (final recordMap in recordMaps) {
        try {
          // 從本地數據重建 DailyRecord 對象（假設有 fromMap 工廠方法）
          // 如果 DailyRecord 沒有 fromMap，可以直接上傳 Map
          final docRef = firestore
              .collection('users')
              .doc(userId)
              .collection('daily_records')
              .doc(recordMap['id'] as String?);

          batch.set(docRef, recordMap);
          batchCount++;
          uploadedCount++;

          // 每 500 條記錄提交一次批量寫入
          if (batchCount >= 500) {
            await batch.commit();
            batchCount = 0;
          }
        } catch (e) {
          print('上傳單筆記錄失敗: $e');
        }
      }

      // 提交剩餘記錄
      if (batchCount > 0) {
        await batch.commit();
      }

      return uploadedCount;
    } catch (e) {
      throw Exception('上傳到 Firebase 失敗：$e');
    }
  }

  /// 從 Firebase 獲取記錄數量
  Future<int> _getRemoteRecordCount(String userId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('daily_records')
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }
}

/// 遷移結果
class MigrationResult {
  final bool success;
  final int recordsCount;
  final String message;

  MigrationResult({
    required this.success,
    required this.recordsCount,
    required this.message,
  });

  @override
  String toString() => 'MigrationResult(success: $success, count: $recordsCount, msg: $message)';
}
