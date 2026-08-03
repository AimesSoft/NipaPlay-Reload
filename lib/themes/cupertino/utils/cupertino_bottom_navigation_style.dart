import 'package:flutter/cupertino.dart';

class CupertinoBottomNavigationColors {
  const CupertinoBottomNavigationColors({
    required this.selected,
    required this.unselected,
  });

  final Color selected;
  final Color unselected;
}

/// Keeps the selected item accented while maximizing inactive-item contrast.
CupertinoBottomNavigationColors resolveCupertinoBottomNavigationColors({
  required Brightness brightness,
  required Color accentColor,
}) {
  return CupertinoBottomNavigationColors(
    selected: accentColor,
    unselected: brightness == Brightness.light
        ? CupertinoColors.black
        : CupertinoColors.white,
  );
}
