import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nipaplay_core/services/dandanplay_remote_service.dart';
import 'package:nipaplay_core/services/webdav_service.dart';
import 'package:nipaplay_core/utils/settings_storage.dart';
import 'package:nipaplay_ui_common/l10n/app_localizations.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';
import 'package:nipaplay_ui_common/media_library/unified_library_management_model.dart';

import '../../data/tv_account_service.dart';
import '../../data/tv_library_loader.dart';
import 'home_page.dart' show TvActionChip;
import '../../data/tv_media_sources.dart';
import 'anime_detail_page.dart';
import '../focusable_card.dart';
import '../widgets/tv_anime_card.dart';
import '../widgets/tv_input_dialog.dart';

/// 媒体库页：添加/管理媒体源（本地文件、WebDAV、媒体服务器、SMB）。
///
/// 源列表经 core 的 [SettingsStorage] 持久化（SharedPreferences 字符串列表）。
/// 播放与远程协议接入在后续阶段挂到 core 的 webdav_service / 媒体服务器服务上。
class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    this.entryFocusNode,
    this.activeSourceIndex,
    this.sourceRequestId,
    this.initialContentSource,
    this.onSourcesChanged,
  });

  /// 壳在切换到本页时把焦点交给这里的入口卡片（"添加媒体"）。
  final FocusNode? entryFocusNode;

  /// 由侧栏「媒体连接」点入时指定的源下标（用于高亮/自动加载）。
  final int? activeSourceIndex;

  /// 请求令牌：同一来源被重复点击时值也会变化，确保刷新生效。
  final int? sourceRequestId;

  /// 侧栏点入的源 key（`kind|location`）；非空时直接进入该源的番剧列表。
  final String? initialContentSource;

  /// 媒体源变化回调（供壳刷新侧栏列表）。
  final VoidCallback? onSourcesChanged;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryManagementViewMode _viewMode = LibraryManagementViewMode.list;
  final List<TvMediaSource> _sources = [];
  bool _loading = true;
  String? _testing;
  String? _focusedSource;
  String? _selectedSource;  // 侧栏点入的来源（过滤内容区）

  /// 番剧列表页：点入某源后展示该源的番剧卡片。
  bool _showContent = false;
  String _sortMode = 'recent'; // recent | name | episodes
  List<TvLibraryItem> _contentItems = const [];
  String? _contentSourceName;
  bool _isContentLoading = false;
  String? _contentMessage;
  // 每个源的加载结果与错误（key = location）
  final Map<String, List<TvLibraryItem>> _contents = {};
  final Map<String, String> _loadErrors = {};
  final Set<String> _loadingSources = {};

  @override
  void initState() {
    super.initState();
    _load();
    // 由侧栏「媒体连接」点入：自动加载对应源的内容
    final idx = widget.activeSourceIndex;
    if (idx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoOpen(idx));
    }
  }

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final idx = widget.activeSourceIndex;
    // 令牌变化即触发（即使下标相同）
    if (widget.sourceRequestId != oldWidget.sourceRequestId && idx != null) {
      _autoOpen(idx);
    }
    // 侧栏点入某源：直接进入番剧列表页
    final key = widget.initialContentSource;
    if (key != null && key != oldWidget.initialContentSource) {
      _enterContent(key, _nameOfLocation(key.split('|').last));
    }
  }

  /// 进入某源的番剧列表页（侧栏点入）。
  void _enterContent(String sourceKey, String sourceName) {
    debugPrint('[TVLib] _enterContent key=$sourceKey '
        'sources=${_sources.length}');
    setState(() {
      _showContent = true;
      _selectedSource = sourceKey;
      _contentSourceName = sourceName;
      _isContentLoading = true;
      _contentMessage = null;
      _contentItems = const [];
    });
    final entry = _sources.firstWhere(
      (e) => '${e.kind.name}|${e.location}' == sourceKey,
      orElse: () => _sources.first,
    );
    debugPrint('[TVLib] _enterContent matched=${entry.kind.name} '
        'loc=${entry.location}');
    if (!_contents.containsKey(entry.location)) {
      _loadContent(entry);
    } else {
      setState(() => _contentItems = _contents[entry.location] ?? const []);
    }
  }

  /// 返回媒体源列表。
  void _leaveContent() {
    setState(() {
      _showContent = false;
      _contentItems = const [];
      _contentSourceName = null;
    });
  }

  Future<void> _autoOpen(int index) async {
    // 等待源列表加载完成。
    // 必须用「当前值」判断：_load() 完成后会把 _loading 置 false，
    // 但那时 _sources 已经就绪，无需任何轮询等待。
    if (_loading) {
      // 初次由壳调用时尚在加载：轮询等待，但设置硬超时避免无限挂起
      var waited = 0;
      while (_loading && waited < 5000) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        waited += 50;
        if (!mounted) return;
      }
    }
    if (!mounted || index < 0 || index >= _sources.length) return;
    final entry = _sources[index];
    // 切到列表视图（内容更清晰）并标记当前来源
    setState(() {
      _viewMode = LibraryManagementViewMode.list;
      _focusedSource = entry.location;
      _selectedSource = entry.location;
    });
    if (!_contents.containsKey(entry.location) &&
        !_loadingSources.contains(entry.location)) {
      await _loadContent(entry);
    }
  }

  Future<void> _load() async {
    final list = await TvMediaSourceStore.load();
    if (mounted) {
      setState(() {
        _sources
          ..clear()
          ..addAll(list);
        _loading = false;
      });
    }
    // 已有源：后台自动加载内容
    for (final e in list) {
      if (e.kind == TvSourceKind.webdav ||
          e.kind == TvSourceKind.dandanplayRemote) {
        unawaited(_loadContent(e));
      }
    }
  }

  Future<void> _persist() async {
    await TvMediaSourceStore.save(_sources);
    widget.onSourcesChanged?.call();
  }

  Future<void> _addSource(TvSourceKind kind) async {
    final result = await showDialog<TvMediaSource>(
      context: context,
      builder: (_) => _AddMediaDialog(kind: kind),
    );
    if (result == null) return;
    setState(() => _sources.add(result));
    await _persist();
    // 添加后立即尝试加载内容
    await _loadContent(result);
  }

  /// 加载某个源的番剧列表（弹弹远程 / WebDAV）。
  Future<void> _loadContent(TvMediaSource entry) async {
    final key = entry.location;
    setState(() {
      _loadingSources.add(key);
      _loadErrors.remove(key);
      if (_selectedSource != null &&
          key == _selectedSource!.split('|').last) {
        _isContentLoading = true;
        _contentMessage = null;
      }
    });
    try {
      await TvAccountService.instance.load();
      final items = await TvLibraryLoader.load(
        kind: entry.kind.name,
        location: entry.location,
        username: entry.username,
        password: entry.password,
        token: entry.token,
        accountToken: TvAccountService.instance.isLoggedIn
            ? TvAccountService.instance.authHeaders()['Authorization']
                ?.replaceFirst('Bearer ', '')
            : null,
      );
      if (!mounted) return;
      setState(() {
        _contents[key] = items;
        _loadingSources.remove(key);
        _isContentLoading = false;
        if (_selectedSource != null &&
            key == _selectedSource!.split('|').last) {
          _contentItems = items;
        }
        if (items.isEmpty) {
          _loadErrors[key] = '该来源没有可显示的番剧内容';
          if (_selectedSource != null &&
              key == _selectedSource!.split('|').last) {
            _contentMessage = '该来源没有番剧内容（可点条目上的「测试连接」查看原因）';
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSources.remove(key);
        _loadErrors[key] = '$e';
        _isContentLoading = false;
        if (_selectedSource != null &&
            key == _selectedSource!.split('|').last) {
          _contentItems = const [];
          _contentMessage = '加载失败：$e';
        }
      });
    }
  }

  /// 钉选/取消钉选到侧边栏（用户手动选择）。
  Future<void> _togglePin(int index) async {
    final cur = _sources[index];
    setState(() {
      _sources[index] = cur.copyWith(pinned: !cur.pinned);
    });
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(cur.pinned ? '已取消钉选' : '已钉选到侧边栏'),
      duration: const Duration(seconds: 2),
    ));
  }

  /// 测试已添加来源的连通性。
  ///
  /// - WebDAV：走 core 的 [WebDAVService.testConnection]（与普通版同一实现）；
  /// - 弹弹远程：走 core 的 [DandanplayRemoteService.connect]，**需先登录账号**；
  /// - 其它类型：仅做 URL 可达性提示（暂无专用客户端）。
  Future<void> _testSource(TvMediaSource entry) async {
    setState(() => _testing = entry.location);
    String message;
    bool ok = false;
    try {
      switch (entry.kind) {
        case TvSourceKind.webdav:
          ok = await WebDAVService.instance.testConnection(
            WebDAVConnection(
              name: entry.name,
              url: entry.location,
              username: entry.username ?? '',
              password: entry.password ?? '',
            ),
          );
          message = ok ? 'WebDAV 连接成功' : 'WebDAV 连接失败（请检查地址与账号密码）';
          break;
        case TvSourceKind.dandanplayRemote:
          if (!TvAccountService.instance.isLoggedIn) {
            message = '弹弹远程服务需先登录账号（「我的」→ 登录）';
            break;
          }
          ok = await DandanplayRemoteService.instance.connect(
            entry.location,
            token: entry.token ??
                (TvAccountService.instance.isLoggedIn
                    ? TvAccountService.instance.token
                    : null),
          );
          message = ok ? '弹弹远程服务连接成功' : '弹弹远程服务连接失败';
          break;
        case TvSourceKind.emby:
        case TvSourceKind.jellyfin:
        case TvSourceKind.smb:
        case TvSourceKind.localFile:
        case TvSourceKind.localFolder:
        case TvSourceKind.url:
          message = '该类型暂不支持连通性测试（已保存地址）';
          ok = true;
          break;
      }
    } catch (e) {
      ok = false;
      message = '连接失败：$e';
    }
    if (!mounted) return;
    setState(() => _testing = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: ok ? const Color(0xFF2E7D32) : const Color(0xFFB71C1C),
    ));
    // 连接成功后自动加载该源的番剧列表
    if (ok) await _loadContent(entry);
  }

  Future<void> _removeSource(int index) async {
    final removed = _sources[index];
    setState(() => _sources.removeAt(index));
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已移除「${removed.name}」')),
    );
  }

  IconData _iconOf(LibraryManagementIcon icon) => switch (icon) {
        LibraryManagementIcon.folder => Icons.folder_outlined,
        LibraryManagementIcon.video => Icons.smart_display_outlined,
        LibraryManagementIcon.file => Icons.insert_drive_file_outlined,
        LibraryManagementIcon.cloud => Icons.cloud_outlined,
        LibraryManagementIcon.server => Icons.dns_outlined,
        LibraryManagementIcon.browse => Icons.travel_explore,
        LibraryManagementIcon.refresh => Icons.refresh,
        LibraryManagementIcon.scan => Icons.radar,
        LibraryManagementIcon.info => Icons.info_outline,
        LibraryManagementIcon.subtitles => Icons.subtitles_outlined,
        LibraryManagementIcon.edit => Icons.edit_outlined,
        LibraryManagementIcon.delete => Icons.delete_outline,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_showContent) return _contentPage(context, l10n);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.tabMediaLibrary,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(width: 20),
              // 主入口：添加媒体（默认聚焦，确认键/点按均可用）
              FocusableCard(
                focusNode: widget.entryFocusNode,
                onActivate: () => _addSource(TvSourceKind.localFile),
                borderRadius: 12,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_circle_outline, size: 22),
                    const SizedBox(width: 8),
                    Text('添加媒体',
                        style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
              ),
              const Spacer(),
              // 视图模式切换
              for (var i = 0;
                  i < LibraryManagementViewMode.values.length;
                  i++)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: FocusableCard(
                    onActivate: () => setState(() =>
                        _viewMode = LibraryManagementViewMode.values[i]),
                    borderRadius: 10,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    selected:
                        _viewMode == LibraryManagementViewMode.values[i],
                    child: Icon(
                      LibraryManagementViewMode.values[i] ==
                              LibraryManagementViewMode.icons
                          ? Icons.grid_view
                          : Icons.view_list,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('添加来源',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Colors.white54)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final kind in TvSourceKind.values)
                FocusableCard(
                  onActivate: () => _addSource(kind),
                  borderRadius: 12,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(kind.icon, size: 22),
                      const SizedBox(width: 10),
                      Text(kind.label,
                          style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              Text('已添加 (${_sources.length})',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: Colors.white54)),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF26C6DA))),
            )
          else if (_sources.isEmpty)
            _emptyState(context)
          else if (_viewMode == LibraryManagementViewMode.icons)
            Wrap(
              spacing: 20,
              runSpacing: 24,
              children: [
                for (var i = 0; i < _sources.length; i++)
                  _cardWithDelete(context, i),
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < _sources.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _sourceCard(context, i),
                  ),
              ],
            ),
          _contentSection(context),
        ],
      ),
    );
  }

  /// 卡片视图：番剧卡片 + 悬浮删除按钮（沿用普通版新版卡片的视觉语言）。
  Widget _cardWithDelete(BuildContext context, int index) {
    final entry = _sources[index];
    return SizedBox(
      width: 200,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          TvAnimeCard(
            name: entry.name,
            imageUrl: '',
            source: entry.pinned
                ? '${entry.kind.label} · 已钉选'
                : entry.kind.label,
            rating: entry.rating,
            showNewBadge: entry.isNew,
            onTap: () => _testSource(entry),
          ),
          // 钉选（左上）
          Positioned(
            top: -8,
            left: -8,
            child: FocusableCard(
              onActivate: () => _togglePin(index),
              borderRadius: 999,
              padding: const EdgeInsets.all(6),
              accentColor: entry.pinned
                  ? const Color(0xFF26C6DA)
                  : Colors.white24,
              child: Icon(
                entry.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 16,
              ),
            ),
          ),
          // 删除（右上）
          Positioned(
            top: -8,
            right: -8,
            child: FocusableCard(
              onActivate: () => _removeSource(index),
              borderRadius: 999,
              padding: const EdgeInsets.all(6),
              accentColor: Colors.redAccent,
              child: const Icon(Icons.close, size: 16),
            ),
          ),
          if (_testing == entry.location)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x99000000),
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Color(0xFF26C6DA)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 番剧列表页：展示某源加载到的番剧卡片（新版卡片视觉）。
  Widget _contentPage(BuildContext context, AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            FocusableCard(
              onActivate: _leaveContent,
              borderRadius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back, size: 18, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text('返回',
                      style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _contentSourceName ?? '番剧',
                style: Theme.of(context).textTheme.headlineMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 排序切换
            FocusableCard(
              onActivate: _cycleSort,
              borderRadius: 10,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort, size: 18, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(_sortLabel,
                      style: const TextStyle(
                          fontSize: 14, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_contentItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  if (_isContentLoading)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF26C6DA)),
                    )
                  else
                    const Icon(Icons.cloud_off,
                        size: 40, color: Colors.white24),
                  const SizedBox(height: 14),
                  Text(
                    _contentMessage ?? '该来源暂无番剧内容',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 15),
                  ),
                ],
              ),
            ),
          )
        else
          // 网格布局：列数随可用宽度自适应（TV 大屏可容纳更多列）
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              const spacing = 20.0;
              // 自适应列数：先扣掉边距，再按目标卡片宽求列数
              final usable = width - 24 * 2; // 页面左右 padding
              final cols = (usable / (96 + spacing)).floor().clamp(2, 12);
              final cardWidth = (usable - spacing * (cols - 1)) / cols;
              return Wrap(
                spacing: spacing,
                runSpacing: 24,
                children: [
                  for (final item in _contentItems)
                    SizedBox(
                      width: cardWidth,
                      child: TvAnimeCard(
                        name: item.title,
                        imageUrl: item.coverUrl,
                        source: item.sourceLabel,
                        episodeLabel: item.episodeLabel,
                        rating: item.rating,
                        showNewBadge: item.isNew,
                        onTap: () => _openDetail(context, item),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  /// 内容区：把各源加载到的番剧以新版卡片呈现。
  Widget _contentSection(BuildContext context) {
    var entries = _contents.entries
        .where((e) => (e.value.isNotEmpty) || _loadErrors.containsKey(e.key))
        .toList();
    // 侧栏点入某来源时，只显示该来源
    final selected = _selectedSource;
    if (selected != null) {
      entries = entries.where((e) => e.key == selected).toList();
    }
    // 按当前排序方式整理
    entries = _sortedEntries(entries);
    if (entries.isEmpty && _loadingSources.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 26),
        Row(
          children: [
            Text(
              selected == null
                  ? '番剧'
                  : '番剧 · ${_nameOfLocation(selected)}',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Colors.white54),
            ),
            if (selected != null) ...[
              const SizedBox(width: 14),
              TvActionChip(
                icon: Icons.grid_view,
                label: '显示全部',
                onTap: () => setState(() => _selectedSource = null),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        for (final e in entries) ...[
          if (_loadErrors.containsKey(e.key))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('${e.key}：${_loadErrors[e.key]}',
                  style: const TextStyle(
                      color: Colors.orangeAccent, fontSize: 13)),
            ),
          if (e.value.isNotEmpty)
            Wrap(
              spacing: 20,
              runSpacing: 24,
              children: [
                for (final item in e.value)
                  TvAnimeCard(
                    name: item.title,
                    imageUrl: item.coverUrl,
                    source: item.sourceLabel,
                    episodeLabel: item.episodeLabel,
                    rating: item.rating,
                    showNewBadge: item.isNew,
                    onTap: () => _openDetail(context, item),
                  ),
              ],
            ),
        ],
        if (_loadingSources.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF26C6DA))),
                SizedBox(width: 10),
                Text('正在加载番剧列表…',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
              ],
            ),
          ),
      ],
    );
  }

  /// 按当前排序方式整理内容条目。
  List<MapEntry<String, List<TvLibraryItem>>> _sortedEntries(
      List<MapEntry<String, List<TvLibraryItem>>> entries) {
    final copy = List.of(entries);
    switch (_sortMode) {
      case 'name':
        copy.sort((a, b) {
          final ta = a.value.isEmpty ? '' : a.value.first.title;
          final tb = b.value.isEmpty ? '' : b.value.first.title;
          return ta.compareTo(tb);
        });
        break;
      case 'episodes':
        copy.sort((a, b) {
          final ea = a.value.fold<int>(0, (s, e) => s + e.episodes.length);
          final eb = b.value.fold<int>(0, (s, e) => s + e.episodes.length);
          return eb.compareTo(ea);
        });
        break;
      default: // recent：按最新加入的顺序（即加载顺序）
        break;
    }
    return copy;
  }

  void _cycleSort() {
    const modes = ['recent', 'name', 'episodes'];
    final idx = modes.indexOf(_sortMode);
    setState(() => _sortMode = modes[(idx + 1) % modes.length]);
  }

  String get _sortLabel => switch (_sortMode) {
        'name' => '名称排序',
        'episodes' => '集数排序',
        _ => '最近添加',
      };

  String _nameOfLocation(String location) {
    for (final s in _sources) {
      if (s.location == location) return s.name;
    }
    return location;
  }

  Future<void> _openDetail(BuildContext context, TvLibraryItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TvAnimeDetailPage(item: item)),
    );
  }

  Widget _emptyState(BuildContext context) {
    final empty = LibraryManagementEmptyContent(
      title: '还没有媒体来源',
      subtitle: '点击上方「添加媒体」或选择来源类型开始添加',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(_iconOf(LibraryManagementIcon.folder),
                size: 72, color: Colors.white24),
            const SizedBox(height: 12),
            Text(empty.title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white60)),
            const SizedBox(height: 6),
            Text(empty.subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white38)),
          ],
        ),
      ),
    );
  }

  Widget _sourceCard(BuildContext context, int index) {
    final entry = _sources[index];
    final focused = _focusedSource == entry.location;
    return FocusableCard(
      onActivate: () {},
      selected: focused,
      child: Row(
        children: [
          Icon(entry.kind.icon,
              size: 26, color: const Color(0xFF26C6DA)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(_testing == entry.location
                        ? '测试连接中…'
                        : '${entry.kind.label} · ${entry.location}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white38)),
              ],
            ),
          ),
          // 删除（触摸/确认键均可）
          FocusableCard(
            onActivate: () => _togglePin(index),
            borderRadius: 10,
            padding: const EdgeInsets.all(8),
            accentColor:
                entry.pinned ? const Color(0xFF26C6DA) : Colors.white24,
            child: Icon(
              entry.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          FocusableCard(
            onActivate: () => _testSource(entry),
            borderRadius: 10,
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.wifi_tethering, size: 20),
          ),
          const SizedBox(width: 8),
          FocusableCard(
            onActivate: () => _removeSource(index),
            borderRadius: 10,
            padding: const EdgeInsets.all(8),
            accentColor: Colors.redAccent,
            child: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

/// 可添加的来源类型。
class _AddMediaDialog extends StatefulWidget {
  const _AddMediaDialog({required this.kind});
  final TvSourceKind kind;

  @override
  State<_AddMediaDialog> createState() => _AddMediaDialogState();
}

class _AddMediaDialogState extends State<_AddMediaDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _locCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;

  bool get _needsAuth => widget.kind == TvSourceKind.webdav;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _locCtrl = TextEditingController();
    _userCtrl = TextEditingController();
    _passCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String get _hint => switch (widget.kind) {
        TvSourceKind.localFile => '/storage/emulated/0/Movies/demo.mp4',
        TvSourceKind.localFolder => '/storage/emulated/0/Movies',
        TvSourceKind.webdav => 'https://example.com/dav',
        TvSourceKind.emby => 'http://192.168.1.10:8096',
        TvSourceKind.jellyfin => 'http://192.168.1.10:8096',
        TvSourceKind.smb => 'smb://192.168.1.10/share',
        TvSourceKind.dandanplayRemote => 'http://192.168.3.39:30000',
        TvSourceKind.url => 'https://example.com/stream.m3u8',
      };

  void _submit() {
    final loc = _locCtrl.text.trim();
    if (loc.isEmpty) return;
    final name = _nameCtrl.text.trim().isEmpty
        ? widget.kind.label
        : _nameCtrl.text.trim();
    Navigator.of(context).pop(
      TvMediaSource(
        name: name,
        location: loc,
        kind: widget.kind,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TvInputDialog(
      title: '添加 ${widget.kind.label}',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('添加')),
      ],
      children: [
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '名称（可选）',
            hintText: '例如：我的电影',
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (widget.kind == TvSourceKind.dandanplayRemote)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('弹弹远程服务需先在「我的」登录弹弹play账号',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 13)),
          ),
        const SizedBox(height: 14),
        TextField(
          controller: _locCtrl,
          decoration: InputDecoration(labelText: '地址', hintText: _hint),
          onSubmitted: (_) => _submit(),
        ),
        if (_needsAuth) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ],
    );
  }
}
