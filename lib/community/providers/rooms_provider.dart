import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/room.dart';

class RoomsProvider extends ChangeNotifier {
  final List<Room> _baseRooms = const [
    Room(
      id: 'mood_down',
      name: '情緒低落',
      icon: Icons.cloudy_snowing,
      description: '想說說那些撐不住的時刻',
    ),
    Room(
      id: 'anxiety',
      name: '焦慮恐慌',
      icon: Icons.flash_on,
      description: '心跳、緊繃、腦內停不下來',
    ),
    Room(
      id: 'sleep',
      name: '睡眠問題',
      icon: Icons.nights_stay,
      description: '失眠、早醒、作息混亂',
    ),
    Room(
      id: 'meds',
      name: '藥物與副作用',
      icon: Icons.medication_outlined,
      description: '用藥經驗、疑問、觀察',
    ),
    Room(
      id: 'heard',
      name: '想被聽見',
      icon: Icons.hearing,
      description: '你可以在這裡只說說話',
    ),
  ];

  List<Room> _extraRooms = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _roomsSub;

  RoomsProvider() {
    _listenRooms();
  }

  List<Room> get rooms => [..._baseRooms, ..._extraRooms];

  void _listenRooms() {
    _roomsSub = FirebaseFirestore.instance
        .collection('community_rooms')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((snap) {
      _extraRooms = snap.docs.map((doc) {
        final data = doc.data();
        final name = (data['name'] ?? '未命名看板').toString();
        return Room(
          id: doc.id,
          name: name,
          description: (data['description'] ?? '').toString(),
          icon: _selectIconForRoomName(name),
        );
      }).toList();
      notifyListeners();
    });
  }

  /// 根據看板名稱自動選擇圖案
  IconData _selectIconForRoomName(String name) {
    final normalized = name.toLowerCase();

    // 關鍵字對應的圖案
    const iconMap = {
      '情緒': Icons.sentiment_very_satisfied_outlined,
      '低落': Icons.cloud_queue_outlined,
      '沮喪': Icons.cloud_queue_outlined,
      '失望': Icons.cloud_queue_outlined,
      '焦慮': Icons.flash_on_outlined,
      '恐慌': Icons.flash_on_outlined,
      '緊張': Icons.flash_on_outlined,
      '睡眠': Icons.nights_stay_outlined,
      '失眠': Icons.nights_stay_outlined,
      '睡覺': Icons.nights_stay_outlined,
      '藥': Icons.medication_outlined,
      '用藥': Icons.medication_outlined,
      '副作用': Icons.medication_outlined,
      '聊天': Icons.chat_bubble_outline,
      '討論': Icons.chat_bubble_outline,
      '吐槽': Icons.chat_bubble_outline,
      '分享': Icons.share_outlined,
      '經驗': Icons.lightbulb_outline,
      '建議': Icons.lightbulb_outline,
      '運動': Icons.directions_run_outlined,
      '音樂': Icons.music_note_outlined,
      '工作': Icons.work_outline,
      '學習': Icons.school_outlined,
      '親情': Icons.family_restroom_outlined,
      '友情': Icons.group_outlined,
      '愛情': Icons.favorite_outline,
      '戀愛': Icons.favorite_outline,
      '飲食': Icons.restaurant_outlined,
      '美食': Icons.restaurant_outlined,
      '旅遊': Icons.flight_takeoff_outlined,
      '興趣': Icons.stars_outlined,
    };

    // 按優先級檢查是否包含關鍵字
    for (final entry in iconMap.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }

    // 預設圖案
    return Icons.forum_outlined;
  }

  Room? byId(String id) {
    try {
      return rooms.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _roomsSub?.cancel();
    super.dispose();
  }
}