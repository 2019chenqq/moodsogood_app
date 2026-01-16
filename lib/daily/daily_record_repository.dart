import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 本地存儲每日記錄（情緒、睡眠、體感等）
/// 當 Firebase 同步禁用時，數據仍會保存在本地 SQLite 中
class DailyRecordRepository {
  static final DailyRecordRepository _instance = DailyRecordRepository._internal();
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
      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: _onCreate,
      );
      _initialized = true;
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
    return '${dir.path}/moodsogood_daily_records.db';
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
      final record = {
        'id': id,
        'userId': userId,
        'date': date.toIso8601String(),
        'emotions': emotions != null ? jsonEncode(emotions) : null,
        'sleep': sleep != null ? jsonEncode(sleep) : null,
        'bodySymptoms': bodySymptoms != null ? jsonEncode(bodySymptoms) : null,
        'dailyActivities': dailyActivities != null ? jsonEncode(dailyActivities) : null,
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
    } catch (e, st) {
      debugPrint('❌ Error saving daily record: $e\nStacktrace: $st');
      rethrow;
    }
  }

  /// 獲取特定日期的記錄
  Future<Map<String, dynamic>?> getDailyRecord({
    required String userId,
    required DateTime date,
  }) async {
    if (!_initialized) await init();

    try {
      // 按日期範圍查詢（整天）
      final startOfDay = DateTime(date.year, date.month, date.day).toIso8601String();
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59).toIso8601String();
      
      final results = await _db.query(
        'daily_records',
        where: 'userId = ? AND date >= ? AND date < ?',
        whereArgs: [userId, startOfDay, endOfDay],
        limit: 1,
      );

      if (results.isEmpty) return null;

      return _decodeRecord(results.first);
    } catch (e) {
      print('Error fetching daily record: $e');
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
      final results = await _db.query(
        'daily_records',
        where: 'userId = ? AND date >= ? AND date <= ?',
        whereArgs: [
          userId,
          startDate.toIso8601String(),
          endDate.toIso8601String(),
        ],
        orderBy: 'date DESC',
      );

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
      'emotions': record['emotions'] != null ? jsonDecode(record['emotions']) : null,
      'sleep': record['sleep'] != null ? jsonDecode(record['sleep']) : null,
      'bodySymptoms': record['bodySymptoms'] != null ? jsonDecode(record['bodySymptoms']) : null,
      'dailyActivities': record['dailyActivities'] != null ? jsonDecode(record['dailyActivities']) : null,
      'medicines': record['medicines'] != null ? jsonDecode(record['medicines']) : null,
      'periodData': record['periodData'] != null ? jsonDecode(record['periodData']) : null,
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
