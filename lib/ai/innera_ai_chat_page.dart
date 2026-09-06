import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../analytics_service.dart';
import '../constants/healing_design_system.dart';
import '../daily/daily_state_dimensions.dart';
import '../daily/body_measurement_input.dart';
import '../daily/emotion_dimensions.dart';
import '../models/daily_record.dart';
import 'ai_callable_diagnostics.dart';
import 'ai_request_id.dart';
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
import 'widgets/ai_free_quota_banner.dart';
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
  int _quotaRevision = 0;
  String? _sendRequestId;
  String? _lastFailedInput;
  List<InneraAiImageAttachment> _lastFailedImages = const [];
  final List<Uint8List> _pendingImageBytes = [];
  final List<String> _pendingImageNames = [];
  AiSafetyLevel _activeSafetyLevel = AiSafetyLevel.normal;
  bool _hasLoggedTaskStart = false;
  final _draftService = InneraAiRecordDraftService();
  final _conversationService = InneraAiConversationService();
  final _imageService = InneraAiChatImageService();
  final _imagePicker = ImagePicker();
  final _safetyService = InneraAiSafetyService();
  InneraAiRecordDraft? _recordDraft;
  bool _loadingDraft = false;
  bool _isExtractingDiary = false;
  final _diaryDraftService = AiDiaryDraftService();

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _service = widget._service ?? InneraAiService();
    AnalyticsService.logAiFeatureOpen(aiMode: _mode.analyticsMode);
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
      final images = message.allImages;
      if (images.isEmpty || images.every((image) => image.isEncrypted)) {
        migrated.add(message);
        continue;
      }
      try {
        final encryptedImages = <InneraAiImageAttachment>[];
        for (final image in images) {
          final encrypted = image.isEncrypted
              ? image
              : await _imageService.migrateLegacyAttachment(image);
          encryptedImages.add(encrypted);
          if (!image.isEncrypted) {
            oldPaths.add(image.storagePath);
            newPaths.add(encrypted.storagePath);
          }
        }
        migrated.add(
          message.copyWith(
            image: message.image == null ? null : encryptedImages.first,
            images: encryptedImages,
          ),
        );
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
    _draftPreparationVersion++;
    setState(() => _loadingDraft = true);
    final imagePaths = _messages
        .expand((message) => message.allImages)
        .map((image) => image.storagePath)
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
        _lastFailedImages = const [];
        _pendingImageBytes.clear();
        _pendingImageNames.clear();
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
      final remaining = 10 - _pendingImageBytes.length;
      if (remaining <= 0) {
        throw const InneraAiChatImageException('每次最多選擇 10 張照片。');
      }
      final picked = source == ImageSource.gallery
          ? await _imagePicker.pickMultiImage(
              maxWidth: 1600,
              maxHeight: 1600,
              imageQuality: 82,
              limit: remaining,
            )
          : [
              if (await _imagePicker.pickImage(
                source: ImageSource.camera,
                maxWidth: 1600,
                maxHeight: 1600,
                imageQuality: 82,
              )
                  case final photo?)
                photo,
            ];
      if (picked.isEmpty) return;
      final newBytes = <Uint8List>[];
      final newNames = <String>[];
      for (final photo in picked.take(remaining)) {
        final bytes = await photo.readAsBytes();
        if (bytes.isEmpty ||
            bytes.length > InneraAiChatImageService.maxImageBytes) {
          throw const InneraAiChatImageException('每張照片大小必須小於 5 MB。');
        }
        newBytes.add(bytes);
        newNames.add(photo.name);
      }
      if (!mounted) return;
      setState(() {
        _pendingImageBytes.addAll(newBytes);
        _pendingImageNames.addAll(newNames);
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
    List<InneraAiImageAttachment> overrideImages = const [],
  }) async {
    final enteredText = (overrideText ?? _controller.text).trim();
    final pendingBytes = overrideText == null
        ? List<Uint8List>.of(_pendingImageBytes)
        : const <Uint8List>[];
    final pendingNames = overrideText == null
        ? List<String>.of(_pendingImageNames)
        : const <String>[];
    final hasImage = overrideImages.isNotEmpty || pendingBytes.isNotEmpty;
    if ((enteredText.isEmpty && !hasImage) ||
        enteredText.length > _maxInputLength ||
        _isSending) {
      return;
    }
    final text = enteredText.isEmpty ? '請幫我閱讀並說明這張照片的內容。' : enteredText;
    // The retry button reuses the original ID, including after a network timeout.
    if (overrideText == null || _sendRequestId == null) {
      _sendRequestId = createAiRequestId();
    }

    final localSafety = _safetyService.assess(text);
    if (localSafety.level == AiSafetyLevel.normal) {
      final intendedMode = resolveInneraAiModeIntent(
        activeMode: _mode,
        message: text,
      );
      if (intendedMode != _mode) {
        _setActiveMode(intendedMode);
      }
    }

    setState(() {
      _isSending = true;
      _draftPreparationVersion++;
      _lastFailedInput = null;
      _lastFailedImages = const [];
      if (overrideText == null) {
        _controller.clear();
        _pendingImageBytes.clear();
        _pendingImageNames.clear();
      }
    });

    final images = <InneraAiImageAttachment>[...overrideImages];
    final temporaryImages = <InneraAiTemporaryImage>[];
    final createdPermanentPaths = <String>[];
    try {
      for (var index = 0; index < pendingBytes.length; index++) {
        final image = await _imageService.uploadEncryptedPermanent(
          bytes: pendingBytes[index],
          fileName: pendingNames[index],
        );
        images.add(image);
        createdPermanentPaths.add(image.storagePath);
      }
      for (var index = 0; index < images.length; index++) {
        temporaryImages.add(index < pendingBytes.length
            ? await _imageService.uploadTemporaryForAi(
                bytes: pendingBytes[index],
                fileName: pendingNames[index],
              )
            : await _imageService.prepareTemporaryForAi(images[index]));
      }
    } catch (error, stackTrace) {
      debugPrint('InneraAiChatPage image upload failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (createdPermanentPaths.isNotEmpty) {
        try {
          await _imageService.deleteAll(createdPermanentPaths);
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
        _pendingImageBytes
          ..clear()
          ..addAll(pendingBytes);
        _pendingImageNames
          ..clear()
          ..addAll(pendingNames);
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
          images: images,
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
      if (!_hasLoggedTaskStart) {
        _hasLoggedTaskStart = true;
        unawaited(
          AnalyticsService.logAiTaskStart(aiMode: _mode.analyticsMode),
        );
      }
      final response = await _service
          .sendMessage(
            requestId: _sendRequestId,
            mode: _mode,
            history: _messages,
            userMessage: text,
            images: temporaryImages,
            recordDraft: _mode.supportsDailyRecordDraft ? _recordDraft : null,
          )
          .timeout(const Duration(seconds: 70));
      if (!mounted) return;
      // Fixed safety UI must not replace an existing pending draft with null.
      InneraAiRecordDraft? nextDraftWithFallback = _recordDraft;
      if (_mode.supportsDailyRecordDraft && !response.requiresFixedSafetyUi) {
        Map<String, dynamic>? recordDraftPatch = response.recordDraft == null
            ? null
            : Map<String, dynamic>.from(response.recordDraft!);
        if (response.eventDrafts.isNotEmpty) {
          recordDraftPatch ??= <String, dynamic>{};
          recordDraftPatch['eventDrafts'] = response.eventDrafts;
        }
        if (_mentionsPreviousDaySleep(text)) {
          // A message about yesterday must not overwrite today's sleep record.
          recordDraftPatch?.remove('sleep');
        }
        final nextDraft =
            (_recordDraft ?? InneraAiRecordDraft.empty(DateTime.now()))
                .mergePatch(recordDraftPatch, rawUserEntry: text);
        nextDraftWithFallback = (_mode == InneraAiMode.dailyRecord
                ? nextDraft.mergeExplicitRecordFacts(text)
                : nextDraft)
            .mergeExplicitHealthEventFacts(
          text,
          DateTime.now(),
          allowPhysicalContinuation: _mode == InneraAiMode.physicalHealth,
        );
      }
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((message) => message.isLoading);
        _activeSafetyLevel = response.safetyLevel;
        if (response.requiresFixedSafetyUi) {
          final userMessageIndex = _messages.lastIndexWhere(
            (message) => message.role == InneraAiMessageRole.user,
          );
          if (userMessageIndex >= 0) {
            _messages[userMessageIndex] = _messages[userMessageIndex].copyWith(
              safetyLevel: response.safetyLevel,
            );
          }
        }
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
      if (_mode.supportsDailyRecordDraft && !response.requiresFixedSafetyUi) {
        unawaited(_prepareDraftSummary(nextDraftWithFallback!));
      }
      unawaited(
        AnalyticsService.logAiTaskComplete(aiMode: _mode.analyticsMode),
      );
      await _persistConversation();
      _scrollToBottom();
    } on FirebaseFunctionsException catch (error) {
      if (!_hasLoggedTaskStart) {
        _hasLoggedTaskStart = true;
        unawaited(
          AnalyticsService.logAiTaskStart(aiMode: _mode.analyticsMode),
        );
      }
      unawaited(
        AnalyticsService.logAiTaskError(
          aiMode: _mode.analyticsMode,
          errorType: mapAiErrorType(error),
        ),
      );
      _showSendError(
        text,
        aiCallableErrorMessage(
          error,
          functionName: AiCallableEndpoints.chat,
          isSignedIn: FirebaseAuth.instance.currentUser != null,
        ),
        images: images,
      );
    } catch (error, stackTrace) {
      if (!_hasLoggedTaskStart) {
        _hasLoggedTaskStart = true;
        unawaited(
          AnalyticsService.logAiTaskStart(aiMode: _mode.analyticsMode),
        );
      }
      unawaited(
        AnalyticsService.logAiTaskError(
          aiMode: _mode.analyticsMode,
          errorType: mapAiErrorType(error),
        ),
      );
      debugPrint('InneraAiChatPage send failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showSendError(text, _messageForError(error), images: images);
    } finally {
      if (mounted) setState(() => _quotaRevision++);
      if (temporaryImages.isNotEmpty) {
        try {
          await _imageService.deleteAll(
            temporaryImages.map((image) => image.storagePath),
          );
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
    List<InneraAiImageAttachment> images = const [],
  }) {
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((message) => message.isLoading);
      _lastFailedInput = text;
      _lastFailedImages = images;
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

  bool _draftPreviewOpen = false;
  int _draftPreparationVersion = 0;

  Future<void> _prepareDraftSummary(InneraAiRecordDraft draft) async {
    final version = ++_draftPreparationVersion;
    final messages = List<InneraAiMessage>.of(_messages);
    try {
      await _draftService.save(draft);
      if (!mounted ||
          _isSending ||
          version != _draftPreparationVersion ||
          !identical(_recordDraft, draft) ||
          _draftPreviewOpen) {
        return;
      }
      if (draft.eventDrafts.isEmpty) return;
      final summarized = await _service.summarizeHealthEvents(
        messages: messages,
        draft: draft,
      );
      // A newer turn or an open editor owns its draft; discard stale summaries.
      if (!mounted ||
          _isSending ||
          version != _draftPreparationVersion ||
          !identical(_recordDraft, draft) ||
          _draftPreviewOpen) {
        return;
      }
      setState(() => _recordDraft = summarized);
      await _draftService.save(summarized);
    } catch (error, stackTrace) {
      // The response draft is already usable, including when offline.
      debugPrint('Innera draft preparation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _showDraftPreview() async {
    final draft = _recordDraft;
    if (draft == null || _draftPreviewOpen) return;
    // Opening an editor invalidates pending summaries even after it is closed.
    _draftPreparationVersion++;
    _draftPreviewOpen = true;
    var workingDraft = draft;
    final bodyInputValidity = <String, bool>{
      'weightKg': true,
      'bodyFatPercent': true,
      'waistCm': true,
    };
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
              if (workingDraft.eventDrafts.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '將建立 ${workingDraft.eventDrafts.length} 筆事件紀錄',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ...workingDraft.eventDrafts.map(
                  (event) => Card(
                    color: HealingDesignSystem.adaptiveSurface(context),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.timeLabel,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (event.emotions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              '情緒',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            ...event.emotions.map(
                              (emotion) => Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        value: emotion.normalizedDimensionId,
                                        hint: Text(
                                          emotion.rawText.isEmpty
                                              ? '選擇情緒'
                                              : emotion.rawText,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        items: kEmotionDimensions
                                            .map(
                                              (dimension) => DropdownMenuItem(
                                                value: dimension.id,
                                                child: Text(
                                                  dimension.displayName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (value) {
                                          final dimension =
                                              kEmotionDimensionsById[value];
                                          if (dimension == null) return;
                                          final oldKey = emotion.dedupeKey;
                                          setSheetState(() {
                                            workingDraft = workingDraft
                                                .withEventEmotionDimension(
                                              event.id,
                                              oldKey,
                                              dimension,
                                            );
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    DropdownButton<int>(
                                      value: emotion.score,
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
                                          workingDraft = workingDraft
                                              .withEventEmotionScore(
                                            event.id,
                                            emotion.dedupeKey,
                                            value,
                                          );
                                        });
                                      },
                                    ),
                                    IconButton(
                                      tooltip: '不寫入此情緒',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.close_rounded),
                                      onPressed: () => setSheetState(() {
                                        workingDraft =
                                            workingDraft.withoutEventEmotion(
                                          event.id,
                                          emotion.dedupeKey,
                                        );
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (event.symptoms.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              '症狀',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            ...event.symptoms.map((symptom) {
                              final severity = event.symptomSeverities[symptom];
                              return Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      symptom,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownButton<int>(
                                    value: severity,
                                    hint: const Text('待補分數'),
                                    items: List.generate(
                                      5,
                                      (index) => DropdownMenuItem(
                                        value: index + 1,
                                        child: Text('${index + 1} / 5'),
                                      ),
                                    ),
                                    onChanged: (value) => setSheetState(() {
                                      workingDraft =
                                          workingDraft.withEventSymptomSeverity(
                                        event.id,
                                        symptom,
                                        value,
                                      );
                                    }),
                                  ),
                                  IconButton(
                                    tooltip: severity == null
                                        ? '$symptom尚無分數'
                                        : '清除$symptom分數',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: severity == null
                                        ? null
                                        : () => setSheetState(() {
                                              workingDraft = workingDraft
                                                  .withEventSymptomSeverity(
                                                event.id,
                                                symptom,
                                                null,
                                              );
                                            }),
                                  ),
                                ],
                              );
                            }),
                          ],
                          if (event.stateChanges.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              '狀態變化',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            ...kDailyStateDimensions
                                .where(
                              (dimension) =>
                                  event.stateChanges.containsKey(dimension.id),
                            )
                                .map((dimension) {
                              final value = event.stateChanges[dimension.id]!;
                              return Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      dimension.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownButton<int>(
                                    value: value,
                                    items: List.generate(
                                      5,
                                      (index) => DropdownMenuItem(
                                        value: index + 1,
                                        child: Text('${index + 1} / 5'),
                                      ),
                                    ),
                                    onChanged: (next) {
                                      if (next == null) return;
                                      setSheetState(() {
                                        workingDraft =
                                            workingDraft.withEventStateChange(
                                          event.id,
                                          dimension.id,
                                          next,
                                        );
                                      });
                                    },
                                  ),
                                  IconButton(
                                    tooltip: '清除${dimension.displayName}',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () => setSheetState(() {
                                      workingDraft =
                                          workingDraft.withEventStateChange(
                                        event.id,
                                        dimension.id,
                                        null,
                                      );
                                    }),
                                  ),
                                ],
                              );
                            }),
                          ],
                          const SizedBox(height: 4),
                          TextFormField(
                            key: ValueKey('event-summary-${event.id}'),
                            initialValue: event.note,
                            minLines: 2,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: 'AI 整理',
                              alignLabelWithHint: true,
                            ),
                            onChanged: (value) => workingDraft =
                                workingDraft.withEventSummary(event.id, value),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (workingDraft.eventDrafts.isEmpty) ...[
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
                Text('狀態變化', style: Theme.of(context).textTheme.titleSmall),
                ...kDailyStateDimensions.map((dimension) {
                  final value = workingDraft.stateChanges[dimension.id];
                  return Row(
                    children: [
                      Expanded(child: Text(dimension.displayName)),
                      DropdownButton<int>(
                        value: value,
                        hint: const Text('尚未填寫'),
                        items: List.generate(
                          5,
                          (index) => DropdownMenuItem(
                            value: index + 1,
                            child: Text(
                              '${index + 1}｜${dailyStateValueLabel(dimension, index + 1)}',
                            ),
                          ),
                        ),
                        onChanged: (next) => setSheetState(() {
                          workingDraft =
                              workingDraft.withStateChange(dimension.id, next);
                        }),
                      ),
                      if (value != null)
                        IconButton(
                          tooltip: '清除${dimension.displayName}',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setSheetState(() {
                            workingDraft = workingDraft.withStateChange(
                              dimension.id,
                              null,
                            );
                          }),
                        ),
                    ],
                  );
                }),
              ],
              const SizedBox(height: 14),
              Text('身體組成', style: Theme.of(context).textTheme.titleSmall),
              Row(
                children: [
                  Expanded(
                    child: _draftMeasurementField(
                      fieldKey: 'weightKg',
                      label: '體重',
                      suffix: 'kg',
                      value: workingDraft.bodyMeasurement?.weightKg,
                      min: 20,
                      max: 300,
                      onChanged: (value) {
                        final current = workingDraft.bodyMeasurement ??
                            const BodyMeasurement();
                        workingDraft = workingDraft.withBodyMeasurement(
                          BodyMeasurement(
                            weightKg: value,
                            bodyFatPercent: current.bodyFatPercent,
                            waistCm: current.waistCm,
                            measuredAt: current.measuredAt,
                            measurementTiming: current.measurementTiming,
                            customMeasurementTime:
                                current.customMeasurementTime,
                          ),
                        );
                      },
                      onValidityChanged: (valid) => setSheetState(
                        () => bodyInputValidity['weightKg'] = valid,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _draftMeasurementField(
                      fieldKey: 'bodyFatPercent',
                      label: '體脂率',
                      suffix: '%',
                      value: workingDraft.bodyMeasurement?.bodyFatPercent,
                      min: 1,
                      max: 70,
                      onChanged: (value) {
                        final current = workingDraft.bodyMeasurement ??
                            const BodyMeasurement();
                        workingDraft = workingDraft.withBodyMeasurement(
                          BodyMeasurement(
                            weightKg: current.weightKg,
                            bodyFatPercent: value,
                            waistCm: current.waistCm,
                            measuredAt: current.measuredAt,
                            measurementTiming: current.measurementTiming,
                            customMeasurementTime:
                                current.customMeasurementTime,
                          ),
                        );
                      },
                      onValidityChanged: (valid) => setSheetState(
                        () => bodyInputValidity['bodyFatPercent'] = valid,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _draftMeasurementField(
                      fieldKey: 'waistCm',
                      label: '腰圍',
                      suffix: 'cm',
                      value: workingDraft.bodyMeasurement?.waistCm,
                      min: 30,
                      max: 250,
                      onChanged: (value) {
                        final current = workingDraft.bodyMeasurement ??
                            const BodyMeasurement();
                        workingDraft = workingDraft.withBodyMeasurement(
                          BodyMeasurement(
                            weightKg: current.weightKg,
                            bodyFatPercent: current.bodyFatPercent,
                            waistCm: value,
                            measuredAt: current.measuredAt,
                            measurementTiming: current.measurementTiming,
                            customMeasurementTime:
                                current.customMeasurementTime,
                          ),
                        );
                      },
                      onValidityChanged: (valid) => setSheetState(
                        () => bodyInputValidity['waistCm'] = valid,
                      ),
                    ),
                  ),
                  if (_hasBodyMeasurementValues(workingDraft) &&
                      workingDraft.bodyMeasurement?.measurementTiming !=
                          null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<MeasurementTiming>(
                        initialValue:
                            workingDraft.bodyMeasurement?.measurementTiming,
                        decoration: const InputDecoration(labelText: '測量時機'),
                        items: MeasurementTiming.values
                            .map(
                              (timing) => DropdownMenuItem(
                                value: timing,
                                child: Text(timing.displayName),
                              ),
                            )
                            .toList(),
                        onChanged: (timing) {
                          final current = workingDraft.bodyMeasurement ??
                              const BodyMeasurement();
                          setSheetState(() {
                            workingDraft = workingDraft.withBodyMeasurement(
                              BodyMeasurement(
                                weightKg: current.weightKg,
                                bodyFatPercent: current.bodyFatPercent,
                                waistCm: current.waistCm,
                                measuredAt: current.measuredAt,
                                measurementTiming: timing,
                                customMeasurementTime:
                                    timing == MeasurementTiming.other
                                        ? current.customMeasurementTime
                                        : null,
                              ),
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ],
              ),
              if (_hasBodyMeasurementValues(workingDraft) &&
                  workingDraft.bodyMeasurement?.measurementTiming ==
                      MeasurementTiming.other) ...[
                const SizedBox(height: 10),
                TextFormField(
                  key: const ValueKey('draft-custom-measurement-time'),
                  initialValue: workingDraft
                          .bodyMeasurement?.effectiveCustomMeasurementTime ??
                      '',
                  decoration: const InputDecoration(
                    labelText: '自訂測量時間',
                    hintText: '例如：運動後、下午三點',
                  ),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) =>
                      value?.trim().isEmpty == false ? null : '選擇其他時間時請填寫',
                  onChanged: (value) {
                    final current =
                        workingDraft.bodyMeasurement ?? const BodyMeasurement();
                    workingDraft = workingDraft.withBodyMeasurement(
                      BodyMeasurement(
                        weightKg: current.weightKg,
                        bodyFatPercent: current.bodyFatPercent,
                        waistCm: current.waistCm,
                        measuredAt: current.measuredAt,
                        measurementTiming: MeasurementTiming.other,
                        customMeasurementTime: value.trim(),
                      ),
                    );
                    setSheetState(() {});
                  },
                ),
              ],
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
              Text('日記草稿', style: Theme.of(context).textTheme.titleSmall),
              Text(workingDraft.diaryText.isEmpty
                  ? '尚未補充'
                  : workingDraft.diaryText),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _hasInvalidConfirmableEmotion(workingDraft) ||
                        bodyInputValidity.values.any((valid) => !valid) ||
                        workingDraft.bodyMeasurement?.isValid == false
                    ? null
                    : () => Navigator.pop(context, workingDraft),
                child: Text(
                  workingDraft.eventDrafts.isEmpty
                      ? '儲存草稿'
                      : '確認並建立 ${workingDraft.eventDrafts.length} 筆事件紀錄',
                ),
              ),
              if (_hasInvalidConfirmableEmotion(workingDraft))
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
    _draftPreviewOpen = false;
    if (confirmedDraft == null || !mounted) return;
    try {
      if (confirmedDraft.eventDrafts.isEmpty) {
        await _draftService.save(confirmedDraft);
      } else {
        await _draftService.confirmAndMerge(
          draft: confirmedDraft,
          diaryContent: confirmedDraft.diaryText,
          replaceDiary: false,
        );
      }
      if (!mounted) return;
      setState(() => _recordDraft = confirmedDraft.copyWith(
            confirmed: confirmedDraft.eventDrafts.isNotEmpty,
          ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            confirmedDraft.eventDrafts.isEmpty
                ? '草稿已儲存，可以繼續補充；尚未加入每日紀錄。'
                : '已建立 ${confirmedDraft.eventDrafts.length} 筆事件紀錄。',
          ),
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
      unawaited(
        AnalyticsService.logAiTaskStart(aiMode: _mode.analyticsMode),
      );
      var draft = await _diaryDraftService.generate(messages: _messages);
      unawaited(
        AnalyticsService.logAiTaskComplete(aiMode: _mode.analyticsMode),
      );
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
          unawaited(
            AnalyticsService.logAiTaskStart(aiMode: _mode.analyticsMode),
          );
          draft = await _diaryDraftService.generate(
            messages: _messages,
            requestedField: field == 'all' ? null : field,
            currentDraft: draft,
          );
          unawaited(
            AnalyticsService.logAiTaskComplete(aiMode: _mode.analyticsMode),
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
      unawaited(
        AnalyticsService.logAiTaskError(
          aiMode: _mode.analyticsMode,
          errorType: mapAiErrorType(error),
        ),
      );
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
      unawaited(
        AnalyticsService.logAiTaskError(
          aiMode: _mode.analyticsMode,
          errorType: 'timeout',
        ),
      );
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
      unawaited(
        AnalyticsService.logAiTaskError(
          aiMode: _mode.analyticsMode,
          errorType: mapAiErrorType(error),
        ),
      );
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

  Widget _draftMeasurementField({
    required String fieldKey,
    required String label,
    required String suffix,
    required double? value,
    required double min,
    required double max,
    required ValueChanged<double?> onChanged,
    required ValueChanged<bool> onValidityChanged,
  }) {
    return TextFormField(
      key: ValueKey('draft-measurement-$fieldKey'),
      initialValue: formatBodyMeasurementNumber(value),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [OneDecimalTextInputFormatter()],
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (raw) => validateBodyMeasurementNumber(
        raw,
        min: min,
        max: max,
        unit: suffix,
      ),
      onChanged: (raw) {
        final text = raw.trim();
        if (text.isEmpty) {
          onValidityChanged(true);
          onChanged(null);
          return;
        }
        final parsed = parseBodyMeasurementNumber(text);
        if (parsed != null && parsed >= min && parsed <= max) {
          onValidityChanged(true);
          onChanged(parsed);
        } else {
          onValidityChanged(false);
        }
      },
    );
  }

  bool _hasInvalidConfirmableEmotion(InneraAiRecordDraft draft) {
    final emotions = draft.eventDrafts.isEmpty
        ? draft.emotions
        : draft.eventDrafts.expand((event) => event.emotions);
    return emotions.any(
      (item) => !item.hasValidDimension || item.score == null,
    );
  }

  bool _hasBodyMeasurementValues(InneraAiRecordDraft draft) {
    final measurement = draft.bodyMeasurement;
    return measurement?.weightKg != null ||
        measurement?.bodyFatPercent != null ||
        measurement?.waistCm != null;
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
    _setActiveMode(selected);
  }

  void _setActiveMode(InneraAiMode nextMode) {
    if (!mounted || nextMode == _mode) return;
    setState(() {
      _mode = nextMode;
      _hasLoggedTaskStart = false;
    });
    unawaited(_persistConversation());
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
        backgroundColor: HealingDesignSystem.adaptiveBackground(context),
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor:
              HealingDesignSystem.adaptiveAppBarBackground(context),
          foregroundColor:
              HealingDesignSystem.adaptiveAppBarForeground(context),
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  HealingDesignSystem.adaptiveAppBarForeground(
                                      context),
                            ),
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
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
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
                    if (_mode.showsRecordDraftCard &&
                        !_loadingDraft &&
                        _recordDraft != null)
                      AiRecordDraftCard(
                        draft: _recordDraft!,
                        onPreview: _showDraftPreview,
                        onExtractDiary: _extractDiaryDraft,
                        isExtractingDiary: _isExtractingDiary,
                      ),
                    ..._messages.map(
                      (message) => AiMessageBubble(
                        message: message,
                        userPhotoUrl:
                            FirebaseAuth.instance.currentUser?.photoURL,
                        onRetry: _lastFailedInput == null
                            ? null
                            : () {
                                setState(() {
                                  _messages.removeWhere((item) => item.isError);
                                });
                                _send(
                                  overrideText: _lastFailedInput,
                                  overrideImages: _lastFailedImages,
                                );
                              },
                      ),
                    ),
                  ],
                ),
              ),
              AiFreeQuotaBanner(mode: _mode, revision: _quotaRevision),
              _InputBar(
                controller: _controller,
                focusNode: _focusNode,
                mode: _mode,
                isSending: _isSending,
                pendingImageBytes: _pendingImageBytes,
                maxLength: _maxInputLength,
                onSend: () => _send(),
                onPickImage: _showImageSourcePicker,
                onRemoveImage: (index) {
                  setState(() {
                    _pendingImageBytes.removeAt(index);
                    _pendingImageNames.removeAt(index);
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
  final List<Uint8List> pendingImageBytes;
  final int maxLength;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final ValueChanged<int> onRemoveImage;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pendingImageBytes.isNotEmpty) ...[
              SizedBox(
                height: 66,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: pendingImageBytes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          pendingImageBytes[index],
                          width: 58,
                          height: 58,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton.filled(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed:
                              isSending ? null : () => onRemoveImage(index),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          tooltip: '移除照片',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: isSending || pendingImageBytes.length >= 10
                      ? null
                      : onPickImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  tooltip: pendingImageBytes.length >= 10
                      ? '每次最多 10 張照片'
                      : '加入照片（最多 10 張）',
                ),
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
                            pendingImageBytes.isNotEmpty) &&
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
          ],
        ),
      ),
    );
  }
}
