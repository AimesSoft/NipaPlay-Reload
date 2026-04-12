import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';

import 'package:nipaplay/providers/dandanplay_remote_provider.dart';

/// 用户在 Cupertino 界面中配置弹弹play 远程访问时输入的数据
class DandanplayConnectionConfig {
  const DandanplayConnectionConfig({
    required this.baseUrl,
    this.apiToken,
  });

  final String baseUrl;
  final String? apiToken;
}

/// 显示原生 iOS 26 风格的连接对话框，依次采集地址与 API 密钥
Future<DandanplayConnectionConfig?> showCupertinoDandanplayConnectionDialog({
  required BuildContext context,
  required DandanplayRemoteProvider provider,
}) async {
  final l10n = context.l10n;
  final bool hasExisting = provider.serverUrl?.isNotEmpty == true;
  final String dialogTitle = hasExisting
      ? l10n.dandanRemoteManageAccessTitle
      : l10n.dandanRemoteConnectAccessTitle;

  final String? baseUrl = await showCupertinoDialog<String>(
    context: context,
    builder: (context) => IOS26AlertDialog(
      title: dialogTitle,
      message: l10n.dandanRemoteAddressPrompt,
      input: AdaptiveAlertDialogInput(
        placeholder: l10n.dandanRemoteAddressPlaceholder,
        initialValue: provider.serverUrl ?? '',
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

  final String trimmedBaseUrl = baseUrl?.trim() ?? '';
  if (trimmedBaseUrl.isEmpty) {
    return null;
  }
  if (!context.mounted) {
    return null;
  }

  final String actionLabel = hasExisting ? l10n.save : l10n.connectAction;

  final String? token = await showCupertinoDialog<String>(
    context: context,
    builder: (context) => IOS26AlertDialog(
      title: l10n.dandanRemoteApiTokenOptionalTitle,
      message: l10n.dandanRemoteApiTokenPrompt(actionLabel),
      input: AdaptiveAlertDialogInput(
        placeholder: provider.tokenRequired
            ? l10n.enterApiToken
            : l10n.optionalApiTokenHint,
        obscureText: true,
      ),
      actions: [
        AlertAction(
          title: l10n.cancel,
          style: AlertActionStyle.cancel,
          onPressed: () {},
        ),
        AlertAction(
          title: actionLabel,
          style: AlertActionStyle.primary,
          onPressed: () {},
        ),
      ],
    ),
  );

  if (token == null) {
    return null;
  }

  final String trimmedToken = token.trim();
  return DandanplayConnectionConfig(
    baseUrl: trimmedBaseUrl,
    apiToken: trimmedToken.isEmpty ? null : trimmedToken,
  );
}
