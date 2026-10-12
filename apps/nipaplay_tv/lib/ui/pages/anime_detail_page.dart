import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay_core/models/bangumi_model.dart';
import 'package:nipaplay_core/player/nipa_player.dart';

import 'package:nipaplay_core/models/bangumi_comment_model.dart';

import '../../data/tv_library_loader.dart';
import '../../data/tv_media_sources.dart';
import '../../data/tv_trending_client.dart';
import 'player_page.dart';

/// TV 番剧详情页：对齐普通版新版番剧页的视觉（全屏背景图 + 标题/元信息 +
/// 简介 + 剧集网格），并按 TV 焦点模型重做导航。
///
/// 两种入口：
/// - 来自排行榜：展示 [anime] 的封面/评分/简介，剧集区提示需绑定媒体源；
/// - 来自媒体库条目：展示 [item] 的分集，可直接播放。
class TvAnimeDetailPage extends StatefulWidget {
  const TvAnimeDetailPage({
    super.key,
    this.anime,
    this.item,
    this.entryFocusNode,
  }) : assert(anime != null || item != null,
            'anime 与 item 至少提供一个');

  final BangumiAnime? anime;
  final TvLibraryItem? item;
  final FocusNode? entryFocusNode;

  @override
  State<TvAnimeDetailPage> createState() => _TvAnimeDetailPageState();
}

class _TvAnimeDetailPageState extends State<TvAnimeDetailPage> {
  int _episodeIndex = 0;
  List<DandanplayComment> _comments = const [];
  BangumiAnime? _detail;
  bool _loadingExtra = true;

  /// 从已添加的媒体源中匹配到的剧集（按 animeId）。
  List<TvLibraryEpisode> _matchedEpisodes = const [];
  String? _matchedSourceName;
  bool _searchingEpisodes = true;

  String get _title {
    final a = widget.anime;
    if (a != null) return a.nameCn.isNotEmpty ? a.nameCn : a.name;
    return widget.item!.title;
  }

  String get _backdrop {
    final a = widget.anime;
    // 直连原图：TV 没有普通版的本地 web 图片代理，不能用 imageProxyUrl。
    return a?.backgroundImageUrl?.isNotEmpty == true
        ? a!.backgroundImageUrl!
        : (a?.imageUrl ?? widget.item?.coverUrl ?? '');
  }

  @override
  void initState() {
    super.initState();
    _loadExtra();
  }

  /// 从已添加的媒体源中查找本番剧的可播放剧集。
  ///
  /// 排行榜条目本身没有媒体源；这里按 animeId / 标题去各源（弹弹远程、
  /// WebDAV）里匹配，命中后剧集区直接可播——解决"已加弹弹却仍提示需绑定"。
  Future<void> _matchEpisodes() async {
    final sources = await TvMediaSourceStore.load();
    if (sources.isEmpty) {
      if (mounted) setState(() => _searchingEpisodes = false);
      return;
    }
    final animeId = widget.anime?.id ?? widget.item?.animeId;
    final title = _title;
    for (final src in sources) {
      if (src.kind != TvSourceKind.dandanplayRemote &&
          src.kind != TvSourceKind.webdav) {
        continue;
      }
      try {
        final items = await TvLibraryLoader.load(
          kind: src.kind.name,
          location: src.location,
          username: src.username,
          password: src.password,
          token: src.token,
        );
        for (final it in items) {
          final idMatch = animeId != null &&
              animeId > 0 &&
              it.animeId != null &&
              it.animeId == animeId;
          final titleMatch = _titlesSimilar(it.title, title);
          if ((idMatch || titleMatch) && it.episodes.isNotEmpty) {
            if (!mounted) return;
            setState(() {
              _matchedEpisodes = it.episodes;
              _matchedSourceName = src.name;
              _searchingEpisodes = false;
            });
            return;
          }
        }
      } catch (_) {
        // 单个源失败不影响其它源
      }
    }
    if (mounted) setState(() => _searchingEpisodes = false);
  }

