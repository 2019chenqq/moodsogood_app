import 'package:flutter/material.dart';
import '../models/room.dart';

class RoomsProvider extends ChangeNotifier {
  final List<Room> rooms = const [
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

  Room? byId(String id) {
    try {
      return rooms.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }
}