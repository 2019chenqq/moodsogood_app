// diary_home_page.dart
import 'package:flutter/material.dart' as m;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/date_time_patterns.dart';

import '/diary/diary_page_demo.dart';
import '../utils/date_helper.dart';
import '../widgets/main_drawer.dart';
import '../quotes.dart';

// 轉成統一的 day key：yyyy-MM-dd
String _normDayKey(String docId) {
  final beforeT = docId.split('T').first;                 // 去掉 T 之後
  final digits  = beforeT.replaceAll(RegExp(r'\D'), '');  // 只留數字
  if (digits.length >= 8) {
    final y = digits.substring(0, 4);
    final m = digits.substring(4, 6);
    final d = digits.substring(6, 8);
    return '$y-$m-$d';
  }
  final parts = beforeT.split(RegExp(r'[-/]'));
  if (parts.length >= 3) {
    final y = parts[0].padLeft(4, '0');
    final m = parts[1].padLeft(2, '0');
    final d = parts[2].padLeft(2, '0');
    return '$y-$m-$d';
  }
  return beforeT; // 後援
}

// yyyy-MM-dd → 20251102（方便排序）
int _keyToInt(String anyIdOrKey) =>
    int.parse(_normDayKey(anyIdOrKey).replaceAll('-', ''));

// 一天只留一筆（保留最新）：依 stream 的 DESC 順序保留第一個
List<QueryDocumentSnapshot<Map<String, dynamic>>> _dedupeByDay(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> raw,
) {
  final seen = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  for (final d in raw) {
    final k = _normDayKey(d.id);
    seen.putIfAbsent(k, () => d); // 已是 DESC，所以第一個即最新
  }
  return seen.values.toList();
}

// 最終排序：無論 docs 從哪裡來，都強制「新→舊」
void _sortByDateDesc(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> list,
) {
  list.sort((a, b) => _keyToInt(b.id).compareTo(_keyToInt(a.id)));
}
/// 入口頁：日記（最近 / 全部）
class DiaryHomePage extends m.StatefulWidget {
  const DiaryHomePage({m.Key? key}) : super(key: key);

  @override
  m.State<DiaryHomePage> createState() => _DiaryHomePageState();
}

class _DiaryHomePageState extends m.State<DiaryHomePage>
    with m.SingleTickerProviderStateMixin {
  late final m.TabController _tab;
late final String _uid;
late final CollectionReference<Map<String, dynamic>> _diariesRef;

@override
void initState() {
  super.initState();
  _uid = FirebaseAuth.instance.currentUser!.uid;   // 取得登入者 uid（要已登入）
  _diariesRef = FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('diary');                      // 確認跟你儲存的集合名稱一致
  // debugPrint('diary path = users/$_uid/diaries'); // 需要時可開啟看看
  _tab = m.TabController(length: 2, vsync: this);
}
  String get uid => FirebaseAuth.instance.currentUser!.uid;
void _openDiaryById(String docId) {
  final p = docId.split('-');
  final date = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  // 依你現有路由寫法：pushNamed 或直接 MaterialPageRoute 都可以
  m.Navigator.pushNamed(context, '/diary/edit', arguments: date);
}
  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }
void _openToday() {
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day);
  _openDiaryEditor(d);
}

Future<void> _pickAndOpenDate() async {
  final now = DateTime.now();
  final picked = await m.showDatePicker(
    context: context,
    initialDate: now,
    firstDate: DateTime(2015, 1, 1),
    lastDate: DateTime(now.year + 1, 12, 31),
  );
  if (picked == null) return;
  final d = DateTime(picked.year, picked.month, picked.day);
  _openDiaryEditor(d);
}

void _openDiaryEditor(DateTime d) {
  m.Navigator.push(
    context,
    m.MaterialPageRoute(
      builder: (_) => DiaryPageDemo(date: d), // 你的編輯頁
    ),
  );
}
 @override
