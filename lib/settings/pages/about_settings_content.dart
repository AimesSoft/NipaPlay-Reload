import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/services/update_service.dart';
import 'package:nipaplay/settings/about_settings_data.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/build_target_label.dart';
import 'package:nipaplay/widgets/adaptive_markdown.dart';
import 'package:nipaplay/widgets/about_version_banner_text.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutSettingsContent extends StatefulWidget {
  const AboutSettingsContent({super.key});

  @override
  State<AboutSettingsContent> createState() => _AboutSettingsContentState();
}

class _AboutSettingsContentState extends State<AboutSettingsContent> {
  late final String _buildTargetLabel = getBuildTargetLabel();
  String _version = '';
  bool _versionLoadFailed = false;
  UpdateInfo? _updateInfo;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _checkForUpdatesInBackgroundIfEnabled();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final versionText = _displayVersionText(context);
    final hasUpdate = _updateInfo?.hasUpdate == true;

    return AdaptiveSettingsPage(
      children: [
        _buildAboutCanvas(context,
            versionText: versionText, hasUpdate: hasUpdate),
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<void>.card(
              title: l10n.openSourceCommunity,
              subtitle: l10n.aboutCommunityHint,
              icon: Ionicons.logo_github,
              phoneIcon:
                  cupertino.CupertinoIcons.chevron_left_slash_chevron_right,
              onTap: () => _launchURL(AboutSettingsData.repositoryUrl),
            ),
            AdaptiveSettingsTile<void>.card(
              title: 'AimesSoft/NipaPlay-Reload',
              subtitle: AboutSettingsData.repositoryUrl,
              icon: Ionicons.logo_github,
              phoneIcon: cupertino.CupertinoIcons.link,
              onTap: () => _launchURL(AboutSettingsData.repositoryUrl),
            ),
            AdaptiveSettingsTile<void>.card(
              title: l10n.aboutQqGroup('961207150'),
              subtitle: AboutSettingsData.qqGroupUrl,
              icon: Ionicons.chatbubbles_outline,
              phoneIcon: cupertino.CupertinoIcons.chat_bubble_2,
              onTap: () => _launchURL(AboutSettingsData.qqGroupUrl),
            ),
            AdaptiveSettingsTile<void>.card(
              title: l10n.aboutOfficialWebsite,
              subtitle: AboutSettingsData.officialWebsiteUrl,
              icon: Ionicons.globe_outline,
              phoneIcon: cupertino.CupertinoIcons.globe,
              onTap: () => _launchURL(AboutSettingsData.officialWebsiteUrl),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<void>.card(
              title: l10n.aboutAfdianSponsorPage,
              subtitle: AboutSettingsData.afdianUrl,
              icon: Ionicons.heart,
              phoneIcon: cupertino.CupertinoIcons.heart_fill,
              onTap: () => _launchURL(AboutSettingsData.afdianUrl),
            ),
            AdaptiveSettingsTile<void>.card(
              title: l10n.appreciationCode,
              subtitle: l10n.appreciationCodeHint,
              icon: Ionicons.qr_code,
              phoneIcon: cupertino.CupertinoIcons.qrcode,
              onTap: _showAppreciationQR,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAboutCanvas(
    BuildContext context, {
    required String versionText,
    required bool hasUpdate,
  }) {
    final l10n = context.l10n;
    final isPhoneLayout = AdaptiveSettingsScope.isPhoneLayout(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = isPhoneLayout
        ? cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.label,
            context,
          )
        : colorScheme.onSurface;
    final secondaryColor = isPhoneLayout
        ? cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.secondaryLabel,
            context,
          )
        : colorScheme.onSurface.withValues(alpha: 0.7);
    final accentColor = isPhoneLayout
        ? cupertino.CupertinoTheme.of(context).primaryColor
        : AppAccentColors.current;

    return AdaptiveSettingsCanvas(
      padding: EdgeInsets.all(isPhoneLayout ? 18 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/logo.png',
            height: isPhoneLayout ? 110 : 120,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Ionicons.image_outline,
                size: isPhoneLayout ? 96 : 100,
                color: secondaryColor,
              );
            },
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: hasUpdate ? () => _launchURL(_updateInfo!.releaseUrl) : null,
            child: MouseRegion(
              cursor: hasUpdate
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AboutVersionBannerText(
                    text: l10n.aboutVersionBanner(versionText),
                    targetLabel: _buildTargetLabel,
                    style: TextStyle(
                      color: textColor,
                      fontSize: isPhoneLayout ? 24 : 26,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.start,
                  ),
                  if (hasUpdate)
                    Positioned(
                      top: -8,
                      right: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'NEW',
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
          ),
          const SizedBox(height: 12),
          _buildCanvasUpdateAction(context, accentColor, secondaryColor),
          const SizedBox(height: 22),
          _buildCanvasRichText(
            context,
            [
              TextSpan(text: l10n.aboutStoryPrefix),
              TextSpan(
                text: 'にぱ〜☆',
                style: TextStyle(
                  color: Colors.pinkAccent.shade100,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                ),
              ),
              TextSpan(text: l10n.aboutStorySuffix),
            ],
            textColor,
          ),
          _buildCanvasDivider(textColor),
          Text(
            l10n.acknowledgements,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildCanvasRichText(
            context,
            [
              TextSpan(text: l10n.aboutThanksDandanplayPrefix),
              TextSpan(
                text: 'Kaedei',
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(text: '${l10n.aboutThanksDandanplaySuffix}\n\n'),
              TextSpan(text: l10n.aboutThanksSakikoPrefix),
              TextSpan(
                text: 'Sakiko',
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(text: l10n.aboutThanksSakikoSuffix),
            ],
            textColor,
          ),
          const SizedBox(height: 14),
          Text(
            l10n.thanksSponsorUsers,
            style: TextStyle(color: textColor, height: 1.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final name in AboutSettingsData.sponsorNames)
                _buildAcknowledgementBadge(context, name, accentColor),
            ],
          ),
          _buildCanvasDivider(textColor),
          Text(
            l10n.sponsorSupport,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${l10n.aboutSponsorParagraph1}\n${l10n.aboutSponsorParagraph2}',
            style: TextStyle(
              color: secondaryColor,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasUpdateAction(
    BuildContext context,
    Color accentColor,
    Color secondaryColor,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _isCheckingUpdate ? null : _manualCheckForUpdates,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isCheckingUpdate)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accentColor,
                ),
              )
            else
              Icon(Icons.system_update_alt, size: 18, color: accentColor),
            const SizedBox(width: 8),
            Text(
              _isCheckingUpdate
                  ? context.l10n.aboutCheckingUpdates
                  : context.l10n.aboutCheckUpdates,
              style: TextStyle(
                color: _isCheckingUpdate ? secondaryColor : accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasRichText(
    BuildContext context,
    List<InlineSpan> spans,
    Color textColor,
  ) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: textColor.withValues(alpha: 0.9),
              height: 1.6,
            ),
        children: spans,
      ),
    );
  }

  Widget _buildCanvasDivider(Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Divider(
        height: 1,
        color: textColor.withValues(alpha: 0.12),
      ),
    );
  }

  Widget _buildAcknowledgementBadge(
    BuildContext context,
    String name,
    Color accentColor,
  ) {
    final textColor = AdaptiveSettingsScope.isPhoneLayout(context)
        ? cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.label,
            context,
          )
        : Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accentColor.withValues(alpha: 0.12),
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Ionicons.ribbon_outline, size: 15, color: accentColor),
          const SizedBox(width: 7),
          Text(
            name,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _versionLoadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _versionLoadFailed = true;
      });
    }
  }

  Future<void> _checkForUpdatesInBackgroundIfEnabled() async {
    final enabled = await UpdateService.isAutoCheckEnabled();
    if (!enabled || !mounted) return;
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    try {
      final updateInfo = await UpdateService.checkForUpdates();
      if (!mounted) return;
      setState(() {
        _updateInfo = updateInfo;
      });
    } catch (_) {
      // Silent background check.
    }
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
        title: context.l10n.updateCheckFailed,
        content: context.l10n.pleaseTryAgainLater,
        actions: [
          HoverScaleTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.close),
          ),
        ],
      );
      return;
    }

    await _showUpdateDialog(info);
  }

  Future<void> _showUpdateDialog(UpdateInfo info) async {
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
            Text(context.l10n.aboutCurrentVersionLabel(info.currentVersion)),
            Text(context.l10n.aboutLatestVersionLabel(info.latestVersion)),
            if (info.releaseName.trim().isNotEmpty)
              Text(context.l10n.aboutReleaseNameLabel(info.releaseName.trim())),
            if (publishedAt.isNotEmpty)
              Text(context.l10n.aboutPublishedAtLabel(publishedAt)),
            if (info.error != null && info.error!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                info.error!.trim(),
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              context.l10n.aboutReleaseNotesTitle,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: SingleChildScrollView(
                child: AdaptiveMarkdown(
                  data: notes,
                  brightness: Theme.of(context).brightness,
                  onTapLink: _launchURL,
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
            child: Text(context.l10n.aboutOpenReleasePage),
          ),
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }

  void _showAppreciationQR() {
    BlurDialog.show(
      context: context,
      title: context.l10n.appreciationCode,
      contentWidget: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 400),
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
                    const Icon(Ionicons.image_outline, size: 60),
                    const SizedBox(height: 10),
                    Text(context.l10n.appreciationImageLoadFailed),
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
          child: Text(context.l10n.close),
        ),
      ],
    );
  }

  Future<void> _launchURL(String urlString) async {
    final uri = Uri.tryParse(urlString);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: context.l10n.cannotOpenLink(urlString),
        type: AdaptiveSnackBarType.error,
      );
    }
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
}
