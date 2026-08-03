import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/cupertino/utils/cupertino_bottom_navigation_style.dart';

void main() {
  const accentColor = Color(0xFF40C7FF);

  test('light mode keeps selected accent and uses black when unselected', () {
    final colors = resolveCupertinoBottomNavigationColors(
      brightness: Brightness.light,
      accentColor: accentColor,
    );

    expect(colors.selected, accentColor);
    expect(colors.unselected, const Color(0xFF000000));
  });

  test('dark mode keeps selected accent and uses white when unselected', () {
    final colors = resolveCupertinoBottomNavigationColors(
      brightness: Brightness.dark,
      accentColor: accentColor,
    );

    expect(colors.selected, accentColor);
    expect(colors.unselected, const Color(0xFFFFFFFF));
  });
}
