import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay_core/models/trending_bangumi.dart';
import 'package:nipaplay_core/player/nipa_player.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';

import '../../data/tv_recent_play_store.dart';
import '../../data/tv_account_service.dart';
import '../../data/tv_trending_client.dart';
import '../widgets/tv_anime_card.dart';
import 'anime_detail_page.dart';
import 'player_page.dart';

/// 首页：Bangumi 排行榜新番 Top10 + 最近播放。
///
/// 封面与榜单均来自 Bangumi/弹弹网关（经 core 的服务器路由，跟随用户镜像设置）。
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.entryFocusNode, this.onRequestLogin});

  final FocusNode? entryFocusNode;

  /// 未登录时点击「去登录」：由壳切到「我的」页。
  final VoidCallback? onRequestLogin;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<TrendingBangumiItem>? _trending;
  List<TvRecentPlay> _recent = const [];
  Object? _error;
  bool _needLogin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _needLogin = false;
    });
    await TvAccountService.instance.load();
    final recent = await TvRecentPlayStore.load();
    if (!mounted) return;
    setState(() => _recent = recent);
    try {
      final items = await TvTrendingClient.instance.fetchTop(limit: 10);
      if (!mounted) return;
      setState(() {
        _trending = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _needLogin = e is TvLoginRequiredException;
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text(l10n.tabHome,
                style: Theme.of(context).textTheme.headlineMedium),
            const Spacer(),
            TvActionChip(
              focusNode: widget.entryFocusNode,
              icon: Icons.refresh,
              label: '刷新',
              onTap: _load,
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
                child: CircularProgressIndicator(color: Color(0xFF26C6DA))),
          )
        else ...[
          if (_needLogin)
            _loginPrompt(context)
          else if (_error != null)
            _errorBanner(context),
          _sectionTitle(context, 'Bangumi 排行榜 · 新番 Top10'),
          const SizedBox(height: 12),
          if (_trending != null && _trending!.isNotEmpty)
            SizedBox(
              height: 404,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _trending!.length,
                separatorBuilder: (_, _) => const SizedBox(width: 18),
                itemBuilder: (context, i) {
                  final item = _trending![i];
                  final anime = item.anime;
                  final title =
                      anime.nameCn.isNotEmpty ? anime.nameCn : anime.name;
                  return TvAnimeCard(
                    name: title,
                    imageUrl: anime.imageUrl,
                    rating: anime.rating,
                    isOnAir: anime.isOnAir ?? false,
                    showNewBadge: i < 3,
                    source: '第 ${item.rank} 名',
                    onTap: () => _openAnime(context, item),
                  );
                },
              ),
            )
          else
            _emptyHint(context, '排行榜暂无数据'),
          const SizedBox(height: 28),
          Row(
            children: [
              _sectionTitle(context, '最近播放'),
              const Spacer(),
              if (_recent.isNotEmpty)
                TvActionChip(
                  icon: Icons.delete_sweep_outlined,
                  label: '清空',
                  onTap: () async {
                    await TvRecentPlayStore.clear();
                    if (mounted) setState(() => _recent = const []);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_recent.isEmpty)
            _emptyHint(context, '还没有播放记录')
          else
            SizedBox(
              height: 404,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recent.length,
                separatorBuilder: (_, _) => const SizedBox(width: 18),
                itemBuilder: (context, i) {
                  final r = _recent[i];
                  return TvAnimeCard(
                    name: r.title,
                    imageUrl: r.coverUrl,
                    episodeLabel: r.episodeLabel,
                    source: r.sourceLabel.isNotEmpty
                        ? '${r.sourceLabel} · 最近播放'
                        : '最近播放',
                    onTap: () => _openRecent(context, r),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);

  Widget _emptyHint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Colors.white38)),
        ),
      );

  /// 未登录引导：排行榜由弹弹网关提供，需登录账号。
  Widget _loginPrompt(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF26C6DA).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: const Color(0xFF26C6DA).withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: Color(0xFF26C6DA), size: 22),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '排行榜由弹弹play网关提供，需登录账号后显示。\n请到「我的」登录弹弹play账号。',
                style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
              ),
            ),
            TvActionChip(
              icon: Icons.person_outline,
              label: '去登录',
              onTap: () => widget.onRequestLogin?.call(),
            ),
          ],
        ),
      );

  Widget _errorBanner(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, color: Colors.redAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  '排行榜加载失败：$_error\n可在「设置 → 网络」更换弹弹/Bangumi 服务器',
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ),
          ],
        ),
      );

  Future<void> _openRecent(BuildContext context, TvRecentPlay r) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TvPlayerPage(
          source: MediaSource(uri: r.sourceUri),
          title: r.title,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openAnime(BuildContext context, TrendingBangumiItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TvAnimeDetailPage(anime: item.anime)),
    );
  }

}

/// 可聚焦操作片：遥控确认键与触摸均可用（TV 遥控适配）。
class TvActionChip extends StatefulWidget {
  const TvActionChip({
    super.key,
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
  State<TvActionChip> createState() => _TvActionChipState();
}

class _TvActionChipState extends State<TvActionChip> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hot = _focused || _hovered;
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
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: hot
                  ? const Color(0xFF26C6DA).withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hot ? const Color(0xFF26C6DA) : Colors.white24,
                width: hot ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 18),
                const SizedBox(width: 8),
                Text(widget.label,
                    style:
                        const TextStyle(fontSize: 15, color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
