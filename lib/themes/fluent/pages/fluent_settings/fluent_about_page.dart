import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/constants/acknowledgements.dart';
import 'package:nipaplay/themes/fluent/widgets/fluent_info_bar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';

class FluentAboutPage extends StatefulWidget {
  const FluentAboutPage({super.key});

  @override
  State<FluentAboutPage> createState() => _FluentAboutPageState();
}

class _FluentAboutPageState extends State<FluentAboutPage> {
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
      if (mounted) {
        FluentInfoBar.show(
          context,
          '无法打开链接',
          content: urlString,
          severity: InfoBarSeverity.error,
        );
      }
    }
  }

  void _showAppreciationQR() {
    BlurDialog.show(
      context: context,
      title: '赞赏码',
      contentWidget: Container(
        constraints: const BoxConstraints(
          maxWidth: 300,
          maxHeight: 400,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'others/赞赏码.jpg',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: material.Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Ionicons.image_outline,
                      size: 60,
                      color: material.Colors.white70,
                    ),
                    SizedBox(height: 10),
                    Text(
                      '赞赏码图片加载失败',
                      style: TextStyle(
                        color: material.Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(
        title: Text('关于'),
      ),
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                const SizedBox(height: 40),
                
                // 应用logo和名称
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '应用信息',
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                        const SizedBox(height: 16),
                        
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: material.Image.asset(
                                  'assets/logo.png',
                                  width: 120,
                                  fit: BoxFit.fitWidth,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(FluentIcons.app_icon_default, size: 120);
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'NipaPlay Reload',
                                      style: FluentTheme.of(context).typography.title,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '当前版本: $_version',
                                      style: FluentTheme.of(context).typography.subtitle,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '一个现代化的跨平台视频播放应用',
                                      style: FluentTheme.of(context).typography.caption,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '基于Flutter开发，支持Windows、macOS、Linux、Android、iOS等多平台',
                                      style: FluentTheme.of(context).typography.caption,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // 应用介绍
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '应用介绍',
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                        const SizedBox(height: 12),
                        material.RichText(
                          text: TextSpan(
                            style: FluentTheme.of(context).typography.body,
                            children: [
                              const TextSpan(text: 'NipaPlay,名字来自《寒蝉鸣泣之时》里古手梨花 (ふるて りか) 的标志性口头禅 "'),
                              TextSpan(
                                text: 'にぱ〜☆',
                                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                  color: material.Colors.pinkAccent[100],
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const TextSpan(text: '" \n为解决我 macOS和Linux 、IOS看番不便。我创造了 NipaPlay。'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // 致谢
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '致谢',
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                        const SizedBox(height: 12),
                        material.RichText(
                          text: TextSpan(
                            style: FluentTheme.of(context).typography.body,
                            children: [
                              const TextSpan(text: '感谢弹弹play (DandanPlay) 和开发者 '),
                              TextSpan(
                                text: 'Kaedei',
                                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                  color: material.Colors.lightBlueAccent[100],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const TextSpan(text: '！提供了 NipaPlay 相关api接口和开发帮助。'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        material.RichText(
                          text: TextSpan(
                            style: FluentTheme.of(context).typography.body,
                            children: [
                              const TextSpan(text: '感谢开发者 '),
                              TextSpan(
                                text: 'Sakiko',
                                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                  color: material.Colors.lightBlueAccent[100],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const TextSpan(text: '！提供了Emby和Jellyfin的媒体库支持。'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '感谢下列用户的赞助支持：',
                          style: FluentTheme.of(context).typography.body,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: kAcknowledgementNames
                              .map((name) => _buildAcknowledgementBadge(context, name))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 赞助支持
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '赞助支持',
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '如果你喜欢 NipaPlay 并且希望支持项目的持续开发，欢迎通过爱发电进行赞助。',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '赞助者的名字将会出现在项目的 README 文件和每次软件更新后的关于页面名单中。',
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _launchURL('https://afdian.com/a/irigas'),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FluentIcons.heart_fill, color: material.Colors.pink),
                              SizedBox(width: 8),
                              Text('爱发电赞助页面'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _showAppreciationQR,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Ionicons.qr_code, color: material.Colors.orange),
                              SizedBox(width: 8),
                              Text('赞赏码'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 开源与社区
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '开源与社区',
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '欢迎贡献代码，或者将其发布到各个软件仓库。(不会 Dart 也没关系，用 Cursor 这种ai编程也是可以的。)',
                        ),
                        const SizedBox(height: 16),
                        HyperlinkButton(
                          onPressed: () => _launchURL('https://www.github.com/MCDFsteve/NipaPlay-Reload'),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FluentIcons.code),
                              SizedBox(width: 8),
                              Text('MCDFsteve/NipaPlay-Reload'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        HyperlinkButton(
                          onPressed: () {
                            // 复制群号到剪贴板并提示用户
                            Clipboard.setData(const ClipboardData(text: '961207150'));
                            FluentInfoBar.show(
                              context,
                              '群号已复制',
                              content: 'QQ群号 961207150 已复制到剪贴板，请手动添加',
                              severity: InfoBarSeverity.info,
                            );
                          },
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FluentIcons.chat),
                              SizedBox(width: 8),
                              Text('QQ 群组 (961207150)'),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: () => _launchURL('https://nipaplay.aimes-soft.com'),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FluentIcons.globe),
                              SizedBox(width: 8),
                              Text('访问官网'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAcknowledgementBadge(BuildContext context, String name) {
    final textStyle = FluentTheme.of(context).typography.bodyStrong?.copyWith(
          color: FluentTheme.of(context).resources.textFillColorPrimary,
          fontWeight: FontWeight.w600,
        );
    final borderColor = FluentTheme.of(context).resources.dividerStrokeColorDefault;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: material.Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Ionicons.ribbon_outline,
            size: 16,
            color:
                material.Colors.amberAccent[100] ?? material.Colors.amberAccent,
          ),
          const SizedBox(width: 8),
          Text(name, style: textStyle),
        ],
      ),
    );
  }
}
