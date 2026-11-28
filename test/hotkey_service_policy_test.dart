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

  test('hotkeys register only inside the player scope', () {
    expect(
      shouldRegisterPlayerHotkeys(
        playerHotkeysAllowed: true,
        hasActiveOverlay: false,
        isEditableTextFocused: false,
      ),
      isTrue,
    );
  });

  test('hotkeys stay unregistered outside the player scope', () {
    expect(
      shouldRegisterPlayerHotkeys(
        playerHotkeysAllowed: false,
        hasActiveOverlay: false,
        isEditableTextFocused: false,
      ),
      isFalse,
    );
  });

  test('overlays and focused text inputs suspend registration', () {
    // 播放器作用域内：overlay 弹层或文本输入框聚焦时都不注册热键，
    // 让按键直达 overlay 控件或输入框（例如弹幕偏移秒数输入）。
    for (final blockedState in <List<bool>>[
      <bool>[true, true],
      <bool>[true, false],
    ]) {
      expect(
        shouldRegisterPlayerHotkeys(
          playerHotkeysAllowed: true,
          hasActiveOverlay: blockedState[0],
          isEditableTextFocused: blockedState[1],
        ),
        isFalse,
      );
    }
  });
}
