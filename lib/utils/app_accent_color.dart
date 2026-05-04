import 'package:flutter/material.dart';

enum AppAccentColorPreset {
  rose(
    storageKey: 'rose',
    title: '绯红',
    color: Color.fromARGB(255, 255, 46, 85),
  ),
  blue(
    storageKey: 'blue',
    title: '蓝色',
    color: Color.fromARGB(255, 42, 81, 212),
  ),
  green(
    storageKey: 'green',
    title: '荧绿',
    color: Color.fromARGB(255, 7, 255, 148),
  );

  const AppAccentColorPreset({
    required this.storageKey,
    required this.title,
    required this.color,
  });

  final String storageKey;
  final String title;
  final Color color;

  static AppAccentColorPreset fromStorageKey(String? storageKey) {
    return AppAccentColorPreset.values.firstWhere(
      (preset) => preset.storageKey == storageKey,
      orElse: () => AppAccentColorPreset.rose,
    );
  }
}

class AppAccentColors {
  const AppAccentColors._();

  static Color _current = AppAccentColorPreset.rose.color;

  static Color get current => _current;

  static void setCurrent(AppAccentColorPreset preset) {
    _current = preset.color;
  }
}
