import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nipaplay_core/services/dandanplay_remote_service.dart';
import 'package:nipaplay_core/services/webdav_service.dart';
import 'package:nipaplay_core/utils/settings_storage.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';
import 'package:nipaplay_ui_common/media_library/unified_library_management_model.dart';

import '../../data/tv_account_service.dart';
import '../focusable_card.dart';
import '../widgets/tv_anime_card.dart';

/// 媒体库页：添加/管理媒体源（本地文件、WebDAV、媒体服务器、SMB）。
///
/// 源列表经 core 的 [SettingsStorage] 持久化（SharedPreferences 字符串列表）。
/// 播放与远程协议接入在后续阶段挂到 core 的 webdav_service / 媒体服务器服务上。
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.entryFocusNode});

  /// 壳在切换到本页时把焦点交给这里的入口卡片（"添加媒体"）。
  final FocusNode? entryFocusNode;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const _storageKey = 'tv.media_sources';

  LibraryManagementViewMode _viewMode = LibraryManagementViewMode.icons;
  final List<_MediaSourceEntry> _sources = [];
  bool _loading = true;
  String? _testing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await SettingsStorage.loadStringList(_storageKey);
    final list = <_MediaSourceEntry>[];
    for (final line in raw) {
      final entry = _MediaSourceEntry.tryDecode(line);
      if (entry != null) list.add(entry);
    }
    if (mounted) {
      setState(() {
        _sources
          ..clear()
          ..addAll(list);
        _loading = false;
      });
    }
  }

  Future<void> _persist() async {
    await SettingsStorage.saveStringList(
      _storageKey,
      _sources.map((e) => e.encode()).toList(),
    );
  }

  Future<void> _addSource(_SourceKind kind) async {
    final result = await showDialog<_MediaSourceEntry>(
      context: context,
      builder: (_) => _AddMediaDialog(kind: kind),
    );
    if (result == null) return;
    setState(() => _sources.add(result));
    await _persist();
  }

  /// 测试已添加来源的连通性。
  ///
  /// - WebDAV：走 core 的 [WebDAVService.testConnection]（与普通版同一实现）；
  /// - 弹弹远程：走 core 的 [DandanplayRemoteService.connect]，**需先登录账号**；
  /// - 其它类型：仅做 URL 可达性提示（暂无专用客户端）。
  Future<void> _testSource(_MediaSourceEntry entry) async {
    setState(() => _testing = entry.location);
    String message;
    bool ok = false;
    try {
      switch (entry.kind) {
        case _SourceKind.webdav:
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
        case _SourceKind.dandanplayRemote:
          if (!TvAccountService.instance.isLoggedIn) {
            message = '弹弹远程服务需先登录账号（「我的」→ 登录）';
            break;
          }
          ok = await DandanplayRemoteService.instance
              .connect(entry.location, token: entry.token);
          message = ok ? '弹弹远程服务连接成功' : '弹弹远程服务连接失败';
          break;
        case _SourceKind.emby:
        case _SourceKind.jellyfin:
        case _SourceKind.smb:
        case _SourceKind.localFile:
        case _SourceKind.localFolder:
        case _SourceKind.url:
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
                onActivate: () => _addSource(_SourceKind.localFile),
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
              for (final kind in _SourceKind.values)
                FocusableCard(
                  onActivate: () => _addSource(kind),
                  borderRadius: 12,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconOf(kind.icon), size: 22),
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
            imageUrl: entry.coverUrl,
            source: entry.kind.label,
            rating: entry.rating,
            showNewBadge: entry.isNew,
            onTap: () => _testSource(entry),
          ),
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
    return FocusableCard(
      onActivate: () {},
      child: Row(
        children: [
          Icon(_iconOf(entry.kind.icon),
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
enum _SourceKind {
  localFile('本地文件', LibraryManagementIcon.video),
  localFolder('本地文件夹', LibraryManagementIcon.folder),
  webdav('WebDAV', LibraryManagementIcon.cloud),
  emby('Emby', LibraryManagementIcon.server),
  jellyfin('Jellyfin', LibraryManagementIcon.server),
  smb('SMB 共享', LibraryManagementIcon.server),
  dandanplayRemote('弹弹远程服务', LibraryManagementIcon.cloud),
  url('网络串流 URL', LibraryManagementIcon.browse);

  const _SourceKind(this.label, this.icon);
  final String label;
  final LibraryManagementIcon icon;
}

/// 一条已添加的媒体来源（JSON 持久化到 core SettingsStorage）。
class _MediaSourceEntry {
  const _MediaSourceEntry({
    required this.name,
    required this.location,
    required this.kind,
    this.coverUrl = '',
    this.rating,
    this.isNew = false,
    this.username,
    this.password,
    this.token,
  });

  final String name;
  final String location;
  final _SourceKind kind;

  /// 封面（网络 URL 或本地路径）。
  final String coverUrl;
  final double? rating;
  final bool isNew;

  /// 认证信息（WebDAV 用账号密码；弹弹远程用 token）。
  final String? username;
  final String? password;
  final String? token;

  String encode() => jsonEncode({
        'n': name,
        'l': location,
        'k': kind.name,
        if (coverUrl.isNotEmpty) 'c': coverUrl,
        if (rating != null) 'r': rating,
        if (isNew) 'new': true,
        if (username != null && username!.isNotEmpty) 'un': username,
        if (password != null && password!.isNotEmpty) 'pw': password,
        if (token != null && token!.isNotEmpty) 'tk': token,
      });

  static _MediaSourceEntry? tryDecode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final kindName = map['k'] as String?;
      final kind = _SourceKind.values.firstWhere(
        (k) => k.name == kindName,
        orElse: () => _SourceKind.localFile,
      );
      return _MediaSourceEntry(
        name: (map['n'] as String?) ?? '未命名',
        location: (map['l'] as String?) ?? '',
        kind: kind,
        coverUrl: (map['c'] as String?) ?? '',
        rating: (map['r'] as num?)?.toDouble(),
        isNew: map['new'] == true,
        username: map['un'] as String?,
        password: map['pw'] as String?,
        token: map['tk'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 添加媒体对话框：名称 + 地址（路径/URL/服务器地址）。
class _AddMediaDialog extends StatefulWidget {
  const _AddMediaDialog({required this.kind});
  final _SourceKind kind;

  @override
  State<_AddMediaDialog> createState() => _AddMediaDialogState();
}

class _AddMediaDialogState extends State<_AddMediaDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _locCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;

  bool get _needsAuth => widget.kind == _SourceKind.webdav;

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
        _SourceKind.localFile => '/storage/emulated/0/Movies/demo.mp4',
        _SourceKind.localFolder => '/storage/emulated/0/Movies',
        _SourceKind.webdav => 'https://example.com/dav',
        _SourceKind.emby => 'http://192.168.1.10:8096',
        _SourceKind.jellyfin => 'http://192.168.1.10:8096',
        _SourceKind.smb => 'smb://192.168.1.10/share',
        _SourceKind.dandanplayRemote => 'http://192.168.3.39:30000',
        _SourceKind.url => 'https://example.com/stream.m3u8',
      };

  void _submit() {
    final loc = _locCtrl.text.trim();
    if (loc.isEmpty) return;
    final name = _nameCtrl.text.trim().isEmpty
        ? widget.kind.label
        : _nameCtrl.text.trim();
    Navigator.of(context).pop(
      _MediaSourceEntry(
        name: name,
        location: loc,
        kind: widget.kind,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A2026),
      title: Text('添加 ${widget.kind.label}'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            if (widget.kind == _SourceKind.dandanplayRemote)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('弹弹远程服务需先在「我的」登录弹弹play账号',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 13)),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _locCtrl,
              decoration: InputDecoration(
                labelText: '地址',
                hintText: _hint,
              ),
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('添加')),
      ],
    );
  }
}
