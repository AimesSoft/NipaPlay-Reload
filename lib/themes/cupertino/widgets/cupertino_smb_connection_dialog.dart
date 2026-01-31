import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

import 'package:nipaplay/services/smb_service.dart';

class CupertinoSmbConnectionDialog {
  static Future<bool?> show(
    BuildContext context, {
    SMBConnection? editConnection,
    Future<bool> Function(SMBConnection)? onSave,
  }) async {
    final bool isEditing = editConnection != null;
    final String title = isEditing ? '编辑 SMB 服务器' : '添加 SMB 服务器';

    final String? hostInput = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => IOS26AlertDialog(
        title: title,
        message: '请输入主机/IP 地址（下一步可设置端口）。',
        input: AdaptiveAlertDialogInput(
          placeholder: '例如：192.168.1.10 或 nas.local 或 [fe80::1]',
          initialValue: editConnection?.host ?? '',
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

    if (hostInput == null) return null;
    final String host = hostInput.trim();
    if (host.isEmpty) return false;

    if (!context.mounted) return false;

    final String? portInput = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => IOS26AlertDialog(
        title: '端口',
        message: 'SMB 默认端口为 445，如使用非标准端口可在此修改。',
        input: AdaptiveAlertDialogInput(
          placeholder: '默认 445',
          initialValue: (editConnection?.port ?? 445).toString(),
          keyboardType: TextInputType.number,
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

    if (portInput == null) return null;
    final String trimmedPort = portInput.trim();
    final int port = trimmedPort.isEmpty ? 445 : int.tryParse(trimmedPort) ?? 0;
    if (port <= 0 || port > 65535) {
      return false;
    }

    if (!context.mounted) return false;

    final String usernameSeed = () {
      final base = editConnection?.username.trim() ?? '';
      final domain = editConnection?.domain.trim() ?? '';
      if (base.isEmpty) return '';
      if (domain.isEmpty) return base;
      return '$domain\\\\$base';
    }();

    final String? usernameInput = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => IOS26AlertDialog(
        title: title,
        message: '用户名可留空以匿名访问；也可输入 DOMAIN\\\\user。',
        input: AdaptiveAlertDialogInput(
          placeholder: '可留空（匿名）',
          initialValue: usernameSeed,
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

    if (usernameInput == null) return null;
    final (domain, username) = _splitDomainUsername(usernameInput.trim());

    if (!context.mounted) return false;

    final String actionLabel = isEditing ? '保存' : '添加';
    final String? passwordInput = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => IOS26AlertDialog(
        title: title,
        message: '密码可留空以匿名访问。',
        input: AdaptiveAlertDialogInput(
          placeholder: '可留空',
          initialValue: editConnection?.password ?? '',
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
            title: actionLabel,
            style: AlertActionStyle.primary,
            onPressed: () {},
          ),
        ],
      ),
    );

    if (passwordInput == null) return null;

    final String name = isEditing
        ? editConnection!.name
        : (port != 445 ? '$host:$port' : host);

    final connection = SMBConnection(
      name: name,
      host: host,
      port: port,
      username: username,
      password: passwordInput,
      domain: domain,
    );

    if (onSave != null) {
      return onSave(connection);
    }

    if (isEditing) {
      return SMBService.instance.updateConnection(editConnection!.name, connection);
    }
    return SMBService.instance.addConnection(connection);
  }

  static (String domain, String username) _splitDomainUsername(String input) {
    if (input.isEmpty) return ('', '');
    final match = RegExp(r'^([^\\\\/]+)[\\\\/](.+)$').firstMatch(input);
    if (match == null) return ('', input);
    final domain = match.group(1)?.trim() ?? '';
    final username = match.group(2)?.trim() ?? '';
    return (domain, username);
  }
}
