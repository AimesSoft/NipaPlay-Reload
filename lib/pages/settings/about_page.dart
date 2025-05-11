// about_page.dart
import 'dart:ui'; // 需要 ImageFilter
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
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

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      // Log or show a snackbar if url can't be launched
      //debugPrint('Could not launch $urlString');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $urlString')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Using a dark theme context for text styles as an example, 
    // assuming the page is shown over a dark-ish blurred background from TabBarView
    final textTheme = Theme.of(context).textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );
    // Use getTextStyle if it provides better themed styles
    // final baseTextStyle = getTextStyle(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center( // Center the content if the page itself is not centered
        child: ConstrainedBox( // Limit max width for better readability on wide screens
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                'assets/logo.png', // Ensure this path is correct
                height: 120, // Adjust size as needed
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Ionicons.image_outline, size: 100, color: Colors.white70); // Placeholder if logo fails
                },
              ),
              const SizedBox(height: 24),
              Text(
                'NipaPlay Reload 当前版本: $_version', // App Name
                style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              _buildInfoCard(
                context: context,
                children: [
                  _buildRichText(
                    context,
                    [
                      const TextSpan(text: 'NipaPlay,名字来自《寒蝉鸣泣之时》里古手梨花 (ふるて りか) 的标志性口头禅 "'),
                      TextSpan(text: 'にぱ〜☆', style: TextStyle(color: Colors.pinkAccent[100], fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                      const TextSpan(text: '" \n为解决我 macOS和Linux 、IOS看番不便。我创造了 NipaPlay。'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              _buildInfoCard(
                context: context,
                title: '致谢',
                children: [
                   _buildRichText(
                    context,
                    [
                      const TextSpan(text: '感谢弹弹play (DandanPlay) 和开发者 '),
                      TextSpan(text: 'Kaedei', style: TextStyle(color: Colors.lightBlueAccent[100], fontWeight: FontWeight.bold)),
                      const TextSpan(text: '！提供了 NipaPlay 相关api接口和开发帮助。'),
                    ]
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              _buildInfoCard(
                context: context,
                title: '开源与社区',
                children: [
                  _buildRichText(
                    context,
                    [
                      const TextSpan(text: '欢迎贡献代码，或者将其发布到各个软件仓库。(不会 Dart 也没关系，用 Cursor 这种ai编程也是可以的。)'),
                    ]
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _launchURL('https://www.github.com/MCFsteve/NipaPlay-Reload'),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Ionicons.logo_github, color: Colors.white.withOpacity(0.8), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'MCFsteve/NipaPlay-Reload',
                            style: TextStyle(
                              color: Colors.cyanAccent[100],
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.cyanAccent[100]?.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({required BuildContext context, String? title, required List<Widget> children}) {
    return ClipRRect( // ClipRRect 用于实现圆角效果
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0), // 调整模糊程度
        child: Container(
          // BackdropFilter 需要其子项至少部分透明才能看到模糊效果
          // 所以 Container 的颜色需要有透明度
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 211, 211, 211).withOpacity(0.25), // 半透明背景色
            // 不需要再在这里定义 borderRadius 或 border，因为 ClipRRect 处理了圆角
            // 如果还需要边框，可以嵌套一个有边框的Container，或者在ClipRRect外层再包一个装饰性的Container
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // 使Column高度包裹内容
            children: [
              if (title != null) ...[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white, 
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRichText(BuildContext context, List<InlineSpan> spans) {
    return RichText(
      textAlign: TextAlign.start, // Or TextAlign.justify if preferred
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Colors.white.withOpacity(0.9), 
          height: 1.6, // Improved line spacing
        ), // Default text style for spans
        children: spans,
      ),
    );
  }
}