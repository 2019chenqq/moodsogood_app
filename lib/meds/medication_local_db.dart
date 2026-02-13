import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class MedicationLocalDB {
  static final MedicationLocalDB _instance = MedicationLocalDB._internal();
  static Database? _database;

  factory MedicationLocalDB() {
    return _instance;
  }

  MedicationLocalDB._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'medications.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE medications (
            id TEXT PRIMARY KEY,
            uid TEXT NOT NULL,
            name TEXT NOT NULL,
            dose REAL,
            unit TEXT,
            type TEXT,
            intervalDays INTEGER,
            times TEXT,
            purposes TEXT,
            note TEXT,
            startDate TEXT,
            isActive INTEGER DEFAULT 1,
            bodySymptoms TEXT,
            purposeOther TEXT,
            createdAt TEXT,
            updatedAt TEXT,
            lastChangeAt TEXT
          )
        ''');
        
        await db.execute('''
          CREATE TABLE medAdjustments (
            id TEXT PRIMARY KEY,
            uid TEXT NOT NULL,
            date TEXT NOT NULL,
            note TEXT,
            items TEXT,
            createdAt TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        debugPrint('📦 資料庫升級：$oldVersion → $newVersion');
        
        // 從版本 1 升級到版本 2：創建 medAdjustments 表
        if (oldVersion < 2) {
          debugPrint('🔨 創建 medAdjustments 表...');
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS medAdjustments (
                id TEXT PRIMARY KEY,
                uid TEXT NOT NULL,
                date TEXT NOT NULL,
                note TEXT,
                items TEXT,
                createdAt TEXT
              )
            ''');
            debugPrint('✅ medAdjustments 表創建成功');
          } catch (e) {
            debugPrint('❌ 創建 medAdjustments 表失敗：$e');
            rethrow;
          }
        }
      },
    );
  }

  // 新增藥物
  Future<void> addMedication(String uid, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'medications',
      {
        'id': data['id'],
        'uid': uid,
        'name': data['name'],
        'dose': data['dose'],
        'unit': data['unit'],
        'type': data['type'],
        'intervalDays': data['intervalDays'],
        'times': _encodeList(data['times']),
        'purposes': _encodeList(data['purposes']),
        'note': data['note'],
        'startDate': data['startDate'],
        'isActive': (data['isActive'] ?? true) ? 1 : 0,
        'bodySymptoms': _encodeList(data['bodySymptoms']),
        'purposeOther': data['purposeOther'],
        'createdAt': data['createdAt'],
        'updatedAt': data['updatedAt'],
        'lastChangeAt': data['lastChangeAt'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 更新藥物
  Future<void> updateMedication(String uid, String docId, Map<String, dynamic> data) async {
    try {
      final db = await database;
      debugPrint('📝 更新藥物 - docId: $docId, uid: $uid');
      
      await db.update(
        'medications',
        {
          'name': data['name'],
          'dose': data['dose'],
          'unit': data['unit'],
          'type': data['type'],
          'intervalDays': data['intervalDays'],
          'times': _encodeList(data['times']),
          'purposes': _encodeList(data['purposes']),
          'note': data['note'],
          'startDate': data['startDate'],
          'isActive': (data['isActive'] ?? true) ? 1 : 0,
          'bodySymptoms': _encodeList(data['bodySymptoms']),
          'purposeOther': data['purposeOther'],
          'updatedAt': data['updatedAt'],
          'lastChangeAt': data['lastChangeAt'],
        },
        where: 'id = ? AND uid = ?',
        whereArgs: [docId, uid],
      );
      debugPrint('✅ 藥物更新成功');
    } catch (e) {
      debugPrint('❌ updateMedication 失敗：$e');
      rethrow;
    }
  }

  // 僅更新「停用/恢復」狀態（避免覆蓋其他欄位）
  Future<void> updateMedicationStatus(
    String uid,
    String docId, {
    required bool isActive,
    String? updatedAt,
    String? lastChangeAt,
  }) async {
    try {
      final db = await database;
      debugPrint('📝 更新藥物狀態 - docId: $docId, uid: $uid, isActive: $isActive');

      await db.update(
        'medications',
        {
          'isActive': isActive ? 1 : 0,
          if (updatedAt != null) 'updatedAt': updatedAt,
          if (lastChangeAt != null) 'lastChangeAt': lastChangeAt,
        },
        where: 'id = ? AND uid = ?',
        whereArgs: [docId, uid],
      );
      debugPrint('✅ 藥物狀態更新成功');
    } catch (e) {
      debugPrint('❌ updateMedicationStatus 失敗：$e');
      rethrow;
    }
  }

  // 删除藥物
  Future<void> deleteMedication(String uid, String docId) async {
    final db = await database;
    await db.delete(
      'medications',
      where: 'id = ? AND uid = ?',
      whereArgs: [docId, uid],
    );
  }

  // 獲取用戶的所有藥物
  Future<List<Map<String, dynamic>>> getMedications(String uid) async {
    final db = await database;
    return db.query(
      'medications',
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'isActive DESC, updatedAt DESC',
    );
  }

  // 獲取單個藥物
  Future<Map<String, dynamic>?> getMedication(String uid, String docId) async {
    final db = await database;
    final results = await db.query(
      'medications',
      where: 'id = ? AND uid = ?',
      whereArgs: [docId, uid],
    );
    return results.isNotEmpty ? results.first : null;
  }

  // 辅助方法：编码 List
  String _encodeList(dynamic value) {
    if (value is List) {
      return value.join(',');
    }
    return '';
  }

  // 辅助方法：解码 List
  List<String> _decodeList(String? value) {
    if (value == null || value.isEmpty) return [];
    return value.split(',').where((s) => s.isNotEmpty).toList();
  }

  // 转换为 Map（用于 UI 显示）
  Future<List<Map<String, dynamic>>> getMedicationsForDisplay(String uid) async {
    final rawMeds = await getMedications(uid);
    return rawMeds.map((m) {
      return {
        'id': m['id'],
        'uid': m['uid'],
        'name': m['name'],
        'dose': m['dose'],
        'unit': m['unit'],
        'type': m['type'],
        'intervalDays': m['intervalDays'],
        'times': _decodeList(m['times']),
        'purposes': _decodeList(m['purposes']),
        'note': m['note'],
        'startDate': m['startDate'],
        'isActive': (m['isActive'] ?? 1) == 1,
        'bodySymptoms': _decodeList(m['bodySymptoms']),
        'purposeOther': m['purposeOther'],
        'createdAt': m['createdAt'],
        'updatedAt': m['updatedAt'],
        'lastChangeAt': m['lastChangeAt'],
      };
    }).toList();
  }

  // 清除所有数据（仅用于调试）
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('medications');
  }

  // 添加調整記錄到本地 DB
  Future<void> addAdjustmentRecord(String uid, String docId, Map<String, dynamic> data) async {
    try {
      final db = await database;
      final itemsJson = data['items'] ?? [];
      
      // 序列化 items
      String itemsJsonStr;
      try {
        itemsJsonStr = jsonEncode(itemsJson);
        debugPrint('✅ items 序列化成功：$itemsJsonStr');
      } catch (e) {
        debugPrint('❌ items 序列化失敗：$e');
        itemsJsonStr = '[]';
      }
      
      debugPrint('💾 插入調整記錄到本地 DB - id: $docId, uid: $uid, date: ${data["date"]}');
      
      await db.insert(
        'medAdjustments',
        {
          'id': docId,
          'uid': uid,
          'date': data['date'],
          'note': data['note'],
          'items': itemsJsonStr,
          'createdAt': data['createdAt'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      debugPrint('✅ 調整記錄插入成功');
    } catch (e) {
      debugPrint('❌ addAdjustmentRecord 失敗：$e');
      rethrow;
    }
  }

  // 獲取用戶的所有調整記錄（按日期倒序）
  Future<List<Map<String, dynamic>>> getAdjustmentRecords(String uid) async {
    final db = await database;
    final results = await db.query(
      'medAdjustments',
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'date DESC',
    );
    return results;
  }

  // 轉換調整記錄為 Map（用於 UI 顯示）
  Future<List<Map<String, dynamic>>> getAdjustmentRecordsForDisplay(String uid) async {
    final rawRecords = await getAdjustmentRecords(uid);
    return rawRecords.map((r) {
      // 解析 items（存儲為 JSON 字符串）
      final itemsStr = r['items'] as String?;
      List<dynamic> items = [];
      
      if (itemsStr != null && itemsStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(itemsStr);
          if (decoded is List) {
            items = decoded;
          }
        } catch (e) {
          debugPrint('❌ 解析 items 失敗：$e');
          items = [];
        }
      }
      
      return {
        'id': r['id'],
        'uid': r['uid'],
        'date': r['date'],
        'note': r['note'],
        'items': items,
        'createdAt': r['createdAt'],
      };
    }).toList();
  }
}