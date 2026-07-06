import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/storage_settings_content.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoStorageSettingsPage extends StatelessWidget {
  const CupertinoStorageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveSettingsScope(
      style: AdaptiveSettingsStyle.cupertino,
      child: StorageSettingsContent(),
    );
  }
}