m.Widget build(m.BuildContext context) {
  return m.Scaffold(
    drawer: const MainDrawer(),
    appBar: m.AppBar(
      toolbarHeight: 120,
  centerTitle: true,
      title: const QuotesTitle(),
      actions: [
        // 今天的日記
        m.IconButton(
          icon: const m.Icon(m.Icons.today_outlined),
          tooltip: '今天的日記',
          onPressed: _openToday,
        ),
        // 跳到指定日期
        m.IconButton(
          icon: const m.Icon(m.Icons.date_range),
          tooltip: '跳到指定日期',
          onPressed: _pickAndOpenDate,
        ),
            ],
      bottom: m.TabBar(
        controller: _tab,
        tabs: const [
          m.Tab(text: '最近'),
          m.Tab(text: '全部'),
        ],
      ),
    ),

    // ← 把 TabBarView 放到 body 裡
    body: m.TabBarView(
      controller: _tab,
      children: [
        _DiaryList(uid: _uid, showOnlyRecent: true),   // 最近
        _DiaryList(uid: _uid, showOnlyRecent: false),  // 全部
      ],
    ),

    // ← 浮動按鈕要在 Scaffold 裡
    floatingActionButton: m.FloatingActionButton.extended(
      icon: const m.Icon(m.Icons.event_available),
      label: const m.Text('今天的日記'),
      onPressed: _openToday,
    ),
  );
}
}
/// 單一分頁清單
class _DiaryList extends m.StatelessWidget {
  final String uid;
  final bool showOnlyRecent;
  const _DiaryList({required this.uid, required this.showOnlyRecent});

// 你的排序：新到舊
  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('diary');

  Query<Map<String, dynamic>> _buildQuery() {
    // 「最近」才 limit；「全部」不能 limit / 不能加時間 where
    return showOnlyRecent
        ? _col.orderBy(FieldPath.documentId, descending: true).limit(60)
        : _col.orderBy(FieldPath.documentId, descending: true);
  }

Stream<QuerySnapshot<Map<String, dynamic>>> _recentDiary(String uid) =>
  FirebaseFirestore.instance
    .collection('users').doc(uid).collection('diary')
    .orderBy(FieldPath.documentId, descending: true)
    .limit(120)   // 想要看更多天自己調
    .snapshots();

Stream<QuerySnapshot<Map<String, dynamic>>> _allDiary(String uid) =>
  FirebaseFirestore.instance
    .collection('users').doc(uid).collection('diary')
    .orderBy(FieldPath.documentId, descending: true)
    .snapshots();

@override
m.Widget build(m.BuildContext context) {
  final uid = FirebaseAuth.instance.currentUser?.uid;

  if (uid == null) {
    return const m.Center(child: m.Text('尚未登入（uid 為 null）'));
  }

  return m.StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('diary') // ← 確認集合名
        .orderBy(FieldPath.documentId, descending: true) // 先用 docId DESC
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == m.ConnectionState.waiting) {
        return const m.Center(child: m.CircularProgressIndicator());
      }
      if (!snapshot.hasData) {
        return const m.Center(child: m.Text('還沒有日記喔~去寫篇日記吧！'));
      }

      final raw = snapshot.data!.docs;
      m.debugPrint('🔥 diary raw count = ${raw.length}');
      if (raw.isNotEmpty) {
        m.debugPrint('🔥 first id = ${raw.first.id}');
      }

      if (raw.isEmpty) {
        return const m.Center(child: m.Text('目前沒有日記'));
      }
final deduped = _dedupeByDay(raw);
_sortByDateDesc(deduped);
      final docs = showOnlyRecent
    ? deduped.take(60).toList()   // 想顯示幾天自己改
    : deduped;
      _sortByDateDesc(docs);

      return m.ListView.separated(
        itemCount: docs.length,
        separatorBuilder: (_, __) => const m.Divider(height: 0),
        itemBuilder: (ctx, i) {
  final doc    = docs[i];
  final dayKey = _normDayKey(doc.id); // 確保是 yyyy-MM-dd
  
  // 1. 先轉成 DateTime 物件
  final date = DateTime.parse(dayKey); 
  
  // 2. 用 Helper 統一顯示格式 (yyyy/MM/dd)
  final title = DateHelper.toDisplay(date);

  return m.ListTile(
    leading: const m.Icon(m.Icons.bookmark_border),
    title: m.Text(title),
    trailing: const m.Icon(m.Icons.chevron_right),
    onTap: () {
      // 直接使用上面轉好的 date 物件導航
      m.Navigator.of(ctx).push(
        m.MaterialPageRoute(
          builder: (_) => DiaryPageDemo(date: date),
        ),
      );
    },
  );
},
      );
}
  );
}
  // ====== List UI ======

  m.Widget _buildList(m.BuildContext context, List<DateTime> dates) {
    return m.ListView.separated(
      padding: const m.EdgeInsets.only(bottom: 96),
      itemCount: dates.length,
      separatorBuilder: (_, __) => const m.Divider(height: 1),
      itemBuilder: (context, i) {
        final d = dates[i];
        return m.ListTile(
          leading: const m.Icon(m.Icons.bookmark_border),
          title: m.Text(DateHelper.toDisplay(d)),
          trailing: const m.Icon(m.Icons.chevron_right),
          onTap: () {
            m.Navigator.push(
              context,
              m.MaterialPageRoute(
                builder: (_) =>
                    // TODO: 這裡改成你的編輯頁 class
                    DiaryPageDemo(date: d),
              ),
            );
          },
        );
      },
    );
  }
  }

