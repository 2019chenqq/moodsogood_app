import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../diary/diary_repository.dart';
import 'ai_callable_diagnostics.dart';
import 'ai_diary_draft.dart';
import 'ai_request_id.dart';
import 'diary_extraction_prompt.dart';
import 'emotion_metaphor_library.dart';
import 'innera_ai_message.dart';

enum DiaryFieldMerge { keepExisting, replace, append }

class InneraSongSearchException implements Exception {
  const InneraSongSearchException(this.code);

  final String code;

  String get userMessage => switch (code) {
        'music_service_not_configured' => 'Spotify 搜尋服務尚未完成設定，請稍後再試。',
        'rate_limit' => 'Spotify 搜尋次數暫時達到上限，請稍後再試。',
        _ => 'Spotify 搜尋服務目前無法連線，請稍後再試。',
      };
}

class DiaryDraftConfirmation {
  const DiaryDraftConfirmation({
    required this.values,
    required this.includedFields,
    required this.mergeChoices,
    this.userEditedFields = const <String>{},
    this.selectedSong,
  });

  final Map<String, String> values;
  final Set<String> includedFields;
  final Map<String, DiaryFieldMerge> mergeChoices;
  final Set<String> userEditedFields;
  final VerifiedSongRecommendation? selectedSong;
}

