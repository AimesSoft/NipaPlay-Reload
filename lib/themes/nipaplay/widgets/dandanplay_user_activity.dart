import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/widgets/user_activity/material_user_activity.dart';
import 'package:nipaplay/widgets/user_activity/fluent_user_activity.dart';

/// 用户活动记录组件的主题适配器
/// 根据当前UI主题自动选择Material或Fluent版本
class DandanplayUserActivity extends StatelessWidget {
  const DandanplayUserActivity({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UIThemeProvider>(
      builder: (context, uiThemeProvider, child) {
        if (uiThemeProvider.isFluentUITheme) {
          return const FluentUserActivity();
        } else {
          return const MaterialUserActivity();
        }
      },
    );
  }
}