import 'dart:ui';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, SystemMouseCursors;
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nipaplay/services/update_service.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';

class CupertinoAboutPage extends StatefulWidget {
  const CupertinoAboutPage({super.key});

  @override
  State<CupertinoAboutPage> createState() => _CupertinoAboutPageState();
}

class _CupertinoAboutPageState extends State<CupertinoAboutPage> {
  String _version = '加载中…';
  UpdateInfo? _updateInfo;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _checkForUpdates();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _version = '获取失败';
      });
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final updateInfo = await UpdateService.checkForUpdates();
      if (!mounted) return;
      setState(() {
        _updateInfo = updateInfo;
      });
    } catch (_) {
      // ignore silently
    }
  }

  Future<void> _launchURL(String urlString) async {
    final uri = Uri.parse(urlString);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      BlurSnackBar.show(context, '无法打开链接: $urlString');
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final labelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final secondaryColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );

    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(
        title: '关于',
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.top + 48,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildHeader(context, labelColor, secondaryColor),
                      const SizedBox(height: 28),
                      _buildRichSection(
                        context,
                        title: null,
                        content: const [
                          TextSpan(text: 'NipaPlay，名字来自《寒蝉鸣泣之时》中古手梨花的口头禅 "'),
                          TextSpan(
                            text: 'にぱ〜☆',
                            style: TextStyle(
                              color: CupertinoColors.systemPink,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          TextSpan(
                            text:
                                '"。为了解决我在 macOS、Linux、iOS 上看番不便的问题，我创造了 NipaPlay。',
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildRichSection(
                        context,
                        title: '致谢',
                        content: const [
                          TextSpan(text: '感谢弹弹play (DandanPlay) 以及开发者 '),
                          TextSpan(
                            text: 'Kaedei',
                            style: TextStyle(
                              color: CupertinoColors.activeBlue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(text: ' 提供的接口与开发帮助。\n\n'),
                          TextSpan(text: '感谢开发者 '),
                          TextSpan(
                            text: 'Sakiko',
                            style: TextStyle(
                              color: CupertinoColors.activeBlue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(text: ' 帮助实现 Emby 与 Jellyfin 媒体库支持。'),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _buildCommunitySection(context, labelColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Color labelColor,
    Color secondaryColor,
  ) {
    final hasUpdate = _updateInfo?.hasUpdate ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'assets/logo.png',
          height: 110,
          errorBuilder: (_, __, ___) => Icon(
            Ionicons.image_outline,
            size: 96,
            color: secondaryColor,
          ),
        ),
        const SizedBox(height: 18),
        GestureDetector(
          onTap:
              hasUpdate ? () => _launchURL(_updateInfo!.releaseUrl) : null,
          child: MouseRegion(
            cursor:
                hasUpdate ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Text(
                  'NipaPlay Reload 当前版本：$_version',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (hasUpdate)
                  Positioned(
                    top: -10,
                    right: -12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemRed,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33999999),
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRichSection(
    BuildContext context, {
    required String? title,
    required List<TextSpan> content,
  }) {
    final base = CupertinoTheme.of(context)
        .textTheme
        .textStyle
        .copyWith(height: 1.6);

    return AdaptiveFormSection.insetGrouped(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(
                  title,
                  style: base.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              RichText(
                text: TextSpan(
                  style: base.copyWith(
                    fontSize: 15,
                    color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label,
                      context,
                    ),
                  ),
                  children: content,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCommunitySection(BuildContext context, Color labelColor) {
    final entries = [
      (
        icon: Ionicons.logo_github,
        label: 'MCDFsteve/NipaPlay-Reload',
        url: 'https://www.github.com/MCDFsteve/NipaPlay-Reload',
      ),
      (
        icon: Ionicons.chatbubbles_outline,
        label: 'QQ群: 961207150',
        url: 'https://qm.qq.com/q/w9j09QJn4Q',
      ),
      (
        icon: Ionicons.globe_outline,
        label: 'NipaPlay 官方网站',
        url: 'https://nipaplay.aimes-soft.com',
      ),
    ];

    return AdaptiveFormSection.insetGrouped(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '开源与社区',
            style: CupertinoTheme.of(context)
                .textTheme
                .textStyle
                .copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        ...entries.map(
          (item) => AdaptiveListTile(
            leading: Icon(
              item.icon,
              color: labelColor,
            ),
            title: Text(item.label),
            trailing: const Icon(CupertinoIcons.arrow_up_right),
            onTap: () => _launchURL(item.url),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            '欢迎贡献代码，或将应用发布到更多平台。不会 Dart 也没关系，借助 AI 编程同样可以。',
            style: CupertinoTheme.of(context)
                .textTheme
                .textStyle
                .copyWith(
                  fontSize: 13,
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel,
                    context,
                  ),
                ),
          ),
        ),
      ],
    );
  }
}
