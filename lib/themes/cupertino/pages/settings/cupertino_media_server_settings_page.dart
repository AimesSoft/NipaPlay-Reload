import 'package:flutter/widgets.dart';
import 'package:nipaplay/settings/pages/remote_media_library_settings_content.dart';

class CupertinoMediaServerSettingsPage extends StatelessWidget {
  const CupertinoMediaServerSettingsPage({super.key});

  static const String routeName = 'cupertino-network-media-settings';

  @override
  Widget build(BuildContext context) {
    return const RemoteMediaLibrarySettingsContent();
  }
}
