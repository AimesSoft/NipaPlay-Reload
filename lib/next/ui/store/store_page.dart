import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/rika_store.dart';
import '../settings/controls.dart';
import '../settings/section_accounts.dart' show ConfirmPill;
import '../shell/shell_controller.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/progress.dart';
import '../widgets/sheet.dart';
import 'store_controller.dart';

Route<void> storeRoute(RouteSettings settings) => PageRouteBuilder<void>(
      settings: settings,
      transitionDuration: NextMotion.page,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, __) => const StorePage(),
      transitionsBuilder: (context, animation, _, child) =>
          nextPageTransition(context, animation, child),
    );

/// 梨花's store, a page of its own: what she can learn, shelf by shelf
/// (BT sources, danmaku, models, tools), as cards with a mark of their
/// kind; what she runs on brings its own (DSH Web, Codex plugins); an npm
/// package can be named at the end. A card opens the item: what it is,
/// where it comes from, what it says before it is installed, its notes.
/// What changes takes effect when she starts again, which the page offers
/// as soon as something changed.
class StorePage extends StatefulWidget {
  const StorePage({super.key, this.store});

  /// The store to show; by default the shell's.
  final NextRikaStore? store;

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  StoreController? _store;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_store != null) return;
    final store = StoreController(
        widget.store ?? NextShellScope.of(context).services.rikaStore)
      ..addListener(_changed);
    _store = store;
    unawaited(store.load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store?.dispose();
    super.dispose();
  }

  bool _matches(UiStoreItem item) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return item.name.toLowerCase().contains(q) ||
        item.description.toLowerCase().contains(q) ||
        item.id.toLowerCase().contains(q);
  }

  Future<void> _install(UiStoreItem item) async {
    final store = _store!;
    if (item.notices.isNotEmpty) {
      final go = await showNextSheet<bool>(
          (context, close) => _Before(
              item: item,
              onCancel: () => close(false),
              onInstall: () => close(true)),
          width: 480);
      if (go != true) return;
    }
    await store.install(item);
  }

  Future<void> _open(UiStoreItem item) async {
    final store = _store!;
    await showNextSheet<void>(
        (context, close) => ListenableBuilder(
              listenable: store,
              builder: (context, _) {
                final current = [
                      ...?store.data?.official,
                      ...?store.data?.fromNpm
                    ].where((i) => i.id == item.id).firstOrNull ??
                    item;
                return _ItemSheet(
                  item: current,
                  readme:
                      current.reviewed ? store.store.readme(current.id) : null,
                  busy: store.busy.contains(current.id),
                  error: store.errors[current.id] ?? current.notLoaded,
                  onInstall: () => _install(current),
                  onRemove: () => store.remove(current.id),
                  onEnabled: (on) => store.setEnabled(current, on),
                  onClose: close,
                );
              },
            ),
        width: 620);
  }

  Future<void> _npm(String spec) async {
    final store = _store!;
    store.busy.add('npm');
    store.errors.remove('npm');
    setState(() {});
    try {
      final facts = await store.resolveNpm(spec);
      if (!mounted) return;
      store.busy.remove('npm');
      setState(() {});
      final version = facts['version'] as String?;
      final integrity = facts['integrity'] as String?;
      final kind = await showNextSheet<String>(
          (context, close) => _NpmFacts(
              facts: facts,
              onCancel: () => close(),
              onInstall: (kind) => close(kind)),
          width: 520);
      if (kind == null || version == null || integrity == null) return;
      await store.installNpm(
          npm: facts['npm'] as String,
          version: version,
          kind: kind,
          integrity: integrity);
    } catch (error) {
      store.errors['npm'] = '$error';
      store.busy.remove('npm');
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store!;
    final data = store.data;
    final compact = NextLayout.compact(context);
    final gutter = NextLayout.gutter(context);
    final shelves = <String, List<UiStoreItem>>{};
    final codexOfficial = <UiStoreItem>[];
    for (final item in data?.official ?? const <UiStoreItem>[]) {
      if (!_matches(item)) continue;
      if (item.kind == 'codexPlugin') {
        codexOfficial.add(item);
      } else {
        shelves.putIfAbsent(item.category, () => []).add(item);
      }
    }
    final installed = [
      for (final item in [...?data?.official, ...?data?.fromNpm])
        if (item.installed && item.kind != 'codexPlugin') item
    ];
    final fromNpm = [
      for (final item in data?.fromNpm ?? const <UiStoreItem>[])
        if (_matches(item)) item
    ];
    return Stack(children: [
      const Positioned.fill(child: _Backdrop()),
      CustomScrollView(slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(gutter,
              NextLayout.underBar(context) + (compact ? 12 : 36), NextLayout.end(context), 0),
          sliver: SliverToBoxAdapter(
            child: _Header(
              count: installed.length,
              query: _query,
              refreshing: store.refreshing,
              onQuery: (q) => setState(() => _query = q),
              onRefresh: () => store.load(refresh: true),
            ),
          ),
        ),
        if (store.pending || store.applyResult != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, 22, NextLayout.end(context), 0),
            sliver: SliverToBoxAdapter(
              child: _RestartBar(
                  pending: store.pending,
                  applying: store.applying,
                  result: store.applyResult,
                  onApply: store.apply),
            ),
          ),
        if (store.failed case final failed?)
          _note(context, '没能读取商店', failed)
        else if (data == null)
          const SliverToBoxAdapter(
              child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: ThinkingDots())))
        else ...[
          if (data.listProblem case final problem?)
            _note(
                context,
                data.official.isEmpty ? '没能取到官方列表' : '官方列表可能不是最新的',
                problem),
          for (final category in storeCategoryNames.keys)
            if (shelves[category] case final items?)
              ..._shelf(context, storeCategoryNames[category]!, [
                for (final item in items) _card(store, item),
              ]),
          if (data.web['version'] != null ||
              codexOfficial.isNotEmpty ||
              store.codex.isNotEmpty)
            ..._shelf(context, '运行器扩展', [
              if (data.web['version'] != null) _webCard(store, data),
              for (final item in codexOfficial) _card(store, item),
              ..._codexCards(store, codexOfficial),
            ], note: '只在对应的运行器下生效'),
          ..._shelf(context, '来自 npm', [
            for (final item in fromNpm) _card(store, item),
            _NpmCard(
              busy: store.busy.contains('npm'),
              error: store.errors['npm'],
              onResolve: _npm,
            ),
          ], note: '没有经过审核，安装前请看清来源'),
        ],
        SliverToBoxAdapter(
            child: SizedBox(height: 80 + NextLayout.foot(context))),
      ]),
    ]);
  }

  Widget _note(BuildContext context, String title, String detail) =>
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
            NextLayout.gutter(context), 28, NextLayout.end(context), 0),
        sliver: SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: NextText.sans(14, color: NextColors.p2)),
            const SizedBox(height: 4),
            Text(detail, style: NextText.sans(12.5, color: NextColors.p3)),
          ]),
        ),
      );

  List<Widget> _shelf(BuildContext context, String title, List<Widget> cards,
          {String? note}) =>
      [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
              NextLayout.gutter(context), 44, NextLayout.end(context), 16),
          sliver: SliverToBoxAdapter(
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(title,
                      style: NextText.sans(19, weight: FontWeight.w600)),
                  if (note != null) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NextText.sans(12.5, color: NextColors.p4)),
                    ),
                  ],
                ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
              NextLayout.gutter(context), 0, NextLayout.end(context), 0),
          sliver: SliverLayoutBuilder(builder: (context, constraints) {
            final width = constraints.crossAxisExtent;
            const gap = 16.0;
            final columns =
                math.max(1, ((width + gap) / (300 + gap)).floor());
            final cardWidth = (width - gap * (columns - 1)) / columns;
            return SliverToBoxAdapter(
              child: Wrap(spacing: gap, runSpacing: gap, children: [
                for (final card in cards)
                  SizedBox(width: cardWidth, height: 176, child: card),
              ]),
            );
          }),
        ),
      ];

  Widget _card(StoreController store, UiStoreItem item) {
    final busy = store.busy.contains(item.id);
    return _StoreCard(
      key: ValueKey('store.${item.id}'),
      mark: _Mark.of(item.kind == 'codexPlugin' ? 'codex' : item.category,
          item.name),
      title: item.name,
      description: item.description,
      meta: [
        item.installedVersion ?? item.version,
        if (item.author != null) item.author!,
      ].join(' · '),
      unreviewed: !item.reviewed,
      warning: store.errors[item.id] ?? item.notLoaded,
      onOpen: () => _open(item),
      action: !item.installed
          ? _GetButton(busy: busy, onTap: () => _install(item))
          : _Installed(
              enabled: item.kind == 'codexPlugin' ? null : item.enabled ?? true,
              updatable: item.versionDiffers,
              busy: busy,
              label: item.name,
              onEnabled: (on) => store.setEnabled(item, on),
              onUpdate: () => _install(item)),
    );
  }

  Widget _webCard(StoreController store, UiStore data) {
    final web = data.web;
    final installed = web['installed'] == true;
    final ready = web['ready'] == true;
    const id = 'dsh-web';
    return _StoreCard(
      key: const ValueKey('store.dsh-web'),
      mark: _Mark.of('web', 'DSH Web'),
      title: 'DSH Web',
      description: ready
          ? 'DeepSeek Harness 的网页界面，在浏览器里管理它的插件。'
          : installed
              ? '已安装，重启梨花后可以打开。'
              : 'DeepSeek Harness 的网页界面，在浏览器里管理它的插件。',
      meta: '${web['version']}',
      warning: store.errors[id],
      action: installed
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              if (ready) ...[
                PillButton(label: '打开', primary: true, onTap: store.store.openWeb),
                const SizedBox(width: 6),
              ],
              ConfirmPill(
                  label: '卸载',
                  confirm: '确认卸载',
                  onConfirm: () => store.remove(id)),
            ])
          : web['installable'] == true
              ? _GetButton(
                  busy: store.busy.contains(id),
                  onTap: () => store.installWeb(web['version'] as String))
              : null,
    );
  }

  List<Widget> _codexCards(
      StoreController store, List<UiStoreItem> official) {
    final writable = store.codex['writable'] == true;
    final officialIds = {
      for (final item in official) '${item.id}@nipaplay-${item.id}',
    };
    return [
      for (final market
          in (store.codex['marketplaces'] as List? ?? const []).whereType<Map>())
        for (final plugin
            in (market['plugins'] as List? ?? const []).whereType<Map>())
          if (!officialIds.contains(plugin['id']) &&
              (writable || plugin['installed'] == true))
            _StoreCard(
              key: ValueKey('store.codex.${plugin['id']}'),
              mark: _Mark.of('codex',
                  (plugin['interface'] as Map?)?['displayName'] as String? ??
                      plugin['name'] as String),
              title: (plugin['interface'] as Map?)?['displayName'] as String? ??
                  plugin['name'] as String,
              description: (plugin['interface'] as Map?)?['shortDescription']
                      as String? ??
                  '来自 ${market['name']}',
              meta: '${market['name']}',
              unreviewed: true,
              warning: store.errors[plugin['id']],
              action: !writable
                  ? null
                  : plugin['installed'] == true
                      ? ConfirmPill(
                          label: '卸载',
                          confirm: '确认卸载',
                          onConfirm: () =>
                              store.removeCodex(plugin['id'] as String))
                      : _GetButton(
                          busy: store.busy.contains(plugin['id']),
                          onTap: () => store.installCodex(
                              plugin['id'] as String,
                              market['name'] as String,
                              plugin['name'] as String)),
            ),
      if (writable)
        _MarketCard(
            busy: store.busy.contains('codex-market'),
            error: store.errors['codex-market'],
            onAdd: store.addMarketplace),
    ];
  }
}

