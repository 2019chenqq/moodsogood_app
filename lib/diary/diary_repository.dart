import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DiaryEntry {
  final int? id;
  final DateTime date;
  final String title;
  final String content;
  final double? moodScore;
  final String? moodKeyword;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? themeSong;
  final String? highlight;
  final String? metaphor;
  final String? proudOf;
  final String? selfCare;

  DiaryEntry({
  this.id,
  required this.date,
  required this.title,
  required this.content,
  this.moodScore,
  this.moodKeyword,
  // ★ 這五個是新加的，可為 null，建構子要接起來
  this.themeSong,
  this.highlight,
  this.metaphor,
  this.proudOf,
  this.selfCare,
  // 時間欄位給預設值
  DateTime? createdAt,
  DateTime? updatedAt,
})  : createdAt = createdAt ?? DateTime.now(),
      updatedAt = updatedAt ?? DateTime.now();

  DiaryEntry copyWith({
    int? id,
    DateTime? date,
    String? title,
    String? content,
    double? moodScore,
    String? moodKeyword,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? themeSong,
    String? highlight,
    String? metaphor,
    String? proudOf,
    String? selfCare,
  }) {
    return DiaryEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      title: title ?? this.title,
      content: content ?? this.content,
      moodScore: moodScore ?? this.moodScore,
      moodKeyword: moodKeyword ?? this.moodKeyword,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      themeSong: themeSong ?? this.themeSong,
      highlight: highlight ?? this.highlight,
      metaphor: metaphor ?? this.metaphor,
      proudOf: proudOf ?? this.proudOf,
      selfCare: selfCare ?? this.selfCare,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'title': title,
        'content': content,
        'moodScore': moodScore,
        'moodKeyword': moodKeyword,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'themeSong': themeSong,
        'highlight': highlight,
        'metaphor': metaphor,
        'proudOf': proudOf,
        'selfCare': selfCare,
      };

  static DiaryEntry fromMap(Map<String, Object?> m) => DiaryEntry(
        id: m['id'] as int?,
        date: DateTime.parse(m['date'] as String),
        title: (m['title'] as String?) ?? '',
        content: (m['content'] as String?) ?? '',
        // sqflite 可能回 int 或 double，轉成 double 保險
        moodScore: (m['moodScore'] as num?)?.toDouble(),
        moodKeyword: m['moodKeyword'] as String?,
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
        themeSong: m['themeSong'] as String?,
        highlight: m['highlight'] as String?,
        metaphor: m['metaphor'] as String?,
        proudOf: m['proudOf'] as String?,
        selfCare: m['selfCare'] as String?,
      );
}

class DiaryRepository {
  static final DiaryRepository _instance = DiaryRepository._internal();
  factory DiaryRepository() => _instance;
  DiaryRepository._internal();

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final docs = await getApplicationDocumentsDirectory();
    final dbPath = '${docs.path}/mood_so_good.db';
    _db = await openDatabase(
      dbPath,
      version: 2, // 增加版本號以觸發升級
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE diary_entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          moodScore REAL,
          moodKeyword TEXT,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL,
          themeSong TEXT,
          highlight TEXT,
          metaphor TEXT,
          proudOf TEXT,
          selfCare TEXT
        );
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_diary_date ON diary_entries(date DESC);');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 添加新欄位（如果舊資料庫不存在這些欄位）
          await db.execute('ALTER TABLE diary_entries ADD COLUMN themeSong TEXT;');
          await db.execute('ALTER TABLE diary_entries ADD COLUMN highlight TEXT;');
          await db.execute('ALTER TABLE diary_entries ADD COLUMN metaphor TEXT;');
          await db.execute('ALTER TABLE diary_entries ADD COLUMN proudOf TEXT;');
          await db.execute('ALTER TABLE diary_entries ADD COLUMN selfCare TEXT;');
        }
      },
    );
    return _db!;
  }

  Future<int> insert(DiaryEntry entry) async {
    final db = await _open();
    return db.insert('diary_entries', entry.toMap());
  }

  Future<int> update(DiaryEntry entry) async {
    if (entry.id == null) throw StateError('update 需要 id');
    final db = await _open();
    return db.update(
      'diary_entries',
      entry.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<List<DiaryEntry>> list({int limit = 200, int offset = 0}) async {
    final db = await _open();
    final rows = await db.query(
      'diary_entries',
      orderBy: 'date DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(DiaryEntry.fromMap).toList();
  }

  Future<DiaryEntry?> getById(int id) async {
    final db = await _open();
    final rows = await db.query('diary_entries', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return DiaryEntry.fromMap(rows.first);
  }

  /// 按日期查詢日記
  Future<DiaryEntry?> getByDate(DateTime date) async {
    final db = await _open();
    final dateStr = date.toIso8601String().split('T')[0]; // yyyy-MM-dd
    final rows = await db.query(
      'diary_entries',
      where: 'date LIKE ?',
      whereArgs: ['$dateStr%'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DiaryEntry.fromMap(rows.first);
  }

  /// Upsert：如果該日期的日記已存在則更新，否則插入
  Future<int> upsert(DiaryEntry entry) async {
    final existing = await getByDate(entry.date);
    if (existing != null) {
      return await update(entry.copyWith(id: existing.id));
    } else {
      return await insert(entry);
    }
  }

  Future<int> delete(int id) async {
    final db = await _open();
    return db.delete('diary_entries', where: 'id = ?', whereArgs: [id]);
  }
}