import 'package:nipaplay/themes/nipaplay/widgets/media_detail_poster.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/adaptive_media_detail_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/immersive_portrait_backdrop_color.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

const int immersiveBackdropMinDecodeWidth = 1280;
const int immersiveBackdropMaxDecodeWidth = 3840;

String normalizeImmersiveSummaryText(String value) {
  // Bangumi 简介常在中文译文后附带 “[简介原文] 日语原文”，
  // 展示时剔除该标记及其后的全部内容，避免无谓地拉长文本。
  final separator = RegExp(r'[\[【]\s*简介原文\s*[\]】]').firstMatch(value);
  if (separator != null) {
    value = value.substring(0, separator.start);
  }
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll('```', '')
      .replaceAll(RegExp(r'[\s\u00A0]+'), ' ')
      .trim();
}

int resolveImmersiveBackdropDecodeWidth(
  double logicalWidth,
  double devicePixelRatio,
) {
  if (!logicalWidth.isFinite || logicalWidth <= 0) {
    return immersiveBackdropMinDecodeWidth;
  }
  final safePixelRatio =
      devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1;
  final raw = (logicalWidth * safePixelRatio).ceil();
  // 量化到 128px 的倍数：拖动窗口缩放时解码宽度不会逐帧变化，
  // 避免背景图在每个布局帧都触发重新加载导致卡顿/闪黑。
  final quantized = ((raw + 64) ~/ 128) * 128;
  return quantized
      .clamp(
        immersiveBackdropMinDecodeWidth,
        immersiveBackdropMaxDecodeWidth,
      )
      .toInt();
}

class ImmersiveAnimeDetailScaffold extends StatelessWidget {
  const ImmersiveAnimeDetailScaffold({
    super.key,
    required this.title,
    required this.onBack,
    required this.actions,
    required this.episodeRail,
    this.subtitle,
    this.backdropUrl,
    this.logoUrl,
    this.posterUrl,
    this.posterHeroTag,
    this.fallbackBackdropUrls = const [],
    this.metadata = const <String>[],
    this.rating,
    this.description,
    this.descriptionExpanded = false,
    this.onToggleDescription,
    this.commentsPanel,
    this.commentsOpen = false,
    this.onCloseComments,
  });

  final String title;
  final String? subtitle;
  final String? backdropUrl;
  final List<String> fallbackBackdropUrls;
  final String? logoUrl;
  final String? posterUrl;
  final Object? posterHeroTag;
  final List<String> metadata;
  final double? rating;
  final String? description;
  final bool descriptionExpanded;
  final VoidCallback? onToggleDescription;
  final Widget actions;
  final Widget episodeRail;
  final VoidCallback onBack;
  final Widget? commentsPanel;
  final bool commentsOpen;
  final VoidCallback? onCloseComments;

