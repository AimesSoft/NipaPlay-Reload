import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';

import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart'
    show MediaServerType;

/// Cupertino 风格的网络服务器连接弹窗 - 使用原生 iOS 26 风格
class CupertinoNetworkServerConnectionDialog {
  static Future<bool?> show(
    BuildContext context,
    MediaServerType serverType,
  ) async {
    final l10n = context.l10n;
    final serverLabel =
        serverType == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';

    // 第一步：输入服务器地址
    final serverUrl = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => IOS26AlertDialog(
        title: l10n.connectServerDialogTitle(serverLabel),
        input: AdaptiveAlertDialogInput(
          placeholder: l10n.serverUrlInputPlaceholder,
          initialValue: '',
          keyboardType: TextInputType.url,
        ),
        actions: [
          AlertAction(
            title: l10n.cancel,
            style: AlertActionStyle.cancel,
            onPressed: () {},
          ),
          AlertAction(
            title: l10n.nextStep,
            style: AlertActionStyle.primary,
            onPressed: () {},
          ),
        ],
      ),
    );

    if (serverUrl == null || serverUrl.isEmpty) {
      return false;
    }

    if (!context.mounted) return false;

    // 第二步：输入用户名
    final username = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => IOS26AlertDialog(
        title: l10n.connectServerDialogTitle(serverLabel),
        input: AdaptiveAlertDialogInput(
          placeholder: l10n.inputUsernamePlaceholder,
          initialValue: '',
          keyboardType: TextInputType.text,
        ),
        actions: [
          AlertAction(
            title: l10n.cancel,
            style: AlertActionStyle.cancel,
            onPressed: () {},
          ),
          AlertAction(
            title: l10n.nextStep,
            style: AlertActionStyle.primary,
            onPressed: () {},
          ),
        ],
      ),
    );

    if (username == null || username.isEmpty) {
      return false;
    }

    if (!context.mounted) return false;

    // 第三步：输入密码
    final password = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => IOS26AlertDialog(
        title: l10n.connectServerDialogTitle(serverLabel),
        input: AdaptiveAlertDialogInput(
          placeholder: l10n.inputPasswordPlaceholder,
          initialValue: '',
          keyboardType: TextInputType.text,
          obscureText: true,
        ),
        actions: [
          AlertAction(
            title: l10n.cancel,
            style: AlertActionStyle.cancel,
            onPressed: () {},
          ),
          AlertAction(
            title: l10n.connectAction,
            style: AlertActionStyle.primary,
            onPressed: () {},
          ),
        ],
      ),
    );

    if (password == null) {
      return false;
    }

    if (!context.mounted) return false;

    try {
      bool connected;
      if (serverType == MediaServerType.jellyfin) {
        connected = await context.read<JellyfinProvider>().connectToServer(
              serverUrl,
              username,
              password,
            );
      } else {
        connected = await context.read<EmbyProvider>().connectToServer(
              serverUrl,
              username,
              password,
            );
      }

      if (context.mounted) {
        if (connected) {
          AdaptiveSnackBar.show(
            context,
            message: l10n.networkServerConnected(serverLabel),
            type: AdaptiveSnackBarType.success,
          );
          return true;
        } else {
          AdaptiveSnackBar.show(
            context,
            message: l10n.connectFailedCheckCredentials,
            type: AdaptiveSnackBarType.error,
          );
          return false;
        }
      }
    } catch (e) {
      if (context.mounted) {
        AdaptiveSnackBar.show(
          context,
          message: l10n.connectFailedWithError('$e'),
          type: AdaptiveSnackBarType.error,
        );
      }
      return false;
    }
    return false;
  }
}
