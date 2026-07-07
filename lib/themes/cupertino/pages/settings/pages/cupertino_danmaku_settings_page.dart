import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/danmaku_settings_content.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoDanmakuSettingsPage extends StatelessWidget {
  const CupertinoDanmakuSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveSettingsScope(
      style: AdaptiveSettingsStyle.phone,
      child: DanmakuSettingsContent(),
    );
  }
}
