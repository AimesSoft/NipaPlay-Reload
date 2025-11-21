import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

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
    final serverLabel =
        serverType == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';

    // 第一步：输入服务器地址
    final serverUrl = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => IOS26AlertDialog(
        title: '连接 $serverLabel 服务器',
        input: const AdaptiveAlertDialogInput(
          placeholder: '例如：http://192.168.1.100:8096',
          initialValue: '',
          keyboardType: TextInputType.url,
        ),
        actions: [
          AlertAction(
            title: '取消',
            style: AlertActionStyle.cancel,
            onPressed: () {},
          ),
          AlertAction(
            title: '下一步',
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
        title: '连接 $serverLabel 服务器',
        input: const AdaptiveAlertDialogInput(
          placeholder: '输入用户名',
          initialValue: '',
          keyboardType: TextInputType.text,
        ),
        actions: [
          AlertAction(
            title: '取消',
            style: AlertActionStyle.cancel,
            onPressed: () {},
          ),
          AlertAction(
            title: '下一步',
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
        title: '连接 $serverLabel 服务器',
        input: const AdaptiveAlertDialogInput(
          placeholder: '输入密码',
          initialValue: '',
          keyboardType: TextInputType.text,
          obscureText: true,
        ),
        actions: [
          AlertAction(
            title: '取消',
            style: AlertActionStyle.cancel,
            onPressed: () {},
          ),
          AlertAction(
            title: '连接',
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
            message: '$serverLabel 服务器已连接',
            type: AdaptiveSnackBarType.success,
          );
          return true;
        } else {
          AdaptiveSnackBar.show(
            context,
            message: '连接失败，请检查服务器地址和凭证',
            type: AdaptiveSnackBarType.error,
          );
          return false;
        }
      }
    } catch (e) {
      if (context.mounted) {
        AdaptiveSnackBar.show(
          context,
          message: '连接错误：$e',
          type: AdaptiveSnackBarType.error,
        );
      }
      return false;
    }
    return false;
  }
}
