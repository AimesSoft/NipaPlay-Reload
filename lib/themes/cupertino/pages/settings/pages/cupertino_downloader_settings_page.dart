import 'package:flutter/widgets.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/downloader_settings_content.dart';

class CupertinoDownloaderSettingsPage extends StatelessWidget {
  const CupertinoDownloaderSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveSettingsScope(
      style: AdaptiveSettingsStyle.cupertino,
      child: DownloaderSettingsContent(),
    );
  }
}
