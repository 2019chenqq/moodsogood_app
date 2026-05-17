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
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE medications (
            id TEXT PRIMARY KEY,
            uid TEXT NOT NULL,
            name TEXT NOT NULL,
            dose REAL,
            dosePerUnit REAL,
            pillCount REAL,
            concentrationMg REAL,
            concentrationMl REAL,
            intakeMl REAL,
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
            lastChangeAt TEXT,
            lastChangedAt TEXT,
            resumedAt TEXT
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

        if (oldVersion < 3) {
          debugPrint('🔨 新增 dosePerUnit/pillCount 欄位...');
          await _ensureMedicationColumns(db, {
            'dosePerUnit': 'REAL',
            'pillCount': 'REAL',
          });
        }

        if (oldVersion < 4) {
          debugPrint('🔨 新增 concentration/intake 欄位...');
          await _ensureMedicationColumns(db, {
            'concentrationMg': 'REAL',
            'concentrationMl': 'REAL',
            'intakeMl': 'REAL',
          });
        }

        if (oldVersion < 5) {
          debugPrint('🔨 新增 resumedAt/lastChangedAt/isActive 欄位...');
          await _ensureMedicationColumns(db, {
            'resumedAt': 'TEXT',
            'lastChangedAt': 'TEXT',
            'isActive': 'INTEGER DEFAULT 1',
          });
        }
      },
    );
  }

  Future<Set<String>> _getTableColumns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows
        .map((r) => (r['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  Future<void> _ensureMedicationColumns(
    Database db,
    Map<String, String> columns,
  ) async {
    final existing = await _getTableColumns(db, 'medications');
    for (final entry in columns.entries) {
      if (existing.contains(entry.key)) continue;
      debugPrint('🧩 補齊 medications.${entry.key} 欄位...');
      await db.execute('ALTER TABLE medications ADD COLUMN ${entry.key} ${entry.value}');
    }
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
        'dosePerUnit': data['dosePerUnit'],
        'pillCount': data['pillCount'],
        'concentrationMg': data['concentrationMg'],
        'concentrationMl': data['concentrationMl'],
        'intakeMl': data['intakeMl'],
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
          'dosePerUnit': data['dosePerUnit'],
          'pillCount': data['pillCount'],
          'concentrationMg': data['concentrationMg'],
          'concentrationMl': data['concentrationMl'],
          'intakeMl': data['intakeMl'],
          'unit': data['unit'],
          'type': data['type'],
          'intervalDays': data['intervalDays'],
          'times': _encodeList(data['times']),
          'purposes': _encodeList(data['purposes']),
          'note': data['note'],
          'startDate': data['startDate'],
          'isActive': _encodeBool(data['isActive'], defaultTrue: true),
          'bodySymptoms': _encodeList(data['bodySymptoms']),
          'purposeOther': data['purposeOther'],
          'updatedAt': data['updatedAt'],
          'lastChangeAt': data['lastChangeAt'],
          if (data.containsKey('resumedAt')) 'resumedAt': data['resumedAt'],
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
    if (value is Iterable) {
      return value.join(',');
    }
    if (value is String) {
      return value;
    }
    return '';
  }

  // 辅助方法：編碼 bool → 0/1
  int _encodeBool(dynamic value, {bool defaultTrue = false}) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value == 0 ? 0 : 1;
    return defaultTrue ? 1 : 0;
  }

  // 辅助方法：解码 List
  List<String> _decodeList(String? value) {
    if (value == null || value.isEmpty) return [];
    return value
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
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
        'dosePerUnit': m['dosePerUnit'],
        'pillCount': m['pillCount'],
        'concentrationMg': m['concentrationMg'],
        'concentrationMl': m['concentrationMl'],
        'intakeMl': m['intakeMl'],
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
        'resumedAt': m['resumedAt'],
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

  // ── 修正：回診調藥後同步更新藥物卡的劑量欄位 ─────────────────────────
  //
  // 說明：
  //   回診調藥記錄（medAdjustments）只儲存「總劑量變化」，不會自動更新
  //   藥物卡的 dosePerUnit / pillCount。
  //   請在「儲存調整記錄」的 function 裡，針對 action == 'adjust' 的每筆
  //   change，呼叫此方法，讓本地 DB 藥物卡與打卡頁同步。
  //
  // 參數說明：
  //   medId       → medications.id（藥物卡的主鍵）
  //   dosePerUnit → 每顆（每單位）劑量，例如 25.0
  //   pillCount   → 每次顆數，例如 2.0
  //   unit        → 單位字串，例如 'mg'
  //
  // 使用範例（在調藥儲存 function 裡）：
  //   for (final change in changes) {
  //     if (change['action'] == 'adjust') {
  //       await MedicationLocalDB().applyAdjustmentToMedication(
  //         uid,
  //         change['medId'],
  //         dosePerUnit : change['dosePerUnit'],
  //         pillCount   : change['pillCount'],
  //         unit        : change['unit'] ?? 'mg',
  //       );
  //     }
  //   }
  Future<void> applyAdjustmentToMedication(
    String uid,
    String medId, {
    required double dosePerUnit,
    required double pillCount,
    required String unit,
  }) async {
    try {
      final db = await database;
      final totalDose = _roundDose(dosePerUnit * pillCount);
      final now = DateTime.now().toIso8601String();

      debugPrint('💊 applyAdjustmentToMedication: medId=$medId '
          'dosePerUnit=$dosePerUnit × pillCount=$pillCount = $totalDose $unit');

      final rows = await db.query(
        'medications',
        columns: ['id'],
        where: 'id = ? AND uid = ?',
        whereArgs: [medId, uid],
      );
      if (rows.isEmpty) {
        debugPrint('⚠️ applyAdjustmentToMedication: 找不到藥物 $medId，略過');
        return;
      }

      await db.update(
        'medications',
        {
          'dose'        : totalDose,
          'dosePerUnit' : dosePerUnit,
          'pillCount'   : pillCount,
          'unit'        : unit,
          'updatedAt'   : now,
          'lastChangeAt': now,
        },
        where: 'id = ? AND uid = ?',
        whereArgs: [medId, uid],
      );
      debugPrint('✅ 藥物卡劑量已同步：$totalDose $unit ($dosePerUnit × $pillCount)');
    } catch (e) {
      debugPrint('❌ applyAdjustmentToMedication 失敗：$e');
      rethrow;
    }
  }

  // 四捨五入到小數點後一位
  double _roundDose(double v) => (v * 10).round() / 10;
}