import 'package:flutter/material.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';

/// Opens login in the current route so the interrupted action can resume.
Future<bool> requestDandanplayLogin(BuildContext context) async {
  final result = await BlurLoginDialog.show(
    context,
    title: '登录弹弹play账号',
    fields: const [
      LoginField(key: 'username', label: '用户名/邮箱', hint: '请输入用户名或邮箱'),
      LoginField(key: 'password', label: '密码', isPassword: true),
    ],
    onLogin: (values) async {
      final result = await DandanplayService.login(
        values['username'] ?? '',
        values['password'] ?? '',
      );
      return LoginResult(
        success: result['success'] == true,
        message: result['message'] as String?,
      );
    },
  );
  return result == true;
}

class DandanplayLoginRequiredView extends StatelessWidget {
  const DandanplayLoginRequiredView({
    super.key,
    required this.onSignedIn,
    this.onClose,
  });

  final VoidCallback onSignedIn;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_circle_outlined, size: 44),
          const SizedBox(height: 12),
          const Text('登录后使用弹弹play在线服务', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('本地视频和已连接的媒体库无需登录，可返回继续播放。', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              AdaptiveMediaActionButton(
                label: '登录弹弹play',
                desktopIcon: Icons.login,
                autofocus: true,
                onPressed: () async {
                  if (await requestDandanplayLogin(context) &&
                      context.mounted) {
                    onSignedIn();
                  }
                },
              ),
              if (onClose != null)
                AdaptiveMediaActionButton(
                  label: '返回',
                  desktopIcon: Icons.arrow_back,
                  onPressed: onClose,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
