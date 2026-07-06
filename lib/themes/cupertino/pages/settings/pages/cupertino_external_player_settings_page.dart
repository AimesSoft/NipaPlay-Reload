import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/external_player_settings_content.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoExternalPlayerSettingsPage extends StatelessWidget {
  const CupertinoExternalPlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveSettingsScope(
      style: AdaptiveSettingsStyle.cupertino,
      child: ExternalPlayerSettingsContent(),
    );
  }
}
