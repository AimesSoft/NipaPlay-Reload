// about_page.dart
import 'package:flutter/material.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/constants/acknowledgements.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/keyboard_activatable.dart';
import 'package:nipaplay/services/update_service.dart';
import 'package:nipaplay/widgets/adaptive_markdown.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/build_target_label.dart';
import 'package:nipaplay/widgets/about_version_banner_text.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final String _buildTargetLabel = getBuildTargetLabel();
  String _version = '';
  bool _versionLoadFailed = false;
  UpdateInfo? _updateInfo;
  bool _isCheckingUpdate = false;
  bool _isUpdateButtonHovered = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _checkForUpdatesInBackgroundIfEnabled();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = info.version;
          _versionLoadFailed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _versionLoadFailed = true;
        });
      }
    }
  }

  Future<void> _checkForUpdatesInBackgroundIfEnabled() async {
    final enabled = await UpdateService.isAutoCheckEnabled();
    if (!enabled || !mounted) return;
    // 静默检查更新，不显示加载状态
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    // 静默检查更新，不显示加载状态
    debugPrint('开始检查更新...');
    try {
      final updateInfo = await UpdateService.checkForUpdates();
      debugPrint(
          '检查更新完成: 当前版本=${updateInfo.currentVersion}, 最新版本=${updateInfo.latestVersion}, 有更新=${updateInfo.hasUpdate}');
      if (updateInfo.hasUpdate) {
        debugPrint(
            '发现新版本: ${updateInfo.latestVersion}, 下载链接: ${updateInfo.releaseUrl}');
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
    final colorScheme = Theme.of(context).colorScheme;
    final notes = info.releaseNotes.trim().isNotEmpty
        ? info.releaseNotes.trim()
        : context.l10n.aboutNoReleaseNotes;
    final publishedAt = _formatPublishedAt(info.publishedAt);

    await BlurDialog.show(
      context: context,
      title: info.hasUpdate
          ? context.l10n.aboutFoundNewVersion(info.latestVersion)
          : context.l10n.aboutCurrentIsLatest,
      contentWidget: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.aboutCurrentVersionLabel(info.currentVersion),
              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.9)),
            ),
            Text(
              context.l10n.aboutLatestVersionLabel(info.latestVersion),
              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.9)),
            ),
            if (info.releaseName.trim().isNotEmpty)
              Text(
                context.l10n.aboutReleaseNameLabel(info.releaseName.trim()),
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.9)),
              ),
            if (publishedAt.isNotEmpty)
              Text(
                context.l10n.aboutPublishedAtLabel(publishedAt),
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.9)),
              ),
            if (info.error != null && info.error!.trim().isNotEmpty) ...[
              SizedBox(height: 8),
              Text(
                info.error!.trim(),
                style: TextStyle(color: Colors.redAccent),
              ),
            ],
            SizedBox(height: 12),
            Text(
              context.l10n.aboutReleaseNotesTitle,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: AdaptiveMarkdown(
                      data: notes,
                      brightness: Theme.of(context).brightness,
                      baseTextStyle: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.9)),
                      linkColor: Colors.lightBlueAccent,
                      onTapLink: (href) {
                        _launchURL(href);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (info.releaseUrl.trim().isNotEmpty)
          HoverScaleTextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _launchURL(info.releaseUrl);
            },
            child: Text(
              context.l10n.aboutOpenReleasePage,
              style: TextStyle(color: colorScheme.onSurface),
            ),
          ),
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            context.l10n.close,
            style: TextStyle(color: colorScheme.onSurface),
          ),
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
    } catch (e) {
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
      final colorScheme = Theme.of(context).colorScheme;
      await BlurDialog.show(
        context: context,
        title: context.l10n.updateCheckFailed,
        content: context.l10n.pleaseTryAgainLater,
        actions: [
          HoverScaleTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              context.l10n.close,
              style: TextStyle(color: colorScheme.onSurface),
            ),
          ),
        ],
      );
      return;
    }

    await _showUpdateDialog(info);
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      // Log or show a snackbar if url can't be launched
      //debugPrint('Could not launch $urlString');
      if (mounted) {
        BlurSnackBar.show(context, context.l10n.cannotOpenLink(urlString));
      }
    }
  }

  void _showAppreciationQR() {
    final colorScheme = Theme.of(context).colorScheme;
    BlurDialog.show(
      context: context,
      title: context.l10n.appreciationCode,
      contentWidget: ConstrainedBox(
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
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Ionicons.image_outline,
                      size: 60,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                    SizedBox(height: 10),
                    Text(
                      context.l10n.appreciationImageLoadFailed,
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.7),
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
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            context.l10n.close,
            style: TextStyle(color: colorScheme.onSurface),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme.apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        );
    final bool isUpdateButtonEnabled = !_isCheckingUpdate;
    final bool showUpdateButtonHover =
        isUpdateButtonEnabled && _isUpdateButtonHovered;
    final l10n = context.l10n;
    final Color updateAccentColor = AppAccentColors.current;
    final Color updateIdleColor =
        colorScheme.onSurface.withOpacity(isUpdateButtonEnabled ? 0.75 : 0.4);
    final Color updateButtonColor =
        showUpdateButtonHover ? updateAccentColor : updateIdleColor;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start, // Change to start
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 40), // Add some space at the top
          SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'assets/logo.png', // Ensure this path is correct
                    height: 120, // Adjust size as needed
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(Ionicons.image_outline,
                          size: 100,
                          color: colorScheme.onSurface
                              .withOpacity(0.7)); // Placeholder if logo fails
                    },
                  ),
                  SizedBox(height: 24),
                  // 版本信息，点击跳转到releases页面（如果有更新）
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      KeyboardActivatable(
                        enabled: _updateInfo?.hasUpdate == true,
                        onActivate: () => _launchURL(_updateInfo!.releaseUrl),
                        child: GestureDetector(
                          onTap: _updateInfo?.hasUpdate == true
                              ? () => _launchURL(_updateInfo!.releaseUrl)
                              : null,
                          child: MouseRegion(
                            cursor: _updateInfo?.hasUpdate == true
                                ? SystemMouseCursors.click
                                : SystemMouseCursors.basic,
                            child: AboutVersionBannerText(
                              text: l10n.aboutVersionBanner(
                                  _displayVersionText(context)),
                              targetLabel: _buildTargetLabel,
                              style: textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ) ??
                                  TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                              textAlign: TextAlign.start,
                            ),
                          ),
                        ),
                      ),
                      // NEW 标识 - 独立定位
                      if (_updateInfo?.hasUpdate == true)
                        Positioned(
                          top: -8,
                          right: -8,
                          child: const Text(
                            'NEW',
                            locale: Locale("zh-Hans", "zh"),
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 20),
                  MouseRegion(
                    onEnter: (_) => isUpdateButtonEnabled
                        ? setState(() => _isUpdateButtonHovered = true)
                        : null,
                    onExit: (_) => isUpdateButtonEnabled
                        ? setState(() => _isUpdateButtonHovered = false)
                        : null,
                    cursor: isUpdateButtonEnabled
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.basic,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: isUpdateButtonEnabled
                            ? _manualCheckForUpdates
                            : null,
                        hoverColor: Colors.transparent,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 10, 16, 10),
                          child: AnimatedScale(
                            scale: showUpdateButtonHover ? 1.1 : 1.0,
                            alignment: Alignment.centerLeft,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutBack,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isCheckingUpdate)
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          updateButtonColor),
                                    ),
                                  )
                                else
                                  Icon(
                                    Icons.system_update_alt,
                                    size: 18,
                                    color: updateButtonColor,
                                  ),
                                SizedBox(width: 6),
                                Text(
                                  _isCheckingUpdate
                                      ? l10n.aboutCheckingUpdates
                                      : l10n.aboutCheckUpdates,
                                  style: textTheme.labelLarge?.copyWith(
                                        color: updateButtonColor,
                                      ) ??
                                      TextStyle(color: updateButtonColor),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 20),

          _buildInfoCard(
            context: context,
            children: [
              _buildRichText(
                context,
                [
                  TextSpan(text: l10n.aboutStoryPrefix),
                  TextSpan(
                      text: 'にぱ〜☆',
                      style: TextStyle(
                          color: Colors.pinkAccent[100],
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic)),
                  TextSpan(text: l10n.aboutStorySuffix),
                ],
              ),
            ],
          ),
          SizedBox(height: 20),

          _buildInfoCard(
            context: context,
            title: l10n.acknowledgements,
            children: [
              _buildRichText(context, [
                TextSpan(text: l10n.aboutThanksDandanplayPrefix),
                TextSpan(
                    text: 'Kaedei',
                    style: TextStyle(
                        color: Colors.lightBlueAccent[100],
                        fontWeight: FontWeight.bold)),
                TextSpan(text: l10n.aboutThanksDandanplaySuffix),
              ]),
              _buildRichText(context, [
                TextSpan(text: l10n.aboutThanksSakikoPrefix),
                TextSpan(
                    text: 'Sakiko',
                    style: TextStyle(
                        color: Colors.lightBlueAccent[100],
                        fontWeight: FontWeight.bold)),
                TextSpan(text: l10n.aboutThanksSakikoSuffix),
              ]),
              SizedBox(height: 12),
              _buildRichText(
                context,
                [
                  TextSpan(text: l10n.thanksSponsorUsers),
                ],
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: kAcknowledgementNames
                    .map((name) => _buildAcknowledgementBadge(context, name))
                    .toList(),
              ),
            ],
          ),
          SizedBox(height: 20),

          _buildInfoCard(
            context: context,
            title: l10n.openSourceCommunity,
            children: [
              _buildRichText(context, [
                TextSpan(text: l10n.aboutCommunityHint),
              ]),
              SizedBox(height: 16),
              _buildActionLink(
                context: context,
                icon: Ionicons.logo_github,
                label: 'AimesSoft/NipaPlay-Reload',
                color: Colors.cyanAccent[100] ?? AppAccentColors.current,
                onPressed: () => _launchURL(
                    'https://www.github.com/AimesSoft/NipaPlay-Reload'),
              ),
              SizedBox(height: 12),
              _buildActionLink(
                context: context,
                icon: Ionicons.chatbubbles_outline,
                label: l10n.aboutQqGroup('961207150'),
                color: Colors.cyanAccent[100] ?? AppAccentColors.current,
                onPressed: () => _launchURL('https://qm.qq.com/q/w9j09QJn4Q'),
              ),
              SizedBox(height: 12),
              _buildActionLink(
                context: context,
                icon: Ionicons.globe_outline,
                label: l10n.aboutOfficialWebsite,
                color: Colors.cyanAccent[100] ?? AppAccentColors.current,
                onPressed: () => _launchURL('https://nipaplay.aimes-soft.com'),
              ),
            ],
          ),
          SizedBox(height: 20),

          _buildInfoCard(
            context: context,
            title: l10n.sponsorSupport,
            children: [
              _buildRichText(context, [
                TextSpan(
                  text:
                      '${l10n.aboutSponsorParagraph1}${l10n.aboutSponsorParagraph2}',
                ),
              ]),
              SizedBox(height: 16),
              _buildActionLink(
                context: context,
                icon: Ionicons.heart,
                label: l10n.aboutAfdianSponsorPage,
                color: Colors.pinkAccent[100] ?? AppAccentColors.current,
                onPressed: () => _launchURL('https://afdian.com/a/irigas'),
              ),
              SizedBox(height: 12),
              _buildActionLink(
                context: context,
                icon: Ionicons.qr_code,
                label: l10n.appreciationCode,
                color: Colors.orangeAccent[100] ?? AppAccentColors.current,
                onPressed: _showAppreciationQR,
              ),
            ],
          ),
          SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildAcknowledgementBadge(BuildContext context, String name) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = Colors.amberAccent[100] ?? Colors.amberAccent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Ionicons.ribbon_outline,
          size: 16,
          color: accentColor,
        ),
        SizedBox(width: 8),
        Text(
          name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  Widget _buildActionLink({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: HoverScaleTextButton(
        onPressed: onPressed,
        idleColor: color,
        hoverColor: color,
        hoverScale: 1.035,
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: colorScheme.onSurface.withOpacity(0.8),
              size: 20,
            ),
            SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                label,
                locale: Locale("zh-Hans", "zh"),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  decoration: TextDecoration.underline,
                  decorationColor: color.withOpacity(0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _displayVersionText(BuildContext context) {
    if (_versionLoadFailed) {
      return context.l10n.versionLoadFailed;
    }
    if (_version.isEmpty) {
      return context.l10n.loading;
    }
    return _version;
  }

  Widget _buildInfoCard(
      {required BuildContext context,
      String? title,
      required List<Widget> children}) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    );
  }

  Widget _buildRichText(BuildContext context, List<InlineSpan> spans) {
    final colorScheme = Theme.of(context).colorScheme;
    return RichText(
      textAlign: TextAlign.start, // Or TextAlign.justify if preferred
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.9),
              height: 1.6, // Improved line spacing
            ), // Default text style for spans
        children: spans,
      ),
    );
  }
}