/// The page's ground: the app's ink with a low warm light from the top
/// left, so the cards sit on something.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.85, -1.1),
            radius: 1.25,
            colors: [Color(0x1FFF2E55), Color(0x00000000)],
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.count,
      required this.query,
      required this.refreshing,
      required this.onQuery,
      required this.onRefresh});
  final int count;
  final String query;
  final bool refreshing;
  final ValueChanged<String> onQuery;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final compact = NextLayout.compact(context);
    final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('商店',
              style: NextText.serif(compact ? 32 : 44, letterSpacing: 2)),
          const SizedBox(height: 8),
          Text(
              count == 0
                  ? '梨花能学会的技能，和给她接入别处模型的插件'
                  : '梨花能学会的技能，和给她接入别处模型的插件 · 已装 $count 个',
              style: NextText.sans(13.5, color: NextColors.p3)),
        ]);
    final tools = Row(mainAxisSize: MainAxisSize.min, children: [
      _SearchField(value: query, onChanged: onQuery),
      const SizedBox(width: 8),
      refreshing
          ? const SizedBox(width: 32, child: ThinkingDots())
          : PillButton(label: '刷新', onTap: onRefresh),
    ]);
    if (compact) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        title,
        const SizedBox(height: 16),
        tools,
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: title),
      tools,
    ]);
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final _text = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        width: NextLayout.compact(context) ? 200 : 240,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: NextColors.line),
        ),
        child: Row(children: [
          const NextIcon(NextGlyph.search, size: 13, color: NextColors.p3),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _text,
              onChanged: widget.onChanged,
              cursorColor: NextColors.accent,
              cursorWidth: 1.5,
              cursorOpacityAnimates: false,
              style: NextText.sans(13),
              decoration: InputDecoration.collapsed(
                  hintText: '找技能或插件',
                  hintStyle: NextText.sans(13, color: NextColors.p4)),
            ),
          ),
        ]),
      );
}

