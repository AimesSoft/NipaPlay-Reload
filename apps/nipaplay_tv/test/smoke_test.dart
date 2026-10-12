import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay_tv/main.dart';
import 'package:nipaplay_tv/ui/focusable_card.dart';

void main() {
  test('TvAppShell is constructible and FocusableCard exposes activate hook',
      () {
    expect(const NipaPlayTvApp(), isNotNull);
    expect(
      FocusableCard(onActivate: () {}, child: const SizedBox.shrink()),
      isNotNull,
    );
  });
}
