import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/webdav_quick_settings_page.dart';
import 'package:provider/provider.dart';

class CupertinoLabsSettingsPage extends StatelessWidget {
  const CupertinoLabsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final double topPadding = MediaQuery.of(context).padding.top + 64;

    return Consumer<LabsSettingsProvider>(
      builder: (context, labsSettings, child) {
        return AdaptiveScaffold(
          appBar: const AdaptiveAppBar(
            title: '实验室',
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
                          CupertinoIcons.tv,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: const Text('大屏幕模式'),
                        subtitle: const Text('开启后，NipaPlay 主题右上角显示大屏幕模式按钮'),
                        trailing: AdaptiveSwitch(
                          value: labsSettings.enableLargeScreenMode,
                          onChanged: (value) {
                            labsSettings.setEnableLargeScreenMode(value);
                          },
                        ),
                        onTap: () {
                          labsSettings.setEnableLargeScreenMode(
                            !labsSettings.enableLargeScreenMode,
                          );
                        },
                        backgroundColor: resolveSettingsTileBackground(context),
                      ),
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.qrcode,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: const Text('显示远程访问二维码'),
                        subtitle: const Text('开启后，远程访问服务页面会显示供手机扫码连接的二维码'),
                        trailing: AdaptiveSwitch(
                          value: labsSettings.showRemoteAccessQrCode,
                          onChanged: (value) {
                            labsSettings.setShowRemoteAccessQrCode(value);
                          },
                        ),
                        onTap: () {
                          labsSettings.setShowRemoteAccessQrCode(
                            !labsSettings.showRemoteAccessQrCode,
                          );
                        },
                        backgroundColor: resolveSettingsTileBackground(context),
                      ),
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.lab_flask,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: const Text('显示 Next2 弹幕内核'),
                        subtitle:
                            const Text('开启后，弹幕渲染引擎下拉菜单显示 NipaPlay Next2'),
                        trailing: AdaptiveSwitch(
                          value: labsSettings.enableNext2DanmakuKernel,
                          onChanged: (value) {
                            labsSettings.setEnableNext2DanmakuKernel(value);
                          },
                        ),
                        onTap: () {
                          labsSettings.setEnableNext2DanmakuKernel(
                            !labsSettings.enableNext2DanmakuKernel,
                          );
                        },
                        backgroundColor: resolveSettingsTileBackground(context),
                      ),
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.cloud,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: const Text('WebDAV 快捷设置'),
                        subtitle:
                            const Text('配置底部 WebDAV 快捷 Tab，快速访问 WebDAV 服务器'),
                        trailing: Icon(
                          CupertinoIcons.chevron_forward,
                          color: CupertinoDynamicColor.resolve(
                            CupertinoColors.tertiaryLabel,
                            context,
                          ),
                          size: 18,
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (_) =>
                                  const CupertinoWebDAVQuickSettingsPage(),
                            ),
                          );
                        },
                        backgroundColor: resolveSettingsTileBackground(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
