// lib/ui/diary_history_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../diary/diary_repository.dart';
import '../diary/diary_detail_page.dart';

Future<void> _openHistoryDetail(
  BuildContext context, {
  required QueryDocumentSnapshot<Map<String, dynamic>> doc,
}) async {
  try {
    final data = doc.data();
    final docId = doc.id;

    // ✅ 三選一：依你的詳情/編輯頁建構子挑一個用，其他刪掉
    // A. 只吃 docId
    //await Navigator.of(context).push(MaterialPageRoute(
    //  builder: (_) => DiaryDetailPage(docId: docId),
    //));

    // B. 只吃整包 data
    // await Navigator.of(context).push(MaterialPageRoute(
    //   builder: (_) => DiaryDetailPage(data: data),
    // ));

    // C. 你有 fromDoc() 這類工廠
     await Navigator.of(context).push(MaterialPageRoute(
       builder: (_) => DiaryDetailPage.fromDoc(doc),
     ));
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('開啟失敗：$e')),
    );
  }
}

Future<void> _deleteHistoryEntry(
  BuildContext context, {
  required String docId,
  DateTime? date,
}) async {
  final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('刪除這筆紀錄？'),
          content: Text(
            date == null
                ? '確定要刪除這筆日記嗎？'
                : '確定要刪除 ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} 的日記嗎？',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('刪除')),
          ],
        ),
      ) ??
      false;
  if (!ok) return;

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先登入')));
    return;
  }

  await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('diary')
      .doc(docId)
      .delete();

  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已刪除')));
}

class DiaryHistoryPage extends StatelessWidget {
  const DiaryHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

if (user == null) {
  return const Center(child: Text('請先登入')); // 或導向登入頁
}
final uid = user.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('diary')
      .orderBy('date', descending: true)
      .snapshots(),
  builder: (context, snap) {
    if (snap.hasError) {
      return Center(child: Text('讀取失敗：${snap.error}'));
    }
    if (!snap.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    final docs = snap.data!.docs; // ← 先取 data! 再 docs

    if (docs.isEmpty) {
      return const Center(child: Text('尚無日記，寫一篇看看吧！'));
    }

return ListView.separated(
  itemCount: docs.length,
  separatorBuilder: (_, __) => const SizedBox(height: 16),
  itemBuilder: (context, index) {
    final doc = docs[index];                         // QueryDocumentSnapshot<Map<String, dynamic>>
    final data = doc.data();
    final docId = doc.id;                            // 你的 yyyymmdd
    final dt = (data['date'] as Timestamp?)?.toDate();
    final mood = (data['moodScore'] ?? '').toString();
    final keyw = (data['moodKeyword'] ?? '').toString();

    return ListTile(
      title: Text(
        dt == null
            ? (data['title'] ?? '')
            : '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
              ' | 心情：$mood（$keyw）',
      ),
      subtitle: Text(data['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => _openHistoryDetail(context, doc: doc),              // ← 點一下開啟
      onLongPress: () => _deleteHistoryEntry(context,                   // ← 長按刪除
          docId: docId,
          date: dt,
      ),
    );
  },
);
      },
    );
  }
  }

/// 心晴｜日記回顧（純 UI）
/// 用法見文末 Navigator 範例
class DiaryReviewScreen extends StatelessWidget {
  final String dateText;
  final double moodScore;        // 例如 7.0
  final String? moodKeyword;     // 例如「期待」
  final String? title;           // 例如「踮動日」
  final String? contentCtrl;
  final String? themeSong;       // 今日主題曲
  final String? highlight;       // 最想記錄的瞬間
  final String? metaphor;        // 今天的情緒像…
  final String? conceited;
  final String? proudOf;         // 我做得不錯的地方
  final String? selfCare;        // 我還能多照顧自己一點

