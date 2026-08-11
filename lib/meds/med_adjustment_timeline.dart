import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/health_data_encryption_service.dart';

class MedicationAdjustmentTimeline extends StatelessWidget {
  final void Function(String adjustId, Map<String, dynamic> data)? onTapItem;

  const MedicationAdjustmentTimeline({super.key, this.onTapItem});

  static const Color _primaryBlue = Color(0xFF7DB7D8);
  static const Color _softBlue = Color(0xFFEAF6FC);
  static const Color _deepText = Color(0xFF2F4858);
  static const Color _mutedText = Color(0xFF7B8B96);
  static const Color _cardBg = Color(0xFFFBFEFF);
  static const Color _lineColor = Color(0xFFD6EAF4);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Center(
        child: Text(
          '請先登入',
          style: TextStyle(color: _mutedText),
        ),
      );
    }

    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('medAdjustments')
        .orderBy('date', descending: true)
        .limit(50);

    return StreamBuilder<List<HealthDocument>>(
      stream: HealthDataEncryptionService.watchEncrypted(q),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: _primaryBlue,
            ),
          );
        }

        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '讀取調藥紀錄時遇到一點問題：\n${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _mutedText,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ),
          );
        }

        final docs = List<HealthDocument>.from(snap.data ?? const [])
          ..sort((left, right) =>
              _dateOf(right.data).compareTo(_dateOf(left.data)));

        if (docs.isEmpty) {
          return const _EmptyTimeline();
        }

        return Container(
          color: const Color(0xFFF7FBFD),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data;

              final date = _dateOf(data);

              final note = (data['note'] as String?)?.trim() ?? '';
              final changes =
                  (data['changes'] as List?)?.whereType<Map>().toList() ?? [];

              final isFirst = i == 0;
              final isLast = i == docs.length - 1;

              return _TimelineItem(
                date: date,
                note: note,
                changes: changes,
                isFirst: isFirst,
                isLast: isLast,
                onTap:
                    onTapItem == null ? null : () => onTapItem!(doc.id, data),
              );
            },
          ),
        );
      },
    );
  }

  static String _fmtYmd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  static DateTime _dateOf(Map<String, dynamic> data) {
    final value = data['date'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _buildSummary(List<Map> changes) {
    if (changes.isEmpty) return '這一天尚未留下明確的藥物變更內容。';

    final items = changes.take(3).map((c) {
      final nameZh = (c['nameZh'] ?? '').toString();
      final nameEn = (c['nameEn'] ?? '').toString();
      final name =
          nameZh.isNotEmpty ? nameZh : (nameEn.isNotEmpty ? nameEn : '未命名藥物');

      final action = (c['action'] ?? '').toString();
      final before = c['doseBefore'];
      final after = c['doseAfter'];
      final unit = (c['unit'] ?? '').toString();

      if (action == 'stop') return '$name：停用';
      if (action == 'add') return '$name：新增 ${(after ?? '')} $unit'.trim();
      if (action == 'injection') {
        return '$name：注射 ${(after ?? '')} $unit'.trim();
      }
      if (action == 'adjust') {
        return '$name：${before ?? ''} → ${after ?? ''} $unit'.trim();
      }

      return '$name：維持原本設定';
    }).toList();

    final more = changes.length > 3 ? '，還有 ${changes.length - 3} 項調整' : '';
    return '${items.join('、')}$more';
  }
}

class _TimelineItem extends StatelessWidget {
  final DateTime date;
  final String note;
  final List<Map> changes;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onTap;

  const _TimelineItem({
    required this.date,
    required this.note,
    required this.changes,
    required this.isFirst,
    required this.isLast,
    this.onTap,
  });

  static const Color _primaryBlue = MedicationAdjustmentTimeline._primaryBlue;
  static const Color _deepText = MedicationAdjustmentTimeline._deepText;
  static const Color _cardBg = MedicationAdjustmentTimeline._cardBg;
  static const Color _lineColor = MedicationAdjustmentTimeline._lineColor;

  @override
  Widget build(BuildContext context) {
    final title = MedicationAdjustmentTimeline._fmtYmd(date);
    final summary = MedicationAdjustmentTimeline._buildSummary(changes);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst ? Colors.transparent : _lineColor,
                  ),
                ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _primaryBlue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _primaryBlue.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : _lineColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(24),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFFE4F1F7),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7DB7D8).withOpacity(0.10),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _HeaderRow(
                            title: title,
                            count: changes.length,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            summary,
                            style: const TextStyle(
                              color: _deepText,
                              fontSize: 14,
                              height: 1.55,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _NoteBox(note: note),
                          ],
                          if (onTap != null) ...[
                            const SizedBox(height: 12),
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  '查看細節',
                                  style: TextStyle(
                                    color: _primaryBlue,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: _primaryBlue,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final String title;
  final int count;

  const _HeaderRow({
    required this.title,
    required this.count,
  });

  static const Color _primaryBlue = MedicationAdjustmentTimeline._primaryBlue;
  static const Color _deepText = MedicationAdjustmentTimeline._deepText;
  static const Color _mutedText = MedicationAdjustmentTimeline._mutedText;
  static const Color _softBlue = MedicationAdjustmentTimeline._softBlue;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _softBlue,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.medication_liquid_rounded,
            color: _primaryBlue,
            size: 21,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '藥物調整紀錄',
                style: TextStyle(
                  color: _mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  color: _deepText,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F8FC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFDCEEF7)),
          ),
          child: Text(
            '$count 項',
            style: const TextStyle(
              color: _primaryBlue,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteBox extends StatelessWidget {
  final String note;

  const _NoteBox({required this.note});

  static const Color _mutedText = MedicationAdjustmentTimeline._mutedText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAF1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF3E6C8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.notes_rounded,
            size: 17,
            color: Color(0xFFC7A458),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              style: const TextStyle(
                color: _mutedText,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();

  static const Color _primaryBlue = MedicationAdjustmentTimeline._primaryBlue;
  static const Color _softBlue = MedicationAdjustmentTimeline._softBlue;
  static const Color _deepText = MedicationAdjustmentTimeline._deepText;
  static const Color _mutedText = MedicationAdjustmentTimeline._mutedText;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7FBFD),
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE4F1F7)),
            boxShadow: [
              BoxShadow(
                color: _primaryBlue.withOpacity(0.10),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.spa_rounded,
                  size: 30,
                  color: _primaryBlue,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '還沒有調藥紀錄',
                style: TextStyle(
                  color: _deepText,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '當你新增回診或藥物調整後，\n這裡會慢慢形成一條屬於你的用藥時間線。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _mutedText,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
