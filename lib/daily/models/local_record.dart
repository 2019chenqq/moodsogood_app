import 'package:isar/isar.dart';

// 執行 flutter pub run build_runner build 後會自動生成
part 'local_record.g.dart';

@collection
class LocalRecord {
  Id id = Isar.autoIncrement; // 本地唯一識別碼

  @Index(unique: true, replace: true)
  late DateTime date; // 以日期作為索引，確保一天只有一筆

  double? overallMood; // 心情分數 (0-10)
  String? note;       // 心情筆記
  
  // 同步標記 (方案 C 的核心)
  bool isSynced = false; 
  DateTime? updatedAt;   // 用於判斷雲端與本地誰比較新
}