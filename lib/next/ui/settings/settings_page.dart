import 'dart:async';

import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/widgets.dart';

import '../data/settings_data.dart';
import '../shell/shell_controller.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';
import 'controls.dart';
import 'host_keys.dart';
import 'registry_rows.dart';
import 'section_accounts.dart';
import 'section_downloaders.dart';
import 'section_host.dart';
import 'section_misc.dart';
import 'section_peer.dart';
import 'section_more.dart';
import 'settings_layout.dart';

/// Where `/settings` opens: a section, and a setting in it to show.
class SettingsTarget {
  const SettingsTarget({this.section, this.key});
  final SettingsSection? section;
  final String? key;
}

Route<void> settingsRoute(RouteSettings settings) {
  final target = settings.arguments as SettingsTarget?;
  return PageRouteBuilder<void>(
    settings: settings,
    transitionDuration: NextMotion.page,
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => SettingsPage(target: target),
    transitionsBuilder: (context, animation, _, child) =>
        nextPageTransition(context, animation, child),
  );
}

/// What the debug driver may do with the page (see `NextUiDebug`).
abstract interface class SettingsDebug {
  Future<void> debug(Map<String, String> p);
  Map<String, Object?> debugStatus();
}

/// Settings: a quiet rail of sections on the left, the section on the
/// right. Ordinary settings come from the registry Nipa reads, so a new
/// one appears here and for her at once; what she changed carries her
/// mark. Esc, or any section of the bar, leaves.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.target});
  final SettingsTarget? target;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> implements SettingsDebug {
  late SettingsSection _section =
      widget.target?.section ?? SettingsSection.accounts;
  String? _highlight;
  Timer? _fade;
  NextShellController? _shell;
  SettingsModel? _model;
  HostKeys? _keys;
  final _scroll = ScrollController();
  final _more = <SettingsSection>{};
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'settings.search');
  final _sources = GlobalKey<SourcesSectionState>();
  final _devices = GlobalKey<DevicesSectionState>();
  final _nipa = GlobalKey<NipaSectionState>();
  final _storage = GlobalKey<StorageSectionState>();
  final _about = GlobalKey<AboutSectionState>();
  final _sync = GlobalKey<SyncSectionState>();
  final _plugins = GlobalKey<PluginsSectionState>();
  final _downloaders = GlobalKey<DownloadersSectionState>();

  /// A source to show opened, or `new` for one being added.
  String? _openSource;

  static const _words = <SettingsSection, String>{
    SettingsSection.accounts: '账号 登录 退出 弹弹play bangumi 同步 观看记录',
    SettingsSection.sources: '媒体来源 服务器 jellyfin emby smb webdav nas 网盘 库 共享 '
        '本机 文件夹 扫描 附近 nipaplay',
    SettingsSection.devices: '设备 组网 本机名 运行程序 远程 局域网 远程访问 信任 遥控 ipv6',
    SettingsSection.downloads: '下载 下载器 qbittorrent 种子 磁力 seedbox 做种 远端',
    SettingsSection.sync: '同步 多端 webdav 坚果云 nextcloud 服务器 备份 记录',
    SettingsSection.nipa: 'nipa 模型 codex api key 密钥 记忆 记得 提供方',
    SettingsSection.storage: '存储 缓存 清理 截图 空间 磁盘 缩略图',
    SettingsSection.shortcuts: '快捷键 按键 键盘',
    SettingsSection.plugins: '插件 扩展 市场 安装 脚本 js 弹幕源',
    SettingsSection.about: '关于 版本 更新 检查更新 新版本',
    SettingsSection.classic: '经典 classic 旧界面',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell?.settingsTarget.removeListener(_target);
    _shell?.chat.removeListener(_chatChanged);
    _shell = shell..settingsTarget.addListener(_target);
    shell.chat.addListener(_chatChanged);
    _mood = shell.chat.mood;
    _model ??= SettingsModel(shell.services.settings)..load();
    _keys ??= HostKeys(shell.services.settings.host)..load();
    if (widget.target?.key case final key?) _show(key);
  }

  /// Nipa may have changed settings in a turn: read them again when she
  /// is done (the registry does not announce changes yet).
  NipaMood? _mood;
  void _chatChanged() {
    final mood = _shell?.chat.mood;
    if (mood == _mood) return;
    final done = mood == NipaMood.idle && _mood != null;
    _mood = mood;
    if (done) _model?.load();
  }

  @override
  void dispose() {
    _shell?.chat.removeListener(_chatChanged);
    _shell?.settingsTarget.removeListener(_target);
    _model?.dispose();
    _keys?.dispose();
    _fade?.cancel();
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// ⌘, or a link while the page is open.
  void _target() {
    final target = _shell?.settingsTarget.value;
    if (target == null) return;
    _shell!.settingsTarget.value = null;
    if (target.key != null) return _show(target.key!);
    if (target.section != null) _go(target.section!);
  }

  void _go(SettingsSection section) {
    if (section == _section && _search.text.isEmpty) return;
    setState(() {
      _section = section;
      _search.clear();
      _highlight = null;
      _openSource = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// 媒体来源, a new source being added (the 片库's “添加来源”).
  void _addSource({String? type}) {
    _go(SettingsSection.sources);
    setState(() => _openSource = 'new');
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _sources.currentState?.show('new', type: type));
  }

  /// A setting where it lives, lit for a moment.
  void _show(String key) {
    if (key == SourcesSection.addKey) return _addSource();
    _fade?.cancel();
    setState(() {
      _section = SettingsLayout.sectionOf(key);
      _search.clear();
      _highlight = key;
      // Arriving at a folded setting leaves its fold open.
      if (SettingsLayout.folded(key)) _more.add(_section);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _rowContext(key);
      if (row != null) {
        Scrollable.ensureVisible(row,
            alignment: 0.35,
            duration: const Duration(milliseconds: 420),
            curve: NextMotion.ease);
      }
    });
    _fade = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _highlight = null);
    });
  }

  BuildContext? _rowContext(String key) {
    BuildContext? found;
    void visit(Element e) {
      if (found != null) return;
      final w = e.widget;
      if (w is RegistryRow && w.setting.key == key) {
        found = e;
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  bool _isMore(SettingsSection s) => _more.contains(s);
  void _toggleMore(SettingsSection s) => setState(() {
        if (!_more.remove(s)) _more.add(s);
      });

  Widget _body(SettingsSection section) {
    final model = _model!;
    final data = model.data;
    final shell = _shell!;
    final keys = _keys!;
    return switch (section) {
      SettingsSection.accounts =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AccountsSection(data: data),
          if (keys.value != null)
            SettingsCard(children: [
              HostKeyRow(keys: keys, which: HostKey.tmdb),
            ]),
        ]),
      SettingsSection.danmaku => RegistryGroups(
          section: section,
          model: model,
          more: _isMore(section),
          onMore: () => _toggleMore(section),
          highlight: _highlight,
          extra: {
            if (keys.value != null)
              '防剧透': [HostKeyRow(keys: keys, which: HostKey.spoilerAi)],
          }),
      SettingsSection.sources => SourcesSection(
          key: _sources,
          data: data,
          folders: shell.services.folders,
          open: _openSource),
      SettingsSection.downloads =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          RegistryGroups(
              section: section,
              model: model,
              more: _isMore(section),
              onMore: () => _toggleMore(section),
              highlight: _highlight),
          if (shell.services.downloaders case final downloaders?)
            DownloadersSection(key: _downloaders, downloaders: downloaders),
        ]),
      SettingsSection.devices => DevicesSection(key: _devices, host: data.host),
      SettingsSection.nipa when shell.services.peers != null =>
        NipaPeerSection(peers: shell.services.peers!),
      SettingsSection.nipa => NipaSection(
          key: _nipa,
          data: data,
          model: model,
          onShow: _show,
          more: _isMore(section),
          onMore: () => _toggleMore(section),
          highlight: _highlight),
      SettingsSection.sync => SyncSection(
          key: _sync,
          sync: shell.services.sync,
          model: model,
          more: _isMore(section),
          onMore: () => _toggleMore(section),
          highlight: _highlight),
      SettingsSection.storage => StorageSection(
          key: _storage,
          upkeep: shell.services.upkeep,
          model: model,
          more: _isMore(section),
          onMore: () => _toggleMore(section),
          highlight: _highlight),
      SettingsSection.shortcuts =>
        ShortcutsSection(model: model, highlight: _highlight),
      SettingsSection.plugins => PluginsSection(
          key: _plugins,
          plugins: shell.services.plugins,
          data: data,
          model: model,
          more: _isMore(section),
          onMore: () => _toggleMore(section),
          highlight: _highlight),
      SettingsSection.about => AboutSection(
          key: _about,
          data: data,
          upkeep: shell.services.upkeep,
          model: model,
          highlight: _highlight),
      SettingsSection.classic => ClassicSection(
          model: model,
          onLeave: shell.onLeave,
          more: _isMore(section),
          onMore: () => _toggleMore(section),
          highlight: _highlight),
      _ => RegistryGroups(
          section: section,
          model: model,
          more: _isMore(section),
          onMore: () => _toggleMore(section),
          highlight: _highlight),
    };
  }

  Widget _results(String query) {
    final q = query.toLowerCase();
    final model = _model!;
    final places = [
      for (final s in SettingsSection.values)
        if (s.title.toLowerCase().contains(q) ||
            (_words[s]?.contains(q) ?? false))
          s
    ];
    final found = <SettingsSection, List<UiSetting>>{};
    for (final s in model.all ?? const <UiSetting>[]) {
      if (!SettingsLayout.shown(s)) continue;
      final words =
          '${SettingWords.title(s)} ${s.title} ${s.key}'.toLowerCase();
      if (!words.contains(q)) continue;
      found.putIfAbsent(SettingsLayout.sectionOf(s.key), () => []).add(s);
    }
    final keys = [
      if (_keys!.value != null)
        for (final k in HostKey.values)
          if (k.words.contains(q) || k.title.toLowerCase().contains(q)) k
    ];
    if (places.isEmpty && found.isEmpty && keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('没有找到', style: NextText.sans(14, color: NextColors.p3)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (places.isNotEmpty)
        SettingsCard(children: [
          for (final s in places)
            SettingsRow(
              title: s.title,
              trailing: const NextIcon(NextGlyph.chevronRight,
                  size: 14, color: NextColors.p3),
              onTap: () => _go(s),
            ),
        ]),
      for (final section in SettingsSection.values)
        if (found.containsKey(section) || keys.any((k) => k.section == section))
          SettingsCard(title: section.title, children: [
            for (final s in found[section] ?? const <UiSetting>[])
              RegistryRow(key: ValueKey(s.key), setting: s, model: model),
            for (final k in keys)
              if (k.section == section) HostKeyRow(keys: _keys!, which: k),
          ]),
    ]);
  }


  /// The section (or the search's results), scrolling, inside [padding].
  Widget _content(SettingsModel model, String query, EdgeInsets padding) =>
      ListenableBuilder(
                listenable: Listenable.merge([model, _keys]),
                builder: (context, _) => SingleChildScrollView(
                  controller: _scroll,
                  padding: padding,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.topLeft,
                            children: [
                              ...previous,
                              if (current != null) current
                            ]),
                        child: Column(
                          key: ValueKey(query.isEmpty ? _section : 'search'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 26),
                              child: Text(
                                  query.isEmpty ? _section.title : '“$query”',
                                  style: NextText.sans(28,
                                      weight: FontWeight.w600)),
                            ),
                            if (model.all == null && model.failed == null)
                              const SizedBox(height: 200)
                            else if (query.isNotEmpty)
                              _results(query)
                            else
                              _body(_section),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );

  /// A phone: back and the search on the bar's row, the sections in a row
  /// that scrolls sideways, the section under them in one column.
  Widget _phone(SettingsModel model, String query) {
    const gutter = NextLayout.compactGutter;
    return ColoredBox(
      color: NextColors.ink,
      child: Padding(
        padding: EdgeInsets.only(top: NextLayout.barTop(context)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Back on the bar's row (its right holds the shell's own).
          SizedBox(
            height: NextMetrics.topBar,
            child: Padding(
              padding: const EdgeInsets.only(left: gutter - 9),
              child: Align(
                alignment: Alignment.centerLeft,
                child: NextIconButton(
                    glyph: NextGlyph.chevronLeft,
                    label: '返回',
                    onTap: () => Navigator.of(context).maybePop()),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(gutter, 6, gutter, 6),
            child: _SearchField(
                search: _search,
                searchFocus: _searchFocus,
                onSearch: () {
                  setState(() {});
                  if (_scroll.hasClients) _scroll.jumpTo(0);
                }),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: gutter),
              children: [
                for (final s in SettingsSection.rail.expand((g) => g))
                  Padding(
                    padding: const EdgeInsets.only(right: 22),
                    child: _RailItem(
                        label: s.title,
                        active: query.isEmpty && s == _section,
                        onTap: () => _go(s),
                        under: true),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _content(
                model,
                query,
                EdgeInsets.fromLTRB(gutter, 18, gutter,
                    64 + MediaQuery.paddingOf(context).bottom)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = _model!;
    final query = _search.text.trim();
    if (NextLayout.compact(context)) return _phone(model, query);
    return ColoredBox(
      color: NextColors.ink,
      child: Stack(children: [
        Positioned.fill(
          top: NextLayout.underBar(context),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: NextMetrics.gutter),
            SizedBox(
              width: 176,
              child: Padding(
                padding: const EdgeInsets.only(top: 34),
                child: _Rail(
                  current: query.isEmpty ? _section : null,
                  search: _search,
                  searchFocus: _searchFocus,
                  onSearch: () {
                    setState(() {});
                    if (_scroll.hasClients) _scroll.jumpTo(0);
                  },
                  onTap: _go,
                ),
              ),
            ),
            const SizedBox(width: 56),
            Expanded(
              child: _content(model, query,
                  const EdgeInsets.only(top: 28, bottom: 96, right: 64)),
            ),
          ]),
        ),
      ]),
    );
  }

  // —— 调试 ——

  @override
  Future<void> debug(Map<String, String> p) async {
    if (p['section'] case final name?) _go(SettingsSection.values.byName(name));
    if (p['key'] case final key?) _show(key);
    if (p['query'] case final q?) {
      _search.text = q;
      setState(() {});
    }
    if (p['more'] case final on?) {
      setState(
          () => on == 'true' ? _more.add(_section) : _more.remove(_section));
    }
    if (p['source'] case final which?) {
      _openSource = which == 'none' ? null : which;
      _sources.currentState?.show(_openSource);
    }
    if (p['adding'] == 'true') _addSource();
    switch (p['folders']) {
      case 'scan':
        _go(SettingsSection.sources);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await _sources.currentState?.debugScan();
      case 'nearby':
        _addSource(type: 'nipaplay');
    }
    if (p['downloader'] == 'add') {
      _go(SettingsSection.downloads);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _downloaders.currentState?.debugAdd(p);
    }
    if (p['plugins'] == 'market') {
      _go(SettingsSection.plugins);
      setState(() => _more.add(SettingsSection.plugins));
    }
    if (p['plugin'] case final id?) {
      _go(SettingsSection.plugins);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      // Not awaited: an action may be asking in a sheet.
      unawaited(_plugins.currentState?.debugInvoke(id, p['invoke']));
    }
    if (p['sync'] case final what?) {
      _go(SettingsSection.sync);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final sync = _sync.currentState;
      switch (what) {
        case 'test':
          await sync?.test();
        case 'run':
          await sync?.run();
      }
    }
    if (p['clear'] case final kind?) {
      _go(SettingsSection.storage);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _storage.currentState?.clear(kind);
    }
    if (p['update'] == 'check') {
      _go(SettingsSection.about);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _about.currentState?.check();
    }
    if (p['memory'] case final path?) {
      _nipa.currentState?.debugOpenMemory(path == 'none' ? null : path);
    }
    if (p['importCodex'] == 'true') {
      await _nipa.currentState?.debugImportCodex();
    }
    if (p['check'] == 'true') await _nipa.currentState?.debugCheck();
    if (p['advanced'] case final on?) {
      _devices.currentState?.debugAdvanced(on == 'true');
    }
    if (p['reload'] == 'true') await _model?.load();
    if (p['scroll'] case final to?) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (_scroll.hasClients) {
        final max = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(
            to == 'end' ? max : double.parse(to).clamp(0, max).toDouble());
      }
    }
  }

  @override
  Map<String, Object?> debugStatus() => {
        'page': _section.name,
        'query': _search.text,
        'highlight': _highlight,
        'settings': _model?.all?.length,
        'byNipa': [for (final s in _model?.byNipa ?? const []) s.key],
        'changed': {
          for (final s in _model?.all ?? const <UiSetting>[])
            if (s.changedBy != null) s.key: s.changedBy
        },
        'scroll': _scroll.hasClients ? _scroll.offset : null,
        'memory': _nipa.currentState?.debugMemory,
      };
}

/// The sections, in quiet groups, with a search above them.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.current,
    required this.search,
    required this.searchFocus,
    required this.onSearch,
    required this.onTap,
  });
  final SettingsSection? current;
  final TextEditingController search;
  final FocusNode searchFocus;
  final VoidCallback onSearch;
  final ValueChanged<SettingsSection> onTap;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SearchField(
            search: search, searchFocus: searchFocus, onSearch: onSearch),
        const SizedBox(height: 22),
        for (final (i, group) in SettingsSection.rail.indexed) ...[
          if (i > 0) const SizedBox(height: 14),
          for (final s in group)
            _RailItem(
                label: s.title, active: s == current, onTap: () => onTap(s)),
        ],
      ]);
}