/// After something changed: one line, and the restart that applies it.
class _RestartBar extends StatelessWidget {
  const _RestartBar(
      {required this.pending,
      required this.applying,
      required this.result,
      required this.onApply});
  final bool pending;
  final bool applying;
  final String? result;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0x14FF2E55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x33FF2E55)),
        ),
        child: Row(children: [
          if (pending) ...[
            const StateDot(NextColors.accent),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
                pending
                    ? result ?? '有改动，梨花重新启动后生效'
                    : result ?? '',
                style: NextText.sans(13.5, color: NextColors.paper)),
          ),
          if (pending)
            PillButton(
                label: '重启梨花',
                primary: true,
                busy: applying,
                onTap: applying ? null : onApply),
        ]),
      );
}

/// What kind of thing an item is, as a mark: a tinted tile with the
/// glyph of its shelf and, under it, the first letter of its name.
final class _Mark {
  const _Mark(this.color, this.glyph, this.letter);
  final Color color;
  final NextGlyph glyph;
  final String letter;

  static _Mark of(String kind, String name) {
    final letter = name.isEmpty ? '·' : name.characters.first;
    return switch (kind) {
      'bt' => _Mark(NextColors.amber, NextGlyph.torrent, letter),
      'danmaku' => _Mark(NextColors.accent2, NextGlyph.danmaku, letter),
      'model' => _Mark(NextColors.mint, NextGlyph.device, letter),
      'web' => _Mark(const Color(0xFF8AB4FF), NextGlyph.grid, letter),
      'codex' => _Mark(const Color(0xFFB9A4FF), NextGlyph.grid, letter),
      _ => _Mark(NextColors.paper, NextGlyph.settings, letter),
    };
  }
}

