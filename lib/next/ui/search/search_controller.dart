import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../data/discover.dart' show Found;
import '../data/search.dart';
import 'recent_searches.dart';

/// The groups, in the order they show.
enum SearchGroupKind { library, online, sources }

enum SearchGroupState { idle, loading, done, failed }

/// One group's answer. While a new query runs it keeps the last answer
/// (dimmed) when the new query refines the old one.
final class SearchGroup {
  const SearchGroup(
      [this.entries = const [],
      this.state = SearchGroupState.idle,
      this.unanswered = const []]);
  final List<SearchEntry> entries;
  final SearchGroupState state;

  /// The sources that could not be searched and have nothing to show, by
  /// name: what they hold is unknown.
  final List<String> unanswered;

  bool get loading => state == SearchGroupState.loading;
  bool get failed => state == SearchGroupState.failed;
}

/// A row of the search panel. [key] follows it while other groups land.
sealed class SearchEntry {
  const SearchEntry();
  String get key;
}

/// A search term searched before.
final class RecentEntry extends SearchEntry {
  const RecentEntry(this.text);
  final String text;
  @override
  String get key => 'recent:$text';
}

/// A work: in the library, or online (its found page, or its page in the
/// library when the library has it).
final class WorkEntry extends SearchEntry {
  const WorkEntry(this.group, this.work);
  final SearchGroupKind group;
  final UiWork work;

  /// Found online, and the library has it.
  bool get inLibrary => group == SearchGroupKind.online && !Found.isFound(work);
  @override
  String get key => '${group.name}:${work.workId}';
}

final class EpisodeEntry extends SearchEntry {
  const EpisodeEntry(this.work, this.episode);
  final UiWork work;
  final UiEpisode episode;
  @override
  String get key => 'episode:${episode.episodeId}';
}

/// Something a media source holds: a work, an episode, or a file of a
/// share.
final class SourceEntry extends SearchEntry {
  const SourceEntry(this.hit);
  final UiSourceHit hit;
  @override
  String get key => 'source:${hit.source.sourceId}:${hit.itemId}';
}

/// The last row: the text, for Nipa to look for.
final class NipaEntry extends SearchEntry {
  const NipaEntry(this.text);
  final String text;
  @override
  String get key => 'nipa';
}

/// The search panel's state: what is typed, each group's answer to it,
/// the selected row and the terms searched before (kept in [store], when
/// there is one).
///
/// Typing waits [debounce] before asking; every group asks on its own and
/// an answer to an older query is dropped.
class NextSearch extends ChangeNotifier {
  NextSearch(this.data,
      {this.store, this.debounce = const Duration(milliseconds: 200)}) {
    text.addListener(_typed);
    unawaited(_ready);
  }

  final NextSearchData data;
  final RecentSearchStore? store;
  final Duration debounce;
  final text = TextEditingController();
  final focus = FocusNode(debugLabel: 'next.search');

  static const recentLimit = 10;
  static const _limits = {
    SearchGroupKind.library: 6,
    SearchGroupKind.online: 6,
  };
  static const _episodeLimit = 4;

  /// Rows from each source.
  static const perSource = 3;

  bool _open = false;
  bool get isOpen => _open;

  /// What is typed, trimmed; the groups may still answer an older [query].
  String get typed => text.text.trim();

  /// The query the groups answer.
  String get query => _query;
  String _query = '';
  String _seen = '';
  int _generation = 0;
  Timer? _timer;
  Completer<void>? _libraryLanded;

  final _groups = <SearchGroupKind, SearchGroup>{
    for (final kind in SearchGroupKind.values) kind: const SearchGroup(),
  };

  /// The groups that exist (sources only where they can be searched).
  Map<SearchGroupKind, SearchGroup> get groups => Map.unmodifiable(_groups);

  final _recent = <String>[];
  List<String> get recent => List.unmodifiable(_recent);

  String? _selectedKey;

  /// The last selection came from the keyboard: the list follows it.
  bool movedByKeyboard = false;

  /// … upwards.
  bool movedUp = false;

  List<SearchEntry>? _entries;

  /// The rows, in order: the recent terms when nothing is typed; otherwise
  /// every group's, then Nipa.
  List<SearchEntry> get entries => _entries ??= _build();

  List<SearchEntry> _build() {
    final typed = this.typed;
    if (typed.isEmpty) return [for (final t in _recent) RecentEntry(t)];
    return [
      for (final kind in SearchGroupKind.values) ...shown(kind),
      NipaEntry(typed),
    ];
  }

