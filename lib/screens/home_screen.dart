import 'package:flutter/material.dart';
import 'package:nipaplay/screens/setting_screen.dart';
import 'package:nipaplay/widgets/navigation_bar.dart'as navigation_bar_widgets;
// 假设 globals.dart 中定义了 barPageNumber

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度
    double screenWidth = MediaQuery.of(context).size.width;
    bool isMobileScreen = screenWidth < 550;  // 判断是否为移动端

    return Scaffold(
      body: isMobileScreen
          ? Stack(
              children: [
                SettingScreen(),  // 这会根据 barPageNumber 显示对应的页面
                const Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: navigation_bar_widgets.NavigationBar(
                  ),
                ),
              ],
            )
          : Row(
              children: [
                const navigation_bar_widgets.NavigationBar(),
                Expanded(child: SettingScreen()),  // 根据 barPageNumber 动态显示内容
              ],
            ),
    );
  }
}