class _MarkTile extends StatelessWidget {
  const _MarkTile(this.mark, {this.size = 46});
  final _Mark mark;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              mark.color.withValues(alpha: 0.30),
              mark.color.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(color: mark.color.withValues(alpha: 0.28)),
        ),
        child: Stack(children: [
          Positioned(
            right: size * 0.12,
            bottom: size * 0.1,
            child: NextIcon(mark.glyph,
                size: size * 0.26, color: mark.color.withValues(alpha: 0.9)),
          ),
          Positioned(
            left: size * 0.16,
            top: size * 0.08,
            child: Text(mark.letter,
                style: NextText.serif(size * 0.46,
                    letterSpacing: 0).copyWith(color: NextColors.paper)),
          ),
        ]),
      );
}

class _StoreCard extends StatelessWidget {
  const _StoreCard(
      {super.key,
      required this.mark,
      required this.title,
      required this.description,
      required this.meta,
      this.unreviewed = false,
      this.warning,
      this.action,
      this.onOpen});
  final _Mark mark;
  final String title;
  final String description;
  final String meta;
  final bool unreviewed;
  final String? warning;
  final Widget? action;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onOpen,
        semanticLabel: title,
        pressScale: 0.99,
        focusRadius: BorderRadius.circular(18),
        cursor: onOpen == null ? MouseCursor.defer : SystemMouseCursors.click,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: NextMotion.ease,
          transform: Matrix4.translationValues(0, hovered && onOpen != null ? -2 : 0, 0),
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 14),
          decoration: BoxDecoration(
            color: hovered ? const Color(0xFF1A1A21) : const Color(0xFF141419),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: hovered ? NextColors.line2 : NextColors.line),
            boxShadow: hovered
                ? const [
                    BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 30,
                        offset: Offset(0, 14))
                  ]
                : null,
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _MarkTile(mark),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: NextText.sans(15.5,
                                  weight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Row(children: [
                            Flexible(
                              child: Text(meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: NextText.sans(11.5,
                                      color: NextColors.p4)),
                            ),
                            if (unreviewed) ...[
                              const SizedBox(width: 8),
                              const _Tag('未审核'),
                            ],
                          ]),
                        ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Expanded(
                  child: Text(warning ?? description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NextText.sans(13,
                          color: warning != null
                              ? NextColors.accent2
                              : NextColors.p3,
                          height: 1.5)),
                ),
                if (action != null)
                  Align(alignment: Alignment.centerRight, child: action!),
              ]),
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0x1FFFBF5C),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: NextText.sans(10.5, color: NextColors.amber)),
      );
}

