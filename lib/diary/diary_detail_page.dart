// lib/ui/diary_detail_page.dart
import 'package:flutter/material.dart' as m;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../diary/diary_repository.dart' as repo;   // ← 加上別名 repo
import '../diary/diary_page.dart' show DiaryPage, DailyMeta;

class DiaryDetailPage extends m.StatelessWidget {
  final String? docId;
  final String dateText;
  final double moodScore;        // 例如 7.0
  final String? moodKeyword;     // 例如「期待」
  final String? title;           // 例如「踮動日」
  final String? contentCtrl;     // 內文
  final String? themeSong;       // 今日主題曲
  final String? highlight;       // 最想記錄的瞬間
  final String? metaphor;        // 今天的情緒像…
  final String? conceited;       // 感到驕傲的事
  final String? proudOf;         // 我做得不錯的地方
  final String? selfCare;        // 我還能多照顧自己一點

  const DiaryDetailPage({
    m.Key? key,
    required this.docId,
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

  factory DiaryDetailPage.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final DateTime dt = (data['date'] is Timestamp)
        ? (data['date'] as Timestamp).toDate()
        : (data['date'] as DateTime? ?? DateTime.now());
    String two(int n) => n.toString().padLeft(2, '0');
    final dateText = '${dt.year}-${two(dt.month)}-${two(dt.day)}';
    final moodScore = (data['moodScore'] is num) ? (data['moodScore'] as num).toDouble() : 0.0;
    return DiaryDetailPage(docId: doc.id, dateText: dateText, moodScore: moodScore);
  }

  @override
  m.Widget build(m.BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;
    final color = _moodColor(moodScore, cs);

    return m.Scaffold(
      backgroundColor: cs.surfaceVariant.withOpacity(.15),
      appBar: m.AppBar(
        title: const m.Text('日記回顧'),
        elevation: 0,
        backgroundColor: cs.surface,
      ),
      body: m.SafeArea(
        child: m.ListView(
          padding: const m.EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _HeaderCard(
              dateText: dateText,
              moodScore: moodScore,
              moodKeyword: moodKeyword,
              color: color,
            ),
            if (_notEmpty(title)) ...[
              const m.SizedBox(height: 12),
              _ChipCard(
                icon: m.Icons.bookmark_rounded,
                label: '標題',
                text: title!,
              ),
            ],
const m.SizedBox(height: 16),
_SectionCard(
  icon: m.Icons.bookmark_rounded,
  label: '標題',
  text: title,                 // <- 確保上面有取得 title（String?）
  placeholder: '（可留白）',
),
const m.SizedBox(height: 12),
_SectionCard(
  icon: m.Icons.subject_rounded,
  label: '內容',
  text: contentCtrl,               // <- 確保上面有取得 content（String?）
  placeholder: '留下一點點也很好…',
  big: true,
),
            const m.SizedBox(height: 12),
            _SectionCard(
              icon: m.Icons.headphones_rounded,
              label: '今日的主題曲',
              text: themeSong,
              placeholder: '—',
            ),
            const m.SizedBox(height: 12),
            _SectionCard(
              icon: m.Icons.auto_awesome_rounded,
              label: '今天最想記錄的瞬間',
              text: highlight,
              placeholder: '今天最想留住的畫面、對話或感受…',
              big: true,
            ),
            const m.SizedBox(height: 12),
            _SectionCard(
              icon: m.Icons.theater_comedy_rounded,
              label: '今天的情緒像…',
              text: metaphor,
              placeholder: '例：潮汐、霧氣、烈陽、玻璃珠…',
            ),
            const m.SizedBox(height: 12),
            _SectionCard(
              icon: m.Icons.emoji_events_rounded,
              label: '為自己感到驕傲的是',
              text: conceited,
              placeholder: '完成了什麼、撐住了什麼、或小小突破…',
            ),
            const m.SizedBox(height: 12),
            _SectionCard(
              icon: m.Icons.wb_sunny_rounded,
              label: '我做得不錯的地方',
              text: proudOf,
              placeholder: '肯定一下今天的自己，哪怕是很小的事情。',
              big: true,
            ),
            const m.SizedBox(height: 12),
            _SectionCard(
              icon: m.Icons.volunteer_activism_rounded,
              label: '我還能多照顧自己一點的地方',
              text: selfCare,
              placeholder: '下一步可以怎麼做？睡眠、飲食、邊界、運動或求助…',
              big: true,
            ),

            const m.SizedBox(height: 18),
            _Hint(cs: cs),
          ],
        ),
      ),
    );
  }

  static bool _notEmpty(String? s) => s != null && s.trim().isNotEmpty;

