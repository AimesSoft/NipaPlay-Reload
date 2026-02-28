import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';

class CupertinoExternalPlayerSettingsPage extends StatelessWidget {
  const CupertinoExternalPlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final double topPadding = MediaQuery.of(context).padding.top + 64;
    final bool externalSupported = globals.isDesktop;

    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(
        title: '外部调用',
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  externalSupported
                      ? '启用后，所有播放操作将通过外部播放器打开。'
                      : '仅桌面端支持外部播放器调用。',
                  style: TextStyle(
                    fontSize: 13,
                    color: resolveSettingsSecondaryTextColor(context),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildExternalSettingsCard(context, externalSupported),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExternalSettingsCard(
      BuildContext context, bool externalSupported) {
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      addDividers: true,
      dividerIndent: 16,
      children: [
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            Future<void> toggleExternal(bool value) async {
              if (!externalSupported) {
                return;
              }
              if (value) {
                if (settingsProvider.externalPlayerPath.trim().isEmpty) {
                  final picked =
                      await FilePickerService().pickExternalPlayerExecutable();
                  if (picked == null || picked.trim().isEmpty) {
                    AdaptiveSnackBar.show(
                      context,
                      message: '已取消选择外部播放器',
                      type: AdaptiveSnackBarType.info,
                    );
                    await settingsProvider.setUseExternalPlayer(false);
                    return;
                  }
                  await settingsProvider.setExternalPlayerPath(picked);
                }
                await settingsProvider.setUseExternalPlayer(true);
                AdaptiveSnackBar.show(
                  context,
                  message: '已启用外部播放器',
                  type: AdaptiveSnackBarType.success,
                );
              } else {
                await settingsProvider.setUseExternalPlayer(false);
                AdaptiveSnackBar.show(
                  context,
                  message: '已关闭外部播放器',
                  type: AdaptiveSnackBarType.success,
                );
              }
            }

            return CupertinoSettingsTile(
              leading: Icon(
                CupertinoIcons.square_arrow_up,
                color: resolveSettingsIconColor(context),
              ),
              title: const Text('启用外部播放器'),
              subtitle: Text(externalSupported ? '开启后将使用外部播放器播放视频' : '仅桌面端支持'),
              trailing: AdaptiveSwitch(
                value: settingsProvider.useExternalPlayer,
                onChanged: externalSupported ? toggleExternal : null,
              ),
              onTap: externalSupported
                  ? () => toggleExternal(!settingsProvider.useExternalPlayer)
                  : null,
              backgroundColor: tileColor,
            );
          },
        ),
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            final path = settingsProvider.externalPlayerPath.trim();
            final subtitle = !externalSupported
                ? '仅桌面端支持'
                : (path.isEmpty ? '未选择外部播放器' : path);
            return CupertinoSettingsTile(
              leading: Icon(
                CupertinoIcons.folder,
                color: resolveSettingsIconColor(context),
              ),
              title: const Text('选择外部播放器'),
              subtitle: Text(subtitle),
              showChevron: true,
              onTap: externalSupported
                  ? () async {
                      final picked = await FilePickerService()
                          .pickExternalPlayerExecutable();
                      if (picked == null || picked.trim().isEmpty) {
                        AdaptiveSnackBar.show(
                          context,
                          message: '已取消选择外部播放器',
                          type: AdaptiveSnackBarType.info,
                        );
                        return;
                      }
                      await settingsProvider.setExternalPlayerPath(picked);
                      AdaptiveSnackBar.show(
                        context,
                        message: '已更新外部播放器',
                        type: AdaptiveSnackBarType.success,
                      );
                    }
                  : null,
              backgroundColor: tileColor,
            );
          },
        ),
      ],
    );
  }
}