/// 获取: the App Store's word, on a soft pill until it is pressed.
class _GetButton extends StatelessWidget {
  const _GetButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: busy ? null : onTap,
        semanticLabel: '安装',
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 30,
          width: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? NextColors.accent : const Color(0x29FF2E55),
            borderRadius: BorderRadius.circular(15),
          ),
          child: busy
              ? const ThinkingDots()
              : Text('安装',
                  style: NextText.sans(13,
                      weight: FontWeight.w600,
                      color: hovered ? NextColors.paper : NextColors.accent2)),
        ),
      );
}

class _Installed extends StatelessWidget {
  const _Installed(
      {required this.enabled,
      required this.updatable,
      required this.busy,
      required this.label,
      required this.onEnabled,
      required this.onUpdate});
  final bool? enabled;
  final bool updatable;
  final bool busy;
  final String label;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (updatable) ...[
          PillButton(label: '换用列表版本', busy: busy, onTap: busy ? null : onUpdate),
          const SizedBox(width: 8),
        ] else ...[
          const NextIcon(NextGlyph.check, size: 12, color: NextColors.mint),
          const SizedBox(width: 5),
          Text('已安装', style: NextText.sans(12, color: NextColors.p3)),
          const SizedBox(width: 12),
        ],
        if (enabled != null)
          NextToggle(
              value: enabled!,
              label: '启用$label',
              onChanged: busy ? null : onEnabled),
      ]);
}

