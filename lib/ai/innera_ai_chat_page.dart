import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/healing_design_system.dart';
import '../daily/emotion_dimensions.dart';
import 'ai_callable_diagnostics.dart';
import 'ai_diary_draft_service.dart';
import 'innera_ai_conversation_service.dart';
import 'innera_ai_chat_image_service.dart';
import 'innera_ai_message.dart';
import 'innera_ai_mode.dart';
import 'innera_ai_record_draft.dart';
import 'innera_ai_record_draft_service.dart';
import 'innera_ai_safety_service.dart';
import 'innera_ai_service.dart';
import 'widgets/ai_message_bubble.dart';
import 'widgets/ai_safety_notice.dart';
import 'widgets/ai_record_draft_card.dart';
import 'widgets/ai_diary_draft_sheet.dart';

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

class _AiImageMigration {
  const _AiImageMigration({
    required this.originalMessages,
    required this.messages,
    required this.oldPaths,
    required this.newPaths,
  });

  final List<InneraAiMessage> originalMessages;
  final List<InneraAiMessage> messages;
  final List<String> oldPaths;
  final List<String> newPaths;

  bool get hasChanges => oldPaths.isNotEmpty;
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
  InneraAiImageAttachment? _lastFailedImage;
  Uint8List? _pendingImageBytes;
  String? _pendingImageName;
  AiSafetyLevel _activeSafetyLevel = AiSafetyLevel.normal;
  final _draftService = InneraAiRecordDraftService();
  final _conversationService = InneraAiConversationService();
  final _imageService = InneraAiChatImageService();
  final _imagePicker = ImagePicker();
  InneraAiRecordDraft? _recordDraft;
  bool _loadingDraft = false;
  bool _isExtractingDiary = false;
  final _diaryDraftService = AiDiaryDraftService();

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _service = widget._service ?? InneraAiService();
    _loadTodaySession();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadTodaySession() async {
    setState(() => _loadingDraft = true);
    try {
      var draft = _mode.supportsDailyRecordDraft
          ? await _draftService.loadOrCreateToday()
          : null;
      if (draft != null &&
          !draft.confirmed &&
          draft.rawUserEntries.isNotEmpty) {
        draft = draft.reconcileExplicitRecordFacts();
        await _draftService.save(draft);
      }
      final conversation = await _conversationService.loadToday(mode: _mode);
      if (!mounted) return;
      var restoredMessages = <InneraAiMessage>[
        ...?conversation?.messages,
      ];
      final imageMigration = await _migrateLegacyImages(restoredMessages);
      restoredMessages = imageMigration.messages;
      if (!mounted) return;
      var migratedDraftEntries = false;
      if (_mode == InneraAiMode.dailyRecord &&
          draft != null &&
          restoredMessages.isEmpty &&
          draft.rawUserEntries.isNotEmpty) {
        migratedDraftEntries = true;
        final baseTime = DateTime.now().subtract(
          Duration(seconds: draft.rawUserEntries.length + 1),
        );
        for (var index = 0; index < draft.rawUserEntries.length; index++) {
          restoredMessages.add(
            InneraAiMessage(
              id: 'migrated-${draft.dateKey}-$index',
              role: InneraAiMessageRole.user,
              text: draft.rawUserEntries[index],
              createdAt: baseTime.add(Duration(seconds: index)),
            ),
          );
        }
        restoredMessages.add(
          InneraAiMessage(
            id: 'migrated-note-${draft.dateKey}',
            role: InneraAiMessageRole.assistant,
            text: '我已把先前保留在草稿中的原始內容恢復到對話，可以直接接著聊，不需要重新輸入。',
            createdAt: DateTime.now(),
          ),
        );
      }
      if (restoredMessages.isEmpty) {
        restoredMessages.add(_welcomeMessage());
      }
      setState(() {
        _recordDraft = draft;
        _messages
          ..clear()
          ..addAll(restoredMessages);
        _activeSafetyLevel = restoredMessages.last.safetyLevel;
        _loadingDraft = false;
      });
      if (migratedDraftEntries || imageMigration.hasChanges) {
        final saved = await _persistConversation();
        await _finishImageMigration(imageMigration, saved: saved);
      }
      _scrollToBottom();
    } catch (error, stackTrace) {
      debugPrint('InneraAiChatPage session load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          if (_messages.isEmpty) _messages.add(_welcomeMessage());
          _loadingDraft = false;
        });
      }
    }
  }

  InneraAiMessage _welcomeMessage() => InneraAiMessage(
        id: 'welcome-${DateTime.now().microsecondsSinceEpoch}',
        role: InneraAiMessageRole.assistant,
        text: _mode.welcomeMessage,
        createdAt: DateTime.now(),
      );

  Future<bool> _persistConversation() async {
    try {
      await _conversationService.saveToday(
        messages: List<InneraAiMessage>.of(_messages),
        mode: _mode,
      );
      return true;
    } catch (error, stackTrace) {
      debugPrint('InneraAiChatPage conversation save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<_AiImageMigration> _migrateLegacyImages(
    List<InneraAiMessage> messages,
  ) async {
    final migrated = <InneraAiMessage>[];
    final oldPaths = <String>[];
    final newPaths = <String>[];
    for (final message in messages) {
      final image = message.image;
      if (image == null || image.isEncrypted) {
        migrated.add(message);
        continue;
      }
      try {
        final encrypted = await _imageService.migrateLegacyAttachment(image);
        migrated.add(message.copyWith(image: encrypted));
        oldPaths.add(image.storagePath);
        newPaths.add(encrypted.storagePath);
      } catch (error, stackTrace) {
        debugPrint('InneraAiChatPage legacy image migration failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        migrated.add(message);
      }
    }
    return _AiImageMigration(
      originalMessages: messages,
      messages: migrated,
      oldPaths: oldPaths,
      newPaths: newPaths,
    );
  }

  Future<void> _finishImageMigration(
    _AiImageMigration migration, {
    required bool saved,
  }) async {
    if (!migration.hasChanges) return;
    if (!saved && mounted) {
      setState(() {
        _messages
          ..clear()
          ..addAll(migration.originalMessages);
      });
    }
    try {
      await _imageService.deleteAll(
        saved ? migration.oldPaths : migration.newPaths,
      );
    } catch (error, stackTrace) {
      debugPrint('InneraAiChatPage image migration cleanup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<bool> _confirmLeave() async {
    final saved = await _persistConversation();
    if (mounted && saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _mode.supportsDailyRecordDraft
                ? '對話與今天的草稿都已保存，可以稍後繼續。'
                : '狀態回顧對話已保存，可以稍後繼續。',
          ),
        ),
      );
    }
    return true;
  }

  Future<void> _resetConversation() async {
    if (_isSending || _isExtractingDiary) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除對話並重新開始？'),
        content: Text(
          _mode.supportsDailyRecordDraft
              ? '這會刪除目前聊天室今天的 AI 對話與今日整理草稿，讓你重新記錄；已加入的每日紀錄與日記會保留。'
              : '這會刪除今天的狀態回顧對話；既有每日紀錄與日記都會保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('刪除並重新開始'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loadingDraft = true);
    final imagePaths = _messages
        .map((message) => message.image?.storagePath)
        .whereType<String>()
        .toList();
    try {
      await _conversationService.resetToday(
        mode: _mode,
        deleteRecordDraft: _mode.supportsDailyRecordDraft,
      );
      final freshDraft = _mode.supportsDailyRecordDraft
          ? InneraAiRecordDraft.empty(DateTime.now())
          : null;
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..add(_welcomeMessage());
        _recordDraft = freshDraft;
        _lastFailedInput = null;
        _lastFailedImage = null;
        _pendingImageBytes = null;
        _pendingImageName = null;
        _activeSafetyLevel = AiSafetyLevel.normal;
        _controller.clear();
        _loadingDraft = false;
      });
      await _persistConversation();
      try {
        await _imageService.deleteAll(imagePaths);
      } catch (error, stackTrace) {
        debugPrint('InneraAiChatPage old image cleanup failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      _scrollToBottom();
    } catch (error, stackTrace) {
      debugPrint('InneraAiChatPage reset failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _loadingDraft = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前無法刪除對話，原對話與草稿仍保留。')),
      );
    }
  }

  Future<void> _showImageSourcePicker() async {
    if (_isSending) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('從相簿選擇'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty ||
          bytes.length > InneraAiChatImageService.maxImageBytes) {
        throw const InneraAiChatImageException('照片大小必須小於 5 MB。');
      }
      if (!mounted) return;
      setState(() {
        _pendingImageBytes = bytes;
        _pendingImageName = picked.name;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is InneraAiChatImageException
                ? error.message
                : '目前無法讀取照片，請重新選擇。',
          ),
        ),
      );
    }
  }

  Future<void> _send({
    String? overrideText,
    InneraAiImageAttachment? overrideImage,
  }) async {
    final enteredText = (overrideText ?? _controller.text).trim();
    final pendingBytes = overrideText == null ? _pendingImageBytes : null;
    final pendingName = overrideText == null ? _pendingImageName : null;
    final hasImage = overrideImage != null || pendingBytes != null;
    if ((enteredText.isEmpty && !hasImage) ||
        enteredText.length > _maxInputLength ||
        _isSending) {
      return;
    }
    final text = enteredText.isEmpty ? '請幫我閱讀並說明這張照片的內容。' : enteredText;

    setState(() {
      _isSending = true;
      _lastFailedInput = null;
      _lastFailedImage = null;
      if (overrideText == null) {
        _controller.clear();
        _pendingImageBytes = null;
        _pendingImageName = null;
      }
    });

    InneraAiImageAttachment? image = overrideImage;
    InneraAiTemporaryImage? temporaryImage;
    var createdPermanentImage = false;
    try {
      if (image == null && pendingBytes != null) {
        image = await _imageService.uploadEncryptedPermanent(
          bytes: pendingBytes,
          fileName: pendingName ?? 'photo.jpg',
        );
        createdPermanentImage = true;
      }
      if (image != null) {
        temporaryImage = pendingBytes != null
            ? await _imageService.uploadTemporaryForAi(
                bytes: pendingBytes,
                fileName: pendingName ?? 'photo.jpg',
              )
            : await _imageService.prepareTemporaryForAi(image);
      }
    } catch (error, stackTrace) {
      debugPrint('InneraAiChatPage image upload failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (createdPermanentImage && image != null) {
        try {
          await _imageService.deleteAll([image.storagePath]);
        } catch (cleanupError, cleanupStackTrace) {
          debugPrint(
            'InneraAiChatPage permanent image rollback failed: $cleanupError',
          );
          debugPrintStack(stackTrace: cleanupStackTrace);
        }
      }
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _pendingImageBytes = pendingBytes;
        _pendingImageName = pendingName;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is InneraAiChatImageException
                ? error.message
                : '照片上傳失敗，請確認網路後再試一次。',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;

    setState(() {
      _messages.add(
        InneraAiMessage(
          id: 'u-${DateTime.now().microsecondsSinceEpoch}',
          role: InneraAiMessageRole.user,
          text: text,
          createdAt: DateTime.now(),
          image: image,
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
    await _persistConversation();

    try {
      final response = await _service
          .sendMessage(
            mode: _mode,
            history: _messages,
            userMessage: text,
            image: temporaryImage,
            recordDraft: _mode.supportsDailyRecordDraft ? _recordDraft : null,
          )
          .timeout(const Duration(seconds: 70));
      if (!mounted) return;
      InneraAiRecordDraft? nextDraftWithFallback;
      if (_mode.supportsDailyRecordDraft) {
        final recordDraftPatch = response.recordDraft == null
            ? null
            : Map<String, dynamic>.from(response.recordDraft!);
        if (_mentionsPreviousDaySleep(text)) {
          // A message about yesterday must not overwrite today's sleep record.
          recordDraftPatch?.remove('sleep');
        }
        final nextDraft =
            (_recordDraft ?? InneraAiRecordDraft.empty(DateTime.now()))
                .mergePatch(recordDraftPatch, rawUserEntry: text);
        nextDraftWithFallback = _mode == InneraAiMode.dailyRecord
            ? nextDraft.mergeExplicitRecordFacts(text)
            : nextDraft;
        await _draftService.save(nextDraftWithFallback);
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
        _recordDraft = nextDraftWithFallback;
        _isSending = false;
      });
      await _persistConversation();
      _scrollToBottom();
    } on FirebaseFunctionsException catch (error) {
      _showSendError(
        text,
        aiCallableErrorMessage(
          error,
          functionName: AiCallableEndpoints.chat,
        ),
        image: image,
      );
    } catch (error, stackTrace) {
      debugPrint('InneraAiChatPage send failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showSendError(text, _messageForError(error), image: image);
    } finally {
      if (temporaryImage != null) {
        try {
          await _imageService.deleteAll([temporaryImage.storagePath]);
        } catch (cleanupError, cleanupStackTrace) {
          debugPrint(
            'InneraAiChatPage temporary image cleanup failed: $cleanupError',
          );
          debugPrintStack(stackTrace: cleanupStackTrace);
        }
      }
    }
  }

  bool _mentionsPreviousDaySleep(String text) {
    return RegExp(r'昨天[^，。！？\n]{0,16}(睡眠|入睡|起床|睡覺)').hasMatch(text) ||
        RegExp(r'(睡眠|入睡|起床|睡覺)[^，。！？\n]{0,16}昨天').hasMatch(text);
  }

  void _showSendError(
    String text,
    String message, {
    InneraAiImageAttachment? image,
  }) {
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((message) => message.isLoading);
      _lastFailedInput = text;
      _lastFailedImage = image;
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

  String _messageForError(Object error) => error is InneraAiException
      ? error.message
      : _mode.supportsDailyRecordDraft
          ? 'AI 服務連線失敗或發生未預期錯誤，請確認網路後再試；目前草稿已保留。'
          : 'AI 服務連線失敗或發生未預期錯誤，請確認網路後再試；狀態回顧對話已保留。';

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
    var workingDraft = draft;
    final confirmedDraft = await showModalBottomSheet<InneraAiRecordDraft>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '今天的紀錄草稿',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text('情緒', style: Theme.of(context).textTheme.titleSmall),
              if (workingDraft.overallMood != null)
                Text('整體情緒：${workingDraft.overallMood} / 5'),
              if (workingDraft.emotions.isEmpty &&
                  workingDraft.overallMood == null)
                const Text('尚未補充'),
              ...workingDraft.emotions.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.timeContext == null
                                      ? item.rawText
                                      : '${item.rawText}（${item.timeContext}）',
                                ),
                                if (item.normalizedDimensionName != null)
                                  Text(
                                    '最接近：${item.normalizedDimensionName}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => setSheetState(() {
                              workingDraft =
                                  workingDraft.withoutEmotion(item.dedupeKey);
                            }),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: '不寫入此情緒',
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DropdownButton<String>(
                            value: item.normalizedDimensionId,
                            hint: const Text('選擇情緒'),
                            items: kEmotionDimensions
                                .map(
                                  (dimension) => DropdownMenuItem(
                                    value: dimension.id,
                                    child: Text(dimension.displayName),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              final dimension = kEmotionDimensionsById[value];
                              if (dimension == null) return;
                              final oldKey = item.dedupeKey;
                              setSheetState(() {
                                workingDraft =
                                    workingDraft.withEmotionDimension(
                                  oldKey,
                                  dimension,
                                );
                              });
                            },
                          ),
                          DropdownButton<int>(
                            value: item.score,
                            hint: const Text('待補分數'),
                            items: List.generate(
                              5,
                              (index) => DropdownMenuItem(
                                value: index + 1,
                                child: Text('${index + 1} / 5'),
                              ),
                            ),
                            onChanged: (value) {
                              if (value == null) return;
                              setSheetState(() {
                                workingDraft = workingDraft.withEmotionScore(
                                  item.dedupeKey,
                                  value,
                                );
                              });
                            },
                          ),
                        ],
                      ),
                      if (item.evidence?.isNotEmpty == true)
                        Text(
                          '依據：${item.evidence}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('症狀', style: Theme.of(context).textTheme.titleSmall),
              Text(workingDraft.symptoms.isEmpty
                  ? '尚未補充'
                  : workingDraft.symptoms.join('、')),
              const SizedBox(height: 14),
              Text('睡眠', style: Theme.of(context).textTheme.titleSmall),
              Text(_sleepPreview(workingDraft)),
              const SizedBox(height: 14),
              Text('生活事件', style: Theme.of(context).textTheme.titleSmall),
              Text(workingDraft.events.isEmpty
                  ? '目前沒有內容'
                  : workingDraft.events.join('\n')),
              const SizedBox(height: 14),
              Text('原始內容', style: Theme.of(context).textTheme.titleSmall),
              Text(workingDraft.rawUserEntries.isEmpty
                  ? '尚未補充'
                  : workingDraft.rawUserEntries.join('\n\n')),
              const SizedBox(height: 14),
              Text('AI 整理', style: Theme.of(context).textTheme.titleSmall),
              Text(workingDraft.diaryText.isEmpty
                  ? '尚未補充'
                  : workingDraft.diaryText),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: workingDraft.emotions.any(
                  (item) => !item.hasValidDimension || item.score == null,
                )
                    ? null
                    : () => Navigator.pop(context, workingDraft),
                child: const Text('儲存草稿'),
              ),
              if (workingDraft.emotions.any(
                (item) => !item.hasValidDimension || item.score == null,
              ))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('請為辨識到的情緒選擇正式維度與 1～5 分，或移除不需寫入的項目。'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('繼續補充'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmedDraft == null || !mounted) return;
    try {
      await _draftService.save(confirmedDraft);
      if (!mounted) return;
      setState(() => _recordDraft = confirmedDraft);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('草稿已儲存，可以繼續補充；尚未加入每日紀錄。'),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('InneraAiChatPage draft score save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('目前無法儲存草稿，尚未開始整理今日紀錄。')),
        );
      }
    }
  }

  Future<void> _extractDiaryDraft({
    InneraAiRecordDraft? structuredDraft,
  }) async {
    if (_isExtractingDiary || _isSending) return;
    final hasUserMessage =
        _messages.any((item) => item.role == InneraAiMessageRole.user);
    if (!hasUserMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先聊聊今天發生的事，再整理成今日紀錄。')),
      );
      return;
    }
    setState(() => _isExtractingDiary = true);
    try {
      var draft = await _diaryDraftService.generate(messages: _messages);
      DiaryDraftConfirmation? confirmation;
      while (mounted) {
        final existing =
            await _diaryDraftService.existingDiary(draft.recordDate);
        if (!mounted) return;
        final result = await showModalBottomSheet<Object>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          builder: (context) => AiDiaryDraftSheet(
            draft: draft,
            existingDiary: existing,
            originalContent: AiDiaryDraftService.originalUserContent(_messages),
          ),
        );
        if (result is DiaryDraftConfirmation) {
          confirmation = result;
          break;
        }
        if (result is String && result.startsWith('regenerate:')) {
          final field = result.substring('regenerate:'.length);
          draft = await _diaryDraftService.generate(
            messages: _messages,
            requestedField: field == 'all' ? null : field,
            currentDraft: draft,
          );
          continue;
        }
        return;
      }
      if (confirmation == null) return;
      await _diaryDraftService.confirm(
        draft: draft,
        confirmation: confirmation,
      );
      final recordDraft = structuredDraft ?? _recordDraft;
      if (recordDraft != null) {
        try {
          await _draftService.confirmAndMerge(
            draft: recordDraft,
            diaryContent: '',
            replaceDiary: false,
          );
        } catch (error, stackTrace) {
          debugPrint(
            'Diary saved but structured daily record merge failed: $error',
          );
          debugPrintStack(stackTrace: stackTrace);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('完整日記已儲存，但情緒／症狀／睡眠暫時無法合併；草稿仍保留可再次確認。'),
            ),
          );
          return;
        }
      }
      if (!mounted) return;
      if (recordDraft != null) {
        setState(
          () => _recordDraft = recordDraft.copyWith(confirmed: true),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已儲存完整今日紀錄，並合併情緒、症狀與睡眠。')),
      );
    } on FirebaseFunctionsException catch (error, stackTrace) {
      logAiCallableFailure(
        functionName: AiCallableEndpoints.diaryDraft,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              aiCallableErrorMessage(
                error,
                functionName: AiCallableEndpoints.diaryDraft,
              ),
            ),
          ),
        );
      }
    } on TimeoutException catch (error, stackTrace) {
      debugPrint(
        'AI callable timed out: '
        'projectId=${Firebase.app().options.projectId}, '
        'function=${AiCallableEndpoints.diaryDraft}, '
        'region=${AiCallableEndpoints.region}, error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 日記整理回應逾時，請稍後再試；原對話與目前草稿均已保留。')),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Diary extraction failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('目前無法整理日記草稿，原對話與既有紀錄都不會被更動。')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExtractingDiary = false);
    }
  }

  String _sleepPreview(InneraAiRecordDraft draft) {
    final sleep = draft.sleep;
    final details = <String>[];
    if (sleep.sleepTime != null) details.add('${sleep.sleepTime} 入睡');
    if (sleep.finalWakeTime != null) {
      details.add('${sleep.finalWakeTime} 甦醒');
    }
    if (sleep.wakeTime != null) details.add('${sleep.wakeTime} 起床／離床');
    if (sleep.quality != null) details.add('品質 ${sleep.quality} / 5');
    if (sleep.midWakeList != null) details.add('中途醒來：${sleep.midWakeList}');
    details.addAll(
      sleep.flags.map(
        (flag) => '睡眠狀況：${_sleepFlagLabels[flag] ?? flag}',
      ),
    );
    return details.isEmpty ? '尚未補充' : details.join('\n');
  }

  static const _sleepFlagLabels = <String, String>{
    'good': '優',
    'ok': '良好',
    'earlyWake': '早醒',
    'dreams': '多夢／惡夢',
    'lightSleep': '淺眠',
    'fragmented': '睡睡醒醒',
    'insufficient': '睡眠不足',
    'initInsomnia': '入睡困難',
    'interrupted': '睡眠中斷',
    'nocturia': '夜尿',
  };

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
    await _persistConversation();
    if (!mounted) return;
    setState(() {
      _mode = selected;
      _loadingDraft = true;
      _activeSafetyLevel = AiSafetyLevel.normal;
    });
    try {
      final conversation = await _conversationService.loadToday(mode: selected);
      final draft = selected.supportsDailyRecordDraft
          ? await _draftService.loadOrCreateToday()
          : null;
      final imageMigration = await _migrateLegacyImages(
        conversation?.messages ?? const <InneraAiMessage>[],
      );
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(
            imageMigration.messages.isEmpty
                ? [_welcomeMessage()]
                : imageMigration.messages,
          );
        _recordDraft = draft;
        _activeSafetyLevel = _messages.last.safetyLevel;
        _loadingDraft = false;
      });
      if (imageMigration.hasChanges) {
        final saved = await _persistConversation();
        await _finishImageMigration(imageMigration, saved: saved);
      }
    } catch (error, stackTrace) {
      debugPrint('InneraAiChatPage mode conversation load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..add(_welcomeMessage());
        _loadingDraft = false;
      });
    }
    await _persistConversation();
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
          actions: [
            IconButton(
              onPressed: _isSending || _isExtractingDiary || _loadingDraft
                  ? null
                  : _resetConversation,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: '刪除對話並重新開始',
            ),
          ],
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
                  unawaited(_persistConversation());
                  _scrollToBottom();
                },
              ),
              if (_mode.supportsDailyRecordDraft &&
                  !_loadingDraft &&
                  _recordDraft != null)
                AiRecordDraftCard(
                  draft: _recordDraft!,
                  onPreview: _showDraftPreview,
                  onExtractDiary: _extractDiaryDraft,
                  isExtractingDiary: _isExtractingDiary,
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
                      userPhotoUrl: FirebaseAuth.instance.currentUser?.photoURL,
                      onRetry: _lastFailedInput == null
                          ? null
                          : () {
                              setState(() {
                                _messages.removeWhere((item) => item.isError);
                              });
                              _send(
                                overrideText: _lastFailedInput,
                                overrideImage: _lastFailedImage,
                              );
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
                pendingImageBytes: _pendingImageBytes,
                maxLength: _maxInputLength,
                onSend: () => _send(),
                onPickImage: _showImageSourcePicker,
                onRemoveImage: () {
                  setState(() {
                    _pendingImageBytes = null;
                    _pendingImageName = null;
                  });
                },
              ),
              if (_shouldShowScoreShortcuts())
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
    required this.pendingImageBytes,
    required this.maxLength,
    required this.onSend,
    required this.onPickImage,
    required this.onRemoveImage,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final InneraAiMode mode;
  final bool isSending;
  final Uint8List? pendingImageBytes;
  final int maxLength;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;

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
            IconButton(
              onPressed: isSending ? null : onPickImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              tooltip: '加入照片',
            ),
            if (pendingImageBytes != null) ...[
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      pendingImageBytes!,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: -10,
                    right: -10,
                    child: IconButton.filled(
                      visualDensity: VisualDensity.compact,
                      onPressed: isSending ? null : onRemoveImage,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      tooltip: '移除照片',
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
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
                final canSend = (value.text.trim().isNotEmpty ||
                        pendingImageBytes != null) &&
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
