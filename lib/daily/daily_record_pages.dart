import 'package:flutter/material.dart';
import '../widgets/emotion_slider.dart';
import '../utils/date_helper.dart';
import '../models/daily_record.dart';
import 'daily_record_helpers.dart';
import 'daily_record_dialogs.dart';

// ============================================================
// Page Widgets
// ============================================================

const Map<String, String> emotionDisplayTextMap = {
  '整體情緒': '今天整體過得還好嗎？',
  '焦慮程度': '今天有感到緊繃或不安嗎？',
  '憂鬱程度': '今天心情有比較低落嗎？',
  '空虛程度': '有一種空空的感覺嗎？',
  '無聊程度': '今天有提不起勁嗎？',
  '難過程度': '今天有比較想哭或委屈嗎？',
  '開心程度': '今天有感到一點點開心嗎？',
  '無望感': '有覺得看不到出口嗎？',
  '孤獨感': '今天有覺得自己被落下嗎？',
  '動力': '今天做事有力氣嗎？',
  '自殺意念': '有出現讓你感到害怕的念頭嗎？',
  '食慾': '今天吃東西還順利嗎？',
  '能量': '今天身體的能量還夠嗎？',
  '活動量': '今天有稍微動一動嗎？',
  '疲倦程度': '今天是不是很累了？',
};

const Map<String, String> emotionRightIconMap = {
  // 舊有情緒
  '整體情緒': 'assets/emotion/overall.png',
  '焦慮程度': 'assets/emotion/anxious.png',
  '憂鬱程度': 'assets/emotion/depression.png',
  '空虛程度': 'assets/emotion/absence.png',
  '無聊程度': 'assets/emotion/boring.png',
  '難過程度': 'assets/emotion/sad.png',
  '開心程度': 'assets/emotion/happy.png',
  '無望感': 'assets/emotion/despair.png',
  '孤獨感': 'assets/emotion/loneliness.png',
  '動力': 'assets/emotion/power.png',
  '自殺意念': 'assets/emotion/自殺意念.png',
  '食慾': 'assets/emotion/食慾.png',
  '能量': 'assets/emotion/energy.png',
  '活動量': 'assets/emotion/活動量.png',
  '疲倦程度': 'assets/emotion/tired.png',
  // 整體狀態
  '平靜': 'assets/emotion/default.png',
  '開心': 'assets/emotion/happy.png',
  '有力量': 'assets/emotion/power.png',
  '疲憊': 'assets/emotion/tired.png',
  '沒動力': 'assets/emotion/boring.png',
  // 壓力情緒
  '焦慮': 'assets/emotion/anxious.png',
  '緊張': 'assets/emotion/anxious.png',
  '壓力大': 'assets/emotion/anxious.png',
  '煩躁': 'assets/emotion/anxious.png',
  '生氣': 'assets/emotion/anxious.png',
  // 低落警訊
  '難過': 'assets/emotion/sad.png',
  '憂鬱': 'assets/emotion/depression.png',
  '無助': 'assets/emotion/despair.png',
  '崩潰感': 'assets/emotion/despair.png',
};

/// 情緒分頁
class EmotionPage extends StatelessWidget {
  const EmotionPage({
    Key? key,
    required this.items,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onChangeValue,
  }) : super(key: key);

  final List<EmotionItem> items;
  final VoidCallback onAdd;
  final Future<void> Function(int index) onRename;
  final void Function(int index) onDelete;
  final void Function(int index, int value) onChangeValue;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onSurface = colorScheme.onSurface;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 🔹 情緒清單（Slider 版）
        ...List.generate(items.length, (i) {
          final item = items[i];
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 情緒名稱 + 編輯 / 刪除
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 🔹 左邊：情緒題目（主文）
                      Expanded(
                        child: Text(
                          emotionDisplayTextMap[item.name] ?? item.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),

                      // 🔹 右邊：引導 / 編輯 / 刪除
                      IconButton(
                        icon: const Icon(Icons.info_outline),
                        tooltip: '評分說明',
                        onPressed: () =>
                            showEmotionScaleGuideDialog(context, item.name),
                      ),

                      if (i != 0)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => onRename(i),
                        ),

                      if (i != 0)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => onDelete(i),
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // 🎚️ 情緒 Slider
                  EmotionSlider(
                    label: item.name,
                    value: item.value ?? 1,
                    onChanged: (v) => onChangeValue(i, v),
                    leftIcon: 'assets/emotion/default.png',
                    rightIcon: emotionRightIconMap[item.name] ??
                        'assets/emotion/default.png',
                    gradientColors: const [
                      Color(0xFF9AD0EC),
                      Color(0xFFFFE08A),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 12),

        // ➕ 新增情緒
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('新增情緒項目'),
        ),
      ],
    );
  }
}

