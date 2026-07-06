import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/appearance_settings_content.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoAppearanceSettingsPage extends StatelessWidget {
  const CupertinoAppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveSettingsScope(
      style: AdaptiveSettingsStyle.cupertino,
      child: AppearanceSettingsContent(),
    );
  }
}