class AiDiaryDraftService {
  AiDiaryDraftService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    DiaryRepository? diaryRepository,
  })  : _functions = functions ??
            FirebaseFunctions.instanceFor(region: AiCallableEndpoints.region),
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _diaryRepository = diaryRepository ?? DiaryRepository();

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final DiaryRepository _diaryRepository;

  static String originalUserContent(List<InneraAiMessage> messages) => messages
      .where(
        (item) =>
            item.role == InneraAiMessageRole.user &&
            !item.isLoading &&
            !item.isError,
      )
      .map((item) => item.text.trim())
      .where((text) => text.isNotEmpty)
      .join('\n\n');

  static String combineSuggestionValues(
    Iterable<DiaryDraftSuggestion> suggestions,
  ) =>
      suggestions
          .map((item) => item.value.trim())
          .where((value) => value.isNotEmpty)
          .join('\n');

  Future<AiDiaryDraft> generate({
    required List<InneraAiMessage> messages,
    String? requestedField,
    AiDiaryDraft? currentDraft,
  }) async {
    final conversation = messages
        .where((item) => !item.isLoading && !item.isError)
        .where((item) =>
            item.role == InneraAiMessageRole.user ||
            item.role == InneraAiMessageRole.assistant)
        .skip(messages.length > 24 ? messages.length - 24 : 0)
        .map((item) => {
              'role':
                  item.role == InneraAiMessageRole.user ? 'user' : 'assistant',
              'content': item.text,
            })
        .toList();
    if (!conversation.any((item) => item['role'] == 'user')) {
      throw const FormatException('沒有可整理的使用者對話');
    }

    final result =
        await _functions.httpsCallable(AiCallableEndpoints.diaryDraft).call({
      'messages': conversation,
      'requestId': createAiRequestId(),
      'recordDate': _dateKey(DateTime.now()),
      'promptVersion': DiaryExtractionPrompt.version,
      if (requestedField != null) 'requestedField': requestedField,
      if (currentDraft != null) 'currentDraft': _jsonSafe(currentDraft.toMap()),
    }).timeout(const Duration(seconds: 70));
    if (result.data is! Map) {
      throw const FormatException('AI 日記草稿格式錯誤');
    }
    final data = Map<String, dynamic>.from(result.data as Map);
    var draft = AiDiaryDraft.fromMap(data);

    // Metaphors stored by the app must come from the reviewed local library.
    final map = _jsonSafe(draft.toMap());
    map['emotionMetaphorSuggestions'] = EmotionMetaphorLibrary.recommend(
      draft.emotionAnalysis,
      variationSeed: '${draft.createdAt.toIso8601String()}|'
          '${originalUserContent(messages)}',
    ).map((item) => item.toMap()).toList();
    draft = AiDiaryDraft.fromMap(map);
    final keepCurrentSongs = currentDraft != null &&
        requestedField != null &&
        requestedField != 'themeSong';
    if (keepCurrentSongs) {
      final withCurrentSongs = _jsonSafe(draft.toMap());
      withCurrentSongs['songRecommendations'] =
          currentDraft.songRecommendations.map((item) => item.toMap()).toList();
      withCurrentSongs['songRecommendationError'] =
          currentDraft.songRecommendationError;
      draft = AiDiaryDraft.fromMap(withCurrentSongs);
    } else {
      try {
        final songResult = await _functions
            .httpsCallable(AiCallableEndpoints.recommendSongs)
            .call({
          'requestId': createAiRequestId(),
          'profile': draft.songRecommendationProfile.toMap(),
          'market': 'TW',
        }).timeout(const Duration(seconds: 45));
        final songData = songResult.data is Map
            ? Map<String, dynamic>.from(songResult.data as Map)
            : const <String, dynamic>{};
        final withSongs = _jsonSafe(draft.toMap());
        withSongs['songRecommendations'] = songData['recommendations'] is List
            ? songData['recommendations']
            : const [];
        withSongs['songRecommendationError'] = songData['error'];
        draft = AiDiaryDraft.fromMap(withSongs);
      } catch (_) {
        final withError = _jsonSafe(draft.toMap());
        withError['songRecommendationError'] = 'music_service_failed';
        draft = AiDiaryDraft.fromMap(withError);
      }
    }
    await _saveDraft(draft);
    return draft;
  }

  Future<DiaryEntry?> existingDiary(DateTime date) =>
      _diaryRepository.getByDate(date);

  Future<List<VerifiedSongRecommendation>> searchSongs(String query) async {
    final result = await _functions
        .httpsCallable(AiCallableEndpoints.searchSongs)
        .call({'query': query.trim(), 'market': 'TW'}).timeout(
            const Duration(seconds: 30));
    final data = result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : const <String, dynamic>{};
    final errorCode = data['error']?.toString().trim() ?? '';
    if (errorCode.isNotEmpty) {
      throw InneraSongSearchException(errorCode);
    }
    return (data['tracks'] as List?)
            ?.whereType<Map>()
            .map((item) => VerifiedSongRecommendation.fromMap(
                Map<String, dynamic>.from(item)))
            .where((item) =>
                item.providerTrackId.isNotEmpty &&
                item.title.isNotEmpty &&
                item.artist.isNotEmpty)
            .toList() ??
        const [];
  }

  Future<void> confirm({
    required AiDiaryDraft draft,
    required DiaryDraftConfirmation confirmation,
  }) async {
    final current = await _diaryRepository.getByDate(draft.recordDate);
    final selectedSong = confirmation.selectedSong;
    final useSelectedSong = selectedSong != null &&
        confirmation.includedFields.contains('themeSong') &&
        ((current?.themeSong ?? '').trim().isEmpty ||
            confirmation.mergeChoices['themeSong'] !=
                DiaryFieldMerge.keepExisting);
    String resolve(String key, String existing) {
      if (!confirmation.includedFields.contains(key)) return existing;
      final next = (confirmation.values[key] ?? '').trim();
      if (existing.trim().isEmpty) return next;
      switch (confirmation.mergeChoices[key] ?? DiaryFieldMerge.keepExisting) {
        case DiaryFieldMerge.keepExisting:
          return existing;
        case DiaryFieldMerge.replace:
          return next;
        case DiaryFieldMerge.append:
          if (next.isEmpty) return existing;
          return '$existing\n\n$next';
      }
    }

    final entry = DiaryEntry(
      id: current?.id,
      date: draft.recordDate,
      title: resolve('title', current?.title ?? ''),
      content: resolve('content', current?.content ?? ''),
      themeSong: resolve('themeSong', current?.themeSong ?? ''),
      highlight: resolve('highlight', current?.highlight ?? ''),
      metaphor: resolve('metaphor', current?.metaphor ?? ''),
      proudOf: resolve('proudOf', current?.proudOf ?? ''),
      selfCare: resolve('selfCare', current?.selfCare ?? ''),
      gratitude: resolve('gratitude', current?.gratitude ?? ''),
      themeSongProvider:
          useSelectedSong ? selectedSong.provider : current?.themeSongProvider,
      themeSongProviderId: useSelectedSong
          ? selectedSong.providerTrackId
          : current?.themeSongProviderId,
      themeSongTitle:
          useSelectedSong ? selectedSong.title : current?.themeSongTitle,
      themeSongArtist:
          useSelectedSong ? selectedSong.artist : current?.themeSongArtist,
      themeSongAlbum:
          useSelectedSong ? selectedSong.album : current?.themeSongAlbum,
      themeSongArtworkUrl: useSelectedSong
          ? selectedSong.artworkUrl
          : current?.themeSongArtworkUrl,
      themeSongExternalUrl: useSelectedSong
          ? selectedSong.externalUrl
          : current?.themeSongExternalUrl,
      themeSongIsrc:
          useSelectedSong ? selectedSong.isrc : current?.themeSongIsrc,
      themeSongRecommendationReason: useSelectedSong
          ? selectedSong.reason
          : current?.themeSongRecommendationReason,
      moodScore: current?.moodScore,
      moodKeyword: current?.moodKeyword,
      imageUrls: current?.imageUrls ?? const [],
      createdAt: current?.createdAt,
      updatedAt: DateTime.now(),
    );
    await _diaryRepository.upsert(entry);

    final accepted = confirmation.includedFields.toList()..sort();
    final rejected = {
      'title',
      'content',
      'themeSong',
      'highlight',
      'metaphor',
      'proudOf',
      'selfCare',
      'gratitude',
    }.difference(confirmation.includedFields).toList()
      ..sort();
    await _draftRef(draft.id).set({
      ...draft.copyWith(status: AiDiaryDraftStatus.confirmed).toMap(),
      'confirmedAt': FieldValue.serverTimestamp(),
      'userAcceptedFields': accepted,
      'userRejectedFields': rejected,
      'userEditedFields': confirmation.userEditedFields.toList(),
    }, SetOptions(merge: true));
  }

  Future<void> discard(AiDiaryDraft draft) => _draftRef(draft.id).set({
        'status': AiDiaryDraftStatus.discarded.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> _saveDraft(AiDiaryDraft draft) => _draftRef(draft.id).set({
        ...draft.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  DocumentReference<Map<String, dynamic>> _draftRef(String id) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('aiDiaryDrafts')
        .doc(id);
  }

  static Map<String, dynamic> _jsonSafe(Map<String, dynamic> source) {
    dynamic convert(dynamic value) {
      if (value is Timestamp) return value.toDate().toIso8601String();
      if (value is Map) {
        return value
            .map((key, item) => MapEntry(key.toString(), convert(item)));
      }
      if (value is List) return value.map(convert).toList();
      return value;
    }

    return Map<String, dynamic>.from(convert(source) as Map);
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
