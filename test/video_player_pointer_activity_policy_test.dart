import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_player_ui.dart';

void main() {
  test('HarmonyOS playback ignores synthetic desktop pointer activity', () {
    expect(
      shouldHandleDesktopPointerActivity(isHarmonyOS: true),
      isFalse,
    );
  });

  test('other platforms keep their existing pointer activity controls', () {
    expect(
      shouldHandleDesktopPointerActivity(isHarmonyOS: false),
      isTrue,
    );
  });
}
