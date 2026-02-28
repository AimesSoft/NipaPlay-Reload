import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

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
Future<DandanplayConnectionConfig?>
    showCupertinoDandanplayConnectionDialog({
  required BuildContext context,
  required DandanplayRemoteProvider provider,
}) async {
  final bool hasExisting = provider.serverUrl?.isNotEmpty == true;
  final String dialogTitle =
      hasExisting ? '管理弹弹play远程访问' : '连接弹弹play远程访问';

  final String? baseUrl = await showCupertinoDialog<String>(
    context: context,
    builder: (context) => IOS26AlertDialog(
      title: dialogTitle,
      message: '请输入桌面端显示的远程服务地址。',
      input: AdaptiveAlertDialogInput(
        placeholder: '例如：http://192.168.1.2:23333',
        initialValue: provider.serverUrl ?? '',
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

  final String trimmedBaseUrl = baseUrl?.trim() ?? '';
  if (trimmedBaseUrl.isEmpty) {
    return null;
  }

  final String actionLabel = hasExisting ? '保存' : '连接';

  final String? token = await showCupertinoDialog<String>(
    context: context,
    builder: (context) => IOS26AlertDialog(
      title: 'API 密钥（可选）',
      message:
          '如已在弹弹play 桌面端启用 API 验证，请输入对应的密钥；未启用可直接点击$actionLabel。',
      input: AdaptiveAlertDialogInput(
        placeholder:
            provider.tokenRequired ? '请输入 API 密钥' : '可留空，按需填写',
        obscureText: true,
      ),
      actions: [
        AlertAction(
          title: '取消',
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
