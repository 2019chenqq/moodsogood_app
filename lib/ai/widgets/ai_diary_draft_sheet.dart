import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/healing_design_system.dart';
import '../../diary/diary_repository.dart';
import '../ai_diary_draft.dart';
import '../ai_diary_draft_service.dart';

class AiDiaryDraftSheet extends StatefulWidget {
  const AiDiaryDraftSheet({
    super.key,
    required this.draft,
    required this.existingDiary,
  });

  final AiDiaryDraft draft;
  final DiaryEntry? existingDiary;

  @override
  State<AiDiaryDraftSheet> createState() => _AiDiaryDraftSheetState();
}

class _AiDiaryDraftSheetState extends State<AiDiaryDraftSheet> {
  static const _labels = <String, String>{
    'title': '標題',
    'content': '內容',
    'metaphor': '今天的情緒像',
    'highlight': '今天最想記錄的瞬間',
    'proudOf': '我做得不錯的地方',
    'themeSong': '今日主題曲',
    'selfCare': '我還能多照顧自己一點的地方',
    'gratitude': '今日感恩事項',
  };

  late final Map<String, TextEditingController> _controllers;
  late final Map<String, String> _initialValues;
  late final Map<String, bool> _included;
  late final Map<String, DiaryFieldMerge> _mergeChoices;
  late List<VerifiedSongRecommendation> _songs;
  String? _selectedSongId;
  bool _searchingSongs = false;

