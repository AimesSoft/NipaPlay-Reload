import 'package:flutter/material.dart';
import 'package:nipaplay/pages/account/material_account_page.dart';

/// 账号设置页面的统一入口，使用Material Design版本
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialAccountPage();
  }
}