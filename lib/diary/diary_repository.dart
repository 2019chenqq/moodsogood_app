import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/encryption_service.dart';
import '../utils/secure_storage_service.dart';
import 'diary_image_encryption_service.dart';

class DiaryEntry {
  final int? id;
  final DateTime date;
  final String title;
  final String content;
  final double? moodScore;
  final double? overallHealth;
  final String? moodKeyword;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? themeSong;
  final String? highlight;
  final String? metaphor;
  final String? proudOf;
  final String? selfCare;
  final String? gratitude;
  final String? themeSongProvider;
  final String? themeSongProviderId;
  final String? themeSongTitle;
  final String? themeSongArtist;
  final String? themeSongAlbum;
  final String? themeSongArtworkUrl;
  final String? themeSongExternalUrl;
  final String? themeSongIsrc;
  final String? themeSongRecommendationReason;
  final List<String> imageUrls;

  DiaryEntry({
    this.id,
    required this.date,
    required this.title,
    required this.content,
    this.moodScore,
    this.overallHealth,
    this.moodKeyword,
    this.themeSong,
    this.highlight,
    this.metaphor,
    this.proudOf,
    this.selfCare,
    this.gratitude,
    this.themeSongProvider,
    this.themeSongProviderId,
    this.themeSongTitle,
    this.themeSongArtist,
    this.themeSongAlbum,
    this.themeSongArtworkUrl,
    this.themeSongExternalUrl,
    this.themeSongIsrc,
    this.themeSongRecommendationReason,
    this.imageUrls = const [],
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
    double? overallHealth,
    String? moodKeyword,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? themeSong,
    String? highlight,
    String? metaphor,
    String? proudOf,
    String? selfCare,
    String? gratitude,
    String? themeSongProvider,
    String? themeSongProviderId,
    String? themeSongTitle,
    String? themeSongArtist,
    String? themeSongAlbum,
    String? themeSongArtworkUrl,
    String? themeSongExternalUrl,
    String? themeSongIsrc,
    String? themeSongRecommendationReason,
    List<String>? imageUrls,
  }) {
    return DiaryEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      title: title ?? this.title,
      content: content ?? this.content,
      moodScore: moodScore ?? this.moodScore,
      overallHealth: overallHealth ?? this.overallHealth,
      moodKeyword: moodKeyword ?? this.moodKeyword,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      themeSong: themeSong ?? this.themeSong,
      highlight: highlight ?? this.highlight,
      metaphor: metaphor ?? this.metaphor,
      proudOf: proudOf ?? this.proudOf,
      selfCare: selfCare ?? this.selfCare,
      gratitude: gratitude ?? this.gratitude,
      themeSongProvider: themeSongProvider ?? this.themeSongProvider,
      themeSongProviderId: themeSongProviderId ?? this.themeSongProviderId,
      themeSongTitle: themeSongTitle ?? this.themeSongTitle,
      themeSongArtist: themeSongArtist ?? this.themeSongArtist,
      themeSongAlbum: themeSongAlbum ?? this.themeSongAlbum,
      themeSongArtworkUrl: themeSongArtworkUrl ?? this.themeSongArtworkUrl,
      themeSongExternalUrl: themeSongExternalUrl ?? this.themeSongExternalUrl,
      themeSongIsrc: themeSongIsrc ?? this.themeSongIsrc,
      themeSongRecommendationReason:
          themeSongRecommendationReason ?? this.themeSongRecommendationReason,
      imageUrls: imageUrls ?? this.imageUrls,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'title': title,
        'content': content,
        'moodScore': moodScore,
        'overallHealth': overallHealth,
        'moodKeyword': moodKeyword,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'themeSong': themeSong,
        'highlight': highlight,
        'metaphor': metaphor,
        'proudOf': proudOf,
        'selfCare': selfCare,
        'gratitude': gratitude,
        'themeSongProvider': themeSongProvider,
        'themeSongProviderId': themeSongProviderId,
        'themeSongTitle': themeSongTitle,
        'themeSongArtist': themeSongArtist,
        'themeSongAlbum': themeSongAlbum,
        'themeSongArtworkUrl': themeSongArtworkUrl,
        'themeSongExternalUrl': themeSongExternalUrl,
        'themeSongIsrc': themeSongIsrc,
        'themeSongRecommendationReason': themeSongRecommendationReason,
        'imageUrls': imageUrls,
      };
}

class DiaryRepository {
  static final DiaryRepository _instance = DiaryRepository._internal();

  factory DiaryRepository() => _instance;

  DiaryRepository._internal();

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _entries =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('diary');

  Future<int> insert(DiaryEntry entry) => upsert(entry);

  Future<int> update(DiaryEntry entry) => upsert(entry);

  Future<List<DiaryEntry>> list({int limit = 200, int offset = 0}) async {
    final snapshot = await _entries
        .orderBy('date', descending: true)
        .limit(limit + offset)
        .get();
    final docs = snapshot.docs.skip(offset);
    return _decodeDocuments(docs);
  }

