import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

class ImmersiveEpisodeRail extends StatefulWidget {
  const ImmersiveEpisodeRail({
    super.key,
    required this.episodeCount,
    required this.itemBuilder,
    required this.onSelectEpisodes,
  });

  final int episodeCount;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback? onSelectEpisodes;

  @override
  State<ImmersiveEpisodeRail> createState() => _ImmersiveEpisodeRailState();
}

class _ImmersiveEpisodeRailState extends State<ImmersiveEpisodeRail> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    final next = (_controller.offset + delta)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      next,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final horizontalPadding = compact ? 24.0 : 0.0;
        final targetVisible = constraints.maxWidth >= 1400
            ? 7.2
            : constraints.maxWidth >= 1100
                ? 6.2
                : constraints.maxWidth >= 760
                    ? 4.2
                    : 2.35;
        final usableWidth = constraints.maxWidth - horizontalPadding * 2;
        final cardWidth =
            ((usableWidth - 12 * (targetVisible - 1)) / targetVisible)
                .clamp(168.0, 250.0);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '剧集',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '共 ${widget.episodeCount} 集',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  if (widget.onSelectEpisodes != null)
                    TextButton.icon(
                      onPressed: widget.onSelectEpisodes,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white.withValues(alpha: 0.82),
                        backgroundColor: Colors.black.withValues(alpha: 0.25),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                        minimumSize: const Size(48, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Ionicons.list_outline, size: 17),
                      label: const Text('选择剧集'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Listener(
                  onPointerSignal: _handlePointerSignal,
                  child: Scrollbar(
                    controller: _controller,
                    thumbVisibility: false,
                    child: ListView.separated(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      itemCount: widget.episodeCount,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) => SizedBox(
                        width: cardWidth,
                        child: widget.itemBuilder(context, index),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ImmersiveEpisodeCard extends StatefulWidget {
  const ImmersiveEpisodeCard({
    super.key,
    required this.episodeLabel,
    required this.title,
    required this.onTap,
    this.thumbnailPath,
    this.progress = 0,
    this.durationLabel,
    this.isCurrent = false,
    this.isCompleted = false,
    this.isUnavailable = false,
  });

  final String episodeLabel;
  final String title;
  final String? thumbnailPath;
  final double progress;
  final String? durationLabel;
  final bool isCurrent;
  final bool isCompleted;
  final bool isUnavailable;
  final VoidCallback? onTap;

  @override
  State<ImmersiveEpisodeCard> createState() => _ImmersiveEpisodeCardState();
}

class _ImmersiveEpisodeCardState extends State<ImmersiveEpisodeCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.current;
    final active = _hovered || _focused;
    return Semantics(
      button: true,
      label: '${widget.episodeLabel} ${widget.title}',
      child: MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: FocusableActionDetector(
          enabled: widget.onTap != null,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: const Color(0xFF24262E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: widget.isCurrent || _focused
                            ? accent
                            : Colors.white.withValues(
                                alpha: active ? 0.24 : 0.1,
                              ),
                        width: widget.isCurrent || _focused ? 1.6 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _EpisodeThumbnail(path: widget.thumbnailPath),
                        if (active)
                          ColoredBox(
                            color: Colors.white.withValues(alpha: 0.045),
                          ),
                        Center(
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.42),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Ionicons.play,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (widget.isUnavailable)
                          const Positioned(
                            right: 7,
                            top: 7,
                            child: ImmersiveEpisodeUnavailableBadge(),
                          )
                        else if (widget.isCompleted)
                          Positioned(
                            right: 7,
                            top: 7,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32),
                                shape: BoxShape.circle,
                                // 深色描边+阴影，保证在浅色缩略图上仍清晰可见
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Ionicons.checkmark,
                                color: Colors.white,
                                size: 13,
                              ),
                            ),
                          ),
                        if (widget.durationLabel?.isNotEmpty == true)
                          Positioned(
                            right: 6,
                            bottom: 7,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              color: Colors.black.withValues(alpha: 0.65),
                              child: Text(
                                widget.durationLabel!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        if (widget.progress > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 3,
                            child: ColoredBox(
                              color: Colors.white.withValues(alpha: 0.16),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: widget.progress.clamp(0.0, 1.0),
                                child: ColoredBox(color: accent),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.episodeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.isCurrent || active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.84),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.title.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Marks an episode that exists in metadata but has no playable media file.
class ImmersiveEpisodeUnavailableBadge extends StatelessWidget {
  const ImmersiveEpisodeUnavailableBadge({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '暂无资源',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF686B73),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.42),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '!',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.94),
              fontSize: size * 0.68,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeThumbnail extends StatelessWidget {
  const _EpisodeThumbnail({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final value = path?.trim() ?? '';
    if (value.isEmpty) return const _EpisodePlaceholder();
    final lower = value.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        child: CachedNetworkImageWidget(
          key: ValueKey(value),
          imageUrl: value,
          fit: BoxFit.cover,
          memCacheWidth: 520,
          fadeDuration: const Duration(milliseconds: 240),
          errorBuilder: (_, __) => const _EpisodePlaceholder(),
        ),
      );
    }
    if (kIsWeb) return const _EpisodePlaceholder();
    final file = File(value);
    if (!file.existsSync()) return const _EpisodePlaceholder();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: Image.file(
        file,
        key: ValueKey(value),
        fit: BoxFit.cover,
        cacheWidth: 520,
        errorBuilder: (_, __, ___) => const _EpisodePlaceholder(),
      ),
    );
  }
}

class _EpisodePlaceholder extends StatelessWidget {
  const _EpisodePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF2A2C34),
      child: Center(
        child: Icon(
          Ionicons.videocam_outline,
          color: Color(0x5CFFFFFF),
          size: 29,
        ),
      ),
    );
  }
}