  @override
  Widget build(BuildContext context) {
    // 沉浸式详情页没有 Material 祖先，DefaultTextStyle 不带主题里的
    // zh-Hans locale，Windows 上 CJK 文本会退回日文字形变体（如「达」
    // 的走之底渲染成 ⻍）。在根部补一次 locale，页内文本统一继承。
    return DefaultTextStyle(
      style: DefaultTextStyle.of(context)
          .style
          .copyWith(locale: const Locale('zh-Hans')),
      child: ColoredBox(
        color: const Color(0xFF080B12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final phoneSurface =
                AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone;
            final portrait = phoneSurface ||
                constraints.maxHeight > constraints.maxWidth ||
                constraints.maxWidth < 760;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (portrait)
                  _buildPortrait(context, constraints)
                else
                  _buildLandscape(context, constraints),
                if (commentsPanel != null)
                  _CommentsOverlay(
                    open: commentsOpen,
                    portrait: portrait,
                    onClose: onCloseComments,
                    child: commentsPanel!,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLandscape(BuildContext context, BoxConstraints constraints) {
    final compact = constraints.maxHeight < 720;
    final horizontalPadding = constraints.maxWidth >= 1400 ? 54.0 : 34.0;
    final railHeight = (constraints.maxHeight * 0.29).clamp(165.0, 235.0);
    final infoHeight = constraints.maxHeight -
        MediaQuery.paddingOf(context).vertical -
        30 -
        railHeight -
        (compact ? 14 : 22);
    final infoTop = (infoHeight * 0.14).clamp(62.0, 96.0);
    final availableHeight =
        (infoHeight - infoTop).clamp(160.0, double.infinity);
    final posterHeight = (constraints.maxHeight * 0.4)
        .clamp(240.0, 360.0)
        .clamp(0.0, availableHeight);
    final posterWidth = posterHeight * 0.7;
    final gap = constraints.maxWidth < 1000 ? 20.0 : 30.0;
    final textWidth = (constraints.maxWidth * 0.38).clamp(300.0, 540.0).clamp(
        0.0, constraints.maxWidth - horizontalPadding * 2 - posterWidth - gap);

    return Stack(
      fit: StackFit.expand,
      children: [
        _Backdrop(url: backdropUrl, fallbacks: fallbackBackdropUrls),
        const _CinematicGradients(),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                horizontalPadding, 12, horizontalPadding, 18),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: _DetailTopBar(title: title, onBack: onBack),
                ),
                Positioned(
                  left: 0,
                  top: infoTop,
                  width: posterWidth + gap + textWidth,
                  bottom: railHeight + (compact ? 14 : 22),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: posterWidth,
                          height: posterHeight,
                          child: MediaDetailPoster(
                              key: const ValueKey('immersive-detail-poster'),
                              url: posterUrl,
                              heroTag: posterHeroTag)),
                      SizedBox(width: gap),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _InformationHeader(
                              title: title,
                              logoUrl: logoUrl,
                              subtitle: subtitle,
                              metadata: metadata,
                              rating: rating,
                              compact: compact),
                          if (description?.trim().isNotEmpty == true) ...[
                            SizedBox(height: compact ? 10 : 16),
                            Flexible(
                                fit: FlexFit.loose,
                                child: _limitedDescription(context,
                                    compact: compact)),
                          ],
                          SizedBox(height: compact ? 10 : 16),
                          KeyedSubtree(
                              key: const ValueKey('immersive-fixed-actions'),
                              child: actions),
                        ],
                      )),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: railHeight,
                  child: episodeRail,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _limitedDescription(BuildContext context, {bool compact = false}) {
    final fontSize = MediaQuery.textScalerOf(context).scale(compact ? 13 : 14);
    return ConstrainedBox(
      key: const ValueKey('immersive-description-width'),
      constraints: BoxConstraints(maxWidth: 32 * fontSize),
      child: _DescriptionBlock(
          description: description!,
          expanded: descriptionExpanded,
          onToggle: onToggleDescription,
          compact: compact),
    );
  }

  Widget _buildPortrait(BuildContext context, BoxConstraints constraints) {
    final heroHeight = constraints.maxHeight / 2;
    final phone =
        AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone ||
            constraints.maxWidth < 600;
    final safeTop = MediaQuery.paddingOf(context).top;
    final posterWidth = (constraints.maxWidth * (phone ? 0.34 : 0.23))
        .clamp(phone ? 120.0 : 140.0, phone ? 156.0 : 190.0);
    final posterHeight = posterWidth / 0.7;
    final heroLead =
        (heroHeight - safeTop - 64 - posterHeight.clamp(180.0, 280.0))
            .clamp(0.0, double.infinity);
    final backButton = Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: _DetailTopBar(title: title, onBack: onBack),
    );
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: posterWidth,
            height: posterHeight,
            child: MediaDetailPoster(
                key: const ValueKey('immersive-detail-poster'),
                url: posterUrl,
                heroTag: posterHeroTag)),
        SizedBox(width: phone ? 16 : 24),
        Expanded(
            child: _InformationHeader(
                title: title,
                logoUrl: logoUrl,
                subtitle: subtitle,
                metadata: metadata,
                rating: rating,
                compact: phone)),
      ]),
    );
    final actionRow = Padding(
      key: const ValueKey('immersive-fixed-actions'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Align(alignment: Alignment.centerLeft, child: actions),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        _PortraitBackdropSurface(
          url: backdropUrl,
          heroHeight: heroHeight,
          fallbacks: fallbackBackdropUrls,
        ),
        SafeArea(
          child: phone
              ? SingleChildScrollView(
                  key: const ValueKey('immersive-phone-scroll'),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      backButton,
                      SizedBox(height: heroLead),
                      header,
                      if (description?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _limitedDescription(context),
                        ),
                      ],
                      actionRow,
                      SizedBox(height: 235, child: episodeRail),
                      const SizedBox(height: 24),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    backButton,
                    SizedBox(height: heroLead),
                    header,
                    if (description?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 16),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _limitedDescription(context),
                        ),
                      ),
                    ],
                    actionRow,
                    Expanded(child: episodeRail),
                    const SizedBox(height: 18),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PortraitBackdropSurface extends StatefulWidget {
  const _PortraitBackdropSurface(
      {required this.url, required this.heroHeight, this.fallbacks = const []});

  final String? url;
  final double heroHeight;
  final List<String> fallbacks;

  @override
  State<_PortraitBackdropSurface> createState() =>
      _PortraitBackdropSurfaceState();
}

