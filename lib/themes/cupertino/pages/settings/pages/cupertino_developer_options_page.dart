import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_debug_log_viewer_sheet.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:provider/provider.dart';

class CupertinoDeveloperOptionsPage extends StatelessWidget {
  const CupertinoDeveloperOptionsPage({super.key});

  Future<void> _openTerminalOutput(BuildContext context) async {
    await CupertinoBottomSheet.show(
      context: context,
      title: '终端输出',
      floatingTitle: true,
      child: const CupertinoDebugLogViewerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DeveloperOptionsProvider>(
      builder: (context, devOptions, child) {
    final Color backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final double topPadding = MediaQuery.of(context).padding.top + 64;
    return AdaptiveScaffold(
          appBar: const AdaptiveAppBar(
            title: '开发者选项',
            useNativeToolbar: true,
          ),
          body: ColoredBox(
            color: backgroundColor,
            child: SafeArea(
              top: false,
              bottom: false,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
                children: [
                  CupertinoSettingsGroupCard(
                    margin: EdgeInsets.zero,
                    backgroundColor: resolveSettingsSectionBackground(context),
                    addDividers: true,
                    children: [
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.command,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: const Text('终端输出'),
                        subtitle: const Text('查看日志、复制内容或生成二维码分享'),
                        backgroundColor: resolveSettingsTileBackground(context),
                        showChevron: true,
                        onTap: () => _openTerminalOutput(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