/// An npm package named by the person: the field, and what was found is
/// shown before anything is installed.
class _NpmCard extends StatefulWidget {
  const _NpmCard(
      {required this.busy, required this.error, required this.onResolve});
  final bool busy;
  final String? error;
  final ValueChanged<String> onResolve;

  @override
  State<_NpmCard> createState() => _NpmCardState();
}

class _NpmCardState extends State<_NpmCard> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _go() {
    final spec = _text.text.trim();
    if (spec.isEmpty || widget.busy) return;
    widget.onResolve(spec);
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NextColors.line2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _MarkTile(_Mark.of('npm', 'n')),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('按名字安装',
                        style: NextText.sans(15.5, weight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('npm 上的 DSH 插件，或带 SKILL.md 的技能包',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NextText.sans(11.5, color: NextColors.p4)),
                  ]),
            ),
          ]),
          const Spacer(),
          if (widget.error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(error,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(12, color: NextColors.accent2)),
            ),
          Row(children: [
            Expanded(
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: const Color(0x0DFFFFFF),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: TextField(
                  controller: _text,
                  onSubmitted: (_) => _go(),
                  cursorColor: NextColors.accent,
                  cursorWidth: 1.5,
                  cursorOpacityAnimates: false,
                  style: NextText.mono(12.5),
                  decoration: InputDecoration.collapsed(
                      hintText: '@scope/name@1.2.3',
                      hintStyle: NextText.mono(12.5, color: NextColors.p4)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PillButton(
                label: '查看',
                busy: widget.busy,
                onTap: widget.busy ? null : _go),
          ]),
        ]),
      );
}

class _MarketCard extends StatefulWidget {
  const _MarketCard(
      {required this.busy, required this.error, required this.onAdd});
  final bool busy;
  final String? error;
  final ValueChanged<String> onAdd;

  @override
  State<_MarketCard> createState() => _MarketCardState();
}

class _MarketCardState extends State<_MarketCard> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NextColors.line2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _MarkTile(_Mark.of('codex', '+')),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('添加 Codex 插件市场',
                        style: NextText.sans(15.5, weight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('第三方市场没有经过审核',
                        style: NextText.sans(11.5, color: NextColors.p4)),
                  ]),
            ),
          ]),
          const Spacer(),
          if (widget.error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(error,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(12, color: NextColors.accent2)),
            ),
          Row(children: [
            Expanded(
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: const Color(0x0DFFFFFF),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: TextField(
                  controller: _text,
                  cursorColor: NextColors.accent,
                  cursorWidth: 1.5,
                  cursorOpacityAnimates: false,
                  style: NextText.mono(12.5),
                  decoration: InputDecoration.collapsed(
                      hintText: '市场地址或本地路径',
                      hintStyle: NextText.sans(12.5, color: NextColors.p4)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PillButton(
                label: '添加',
                busy: widget.busy,
                onTap: widget.busy
                    ? null
                    : () {
                        final source = _text.text.trim();
                        if (source.isNotEmpty) widget.onAdd(source);
                      }),
          ]),
        ]),
      );
}

