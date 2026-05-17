import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../daily/models/local_record.dart';

class MoodRepository {
  final Future<Isar> db;

  MoodRepository() : db = openDB();

  static Future<Isar> openDB() async {
    final dir = await getApplicationDocumentsDirectory();
    final existing = Isar.getInstance();
    if (existing != null) return existing;

    return Isar.open(
      [LocalRecordSchema],
      directory: dir.path,
    );
  }

  /// [days] 為 null 時代表查詢全部資料
  Future<List<LocalRecord>> getTrendData(int? days) async {
    final isar = await db;

    if (days == null) {
      return isar.localRecords.where().anyDate().sortByDate().findAll();
    }

    final fromDate = DateTime.now().subtract(Duration(days: days));

    return isar.localRecords
        .where()
        .dateGreaterThan(fromDate)
        .sortByDate()
        .findAll();
  }

  Future<void> saveRecord(LocalRecord record, bool isPro) async {
    final isar = await db;

    await isar.writeTxn(() async {
      record.updatedAt = DateTime.now();
      record.isSynced = !isPro;
      await isar.localRecords.put(record);
    });

    if (isPro) {
      await _syncToFirebase(record);
    }
  }

  Future<void> _syncToFirebase(LocalRecord record) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final docId = record.date.toIso8601String().split('T')[0];

      await firestore.collection('mood_records').doc(docId).set({
        'overallMood': record.overallMood,
        'note': record.note,
        'date': record.date,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final isar = await db;

      await isar.writeTxn(() async {
        record.isSynced = true;
        await isar.localRecords.put(record);
      });

      debugPrint("心域雲端同步成功：$docId");
    } catch (e) {
      debugPrint("雲端同步失敗，資料仍保存在本地：$e");
    }
  }

  /// 取得按月平均的趨勢數據
  Future<Map<String, double>> getMonthlyAverages() async {
    final isar = await db;

    final allRecords = await isar.localRecords.where().sortByDate().findAll();

    final Map<String, List<double>> groupedData = {};

    for (final record in allRecords) {
      final mood = record.overallMood;

      if (mood != null) {
        final monthKey =
            "${record.date.year}-${record.date.month.toString().padLeft(2, '0')}";

        groupedData.putIfAbsent(monthKey, () => []).add(mood);
      }
    }

    return groupedData.map(
      (key, scores) => MapEntry(
        key,
        scores.reduce((a, b) => a + b) / scores.length,
      ),
    );
  }
}