import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV 版番剧卡片：移植普通版新版卡片（`themes/nipaplay/widgets/anime_card.dart`）
/// 的视觉语言——竖版海报、圆角、底部渐变遮罩、来源/评分/在播徽标、NEW 标识——
/// 并叠加 TV 焦点逻辑（D-pad 放大 + 光环 + 触摸点按）。
///
/// 普通版卡片依赖 provider/焦点工具/图片缓存管理等多处 app 态，无法直接搬入
/// ui_common；TV 版按自己的焦点模型重做，视觉与信息结构保持一致。
class TvAnimeCard extends StatefulWidget {
  const TvAnimeCard({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
    this.focusNode,
    this.isOnAir = false,
    this.source,
    this.rating,
    this.showNewBadge = false,
    this.episodeLabel,
    this.width = 200,
    this.autofocus = false,
    this.selected = false,
  });

  final String name;

  /// 网络封面或本地文件路径。
  final String imageUrl;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool isOnAir;

  /// 来源标签（本地 / WebDAV / Emby / Jellyfin / SMB）。
  final String? source;
  final double? rating;
  final bool showNewBadge;

  /// 集数/进度标签（如「第 5 话」）。
  final String? episodeLabel;
  final double width;
  final bool autofocus;
  final bool selected;

  @override
  State<TvAnimeCard> createState() => _TvAnimeCardState();
}

class _TvAnimeCardState extends State<TvAnimeCard> {
  bool _focused = false;
  bool _hovered = false;

  bool get _highlighted => _focused || _hovered;

  /// 封面直接用原始 URL。
  ///
  /// 注意：**不要**经 `WebRemoteAccessService.imageProxyUrl()` —— 那是普通版
  /// 依赖本地 web 服务器的图片代理，TV 版没有该服务器，会导致封面全部加载失败。
  /// 弹弹网关的图片地址已自带 token，Bangumi 图床直连可达。
  String get _resolvedImage => widget.imageUrl;

  bool get _isLocalFile {
    final u = widget.imageUrl;
    return u.startsWith('/') || u.startsWith('file:');
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF26C6DA);
    final radius = BorderRadius.circular(14);
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _highlighted ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: SizedBox(
              width: widget.width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(
                        color: _highlighted
                            ? accent
                            : (widget.selected
                                ? accent.withValues(alpha: 0.85)
                                : Colors.white24),
                        width: _highlighted ? 3 : (widget.selected ? 2 : 1),
                      ),
                      boxShadow: _highlighted
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.4),
                                blurRadius: 24,
                                spreadRadius: 1,
                              ),
                            ]
                          : const [],
                    ),
                    child: ClipRRect(
                      borderRadius: radius,
                      child: AspectRatio(
                        aspectRatio: 2 / 3, // 竖版海报，与普通版一致
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _cover(),
                            // 底部渐变遮罩，保证文字可读（十英尺距离）
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.center,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.82),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (widget.showNewBadge)
                              const Positioned(
                                top: 8,
                                left: 8,
                                child: _Badge(
                                    text: 'NEW', color: Color(0xFFE53935)),
                              ),
                            if (widget.isOnAir)
                              const Positioned(
                                top: 8,
                                right: 8,
                                child: _Badge(
                                    text: '在播', color: Color(0xFF2E7D32)),
                              ),
                            if (widget.rating != null && widget.rating! > 0)
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: _Badge(
                                  text: '★ ${widget.rating!.toStringAsFixed(1)}',
                                  color: Colors.black.withValues(alpha: 0.7),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          _highlighted ? FontWeight.w700 : FontWeight.w600,
                      color: _highlighted ? Colors.white : Colors.white70,
                      height: 1.25,
                    ),
                  ),
                  if (widget.source != null || widget.episodeLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          if (widget.episodeLabel != null)
                            widget.episodeLabel!,
                          if (widget.source != null) widget.source!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover() {
    if (widget.imageUrl.isEmpty) return _placeholder();
    if (_isLocalFile) {
      return Image.file(
        File(widget.imageUrl.replaceFirst('file://', '')),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return Image.network(
      _resolvedImage,
      fit: BoxFit.cover,
      headers: const {'User-Agent': 'NipaPlay/1.0'},
      errorBuilder: (_, _, _) => _placeholder(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return ColoredBox(
          color: Colors.white.withValues(alpha: 0.04),
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF26C6DA)),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder() => ColoredBox(
        color: Colors.white.withValues(alpha: 0.06),
        child: const Center(
          child: Icon(Icons.movie_outlined, size: 44, color: Colors.white24),
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
