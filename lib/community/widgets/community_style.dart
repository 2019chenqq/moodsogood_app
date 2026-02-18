import 'package:flutter/material.dart';

class CommunityStyle {
  static const Color background = Color(0xFFF7F6F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFF1EFE8);
  static const Color outline = Color(0xFFE3DDD2);
  static const Color accent = Color(0xFF7BA59A);
  static const Color accentDark = Color(0xFF5D8B7C);
  static const Color text = Color(0xFF2F3A3D);
  static const Color muted = Color(0xFF6B7280);

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
