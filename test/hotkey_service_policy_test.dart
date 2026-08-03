import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/hotkey_service.dart';

void main() {
  test('large-screen mode blocks the complete desktop hotkey set', () {
    expect(
      shouldBlockDesktopHotkeys(
        isLargeScreenModeActive: true,
        hasActiveOverlay: false,
        isEditableTextFocused: false,
        playerHotkeysSuppressed: false,
      ),
      isTrue,
    );
  });

  test('desktop hotkeys remain available after leaving large-screen mode', () {
    expect(
      shouldBlockDesktopHotkeys(
        isLargeScreenModeActive: false,
        hasActiveOverlay: false,
        isEditableTextFocused: false,
        playerHotkeysSuppressed: false,
      ),
      isFalse,
    );
  });

  test('existing overlay, text input, and player guards remain active', () {
    for (final blockedState in <List<bool>>[
      <bool>[true, false, false],
      <bool>[false, true, false],
      <bool>[false, false, true],
    ]) {
      expect(
        shouldBlockDesktopHotkeys(
          isLargeScreenModeActive: false,
          hasActiveOverlay: blockedState[0],
          isEditableTextFocused: blockedState[1],
          playerHotkeysSuppressed: blockedState[2],
        ),
        isTrue,
      );
    }
  });
}