class _PortraitBackdropSurfaceState extends State<_PortraitBackdropSurface> {
  String? _sampleKey;
  Future<ImmersiveBackdropAppearance>? _appearance;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, widget.heroHeight);
        // Quantize resizes so dragging a portrait window does not decode a
        // fresh palette image for every single logical pixel.
        final key = '${widget.url}|${(viewport.width / 32).round()}|'
            '${(viewport.height / 32).round()}';
        if (_sampleKey != key) {
          _sampleKey = key;
          _appearance = loadImmersiveBackdropAppearance(
            widget.url,
            viewport,
            sampleColor: true,
            targetWidth: resolveImmersiveBackdropDecodeWidth(
              viewport.width,
              MediaQuery.devicePixelRatioOf(context),
            ),
          );
        }
        return FutureBuilder<ImmersiveBackdropAppearance>(
          // Preserve the previous appearance during a window resize, but do
          // not show another poster's palette when the image URL changes.
          key: ValueKey(widget.url),
          future: _appearance,
          builder: (context, snapshot) {
            final color =
                snapshot.data?.color ?? immersivePortraitFallbackColor;
            // The fill can be brighter than the poster edge. Keep a darker
            // shade of the same hue behind the overlapping title/subtitle.
            final titleScrim = Color.lerp(color, Colors.black, 0.38)!;
            return Stack(
              fit: StackFit.expand,
              children: [
                AnimatedContainer(
                  key: const ValueKey('immersive-portrait-color-fill'),
                  duration: const Duration(milliseconds: 350),
                  color: color,
                ),
                Positioned(
                  key: const ValueKey('immersive-portrait-poster'),
                  left: 0,
                  right: 0,
                  top: 0,
                  height: widget.heroHeight,
                  child: _Backdrop(
                    url: widget.url,
                    fallbacks: widget.fallbacks,
                    alignment: snapshot.data?.alignment ?? Alignment.center,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: widget.heroHeight * 0.25,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xC7000000), Colors.transparent],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  key: const ValueKey('immersive-portrait-seam'),
                  left: 0,
                  right: 0,
                  top: widget.heroHeight * 0.48,
                  height: widget.heroHeight * 0.52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.2, 0.4, 1],
                        colors: [
                          Colors.transparent,
                          titleScrim.withValues(alpha: 0.68),
                          titleScrim.withValues(alpha: 0.98),
                          color,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Backdrop extends StatefulWidget {
  const _Backdrop({this.url, this.alignment, this.fallbacks = const []});

  final String? url;
  final List<String> fallbacks;
  final Alignment? alignment;

  @override
  State<_Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<_Backdrop> {
  String? _analysisKey;
  String? _analysisUrl;
  Future<ImmersiveBackdropAppearance>? _appearance;
  Alignment _previousAlignment = Alignment.center;

  @override
  Widget build(BuildContext context) {
    final value = widget.url?.trim() ?? '';
    Widget fallback = const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF191525), Color(0xFF080B12)],
        ),
      ),
    );
    if (widget.fallbacks.isNotEmpty) {
      fallback = _Backdrop(
          url: widget.fallbacks.first,
          fallbacks: widget.fallbacks.skip(1).toList(),
          alignment: widget.alignment);
    }
    if (value.isEmpty) return fallback;

    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final targetWidth = resolveImmersiveBackdropDecodeWidth(
          logicalWidth,
          MediaQuery.devicePixelRatioOf(context),
        );
        Widget imageAt(Alignment alignment) {
          final lower = value.toLowerCase();
          if (lower.startsWith('http://') || lower.startsWith('https://')) {
            return CachedNetworkImageWidget(
              imageUrl: value,
              fit: BoxFit.cover,
              alignment: alignment,
              fadeDuration: const Duration(milliseconds: 300),
              // 仅指定宽度：Flutter 会保留源图比例，BoxFit.cover 再负责裁切。
              memCacheWidth: targetWidth,
              maxDecodeEdge: immersiveBackdropMaxDecodeWidth,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __) => fallback,
            );
          }
          if (kIsWeb) return fallback;
          final file = File(value);
          if (!file.existsSync()) return fallback;
          return Image.file(
            file,
            fit: BoxFit.cover,
            alignment: alignment,
            // cacheWidth 只约束单边，原图比例不会被改写。
            cacheWidth: targetWidth,
            errorBuilder: (_, __, ___) => fallback,
          );
        }

        if (widget.alignment != null) return imageAt(widget.alignment!);
        final logicalHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        if (logicalHeight <= 0) return imageAt(Alignment.center);
        final viewport = Size(logicalWidth, logicalHeight);
        final analysisKey =
            '$value|${(logicalWidth / logicalHeight * 100).round()}';
        if (_analysisKey != analysisKey || _appearance == null) {
          if (_analysisUrl != value) {
            _previousAlignment = Alignment.center;
          }
          _analysisKey = analysisKey;
          _analysisUrl = value;
          _appearance = loadImmersiveBackdropAppearance(
            value,
            viewport,
            targetWidth: targetWidth,
          );
        }
        return FutureBuilder<ImmersiveBackdropAppearance>(
          key: ValueKey(value),
          future: _appearance,
          builder: (context, snapshot) {
            final alignment = snapshot.data?.alignment ?? _previousAlignment;
            if (snapshot.hasData) _previousAlignment = alignment;
            return imageAt(alignment);
          },
        );
      },
    );
  }
}

