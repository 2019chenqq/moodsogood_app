// diary_home_page.dart
import 'package:flutter/material.dart' as m;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '/diary/diary_page_demo.dart';
import '/diary/diary_repository.dart';
import '../utils/date_helper.dart';

// 簡化的日記數據結構，用於統一處理本地和 Firebase 數據
class _DiaryItem {
  final String id;
  final DateTime date;
  final Map<String, dynamic> data;

  _DiaryItem({required this.id, required this.date, required this.data});
}

// 轉成統一的 day key：yyyy-MM-dd
String _normDayKey(String docIdOrDate) {
  // 處理 DateTime ISO string
  if (docIdOrDate.contains('T')) {
    final date = DateTime.tryParse(docIdOrDate);
    if (date != null) {
      return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  final beforeT = docIdOrDate.split('T').first;                 // 去掉 T 之後
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

// 一天只留一筆（保留最新）：依 stream 的 DESC 順序保留第一個
List<_DiaryItem> _dedupeByDay(List<_DiaryItem> raw) {
  final seen = <String, _DiaryItem>{};
  for (final item in raw) {
    final k = _normDayKey(item.id);
    seen.putIfAbsent(k, () => item); // 已是 DESC，所以第一個即最新
  }
  return seen.values.toList();
}

// 最終排序：無論 docs 從哪裡來，都強制「新→舊」
void _sortByDateDesc(List<_DiaryItem> list) {
  list.sort((a, b) => b.date.compareTo(a.date));
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

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser!.uid;   // 取得登入者 uid（要已登入）
    _tab = m.TabController(length: 2, vsync: this);
  }

  String get uid => FirebaseAuth.instance.currentUser!.uid;

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
        builder: (_) => DiaryPageDemo(date: d),
      ),
    );
  }

  @override
  m.Widget build(m.BuildContext context) {
    return m.Scaffold(
      // drawer: const MainDrawer(),
      appBar: m.AppBar(
        toolbarHeight: 60,
        elevation: 0,
        actions: [
          m.IconButton(
            icon: const m.Icon(m.Icons.today_outlined),
            tooltip: '今天的日記',
            onPressed: _openToday,
          ),
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
      body: m.TabBarView(
        controller: _tab,
        children: [
          _DiaryList(uid: _uid, showOnlyRecent: true),
          _DiaryList(uid: _uid, showOnlyRecent: false),
        ],
      ),
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

  /// 從 Firebase 和本地 SQLite 加載日記並合併去重
  Future<List<_DiaryItem>> _loadMergedDiaries() async {
    final map = <String, _DiaryItem>{};

    try {
      // 1. 從本地 SQLite 加載
      final localEntries = await DiaryRepository().list(limit: 500);
      for (final entry in localEntries) {
        final dayKey = _normDayKey(entry.date.toIso8601String());
        map[dayKey] = _DiaryItem(
          id: dayKey,
          date: entry.date,
          data: entry.toMap() as Map<String, dynamic>,
        );
      }
      m.debugPrint('📔 Loaded ${localEntries.length} entries from local SQLite');
    } catch (e) {
      m.debugPrint('❌ Error loading local diaries: $e');
    }

    try {
      // 2. 從 Firebase 加載（覆蓋本地的同一天）
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('diary')
            .limit(500)
            .get();

        for (final doc in snapshot.docs) {
          final dayKey = _normDayKey(doc.id);
          final data = doc.data();
          
          // 轉換日期（Firebase 可能存的是 string 或 timestamp）
          DateTime date;
          if (data['date'] is Timestamp) {
            date = (data['date'] as Timestamp).toDate();
          } else if (data['date'] is String) {
            date = DateTime.parse(data['date'] as String);
          } else {
            date = DateTime.now();
          }

          map[dayKey] = _DiaryItem(
            id: dayKey,
            date: date,
            data: data,
          );
        }
        m.debugPrint('📔 Loaded ${snapshot.docs.length} entries from Firebase');
      }
    } catch (e) {
      m.debugPrint('❌ Error loading Firebase diaries: $e');
    }

    final result = map.values.toList();
    m.debugPrint('📔 Total merged diary count = ${result.length}');
    return result;
  }

  @override
  m.Widget build(m.BuildContext context) {
    return m.FutureBuilder<List<_DiaryItem>>(
      future: _loadMergedDiaries(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == m.ConnectionState.waiting) {
          return const m.Center(child: m.CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return m.Center(child: m.Text('發生錯誤：${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const m.Center(child: m.Text('還沒有日記喔~去寫篇日記吧！'));
        }

        final raw = snapshot.data!;
        m.debugPrint('📔 Total merged diary count = ${raw.length}');
        if (raw.isNotEmpty) {
          m.debugPrint('📔 First diary id = ${raw.first.id}');
        }

        final deduped = _dedupeByDay(raw);
        _sortByDateDesc(deduped);

        final docs = showOnlyRecent
            ? deduped.take(60).toList()
            : deduped;

        return m.ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const m.Divider(height: 0),
          itemBuilder: (ctx, i) {
            final doc = docs[i];
            final dayKey = _normDayKey(doc.id);

            final date = DateTime.parse(dayKey);
            final title = DateHelper.toDisplay(date);

            return m.ListTile(
              leading: const m.Icon(m.Icons.bookmark_border),
              title: m.Text(title),
              trailing: const m.Icon(m.Icons.chevron_right),
              onTap: () {
                m.Navigator.of(ctx).push(
                  m.MaterialPageRoute(
                    builder: (_) => DiaryPageDemo(date: date),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
