import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/desktop_exit_handler.dart';

void main() {
  group('DesktopExitHandler window close interception', () {
    test('supports every desktop operating system', () {
      expect(
        DesktopExitHandler.supportsWindowCloseInterception(
          isWindows: true,
          isMacOS: false,
          isLinux: false,
        ),
        isTrue,
      );
      expect(
        DesktopExitHandler.supportsWindowCloseInterception(
          isWindows: false,
          isMacOS: true,
          isLinux: false,
        ),
        isTrue,
      );
      expect(
        DesktopExitHandler.supportsWindowCloseInterception(
          isWindows: false,
          isMacOS: false,
          isLinux: true,
        ),
        isTrue,
      );
    });

    test('does not enable desktop hooks on unsupported platforms', () {
      expect(
        DesktopExitHandler.supportsWindowCloseInterception(
          isWindows: false,
          isMacOS: false,
          isLinux: false,
        ),
        isFalse,
      );
    });
  });
}
