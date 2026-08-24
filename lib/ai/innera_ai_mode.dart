import 'package:flutter/material.dart';

enum InneraAiMode {
  dailyRecord,
  emotionalSupport,
  physicalHealth,
  recentReview,
}

InneraAiMode resolveInneraAiModeIntent({
  required InneraAiMode activeMode,
  required String message,
}) {
  final text = message.replaceAll(RegExp(r'\s+'), '');
  final chatIntent = RegExp(
    r'不想記(了|錄)?|不要記(了|錄)?|先不用記(錄)?|不用幫我記|只是想聊聊|想聊聊就好|我們聊聊就好|先聊聊',
  );
  if (chatIntent.hasMatch(text)) return InneraAiMode.emotionalSupport;

  final recordIntent = RegExp(
    r'幫我記(一下|錄|下來)|我要記錄|我想記(一下|錄)|幫我記錄|這(個|件事)?幫我存起來|幫我存(一下|起來|下來)',
  );
  if (recordIntent.hasMatch(text)) return InneraAiMode.dailyRecord;
  return activeMode;
}

extension InneraAiModeX on InneraAiMode {
  bool get supportsDailyRecordDraft => this != InneraAiMode.recentReview;

  bool get showsRecordDraftCard =>
      this == InneraAiMode.dailyRecord || this == InneraAiMode.physicalHealth;

  String get title {
    switch (this) {
      case InneraAiMode.dailyRecord:
        return '幫我記錄';
      case InneraAiMode.emotionalSupport:
        return '陪我聊聊';
      case InneraAiMode.recentReview:
        return '回顧近況';
      case InneraAiMode.physicalHealth:
        return '身體不舒服';
    }
  }

  String get subtitle {
    switch (this) {
      case InneraAiMode.dailyRecord:
        return '把對話整理成狀態紀錄';
      case InneraAiMode.emotionalSupport:
        return '自由說說現在的感受與想法';
      case InneraAiMode.physicalHealth:
        return '記錄身體不適的位置、時間與程度';
      case InneraAiMode.recentReview:
        return '回顧近期的情緒、睡眠與症狀變化';
    }
  }

  IconData get icon {
    switch (this) {
      case InneraAiMode.dailyRecord:
        return Icons.edit_note_rounded;
      case InneraAiMode.emotionalSupport:
        return Icons.chat_bubble_outline_rounded;
      case InneraAiMode.physicalHealth:
        return Icons.monitor_heart_outlined;
      case InneraAiMode.recentReview:
        return Icons.insights_rounded;
    }
  }

  String get welcomeMessage {
    switch (this) {
      case InneraAiMode.dailyRecord:
        return '你可以直接說說今天發生的事，不需要照表格順序。我會先幫你整理，再詢問少數還缺少的資訊。';
      case InneraAiMode.emotionalSupport:
        return '你可以先說最想說的事。我會陪你整理情緒和想法，但不會取代真人支持或專業協助。';
      case InneraAiMode.physicalHealth:
        return '你可以描述不舒服的位置、開始時間和變化。我會協助對照你近期的紀錄，但無法僅憑對話判斷疾病。';
      case InneraAiMode.recentReview:
        return '你可以告訴我想回顧的方向，我會依你近期授權的紀錄整理可觀察到的變化。';
    }
  }

  String get inputHint {
    switch (this) {
      case InneraAiMode.dailyRecord:
        return '今天發生了什麼？你現在感覺如何？';
      case InneraAiMode.emotionalSupport:
        return '現在最想說的是什麼？';
      case InneraAiMode.physicalHealth:
        return '哪裡不舒服？大約從什麼時候開始？';
      case InneraAiMode.recentReview:
        return '最近想回顧哪一方面？';
    }
  }

  String get systemPromptKey => name;

  String get analyticsMode {
    switch (this) {
      case InneraAiMode.dailyRecord:
        return 'daily_record';
      case InneraAiMode.emotionalSupport:
        return 'recent_talk';
      case InneraAiMode.physicalHealth:
        return 'physical_discomfort';
      case InneraAiMode.recentReview:
        return 'status_review';
    }
  }
}
