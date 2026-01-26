import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

class AccountPageSelectionSheet extends StatelessWidget {
  const AccountPageSelectionSheet({super.key});

  static Future<String?> show(BuildContext context) {
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    return NipaplayWindow.show<String>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      child: const AccountPageSelectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
    final sheetHeight = screenSize.height * 0.4;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = colorScheme.onSurface;
    final subTextColor = colorScheme.onSurface.withOpacity(0.7);
    final borderColor = colorScheme.onSurface.withOpacity(isDark ? 0.14 : 0.2);
    final cardColor =
        isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04);

    return NipaplayWindowScaffold(
      maxWidth: dialogWidth,
      maxHeightFactor: (sheetHeight / screenSize.height).clamp(0.4, 0.8),
      onClose: () => Navigator.of(context).maybePop(),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: SizedBox(
          height: sheetHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选择账号页面',
                    locale: const Locale("zh-Hans", "zh"),
                    style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ) ??
                        TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.left,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildPageOptionWithImage(
                          imageAsset: 'assets/dandanplay.png',
                          title: '弹弹play账号',
                          subtitle: '管理登录状态和用户活动',
                          color: const Color(0xFF53A8DC),
                          textColor: textColor,
                          subTextColor: subTextColor,
                          borderColor: borderColor,
                          cardColor: cardColor,
                          onTap: () => Navigator.of(context).pop('dandanplay'),
                        ),
                        const SizedBox(height: 12),
                        _buildPageOptionWithImage(
                          imageAsset: 'assets/bangumi.png',
                          title: 'Bangumi同步',
                          subtitle: '同步观看记录到Bangumi',
                          color: const Color(0xFFEB4994),
                          textColor: textColor,
                          subTextColor: subTextColor,
                          borderColor: borderColor,
                          cardColor: cardColor,
                          onTap: () => Navigator.of(context).pop('bangumi'),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageOptionWithImage({
    required String imageAsset,
    required String title,
    required String subtitle,
    required Color color,
    required Color textColor,
    required Color subTextColor,
    required Color borderColor,
    required Color cardColor,
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
              color: borderColor,
              width: 0.5,
            ),
            color: cardColor,
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
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      locale: const Locale("zh-Hans", "zh"),
                      style: TextStyle(
                        color: subTextColor,
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
                color: textColor.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
