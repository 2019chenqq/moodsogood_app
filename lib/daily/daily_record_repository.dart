import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../services/home_widget_sync_service.dart';

/// 本地存儲每日記錄（情緒、睡眠、體感等）
/// 當 Firebase 同步禁用時，數據仍會保存在本地 SQLite 中
class DailyRecordRepository {
  static final DailyRecordRepository _instance =
      DailyRecordRepository._internal();
  static late Database _db;
  static bool _initialized = false;

  factory DailyRecordRepository() {
    return _instance;
  }

  DailyRecordRepository._internal();

  /// 初始化數據庫
  Future<void> init() async {
    if (_initialized) return;

    try {
      final dbPath = await _getDatabasePath();
      debugPrint('📍 Database path: $dbPath');
      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: _onCreate,
      );
      _initialized = true;
      debugPrint('✅ DailyRecordRepository initialized successfully');
    } catch (e) {
      print('DailyRecordRepository init error: $e');
      rethrow;
    }
  }

  /// 創建表
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE daily_records (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL,
        date TEXT NOT NULL,
        emotions TEXT,
        sleep TEXT,
        bodySymptoms TEXT,
        dailyActivities TEXT,
        medicines TEXT,
        periodData TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    // 創建複合索引以便快速查詢
    await db.execute(
      'CREATE INDEX idx_daily_records_userId_date ON daily_records(userId, date)',
    );
  }

  /// 取得數據庫路徑
  Future<String> _getDatabasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/moodsogood_daily_records.db';
    debugPrint('📁 Application Documents Directory: ${dir.path}');
    debugPrint('📁 Full Database Path: $path');
    return path;
  }

  /// 存儲日常記錄
  /// [id] 通常是 Firestore docId，用於同步時對應
  Future<void> saveDailyRecord({
    required String id,
    required String userId,
    required DateTime date,
    Map<String, dynamic>? emotions,
    Map<String, dynamic>? sleep,
    List<String>? bodySymptoms,
    Map<String, dynamic>? dailyActivities,
    List<Map<String, dynamic>>? medicines,
    Map<String, dynamic>? periodData,
  }) async {
    debugPrint('📝 saveDailyRecord called: id=$id, userId=$userId, date=$date');

    if (!_initialized) {
      debugPrint('⚠️  Database not initialized, initializing now...');
      await init();
    }

    try {
      // 🔧 使用日期部分（YYYY-MM-DD）進行存儲，確保查詢時能正確匹配
      final dateOnly = DateTime(date.year, date.month, date.day);
      final dateStr = dateOnly.toIso8601String(); // 格式：2025-02-05

      final record = {
        'id': id,
        'userId': userId,
        'date': dateStr, // 🔧 只保存日期部分，不包含時間
        'emotions': emotions != null ? jsonEncode(emotions) : null,
        'sleep': sleep != null ? jsonEncode(sleep) : null,
        'bodySymptoms': bodySymptoms != null ? jsonEncode(bodySymptoms) : null,
        'dailyActivities':
            dailyActivities != null ? jsonEncode(dailyActivities) : null,
        'medicines': medicines != null ? jsonEncode(medicines) : null,
        'periodData': periodData != null ? jsonEncode(periodData) : null,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      debugPrint('💾 Inserting record: $record');
      final result = await _db.insert(
        'daily_records',
        record,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('✅ Record inserted successfully with rowid=$result');

      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      if (!dateOnly.isAfter(todayOnly)) {
        final streakDays = await _getConsecutiveRecordDays(
          userId: userId,
          fromDate: todayOnly,
        );

        await HomeWidgetSyncService.updateDailyRecord(
          streakDays: streakDays,
        );
      }
    } catch (e, st) {
      debugPrint('❌ Error saving daily record: $e\nStacktrace: $st');
      rethrow;
    }
  }

  Future<int> _getConsecutiveRecordDays({
    required String userId,
    required DateTime fromDate,
  }) async {
    final dateOnly = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final records = await _db.query(
      'daily_records',
      columns: ['date'],
      where: 'userId = ? AND date <= ?',
      whereArgs: [userId, dateOnly.toIso8601String()],
      orderBy: 'date DESC',
    );

    final recordedDays = records
        .map((record) => DateTime.tryParse(record['date']?.toString() ?? ''))
        .whereType<DateTime>()
        .map((date) =>
            DateTime(date.year, date.month, date.day).toIso8601String())
        .toSet();

    var streak = 0;
    var cursor = dateOnly;
    while (recordedDays.contains(cursor.toIso8601String())) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  /// 獲取特定日期的記錄
  Future<Map<String, dynamic>?> getDailyRecord({
    required String userId,
    required DateTime date,
  }) async {
    if (!_initialized) await init();

    try {
      // 🔧 使用日期部分（YYYY-MM-DD）進行查詢，與保存時的格式一致
      final dateOnly = DateTime(date.year, date.month, date.day);
      final dateStr = dateOnly.toIso8601String();

      debugPrint(
          '🔍 getDailyRecord: userId=$userId, date=$date, searching for dateStr=$dateStr');

      final results = await _db.query(
        'daily_records',
        where: 'userId = ? AND date = ?', // 🔧 精確匹配日期
        whereArgs: [userId, dateStr],
        limit: 1,
      );

      debugPrint('✅ getDailyRecord query returned ${results.length} results');

      if (results.isEmpty) {
        debugPrint('⚠️  No record found for $dateStr');
        return null;
      }

      return _decodeRecord(results.first);
    } catch (e, st) {
      debugPrint('❌ Error fetching daily record: $e\nStacktrace: $st');
      return null;
    }
  }

  /// 獲取某個用戶某個日期範圍內的所有記錄
  Future<List<Map<String, dynamic>>> getDailyRecordsByDateRange({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (!_initialized) await init();

    try {
      // 🔧 使用日期部分（YYYY-MM-DD）進行比較，與保存時的格式一致
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);

      final startStr = start.toIso8601String();
      final endStr = end.toIso8601String();

      debugPrint(
          '🔍 getDailyRecordsByDateRange: userId=$userId, from=$startStr to=$endStr');

      final results = await _db.query(
        'daily_records',
        where: 'userId = ? AND date >= ? AND date <= ?',
        whereArgs: [
          userId,
          startStr,
          endStr,
        ],
        orderBy: 'date DESC',
      );

      debugPrint('✅ Query returned ${results.length} records');
      if (results.isEmpty) {
        debugPrint('⚠️  No records found. Debugging:');
        // 診斷：列出所有記錄看看
        final allRecords = await _db.query('daily_records');
        debugPrint('   📋 Total records in database: ${allRecords.length}');
        for (var rec in allRecords) {
          debugPrint(
              '   - ID: ${rec['id']}, UserID: ${rec['userId']}, Date: ${rec['date']}');
        }
      }
      return results.map(_decodeRecord).toList();
    } catch (e) {
      print('Error fetching daily records by date range: $e');
      return [];
    }
  }

  /// 刪除記錄
  Future<void> deleteDailyRecord(String id) async {
    if (!_initialized) await init();

    try {
      await _db.delete(
        'daily_records',
        where: 'id = ?',
        whereArgs: [id],
      );
      print('DailyRecord deleted locally: $id');
    } catch (e) {
      print('Error deleting daily record: $e');
      rethrow;
    }
  }

  /// 解碼記錄（將 JSON 字符串轉回對象）
  Map<String, dynamic> _decodeRecord(Map<String, dynamic> record) {
    return {
      'id': record['id'],
      'userId': record['userId'],
      'date': record['date'],
      'emotions':
          record['emotions'] != null ? jsonDecode(record['emotions']) : null,
      'sleep': record['sleep'] != null ? jsonDecode(record['sleep']) : null,
      'bodySymptoms': record['bodySymptoms'] != null
          ? jsonDecode(record['bodySymptoms'])
          : null,
      'dailyActivities': record['dailyActivities'] != null
          ? jsonDecode(record['dailyActivities'])
          : null,
      'medicines':
          record['medicines'] != null ? jsonDecode(record['medicines']) : null,
      'periodData': record['periodData'] != null
          ? jsonDecode(record['periodData'])
          : null,
      'createdAt': record['createdAt'],
      'updatedAt': record['updatedAt'],
    };
  }

  /// 獲取本地記錄總數
  Future<int> getRecordCount({required String userId}) async {
    if (!_initialized) await init();

    try {
      final result = await _db.query(
        'daily_records',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      return result.length;
    } catch (e) {
      print('Error getting record count: $e');
      return 0;
    }
  }

  /// 清空所有本地記錄（用於測試或數據重置）
  Future<void> clearAllRecords() async {
    if (!_initialized) await init();

    try {
      await _db.delete('daily_records');
      print('All daily records cleared locally');
    } catch (e) {
      print('Error clearing records: $e');
      rethrow;
    }
  }

  /// 關閉數據庫
  Future<void> close() async {
    if (_initialized) {
      await _db.close();
      _initialized = false;
    }
  }
}
