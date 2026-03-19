import 'package:flutter/material.dart';

class CommunityStyle {
  static const Color background = Color(0xFFF3EEF5);
  static const Color surface = Color(0xFFFAF7FB);
  static const Color surfaceSoft = Color(0xFFEDE6F0);
  static const Color outline = Color(0xFFDDD4E1);
  static const Color accent = Color(0xFF9B87B8);
  static const Color accentDark = Color(0xFF7D6A96);
  static const Color text = Color(0xFF3A3544);
  static const Color muted = Color(0xFF8B8593);

  static const RoundedRectangleBorder cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(18)),
    side: BorderSide(color: outline),
  );

  static const LinearGradient headerGradient = LinearGradient(
    colors: [Color(0xFFF3EFE7), Color(0xFFEAF2EE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
