// about_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';

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
        BlurSnackBar.show(context, '无法打开链接: $urlString');
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
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24.0),
      child: ConstrainedBox( // Limit max width for better readability on wide screens
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start, // Change to start
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40), // Add some space at the top
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
                _buildRichText(
                  context,
                  [
                    const TextSpan(text: '感谢开发者 '),
                    TextSpan(text: 'Sakiko', style: TextStyle(color: Colors.lightBlueAccent[100], fontWeight: FontWeight.bold)),
                    const TextSpan(text: '！提供了Emby和Jellyfin的媒体库支持。'),
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
                  onTap: () => _launchURL('https://www.github.com/MCDFsteve/NipaPlay-Reload'),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ionicons.logo_github, color: Colors.white.withOpacity(0.8), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'MCDFsteve/NipaPlay-Reload',
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
    );
  }

  Widget _buildInfoCard({required BuildContext context, String? title, required List<Widget> children}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 25,
          sigmaY: 25,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withOpacity(0.3),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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