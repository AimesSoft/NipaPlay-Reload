import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';

void main() {
  test('MediaKit maps the player User-Agent to libmpv options', () {
    final applied = <(String, String)>[];

    applyMediaKitNetworkOptions(
      (key, value) => applied.add((key, value)),
      userAgent: 'PlayerClient/5.0',
    );

    expect(
      applied,
      [('user-agent', 'PlayerClient/5.0')],
    );
  });

  test('MediaKit preserves its default User-Agent when no override is set', () {
    final cases = <({
      String userAgent,
      List<(String, String)> expected,
    })>[
      (userAgent: '', expected: []),
      (
        userAgent: 'PlayerClient/5.0',
        expected: [('user-agent', 'PlayerClient/5.0')],
      ),
    ];

    for (final testCase in cases) {
      final applied = <(String, String)>[];
      applyMediaKitNetworkOptions(
        (key, value) => applied.add((key, value)),
        userAgent: testCase.userAgent,
      );
      expect(applied, testCase.expected);
    }
  });

  test('PlayerFactory passes the User-Agent to supported adapters', () {
    final factorySource = File(
      'lib/player_abstraction/player_factory.dart',
    ).readAsStringSync();
    final mdkSource = File(
      'lib/player_abstraction/mdk_player_adapter_io.dart',
    ).readAsStringSync();
    final mediaKitSource = File(
      'lib/player_abstraction/media_kit_player_adapter.dart',
    ).readAsStringSync();
    final compactFactory = factorySource.replaceAll(RegExp(r'\s+'), ' ');
    final compactMdk = mdkSource.replaceAll(RegExp(r'\s+'), ' ');
    final compactMediaKit = mediaKitSource.replaceAll(RegExp(r'\s+'), ' ');
    String kernelCase(String current, String next) {
      final start = compactFactory.indexOf('case PlayerKernelType.$current:');
      expect(start, greaterThanOrEqualTo(0));
      final end = compactFactory.indexOf('case PlayerKernelType.$next:', start);
      expect(end, greaterThan(start));
      return compactFactory.substring(start, end);
    }

    final mdkCase = kernelCase('mdk', 'videoPlayer');
    final mediaKitCase = kernelCase('mediaKit', 'erika');

    expect(mdkCase, contains('MdkPlayerAdapter('));
    expect(mdkCase, contains('userAgent: customPlayerUA'));
    expect(mediaKitCase, contains('MediaKitPlayerAdapter('));
    expect(mediaKitCase, contains('userAgent: customPlayerUA'));
    expect(
      compactMdk,
      contains('applyMdkUserAgentProperties(_setStickyProperty, _userAgent)'),
    );
    expect(
      compactMediaKit,
      contains(
        'applyMediaKitNetworkOptions( _setMpvPropertyOption, '
        'userAgent: _userAgent, )',
      ),
    );
  });
}
