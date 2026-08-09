import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import '../models/daily_check_in.dart';
import '../widgets/emotion_slider.dart';
import 'daily_check_in_service.dart';

class DailyCheckInPage extends StatefulWidget {
  const DailyCheckInPage({super.key, this.date});

  final DateTime? date;

  @override
  State<DailyCheckInPage> createState() => _DailyCheckInPageState();
}

class _DailyCheckInPageState extends State<DailyCheckInPage> {
  final _service = DailyCheckInService();
  int? _overallMood;
  int? _healthStatus;
  bool _noSpecialEvent = false;
  bool _loading = true;
  bool _saving = false;

  DateTime get _date {
    final value = widget.date ?? DateTime.now();
    return DateTime(value.year, value.month, value.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final checkIn = await _service.getForDate(_date);
      if (!mounted) return;
      setState(() {
        _overallMood = checkIn?.overallMood;
        _healthStatus = checkIn?.healthStatus;
        _noSpecialEvent = checkIn?.noSpecialEvent ?? false;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法載入今日 Check-in：$error')),
      );
    }
  }

  Future<void> _save() async {
    if (_overallMood == null || _healthStatus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請完成兩項 1～5 分評分')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.save(DailyCheckIn(
        date: _date,
        overallMood: _overallMood!,
        healthStatus: _healthStatus!,
        noSpecialEvent: _noSpecialEvent,
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('今日 Check-in 已儲存')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存失敗：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('每日 Check-in')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
                children: [
                  _ScoreCard(
                    title: '整體情緒',
                    value: _overallMood,
                    onChanged: (value) => setState(() => _overallMood = value),
                  ),
                  const SizedBox(height: 12),
                  _ScoreCard(
                    title: '今日身心狀態',
                    value: _healthStatus,
                    onChanged: (value) => setState(() => _healthStatus = value),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: _noSpecialEvent,
                    onChanged: (value) =>
                        setState(() => _noSpecialEvent = value ?? false),
                    title: const Text('今天沒有特別需要記錄的狀況'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? '儲存中…' : '儲存'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
      decoration: HealingDesignSystem.cardDecoration(
        bgColor: HealingDesignSystem.adaptiveSurface(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: HealingDesignSystem.titleMedium),
          Text(
            value == null ? '尚未評分，請滑動選擇 1～5' : '$value / 5',
            style: HealingDesignSystem.bodySmall,
          ),
          EmotionSlider(
            label: title,
            value: value,
            onChanged: onChanged,
            leftIcon: 'assets/emotion/default.png',
            rightIcon: 'assets/emotion/default.png',
            gradientColors: const [Color(0xFF9AD0EC), Color(0xFFFFE08A)],
          ),
        ],
      ),
    );
  }
}