  /// 标题相似判定（去空格/标点，忽略大小写，包含即算命中）。
  bool _titlesSimilar(String a, String b) {
    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-_·:：!！?？,，.。~～]'), '');
    final na = norm(a);
    final nb = norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na.contains(nb) || nb.contains(na);
  }

  /// 加载补充信息：番剧详情（简介/评分）与评论。
  /// 榜单条目只带基础字段，详情与评论需另行请求弹弹网关。
  Future<void> _loadExtra() async {
    await _matchEpisodes();
    final animeId = widget.anime?.id ?? widget.item?.animeId;
    if (animeId == null || animeId <= 0) {
      if (mounted) setState(() => _loadingExtra = false);
      return;
    }
    final client = TvTrendingClient.instance;
    final detail = await client.fetchAnimeDetail(animeId);
    final comments = await client.fetchComments(animeId);
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _comments = comments;
      _loadingExtra = false;
    });
  }

  /// 优先用详情数据，回退到榜单自带字段。
  BangumiAnime? get _effectiveAnime => _detail ?? widget.anime;

  @override
  Widget build(BuildContext context) {
    final a = _effectiveAnime;
    final item = widget.item;
    // 剧集来源优先级：媒体库条目自带 > 从媒体源匹配到
    final episodes = (item?.episodes.isNotEmpty ?? false)
        ? item!.episodes
        : _matchedEpisodes;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F12),
      body: Stack(
        children: [
          // 全屏背景（毛玻璃式压暗，与普通版一致）
          Positioned.fill(child: _backdropImage()),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0B0F12).withValues(alpha: 0.55),
                    const Color(0xFF0B0F12).withValues(alpha: 0.92),
                    const Color(0xFF0B0F12),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 返回
                  _FocusableButton(
                    focusNode: widget.entryFocusNode,
                    icon: Icons.arrow_back,
                    label: '返回',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: 22),
                  Text(_title,
                      style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.15)),
                  if (a != null && a.name.isNotEmpty && a.nameCn.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(a.name,
                          style: const TextStyle(
                              fontSize: 15, color: Colors.white38)),
                    ),
                  const SizedBox(height: 10),
                  _metaRow(a),
                  const SizedBox(height: 18),
                  if ((a?.summary ?? '').isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Text(
                        a!.summary!,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white70,
                            height: 1.7),
                      ),
                    ),
                  const SizedBox(height: 24),
                  // 剧集区
                  Row(
                    children: [
                      const Text('剧集',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(width: 12),
                      Text(
                        episodes.isNotEmpty
                            ? '共 ${episodes.length} 集'
                                '${_matchedSourceName != null ? ' · 来源：$_matchedSourceName' : ''}'
                            : (_searchingEpisodes
                                ? '正在匹配媒体来源…'
                                : (item != null ? '该来源无可播放剧集' : '未找到匹配的媒体来源')),
                        style: const TextStyle(
                            fontSize: 14, color: Colors.white38),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (episodes.isEmpty)
                    _searchingEpisodes
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Row(
                              children: [
                                SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF26C6DA))),
                                SizedBox(width: 10),
                                Text('正在从已添加的媒体来源中匹配剧集…',
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 15)),
                              ],
                            ),
                          )
                        : _episodePlaceholder(item != null)
                  else
                    _episodeGrid(episodes),
                  const SizedBox(height: 28),
                  _commentsSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backdropImage() {
    final url = _backdrop;
    if (url.isEmpty) return const ColoredBox(color: Color(0xFF0B0F12));
    return Image.network(
      url,
      fit: BoxFit.cover,
      headers: const {'User-Agent': 'NipaPlay/1.0'},
      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF0B0F12)),
    );
  }

  Widget _metaRow(BangumiAnime? a) {
    final chips = <String>[];
    if (a?.platform != null && a!.platform!.isNotEmpty) chips.add(a.platform!);
    if (a?.airDate != null && a!.airDate!.isNotEmpty) {
      chips.add(a.airDate!.length >= 4 ? a.airDate!.substring(0, 4) : a.airDate!);
    }
    if (a?.totalEpisodes != null) chips.add('共 ${a!.totalEpisodes} 集');
    if (widget.item != null) chips.add(widget.item!.sourceLabel);
    return Row(
      children: [
        for (final c in chips) ...[
          Text(c, style: const TextStyle(fontSize: 14, color: Colors.white54)),
          const SizedBox(width: 14),
        ],
        if (a != null && (a.rating ?? 0) > 0) ...[
          const Icon(Icons.star, size: 16, color: Color(0xFFFFC107)),
          const SizedBox(width: 4),
          Text(a.rating!.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFFFFC107),
                  fontWeight: FontWeight.w700)),
        ],
      ],
    );
  }

  Widget _episodeGrid(List<TvLibraryEpisode> episodes) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        for (var i = 0; i < episodes.length; i++)
          _EpisodeTile(
            episode: episodes[i],
            index: i,
            selected: i == _episodeIndex,
            onActivate: () {
              setState(() => _episodeIndex = i);
              _play(episodes[i]);
            },
          ),
      ],
    );
  }

  Widget _commentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('评论',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(width: 12),
            Text(
              _loadingExtra
                  ? '加载中…'
                  : (_comments.isEmpty ? '暂无评论' : '共 ${_comments.length} 条'),
              style: const TextStyle(fontSize: 14, color: Colors.white38),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_comments.isEmpty)
          Text(
            _loadingExtra ? '正在获取评论…' : '该番剧暂无评论，或未登录弹弹play账号。',
            style: const TextStyle(color: Colors.white38, fontSize: 15),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              children: [
                for (final c in _comments.take(10))
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              c.userName.isNotEmpty ? c.userName : '匿名',
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF26C6DA),
                                  fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            if (c.rating > 0) ...[
                              const Icon(Icons.star,
                                  size: 14, color: Color(0xFFFFC107)),
                              const SizedBox(width: 3),
                              Text('${c.rating}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFFFC107))),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(c.text,
                            style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                                height: 1.6)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _episodePlaceholder(bool fromLibrary) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            const Icon(Icons.link_off, color: Colors.white38, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                fromLibrary
                    ? '该条目下没有可播放的视频文件'
                    : '未在已添加的媒体来源中找到本番剧。\n'
                        '请在「媒体库」添加 WebDAV / 弹弹远程服务（并确认已钉选），'
                        '剧集会自动匹配显示。',
                style: const TextStyle(color: Colors.white60, fontSize: 15),
              ),
            ),
          ],
        ),
      );

  Future<void> _play(TvLibraryEpisode ep) async {
    if (ep.playUri.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TvPlayerPage(
          source: MediaSource(uri: ep.playUri),
          title: '$_title · ${ep.title}',
        ),
      ),
    );
  }
}

