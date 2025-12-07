import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'diary_model.dart';

class DiaryRepo {
  // ✅ 用 withConverter，把 Firestore <-> DiaryDoc 轉換綁好
  final _col = FirebaseFirestore.instance
      .collection('diaryEntries')
      .withConverter<DiaryDoc>(
    fromFirestore: (snap, _) {
      final d = snap.data()!;
      return DiaryDoc(
        id: snap.id,
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
    },
    toFirestore: (doc, _) => doc.toMap(),
  );

  // ✅ 監聽我的日記（直接拿 d.data() 就是 DiaryDoc）
  Stream<List<DiaryDoc>> watchMyDiaries({int limit = 200}) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return _col
        .where('uid', isEqualTo: uid)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // ✅ upsert 時，因為 _col 是 CollectionReference<DiaryDoc>，
  // set() 要傳 DiaryDoc，不是 Map
  Future<void> upsert(DiaryDoc doc) async {
    await _col.doc(doc.id).set(doc, SetOptions(merge: true));
  }

  // 產生 yyyyMMdd 當 docId（同一天覆寫同一筆）
  static String idForDate(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
}
