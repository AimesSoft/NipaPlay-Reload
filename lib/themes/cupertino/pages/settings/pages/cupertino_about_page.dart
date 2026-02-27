import 'dart:ui';

import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:flutter/material.dart' show SystemMouseCursors;
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nipaplay/services/update_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/constants/acknowledgements.dart';

import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/widgets/adaptive_markdown.dart';

class CupertinoAboutPage extends StatefulWidget {
  const CupertinoAboutPage({super.key});

  @override
  State<CupertinoAboutPage> createState() => _CupertinoAboutPageState();
}

class _CupertinoAboutPageState extends State<CupertinoAboutPage> {
  String _version = '加载中…';
  UpdateInfo? _updateInfo;
  bool _isCheckingUpdate = false;

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

  String _formatPublishedAt(String publishedAt) {
    if (publishedAt.trim().isEmpty) return '';
    try {
      final dt = DateTime.parse(publishedAt).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d $hh:$mm';
    } catch (_) {
      return publishedAt;
    }
  }

  Future<void> _showUpdateDialog(UpdateInfo info) async {
    final notes = info.releaseNotes.trim().isNotEmpty
        ? info.releaseNotes.trim()
        : '暂无更新内容';
    final publishedAt = _formatPublishedAt(info.publishedAt);
    final brightness = CupertinoTheme.brightnessOf(context);
    final notesBackground = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGrey6,
      context,
    );
    final notesBorder = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );
    final notesTextColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final linkColor = CupertinoTheme.of(context).primaryColor;

    await BlurDialog.show(
      context: context,
      title: info.hasUpdate ? '发现新版本 ${info.latestVersion}' : '当前已是最新版本',
      contentWidget: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本: ${info.currentVersion}'),
            Text('最新版本: ${info.latestVersion}'),
            if (info.releaseName.trim().isNotEmpty)
              Text('版本名称: ${info.releaseName.trim()}'),
            if (publishedAt.isNotEmpty) Text('发布时间: $publishedAt'),
            if (info.error != null && info.error!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                info.error!.trim(),
                style: const TextStyle(
                  color: CupertinoColors.systemRed,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              '更新内容',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: notesBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: notesBorder),
              ),
              child: SizedBox(
                height: 220,
                child: SingleChildScrollView(
                  child: AdaptiveMarkdown(
                    data: notes,
                    brightness: brightness,
                    baseTextStyle:
                        CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                              fontSize: 13,
                              height: 1.4,
                              color: notesTextColor,
                            ),
                    linkColor: linkColor,
                    onTapLink: (href) {
                      _launchURL(href);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (info.releaseUrl.trim().isNotEmpty)
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(context).pop();
              _launchURL(info.releaseUrl);
            },
            child: const Text('跳转'),
          ),
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _manualCheckForUpdates() async {
    if (_isCheckingUpdate) return;
    setState(() {
      _isCheckingUpdate = true;
    });

    UpdateInfo? info;
    try {
      info = await UpdateService.checkForUpdates();
    } catch (_) {
      info = null;
    }

    if (!mounted) return;
    setState(() {
      _isCheckingUpdate = false;
      if (info != null) {
        _updateInfo = info;
      }
    });

    if (info == null) {
      await BlurDialog.show(
        context: context,
        title: '检查更新失败',
        content: '请稍后再试',
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
      return;
    }

    await _showUpdateDialog(info);
  }

  Future<void> _launchURL(String urlString) async {
    final uri = Uri.parse(urlString);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '无法打开链接: $urlString',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  void _showAppreciationQR() {
    CupertinoBottomSheet.show(
      context: context,
      title: '赞赏码',
      heightRatio: 0.82,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final errorTextColor = CupertinoDynamicColor.resolve(
              CupertinoColors.secondaryLabel,
              context,
            );
            final errorIconColor = CupertinoDynamicColor.resolve(
              CupertinoColors.systemGrey,
              context,
            );
            final errorBackgroundColor = CupertinoDynamicColor.resolve(
              CupertinoColors.secondarySystemBackground,
              context,
            );

            return Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Image.asset(
                    'others/赞赏码.jpg',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: errorBackgroundColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Ionicons.image_outline,
                              size: 60,
                              color: errorIconColor,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '赞赏码图片加载失败',
                              style: TextStyle(
                                color: errorTextColor,
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
            );
          },
        ),
      ),
    );
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
    final accentColor = CupertinoTheme.of(context).primaryColor;

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
                        content: [
                          const TextSpan(
                            text: '感谢弹弹play (DandanPlay) 以及开发者 ',
                          ),
                          TextSpan(
                            text: 'Kaedei',
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const TextSpan(text: ' 提供的接口与开发帮助。\n\n'),
                          const TextSpan(text: '感谢开发者 '),
                          TextSpan(
                            text: 'Sakiko',
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const TextSpan(text: ' 帮助实现 Emby 与 Jellyfin 媒体库支持。'),
                        ],
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '感谢下列用户的赞助支持：',
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle
                                  .copyWith(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.label,
                                      context,
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: kAcknowledgementNames
                                  .map((name) =>
                                      _buildAcknowledgementPill(context, name))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildSponsorshipSection(context),
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
          onTap: hasUpdate ? () => _launchURL(_updateInfo!.releaseUrl) : null,
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
        const SizedBox(height: 12),
        CupertinoButton.filled(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          onPressed: _isCheckingUpdate ? null : _manualCheckForUpdates,
          child: _isCheckingUpdate
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoActivityIndicator(radius: 8),
                    SizedBox(width: 8),
                    Text('检测中…'),
                  ],
                )
              : const Text('检测更新'),
        ),
      ],
    );
  }

  Widget _buildRichSection(
    BuildContext context, {
    required String? title,
    required List<TextSpan> content,
    Widget? trailing,
  }) {
    final base =
        CupertinoTheme.of(context).textTheme.textStyle.copyWith(height: 1.6);

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: resolveSettingsSectionBackground(context),
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
              if (trailing != null) ...[
                const SizedBox(height: 12),
                trailing,
              ],
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

    final tileColor = resolveSettingsTileBackground(context);

    final List<Widget> children = [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          '开源与社区',
          style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
      _buildSettingsDivider(context),
    ];

    for (var i = 0; i < entries.length; i++) {
      final item = entries[i];
      children.add(
        CupertinoSettingsTile(
          leading: Icon(
            item.icon,
            color: labelColor,
          ),
          title: Text(item.label),
          trailing: Icon(
            CupertinoIcons.arrow_up_right,
            color: resolveSettingsIconColor(context),
          ),
          backgroundColor: tileColor,
          onTap: () => _launchURL(item.url),
        ),
      );
      if (i < entries.length - 1) {
        children.add(_buildSettingsDivider(context));
      }
    }

    children.addAll(const [
      SizedBox(height: 4),
    ]);

    children.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Text(
          '欢迎贡献代码，或将应用发布到更多平台。不会 Dart 也没关系，借助 AI 编程同样可以。',
          style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                fontSize: 13,
                color: CupertinoDynamicColor.resolve(
                  CupertinoColors.secondaryLabel,
                  context,
                ),
              ),
        ),
      ),
    );

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: resolveSettingsSectionBackground(context),
      children: children,
    );
  }

  Widget _buildSponsorshipSection(BuildContext context) {
    final Color tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: resolveSettingsSectionBackground(context),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '赞助支持',
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            '如果你喜欢 NipaPlay 并且希望支持项目的持续开发，欢迎通过爱发电进行赞助。',
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 14,
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.label,
                    context,
                  ),
                  height: 1.5,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            '赞助者的名字将会出现在项目的 README 文件和每次软件更新后的关于页面名单中。',
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 14,
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.label,
                    context,
                  ),
                  height: 1.5,
                ),
          ),
        ),
        _buildSettingsDivider(context),
        CupertinoSettingsTile(
          leading: const Icon(
            Ionicons.heart,
            color: CupertinoColors.systemPink,
          ),
          title: const Text('爱发电赞助页面'),
          trailing: Icon(
            CupertinoIcons.arrow_up_right,
            color: resolveSettingsIconColor(context),
          ),
          backgroundColor: tileColor,
          onTap: () => _launchURL('https://afdian.com/a/irigas'),
        ),
        _buildSettingsDivider(context),
        CupertinoSettingsTile(
          leading: const Icon(
            Ionicons.qr_code,
            color: CupertinoColors.systemOrange,
          ),
          title: const Text('赞赏码'),
          trailing: Icon(
            CupertinoIcons.chevron_forward,
            color: resolveSettingsIconColor(context),
          ),
          backgroundColor: tileColor,
          onTap: _showAppreciationQR,
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildAcknowledgementPill(BuildContext context, String name) {
    final baseStyle = CupertinoTheme.of(context).textTheme.textStyle;
    final labelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final fillColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemFill,
      context,
    );
    final iconColor = CupertinoDynamicColor.resolve(
      CupertinoColors.activeOrange,
      context,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: fillColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: labelColor.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.sparkles,
            size: 16,
            color: iconColor,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: baseStyle.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsDivider(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsetsDirectional.only(start: 20),
      color: resolveSettingsSeparatorColor(context),
    );
  }
}
