import 'package:flutter/material.dart';

enum InneraAiMode {
  dailyRecord,
  emotionalSupport,
  physicalHealth,
  recentReview,
}

extension InneraAiModeX on InneraAiMode {
  bool get supportsDailyRecordDraft => this != InneraAiMode.recentReview;

  String get title {
    switch (this) {
      case InneraAiMode.dailyRecord:
        return '今日記錄';
      case InneraAiMode.emotionalSupport:
        return '我想聊聊';
      case InneraAiMode.recentReview:
        return '狀態回顧';
      case InneraAiMode.physicalHealth:
        return '身體不適聊聊';
    }
  }

  String get subtitle {
    switch (this) {
      case InneraAiMode.dailyRecord:
        return '說說今天發生的事，AI 會協助整理情緒、症狀與生活狀態';
      case InneraAiMode.emotionalSupport:
        return '整理現在的情緒、想法與困擾';
      case InneraAiMode.physicalHealth:
        return '對照近期症狀、睡眠及用藥紀錄，整理值得注意的變化';
      case InneraAiMode.recentReview:
        return '整理近期情緒、睡眠、症狀與生活模式';
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
}
