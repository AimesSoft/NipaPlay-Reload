import 'package:flutter/cupertino.dart';

/// Returns the high-contrast foreground shared by every bottom-navigation item.
Color resolveCupertinoBottomNavigationForegroundColor(Brightness brightness) {
  return brightness == Brightness.light
      ? CupertinoColors.black
      : CupertinoColors.white;
}