class _CinematicGradients extends StatelessWidget {
  const _CinematicGradients();

  @override
  Widget build(BuildContext context) {
    // 参考 Erika 播放器 details_wash 的三层遮罩结构：
    // 1. 全局淡色蒙版（20%）——整体轻微压暗，保留背景大面积可见
    // 2. 左侧横向渐变（左 62% 区域，56% 最大不透明度，向右淡出）——海报/标题区可读性
    // 3. 底部竖向渐变（下 42% 区域，88% 最大不透明度，向上淡出）——剧集轨道可读性
    // 右上角仅受全局 20% 蒙版影响，背景图清晰可见。
    return const Stack(
      fit: StackFit.expand,
      children: [
        // 全局淡色蒙版
        ColoredBox(color: Color(0x33080B12)),
        // 左侧横向渐变：左 56% → 62% 处淡出至透明，右侧不受影响
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [0, 0.62, 1],
              colors: [
                Color(0x8F080B12),
                Color(0x00080B12),
                Color(0x00080B12),
              ],
            ),
          ),
        ),
        // 底部竖向渐变：58% 以上透明 → 底部 88%
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.58, 1],
              colors: [
                Color(0x00080B12),
                Color(0x00080B12),
                Color(0xE0080B12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _BackButton(onPressed: onBack),
          const SizedBox(width: 14),
          Expanded(
              child: Text(
            title,
            key: const ValueKey('immersive-top-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                height: 1.2,
                fontWeight: FontWeight.w700),
          )),
        ],
      );
}

/// Same contain bounds and missing-artwork fallback as Erika's detail hero.
class _TitleArtwork extends StatefulWidget {
  const _TitleArtwork(
      {required this.url,
      required this.title,
      required this.compact,
      required this.fallback});
  final String? url;
  final String title;
  final bool compact;
  final Widget fallback;

  @override
  State<_TitleArtwork> createState() => _TitleArtworkState();
}

