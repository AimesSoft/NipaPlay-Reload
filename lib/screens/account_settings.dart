import 'package:flutter/material.dart';
import 'package:nipaplay/services/settings_service.dart';
import 'package:nipaplay/widgets/login_window.dart';
import 'package:nipaplay/widgets/rounded_button.dart';
import 'package:nipaplay/utils/theme_utils.dart'; // 引入我们刚刚创建的文件
import 'package:nipaplay/widgets/rounded_container.dart'; // 导入 RoundedContainer

class AccountSettings extends StatelessWidget {
  final SettingsService settingsService;

  const AccountSettings({super.key, required this.settingsService});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "账号设置",
          style: getTitleTextStyle(context), // 动态设置字体样式
        ),
        RoundedContainer(
          // 使用 RoundedContainer 包裹按钮行
          child: Row(
            children: [
              RoundedButton(
                text: "登录弹弹Play账号",
                onPressed: () {
                  showLoginDialog(context, '登录弹弹Play');
                },
              ),
              const SizedBox(width: 10),
              RoundedButton(
                text: "登录Bangumi账号",
                onPressed: () {
                  showLoginDialog(context, '登录Bangumi');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
