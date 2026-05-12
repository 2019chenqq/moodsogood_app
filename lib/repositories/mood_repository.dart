import 'package:isar/isar.dart';
import '../daily/models/local_record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart'; // 解決 debugPrint 報錯
import 'package:cloud_firestore/cloud_firestore.dart'; // 解決 FirebaseFirestore 與 FieldValue 報錯
import '../daily/models/local_record.dart'; // 確保路徑與你的檔案結構一致

class MoodRepository {
  late Future<Isar> db;

  MoodRepository() {
    db = openDB();
  }

  // 初始化 Isar 資料庫
  Future<Isar> openDB() async {
    final dir = await getApplicationDocumentsDirectory();
    if (Isar.instanceNames.isEmpty) {
      return await Isar.open(
        [LocalRecordSchema],
        directory: dir.path,
      );
    }
    return Isar.getInstance()!;
  }

  // 【方案 C 的 SQL Connect 同等功能】
  // 獲取趨勢數據：這裡跑的是本地的高效能查詢
  Future<List<LocalRecord>> getTrendData(int days) async {
    final isar = await db;
    return await isar.localRecords
        .where()
        .filter()
        .dateGreaterThan(DateTime.now().subtract(Duration(days: days)))
        .sortByDate()
        .findAll();
  }

  // 儲存紀錄：非 Pro 直接存，Pro 則標記待同步
  Future<void> saveRecord(LocalRecord record, bool isPro) async {
    final isar = await db;
    await isar.writeTxn(() async {
      record.updatedAt = DateTime.now();
      record.isSynced = isPro ? false : true; // 非 Pro 視為已同步(不需傳雲端)
      await isar.localRecords.put(record);
    });
    
    // 如果是 Pro 方案，在這裡呼叫 Firebase 同步邏輯
    if (isPro) {
      _syncToFirebase(record);
    }
  }

  Future<void> _syncToFirebase(LocalRecord record) async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // 使用日期作為 Document ID (例如 2026-05-12)，這樣同一天的紀錄會自動覆蓋，不會重複
      final docId = record.date.toIso8601String().split('T')[0]; 

      // 1. 將資料上傳到 Firestore
      await firestore.collection('mood_records').doc(docId).set({
        'overallMood': record.overallMood,
        'note': record.note,
        'date': record.date,
        'updatedAt': FieldValue.serverTimestamp(), // 使用伺服器時間戳記
      });

      // 2. 上傳成功後，修改本地 Isar 的狀態為「已同步」
      final isar = await db;
      await isar.writeTxn(() async {
        record.isSynced = true;
        await isar.localRecords.put(record);
      });
      
      debugPrint("心域雲端同步成功：$docId");
    } catch (e) {
      // 如果網路斷線或權限錯誤會跑到這裡
      debugPrint("雲端同步失敗，資料仍保存在本地：$e");
    }
  }
  }