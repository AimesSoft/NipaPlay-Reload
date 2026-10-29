import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui_data/library.dart';
import '../../ui_data/ui_data.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/devices.dart';
import '../widgets/icons.dart';
import '../widgets/words.dart';
import 'fan_cover.dart';
import 'selection.dart';

/// A category's items as a grid loads them: slices of [slice], each asked
/// for when its first tile is built. What is loaded stays on screen until
/// a change brings it again, so nothing blinks.
class CategoryItems extends ChangeNotifier {
  CategoryItems(this.data, this.categoryId, {int? total, this.sort})
      : _total = total;

  final NextLibraryData data;
  final String categoryId;

  /// The order asked for; null keeps the category's own.
  String? sort;
  int? _total;
  final _slices = <int, List<UiLibraryItem>>{};
  final _loading = <int>{};
  final _stale = <int>{};
  bool _gone = false;
  int _refreshRevision = 0;

  static const slice = 60;

  /// Tiles to lay out: the whole category when its size is known, else
  /// what is loaded and one slice more.
  int get count =>
      _total ??
      (_slices.isEmpty
          ? slice
          : (_slices.keys.reduce((a, b) => a > b ? a : b) + 2) * slice);

  /// Slices loaded so far, for the driver.
  List<int> get loaded => _slices.keys.toList()..sort();

  UiLibraryItem? at(int index) {
    final n = index ~/ slice;
    final items = _slices[n];
    if (items == null || _stale.contains(n)) unawaited(_load(n));
    final i = index % slice;
    return items == null || i >= items.length ? null : items[i];
  }

  /// The loaded works from the one with [anchor] to the one at [index].
  List<UiWork>? between(String anchor, int index) {
    UiLibraryItem? loaded(int index) {
      final items = _slices[index ~/ slice];
      final i = index % slice;
      return items == null || i >= items.length ? null : items[i];
    }

    final end = _slices.isEmpty
        ? 0
        : (_slices.keys.reduce((a, b) => a > b ? a : b) + 1) * slice;
    return worksBetween(
        [for (var i = 0; i < end; i++) loaded(i)], anchor, index);
  }

  Future<void> _load(int n) async {
    if (!_loading.add(n)) return;
    final asked = sort;
    final revision = _refreshRevision;
    late final UiSlice got;
    try {
      got = await data.items(categoryId,
          offset: n * slice, limit: slice, sort: asked);
    } finally {
      _loading.remove(n);
    }
    if (_gone || asked != sort) return;
    if (revision != _refreshRevision) {
      // Coalesce refreshes that arrived while this stale read was in flight.
      // An empty response cannot rely on a tile to request the next read.
      unawaited(_load(n));
      return;
    }
    _slices[n] = got.items;
    _stale.remove(n);
    _total = got.total ??
        (got.items.length < slice ? n * slice + got.items.length : _total);
    notifyListeners();
  }

  /// Something changed: each slice is asked for again as it is shown.
  void refresh() {
    _refreshRevision++;
    _stale.addAll(_slices.keys);
    // An empty grid builds no tiles, so none can ask for a stale slice.
    // Read its first slice to discover works that have arrived since.
    if (_total == 0) unawaited(_load(0));
    notifyListeners();
  }

  /// Another order: everything again, from the top.
  void reorder(String id) {
    sort = id;
    _slices.clear();
    _stale.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }
}

/// What opening and playing do from a library tile.
class LibraryCallbacks {
  const LibraryCallbacks(
      {required this.openWork, required this.play, required this.openFolder});
  final void Function(UiWork work) openWork;
  final void Function(UiWork work) play;
  final void Function(UiFolderItem folder) openFolder;
}

/// A tile for one item: a poster with its title (and the device it is on),
/// or a folder's fan. Up to [width] wide. [range] gives the works from a
/// picked one to this one, for a Shift-click.
Widget libraryTile(UiLibraryItem item, double width, LibraryCallbacks on,
        {List<UiWork>? Function(String anchor)? range}) =>
    switch (item) {
      UiWorkItem(:final work) =>
        WorkTile(work: work, width: width, on: on, range: range),
      UiFolderItem(:final title, :final count, :final posters) => FolderTile(
          title: title,
          count: count,
          posters: posters,
          width: width,
          onOpen: () => on.openFolder(item),
        ),
    };