class _TitleArtworkState extends State<_TitleArtwork> {
  String? _svgUrl;
  Future<Uint8List>? _svgBytes;

  @override
  Widget build(BuildContext context) {
    final value = widget.url?.trim() ?? '';
    if (value.isEmpty) return widget.fallback;
    final uri = Uri.tryParse(value);
    final imagePath =
        Uri.tryParse(uri?.queryParameters['url'] ?? value)?.path ?? '';
    final height = widget.compact ? 72.0 : 88.0;
    Widget image;
    if (imagePath.endsWith('.svg')) {
      if (_svgUrl != value) {
        _svgUrl = value;
        _svgBytes = ImageCacheManager.instance.loadImageBytes(value);
      }
      image = FutureBuilder<Uint8List>(
        key: ValueKey(value),
        future: _svgBytes,
        builder: (context, snapshot) => snapshot.hasData
            ? SvgPicture.memory(snapshot.data!,
                width: 320,
                height: height,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                errorBuilder: (_, __, ___) => widget.fallback)
            : widget.fallback,
      );
    } else {
      image = CachedNetworkImageWidget(
        key: ValueKey(value),
        imageUrl: value,
        width: 320,
        height: height,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        memCacheWidth: 1000,
        filterQuality: FilterQuality.high,
        placeholderBuilder: (_) => widget.fallback,
        errorBuilder: (_, __) => widget.fallback,
      );
    }
    return Semantics(
      image: true,
      label: widget.title,
      child: ExcludeSemantics(
          child: ConstrainedBox(
        key: const ValueKey('immersive-title-logo'),
        constraints: BoxConstraints(maxWidth: 320, maxHeight: height),
        child: image,
      )),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (AdaptiveMediaDetailActionButton.useNativeLiquidGlass(context)) {
      return AdaptiveMediaDetailActionButton(
        icon: Ionicons.chevron_back,
        label: '返回',
        iconOnly: true,
        onPressed: onPressed,
      );
    }
    return AdaptiveMediaDetailIconButton(
      icon: Ionicons.chevron_back,
      tooltip: '返回',
      onPressed: onPressed,
    );
  }
}

class _InformationHeader extends StatelessWidget {
  const _InformationHeader({
    required this.title,
    required this.subtitle,
    required this.metadata,
    required this.rating,
    this.compact = false,
    this.logoUrl,
  });