/// An item opened: its mark large, what it is and where it comes from as
/// a row of facts, what it says before it is installed, and its notes.
class _ItemSheet extends StatelessWidget {
  const _ItemSheet(
      {required this.item,
      required this.readme,
      required this.busy,
      required this.error,
      required this.onInstall,
      required this.onRemove,
      required this.onEnabled,
      required this.onClose});
  final UiStoreItem item;
  final Future<({String version, String? text})>? readme;
  final bool busy;
  final String? error;
  final VoidCallback onInstall;
  final VoidCallback onRemove;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final mark =
        _Mark.of(item.kind == 'codexPlugin' ? 'codex' : item.category, item.name);
    return SheetSurface(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The mark's colour runs into the sheet's head, as an app's
            // icon colours its page in the App Store.
            Container(
              padding: const EdgeInsets.fromLTRB(26, 26, 18, 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomCenter,
                  colors: [
                    mark.color.withValues(alpha: 0.16),
                    const Color(0x00000000),
                  ],
                ),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _MarkTile(mark, size: 72),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            style: NextText.sans(22, weight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                            item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: NextText.sans(13.5,
                                color: NextColors.p2, height: 1.45)),
                        const SizedBox(height: 14),
                        Row(children: [
                          if (!item.installed)
                            _GetButton(busy: busy, onTap: onInstall)
                          else ...[
                            if (item.versionDiffers)
                              PillButton(
                                  label: '换用列表版本 ${item.version}',
                                  busy: busy,
                                  onTap: busy ? null : onInstall),
                            if (item.kind != 'codexPlugin') ...[
                              const SizedBox(width: 8),
                              NextToggle(
                                  value: item.enabled ?? true,
                                  label: '启用${item.name}',
                                  onChanged: busy ? null : onEnabled),
                              const SizedBox(width: 6),
                              Text(item.enabled ?? true ? '已启用' : '已停用',
                                  style: NextText.sans(12.5,
                                      color: NextColors.p3)),
                            ],
                            const SizedBox(width: 12),
                            ConfirmPill(
                                label: '卸载',
                                confirm: '确认卸载',
                                onConfirm: onRemove),
                          ],
                        ]),
                      ]),
                ),
                NextIconButton(
                    key: const Key('store.details.close'),
                    glyph: NextGlyph.close,
                    label: '关闭',
                    onTap: onClose),
              ]),
            ),
            Container(height: 1, color: NextColors.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
              child: Row(children: [
                _Fact('类型', item.plugin ? '插件' : item.kind == 'codexPlugin' ? 'Codex 插件' : '技能'),
                _Fact('版本', item.installedVersion ?? item.version),
                _Fact('来源', item.reviewed ? '官方列表' : 'npm'),
                _Fact('审核', item.reviewed ? '已审核' : '未审核',
                    warn: !item.reviewed),
                if (item.author != null) _Fact('作者', item.author!),
              ]),
            ),
            Container(height: 1, color: NextColors.line),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 18, 26, 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (error case final error?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(error,
                              style: NextText.sans(13,
                                  color: NextColors.accent2, height: 1.5)),
                        ),
                      if (item.notices.isNotEmpty) ...[
                        _Notices(item.notices),
                        const SizedBox(height: 18),
                      ],
                      if (readme case final readme?)
                        FutureBuilder<({String version, String? text})>(
                          future: readme,
                          builder: (context, snapshot) => switch (snapshot.data) {
                            final data? => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (data.version != item.version)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Text('这份说明对应 ${data.version}。',
                                          style: NextText.sans(12.5,
                                              color: NextColors.p3)),
                                    ),
                                  _Readme(data.text ?? '没有说明'),
                                ]),
                            _ when snapshot.hasError => Text('说明没能取到',
                                style: NextText.sans(13, color: NextColors.p3)),
                            _ => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: ThinkingDots()),
                          },
                        ),
                    ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An item's notes as written: headings, lists and code set like the
/// conversation's replies, links opened in the browser.
class _Readme extends StatelessWidget {
  const _Readme(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final base = NextText.sans(13.5, color: NextColors.p2, height: 1.7);
    return MarkdownBody(
      data: text,
      softLineBreak: true,
      onTapLink: (_, href, __) {
        final uri = Uri.tryParse(href ?? '');
        if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
        unawaited(launchUrl(uri, mode: LaunchMode.externalApplication)
            .catchError((Object _) => false));
      },
      styleSheet: MarkdownStyleSheet(
        p: base,
        strong: const TextStyle(fontWeight: FontWeight.w600, color: NextColors.paper),
        a: const TextStyle(color: NextColors.accent2),
        code: NextText.mono(12, color: NextColors.paper)
            .copyWith(backgroundColor: const Color(0x14FFFFFF)),
        h1: NextText.sans(18, weight: FontWeight.w600),
        h2: NextText.sans(15, weight: FontWeight.w600),
        h3: NextText.sans(14, weight: FontWeight.w600),
        listBullet: base,
        blockquote: base.copyWith(color: NextColors.p3),
        blockquoteDecoration: const BoxDecoration(
            border: Border(left: BorderSide(color: NextColors.line2, width: 2))),
        blockquotePadding: const EdgeInsets.only(left: 12),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NextColors.line),
        ),
        h1Padding: const EdgeInsets.only(top: 4),
        h2Padding: const EdgeInsets.only(top: 10),
        pPadding: EdgeInsets.zero,
        blockSpacing: 10,
        listIndent: 18,
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.warn = false});
  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(label,
              style: NextText.sans(11, color: NextColors.p4, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NextText.sans(13.5,
                  weight: FontWeight.w600,
                  color: warn ? NextColors.amber : NextColors.paper)),
        ]),
      );
}