/// A work's poster with its title (and the device it is on). Where the
/// page has a selection, a right-click opens its menu and ⌘- or
/// Shift-click picks (Shift: everything from the last pick); while
/// picking, a click picks instead of opening.
class WorkTile extends StatelessWidget {
  const WorkTile({
    super.key,
    required this.work,
    required this.width,
    required this.on,
    this.range,
  });

  final UiWork work;
  final double width;
  final LibraryCallbacks on;
  final List<UiWork>? Function(String anchor)? range;

  @override
  Widget build(BuildContext context) {
    final scope = SelectionScope.maybeOf(context);
    final selection = scope?.selection;
    final picking = selection != null && selection.active;

    void pick() {
      final anchor = selection!.anchor;
      if (HardwareKeyboard.instance.isShiftPressed && anchor != null) {
        if (range?.call(anchor) case final works?) return selection.add(works);
      }
      selection.toggle(work);
    }

    void open() {
      final keys = HardwareKeyboard.instance;
      if (selection != null &&
          (keys.isMetaPressed ||
              keys.isControlPressed ||
              keys.isShiftPressed)) {
        return pick();
      }
      on.openWork(work);
    }

    final poster = PosterCard(
      workId: work.workId,
      image: work.artwork.poster,
      tint: work.artwork.tint,
      title: work.title,
      width: width,
      height: width * 3 / 2,
      onOpen: picking ? null : open,
      onPlay: !picking && Words.canPlay(work) ? () => on.play(work) : null,
    );
    final tile = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (picking)
          Stack(children: [
            IgnorePointer(child: poster),
            Positioned(
              left: 0,
              top: 0,
              width: width,
              height: width * 3 / 2,
              child: PickMark(picked: selection.contains(work)),
            ),
          ])
        else
          poster,
        if (work.devices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: DeviceMark(work.devices),
          ),
      ],
    );
    if (scope == null) return tile;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: picking ? pick : null,
      onSecondaryTapUp: (d) => scope.menu(work, d.globalPosition),
      child: MouseRegion(
        cursor: picking ? SystemMouseCursors.click : MouseCursor.defer,
        child: tile,
      ),
    );
  }
}

/// Over a poster while picking: a ring to tick, and once picked, the
/// accent's outline and tick.
class PickMark extends StatelessWidget {
  const PickMark({super.key, required this.picked});
  final bool picked;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: picked ? NextColors.accent : const Color(0x00FF2E55),
              width: 2.5),
        ),
        alignment: Alignment.topRight,
        padding: const EdgeInsets.all(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: picked ? NextColors.accent : const Color(0x59000000),
            border: Border.all(
                color: picked ? NextColors.accent : const Color(0xD9F5F1EA),
                width: 1.5),
          ),
          child: picked
              ? const NextIcon(NextGlyph.check,
                  size: 13, color: NextColors.paper)
              : null,
        ),
      );
}

/// A tile still on its way: the poster's shape, quietly.
class WaitingTile extends StatelessWidget {
  const WaitingTile(this.width, {super.key});
  final double width;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: width * 3 / 2,
            decoration: BoxDecoration(
              color: const Color(0x0AFFFFFF),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: width * 0.6,
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0x0AFFFFFF),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      );
}

/// A category's items as a grid of posters, laid out for any number and
/// built only where it is seen (a sliver).
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    super.key,
    required this.items,
    required this.on,
    this.deviceLine = false,
  });

  final CategoryItems items;
  final LibraryCallbacks on;

  /// Room under each title for the device it is on (this device's source,
  /// where the mesh's works are).
  final bool deviceLine;

  static const maxTile = 196.0, gap = 20.0;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final columns = ((width + gap) / (maxTile + gap)).ceil();
          final tile = (width - gap * (columns - 1)) / columns;
          return ListenableBuilder(
            listenable: items,
            builder: (context, _) => SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 28,
                crossAxisSpacing: gap,
                // Poster, title, and the device line when there may be one.
                mainAxisExtent: tile * 3 / 2 + 12 + 22 + (deviceLine ? 21 : 0),
              ),
              delegate: SliverChildBuilderDelegate(
                childCount: items.count,
                (context, i) => switch (items.at(i)) {
                  final item? => libraryTile(item, tile, on,
                      range: (anchor) => items.between(anchor, i)),
                  null => WaitingTile(tile),
                },
              ),
            ),
          );
        },
      );
}