  /// A group's rows. A work the library shows is not shown again as found
  /// online or in a source: the same work by its library ID, whatever it is
  /// called there.
  List<SearchEntry> shown(SearchGroupKind kind) {
    final group = _groups[kind];
    if (group == null) return const [];
    if (kind == SearchGroupKind.library) return group.entries;
    final have = {
      for (final e in _groups[SearchGroupKind.library]!.entries)
        if (e is WorkEntry) e.work.workId,
    };
    return [
      for (final e in group.entries)
        if (switch (e) {
          WorkEntry(:final work) => !have.contains(work.workId),
          SourceEntry(:final hit) when hit.kind == UiSourceHitKind.work =>
            !have.contains(hit.work?.workId),
          _ => true,
        })
          e,
    ];
  }

  /// Every group, every source, has answered the query typed, with nothing.
  bool get nothingFound =>
      typed.isNotEmpty &&
      typed == _query &&
      _timer == null &&
      _groups.values.every(
          (g) => g.state == SearchGroupState.done && g.unanswered.isEmpty) &&
      entries.length == 1;

  bool get loading => _timer != null || _groups.values.any((g) => g.loading);

  int get selectedIndex {
    final list = entries;
    final at = list.indexWhere((e) => e.key == _selectedKey);
    return at < 0 ? 0 : at;
  }

  SearchEntry? get selected {
    final list = entries;
    return list.isEmpty ? null : list[selectedIndex];
  }

  bool _disposed = false;

  void _changed() {
    if (_disposed) return;
    _entries = null;
    notifyListeners();
  }

  // —— Open and close ——

  /// Opens the panel; what was typed before stays, selected, so typing
  /// replaces it.
  void show() {
    text.selection =
        TextSelection(baseOffset: 0, extentOffset: text.text.length);
    if (_open) return;
    _open = true;
    // The sources there are now, read as the panel opens.
    _sourceList = _readSources();
    _changed();
  }

  /// Closes the panel. A dismissal gives the focus back to where it was;
  /// what a row opens takes it instead ([restoreFocus] false).
  void hide({bool restoreFocus = true}) {
    if (!_open) return;
    _open = false;
    this.restoreFocus = restoreFocus;
    _changed();
  }

  /// How the panel was last closed (see [hide]).
  bool restoreFocus = true;

  // —— Typing ——

  void _typed() {
    final value = text.value;
    // Pinyin being composed is not what is looked for yet.
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    final typed = value.text.trim();
    if (typed == _seen) return;
    _seen = typed;
    _timer?.cancel();
    _timer = null;
    _selectedKey = null;
    if (typed.isEmpty) {
      _generation++;
      _query = '';
      for (final kind in _groups.keys) {
        _groups[kind] = const SearchGroup();
      }
    } else {
      _timer = Timer(debounce, () => _run(typed));
    }
    _changed();
  }

  /// Asks every group now, for [q].
  void _run(String q) {
    _timer?.cancel();
    _timer = null;
    final generation = ++_generation;
    final refines =
        _query.isNotEmpty && (q.contains(_query) || _query.contains(q));
    _query = q;
    _selectedKey = null;
    final landed = _libraryLanded = Completer<void>();

    void ask(SearchGroupKind kind, Future<List<SearchEntry>> answer) {
      final before = _groups[kind]!;
      _groups[kind] = SearchGroup(
          refines ? before.entries : const [], SearchGroupState.loading);
      answer.then((entries) {
        if (generation != _generation) return;
        _groups[kind] = SearchGroup(entries, SearchGroupState.done);
        _changed();
      }, onError: (Object error) {
        if (generation != _generation) return;
        debugPrint('[NextUi] search ${kind.name} failed: $error');
        _groups[kind] = const SearchGroup([], SearchGroupState.failed);
        _changed();
      }).whenComplete(() {
        if (kind == SearchGroupKind.library && !landed.isCompleted) {
          landed.complete();
        }
      });
    }

    ask(
        SearchGroupKind.library,
        Future.sync(() => data.library(q)).then((hits) => [
              for (final w
                  in hits.works.take(_limits[SearchGroupKind.library]!))
                WorkEntry(SearchGroupKind.library, w),
              for (final (w, e) in hits.episodes.take(_episodeLimit))
                EpisodeEntry(w, e),
            ]));
    ask(
        SearchGroupKind.online,
        Future.sync(() => data.online(q)).then((works) {
          // Two results may be one work of the library.
          final seen = <String>{};
          return [
            for (final w in works)
              if (seen.add(w.workId)) WorkEntry(SearchGroupKind.online, w),
          ].take(_limits[SearchGroupKind.online]!).toList();
        }));
    _askSources(q, generation, refines);
    _changed();
  }

  // —— Sources ——

  /// The sources, read when the panel opens; read again after a failure.
  Future<List<UiSearchSource>>? _sourceList;

  Future<List<UiSearchSource>> _readSources() {
    final list = Future.sync(data.sources);
    list.then((_) {}, onError: (Object error) {
      if (identical(_sourceList, list)) _sourceList = null;
    });
    return list;
  }

