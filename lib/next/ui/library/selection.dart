import 'package:flutter/widgets.dart';

import '../../ui_data/library.dart';
import '../../ui_data/ui_data.dart';

/// The works picked on a page to do something to them together, in the
/// order picked. Active from the first pick until ended (Esc, 取消),
/// even with none picked.
class LibrarySelection extends ChangeNotifier {
  final _works = <String, UiWork>{};
  bool _active = false;
  String? _anchor;

  bool get active => _active;
  List<UiWork> get works => _works.values.toList();
  int get count => _works.length;
  bool contains(UiWork work) => _works.containsKey(work.workId);

  /// The work last picked alone, where a Shift-click's range starts.
  String? get anchor => _anchor;

  void toggle(UiWork work) {
    _active = true;
    if (_works.remove(work.workId) == null) _works[work.workId] = work;
    _anchor = work.workId;
    notifyListeners();
  }

  void add(Iterable<UiWork> works) {
    _active = true;
    for (final w in works) {
      _works[w.workId] = w;
    }
    notifyListeners();
  }

  void end() {
    if (!_active) return;
    _active = false;
    _works.clear();
    _anchor = null;
    notifyListeners();
  }
}

/// A page's selection for its tiles, and the menu a right-click opens.
class SelectionScope extends InheritedNotifier<LibrarySelection> {
  const SelectionScope({
    super.key,
    required LibrarySelection selection,
    required this.menu,
    required super.child,
  }) : super(notifier: selection);

  /// Opens the tile menu for a work where the pointer is (global).
  final void Function(UiWork work, Offset at) menu;

  static SelectionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SelectionScope>();

  LibrarySelection get selection => notifier!;
}

/// The works of [items] from the one with [anchor] to the one at [index],
/// either way; null when [anchor] is not among them.
List<UiWork>? worksBetween(
    List<UiLibraryItem?> items, String anchor, int index) {
  final from =
      items.indexWhere((i) => i is UiWorkItem && i.work.workId == anchor);
  if (from < 0) return null;
  final (a, b) = from < index ? (from, index) : (index, from);
  return [
    for (final item in items.sublist(a, b + 1))
      if (item is UiWorkItem) item.work
  ];
}

/// Every work of a category, read a slice at a time (folders left out).
Future<List<UiWork>> allWorks(NextLibraryData data, String categoryId,
    {String? sort}) async {
  const slice = 60;
  final works = <UiWork>[];
  for (var offset = 0;; offset += slice) {
    final got =
        await data.items(categoryId, offset: offset, limit: slice, sort: sort);
    works.addAll([
      for (final item in got.items)
        if (item is UiWorkItem) item.work
    ]);
    final total = got.total;
    if (got.items.length < slice ||
        (total != null && offset + slice >= total)) {
      return works;
    }
  }
}
