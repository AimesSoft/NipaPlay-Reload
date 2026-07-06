import 'package:flutter/material.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/settings/pages/remote_access_receiver_settings_section.dart';

class RemoteAccessSettingsContent extends StatelessWidget {
  const RemoteAccessSettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveSettingsPage(
      title: '远程访问',
      children: [
        RemoteAccessReceiverSettingsSection(),
      ],
    );
  }
}
