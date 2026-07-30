import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/healing_design_system.dart';
import '../models/weekly_record.dart';
import 'weekly_record_repository.dart';

class WeeklyReviewPage extends StatefulWidget {
  const WeeklyReviewPage({
    super.key,
    required this.weekStart,
    required this.weekEnd,
  });

  final DateTime weekStart;
  final DateTime weekEnd;

  @override
  State<WeeklyReviewPage> createState() => _WeeklyReviewPageState();
}

class _WeeklyReviewPageState extends State<WeeklyReviewPage> {
  static const _stepTitles = ['整體', '情緒', '睡眠', '身體與生活', '這週的變化'];
  static const _stateLabels = ['很不好', '不太好', '普通', '還不錯', '很好'];
  static const _comparisons = ['明顯變差', '稍微變差', '差不多', '稍微變好', '明顯變好'];
  static const _emotions = [
    '平靜',
    '開心',
    '有希望',
    '焦慮',
    '緊張',
    '低落',
    '空虛',
    '煩躁',
    '生氣',
    '興奮',
    '疲憊',
    '麻木',
    '無聊',
    '害怕',
    '其他',
  ];
  static const _sleepIssues = [
    '入睡困難',
    '容易醒來',
    '太早醒',
    '睡眠時間不足',
    '睡太多',
    '作息不規律',
    '白天很想睡',
    '惡夢',
    '沒有明顯問題',
    '其他',
  ];
  static const _symptomOptions = [
    '心悸',
    '頭痛',
    '胸悶',
    '呼吸不順',
    '噁心',
    '食慾增加',
    '食慾下降',
    '疲倦',
    '注意力不集中',
    '身體疼痛',
    '焦躁坐立難安',
    '其他',
  ];
  static const _functionOptions = [
    '起床與維持作息',
    '工作或上課',
    '家事與自我照顧',
    '與人互動',
    '外出',
    '專注完成事情',
  ];
  static const _impactLabels = ['有點困難', '明顯困難', '幾乎做不到'];
  static const _majorChanges = [
    '藥物調整',
    '忘記或停止服藥',
    '回診或接受治療',
    '工作／學業壓力',
    '人際事件',
    '家庭事件',
    '身體不適或生病',
    '生理期',
    '飲食或體重明顯變化',
    '運動量改變',
    '生活作息改變',
    '其他重大事件',
    '沒有明顯變化',
  ];
  static const _safetyOptions = [
    '覺得撐不下去',
    '有傷害自己的念頭',
    '有失控、摔東西或傷害他人的衝動',
    '出現明顯幻聽、幻覺或強烈不真實感',
    '都沒有',
  ];

  final _pageController = PageController();
  final _eventController = TextEditingController();
  final _noteController = TextEditingController();
  final _nextWeekController = TextEditingController();

  int _step = 0;
  int? _overallState;
  String? _comparison;
  final Set<String> _selectedEmotions = {};
  String? _primaryEmotion;
  int? _primaryEmotionIntensity;
  int? _sleepQuality;
  String? _poorSleepDays;
  final Set<String> _selectedSleepIssues = {};
  final Map<String, WeeklySymptom> _selectedSymptoms = {};
  final Map<String, int> _functionImpacts = {};
  final Set<String> _selectedChanges = {};
  final Set<String> _safetyFlags = {};
  bool _saving = false;

  @override
  void dispose() {
    _pageController.dispose();
    _eventController.dispose();
    _noteController.dispose();
    _nextWeekController.dispose();
    super.dispose();
  }

