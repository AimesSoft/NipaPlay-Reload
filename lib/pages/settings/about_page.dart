// about_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_card.dart';
import 'package:nipaplay/services/update_service.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '加载中...';
  UpdateInfo? _updateInfo;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    // 静默检查更新，不显示加载状态
    _checkForUpdates();
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

  Future<void> _checkForUpdates() async {
    // 静默检查更新，不显示加载状态
    debugPrint('开始检查更新...');
    try {
      final updateInfo = await UpdateService.checkForUpdates();
      debugPrint('检查更新完成: 当前版本=${updateInfo.currentVersion}, 最新版本=${updateInfo.latestVersion}, 有更新=${updateInfo.hasUpdate}');
      if (updateInfo.hasUpdate) {
        debugPrint('发现新版本: ${updateInfo.latestVersion}, 下载链接: ${updateInfo.releaseUrl}');
      }
      if (updateInfo.error != null) {
        debugPrint('检查更新时出现错误: ${updateInfo.error}');
      }
      if (mounted) {
        setState(() {
          _updateInfo = updateInfo;
        });
      }
    } catch (e) {
      // 静默处理错误，不影响用户体验
      debugPrint('检查更新失败: $e');
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
            // 版本信息，点击跳转到releases页面（如果有更新）
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: _updateInfo?.hasUpdate == true 
                        ? () => _launchURL(_updateInfo!.releaseUrl) 
                        : null,
                    child: MouseRegion(
                      cursor: _updateInfo?.hasUpdate == true 
                          ? SystemMouseCursors.click 
                          : SystemMouseCursors.basic,
                      child: Text(
                        'NipaPlay Reload 当前版本: $_version',
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  // NEW 标识 - 独立定位
                  if (_updateInfo?.hasUpdate == true)
                    Positioned(
                      top: -8,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Text(
                          'NEW',
                          locale:Locale("zh-Hans","zh"),
style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _buildInfoCard(
              context: context,
              children: [
                _buildRichText(
                  context,
                  [
                    const TextSpan(text: 'NipaPlay,名字来自《寒蝉鸣泣之时》里古手梨花 (ふるて りか) 的标志性口头禅 "'),
                    TextSpan(text: 'にぱ〜☆', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.pinkAccent[100], fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
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
                    TextSpan(text: 'Kaedei', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.lightBlueAccent[100], fontWeight: FontWeight.bold)),
                    const TextSpan(text: '！提供了 NipaPlay 相关api接口和开发帮助。'),
                  ]
                ),
                _buildRichText(
                  context,
                  [
                    const TextSpan(text: '感谢开发者 '),
                    TextSpan(text: 'Sakiko', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.lightBlueAccent[100], fontWeight: FontWeight.bold)),
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
                          locale:Locale("zh-Hans","zh"),
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
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _launchURL('https://qm.qq.com/q/w9j09QJn4Q'),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ionicons.chatbubbles_outline, color: Colors.white.withOpacity(0.8), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'QQ群: 961207150',
                          locale:Locale("zh-Hans","zh"),
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
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _launchURL('https://nipaplay.aimes-soft.com'),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ionicons.globe_outline, color: Colors.white.withOpacity(0.8), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'NipaPlay 官方网站',
                          locale:Locale("zh-Hans","zh"),
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
    return SettingsCard(
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