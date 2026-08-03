import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/cupertino/utils/cupertino_bottom_navigation_style.dart';

void main() {
  test('bottom navigation uses pure black in light mode', () {
    expect(
      resolveCupertinoBottomNavigationForegroundColor(Brightness.light),
      const Color(0xFF000000),
    );
  });

  test('bottom navigation uses pure white in dark mode', () {
    expect(
      resolveCupertinoBottomNavigationForegroundColor(Brightness.dark),
      const Color(0xFFFFFFFF),
    );
  });
}
