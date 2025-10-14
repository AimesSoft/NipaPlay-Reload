import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

class AccountPageSelectionSheet extends StatelessWidget {
  const AccountPageSelectionSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const AccountPageSelectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.4,
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: GlassmorphicContainer(
        width: double.infinity,
        height: double.infinity,
        borderRadius: 20,
        blur: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 20 : 0,
        alignment: Alignment.center,
        border: 1,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.3),
            Colors.white.withOpacity(0.25),
          ],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.5),
            Colors.white.withOpacity(0.5),
          ],
        ),
        child: Column(
          children: [
            // 拖拽条
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 标题
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                '选择账号页面',
                locale: Locale("zh-Hans", "zh"),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // 选项列表
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // 弹弹play账号选项
                    _buildPageOptionWithImage(
                      imageAsset: 'assets/dandanplay.png',
                      title: '弹弹play账号',
                      subtitle: '管理登录状态和用户活动',
                      color: const Color(0xFF53A8DC), // 弹弹play官方色调
                      onTap: () => Navigator.of(context).pop('dandanplay'),
                    ),

                    const SizedBox(height: 12),

                    // Bangumi同步选项
                    _buildPageOptionWithImage(
                      imageAsset: 'assets/bangumi.png',
                      title: 'Bangumi同步',
                      subtitle: '同步观看记录到Bangumi',
                      color: const Color(0xFFEB4994), // Bangumi官方色调
                      onTap: () => Navigator.of(context).pop('bangumi'),
                    ),

                    // 添加底部边距，确保最后一项可以完全显示
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageOptionWithImage({
    required String imageAsset,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              // Logo图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.8), // 提高透明度到80%，让颜色更亮
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Image.asset(
                    imageAsset,
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // 文本信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      locale: const Locale("zh-Hans", "zh"),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // 箭头图标
              Icon(
                Ionicons.chevron_forward,
                size: 16,
                color: Colors.white.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}