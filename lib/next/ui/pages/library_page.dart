import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/library.dart';
import '../library/category_editor.dart';
import '../library/category_grid.dart';
import '../library/category_page.dart';
import '../library/fan_cover.dart';
import '../library/library_controls.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import '../widgets/segmented.dart';

/// 片库: one source at a time, chosen from its title (本地 — this device
/// with the mesh — then each SMB, WebDAV, Jellyfin and Emby). Its
/// categories show as shelves of previews or as cards with a fan of
/// posters; a source with a single category shows that category's grid
/// directly. Its own structure or Nipa's arrangement, when Nipa made one.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

/// Handles for `ext.nipaplay.nextui` in lab profiles.
abstract interface class LibraryDebug {
  /// Applies `source=`, `form=`, `arranged=`, `menu=`, `open=`, `sort=`,
  /// `move=<categoryId>,<index>` and `remove=<categoryId>`.
  Future<void> debug(Map<String, String> p);
  Map<String, Object?> debugStatus();
}

enum _Menu { none, sources, sort, edit }

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin
    implements LibraryDebug {
  NextShellController? _shell;
  StreamSubscription<void>? _changes;
  List<UiLibrarySource> _sources = const [];
  String? _sourceId;
  UiLibraryPage? _page;

  /// The items of a page that has a single category.
  CategoryItems? _single;
  _Menu _menu = _Menu.none;
  int _reads = 0;
  final _scroll = ScrollController();
  final _sourceLink = LayerLink();
  final _sortLink = LayerLink();
  final _editLink = LayerLink();

  /// The page's contents fade in when the form or arrangement changes.
  late final _fade = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360), value: 1);

  NextLibraryData get _data => _shell!.services.library;
  NextLibraryActions get _actions => _shell!.services.libraryActions;

  UiLibrarySource? get _source =>
      _sources.where((s) => s.sourceId == _sourceId).firstOrNull;

  /// This device's works carry the mesh's devices under their titles.
  bool get _deviceLine => _source?.kind == UiSourceKind.local;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell = shell;
    _changes?.cancel();
    _changes = _data.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    _single?.dispose();
    _fade.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final read = ++_reads;
    final sources = await _data.sources();
    final id = sources.any((s) => s.sourceId == _sourceId)
        ? _sourceId!
        : sources.first.sourceId;
    final page = await _data.page(id);
    if (!mounted || read != _reads) return;
    final before = _page;
    final changedShape = before != null &&
        id == _sourceId &&
        (before.form != page.form || before.arranged != page.arranged);
    setState(() {
      _sources = sources;
      _sourceId = id;
      _page = page;
      _syncSingle();
    });
    if (changedShape) _fade.forward(from: 0);
  }

  void _syncSingle() {
    final categories = _page!.categories;
    final only = categories.length == 1 ? categories.single : null;
    if (only != null && _single?.categoryId == only.categoryId) {
      _single!.refresh();
      return;
    }
    _single?.dispose();
    _single = only == null
        ? null
        : CategoryItems(_data, only.categoryId, total: only.count);
  }

  void _choose(String sourceId) {
    setState(() {
      _menu = _Menu.none;
      if (sourceId == _sourceId) return;
      _sourceId = sourceId;
      _page = null;
      _single?.dispose();
      _single = null;
    });
    _load();
  }

  void _toggle(_Menu menu) =>
      setState(() => _menu = _menu == menu ? _Menu.none : menu);

  void _open(CategoryRef ref) {
    final shell = _shell!;
    setState(() => _menu = _Menu.none);
    Navigator.of(context)
        .push(categoryRoute(ref, deviceLine: _deviceLine))
        .then((_) => shell.scrolled.value =
            _scroll.hasClients && _scroll.offset > 24);
  }

  void _openCategory(UiCategory c) => _open(CategoryRef(
      categoryId: c.categoryId,
      title: c.title,
      count: c.count,
      sorts: c.sorts));

  LibraryCallbacks get _on => LibraryCallbacks(
        openWork: _shell!.openWork,
        play: (work) => _shell!.play(work),
        openFolder: (f) => _open(CategoryRef(
            categoryId: f.categoryId, title: f.title, count: f.count)),
      );

  /// Nipa arranges what the viewer cannot do in a few drags. The viewer
  /// finishes the sentence: how they want it arranged is theirs to say.
  void _askNipa() {
    final shell = _shell!;
    setState(() => _menu = _Menu.none);
    final text = '帮我整理片库里的「${_source!.name}」：';
    shell.askText.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    shell.openChat();
  }

  // —— Debug ——

  @override
  Future<void> debug(Map<String, String> p) async {
    if (p['source'] case final id?) _choose(id);
    if (p['form'] case final form?) {
      await _actions.setForm(_sourceId!, UiLibraryForm.values.byName(form));
    }
    if (p['arranged'] case final on?) {
      await _actions.useOriginal(_sourceId!, on != 'true');
    }
    if (p['menu'] case final menu?) {
      setState(() => _menu = _Menu.values.byName(menu));
    }
    if (p['sort'] case final id?) setState(() => _single!.reorder(id));
    if (p['move'] case final move?) {
      final [id, index] = move.split(',');
      await _actions.moveCategory(id, int.parse(index));
    }
    if (p['remove'] case final id?) await _actions.removeCategory(id);
    if (p['open'] case final id?) {
      _openCategory(_page!.categories.firstWhere((c) => c.categoryId == id));
    }
  }

  @override
  Map<String, Object?> debugStatus() => {
        'source': _source?.name,
        'sources': [for (final s in _sources) s.name],
        'form': _page?.form.name,
        'arranged': _page?.arranged,
        'hasArrangement': _page?.hasArrangement,
        'categories': [
          for (final c in _page?.categories ?? const <UiCategory>[])
            '${c.categoryId} ${c.title} ${c.count} '
                'posters:${c.posters.length} preview:${c.preview.length}'
        ],
        'single': _single == null
            ? null
            : {'count': _single!.count, 'loadedSlices': _single!.loaded},
        'menu': _menu.name,
      };

  // —— Building ——

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Stack(children: [
      CustomScrollView(
        key: PageStorageKey('library/$_sourceId'),
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                NextMetrics.gutter, NextMetrics.topBar + 40, 56, 28),
            sliver: SliverToBoxAdapter(child: _header()),
          ),
          if (page != null)
            for (final sliver in _body(page))
              SliverFadeTransition(
                opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
                sliver: sliver,
              ),
        ],
      ),
      ..._menus(),
    ]);
  }

  Widget _header() {
    final page = _page;
    final only = page != null && page.categories.length == 1
        ? page.categories.single
        : null;
    return SizedBox(
      height: 40,
      child: Row(children: [
        CompositedTransformTarget(
          link: _sourceLink,
          child: SourceTitle(
            name: _source?.name ?? '片库',
            open: _menu == _Menu.sources,
            onTap: () => _toggle(_Menu.sources),
          ),
        ),
        if (only?.count case final count?) ...[
          const SizedBox(width: 14),
          Text('$count', style: NextText.num(18, color: NextColors.p3)),
        ],
        const Spacer(),
        if (page != null && page.hasArrangement) ...[
          Segmented<bool>(
            value: page.arranged,
            options: [
              for (final (arranged, text) in const [(false, '原始'), (true, '整理过')])
                (
                  arranged,
                  text,
                  (c) => Text(text, style: NextText.sans(12.5, color: c))
                ),
            ],
            onChanged: (arranged) =>
                _actions.useOriginal(_sourceId!, !arranged),
          ),
          const SizedBox(width: 12),
        ],
        if (page != null && only == null) ...[
          Segmented<UiLibraryForm>(
            value: page.form,
            options: [
              (
                UiLibraryForm.shelves,
                '书架',
                (c) => NextIcon(NextGlyph.rows, size: 15, color: c)
              ),
              (
                UiLibraryForm.cards,
                '卡片',
                (c) => NextIcon(NextGlyph.grid, size: 15, color: c)
              ),
            ],
            onChanged: (form) => _actions.setForm(_sourceId!, form),
          ),
          const SizedBox(width: 12),
        ],
        if (only != null && only.sorts.length > 1) ...[
          CompositedTransformTarget(
            link: _sortLink,
            child: MenuPill(
              label: _sortOf(only).label,
              onTap: () => _toggle(_Menu.sort),
            ),
          ),
          const SizedBox(width: 12),
        ],
        if (page != null)
          CompositedTransformTarget(
            link: _editLink,
            child: RoundGhostButton(
              size: 32,
              label: '调整',
              onTap: () => _toggle(_Menu.edit),
              child: Text('⋯',
                  style: NextText.sans(13,
                      weight: FontWeight.w600, color: NextColors.paper)),
            ),
          ),
      ]),
    );
  }

  UiSort _sortOf(UiCategory c) {
    final id = _single?.sort ?? c.sorts.first.id;
    return c.sorts.firstWhere((s) => s.id == id);
  }

  List<Widget> _body(UiLibraryPage page) {
    if (page.categories.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.only(left: NextMetrics.gutter),
          sliver: SliverToBoxAdapter(
            child: Text('这里还空着。',
                style: NextText.sans(14.5, color: NextColors.p3)),
          ),
        ),
      ];
    }
    if (_single case final items?) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(NextMetrics.gutter, 0, 56, 64),
          sliver: CategoryGrid(items: items, on: _on, deviceLine: _deviceLine),
        ),
      ];
    }
    return switch (page.form) {
      UiLibraryForm.shelves => [
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 64),
            sliver: SliverList.separated(
              itemCount: page.categories.length,
              separatorBuilder: (_, __) => const SizedBox(height: 40),
              itemBuilder: (context, i) {
                final c = page.categories[i];
                return _CategoryShelf(
                  key: ValueKey(c.categoryId),
                  category: c,
                  on: _on,
                  deviceLine: _deviceLine,
                  onOpen: () => _openCategory(c),
                );
              },
            ),
          ),
        ],
      UiLibraryForm.cards => [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(NextMetrics.gutter, 0, 56, 64),
            sliver: SliverLayoutBuilder(builder: (context, constraints) {
              const gap = 24.0;
              final width = constraints.crossAxisExtent;
              final columns = ((width + gap) / (420 + gap)).ceil();
              final tile = (width - gap * (columns - 1)) / columns;
              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  mainAxisExtent: tile * 0.62,
                ),
                itemCount: page.categories.length,
                itemBuilder: (context, i) {
                  final c = page.categories[i];
                  return CategoryCard(
                    key: ValueKey(c.categoryId),
                    title: c.title,
                    count: c.count,
                    posters: c.posters,
                    backdrop: c.backdrop,
                    tint: c.tint,
                    onOpen: () => _openCategory(c),
                  );
                },
              );
            }),
          ),
        ],
    };
  }

  List<Widget> _menus() {
    void close() => setState(() => _menu = _Menu.none);
    final page = _page;
    return switch (_menu) {
      _Menu.none => const [],
      _Menu.sources => anchoredMenu(
          link: _sourceLink,
          close: close,
          menu: MenuPanel(width: 260, children: [
            for (final s in _sources)
              Opacity(
                opacity: s.online ? 1 : 0.5,
                child: MenuItem(
                  label: s.name,
                  selected: s.sourceId == _sourceId,
                  onTap: () => _choose(s.sourceId),
                  trailing: _kind(s),
                ),
              ),
          ]),
        ),
      _Menu.sort => anchoredMenu(
          link: _sortLink,
          close: close,
          right: true,
          menu: MenuPanel(width: 160, children: [
            for (final s in page!.categories.single.sorts)
              MenuItem(
                label: s.label,
                selected: s.id == _sortOf(page.categories.single).id,
                onTap: () => setState(() {
                  _menu = _Menu.none;
                  _single!.reorder(s.id);
                }),
              ),
          ]),
        ),
      _Menu.edit => anchoredMenu(
          link: _editLink,
          close: close,
          right: true,
          menu: CategoryEditor(
            categories: page!.categories,
            onMove: _actions.moveCategory,
            onRemove: _actions.removeCategory,
            onAskNipa: _askNipa,
            original: !page.arranged,
            hidden: page.hiddenCategories,
            onRestore: _actions.restoreCategory,
          ),
        ),
    };
  }

  /// What kind of source it is, when its name does not say.
  Widget? _kind(UiLibrarySource s) {
    final kind = switch (s.kind) {
      UiSourceKind.smb => 'SMB',
      UiSourceKind.webdav => 'WebDAV',
      UiSourceKind.jellyfin => 'Jellyfin',
      UiSourceKind.emby => 'Emby',
      UiSourceKind.local || UiSourceKind.other => null,
    };
    if (kind == null || s.name.toLowerCase().contains(kind.toLowerCase())) {
      return null;
    }
    return Text(kind, style: NextText.sans(12, color: NextColors.p3));
  }
}

