import 'package:flutter/cupertino.dart';

import 'settings/sections/cupertino_settings_general_section.dart';
import 'settings/sections/cupertino_settings_about_section.dart';

class CupertinoSettingsPage extends StatefulWidget {
  const CupertinoSettingsPage({super.key});

  @override
  State<CupertinoSettingsPage> createState() => _CupertinoSettingsPageState();
}

class _CupertinoSettingsPageState extends State<CupertinoSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final Color backgroundColor =
        CupertinoColors.systemGroupedBackground.resolveFrom(context);

    final Color navBackgroundColor = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: Color(0xCCF2F2F7),
        darkColor: Color(0xCC1C1C1E),
      ),
      context,
    );

    return CupertinoPageScaffold(
      backgroundColor: backgroundColor,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('设置'),
            border: null,
            backgroundColor: navBackgroundColor,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  CupertinoSettingsGeneralSection(),
                  SizedBox(height: 24),
                  CupertinoSettingsAboutSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
