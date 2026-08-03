import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/danmaku/style.dart';

void main() {
  test('televisions expose Erika as their only player kernel', () {
    expect(
      PlayerFactory.isKernelSupportedOnTelevision(PlayerKernelType.videoPlayer),
      isFalse,
    );
    expect(
      PlayerFactory.isKernelSupportedOnTelevision(PlayerKernelType.erika),
      isTrue,
    );
    expect(
      PlayerFactory.isKernelSupportedOnTelevision(PlayerKernelType.mdk),
      isFalse,
    );
    expect(
      PlayerFactory.isKernelSupportedOnTelevision(PlayerKernelType.mediaKit),
      isFalse,
    );
  });

  test('tvOS Erika defaults to thin danmaku outlines', () {
    expect(defaultTvOSErikaDanmakuOutlineWidthLevel, 1.0);
    expect(
      normalizeDanmakuOutlineWidthLevel(
        null,
        fallback: defaultTvOSErikaDanmakuOutlineWidthLevel,
      ),
      1.0,
    );
  });

  test('tvOS settings hide kernel selectors and the Erika lab switch', () {
    final labs = File(
      'lib/settings/pages/labs_settings_content.dart',
    ).readAsStringSync();
    final player = File(
      'lib/settings/pages/player_settings_content.dart',
    ).readAsStringSync();
    final danmaku = File(
      'lib/settings/pages/danmaku_settings_content.dart',
    ).readAsStringSync();

    expect(
      labs,
      contains('PlayerFactory.isErikaKernelSupported &&'),
    );
    expect(player, contains('if (!kIsWeb && !globals.isTelevision)'));
    expect(
      danmaku,
      contains('final isErikaPlayerKernel = globals.isTelevision ||'),
    );
    expect(
      danmaku,
      contains('final showNextPlusPlusToggle = !globals.isTelevision &&'),
    );
  });

  test('tvOS release pins the native Erika plugin and reports Erika', () {
    final tvOSOverrides = File(
      'pubspec_overrides.tvos.yaml',
    ).readAsStringSync();
    final monitor = File(
      'lib/utils/system_resource_monitor.dart',
    ).readAsStringSync();

    expect(
      tvOSOverrides,
      contains('ref: 29f47da8e64ae9caacfd7317c2a6ad9d2d609e9b'),
    );
    expect(monitor, contains('_instance._updatePlayerKernelType();'));
    expect(monitor, contains("_instance._activeDecoder = 'Erika（等待媒体）';"));

    final tvOSBranchStart =
        monitor.indexOf('    } else {\n      // Television');
    final tvOSBranchEnd = monitor.indexOf('\n    }\n  }', tvOSBranchStart);
    expect(tvOSBranchStart, greaterThanOrEqualTo(0));
    expect(tvOSBranchEnd, greaterThan(tvOSBranchStart));
    expect(
      monitor.substring(tvOSBranchStart, tvOSBranchEnd),
      isNot(contains("_playerKernelType = 'Video Player'")),
    );
  });

  test('tvOS hides unsupported desktop settings entries', () {
    final entries = File(
      'lib/settings/unified_settings_entries.dart',
    ).readAsStringSync();

    expect(
        entries,
        contains('contentType: UnifiedSettingContentType.storage,'
            '\n      visible: (context, surface) => !globals.isTelevision,'));
    expect(
      entries,
      contains('contentType: UnifiedSettingContentType.externalPlayer,'
          '\n      visible: (context, surface) => !globals.isTelevision,'),
    );
    expect(
      entries,
      contains('!globals.isPhone &&\n          !globals.isTelevision'),
    );
    expect(
      entries,
      contains(
        'visible: (context, surface) => !kIsWeb && !globals.isTelevision',
      ),
    );
  });
}
