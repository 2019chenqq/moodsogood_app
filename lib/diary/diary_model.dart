import 'package:cloud_firestore/cloud_firestore.dart';

class DiaryDoc {
  final String id;
  final String uid;
  final DateTime date;         // 只放日期（不含時分秒），方便查詢
  final double moodScore;
  final String? moodKeyword;
  final String themeSong;
  final String highlight;
  final String metaphor;
  final String proudOf;
  final String selfCare;
  final DateTime createdAt;
  final DateTime updatedAt;

  DiaryDoc({
    required this.id,
    required this.uid,
    required this.date,
    required this.moodScore,
    this.moodKeyword,
    this.themeSong = '',
    this.highlight = '',
    this.metaphor = '',
    this.proudOf = '',
    this.selfCare = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory DiaryDoc.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data()!;
    return DiaryDoc(
      id: s.id,
      uid: d['uid'] as String,
      date: (d['date'] as Timestamp).toDate(),
      moodScore: (d['moodScore'] as num).toDouble(),
      moodKeyword: d['moodKeyword'] as String?,
      themeSong: d['themeSong'] as String? ?? '',
      highlight: d['highlight'] as String? ?? '',
      metaphor: d['metaphor'] as String? ?? '',
      proudOf: d['proudOf'] as String? ?? '',
      selfCare: d['selfCare'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      updatedAt: (d['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
    'moodScore': moodScore,
    'moodKeyword': moodKeyword,
    'themeSong': themeSong,
    'highlight': highlight,
    'metaphor': metaphor,
    'proudOf': proudOf,
    'selfCare': selfCare,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };
}
