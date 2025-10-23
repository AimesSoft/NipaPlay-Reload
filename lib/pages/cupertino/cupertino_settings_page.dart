import 'package:flutter/cupertino.dart';

import 'settings/sections/cupertino_settings_general_section.dart';

class CupertinoSettingsPage extends StatelessWidget {
  const CupertinoSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );

    return ColoredBox(
      color: backgroundColor,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: const [
          CupertinoSliverNavigationBar(
            largeTitle: Text('设置'),
            stretch: true,
            backgroundColor: Color(0x00000000),
            border: null,
          ),
          SliverSafeArea(
            top: false,
            sliver: _CupertinoSettingsContent(),
          ),
        ],
      ),
    );
  }
}

class _CupertinoSettingsContent extends StatelessWidget {
  const _CupertinoSettingsContent();

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            CupertinoSettingsGeneralSection(),
          ],
        ),
      ),
    );
  }
}