/// 症狀分頁
class SymptomPage extends StatelessWidget {
  final List<SymptomItem> items;
  final VoidCallback onAdd;
  final Future<void> Function(int index) onRename;
  final void Function(int index) onDelete;
  final void Function(String name, bool selected) onTogglePreset;

  // 接收外部傳入的狀態
  final bool isPeriod;
  final ValueChanged<bool> onTogglePeriod;

  const SymptomPage({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.isPeriod,
    required this.onTogglePeriod,
    required this.onTogglePreset,
  });

  @override
  Widget build(BuildContext context) {
    // 根據開關狀態決定顏色
    final colorScheme = Theme.of(context).colorScheme;
    final onSurface = colorScheme.onSurface;
    final outline = colorScheme.outlineVariant;
    final muted = onSurface.withOpacity(0.65);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = Colors.pinkAccent;
    // 開啟時的背景 (ON)
    final activeBg = isDark
        ? Colors.pinkAccent.withOpacity(0.15) // 深色模式：深一點的粉紅透光
        : Colors.pink.withOpacity(0.1); // 淺色模式：淺粉紅

    // 關閉時的顏色 (OFF)
    final inactiveColor = isDark ? Colors.pink.shade200 : Colors.pink.shade200;
    final inactiveBg = isDark
        ? const Color(0xFF2A1C20) // 深色模式：帶有粉色調的深灰
        : const Color(0xFFFFF5F7); // 淺色模式：櫻花白

    const presetSymptoms = <String>{
      '心悸',
      '胸悶',
      '胸痛',
      '呼吸困難',
      '過度換氣',
      '胃食道逆流',
      '胃痛',
      '腹痛',
      '腹瀉',
      '便秘',
      '噁心反胃',
      '嘔吐',
      '脹氣',
      '食慾不振',
      '頭暈',
      '頭痛',
      '頭脹',
      '眼睛乾澀',
      '眼睛疲勞',
      '視力模糊',
      '不斷流淚',
      '耳鳴',
      '口乾舌燥',
      '失去味覺',
      '口腔苦澀',
      '咽喉異物感',
      '顫抖',
      '發麻',
      '手汗變多',
      '肌肉緊繃',
      '肌肉抽蓄',
      '四肢無力',
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. 生理期卡片
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isPeriod ? activeColor : inactiveColor.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          color: isPeriod ? activeBg : inactiveBg,
          child: SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isPeriod
                    ? Colors.pink.withOpacity(0.08)
                    : Colors.blueGrey.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset(
                'assets/icons/粉色水滴.png',
                width: 28,
                height: 28,
                fit: BoxFit.contain,
              ),
            ),
            title: Text(
              isPeriod ? '生理期中 🩸' : '生理期來了嗎？',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isPeriod ? Colors.pink : colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              isPeriod ? '紀錄中...' : '紀錄週期，預測下次經期',
              style: TextStyle(
                color: isPeriod ? Colors.pink.shade300 : Colors.grey,
              ),
            ),
            value: isPeriod,
            activeColor: activeColor,
            onChanged: (v) => onTogglePeriod(v),
          ),
        ),

        const SizedBox(height: 24),

        // 2. 症狀列表
        Card(
          elevation: 0,
          color: isDark
              ? colorScheme.surfaceVariant.withOpacity(0.95)
              : const Color(0xFFFFF1CC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? colorScheme.outline : outline.withOpacity(0.4),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: isDark
                      ? onSurface.withOpacity(0.92)
                      : Colors.amber.shade700,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '溫柔提醒',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: onSurface.withOpacity(isDark ? 0.98 : 0.9),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '不用很完整，想到什麼寫什麼就好。\n'
                        '也可以先寫一個最明顯的感覺：例如「心悸」「胸悶」「頭痛」。',
                        style: TextStyle(
                          color: onSurface.withOpacity(isDark ? 0.9 : 0.8),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 2. 心血管症狀（勾選）
        Text(
          '心血管與呼吸',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['心悸', '胸悶', '胸痛','呼吸不順', '過度換氣'].map((name) {
            final isSelected = items.any((s) => s.name == name);
            return FilterChip(
              label: Text(name),
              selected: isSelected,
              onSelected: (selected) => onTogglePreset(name, selected),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // 3. 消化系統（勾選）
        Text(
          '消化系統',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            '胃食道逆流',
            '胃痛',
            '腹痛',
            '腹瀉',
            '便秘',
            '噁心反胃',
            '嘔吐',
            '脹氣',
            '食慾不振',
          ].map((name) {
            final isSelected = items.any((s) => s.name == name);
            return FilterChip(
              label: Text(name),
              selected: isSelected,
              onSelected: (selected) => onTogglePreset(name, selected),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // 4. 頭部（勾選）
        Text(
          '頭部',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['頭暈', '頭痛', '頭脹'].map((name) {
            final isSelected = items.any((s) => s.name == name);
            return FilterChip(
              label: Text(name),
              selected: isSelected,
              onSelected: (selected) => onTogglePreset(name, selected),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // 5. 眼睛與耳朵（勾選）
        Text(
          '眼睛與耳朵',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['眼睛乾澀', '眼睛疲勞', '視力模糊', '不斷流淚', '耳鳴'].map((name) {
            final isSelected = items.any((s) => s.name == name);
            return FilterChip(
              label: Text(name),
              selected: isSelected,
              onSelected: (selected) => onTogglePreset(name, selected),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // 6. 口腔與咽喉（勾選）
        Text(
          '口腔與咽喉',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['口乾舌燥', '失去味覺', '口腔苦澀', '咽喉異物感'].map((name) {
            final isSelected = items.any((s) => s.name == name);
            return FilterChip(
              label: Text(name),
              selected: isSelected,
              onSelected: (selected) => onTogglePreset(name, selected),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // 7. 四肢與肌肉（勾選）
        Text(
          '四肢與肌肉',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['顫抖', '發麻', '手汗變多', '肌肉緊繃', '肌肉抽蓄', '四肢無力']
              .map((name) {
            final isSelected = items.any((s) => s.name == name);
            return FilterChip(
              label: Text(name),
              selected: isSelected,
              onSelected: (selected) => onTogglePreset(name, selected),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // 8. 自訂症狀清單
        if (items
            .asMap()
            .entries
            .any((e) => e.value.name.trim().isNotEmpty && !presetSymptoms.contains(e.value.name)))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '自訂症狀清單',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items.asMap().entries
                    .where((e) =>
                        e.value.name.trim().isNotEmpty &&
                        !presetSymptoms.contains(e.value.name))
                    .map((e) => InputChip(
                          label: Text(e.value.name),
                          onPressed: () => onRename(e.key),
                          onDeleted: () => onDelete(e.key),
                        ))
                    .toList(),
              ),
            ],
          ),

        const SizedBox(height: 8),

        // 3. 新增按鈕
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('新增症狀'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

/// 睡眠分頁
class SleepPage extends StatelessWidget {
  SleepPage({
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
    final colorScheme = Theme.of(context).colorScheme;
    final onSurface = colorScheme.onSurface;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SwitchListTile(
            secondary: const Icon(Icons.medication_outlined,
                color: Colors.purple),
            title: const Text('前一晚是否有吃安眠藥？'),
            value: tookHypnotic,
            onChanged: onToggleHypnotic,
          ),
        ),
        if (tookHypnotic) ...[
          const SizedBox(height: 8),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text('安眠藥名稱與劑量',
                      style: Theme.of(context).textTheme.titleMedium),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.bed_outlined, color: Colors.indigo),
            title: const Text('前一日準備睡覺時間'),
            subtitle: Text(sleepTime == null
                ? '—'
                : DateHelper.formatTime(sleepTime!)),
            onTap: onPickSleepTime,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ExpansionTile(
            leading: const Icon(Icons.nightlight_outlined, color: Colors.deepPurple),
            title: const Text('夜間睡眠狀況',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              flags.isEmpty ? '未選擇' : '已選 ${flags.length} 項',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('可多選',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                          return FilterChip(
                            label: Text(sleepFlagLabel(f)),
                            selected: selected,
                            onSelected: (_) => onToggleFlag(f),
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
        const SizedBox(height: 12),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading:
                const Icon(Icons.star_border_rounded, color: Colors.amber),
            title: const Text('自覺睡眠品質'),
            subtitle: Text(sleepQuality == null ? '—' : '$sleepQuality'),
            onTap: onPickValue,
          ),
        ),
        const SizedBox(height: 12),
        const Text('睡眠註記',
            style: TextStyle(fontWeight: FontWeight.w600)),
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
                            fontWeight: FontWeight.bold,
                            color: Colors.brown)),
                    const SizedBox(height: 4),
                    Text(
                      '半夜醒來或剛睡醒時不想開 App？\n試試「手機截圖」！起床後再看相簿時間回填即可，減少看螢幕的焦慮。',
                      style: TextStyle(
                          fontSize: 13, color: Colors.brown.shade700),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.wb_twilight, color: Colors.orange),
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
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        const Text('小睡（可新增多筆)',
            style: TextStyle(fontWeight: FontWeight.w600)),
        ...List.generate(naps.length, (i) {
          final n = naps[i];
          return Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.timer_outlined, color: Colors.teal),
              title: Text(
                  '${DateHelper.formatTime(n.start)} – ${DateHelper.formatTime(n.end)}'),
              subtitle: Text(
                  'time長：${DateHelper.formatDurationText(n.durationMinutes)}'),
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
