import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/library.dart';
import '../../ui_data/ui_data.dart';
import '../widgets/cards.dart';
import '../widgets/devices.dart';
import '../widgets/words.dart';
import 'fan_cover.dart';

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

  Future<void> _load(int n) async {
    if (!_loading.add(n)) return;
    final asked = sort;
    final got = await data.items(categoryId,
        offset: n * slice, limit: slice, sort: asked);
    _loading.remove(n);
    if (_gone || asked != sort) return;
    _slices[n] = got.items;
    _stale.remove(n);
    _total = got.total ??
        (got.items.length < slice ? n * slice + got.items.length : _total);
    notifyListeners();
  }

  /// Something changed: each slice is asked for again as it is shown.
  void refresh() {
    _stale.addAll(_slices.keys);
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
/// or a folder's fan. Up to [width] wide.
Widget libraryTile(UiLibraryItem item, double width, LibraryCallbacks on) =>
    switch (item) {
      UiWorkItem(:final work) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            PosterCard(
              workId: work.workId,
              image: work.artwork.poster,
              tint: work.artwork.tint,
              title: work.title,
              width: width,
              height: width * 3 / 2,
              onOpen: () => on.openWork(work),
              onPlay: Words.canPlay(work) ? () => on.play(work) : null,
            ),
            if (work.devices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: DeviceMark(work.devices),
              ),
          ],
        ),
      UiFolderItem(:final title, :final count, :final posters) => FolderTile(
          title: title,
          count: count,
          posters: posters,
          width: width,
          onOpen: () => on.openFolder(item),
        ),
    };

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
                  final item? => libraryTile(item, tile, on),
                  null => WaitingTile(tile),
                },
              ),
            ),
          );
        },
      );
}