  static m.Color _moodColor(double score, m.ColorScheme cs) {
    if (score >= 8) return cs.primaryContainer;
    if (score >= 6) return cs.tertiaryContainer;
    if (score >= 4) return cs.secondaryContainer;
    return cs.errorContainer;
  }
}

/// ---- 標頭：日期＋心情分數膠囊 ---------------------------------
class _HeaderCard extends m.StatelessWidget {
  final String dateText;
  final double moodScore;
  final String? moodKeyword;
  final m.Color color;

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
  m.Widget build(m.BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;

    return m.Container(
      decoration: m.BoxDecoration(
        color: cs.surface,
        borderRadius: m.BorderRadius.circular(20),
        border: m.Border.all(color: cs.outline.withOpacity(.45)),
      ),
      padding: const m.EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: m.Row(
        crossAxisAlignment: m.CrossAxisAlignment.center,
        children: [
          // 左：心情分數膠囊
          m.Container(
            width: 60,
            height: 60,
            decoration: m.BoxDecoration(
              color: color,
              borderRadius: m.BorderRadius.circular(16),
            ),
            alignment: m.Alignment.center,
            child: m.Text(
              moodScore.toStringAsFixed(1),
              style: m.Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: m.FontWeight.w800,
                    color: m.Colors.black.withOpacity(.72),
                  ),
            ),
          ),
          const m.SizedBox(width: 14),
          // 中：日期 + 標籤
          m.Expanded(
            child: m.Column(
              crossAxisAlignment: m.CrossAxisAlignment.start,
              children: [
                m.Text(
                  dateText,
                  style: m.Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: m.FontWeight.w700),
                ),
                const m.SizedBox(height: 6),
                m.Wrap(
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
class _Tag extends m.StatelessWidget {
  final String text;
  const _Tag({required this.text});

  @override
  m.Widget build(m.BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;
    return m.Container(
      padding: const m.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: m.BoxDecoration(
        color: cs.primaryContainer.withOpacity(.55),
        borderRadius: m.BorderRadius.circular(24),
      ),
      child: m.Text(
        text,
        style: m.Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onPrimaryContainer,
              fontWeight: m.FontWeight.w600,
            ),
      ),
    );
  }
}

/// ---- 單行小卡（像標題用） -----------------------------------
class _ChipCard extends m.StatelessWidget {
  final m.IconData icon;
  final String label;
  final String text;

  const _ChipCard({
    required this.icon,
    required this.label,
    required this.text,
  });

  @override
  m.Widget build(m.BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;
    return m.Container(
      decoration: m.BoxDecoration(
        color: cs.surface,
        borderRadius: m.BorderRadius.circular(16),
        border: m.Border.all(color: cs.outline.withOpacity(.45)),
      ),
      padding: const m.EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: m.Row(
        children: [
          m.Icon(icon, size: 18, color: cs.primary),
          const m.SizedBox(width: 10),
          m.Text(
            text,
            style: m.Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: m.FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// ---- 內容區卡片 ---------------------------------------------
class _SectionCard extends m.StatelessWidget {
  final m.IconData icon;
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
  m.Widget build(m.BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;
    final hasText = text != null && text!.trim().isNotEmpty;

    return m.Container(
      decoration: m.BoxDecoration(
        color: cs.surface,
        borderRadius: m.BorderRadius.circular(20),
        border: m.Border.all(color: cs.outline.withOpacity(.45)),
      ),
      padding: const m.EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: m.Column(
        crossAxisAlignment: m.CrossAxisAlignment.start,
        children: [
          m.Row(
            children: [
              m.Icon(icon, size: 18, color: cs.primary),
              const m.SizedBox(width: 8),
              m.Text(
                label,
                style: m.Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: m.FontWeight.w700),
              ),
            ],
          ),
          const m.SizedBox(height: 10),
          m.Text(
            hasText ? text! : placeholder,
            style: m.Theme.of(context).textTheme.bodyLarge?.copyWith(
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
class _Hint extends m.StatelessWidget {
  final m.ColorScheme cs;
  const _Hint({required this.cs});

  @override
  m.Widget build(m.BuildContext context) {
    return m.Container(
      decoration: m.BoxDecoration(
        color: cs.surface,
        borderRadius: m.BorderRadius.circular(14),
        border: m.Border.all(color: cs.outline.withOpacity(.35)),
      ),
      padding: const m.EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: m.Row(
        crossAxisAlignment: m.CrossAxisAlignment.start,
        children: [
          m.Icon(m.Icons.info_outline_rounded,
              size: 18, color: cs.onSurfaceVariant),
          const m.SizedBox(width: 8),
          m.Expanded(
            child: m.Text(
              '小提醒：內容儲存後仍可在日記回顧中編輯。',
              style: m.Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
