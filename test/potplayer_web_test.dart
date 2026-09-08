@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/external_player_session/potplayer_session.dart';
import 'package:nipaplay/models/external_player_session/potplayer_window_api.dart';

void main() {
  test('PotPlayer session can be compiled into the embedded Web UI', () {
    expect(
      PotPlayerSession.buildExtraArgs(const Duration(seconds: 12), const [
        '/user_agent=NipaPlay',
      ]),
      ['/new', '/seek=00:00:12.000', '/user_agent=NipaPlay'],
    );
    expect(() => WindowsPotPlayerApi.instance, throwsUnsupportedError);
  });
}