/// The settings' search, on the rail or a phone's bar.
class _SearchField extends StatelessWidget {
  const _SearchField(
      {required this.search,
      required this.searchFocus,
      required this.onSearch});
  final TextEditingController search;
  final FocusNode searchFocus;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) =>
        ListenableBuilder(
          listenable: searchFocus,
          builder: (context, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: searchFocus.hasFocus
                  ? const Color(0x14FFFFFF)
                  : const Color(0x0AFFFFFF),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                  color: searchFocus.hasFocus
                      ? const Color(0x59FF2E55)
                      : NextColors.line),
            ),
            child: Row(children: [
              const NextIcon(NextGlyph.search, size: 14, color: NextColors.p3),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: search,
                  focusNode: searchFocus,
                  cursorColor: NextColors.accent,
                  cursorWidth: 1.5,
                  style: NextText.sans(13),
                  onChanged: (_) => onSearch(),
                  decoration: InputDecoration.collapsed(
                    hintText: '搜索',
                    hintStyle: NextText.sans(13, color: NextColors.p4),
                  ),
                ),
              ),
            ]),
          ),
        );
}

class _RailItem extends StatelessWidget {
  const _RailItem(
      {required this.label,
      required this.active,
      required this.onTap,
      this.under = false});
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// The dot under the word (a phone's row of sections), not left of it.
  final bool under;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        pressScale: 0.98,
        builder: (context, hovered) => SizedBox(
          height: 34,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: under ? null : -16,
              top: under ? null : 15,
              bottom: under ? 0 : null,
              right: null,
              child: AnimatedOpacity(
                opacity: active ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: NextColors.accent,
                    boxShadow: [
                      BoxShadow(color: NextColors.accent, blurRadius: 10)
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: NextText.sans(14,
                    weight: active ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: 0.2,
                    color:
                        active || hovered ? NextColors.paper : NextColors.p3),
                child: Text(label),
              ),
            ),
          ]),
        ),
      );
}
