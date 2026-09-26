import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/immersive_portrait_backdrop_color.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

const int immersiveBackdropMinDecodeWidth = 1280;
const int immersiveBackdropMaxDecodeWidth = 3840;

String normalizeImmersiveSummaryText(String value) {
  // Bangumi 简介常在中文译文后附带 “[简介原文] 日语原文”，
  // 展示时剔除该标记及其后的全部内容，避免无谓地拉长文本。
  final separator =
      RegExp(r'[\[【]\s*简介原文\s*[\]】]').firstMatch(value);
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
    final infoWidth =
        (constraints.maxWidth * (constraints.maxWidth >= 1100 ? 0.42 : 0.48))
            .clamp(420.0, 650.0);
    final railHeight = compact ? 190.0 : 235.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        _Backdrop(url: backdropUrl),
        const _CinematicGradients(),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                horizontalPadding, 12, horizontalPadding, 18),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: _BackButton(onPressed: onBack),
                ),
                Positioned(
                  left: 0,
                  // 标题区下移量随窗口高度自适应：矮窗口少下移以保住简介
                  // 行数，高窗口多下移以拉开大标题与返回按钮的间距。
                  // 锚点：600px 高 → 60；1000px 高 → 150，区间内线性过渡。
                  top: (60.0 + (constraints.maxHeight - 600) / 400 * 90)
                      .clamp(60.0, 150.0),
                  width: infoWidth,
                  bottom: railHeight + (compact ? 14 : 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InformationHeader(
                        title: title,
                        subtitle: subtitle,
                        metadata: metadata,
                        rating: rating,
                        compact: compact,
                      ),
                      if (description?.trim().isNotEmpty == true) ...[
                        SizedBox(height: compact ? 8 : 16),
                        // 简介按剩余空间自适应行数（loose）：操作按钮紧跟
                        // 简介下方；展开时简介把按钮行往下顶，空间不足则
                        // 简介区内部滚动、按钮停留在剧集栏上方。
                        Flexible(
                          fit: FlexFit.loose,
                          child: _DescriptionBlock(
                            description: description!,
                            expanded: descriptionExpanded,
                            onToggle: onToggleDescription,
                            compact: compact,
                          ),
                        ),
                      ],
                      SizedBox(height: compact ? 6 : 14),
                      KeyedSubtree(
                        key: const ValueKey('immersive-fixed-actions'),
                        child: actions,
                      ),
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

  Widget _buildPortrait(BuildContext context, BoxConstraints constraints) {
    final heroHeight = constraints.maxHeight / 2;
    final phone =
        AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone ||
            constraints.maxWidth < 600;
    final safeTop = MediaQuery.paddingOf(context).top;
    final heroLead = (heroHeight - safeTop - 54 - (phone ? 140 : 180))
        .clamp(0.0, double.infinity);
    final backButton = Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: _BackButton(onPressed: onBack, onImage: true),
    );
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _InformationHeader(
        title: title,
        subtitle: subtitle,
        metadata: metadata,
        rating: rating,
      ),
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
                          child: _DescriptionBlock(
                            description: description!,
                            expanded: descriptionExpanded,
                            onToggle: onToggleDescription,
                          ),
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
                          child: _DescriptionBlock(
                            description: description!,
                            expanded: descriptionExpanded,
                            onToggle: onToggleDescription,
                          ),
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
  const _PortraitBackdropSurface({required this.url, required this.heroHeight});

  final String? url;
  final double heroHeight;

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
  const _Backdrop({this.url, this.alignment});

  final String? url;
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
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [0, 0.42, 0.75, 1],
              colors: [
                Color(0xF2080B12),
                Color(0xC7080B12),
                Color(0x30080B12),
                Color(0x26080B12),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.48, 0.75, 1],
              colors: [
                Color(0x5C080B12),
                Color(0x10080B12),
                Color(0xC7080B12),
                Color(0xFF080B12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed, this.onImage = false});

  final VoidCallback onPressed;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '返回',
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor:
              onImage ? Colors.black.withValues(alpha: 0.58) : null,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        ),
        icon: const Icon(Ionicons.chevron_back, size: 20),
        label: const Text('返回', style: TextStyle(fontSize: 15)),
      ),
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
  });

  final String title;
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
        Text(
          title,
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
/// 收起状态下按可用高度自适应显示行数（占住标题与操作按钮之间的空间）；
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
  // 有界高度下的自适应行数上限：非紧凑档多给一行。
  // pad 等中等高度窗口的信息栏较窄、每行容纳字数少，
  // 4 行封顶会浪费剩余空间，加重阅读压力。
  int get _maxAdaptiveLines => compact ? 4 : 5;
  // “查看更多”按钮的占位高度（minimumSize(44, 28) 收紧后）。
  static const double _toggleHeight = 30.0;

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
        final lineHeight = painter.preferredLineHeight;
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : null;

        // 收起状态：按剩余空间换算可显示行数，用于占位。
        int collapsedLines = compact ? 3 : _fallbackLines;
        if (availableHeight != null && lineHeight > 0) {
          collapsedLines =
              (((availableHeight - _toggleHeight) / lineHeight).floor())
                  .clamp(1, _maxAdaptiveLines);
        }
        final fitsCollapsed =
            naturalHeight <= collapsedLines * lineHeight + 0.5;

        double viewportHeight;
        if (expanded) {
          // 展开状态：完整显示，超出可用高度时滚动。
          viewportHeight = naturalHeight;
          if (availableHeight != null) {
            viewportHeight =
                viewportHeight.clamp(0.0, availableHeight - _toggleHeight);
          }
        } else {
          viewportHeight = fitsCollapsed
              ? naturalHeight
              : collapsedLines * lineHeight;
        }
        if (availableHeight != null && viewportHeight > availableHeight) {
          viewportHeight = availableHeight;
        }

        final showToggle = onToggle != null && (expanded || !fitsCollapsed);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: viewportHeight.clamp(0.0, double.infinity),
              // 展开后文本超出可视高度时可滚动，并显示滚动条指示。
              child: Scrollbar(
                thumbVisibility:
                    expanded && naturalHeight > viewportHeight + 0.5,
                child: SingleChildScrollView(
                  key: const ValueKey('immersive-description-scroll'),
                  child: Text(
                    value,
                    maxLines:
                        expanded || fitsCollapsed ? null : collapsedLines,
                    overflow: expanded || fitsCollapsed
                        ? TextOverflow.clip
                        : TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
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
