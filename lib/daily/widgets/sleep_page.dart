import 'package:flutter/material.dart';
import '../../constants/healing_design_system.dart';
import '../../utils/date_helper.dart';
import '../../models/daily_record.dart';
import '../../widgets/emotion_slider.dart';
import '../daily_record_helpers.dart';

/// 睡眠分頁
class SleepPage extends StatelessWidget {
  const SleepPage({
    super.key,
    required this.sleepTime,
    required this.estimatedSleepTime,
    required this.wakeTime,
    required this.onPickSleepTime,
    required this.onPickEstimatedSleepTime,
    required this.onPickWakeTime,
    required this.finalWakeTime,
    required this.onPickFinalWakeTime,
    required this.nightAwakenings,
    required this.onAddNightAwakening,
    required this.onEditNightAwakening,
    required this.onDeleteNightAwakening,
    required this.legacyMidWakeText,
    required this.flags,
    required this.onToggleFlag,
    required this.sleepNote,
    required this.onChangeNote,
    required this.sleepQuality,
    required this.onPickValue,
    this.onChangeSleepQuality,
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
  final TimeOfDay? estimatedSleepTime;
  final TimeOfDay? wakeTime;
  final Future<void> Function() onPickSleepTime;
  final Future<void> Function() onPickEstimatedSleepTime;
  final Future<void> Function() onPickWakeTime;
  final TimeOfDay? finalWakeTime;
  final Future<void> Function() onPickFinalWakeTime;
  final List<NightAwakeningItem> nightAwakenings;
  final Future<void> Function() onAddNightAwakening;
  final Future<void> Function(int) onEditNightAwakening;
  final void Function(int) onDeleteNightAwakening;
  final String legacyMidWakeText;

  final Set<SleepFlag> flags;
  final void Function(SleepFlag) onToggleFlag;

  final String sleepNote;
  final void Function(String) onChangeNote;

  final int? sleepQuality;
  final Future<void> Function() onPickValue;
  final ValueChanged<int>? onChangeSleepQuality;

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

  Widget _sleepCard({required Widget child, EdgeInsetsGeometry? margin}) {
    return Builder(
      builder: (context) => Container(
        margin: margin ?? const EdgeInsets.only(bottom: 10),
        decoration: HealingDesignSystem.adaptiveCardDecoration(context),
        child: child,
      ),
    );
  }

  InputDecoration _sleepInputDecoration({
    required BuildContext context,
    required String hintText,
    String? labelText,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: HealingDesignSystem.adaptiveFill(context),
      hintStyle: TextStyle(
        color: HealingDesignSystem.adaptiveSecondaryText(context),
      ),
      labelStyle: TextStyle(
        color: HealingDesignSystem.adaptiveSecondaryText(context),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        borderSide: BorderSide(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        borderSide: BorderSide(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        borderSide: const BorderSide(
          color: HealingDesignSystem.primaryBlue,
          width: 1.4,
        ),
      ),
      isDense: true,
    );
  }

  Widget _nightAwakeningTile(
    BuildContext context,
    NightAwakeningItem item,
    int index,
  ) {
    final detail = item.end != null
        ? ' → ${DateHelper.formatTime(item.end)}'
        : item.estimatedDurationMinutes != null
            ? ' · 約 ${item.estimatedDurationMinutes} 分鐘'
            : '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.access_time_outlined),
      title: Text('${DateHelper.formatTime(item.start)}$detail'),
      subtitle:
          item.note?.trim().isNotEmpty == true ? Text(item.note!.trim()) : null,
      onTap: () => onEditNightAwakening(index),
      trailing: IconButton(
        tooltip: '刪除這筆夜間醒來',
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: () => onDeleteNightAwakening(index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onSurface = colorScheme.onSurface;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sleepCard(
          child: SwitchListTile(
            secondary: const Icon(
              Icons.medication_outlined,
              color: HealingDesignSystem.primaryBlue,
            ),
            title: const Text('前一晚是否有吃安眠藥？'),
            value: tookHypnotic,
            activeThumbColor: HealingDesignSystem.primaryBlue,
            onChanged: onToggleHypnotic,
          ),
        ),
        if (tookHypnotic) ...[
          _sleepCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 20,
                        color: HealingDesignSystem.mutedText,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '安眠藥名稱與劑量',
                        style: HealingDesignSystem.titleSmall.copyWith(
                          color:
                              HealingDesignSystem.adaptivePrimaryText(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hypnoticNameCtrl,
                    style: TextStyle(
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    ),
                    decoration: _sleepInputDecoration(
                      context: context,
                      hintText: '例如：Clonazepam（克癇平）',
                      prefixIcon: const Icon(Icons.local_pharmacy_outlined),
                    ),
                    onChanged: onChangeHypnoticName,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hypnoticDoseCtrl,
                    style: TextStyle(
                      color: HealingDesignSystem.adaptivePrimaryText(context),
                    ),
                    decoration: _sleepInputDecoration(
                      context: context,
                      hintText: '例如：0.5 mg',
                      prefixIcon: const Icon(Icons.numbers),
                    ),
                    onChanged: onChangeHypnoticDose,
                  ),
                ],
              ),
            ),
          ),
        ],
        _sleepCard(
          child: ListTile(
            leading: const Icon(
              Icons.bed_outlined,
              color: HealingDesignSystem.primaryBlue,
            ),
            title: const Text('前一日準備睡覺時間'),
            subtitle: Text(
                sleepTime == null ? '—' : DateHelper.formatTime(sleepTime!)),
            onTap: onPickSleepTime,
          ),
        ),
        _sleepCard(
          child: ListTile(
            leading: const Icon(
              Icons.bedtime_outlined,
              color: HealingDesignSystem.primaryBlue,
            ),
            title: const Text('大約幾點睡著？（選填）'),
            subtitle: Text(
              estimatedSleepTime == null
                  ? '不確定可留空，系統會以準備睡覺時間估算'
                  : DateHelper.formatTime(estimatedSleepTime),
            ),
            onTap: onPickEstimatedSleepTime,
          ),
        ),
        _sleepCard(
          child: ExpansionTile(
            leading: const Icon(
              Icons.nightlight_outlined,
              color: HealingDesignSystem.primaryBlue,
            ),
            title: const Text('夜間睡眠狀況'),
            subtitle: Text(
              flags.isEmpty ? '未選擇' : '已選 ${flags.length} 項',
              style: const TextStyle(
                color: HealingDesignSystem.mutedText,
                fontSize: 13,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('可多選',
                        style: TextStyle(
                          fontSize: 12,
                          color: HealingDesignSystem.mutedText,
                        )),
                    const SizedBox(height: 8),
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
                          return ChoiceChip(
                            label: Text(sleepFlagLabel(f)),
                            selected: selected,
                            onSelected: (_) => onToggleFlag(f),
                            selectedColor: HealingDesignSystem.primaryBlue
                                .withValues(alpha: 0.16),
                            side: BorderSide(
                              color: selected
                                  ? HealingDesignSystem.primaryBlue
                                  : HealingDesignSystem.lineColor,
                            ),
                            labelStyle: TextStyle(
                              color: selected
                                  ? HealingDesignSystem.primaryBlue
                                  : HealingDesignSystem.adaptivePrimaryText(
                                      context),
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  HealingDesignSystem.radiusM),
                            ),
                          );
                        }).toList();
                      })(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _sleepCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.star_border_rounded,
                      color: HealingDesignSystem.primaryBlue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '自覺睡眠品質',
                      style: HealingDesignSystem.titleSmall.copyWith(
                        color: HealingDesignSystem.adaptivePrimaryText(context),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      sleepQuality == null ? '尚未評分' : '$sleepQuality / 5',
                      style: HealingDesignSystem.bodySmall.copyWith(
                        color:
                            HealingDesignSystem.adaptiveSecondaryText(context),
                      ),
                    ),
                  ],
                ),
                if (onChangeSleepQuality == null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: onPickValue,
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('選擇睡眠品質'),
                    ),
                  ),
                ] else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '1 分：最差｜3 分：普通｜5 分：最好',
                        style: HealingDesignSystem.bodySmall,
                      ),
                      EmotionSlider(
                        label: '睡眠品質',
                        value: sleepQuality ?? 3,
                        onChanged: onChangeSleepQuality,
                        leftIcon: 'assets/emotion/default.png',
                        rightIcon: 'assets/emotion/default.png',
                        gradientColors: const [
                          Color(0xFF9AD0EC),
                          Color(0xFFFFE08A),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        _sleepCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '睡眠註記',
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: sleepNote,
                  minLines: 1,
                  maxLines: 3,
                  style: TextStyle(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                  decoration: _sleepInputDecoration(
                    context: context,
                    hintText: '例如：一直做夢，感覺好像沒睡覺，起床精神很差',
                    prefixIcon: const Icon(Icons.edit_note),
                  ),
                  onChanged: onChangeNote,
                ),
              ],
            ),
          ),
        ),
        _sleepCard(
          margin: const EdgeInsets.fromLTRB(0, 2, 0, 5),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HealingDesignSystem.adaptiveFill(context),
              borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
              border: Border.all(color: HealingDesignSystem.lineColor),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  color: HealingDesignSystem.primaryBlue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '紀錄小撇步',
                        style: HealingDesignSystem.titleSmall.copyWith(
                          color:
                              HealingDesignSystem.adaptivePrimaryText(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '半夜醒來或剛睡醒時不想開 App？\n試試「手機截圖」！起床後再看相簿時間回填即可，減少看螢幕的焦慮。',
                        style: HealingDesignSystem.bodySmall.copyWith(
                          color: HealingDesignSystem.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _sleepCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '夜間醒來',
                  style: HealingDesignSystem.titleSmall.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '記錄醒來時間，並可補上再次睡著時間或推估清醒時長。',
                  style: HealingDesignSystem.bodySmall.copyWith(
                    color: HealingDesignSystem.mutedText,
                  ),
                ),
                if (nightAwakenings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (var i = 0; i < nightAwakenings.length; i++)
                    _nightAwakeningTile(context, nightAwakenings[i], i),
                ],
                if (legacyMidWakeText.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: HealingDesignSystem.adaptiveFill(context),
                      borderRadius: BorderRadius.circular(
                        HealingDesignSystem.radiusS,
                      ),
                    ),
                    child: Text(
                      '舊版夜間醒來註記：${legacyMidWakeText.trim()}',
                      style: HealingDesignSystem.bodySmall.copyWith(
                        color: HealingDesignSystem.mutedText,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onAddNightAwakening,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('新增夜間醒來'),
                  ),
                ),
              ],
            ),
          ),
        ),
        _sleepCard(
          child: ListTile(
            leading: const Icon(
              Icons.wb_twilight,
              color: HealingDesignSystem.primaryBlue,
            ),
            title: const Text('甦醒時刻 (睜開眼)'),
            subtitle: Text(
              finalWakeTime == null
                  ? '尚未設定'
                  : DateHelper.formatTime(finalWakeTime),
              style: TextStyle(
                color: finalWakeTime == null
                    ? colorScheme.onSurfaceVariant
                    : onSurface,
              ),
            ),
            onTap: onPickFinalWakeTime,
          ),
        ),
        _sleepCard(
          child: ListTile(
            leading: const Icon(
              Icons.directions_run,
              color: HealingDesignSystem.primaryBlue,
            ),
            title: const Text('離床活動時間'),
            subtitle: Text(
              wakeTime == null ? '—' : DateHelper.formatTime(wakeTime),
            ),
            onTap: onPickWakeTime,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '小睡（可新增多筆)',
          style: HealingDesignSystem.titleSmall.copyWith(
            color: HealingDesignSystem.adaptivePrimaryText(context),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(naps.length, (i) {
          final n = naps[i];
          return _sleepCard(
            child: ListTile(
              leading: const Icon(
                Icons.timer_outlined,
                color: HealingDesignSystem.primaryBlue,
              ),
              title: Text(
                  '${DateHelper.formatTime(n.start)} – ${DateHelper.formatTime(n.end)}'),
              subtitle: Text(
                  '時長：${DateHelper.formatDurationText(n.durationMinutes)}'),
              onTap: () => onEditNap(i),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDeleteNap(i),
              ),
            ),
          );
        }),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: HealingDesignSystem.lineColor,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAddNap,
              borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
              child: const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: HealingDesignSystem.paddingL,
                  vertical: HealingDesignSystem.paddingM,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: HealingDesignSystem.primaryBlue),
                    SizedBox(width: HealingDesignSystem.paddingM),
                    Text(
                      '新增小睡',
                      style: TextStyle(
                        color: HealingDesignSystem.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