  void _goToStep(int next) {
    if (next > _step && _step == 0 && _overallState == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先選一個最接近這週的整體狀態就好')),
      );
      return;
    }
    final target = next.clamp(0, _stepTitles.length - 1);
    setState(() => _step = target);
    _pageController.animateToPage(
      target,
      duration: HealingDesignSystem.animationNormal,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _save() async {
    if (_overallState == null) {
      _goToStep(0);
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登入後才能儲存週紀錄')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await WeeklyRecordRepository().saveWeeklyRecord(
        userId: uid,
        weekStart: widget.weekStart,
        weekEnd: widget.weekEnd,
        overallState: _overallState!,
        comparison: _comparison,
        emotions: _selectedEmotions.toList(),
        primaryEmotion: _primaryEmotion,
        primaryEmotionIntensity: _primaryEmotionIntensity,
        sleepQuality: _sleepQuality,
        poorSleepDays: _poorSleepDays,
        sleepIssues: _selectedSleepIssues.toList(),
        symptoms: _selectedSymptoms.values.toList(),
        functionImpacts: _functionImpacts,
        majorChanges: _selectedChanges.toList(),
        eventNote: _eventController.text,
        safetyFlags: _safetyFlags.toList(),
        note: _noteController.text,
        nextWeekFocus: _nextWeekController.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('暫時無法儲存，請稍後再試：$error')),
      );
    }
  }

  Future<void> _showSafetyReminder() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.health_and_safety_outlined,
          color: HealingDesignSystem.warningOrange,
          size: 32,
        ),
        title: const Text('先照顧此刻的安全'),
        content: const Text(
          '謝謝你願意說出來。若你現在可能傷害自己或他人，請先離開危險物品，不要獨處，並立即聯絡一位可以陪你的人或前往急診。\n\n'
          '你也可以撥打衛福部 1925 安心專線。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('我知道了'),
          ),
          FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse('tel:1925')),
            icon: const Icon(Icons.call_outlined),
            label: const Text('撥打 1925'),
          ),
        ],
      ),
    );
  }

  void _toggleExclusive({
    required Set<String> values,
    required String value,
    required String noneValue,
  }) {
    setState(() {
      if (value == noneValue) {
        values
          ..clear()
          ..add(value);
      } else {
        values.remove(noneValue);
        values.contains(value) ? values.remove(value) : values.add(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final secondary = HealingDesignSystem.adaptiveSecondaryText(context);
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
        foregroundColor: HealingDesignSystem.adaptiveAppBarForeground(context),
        title: const Text('3 分鐘每週回顧'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${_step + 1} / ${_stepTitles.length}',
                        style: TextStyle(
                          color: secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _stepTitles[_step],
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (_step + 1) / _stepTitles.length,
                      minHeight: 7,
                      color: HealingDesignSystem.primaryBlue,
                      backgroundColor:
                          HealingDesignSystem.adaptiveCardBorder(context),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildOverallStep(),
                  _buildEmotionStep(),
                  _buildSleepStep(),
                  _buildBodyAndFunctionStep(),
                  _buildChangesStep(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              decoration: BoxDecoration(
                color: HealingDesignSystem.adaptiveBackground(context),
                border: Border(
                  top: BorderSide(
                    color: HealingDesignSystem.adaptiveCardBorder(context),
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: () => _goToStep(_step - 1),
                      child: const Text('上一步'),
                    )
                  else
                    const SizedBox(width: 76),
                  const Spacer(),
                  Text(
                    _step == 0 ? '只有整體狀態必填' : '其餘皆可跳過',
                    style: TextStyle(color: secondary, fontSize: 11),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    key: Key(_step == _stepTitles.length - 1
                        ? 'save_weekly_review_button'
                        : 'next_weekly_review_button'),
                    onPressed: _saving
                        ? null
                        : _step == _stepTitles.length - 1
                            ? _save
                            : () => _goToStep(_step + 1),
                    style: FilledButton.styleFrom(
                      backgroundColor: HealingDesignSystem.primaryBlue,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_step == _stepTitles.length - 1 ? '完成' : '下一步'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepList(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: children,
    );
  }

  Widget _buildOverallStep() {
    return _stepList([
      const _StepIntro(
        title: '先留下一個這週的輪廓',
        description: '不用補回每天，也不用想得很精準。選最接近的答案就好。',
      ),
      _QuestionCard(
        title: '這週整體過得如何？',
        helper: '必填',
        child: _ScoreSelector(
          value: _overallState,
          labels: _stateLabels,
          onChanged: (value) => setState(() => _overallState = value),
        ),
      ),
      const SizedBox(height: 14),
      _QuestionCard(
        title: '和上週相比？',
        helper: '選填',
        child: _SingleChoiceWrap(
          options: _comparisons,
          value: _comparison,
          onChanged: (value) => setState(() {
            _comparison = _comparison == value ? null : value;
          }),
        ),
      ),
    ]);
  }

  Widget _buildEmotionStep() {
    return _stepList([
      const _StepIntro(
        title: '這週常出現哪些情緒？',
        description: '最多選 3 個。這會成為每週情緒趨勢，而不是診斷。',
      ),
      _QuestionCard(
        title: '本週主要情緒',
        helper: '${_selectedEmotions.length} / 3',
        child: _MultiChoiceWrap(
          options: _emotions,
          values: _selectedEmotions,
          maxSelections: 3,
          onToggle: (emotion) {
            setState(() {
              if (_selectedEmotions.contains(emotion)) {
                _selectedEmotions.remove(emotion);
                if (_primaryEmotion == emotion) {
                  _primaryEmotion = null;
                  _primaryEmotionIntensity = null;
                }
              } else if (_selectedEmotions.length < 3) {
                _selectedEmotions.add(emotion);
              }
            });
          },
        ),
      ),
      if (_selectedEmotions.isNotEmpty) ...[
        const SizedBox(height: 14),
        _QuestionCard(
          title: '最影響你的是哪一種？',
          helper: '選填',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SingleChoiceWrap(
                options: _selectedEmotions.toList(),
                value: _primaryEmotion,
                onChanged: (value) => setState(() {
                  _primaryEmotion = value;
                  _primaryEmotionIntensity ??= 3;
                }),
              ),
              if (_primaryEmotion != null) ...[
                const SizedBox(height: 14),
                Text('影響強度：${_primaryEmotionIntensity ?? 3} / 5'),
                Slider(
                  value: (_primaryEmotionIntensity ?? 3).toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '${_primaryEmotionIntensity ?? 3}',
                  onChanged: (value) => setState(
                    () => _primaryEmotionIntensity = value.round(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ]);
  }

  Widget _buildSleepStep() {
    return _stepList([
      const _StepIntro(
        title: '用估計的方式回想睡眠',
        description: '這是「本週回顧估計」，不是由每日資料算出的精確平均。',
      ),
      _QuestionCard(
        title: '整體睡眠品質如何？',
        helper: '選填',
        child: _ScoreSelector(
          value: _sleepQuality,
          labels: const ['很差', '較差', '普通', '不錯', '很好'],
          onChanged: (value) => setState(() => _sleepQuality = value),
        ),
      ),
      const SizedBox(height: 14),
      _QuestionCard(
        title: '這週大約有幾天睡不好？',
        helper: '選填',
        child: _SingleChoiceWrap(
          options: const ['0 天', '1～2 天', '3～4 天', '5 天以上'],
          value: _poorSleepDays,
          onChanged: (value) => setState(() => _poorSleepDays = value),
        ),
      ),
      const SizedBox(height: 14),
      _QuestionCard(
        title: '主要睡眠狀況',
        helper: '可複選',
        child: _MultiChoiceWrap(
          options: _sleepIssues,
          values: _selectedSleepIssues,
          onToggle: (value) => _toggleExclusive(
            values: _selectedSleepIssues,
            value: value,
            noneValue: '沒有明顯問題',
          ),
        ),
      ),
    ]);
  }

  Widget _buildBodyAndFunctionStep() {
    return _stepList([
      const _StepIntro(
        title: '哪些狀況影響了這週？',
        description: '只勾明顯的項目；沒選代表這週沒有要特別記。',
      ),
      _QuestionCard(
        title: '明顯症狀',
        helper: '選取後可補影響程度與頻率',
        child: Column(
          children: [
            _MultiChoiceWrap(
              options: _symptomOptions,
              values: _selectedSymptoms.keys.toSet(),
              onToggle: (name) => setState(() {
                if (_selectedSymptoms.containsKey(name)) {
                  _selectedSymptoms.remove(name);
                } else {
                  _selectedSymptoms[name] = WeeklySymptom(name: name);
                }
              }),
            ),
            ..._selectedSymptoms.entries.map((entry) {
              final symptom = entry.value;
              return _SymptomDetailRow(
                symptom: symptom,
                onChanged: (next) => setState(() {
                  _selectedSymptoms[entry.key] = next;
                }),
              );
            }),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _QuestionCard(
        title: '日常功能影響',
        helper: '只選有受到影響的項目',
        child: Column(
          children: [
            _MultiChoiceWrap(
              options: _functionOptions,
              values: _functionImpacts.keys.toSet(),
              onToggle: (name) => setState(() {
                if (_functionImpacts.containsKey(name)) {
                  _functionImpacts.remove(name);
                } else {
                  _functionImpacts[name] = 1;
                }
              }),
            ),
            ..._functionImpacts.entries.map(
              (entry) => _ImpactRow(
                label: entry.key,
                value: entry.value,
                onChanged: (value) => setState(() {
                  _functionImpacts[entry.key] = value;
                }),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildChangesStep() {
    return _stepList([
      const _StepIntro(
        title: '最後，留下重要變化',
        description: '這些內容可直接整理進回診摘要；安全題不會被藏在週報裡。',
      ),
      _QuestionCard(
        title: '這週發生哪些變化？',
        helper: '可複選',
        child: Column(
          children: [
            _MultiChoiceWrap(
              options: _majorChanges,
              values: _selectedChanges,
              onToggle: (value) => _toggleExclusive(
                values: _selectedChanges,
                value: value,
                noneValue: '沒有明顯變化',
              ),
            ),
            if (_selectedChanges.isNotEmpty &&
                !_selectedChanges.contains('沒有明顯變化')) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _eventController,
                minLines: 2,
                maxLines: 4,
                maxLength: 160,
                decoration: const InputDecoration(
                  labelText: '發生了什麼？（選填）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      _QuestionCard(
        title: '這週的安全狀態',
        helper: '固定保留的一題',
        child: _MultiChoiceWrap(
          options: _safetyOptions,
          values: _safetyFlags,
          onToggle: (value) {
            final isNewRisk = value != '都沒有' && !_safetyFlags.contains(value);
            _toggleExclusive(
              values: _safetyFlags,
              value: value,
              noneValue: '都沒有',
            );
            if (isNewRisk) _showSafetyReminder();
          },
        ),
      ),
      const SizedBox(height: 14),
      _QuestionCard(
        title: '這週最想記錄的一件事',
        helper: '選填',
        child: TextField(
          controller: _noteController,
          minLines: 2,
          maxLines: 4,
          maxLength: 160,
          decoration: const InputDecoration(
            hintText: '例如：這週先把日子過完，就已經很不容易。',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      const SizedBox(height: 14),
      _QuestionCard(
        title: '下週最希望關注什麼？',
        helper: '選填',
        child: TextField(
          controller: _nextWeekController,
          minLines: 1,
          maxLines: 3,
          maxLength: 100,
          decoration: const InputDecoration(
            hintText: '例如：睡眠與作息',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    ]);
  }
}

class _StepIntro extends StatelessWidget {
  const _StepIntro({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: HealingDesignSystem.adaptivePrimaryText(context),
              fontSize: 21,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            style: TextStyle(
              color: HealingDesignSystem.adaptiveSecondaryText(context),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.title,
    required this.helper,
    required this.child,
  });

  final String title;
  final String helper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: HealingDesignSystem.adaptiveCardDecoration(
        context,
        radius: HealingDesignSystem.radiusM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                helper,
                style: TextStyle(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ScoreSelector extends StatelessWidget {
  const _ScoreSelector({
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final int? value;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(5, (index) {
        final score = index + 1;
        final selected = value == score;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 4 ? 0 : 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(score),
              child: AnimatedContainer(
                duration: HealingDesignSystem.animationFast,
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? HealingDesignSystem.primaryBlue.withValues(alpha: 0.18)
                      : HealingDesignSystem.adaptiveFill(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? HealingDesignSystem.primaryBlue
                        : HealingDesignSystem.adaptiveCardBorder(context),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '$score',
                      style: TextStyle(
                        color: selected
                            ? HealingDesignSystem.primaryBlue
                            : HealingDesignSystem.adaptivePrimaryText(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color:
                            HealingDesignSystem.adaptiveSecondaryText(context),
                        fontSize: 10,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _SingleChoiceWrap extends StatelessWidget {
  const _SingleChoiceWrap({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<String> options;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options
          .map(
            (option) => ChoiceChip(
              label: Text(option),
              selected: value == option,
              showCheckmark: false,
              onSelected: (_) => onChanged(option),
            ),
          )
          .toList(),
    );
  }
}

class _MultiChoiceWrap extends StatelessWidget {
  const _MultiChoiceWrap({
    required this.options,
    required this.values,
    required this.onToggle,
    this.maxSelections,
  });

  final List<String> options;
  final Set<String> values;
  final ValueChanged<String> onToggle;
  final int? maxSelections;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final selected = values.contains(option);
        final disabled = !selected &&
            maxSelections != null &&
            values.length >= maxSelections!;
        return FilterChip(
          label: Text(option),
          selected: selected,
          showCheckmark: false,
          onSelected: disabled ? null : (_) => onToggle(option),
        );
      }).toList(),
    );
  }
}

class _SymptomDetailRow extends StatelessWidget {
  const _SymptomDetailRow({
    required this.symptom,
    required this.onChanged,
  });

  final WeeklySymptom symptom;
  final ValueChanged<WeeklySymptom> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HealingDesignSystem.adaptiveFill(context),
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusS),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            symptom.name,
            style: TextStyle(
              color: HealingDesignSystem.adaptivePrimaryText(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: symptom.intensity,
                  decoration: const InputDecoration(
                    labelText: '影響程度',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(
                    5,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('${index + 1} / 5'),
                    ),
                  ),
                  onChanged: (value) => onChanged(
                    WeeklySymptom(
                      name: symptom.name,
                      intensity: value ?? symptom.intensity,
                      frequency: symptom.frequency,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: symptom.frequency,
                  decoration: const InputDecoration(
                    labelText: '出現頻率',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const ['偶爾', '數天', '大部分時間']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => onChanged(
                    WeeklySymptom(
                      name: symptom.name,
                      intensity: symptom.intensity,
                      frequency: value ?? symptom.frequency,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: HealingDesignSystem.adaptiveFill(context),
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusS),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: HealingDesignSystem.adaptivePrimaryText(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: List.generate(
              3,
              (index) => ButtonSegment(
                value: index + 1,
                label: Text(
                  _WeeklyReviewPageState._impactLabels[index],
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ],
      ),
    );
  }
}
