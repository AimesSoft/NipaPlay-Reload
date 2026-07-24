import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/abstract_player.dart';
import 'package:nipaplay/player_abstraction/mdk_player_adapter_io.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every player open applies and then clears a one-time User-Agent',
      () async {
    SharedPreferences.setMockInitialValues({});
    await PlayerFactory.initialize();
    final player = _UserAgentRecordingPlayer();
    addTearDown(() {
      PlayerFactory.setOneTimeUA('');
      SharedPreferences.setMockInitialValues({});
    });

    PlayerFactory.setOneTimeUA('OneTimeClient/1.0');
    PlayerFactory.applyUserAgentForNextOpen(player.setUserAgent);
    PlayerFactory.applyUserAgentForNextOpen(player.setUserAgent);

    expect(player.userAgents, <String>['OneTimeClient/1.0', '']);
  });

  test('empty User-Agent clears both native player option layers', () {
    final mdkApplied = <(String, String)>[];
    applyMdkUserAgentProperties(
      (key, value) => mdkApplied.add((key, value)),
      '',
    );
    expect(mdkApplied, <(String, String)>[
      ('avformat.user_agent', ''),
      ('avio.user_agent', ''),
    ]);

    final mediaKitApplied = <(String, String)>[];
    applyMediaKitUserAgentProperty(
      (key, value) => mediaKitApplied.add((key, value)),
      '',
    );
    expect(mediaKitApplied, <(String, String)>[('user-agent', '')]);
  });

  test('stream setup does not issue an unconfigured HTTP preflight', () {
    final source = File(
      'lib/utils/video_player_state/video_player_state_player_setup.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('http.head(')));
    expect(
      source,
      contains('PlayerFactory.applyUserAgentForNextOpen(player.setUserAgent);'),
    );
  });
}

class _UserAgentRecordingPlayer extends Fake implements AbstractPlayer {
  final List<String> userAgents = <String>[];

  @override
  void setUserAgent(String ua) => userAgents.add(ua);
}
