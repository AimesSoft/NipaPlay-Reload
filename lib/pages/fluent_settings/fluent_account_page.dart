import 'package:flutter/widgets.dart';
import 'package:nipaplay/pages/account/fluent_account_page.dart' as account;

/// FluentUI账号设置页面的统一入口
class FluentAccountPage extends StatelessWidget {
  const FluentAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const account.FluentAccountPage();
  }
}