  const DiaryReviewScreen({
    Key? key,
    required this.dateText,
    required this.moodScore,
    this.moodKeyword,
    this.title,
    this.contentCtrl,
    this.themeSong,
    this.highlight,
    this.metaphor,
    this.conceited,
    this.proudOf,
    this.selfCare,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _moodColor(moodScore, cs);

    return Scaffold(
      backgroundColor: cs.surfaceVariant.withOpacity(.15),
      appBar: AppBar(
        title: const Text('日記回顧'),
        elevation: 0,
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _HeaderCard(
              dateText: dateText,
              moodScore: moodScore,
              moodKeyword: moodKeyword,
              color: color,
            ),
            if (_notEmpty(title)) ...[
              const SizedBox(height: 12),
              _ChipCard(
                icon: Icons.bookmark_rounded,
                label: '標題',
                text: title!,
              ),
            ],
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.music_note_rounded,
              label: '內文',
              text: contentCtrl,
              placeholder: '—',
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.music_note_rounded,
              label: '🎧 今日的主題曲',
              text: themeSong,
              placeholder: '—',
            ),
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.local_florist_rounded,
              label: '✨ 今天最想記錄的瞬間',
              text: highlight,
              placeholder: '今天最想留住的畫面、對話或感受…',
              big: true,
            ),
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.theater_comedy_rounded,
              label: '🎭 今天的情緒像…',
              text: metaphor,
              placeholder: '例：潮汐、霧氣、烈陽、玻璃珠…',
            ),
            const SizedBox(height: 12),
                        _SectionCard(
              icon: Icons.theater_comedy_rounded,
              label: '🏅 為自己感到驕傲的是',
              text: conceited,
              placeholder: '例：潮汐、霧氣、烈陽、玻璃珠…',
            ),
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.wb_sunny_rounded,
              label: '🌤️ 我做得不錯的地方',
              text: proudOf,
              placeholder: '肯定一下今天的自己，哪怕是很小的事情。',
              big: true,
            ),
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.volunteer_activism_rounded,
              label: '🫶 我還能多照顧自己一點的地方',
              text: selfCare,
              placeholder: '下一步可以怎麼做？睡眠、飲食、邊界、運動或求助…',
              big: true,
            ),

            const SizedBox(height: 18),
            _Hint(cs: cs),
          ],
        ),
      ),
    );
  }

  static bool _notEmpty(String? s) => s != null && s.trim().isNotEmpty;

  static Color _moodColor(double score, ColorScheme cs) {
    if (score >= 8) return cs.primaryContainer;
    if (score >= 6) return cs.tertiaryContainer;
    if (score >= 4) return cs.secondaryContainer;
    return cs.errorContainer;
  }
}

/// ---- 標頭：日期＋心情分數膠囊 ---------------------------------
class _HeaderCard extends StatelessWidget {
  final String dateText;
  final double moodScore;
  final String? moodKeyword;
  final Color color;

  const _HeaderCard({
    required this.dateText,
    required this.moodScore,
    this.moodKeyword,
    required this.color,
  });

  String get moodLabel {
    // 也可接你本來的標籤邏輯
    if (moodScore >= 8) return '喜悅';
    if (moodScore >= 6) return '期待';
    if (moodScore >= 4) return '平穩';
    if (moodScore >= 2) return '低潮';
    return '難熬';
    }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withOpacity(.45)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左：心情分數膠囊
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              moodScore.toStringAsFixed(1),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.black.withOpacity(.72),
                  ),
            ),
          ),
          const SizedBox(width: 14),
          // 中：日期 + 標籤
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateText,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _Tag(text: '心情：${moodScore.toStringAsFixed(1)}（$moodLabel）'),
                    if (moodKeyword != null && moodKeyword!.trim().isNotEmpty)
                      _Tag(text: moodKeyword!),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ---- 小籤標 ---------------------------------------------------
class _Tag extends StatelessWidget {
  final String text;
  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(.55),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// ---- 單行小卡（像標題用） -----------------------------------
class _ChipCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;

  const _ChipCard({
    required this.icon,
    required this.label,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withOpacity(.45)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Text(
            text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// ---- 內容區卡片 ---------------------------------------------
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? text;
  final String placeholder;
  final bool big; // 文字較多的給 true

  const _SectionCard({
    required this.icon,
    required this.label,
    required this.text,
    required this.placeholder,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasText = text != null && text!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withOpacity(.45)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hasText ? text! : placeholder,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  color: hasText
                      ? cs.onSurface
                      : cs.onSurfaceVariant.withOpacity(.8),
                ),
          ),
        ],
      ),
    );
  }
}

/// ---- 底部溫柔提醒 -------------------------------------------
class _Hint extends StatelessWidget {
  final ColorScheme cs;
  const _Hint({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withOpacity(.35)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '小提醒：內容儲存後仍可在日記回顧中編輯。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
