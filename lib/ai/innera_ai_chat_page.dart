import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../constants/healing_design_system.dart';
import 'innera_ai_message.dart';
import 'innera_ai_mode.dart';
import 'innera_ai_record_draft.dart';
import 'innera_ai_record_draft_service.dart';
import 'innera_ai_safety_service.dart';
import 'innera_ai_service.dart';
import 'widgets/ai_message_bubble.dart';
import 'widgets/ai_safety_notice.dart';
import 'widgets/ai_record_draft_card.dart';

class InneraAiChatPage extends StatefulWidget {
  const InneraAiChatPage({
    super.key,
    required this.initialMode,
    InneraAiService? service,
  }) : _service = service;

  final InneraAiMode initialMode;
  final InneraAiService? _service;

  @override
  State<InneraAiChatPage> createState() => _InneraAiChatPageState();
}

class _InneraAiChatPageState extends State<InneraAiChatPage> {
  static const int _maxInputLength = 2000;

  late InneraAiMode _mode;
  late InneraAiService _service;
  final _messages = <InneraAiMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _isSending = false;
  String? _lastFailedInput;
  AiSafetyLevel _activeSafetyLevel = AiSafetyLevel.normal;
  final _draftService = InneraAiRecordDraftService();
  InneraAiRecordDraft? _recordDraft;
  bool _loadingDraft = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _service = widget._service ?? InneraAiService();
    _addWelcomeMessage();
    if (_mode == InneraAiMode.dailyRecord) _loadTodayDraft();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addWelcomeMessage() {
    _messages.add(
      InneraAiMessage(
        id: 'welcome-${DateTime.now().microsecondsSinceEpoch}',
        role: InneraAiMessageRole.assistant,
        text: _mode.welcomeMessage,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _loadTodayDraft() async {
    setState(() => _loadingDraft = true);
    try {
      final draft = await _draftService.loadOrCreateToday();
      if (!mounted) return;
      setState(() {
        _recordDraft = draft;
        if (draft.rawUserEntries.isNotEmpty ||
            draft.emotions.isNotEmpty ||
            draft.symptoms.isNotEmpty) {
          _messages.add(InneraAiMessage(
            id: 'draft-restored-${DateTime.now().microsecondsSinceEpoch}',
            role: InneraAiMessageRole.assistant,
            text: draft.hasExistingRecord
                ? '今天已經有一筆紀錄。這次整理的內容將先作為草稿，確認後再合併。'
                : '我保留了你剛才整理到的內容，可以繼續補充。',
            createdAt: DateTime.now(),
          ));
        }
        _loadingDraft = false;
      });
      _scrollToBottom();
    } catch (error, stackTrace) {
      debugPrint('InneraAiChatPage draft load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _loadingDraft = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (_mode == InneraAiMode.dailyRecord && _recordDraft != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('今天的紀錄草稿已保存，你可以稍後回來繼續。')),
      );
      return true;
    }
    final hasConversation =
        _messages.where((m) => m.role == InneraAiMessageRole.user).isNotEmpty;
    if (!hasConversation) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('離開對話？'),
        content: const Text('這次對話尚未儲存，離開後將不會保留。確定要離開嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('繼續對話'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('離開'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _send({String? overrideText}) async {
    final text = (overrideText ?? _controller.text).trim();
    if (text.isEmpty || text.length > _maxInputLength || _isSending) return;

    setState(() {
      _isSending = true;
      _lastFailedInput = null;
      if (overrideText == null) _controller.clear();
      _messages.add(
        InneraAiMessage(
          id: 'u-${DateTime.now().microsecondsSinceEpoch}',
          role: InneraAiMessageRole.user,
          text: text,
          createdAt: DateTime.now(),
        ),
      );
      _messages.add(
        InneraAiMessage(
          id: 'loading-${DateTime.now().microsecondsSinceEpoch}',
          role: InneraAiMessageRole.assistant,
          text: '',
          createdAt: DateTime.now(),
          isLoading: true,
        ),
      );
    });
    _scrollToBottom();

    try {
      final response = await _service
          .sendMessage(
            mode: _mode,
            history: _messages,
            userMessage: text,
            recordDraft:
                _mode == InneraAiMode.dailyRecord ? _recordDraft : null,
          )
          .timeout(const Duration(seconds: 70));
      if (!mounted) return;
      InneraAiRecordDraft? nextDraft;
      if (_mode == InneraAiMode.dailyRecord) {
        final recordDraftPatch = response.recordDraft == null
            ? null
            : Map<String, dynamic>.from(response.recordDraft!);
        if (_mentionsPreviousDaySleep(text)) {
          // A message about yesterday must not overwrite today's sleep record.
          recordDraftPatch?.remove('sleep');
        }
        nextDraft = (_recordDraft ?? InneraAiRecordDraft.empty(DateTime.now()))
            .mergePatch(recordDraftPatch, rawUserEntry: text)
            .mergeExplicitEmotionScores(text);
        await _draftService.save(nextDraft);
      }
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((message) => message.isLoading);
        _activeSafetyLevel = response.safetyLevel;
        if (!response.requiresFixedSafetyUi) {
          _messages.add(
            InneraAiMessage(
              id: 'a-${DateTime.now().microsecondsSinceEpoch}',
              role: InneraAiMessageRole.assistant,
              text: response.displayText,
              createdAt: DateTime.now(),
              sources: response.sources,
              safetyLevel: response.safetyLevel,
            ),
          );
        }
        if (nextDraft != null) _recordDraft = nextDraft;
        _isSending = false;
      });
      _scrollToBottom();
    } on FirebaseFunctionsException catch (error, stackTrace) {
      debugPrint(
        'generateInneraAiChat failed in chat page: '
        'code=${error.code}, message=${error.message}, '
        'details=${error.details}',
      );
      debugPrintStack(stackTrace: stackTrace);
      _showSendError(text, _callableErrorMessage(error));
    } catch (error, stackTrace) {
      debugPrint('InneraAiChatPage send failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showSendError(text, _messageForError(error));
    }
  }

  bool _mentionsPreviousDaySleep(String text) {
    return RegExp(r'昨天[^，。！？\n]{0,16}(睡眠|入睡|起床|睡覺)').hasMatch(text) ||
        RegExp(r'(睡眠|入睡|起床|睡覺)[^，。！？\n]{0,16}昨天').hasMatch(text);
  }

  void _showSendError(String text, String message) {
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((message) => message.isLoading);
      _lastFailedInput = text;
      _messages.add(
        InneraAiMessage(
          id: 'err-${DateTime.now().microsecondsSinceEpoch}',
          role: InneraAiMessageRole.assistant,
          text: message,
          createdAt: DateTime.now(),
          isError: true,
          canRetry: true,
        ),
      );
      _isSending = false;
    });
    _scrollToBottom();
  }

  String _messageForError(Object error) =>
      error is InneraAiException ? error.message : 'AI 服務暫時無法回覆，請稍後再試。';

  String _callableErrorMessage(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
        return '登入狀態已失效，請重新登入後再試。';
      case 'not-found':
        return 'AI 服務尚未部署，請確認 Firebase Functions 設定。';
      case 'failed-precondition':
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'AI 服務設定暫時無法使用。';
      case 'resource-exhausted':
        return 'AI 使用額度已達限制，請稍後再試。';
      case 'internal':
        return 'AI 服務暫時無法回覆，請稍後再試。';
      default:
        return 'AI 服務暫時無法回覆，請稍後再試。';
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _showDraftPreview() async {
    final draft = _recordDraft;
    if (draft == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text('今天的紀錄', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('情緒', style: Theme.of(context).textTheme.titleSmall),
            Text(draft.emotions.isEmpty
                ? '尚未補充'
                : [
                    if (draft.overallMood != null)
                      '整體情緒：${draft.overallMood} / 5',
                    ...draft.emotions.map(
                      (item) => item.source ==
                              AiDraftSource.defaultPendingConfirmation
                          ? '${item.name}：暫定 ${item.score} / 5（可調整）'
                          : '${item.name}：${item.score} / 5',
                    ),
                  ].join('\n')),
            const SizedBox(height: 14),
            Text('症狀', style: Theme.of(context).textTheme.titleSmall),
            Text(draft.symptoms.isEmpty ? '尚未補充' : draft.symptoms.join('、')),
            const SizedBox(height: 14),
            Text('睡眠', style: Theme.of(context).textTheme.titleSmall),
            Text(_sleepPreview(draft)),
            const SizedBox(height: 14),
            Text('原始內容', style: Theme.of(context).textTheme.titleSmall),
            Text(draft.rawUserEntries.isEmpty
                ? '尚未補充'
                : draft.rawUserEntries.join('\n\n')),
            const SizedBox(height: 14),
            Text('AI 整理', style: Theme.of(context).textTheme.titleSmall),
            Text(draft.diaryText.isEmpty ? '尚未補充' : draft.diaryText),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'confirm'),
              child: const Text('確認加入今日紀錄'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('繼續補充'),
            ),
          ],
        ),
      ),
    );
    if (action != 'confirm' || !mounted) return;
    await _confirmDraft(draft);
  }

  String _sleepPreview(InneraAiRecordDraft draft) {
    final sleep = draft.sleep;
    final details = <String>[];
    if (sleep.sleepTime != null) details.add('${sleep.sleepTime} 入睡');
    if (sleep.wakeTime != null) details.add('${sleep.wakeTime} 起床');
    if (sleep.quality != null) details.add('品質 ${sleep.quality} / 5');
    if (sleep.midWakeList != null) details.add('中途醒來：${sleep.midWakeList}');
    details.addAll(sleep.flags);
    return details.isEmpty ? '尚未補充' : details.join('\n');
  }

  Future<void> _confirmDraft(InneraAiRecordDraft draft) async {
    final selection = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('選擇日記內容'),
        content:
            const Text('原始內容會保留使用者描述；AI 整理版本可作為較易閱讀的日記。若當天已有日記，選擇附加會保留原文。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'rawAppend'),
            child: const Text('使用原始內容並附加'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'aiAppend'),
            child: const Text('使用 AI 整理並附加'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'aiReplace'),
            child: const Text('使用 AI 整理取代'),
          ),
        ],
      ),
    );
    if (selection == null || !mounted) return;
    final content = selection == 'rawAppend'
        ? draft.rawUserEntries.join('\n\n')
        : draft.diaryText;
    try {
      await _draftService.confirmAndMerge(
        draft: draft,
        diaryContent: content,
        replaceDiary: selection == 'aiReplace',
      );
      if (!mounted) return;
      setState(() => _recordDraft = draft.copyWith(confirmed: true));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已合併到今天的每日紀錄與日記。')),
      );
    } catch (error, stackTrace) {
      debugPrint('InneraAiChatPage confirm draft failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('目前無法確認儲存，草稿仍會保留。')),
        );
      }
    }
  }

  Future<void> _showModeSheet() async {
    final selected = await showModalBottomSheet<InneraAiMode>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            Text(
              '切換模式',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ...InneraAiMode.values.map(
              (mode) => ListTile(
                leading: Icon(mode.icon),
                title: Text(mode.title),
                subtitle: Text(mode.subtitle),
                selected: mode == _mode,
                onTap: () => Navigator.of(context).pop(mode),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || selected == _mode || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切換模式？'),
        content: const Text('切換模式後，AI 的回答方向與可使用的資料可能不同，是否繼續？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('繼續'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _mode = selected;
      _activeSafetyLevel = AiSafetyLevel.normal;
      _messages.add(
        InneraAiMessage(
          id: 'mode-${DateTime.now().microsecondsSinceEpoch}',
          role: InneraAiMessageRole.assistant,
          text: selected.welcomeMessage,
          createdAt: DateTime.now(),
        ),
      );
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('心域 AI'),
              InkWell(
                onTap: _isSending ? null : _showModeSheet,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '目前模式：${_mode.title}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.expand_more_rounded, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              AiSafetyNotice(
                level: _activeSafetyLevel,
                onTemporarilySafe: () {
                  setState(() {
                    _messages.add(
                      InneraAiMessage(
                        id: 'safe-${DateTime.now().microsecondsSinceEpoch}',
                        role: InneraAiMessageRole.assistant,
                        text: InneraAiSafetyService.temporarilySafeReply,
                        createdAt: DateTime.now(),
                        safetyLevel: AiSafetyLevel.possibleSelfHarm,
                      ),
                    );
                  });
                  _scrollToBottom();
                },
              ),
              if (_mode == InneraAiMode.dailyRecord &&
                  !_loadingDraft &&
                  _recordDraft != null)
                AiRecordDraftCard(
                  draft: _recordDraft!,
                  onPreview: _showDraftPreview,
                ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return AiMessageBubble(
                      message: message,
                      onRetry: _lastFailedInput == null
                          ? null
                          : () {
                              setState(() {
                                _messages.removeWhere((item) => item.isError);
                              });
                              _send(overrideText: _lastFailedInput);
                            },
                    );
                  },
                ),
              ),
              _InputBar(
                controller: _controller,
                focusNode: _focusNode,
                mode: _mode,
                isSending: _isSending,
                maxLength: _maxInputLength,
                onSend: () => _send(),
              ),
              if (_mode == InneraAiMode.dailyRecord &&
                  _shouldShowScoreShortcuts())
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      const Text('1 最低'),
                      const SizedBox(width: 8),
                      ...List.generate(
                        5,
                        (index) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: OutlinedButton(
                              onPressed: _isSending
                                  ? null
                                  : () => _send(overrideText: '${index + 1} 分'),
                              child: Text('${index + 1}'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('5 最高'),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _shouldShowScoreShortcuts() {
    for (final message in _messages.reversed) {
      if (message.role == InneraAiMessageRole.assistant && !message.isLoading) {
        return message.text.contains('1～5') || message.text.contains('1 到 5');
      }
    }
    return false;
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.mode,
    required this.isSending,
    required this.maxLength,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final InneraAiMode mode;
  final bool isSending;
  final int maxLength;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HealingDesignSystem.adaptiveSurface(context),
        border: Border(
          top: BorderSide(
            color: HealingDesignSystem.adaptiveCardBorder(context),
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          10,
          12,
          10 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !isSending,
                minLines: 1,
                maxLines: 5,
                maxLength: maxLength,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: mode.inputHint,
                  counterText: '',
                  filled: true,
                  fillColor: HealingDesignSystem.adaptiveFill(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, child) {
                final canSend = value.text.trim().isNotEmpty &&
                    value.text.trim().length <= maxLength &&
                    !isSending;
                return IconButton.filled(
                  onPressed: canSend ? onSend : null,
                  icon: const Icon(Icons.send_rounded),
                  tooltip: '送出',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