  /// Every source on its own: its rows land as it answers, in the sources'
  /// order; one that cannot answer says so alone. No sources, no group.
  void _askSources(String q, int generation, bool refines) {
    const kind = SearchGroupKind.sources;
    final kept = refines
        ? _groups[kind]?.entries ?? const <SearchEntry>[]
        : const <SearchEntry>[];
    _groups[kind] = SearchGroup(kept, SearchGroupState.loading);
    (_sourceList ??= _readSources()).then((sources) {
      if (generation != _generation) return;
      if (sources.isEmpty) {
        _groups.remove(kind);
        _changed();
        return;
      }
      final answers = List<UiSourceAnswer?>.filled(sources.length, null);
      void land(int i, UiSourceAnswer answer) {
        if (generation != _generation) return;
        answers[i] = answer;
        final seen = <String>{};
        _groups[kind] = SearchGroup(
          [
            for (final a in answers.nonNulls)
              for (final hit in a.hits.take(perSource))
                if (SourceEntry(hit) case final e when seen.add(e.key)) e,
          ],
          answers.contains(null)
              ? SearchGroupState.loading
              : SearchGroupState.done,
          [
            for (final (i, a) in answers.indexed)
              if (a != null && a.failed && a.hits.isEmpty) sources[i].name,
          ],
        );
        _changed();
      }

      for (final (i, source) in sources.indexed) {
        Future.sync(() => data.searchSource(source, q, limit: perSource))
            .then((answer) => land(i, answer), onError: (Object error) {
          debugPrint('[NextUi] search ${source.kind.name} source failed: '
              '$error');
          land(i, const UiSourceAnswer([], failed: true));
        });
      }
    }, onError: (Object error) {
      if (generation != _generation) return;
      debugPrint('[NextUi] search sources failed: $error');
      _groups[kind] = const SearchGroup([], SearchGroupState.failed);
      _changed();
    });
  }

  /// Puts [term] in the box and searches it at once (a recent term).
  void searchNow(String term) {
    text.value = TextEditingValue(
        text: term, selection: TextSelection.collapsed(offset: term.length));
    if (_timer != null) _run(typed);
  }

  /// Enter: the selected row. When the rows still answer an older text,
  /// the search runs now and the library's first work is taken, if any.
  Future<SearchEntry?> submit() async {
    final typed = this.typed;
    if (typed.isEmpty ||
        (typed == _query &&
            _timer == null &&
            !_groups[SearchGroupKind.library]!.loading)) {
      return selected;
    }
    if (_timer != null || typed != _query) _run(typed);
    final generation = _generation;
    await _libraryLanded?.future;
    if (generation != _generation || !_open) return null;
    final first = entries.first;
    return first is NipaEntry ? null : first;
  }

  // —— Selection ——

  void move(int delta) {
    final list = entries;
    if (list.isEmpty) return;
    final to = (selectedIndex + delta).clamp(0, list.length - 1);
    _selectedKey = list[to].key;
    movedByKeyboard = true;
    movedUp = delta < 0;
    _changed();
  }

  /// The pointer moved over a row.
  void hover(SearchEntry entry) {
    if (_selectedKey == entry.key) return;
    _selectedKey = entry.key;
    movedByKeyboard = false;
    _changed();
  }

  // —— Recent terms ——

  /// The stored terms, read once; terms remembered meanwhile stay first.
  late final Future<void> _ready = _load();
  bool _cleared = false;

  Future<void> _load() async {
    final store = this.store;
    if (store == null) return;
    try {
      final stored = await store.load();
      if (_disposed || _cleared) return;
      for (final term in stored) {
        if (_recent.length >= recentLimit) break;
        if (!_recent.contains(term)) _recent.add(term);
      }
      _changed();
    } catch (error) {
      debugPrint('[NextUi] recent searches unreadable: $error');
    }
  }

  void _store(Future<void> Function(RecentSearchStore store) write) {
    final store = this.store;
    if (store == null) return;
    unawaited(_ready.then((_) => write(store)).catchError((Object error) {
      debugPrint('[NextUi] recent searches not kept: $error');
    }));
  }

  /// Something was opened for what is typed: it becomes a recent term.
  void remember() {
    final term = typed;
    if (term.isEmpty) return;
    _recent
      ..remove(term)
      ..insert(0, term);
    while (_recent.length > recentLimit) {
      _recent.removeLast();
    }
    final terms = List.of(_recent);
    _store((store) => store.save(terms));
    _changed();
  }

  /// Forgets every recent term, the stored record too.
  void clearRecent() {
    _cleared = true;
    _store((store) => store.clear());
    if (_recent.isEmpty) return;
    _recent.clear();
    _selectedKey = null;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    text.removeListener(_typed);
    text.dispose();
    focus.dispose();
    super.dispose();
  }
}
