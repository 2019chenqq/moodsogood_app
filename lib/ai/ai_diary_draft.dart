import 'package:cloud_firestore/cloud_firestore.dart';

enum DiaryDraftSource { explicit, summarized, inferred, suggested, missing }

enum AiDiaryDraftStatus { pendingReview, confirmed, discarded }

class DiaryDraftSuggestion {
  const DiaryDraftSuggestion({
    required this.value,
    required this.source,
    required this.confidence,
    this.evidence = '',
    this.reason = '',
  });

  final String value;
  final DiaryDraftSource source;
  final double confidence;
  final String evidence;
  final String reason;

  factory DiaryDraftSuggestion.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    return DiaryDraftSuggestion(
      value: (data['value'] ?? '').toString().trim(),
      source: DiaryDraftSource.values.firstWhere(
        (item) => item.name == data['source'],
        orElse: () => DiaryDraftSource.missing,
      ),
      confidence:
          ((data['confidence'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      evidence: (data['evidence'] ?? '').toString().trim(),
      reason: (data['reason'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() => {
        'value': value,
        'source': source.name,
        'confidence': confidence,
        'evidence': evidence,
        'reason': reason,
      };
}

class DiaryEmotionAnalysis {
  const DiaryEmotionAnalysis({
    this.primaryEmotion = '',
    this.secondaryEmotions = const [],
    this.valence = 3,
    this.energy = 3,
    this.intensity = 3,
  });

  final String primaryEmotion;
  final List<String> secondaryEmotions;
  final int valence;
  final int energy;
  final int intensity;

  factory DiaryEmotionAnalysis.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    int score(String key) => ((data[key] as num?)?.toInt() ?? 3).clamp(1, 5);
    return DiaryEmotionAnalysis(
      primaryEmotion: (data['primaryEmotion'] ?? '').toString().trim(),
      secondaryEmotions: _strings(data['secondaryEmotions']),
      valence: score('valence'),
      energy: score('energy'),
      intensity: score('intensity'),
    );
  }

  Map<String, dynamic> toMap() => {
        'primaryEmotion': primaryEmotion,
        'secondaryEmotions': secondaryEmotions,
        'valence': valence,
        'energy': energy,
        'intensity': intensity,
      };
}

class SongRecommendationProfile {
  const SongRecommendationProfile({
    this.primaryEmotion = '',
    this.secondaryEmotions = const [],
    this.desiredEffect = '',
    this.musicTags = const [],
    this.searchKeywords = const [],
    this.preferredLanguages = const [],
    this.energy = 3,
    this.valence = 3,
    this.avoidThemes = const [],
  });

  final String primaryEmotion;
  final List<String> secondaryEmotions;
  final String desiredEffect;
  final List<String> musicTags;
  final List<String> searchKeywords;
  final List<String> preferredLanguages;
  final int energy;
  final int valence;
  final List<String> avoidThemes;

  factory SongRecommendationProfile.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    int score(String key) => ((data[key] as num?)?.toInt() ?? 3).clamp(1, 5);
    return SongRecommendationProfile(
      primaryEmotion: (data['primaryEmotion'] ?? '').toString().trim(),
      secondaryEmotions: _strings(data['secondaryEmotions']),
      desiredEffect: (data['desiredEffect'] ?? '').toString().trim(),
      musicTags: _strings(data['musicTags']),
      searchKeywords: _strings(data['searchKeywords']),
      preferredLanguages: _strings(data['preferredLanguages']),
      energy: score('energy'),
      valence: score('valence'),
      avoidThemes: _strings(data['avoidThemes']),
    );
  }

  Map<String, dynamic> toMap() => {
        'primaryEmotion': primaryEmotion,
        'secondaryEmotions': secondaryEmotions,
        'desiredEffect': desiredEffect,
        'musicTags': musicTags,
        'searchKeywords': searchKeywords,
        'preferredLanguages': preferredLanguages,
        'energy': energy,
        'valence': valence,
        'avoidThemes': avoidThemes,
      };
}

class VerifiedSongRecommendation {
  const VerifiedSongRecommendation({
    required this.candidateId,
    required this.provider,
    required this.providerTrackId,
    required this.title,
    required this.artist,
    required this.externalUrl,
    this.album = '',
    this.artworkUrl = '',
    this.previewUrl = '',
    this.isrc = '',
    this.reason = '',
  });

  final String candidateId;
  final String provider;
  final String providerTrackId;
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
  final String externalUrl;
  final String previewUrl;
  final String isrc;
  final String reason;

  factory VerifiedSongRecommendation.fromMap(Map<String, dynamic> map) =>
      VerifiedSongRecommendation(
        candidateId: (map['candidateId'] ?? '').toString().trim(),
        provider: (map['provider'] ?? '').toString().trim(),
        providerTrackId: (map['providerTrackId'] ?? '').toString().trim(),
        title: (map['title'] ?? '').toString().trim(),
        artist: (map['artist'] ?? '').toString().trim(),
        album: (map['album'] ?? '').toString().trim(),
        artworkUrl: (map['artworkUrl'] ?? '').toString().trim(),
        externalUrl: (map['externalUrl'] ?? '').toString().trim(),
        previewUrl: (map['previewUrl'] ?? '').toString().trim(),
        isrc: (map['isrc'] ?? '').toString().trim(),
        reason: (map['reason'] ?? '').toString().trim(),
      );

  Map<String, dynamic> toMap() => {
        'candidateId': candidateId,
        'provider': provider,
        'providerTrackId': providerTrackId,
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'externalUrl': externalUrl,
        'previewUrl': previewUrl,
        'isrc': isrc,
        'reason': reason,
      };
}

class AiDiaryDraft {
  const AiDiaryDraft({
    required this.id,
    required this.recordDate,
    required this.promptVersion,
    required this.createdAt,
    this.titleSuggestions = const [],
    this.content,
    this.memorableMomentSuggestions = const [],
    this.didWellSuggestions = const [],
    this.selfCareSuggestions = const [],
    this.gratitudeSuggestions = const [],
    this.emotionMetaphorSuggestions = const [],
    this.emotionAnalysis = const DiaryEmotionAnalysis(),
    this.songRecommendationProfile = const SongRecommendationProfile(),
    this.songRecommendations = const [],
    this.songRecommendationError,
    this.missingFields = const [],
    this.followUpQuestions = const [],
    this.safetyRiskDetected = false,
    this.safetyRiskLevel = 'none',
    this.safetyRiskReason = '',
    this.status = AiDiaryDraftStatus.pendingReview,
    this.modelName,
    this.conversationMessageCount = 0,
    this.parseSucceeded = true,
  });

  final String id;
  final DateTime recordDate;
  final String promptVersion;
  final DateTime createdAt;
  final List<DiaryDraftSuggestion> titleSuggestions;
  final DiaryDraftSuggestion? content;
  final List<DiaryDraftSuggestion> memorableMomentSuggestions;
  final List<DiaryDraftSuggestion> didWellSuggestions;
  final List<DiaryDraftSuggestion> selfCareSuggestions;
  final List<DiaryDraftSuggestion> gratitudeSuggestions;
  final List<DiaryDraftSuggestion> emotionMetaphorSuggestions;
  final DiaryEmotionAnalysis emotionAnalysis;
  final SongRecommendationProfile songRecommendationProfile;
  final List<VerifiedSongRecommendation> songRecommendations;
  final String? songRecommendationError;
  final List<String> missingFields;
  final List<Map<String, String>> followUpQuestions;
  final bool safetyRiskDetected;
  final String safetyRiskLevel;
  final String safetyRiskReason;
  final AiDiaryDraftStatus status;
  final String? modelName;
  final int conversationMessageCount;
  final bool parseSucceeded;

  factory AiDiaryDraft.fromMap(Map<String, dynamic> map) {
    final date = DateTime.tryParse((map['recordDate'] ?? '').toString()) ??
        DateTime.now();
    List<DiaryDraftSuggestion> suggestions(String key) =>
        (map[key] as List?)
            ?.whereType<Map>()
            .map((item) =>
                DiaryDraftSuggestion.fromMap(Map<String, dynamic>.from(item)))
            .where((item) => item.value.isNotEmpty)
            .toList() ??
        const [];
    final contentMap = map['content'] is Map
        ? Map<String, dynamic>.from(map['content'] as Map)
        : null;
    final safety = map['safetyRisk'] is Map
        ? Map<String, dynamic>.from(map['safetyRisk'] as Map)
        : const <String, dynamic>{};
    return AiDiaryDraft(
      id: (map['id'] ?? _dateKey(date)).toString(),
      recordDate: date,
      promptVersion: (map['promptVersion'] ?? 'diary_extraction_v1').toString(),
      createdAt: _date(map['createdAt']) ?? DateTime.now(),
      titleSuggestions: suggestions('titleSuggestions'),
      content:
          contentMap == null ? null : DiaryDraftSuggestion.fromMap(contentMap),
      memorableMomentSuggestions: suggestions('memorableMomentSuggestions'),
      didWellSuggestions: suggestions('didWellSuggestions'),
      selfCareSuggestions: suggestions('selfCareSuggestions'),
      gratitudeSuggestions: suggestions('gratitudeSuggestions'),
      emotionMetaphorSuggestions: suggestions('emotionMetaphorSuggestions'),
      emotionAnalysis: DiaryEmotionAnalysis.fromMap(
          map['emotionAnalysis'] is Map
              ? Map<String, dynamic>.from(map['emotionAnalysis'] as Map)
              : null),
      songRecommendationProfile: SongRecommendationProfile.fromMap(
          map['songRecommendationProfile'] is Map
              ? Map<String, dynamic>.from(
                  map['songRecommendationProfile'] as Map)
              : null),
      songRecommendations: (map['songRecommendations'] as List?)
              ?.whereType<Map>()
              .map((item) => VerifiedSongRecommendation.fromMap(
                  Map<String, dynamic>.from(item)))
              .where((item) =>
                  item.providerTrackId.isNotEmpty &&
                  item.title.isNotEmpty &&
                  item.artist.isNotEmpty &&
                  item.externalUrl.isNotEmpty)
              .toList() ??
          const [],
      songRecommendationError: map['songRecommendationError']?.toString(),
      missingFields: _strings(map['missingFields']),
      followUpQuestions: (map['followUpQuestions'] as List?)
              ?.whereType<Map>()
              .map((item) => {
                    'targetField': (item['targetField'] ?? '').toString(),
                    'question': (item['question'] ?? '').toString(),
                  })
              .toList() ??
          const [],
      safetyRiskDetected: safety['detected'] == true,
      safetyRiskLevel: (safety['level'] ?? 'none').toString(),
      safetyRiskReason: (safety['reason'] ?? '').toString(),
      status: AiDiaryDraftStatus.values.firstWhere(
        (item) => item.name == map['status'],
        orElse: () => AiDiaryDraftStatus.pendingReview,
      ),
      modelName: map['modelName']?.toString(),
      conversationMessageCount:
          (map['conversationMessageCount'] as num?)?.toInt() ?? 0,
      parseSucceeded: map['parseSucceeded'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'recordDate': _dateKey(recordDate),
        'promptVersion': promptVersion,
        'createdAt': Timestamp.fromDate(createdAt),
        'titleSuggestions':
            titleSuggestions.map((item) => item.toMap()).toList(),
        'content': content?.toMap(),
        'memorableMomentSuggestions':
            memorableMomentSuggestions.map((item) => item.toMap()).toList(),
        'didWellSuggestions':
            didWellSuggestions.map((item) => item.toMap()).toList(),
        'selfCareSuggestions':
            selfCareSuggestions.map((item) => item.toMap()).toList(),
        'gratitudeSuggestions':
            gratitudeSuggestions.map((item) => item.toMap()).toList(),
        'emotionMetaphorSuggestions':
            emotionMetaphorSuggestions.map((item) => item.toMap()).toList(),
        'emotionAnalysis': emotionAnalysis.toMap(),
        'songRecommendationProfile': songRecommendationProfile.toMap(),
        'songRecommendations':
            songRecommendations.map((item) => item.toMap()).toList(),
        'songRecommendationError': songRecommendationError,
        'missingFields': missingFields,
        'followUpQuestions': followUpQuestions,
        'safetyRisk': {
          'detected': safetyRiskDetected,
          'level': safetyRiskLevel,
          'reason': safetyRiskReason,
        },
        'status': status.name,
        'modelName': modelName,
        'conversationMessageCount': conversationMessageCount,
        'parseSucceeded': parseSucceeded,
      };

  AiDiaryDraft copyWith({AiDiaryDraftStatus? status}) => AiDiaryDraft(
        id: id,
        recordDate: recordDate,
        promptVersion: promptVersion,
        createdAt: createdAt,
        titleSuggestions: titleSuggestions,
        content: content,
        memorableMomentSuggestions: memorableMomentSuggestions,
        didWellSuggestions: didWellSuggestions,
        selfCareSuggestions: selfCareSuggestions,
        gratitudeSuggestions: gratitudeSuggestions,
        emotionMetaphorSuggestions: emotionMetaphorSuggestions,
        emotionAnalysis: emotionAnalysis,
        songRecommendationProfile: songRecommendationProfile,
        songRecommendations: songRecommendations,
        songRecommendationError: songRecommendationError,
        missingFields: missingFields,
        followUpQuestions: followUpQuestions,
        safetyRiskDetected: safetyRiskDetected,
        safetyRiskLevel: safetyRiskLevel,
        safetyRiskReason: safetyRiskReason,
        status: status ?? this.status,
        modelName: modelName,
        conversationMessageCount: conversationMessageCount,
        parseSucceeded: parseSucceeded,
      );
}

List<String> _strings(dynamic value) => value is List
    ? value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList()
    : const [];

DateTime? _date(dynamic value) => value is Timestamp
    ? value.toDate()
    : value is String
        ? DateTime.tryParse(value)
        : null;

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
