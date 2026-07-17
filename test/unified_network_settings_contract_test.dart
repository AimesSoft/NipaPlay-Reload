import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/settings/widgets/media_server_connection_user_agent_setting.dart';

void main() {
  test('unified remote-media settings expose the connection UA workflow', () {
    final pageSource = File(
      'lib/settings/pages/remote_media_library_settings_content.dart',
    ).readAsStringSync();
    final settingSource = File(
      'lib/settings/widgets/media_server_connection_user_agent_setting.dart',
    ).readAsStringSync();

    expect(
      pageSource,
      contains('MediaServerConnectionUserAgentSetting'),
    );
    expect(
      settingSource,
      contains('MediaServerServiceBase.getStoredConnectionUserAgent'),
    );
    expect(
      settingSource,
      contains('MediaServerServiceBase.saveConnectionUserAgent'),
    );
    expect(
      settingSource,
      contains('MediaServerServiceBase.defaultConnectionUserAgent'),
    );
    expect(supportsMediaServerConnectionUserAgentSetting(isWeb: true), isFalse);
    expect(supportsMediaServerConnectionUserAgentSetting(isWeb: false), isTrue);
  });
}