/// 剧集瓦片（16:9 缩略图 + 标题），TV 焦点可导航。
class _EpisodeTile extends StatefulWidget {
  const _EpisodeTile({
    required this.episode,
    required this.index,
    required this.selected,
    required this.onActivate,
  });

  final TvLibraryEpisode episode;
  final int index;
  final bool selected;
  final VoidCallback onActivate;

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hot = _focused || _hovered;
    final accent = const Color(0xFF26C6DA);
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onActivate();
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
          onTap: widget.onActivate,
          child: SizedBox(
            width: 240,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: hot
                          ? accent
                          : (widget.selected ? accent : Colors.white24),
                      width: hot ? 3 : (widget.selected ? 2 : 1),
                    ),
                    boxShadow: hot
                        ? [
                            BoxShadow(
                                color: accent.withValues(alpha: 0.35),
                                blurRadius: 18)
                          ]
                        : const [],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: Colors.white.withValues(alpha: 0.06),
                            child: const Center(
                              child: Icon(Icons.play_circle_outline,
                                  size: 34, color: Colors.white38),
                            ),
                          ),
                          if (widget.episode.thumbnailUrl.isNotEmpty)
                            Image.network(
                              widget.episode.thumbnailUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            ),
                          if (widget.episode.matched)
                            const Positioned(
                              top: 6,
                              right: 6,
                              child: Icon(Icons.check_circle,
                                  size: 18, color: Color(0xFF4CAF50)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '第 ${widget.index + 1} 话  ${widget.episode.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: hot ? Colors.white : Colors.white70,
                    fontWeight: hot ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 简洁可聚焦按钮（详情页返回等）。
class _FocusableButton extends StatefulWidget {
  const _FocusableButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  State<_FocusableButton> createState() => _FocusableButtonState();
}

class _FocusableButtonState extends State<_FocusableButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _focused
                ? const Color(0xFF26C6DA).withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? const Color(0xFF26C6DA) : Colors.white24,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Text(widget.label,
                  style: const TextStyle(fontSize: 15, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}
