import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/player_settings_content.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoPlayerSettingsPage extends StatelessWidget {
  const CupertinoPlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveSettingsScope(
      style: AdaptiveSettingsStyle.phone,
      child: PlayerSettingsContent(),
    );
  }
}