// ================= 工具 =================

/// 解析日期：優先從 doc.id（支援 yyyy-MM-dd 與 yyyy-MM-ddT...）
/// 若失敗再看 `date` 欄位（Timestamp / ISO 字串），最後 fallback 今天。
DateTime _dateFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
  final id = d.id;
  final m0 = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(id);
  if (m0 != null) {
    return DateTime(
      int.parse(m0.group(1)!),
      int.parse(m0.group(2)!),
      int.parse(m0.group(3)!),
    );
  }
  final v = d.data()['date'];
  if (v is Timestamp) return v.toDate();
  if (v is String) {
    final parsed = DateTime.tryParse(v);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
  }
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}


List<DateTime> _mockDates() {
  final now = DateTime.now();
  return List.generate(
    30,
    (i) {
      final d = now.subtract(Duration(days: i));
      return DateTime(d.year, d.month, d.day);
    },
  );
}

/// 列表元件：共用「最近／全部」兩個分頁
class DiaryListView extends m.StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final bool showOnlyRecent;
  const DiaryListView({super.key, required this.docs, required this.showOnlyRecent});

  @override
  m.Widget build(m.BuildContext context) {
    // 若要限制「最近」只顯示 N 筆，改這行，如：take(30)
    final show = showOnlyRecent ? docs : docs;

    return m.ListView.separated(
      itemCount: show.length,
      separatorBuilder: (_, __) => const m.Divider(height: 0),
itemBuilder: (_, i) {
  final doc = show[i];
  // 使用現有的 _normDayKey 確保格式正確
  final dayKey = _normDayKey(doc.id);
  
  // 轉物件 -> 轉顯示字串
  final date = DateTime.parse(dayKey);
  final title = DateHelper.toDisplay(date);

  return m.ListTile(
    leading: const m.Icon(m.Icons.menu_book_rounded),
    title: m.Text(title),
    trailing: const m.Icon(m.Icons.chevron_right),
    onTap: () {
      m.Navigator.push(
        context,
        m.MaterialPageRoute(
          builder: (_) => DiaryPageDemo(date: date),
        ),
      );
    },
  );
},
);
      }
  }

String _dayKeyFromDocId(String id) {
  final onlyDate = id.split('T').first;                // 2025-11-02T... → 2025-11-02
  return onlyDate.length >= 10 ? onlyDate.substring(0, 10) : onlyDate;
}
/// 點進去「那一天」：若你已有既存的開啟方法，改成呼叫它即可
void _openDiaryByDoc(m.BuildContext context, QueryDocumentSnapshot doc) {
  // 你目前日記的路由看起來是「用日期開編輯頁」，
  // 若已有現成的 openDiary(DateTime) 之類，這裡轉換後呼叫。
  final day = _dayKeyFromDocId(doc.id); // yyyy-MM-dd
  final parts = day.split('-');
  final date = DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );

  // TODO：把下面這段換成你專案既有的導航方式
  // 例如：Navigator.push(context, MaterialPageRoute(builder: (_) => DiaryPageDemo(date: date)));
  m.Navigator.pushNamed(context, '/diary/edit', arguments: date);
}
DateTime _ymd(DateTime d) => DateTime(d.year, d.month, d.day);
String _key(DateTime d) =>
  '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

class DiaryRec {
  DiaryRec({required this.id, required this.date, this.updatedAt, this.note});
  final String id;
  final DateTime date;
  final DateTime? updatedAt;
  final String? note;

  factory DiaryRec.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    DateTime? parseDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }
    final dt = parseDate(m['date']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final ua = parseDate(m['updatedAt']);
    return DiaryRec(id: d.id, date: _ymd(dt), updatedAt: ua, note: m['note'] as String?);
  }
}

List<DiaryRec> dedupeAndSort(List<DiaryRec> recs) {
  // 同一天只保留「最後更新的那筆」
  final byDay = <String, DiaryRec>{};
  for (final r in recs) {
    final k = _key(r.date);
    final old = byDay[k];
    final rTime = r.updatedAt ?? r.date;
    final oTime = old?.updatedAt ?? old?.date;
    if (old == null || rTime.isAfter(oTime!)) byDay[k] = r;
  }
  final out = byDay.values.toList()
    ..sort((a, b) => b.date.compareTo(a.date)); // 新到舊
  return out;
}