  final String title;
  final String? logoUrl;
  final String? subtitle;
  final List<String> metadata;
  final double? rating;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cleanSubtitle = subtitle?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleArtwork(
          url: logoUrl,
          title: title,
          compact: compact,
          fallback: Text(
            title,
            key: const ValueKey('immersive-hero-title'),
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 34 : 42,
              height: 1.08,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.7,
            ),
          ),
        ),
        if (cleanSubtitle?.isNotEmpty == true && cleanSubtitle != title) ...[
          const SizedBox(height: 8),
          Text(
            cleanSubtitle!,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 14,
              height: 1.3,
            ),
          ),
        ],
        if (metadata.isNotEmpty || rating != null) ...[
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var index = 0; index < metadata.length; index++) ...[
                if (index > 0)
                  Text('·',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.34))),
                Text(
                  metadata[index],
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (rating != null) ...[
                if (metadata.isNotEmpty)
                  Text('·',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.34))),
                Icon(Ionicons.star, size: 15, color: AppAccentColors.current),
                Text(
                  rating!.toStringAsFixed(1),
                  style: TextStyle(
                    color: AppAccentColors.current,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// 简介展示块：文本视口与“查看更多/收起”按钮的组合。
///
/// 收起状态下按可用高度自适应显示行数；
/// 实测完整文本在收起行数内就能显示时，自动隐藏展开按钮。
/// 无界高度（滚动布局）中退化为固定行数，但仍保留精确的溢出测量。
class _DescriptionBlock extends StatelessWidget {
  const _DescriptionBlock({
    required this.description,
    required this.expanded,
    required this.onToggle,
    this.compact = false,
  });

  final String description;
  final bool expanded;
  final VoidCallback? onToggle;
  final bool compact;

  static const int _fallbackLines = 4;
  static const double _toggleHeight = 28.0;

  // TextPainter 手动构造样式、不读 DefaultTextStyle，locale 需显式带上，
  // 保证测量与显示使用同一套 CJK 字形变体。
  TextStyle _style() => TextStyle(
        color: Colors.white.withValues(alpha: 0.86),
        fontSize: compact ? 13 : 14,
        height: 1.62,
        locale: const Locale('zh-Hans'),
      );

  @override
  Widget build(BuildContext context) {
    final value = description.trim();
    final style = _style();
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final naturalHeight = painter.height;
        final naturalLines = painter.computeLineMetrics().length;
        final lineHeight = painter.preferredLineHeight;
        final availableHeight =
            constraints.hasBoundedHeight ? constraints.maxHeight : null;

        // Use the space left after the header and actions, but keep collapsed
        // summaries brief even when a large desktop has plenty of free space.
        // The ceiling rises gradually from 3 lines on a short tablet to at
        // most 6 lines on a tall desktop.
        int collapsedLines = _fallbackLines;
        if (availableHeight != null && lineHeight > 0) {
          final reservedHeight = onToggle == null ? 0.0 : _toggleHeight;
          final fittingLines =
              ((availableHeight - reservedHeight) / lineHeight).floor();
          final maxPreviewLines =
              (3 + ((availableHeight - 140) / 120).floor()).clamp(3, 6);
          collapsedLines = maxPreviewLines.clamp(1, fittingLines.clamp(1, 6));
        }
        final fitsCollapsed = naturalLines <= collapsedLines;
        final showToggle = onToggle != null && (expanded || !fitsCollapsed);
        final viewportLimit = availableHeight == null
            ? double.infinity
            : (availableHeight - (showToggle ? _toggleHeight : 0))
                .clamp(0.0, double.infinity);

        double viewportHeight;
        if (expanded) {
          // 展开状态：完整显示，超出可用高度时滚动。
          viewportHeight = naturalHeight;
          viewportHeight = viewportHeight.clamp(0.0, viewportLimit);
        } else {
          viewportHeight =
              fitsCollapsed ? naturalHeight : collapsedLines * lineHeight;
          viewportHeight = viewportHeight.clamp(0.0, viewportLimit);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              key: const ValueKey('immersive-description-viewport'),
              height: viewportHeight.clamp(0.0, double.infinity),
              child: expanded && naturalHeight > viewportHeight + 0.5
                  ? Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        key: const ValueKey('immersive-description-scroll'),
                        child: Text(value, style: style),
                      ),
                    )
                  : Text(
                      value,
                      maxLines:
                          expanded || fitsCollapsed ? null : collapsedLines,
                      overflow: expanded || fitsCollapsed
                          ? TextOverflow.clip
                          : TextOverflow.ellipsis,
                      style: style,
                    ),
            ),
            if (showToggle)
              _DescriptionToggle(
                expanded: expanded,
                onPressed: onToggle!,
              ),
          ],
        );
      },
    );
  }
}

class _DescriptionToggle extends StatelessWidget {
  const _DescriptionToggle({
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.7),
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(expanded ? '收起' : '查看更多'),
    );
  }
}

class _CommentsOverlay extends StatelessWidget {
  const _CommentsOverlay({
    required this.open,
    required this.portrait,
    required this.onClose,
    required this.child,
  });

  final bool open;
  final bool portrait;
  final VoidCallback? onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !open,
      child: AnimatedOpacity(
        opacity: open ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: onClose,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
            ),
            SafeArea(
              child: Align(
                alignment:
                    portrait ? Alignment.bottomCenter : Alignment.centerRight,
                child: AnimatedSlide(
                  offset: open
                      ? Offset.zero
                      : portrait
                          ? const Offset(0, 1)
                          : const Offset(1, 0),
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    width: portrait ? double.infinity : 410,
                    height: portrait
                        ? MediaQuery.sizeOf(context).height * 0.72
                        : double.infinity,
                    margin: portrait
                        ? const EdgeInsets.only(top: 72)
                        : const EdgeInsets.fromLTRB(0, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xF21A1C26),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
                      borderRadius: BorderRadius.circular(portrait ? 16 : 12),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