/// A category in the shelves form: its name and count (opening it), then
/// a row of its first items.
class _CategoryShelf extends StatelessWidget {
  const _CategoryShelf({
    super.key,
    required this.category,
    required this.on,
    required this.deviceLine,
    required this.onOpen,
  });

  final UiCategory category;
  final LibraryCallbacks on;
  final bool deviceLine;
  final VoidCallback onOpen;

  static const _tile = 150.0;

  @override
  Widget build(BuildContext context) {
    final preview = category.preview;
    final line = deviceLine &&
        preview.any((i) => i is UiWorkItem && i.work.devices.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: NextMetrics.gutter),
          child: Pressable(
            onTap: onOpen,
            semanticLabel: category.title,
            pressScale: 0.98,
            builder: (context, hovered) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: CategoryName(
                      title: category.title, count: category.count, size: 19),
                ),
                const SizedBox(width: 8),
                AnimatedSlide(
                  offset: Offset(hovered ? 0.25 : 0, 0),
                  duration: const Duration(milliseconds: 200),
                  child: NextIcon(NextGlyph.chevronRight,
                      size: 15,
                      color: hovered ? NextColors.paper : NextColors.p3),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: _tile * 3 / 2 + 12 + 22 + (line ? 21 : 0),
          child: ListView.separated(
            key: PageStorageKey('shelf/${category.categoryId}'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.only(left: NextMetrics.gutter, right: 56),
            itemCount: preview.length,
            separatorBuilder: (_, __) => const SizedBox(width: 18),
            itemBuilder: (context, i) => libraryTile(preview[i], _tile, on),
          ),
        ),
      ],
    );
  }
}
