import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../ui_data/library.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import 'category_grid.dart';
import 'fan_cover.dart';
import 'library_controls.dart';

/// What a category's page opens with: what its card, shelf or folder knew.
class CategoryRef {
  const CategoryRef(
      {required this.categoryId,
      required this.title,
      this.count,
      this.sorts = const []});
  final String categoryId;
  final String title;
  final int? count;
  final List<UiSort> sorts;
}

/// A category's whole page, over the library: pushed on the shell's
/// navigator, so Esc and the back button leave it and a work opens over it.
Route<void> categoryRoute(CategoryRef ref, {required bool deviceLine}) =>
    PageRouteBuilder<void>(
      transitionDuration: NextMotion.page,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, __) =>
          CategoryPage(ref: ref, deviceLine: deviceLine),
      transitionsBuilder: (context, animation, _, child) =>
          nextPageTransition(context, animation, child),
    );

/// Handles for `ext.nipaplay.nextui` in lab profiles.
abstract interface class CategoryDebug {
  ScrollController get debugScroll;
  void debugSort(String id);
  Map<String, Object?> debugStatus();
}

/// Its name and count, its order, and every item in a grid that loads as
/// it scrolls; a folder opens the next level.
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key, required this.ref, required this.deviceLine});
  final CategoryRef ref;
  final bool deviceLine;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    implements CategoryDebug {
  NextShellController? _shell;
  CategoryItems? _items;
  StreamSubscription<void>? _changes;
  final _scroll = ScrollController();
  final _sortLink = LayerLink();
  bool _sortsOpen = false;

  /// Past its big title, the page keeps a small one by the back button.
  final _docked = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _docked.value = _scroll.offset > 56);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell = shell;
    _items?.dispose();
    _items = CategoryItems(shell.services.library, widget.ref.categoryId,
        total: widget.ref.count);
    _changes?.cancel();
    _changes = shell.services.library.changes.listen((_) => _items!.refresh());
  }

  @override
  void dispose() {
    _changes?.cancel();
    _items?.dispose();
    _scroll.dispose();
    _docked.dispose();
    super.dispose();
  }

  List<UiSort> get _sorts => widget.ref.sorts;

  String? get _sortLabel {
    final id = _items!.sort ?? _sorts.firstOrNull?.id;
    return _sorts.where((s) => s.id == id).firstOrNull?.label;
  }

  LibraryCallbacks get _on => LibraryCallbacks(
        openWork: _shell!.openWork,
        play: (work) => _shell!.play(work),
        openFolder: (folder) => Navigator.of(context).push(categoryRoute(
            CategoryRef(
                categoryId: folder.categoryId,
                title: folder.title,
                count: folder.count),
            deviceLine: widget.deviceLine)),
      );

  @override
  ScrollController get debugScroll => _scroll;

  @override
  void debugSort(String id) => setState(() => _items!.reorder(id));

  @override
  Map<String, Object?> debugStatus() {
    var built = 0;
    void visit(Element e) {
      final w = e.widget;
      if (w is PosterCard || w is FolderTile || w is WaitingTile) built++;
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return {
      'category': widget.ref.title,
      'count': _items!.count,
      'sort': _sortLabel,
      'sorts': [for (final s in _sorts) s.label],
      'loadedSlices': _items!.loaded,
      'builtTiles': built,
      'scroll': _scroll.hasClients ? _scroll.offset : null,
      'maxScroll': _scroll.hasClients ? _scroll.position.maxScrollExtent : null,
    };
  }

  /// Under the top bar once the grid scrolls beneath it: a scrim, and the
  /// name small beside the back button.
  Widget _bar(int? count) => ValueListenableBuilder<bool>(
        valueListenable: _docked,
        builder: (context, docked, _) => AnimatedOpacity(
          opacity: docked ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xF208080B), Color(0xE008080B), Color(0x0008080B)],
                stops: [0, 0.6, 1],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(
                  left: NextMetrics.gutter + 30,
                  right: 56,
                  top: NextMetrics.topBar + 8),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  height: 32,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CategoryName(
                        title: widget.ref.title, count: count, size: 15),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final count = widget.ref.count;
    return Listener(
      onPointerDown: (e) {
        if (e.buttons & kBackMouseButton != 0) Navigator.of(context).maybePop();
      },
      child: ColoredBox(
        color: NextColors.ink,
        child: Stack(children: [
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    NextMetrics.gutter, NextMetrics.topBar + 56, 56, 28),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(children: [
                          Flexible(
                            child: Text(widget.ref.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NextText.sans(28,
                                    weight: FontWeight.w600)),
                          ),
                          if (count != null) ...[
                            const SizedBox(width: 14),
                            Text('$count',
                                style:
                                    NextText.num(18, color: NextColors.p3)),
                          ],
                        ]),
                      ),
                      if (_sorts.length > 1)
                        CompositedTransformTarget(
                          link: _sortLink,
                          child: MenuPill(
                            label: _sortLabel!,
                            onTap: () =>
                                setState(() => _sortsOpen = !_sortsOpen),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(NextMetrics.gutter, 0, 56, 64),
                sliver: CategoryGrid(
                    items: _items!, on: _on, deviceLine: widget.deviceLine),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: NextMetrics.topBar + 76,
            child: IgnorePointer(child: _bar(count)),
          ),
          Positioned(
            left: NextMetrics.gutter - 9,
            top: NextMetrics.topBar + 8,
            child: NextIconButton(
              glyph: NextGlyph.chevronLeft,
              label: '返回',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          if (_sortsOpen)
            ...anchoredMenu(
              link: _sortLink,
              right: true,
              close: () => setState(() => _sortsOpen = false),
              menu: MenuPanel(width: 160, children: [
                for (final s in _sorts)
                  MenuItem(
                    label: s.label,
                    selected: s.label == _sortLabel,
                    onTap: () => setState(() {
                      _sortsOpen = false;
                      _items!.reorder(s.id);
                    }),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