  @override
  void initState() {
    super.initState();
    final values = <String, String>{
      'title': _first(widget.draft.titleSuggestions),
      'content': widget.draft.content?.value ?? '',
      'metaphor': _first(widget.draft.emotionMetaphorSuggestions),
      'highlight': _first(widget.draft.memorableMomentSuggestions),
      'proudOf': _first(widget.draft.didWellSuggestions),
      'themeSong': '',
      'selfCare': _first(widget.draft.selfCareSuggestions),
      'gratitude': _first(widget.draft.gratitudeSuggestions),
    };
    _initialValues = Map.of(values);
    _controllers = values.map(
      (key, value) => MapEntry(key, TextEditingController(text: value)),
    );
    _included = values.map((key, value) => MapEntry(key, value.isNotEmpty));
    _mergeChoices = {
      for (final key in _labels.keys) key: DiaryFieldMerge.keepExisting,
    };
    _songs = List.of(widget.draft.songRecommendations);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.65,
      maxChildSize: 0.96,
      builder: (context, scrollController) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '今日紀錄草稿',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '稍後再整理',
                  ),
                ],
              ),
            ),
            if (widget.draft.safetyRiskDetected)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('對話中有需要優先留意的安全訊號；請先使用畫面上的安全支援資訊。'),
              ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _field(
                    'title',
                    widget.draft.titleSuggestions,
                    maxLines: 1,
                  ),
                  _field(
                    'content',
                    widget.draft.content == null
                        ? const []
                        : [widget.draft.content!],
                    maxLines: 7,
                  ),
                  _field(
                    'metaphor',
                    widget.draft.emotionMetaphorSuggestions,
                  ),
                  _field(
                    'highlight',
                    widget.draft.memorableMomentSuggestions,
                  ),
                  _field('proudOf', widget.draft.didWellSuggestions),
                  _songField(),
                  _field('selfCare', widget.draft.selfCareSuggestions),
                  _field('gratitude', widget.draft.gratitudeSuggestions),
                  if (widget.draft.missingFields.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '對話未提及：${widget.draft.missingFields.join('、')}。未提及的欄位會保持空白。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('儲存到今日紀錄'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 'regenerate:all'),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重新產生整份草稿'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('稍後再整理'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String key,
    List<DiaryDraftSuggestion> suggestions, {
    int maxLines = 3,
  }) {
    final existing = _existingValue(key);
    final enabled = _included[key] ?? false;
    return Card(
      color: HealingDesignSystem.adaptiveSurface(context),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: enabled,
              title: Text(
                _labels[key]!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: suggestions.isEmpty ? const Text('對話資訊不足，保持空白') : null,
              secondary: IconButton(
                onPressed: () => Navigator.pop(context, 'regenerate:$key'),
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '只重新產生此欄位',
              ),
              onChanged: (value) =>
                  setState(() => _included[key] = value == true),
            ),
            if (suggestions.length > 1)
              ...suggestions.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    _controllers[key]!.text == item.value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(item.value),
                  subtitle: _source(item),
                  onTap: !enabled
                      ? null
                      : () => setState(
                            () => _controllers[key]!.text = item.value,
                          ),
                ),
              )
            else if (suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _source(suggestions.first),
              ),
            TextField(
              controller: _controllers[key],
              enabled: enabled,
              minLines: 1,
              maxLines: maxLines,
              decoration: const InputDecoration(
                labelText: '可在儲存前修改',
                border: OutlineInputBorder(),
              ),
            ),
            if (existing.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('今日已有內容：$existing',
                  maxLines: 3, overflow: TextOverflow.ellipsis),
              DropdownButtonFormField<DiaryFieldMerge>(
                initialValue: _mergeChoices[key],
                decoration: const InputDecoration(labelText: '如何處理已有內容'),
                items: const [
                  DropdownMenuItem(
                    value: DiaryFieldMerge.keepExisting,
                    child: Text('保留原內容（預設）'),
                  ),
                  DropdownMenuItem(
                    value: DiaryFieldMerge.replace,
                    child: Text('使用 AI 草稿取代'),
                  ),
                  DropdownMenuItem(
                    value: DiaryFieldMerge.append,
                    child: Text('合併原內容與草稿'),
                  ),
                ],
                onChanged: enabled
                    ? (value) => setState(() {
                          if (value != null) _mergeChoices[key] = value;
                        })
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _songField() {
    final profile = widget.draft.songRecommendationProfile;
    final recommendations = _songs;
    final details = [
      ...profile.musicTags,
      if (profile.desiredEffect.isNotEmpty) profile.desiredEffect,
    ];
    return Card(
      color: HealingDesignSystem.adaptiveSurface(context),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日主題曲', style: Theme.of(context).textTheme.titleMedium),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context, 'regenerate:themeSong'),
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '重新推薦歌曲',
              ),
            ),
            const SizedBox(height: 8),
            if (recommendations.isEmpty)
              const Text('今天暫時找不到適合的主題曲。這不影響其他欄位儲存，也不會用 AI 編造歌曲。')
            else
              ...recommendations.map(
                (song) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: song.artworkUrl.isEmpty
                        ? const CircleAvatar(
                            child: Icon(Icons.music_note_rounded),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              song.artworkUrl,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                width: 48,
                                height: 48,
                                child: Icon(Icons.music_note_rounded),
                              ),
                            ),
                          ),
                    title: Text(song.title),
                    subtitle: Text(
                      '${song.artist}\n${song.reason}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: Icon(
                      _selectedSongId == song.candidateId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: () => setState(() {
                      _selectedSongId = song.candidateId;
                      _included['themeSong'] = true;
                      _controllers['themeSong']!.text =
                          '${song.title}｜${song.artist}';
                    }),
                  ),
                ),
              ),
            if (recommendations.isNotEmpty)
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _selectedSong == null
                        ? null
                        : () async {
                            final uri =
                                Uri.tryParse(_selectedSong!.externalUrl);
                            if (uri != null) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('到 Spotify 聆聽'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _selectedSongId = null;
                      _included['themeSong'] = false;
                      _controllers['themeSong']!.clear();
                    }),
                    child: const Text('今天不需要主題曲'),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _searchingSongs ? null : _searchSongs,
                icon: _searchingSongs
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
                label: const Text('自己搜尋歌曲'),
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    details.map((item) => Chip(label: Text(item))).toList(),
              ),
            ],
            if (_existingValue('themeSong').isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('目前主題曲：${_existingValue('themeSong')}'),
              ),
              DropdownButtonFormField<DiaryFieldMerge>(
                initialValue: _mergeChoices['themeSong'],
                decoration: const InputDecoration(labelText: '如何處理目前主題曲'),
                items: const [
                  DropdownMenuItem(
                    value: DiaryFieldMerge.keepExisting,
                    child: Text('保留原內容（預設）'),
                  ),
                  DropdownMenuItem(
                    value: DiaryFieldMerge.replace,
                    child: Text('使用新選擇取代'),
                  ),
                ],
                onChanged: _selectedSong == null
                    ? null
                    : (value) => setState(() {
                          if (value != null) {
                            _mergeChoices['themeSong'] = value;
                          }
                        }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _source(DiaryDraftSuggestion item) {
    final inferred = item.source == DiaryDraftSource.inferred;
    final label = switch (item.source) {
      DiaryDraftSource.explicit => '對話中明確提到',
      DiaryDraftSource.summarized => '依原意整理',
      DiaryDraftSource.inferred => 'AI 合理推測，請特別確認',
      DiaryDraftSource.suggested => 'AI／本地詞庫建議',
      DiaryDraftSource.missing => '資訊不足',
    };
    return Text(
      item.evidence.isEmpty ? label : '$label｜${item.evidence}',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: inferred ? Theme.of(context).colorScheme.error : null,
          ),
    );
  }

  String _existingValue(String key) {
    final entry = widget.existingDiary;
    if (entry == null) return '';
    return switch (key) {
      'title' => entry.title,
      'content' => entry.content,
      'themeSong' => entry.themeSong ?? '',
      'highlight' => entry.highlight ?? '',
      'metaphor' => entry.metaphor ?? '',
      'proudOf' => entry.proudOf ?? '',
      'selfCare' => entry.selfCare ?? '',
      'gratitude' => entry.gratitude ?? '',
      _ => '',
    };
  }

  void _submit() {
    final values = _controllers.map(
      (key, controller) => MapEntry(key, controller.text.trim()),
    );
    final included = _included.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toSet();
    final edited = values.entries
        .where((entry) => entry.value != _initialValues[entry.key])
        .map((entry) => entry.key)
        .toSet();
    Navigator.pop(
      context,
      DiaryDraftConfirmation(
        values: values,
        includedFields: included,
        mergeChoices: Map.of(_mergeChoices),
        userEditedFields: edited,
        selectedSong: _selectedSong,
      ),
    );
  }

  VerifiedSongRecommendation? get _selectedSong {
    for (final song in _songs) {
      if (song.candidateId == _selectedSongId) return song;
    }
    return null;
  }

  Future<void> _searchSongs() async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自己搜尋歌曲'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '歌名、歌手或關鍵字',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('搜尋'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (query == null || query.isEmpty || !mounted) return;
    setState(() => _searchingSongs = true);
    try {
      final results = await AiDiaryDraftService().searchSongs(query);
      if (!mounted) return;
      setState(() => _songs = results);
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('找不到可用的 Spotify 歌曲結果。')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('歌曲搜尋暫時無法使用，其他欄位仍可正常儲存。')),
        );
      }
    } finally {
      if (mounted) setState(() => _searchingSongs = false);
    }
  }

  static String _first(List<DiaryDraftSuggestion> values) =>
      values.isEmpty ? '' : values.first.value;
}
