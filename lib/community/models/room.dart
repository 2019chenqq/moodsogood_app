import 'package:flutter/material.dart';

class Room {
  final String id;
  final String name;
  final IconData icon;
  final String description;

  const Room({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
  });
}