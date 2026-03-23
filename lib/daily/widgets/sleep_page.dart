import 'package:flutter/material.dart';
import '../../utils/date_helper.dart';
import '../../models/daily_record.dart';
import '../models/sleep_flag.dart';

/// 睡眠分頁
class SleepPage extends StatelessWidget {
  const SleepPage({
    super.key,
    required this.sleepTime,
    required this.wakeTime,
    required this.onPickSleepTime,
    required this.onPickWakeTime,
    required this.finalWakeTime,
    required this.onPickFinalWakeTime,
    required this.midWakeCtrl,
    required this.onChangeMidWake,
    required this.flags,
    required this.onToggleFlag,
    required this.sleepNote,
    required this.onChangeNote,
    required this.sleepQuality,
    required this.onPickValue,
    required this.naps,
    required this.onAddNap,
    required this.onEditNap,
    required this.onDeleteNap,
    required this.tookHypnotic,
    required this.onToggleHypnotic,
    required this.hypnoticName,
    required this.onChangeHypnoticName,
    required this.hypnoticDose,
    required this.onChangeHypnoticDose,
    required this.hypnoticNameCtrl,
    required this.hypnoticDoseCtrl,
  });

  final TimeOfDay? sleepTime;
  final TimeOfDay? wakeTime;
  final Future<void> Function() onPickSleepTime;
  final Future<void> Function() onPickWakeTime;
  final TimeOfDay? finalWakeTime;
  final Future<void> Function() onPickFinalWakeTime;
  final TextEditingController midWakeCtrl;
  final ValueChanged<String> onChangeMidWake;
  final Set<SleepFlag> flags;
  final void Function(SleepFlag) onToggleFlag;
  final String sleepNote;
  final void Function(String) onChangeNote;
  final int? sleepQuality;
  final Future<void> Function() onPickValue;
  final List<NapItem> naps;
  final Future<void> Function() onAddNap;
  final Future<void> Function(int) onEditNap;
  final void Function(int) onDeleteNap;
  final bool tookHypnotic;
  final ValueChanged<bool> onToggleHypnotic;
  final String hypnoticName;
  final ValueChanged<String> onChangeHypnoticName;
  final String hypnoticDose;
  final ValueChanged<String> onChangeHypnoticDose;
  final TextEditingController hypnoticNameCtrl;
  final TextEditingController hypnoticDoseCtrl;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SwitchListTile(
            secondary: const Icon(Icons.medication_outlined, color: Colors.purple),
            title: const Text('前一晚是否有吃安眠藥？'),
            value: tookHypnotic,
            onChanged: onToggleHypnotic,
          ),
        ),
        if (tookHypnotic) ...[
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 20, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text('安眠藥名稱與劑量',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hypnoticNameCtrl,
                    decoration: const InputDecoration(
                      hintText: '例如：Clonazepam（克癇平）',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.local_pharmacy_outlined),
                    ),
                    onChanged: onChangeHypnoticName,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hypnoticDoseCtrl,
                    decoration: const InputDecoration(
                      hintText: '例如：0.5 mg',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    onChanged: onChangeHypnoticDose,
                  ),
                ],
              ),
            ),
          ),
        ],
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.bed_outlined, color: Colors.indigo),
            title: const Text('前一日準備睡覺時間'),
            subtitle: Text(
                sleepTime == null ? '—' : DateHelper.formatTime(sleepTime!)),
            onTap: onPickSleepTime,
          ),
        ),
        const SizedBox(height: 8),
        const Text('夜間睡眠狀況（可多選）',
            style: TextStyle(fontWeight: FontWeight.w600)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: (() {
            const desired = [
              '優',
              '良好',
              '早醒',
              '多夢',
              '淺眠',
              '夜尿',
              '睡睡醒醒',
              '睡眠不足',
              '入睡困難 (躺超過 30 分鐘才入睡)',
              '睡眠中斷 (醒來後超過 30 分鐘才又入睡)',
            ];

            final list = SleepFlag.values.toList()
              ..sort((a, b) {
                int ia = desired.indexOf(sleepFlagLabel(a));
                int ib = desired.indexOf(sleepFlagLabel(b));
                if (ia < 0) ia = 999;
                if (ib < 0) ib = 999;
                return ia.compareTo(ib);
              });

            return list.map((f) {
              final selected = flags.contains(f);
              return FilterChip(
                label: Text(sleepFlagLabel(f)),
                selected: selected,
                onSelected: (_) => onToggleFlag(f),
              );
            }).toList();
          })(),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.star_border_rounded, color: Colors.amber),
            title: const Text('自覺睡眠品質'),
            subtitle: Text(sleepQuality == null ? '—' : '$sleepQuality'),
            onTap: onPickValue,
          ),
        ),
        const SizedBox(height: 12),
        const Text('睡眠註記', style: TextStyle(fontWeight: FontWeight.w600)),
        TextField(
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '例如：一直做夢，感覺好像沒睡覺，起床精神很差',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.edit_note, color: Colors.grey),
          ),
          onChanged: onChangeNote,
        ),
        const SizedBox(height: 24),
        const Text('中途與甦醒',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFCC80)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💡 紀錄小撇步',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.brown)),
                    const SizedBox(height: 4),
                    Text(
                      '半夜醒來或剛睡醒時不想開 App？\n試試「手機截圖」！起床後再看相簿時間回填即可，減少看螢幕的焦慮。',
                      style: TextStyle(fontSize: 13, color: Colors.brown.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        TextField(
          controller: midWakeCtrl,
          decoration: const InputDecoration(
            labelText: '半夜醒來時間 (可留白)',
            hintText: '例：03:15, 05:40 (看截圖時間)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.access_time_outlined),
          ),
          onChanged: onChangeMidWake,
        ),
        const SizedBox(height: 16),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.wb_twilight, color: Colors.orange),
            title: const Text('甦醒時刻 (睜開眼)'),
            subtitle: Text(
              finalWakeTime == null
                  ? '尚未設定'
                  : DateHelper.formatTime(finalWakeTime),
              style: TextStyle(
                  color: finalWakeTime == null ? Colors.grey : Colors.black),
            ),
            onTap: onPickFinalWakeTime,
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.directions_run, color: Colors.blue),
            title: const Text('離床活動時間'),
            subtitle: Text(
              wakeTime == null ? '—' : DateHelper.formatTime(wakeTime),
            ),
            onTap: onPickWakeTime,
          ),
        ),
        const SizedBox(height: 16),
        const Text('小睡（可新增多筆）', style: TextStyle(fontWeight: FontWeight.w600)),
        ...List.generate(naps.length, (i) {
          final n = naps[i];
          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.timer_outlined, color: Colors.teal),
              title: Text(
                  '${DateHelper.formatTime(n.start)} – ${DateHelper.formatTime(n.end)}'),
              subtitle: Text(
                  '時長：${DateHelper.formatDurationText(n.durationMinutes)}'),
              onTap: () => onEditNap(i),
              trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDeleteNap(i)),
            ),
          );
        }),
        OutlinedButton.icon(
            onPressed: onAddNap,
            icon: const Icon(Icons.add),
            label: const Text('新增小睡')),
      ],
    );
  }
}
