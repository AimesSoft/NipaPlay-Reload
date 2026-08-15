import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android TV keeps Android player and danmaku kernel choices', () {
    final playerFactory = File(
      'lib/player_abstraction/player_factory.dart',
    ).readAsStringSync();
    final playerSettings = File(
      'lib/settings/pages/player_settings_content.dart',
    ).readAsStringSync();
    final danmakuSettings = File(
      'lib/settings/pages/danmaku_settings_content.dart',
    ).readAsStringSync();
    final next2Support = File(
      'lib/danmaku_next/next2_platform_support.dart',
    ).readAsStringSync();
    final kernelManager = File(
      'lib/utils/player_kernel_manager.dart',
    ).readAsStringSync();

    expect(
      playerFactory,
      contains(
        'globals.isTvOS ? PlayerKernelType.erika : PlayerKernelType.mdk',
      ),
    );
    expect(playerSettings, contains('if (!kIsWeb && !globals.isTvOS)'));
    expect(
      danmakuSettings,
      contains('final isErikaPlayerKernel = globals.isTvOS ||'),
    );
    expect(
      next2Support,
      contains('if (kIsWeb || globals.isTvOS) return false;'),
    );
    expect(next2Support, isNot(contains('kIsWeb || globals.isTelevision')));
    expect(kernelManager, contains('globals.isTvOS ? \'Erika\' : kernel'));
  });

  test('Android TV can leave large-screen mode while tvOS stays locked', () {
    final main = File('lib/main.dart').readAsStringSync();
    final themeProvider = File(
      'lib/providers/ui_theme_provider.dart',
    ).readAsStringSync();
    final scaffold = File(
      'lib/themes/nipaplay/widgets/large_screen_scaffold_layout.dart',
    ).readAsStringSync();

    expect(main, contains('isTelevision: globals.isTvOS'));
    expect(themeProvider, contains('isTelevision: globals.isTvOS'));
    expect(
      scaffold,
      contains('globals.isTvOS ? null : widget.onToggleLargeScreen'),
    );
  });
}
