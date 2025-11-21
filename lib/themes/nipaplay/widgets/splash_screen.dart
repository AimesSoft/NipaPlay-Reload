import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _version = '加载中...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = info.version;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _version = '获取失败';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode 
        ? const Color.fromARGB(255, 30, 30, 30) 
        : Colors.white;
    final textColor = isDarkMode 
        ? const Color.fromARGB(150, 255, 255, 255) 
        : const Color.fromARGB(75, 22, 22, 22);

    return Container(
      color: backgroundColor,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo512.png', 
              width: 128, 
              height: 128,
              color: isDarkMode ? Colors.white.withOpacity(0.8) : null,
              colorBlendMode: isDarkMode ? BlendMode.modulate : null,
            ),
            const SizedBox(height: 24),
            Image.asset(
              'assets/logo.png', 
              width: 200,
              color: isDarkMode ? Colors.white.withOpacity(0.8) : null,
              colorBlendMode: isDarkMode ? BlendMode.modulate : null,
            ),
            const SizedBox(height: 16),
            Text(
              'v$_version',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(
                fontSize: 16,
                color: textColor,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 