import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

const int immersiveBackdropMinDecodeWidth = 1280;
const int immersiveBackdropMaxDecodeWidth = 3840;

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
    return ColoredBox(
      color: const Color(0xFF080B12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final portrait = constraints.maxHeight > constraints.maxWidth ||
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
    );
  }

  Widget _buildLandscape(BuildContext context, BoxConstraints constraints) {
    final horizontalPadding = constraints.maxWidth >= 1400 ? 54.0 : 34.0;
    final infoWidth =
        (constraints.maxWidth * (constraints.maxWidth >= 1100 ? 0.42 : 0.48))
            .clamp(420.0, 650.0);
    final railHeight = constraints.maxHeight < 720 ? 205.0 : 235.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        _Backdrop(url: backdropUrl),
        const _CinematicGradients(portrait: false),
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
                  // 标题区整体下移，收窄“观看”按钮与下方剧集轨道之间的空白。
                  top: 92,
                  width: infoWidth,
                  bottom: railHeight + 22,
                  child: SingleChildScrollView(
                    child: _InformationBlock(
                      title: title,
                      subtitle: subtitle,
                      metadata: metadata,
                      rating: rating,
                      description: description,
                      descriptionExpanded: descriptionExpanded,
                      onToggleDescription: onToggleDescription,
                      actions: actions,
                      compact: constraints.maxHeight < 720,
                    ),
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
    final heroHeight = (constraints.maxHeight * 0.42).clamp(280.0, 430.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: heroHeight,
          child: _Backdrop(url: backdropUrl),
        ),
        const _CinematicGradients(portrait: true),
        SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _BackButton(onPressed: onBack),
                  ),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: heroHeight - 112)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                  child: _InformationBlock(
                    title: title,
                    subtitle: subtitle,
                    metadata: metadata,
                    rating: rating,
                    description: description,
                    descriptionExpanded: descriptionExpanded,
                    onToggleDescription: onToggleDescription,
                    actions: actions,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: 250, child: episodeRail),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final value = url?.trim() ?? '';
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
        final lower = value.toLowerCase();
        if (lower.startsWith('http://') || lower.startsWith('https://')) {
          return CachedNetworkImageWidget(
            imageUrl: value,
            fit: BoxFit.cover,
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
          // cacheWidth 只约束单边，原图比例不会被改写。
          cacheWidth: targetWidth,
          errorBuilder: (_, __, ___) => fallback,
        );
      },
    );
  }
}

class _CinematicGradients extends StatelessWidget {
  const _CinematicGradients({required this.portrait});

  final bool portrait;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!portrait)
          const DecoratedBox(
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
              stops: portrait
                  ? const [0, 0.28, 0.48, 1]
                  : const [0, 0.48, 0.75, 1],
              colors: portrait
                  ? const [
                      Color(0x42080B12),
                      Color(0x16080B12),
                      Color(0xF0080B12),
                      Color(0xFF080B12),
                    ]
                  : const [
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
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '返回',
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        ),
        icon: const Icon(Ionicons.chevron_back, size: 20),
        label: const Text('返回', style: TextStyle(fontSize: 15)),
      ),
    );
  }
}

class _InformationBlock extends StatelessWidget {
  const _InformationBlock({
    required this.title,
    required this.subtitle,
    required this.metadata,
    required this.rating,
    required this.description,
    required this.descriptionExpanded,
    required this.onToggleDescription,
    required this.actions,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final List<String> metadata;
  final double? rating;
  final String? description;
  final bool descriptionExpanded;
  final VoidCallback? onToggleDescription;
  final Widget actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cleanSubtitle = subtitle?.trim();
    final cleanDescription = description?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
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
            maxLines: 2,
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
        if (cleanDescription?.isNotEmpty == true) ...[
          SizedBox(height: compact ? 13 : 18),
          Text(
            cleanDescription!,
            maxLines: descriptionExpanded ? 8 : (compact ? 3 : 4),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: compact ? 13 : 14,
              height: 1.62,
            ),
          ),
          if (onToggleDescription != null) ...[
            const SizedBox(height: 2),
            TextButton(
              onPressed: onToggleDescription,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                minimumSize: const Size(44, 34),
              ),
              child: Text(descriptionExpanded ? '收起' : '查看更多'),
            ),
          ],
        ],
        SizedBox(height: compact ? 12 : 18),
        actions,
      ],
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