class _Notices extends StatelessWidget {
  const _Notices(this.notices);
  final List<String> notices;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: const Color(0x14FFBF5C),
          borderRadius: BorderRadius.circular(12),
          border: const Border(
              left: BorderSide(color: NextColors.amber, width: 2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('安装前须知',
              style: NextText.sans(12.5,
                  weight: FontWeight.w600, color: NextColors.amber)),
          for (final notice in notices)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(notice,
                  style: NextText.sans(13, color: NextColors.p2, height: 1.55)),
            ),
        ]),
      );
}

/// Before installing an item that says something of itself.
class _Before extends StatelessWidget {
  const _Before(
      {required this.item, required this.onCancel, required this.onInstall});
  final UiStoreItem item;
  final VoidCallback onCancel;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) => SheetSurface(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _MarkTile(
                    _Mark.of(item.kind == 'codexPlugin' ? 'codex' : item.category,
                        item.name),
                    size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('安装「${item.name}」',
                      style: NextText.sans(17, weight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 16),
              _Notices(item.notices),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                PillButton(label: '取消', onTap: onCancel),
                const SizedBox(width: 8),
                PillButton(
                    key: const Key('store.notice.accept'),
                    label: '安装',
                    primary: true,
                    onTap: onInstall),
              ]),
            ]),
      );
}

/// What was found for an npm name, before anything is installed.
class _NpmFacts extends StatelessWidget {
  const _NpmFacts(
      {required this.facts, required this.onCancel, required this.onInstall});
  final Map<String, Object?> facts;
  final VoidCallback onCancel;
  final ValueChanged<String> onInstall;

  @override
  Widget build(BuildContext context) {
    final version = facts['version'] as String?;
    final integrity = facts['integrity'] as String?;
    final kinds = facts['kinds'] as Map? ?? const {};
    const labels = {'skill': '技能', 'plugin': 'DSH 插件'};
    final notes = [
      for (final notice in facts['notices'] as List? ?? const []) '$notice',
      if (facts['reason'] case final String reason) reason,
      for (final entry in labels.entries)
        if (kinds[entry.key] case {'reason': final String reason})
          '不能装成${entry.value}：$reason',
    ];
    return SheetSurface(
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              _MarkTile(_Mark.of('npm', 'n'), size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${facts['npm']}',
                          style: NextText.mono(15).copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('npm · 没有经过审核',
                          style: NextText.sans(12, color: NextColors.amber)),
                    ]),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              _Fact('版本', version ?? '未知'),
              _Fact('SKILL.md',
                  facts['hasSkill'] == true ? '有' : '没有'),
              _Fact('DSH 插件声明',
                  facts['declaresDshPlugin'] == true ? '有' : '没有'),
            ]),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Notices(notes),
            ],
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              PillButton(label: '取消', onTap: onCancel),
              for (final entry in labels.entries)
                if (kinds[entry.key] case {'installable': true}
                    when version != null && integrity != null) ...[
                  const SizedBox(width: 8),
                  PillButton(
                      label: '安装为${entry.value}',
                      primary: true,
                      onTap: () => onInstall(entry.key)),
                ],
            ]),
          ]),
    );
  }
}

