import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart'; // 假设 globals.dart 中定义了 isMobile
import 'package:nipaplay/widgets/navigation_bar.dart' as navigation_bar_widgets;
import 'package:nipaplay/screens/setting_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度
    double screenWidth = MediaQuery.of(context).size.width;
    // 使用screenWidth来判断是否为移动端，替代原来的isMobile
    bool isMobileScreen = screenWidth < mobileThreshold;

    return Scaffold(
      body: isMobileScreen
          ? Stack(
              children: [
                SettingScreen(),
                const Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: navigation_bar_widgets.NavigationBar(),
                ),
              ],
            )
          : Row(
              children: [
                const navigation_bar_widgets.NavigationBar(),
                Expanded(child: SettingScreen()),
              ],
            ),
    );
  }
}