  Future<List<DiaryEntry>> listInRange(DateTime start, DateTime end) async {
    final from = DateTime(start.year, start.month, start.day);
    final through = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    final snapshot = await _entries
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(through))
        .orderBy('date')
        .get();
    return _decodeDocuments(snapshot.docs);
  }

  Future<DiaryEntry?> getById(int id) async {
    final date = _dateFromInt(id);
    return getByDate(date);
  }

  Future<DiaryEntry?> getByDate(DateTime date) async {
    final doc = await _entries.doc(_dateId(date)).get();
    if (!doc.exists || doc.data() == null) return null;
    final entries = await _decodeDocuments([doc]);
    return entries.isEmpty ? null : entries.first;
  }

  Future<int> upsert(DiaryEntry entry) async {
    final key = await SecureStorageService.getOrRecoverKey();
    if (key == null) throw StateError('Encryption key is unavailable.');
    final encryption = EncryptionService(key);
    await _entries.doc(_dateId(entry.date)).set({
      'date': Timestamp.fromDate(entry.date),
      'title': encryption.encryptData(entry.title),
      'content': encryption.encryptData(entry.content),
      'themeSong': encryption.encryptData(entry.themeSong ?? ''),
      'highlight': encryption.encryptData(entry.highlight ?? ''),
      'metaphor': encryption.encryptData(entry.metaphor ?? ''),
      'proudOf': encryption.encryptData(entry.proudOf ?? ''),
      'selfCare': encryption.encryptData(entry.selfCare ?? ''),
      'gratitude': encryption.encryptData(entry.gratitude ?? ''),
      'themeSongProvider':
          encryption.encryptData(entry.themeSongProvider ?? ''),
      'themeSongProviderId':
          encryption.encryptData(entry.themeSongProviderId ?? ''),
      'themeSongTitle': encryption.encryptData(entry.themeSongTitle ?? ''),
      'themeSongArtist': encryption.encryptData(entry.themeSongArtist ?? ''),
      'themeSongAlbum': encryption.encryptData(entry.themeSongAlbum ?? ''),
      'themeSongArtworkUrl':
          encryption.encryptData(entry.themeSongArtworkUrl ?? ''),
      'themeSongExternalUrl':
          encryption.encryptData(entry.themeSongExternalUrl ?? ''),
      'themeSongIsrc': encryption.encryptData(entry.themeSongIsrc ?? ''),
      'themeSongRecommendationReason':
          encryption.encryptData(entry.themeSongRecommendationReason ?? ''),
      'imageUrls': DiaryImageEncryptionService.encodeImageSources(
        entry.imageUrls,
        encryption,
      ),
      'imageRefsEncrypted': true,
      'imageEncryptionVersion': DiaryImageEncryptionService.migrationVersion,
      'overallMood': entry.moodScore,
      'overallHealth': entry.overallHealth,
      'updatedAt': FieldValue.serverTimestamp(),
      'isEncrypted': true,
    }, SetOptions(merge: true));
    return _dateInt(entry.date);
  }

  Future<int> delete(int id) => deleteByDate(_dateFromInt(id));

  Future<int> deleteByDate(DateTime date) async {
    final ref = _entries.doc(_dateId(date));
    final snapshot = await ref.get();
    var imageSources = const <String>[];
    final data = snapshot.data();
    if (data != null) {
      final key = await SecureStorageService.getOrRecoverKey();
      if (key != null) {
        imageSources = DiaryImageEncryptionService.decodeImageSources(
          data,
          EncryptionService(key),
        );
      }
    }
    await ref.delete();
    for (final source in imageSources) {
      try {
        await DiaryImageEncryptionService.deleteSource(source);
      } catch (_) {}
    }
    return 1;
  }

  Future<List<DiaryEntry>> _decodeDocuments(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final key = await SecureStorageService.getOrRecoverKey();
    if (key == null) throw StateError('Encryption key is unavailable.');
    final encryption = EncryptionService(key);
    return docs.map((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
      final date = _asDate(data['date']) ?? _dateFromId(doc.id);
      String text(String field) {
        final value = data[field]?.toString() ?? '';
        return data['isEncrypted'] == true
            ? encryption.tryDecryptData(value) ?? ''
            : value;
      }

      return DiaryEntry(
        id: _dateInt(date),
        date: date,
        title: text('title'),
        content: text('content'),
        themeSong: text('themeSong'),
        highlight: text('highlight'),
        metaphor: text('metaphor'),
        proudOf: text('proudOf'),
        selfCare: text('selfCare'),
        gratitude: text('gratitude'),
        themeSongProvider: text('themeSongProvider'),
        themeSongProviderId: text('themeSongProviderId'),
        themeSongTitle: text('themeSongTitle'),
        themeSongArtist: text('themeSongArtist'),
        themeSongAlbum: text('themeSongAlbum'),
        themeSongArtworkUrl: text('themeSongArtworkUrl'),
        themeSongExternalUrl: text('themeSongExternalUrl'),
        themeSongIsrc: text('themeSongIsrc'),
        themeSongRecommendationReason: text('themeSongRecommendationReason'),
        imageUrls: DiaryImageEncryptionService.decodeImageSources(
          data,
          encryption,
        ),
        moodScore: (data['overallMood'] as num?)?.toDouble(),
        overallHealth: (data['overallHealth'] as num?)?.toDouble(),
        createdAt: _asDate(data['createdAt']),
        updatedAt: _asDate(data['updatedAt']),
      );
    }).toList();
  }

  DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _dateId(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  int _dateInt(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  DateTime _dateFromInt(int value) {
    return DateTime(value ~/ 10000, (value ~/ 100) % 100, value % 100);
  }

  DateTime _dateFromId(String id) =>
      DateTime.tryParse(id) ?? DateTime.fromMillisecondsSinceEpoch(0);
}
