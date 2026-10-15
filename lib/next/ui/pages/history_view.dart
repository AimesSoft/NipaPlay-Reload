import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/gui_calls.dart';
import '../data/history.dart';
import '../settings/controls.dart' show PillButton;
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/icons.dart';
import '../widgets/progress.dart';
import '../widgets/sheet.dart';

/// Debug hooks of the 观看记录 list.
abstract interface class HistoryDebug {
  /// Applies `reload=true`, `more=true` (reads the next page),
  /// `hover=<i>` (`none` to stop), `open=<i>`, `resume=<i>` (not waiting
  /// for a question it may ask), `remove=<i>` and `clear=ask` (not waiting
  /// for the answer); `i` counts the entries shown from 0, latest first.
  Future<void> debug(Map<String, String> p);
  Map<String, Object?> debugStatus();
}

/// A day of the record and what was watched on it, latest first.
final class HistoryGroup {
  HistoryGroup(this.label);
  final String label;
  final entries = <UiHistoryEntry>[];
}

/// The record cut by day, in its own order: 今天, 昨天, the five days
/// before by weekday, then dates.
List<HistoryGroup> groupHistory(Iterable<UiHistoryEntry> entries,
    {DateTime? now}) {
  final current = now ?? DateTime.now();
  final groups = <String, HistoryGroup>{};
  for (final e in entries) {
    final label = historyDay(e.at, now: current);
    (groups[label] ??= HistoryGroup(label)).entries.add(e);
  }
  return groups.values.toList();
}

/// The day [at] falls on, as a group of the record calls it. A week ago
/// shares today's weekday, so from there on it is a date.
String historyDay(DateTime? at, {required DateTime now}) {
  if (at == null) return '更早';
  final today = DateTime(now.year, now.month, now.day);
  final days =
      (today.difference(DateTime(at.year, at.month, at.day)).inHours / 24)
          .round();
  if (days <= 0) return '今天';
  if (days == 1) return '昨天';
  if (days < 7) return _weekdays[at.weekday - 1];
  return at.year == now.year
      ? '${at.month}月${at.day}日'
      : '${at.year}年${at.month}月${at.day}日';
}

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String _clock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// Watched to here counts as seen through (the credits).
const _seen = 0.95;

/// An entry whose work or episode the library no longer has.
const _missing = '已经不在了';

const _width = 760.0;

/// 观看记录: what was watched, by day, latest first. Scrolls itself and
/// reads on near the end; [top] leaves room for what the page draws above
/// it. An entry opens its work (goes on with it when it has none);
/// hovering it offers to go on with it or forget it.
class HistoryView extends StatefulWidget {
  const HistoryView({super.key, this.top = 0});
  final double top;

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> implements HistoryDebug {
  NextShellController? _shell;
  final _scroll = ScrollController();

  List<UiHistoryEntry> _entries = const [];
  String? _cursor;

  /// The first read has come back.
  bool _read = false;
  bool _reading = false;

  /// Counts reads; one overtaken by a newer one is dropped.
  int _reads = 0;

  /// Reading from the start failed.
  Object? _error;

  /// Reading on failed.
  Object? _moreError;

  bool _clearing = false;
  String? _clearNote;

  /// Forgotten, fading out.
  final _gone = <String>{};
  final _working = <String>{};
  final _notes = <String, String>{};
  String? _hover;

  NextHistory get _history => _shell!.services.history;

  List<UiHistoryEntry> get _shown => [
        for (final e in _entries)
          if (!_gone.contains(e.entryId)) e
      ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell = shell;
    unawaited(_reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Reads from the start again.
  Future<void> _reload() async {
    final read = ++_reads;
    _reading = true;
    try {
      final page = await _history.page();
      if (!mounted || read != _reads) return;
      setState(() {
        _entries = page.entries;
        _cursor = page.cursor;
        _read = true;
        _reading = false;
        _error = null;
        _moreError = null;
        _gone.clear();
        _notes.clear();
      });
    } catch (e) {
      if (!mounted || read != _reads) return;
      setState(() {
        _read = true;
        _reading = false;
        _error = e;
      });
    }
    _fill();
  }

  Future<void> _more() async {
    if (_reading || _cursor == null || _moreError != null) return;
    final read = ++_reads;
    _reading = true;
    try {
      final page = await _history.page(cursor: _cursor);
      if (!mounted || read != _reads) return;
      setState(() {
        _entries = [..._entries, ...page.entries];
        _cursor = page.cursor;
        _reading = false;
      });
    } catch (e) {
      if (!mounted || read != _reads) return;
      setState(() {
        _reading = false;
        _moreError = e;
      });
    }
    _fill();
  }

  void _nearEnd() {
    if (_scroll.position.extentAfter < 480) unawaited(_more());
  }

  /// A list too short to scroll reads on by itself.
  void _fill() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _nearEnd();
      });

  void _retry() {
    setState(() => _moreError = null);
    unawaited(_error == null ? _more() : _reload());
  }

  Future<void> _open(UiHistoryEntry e) async {
    final shell = _shell!;
    setState(() => _notes.remove(e.entryId));
    try {
      final work = await shell.services.data.work(e.workId!);
      if (!mounted) return;
      if (work == null) {
        setState(() => _notes[e.entryId] = _missing);
      } else {
        shell.openWork(work);
      }
    } catch (error) {
      if (mounted) setState(() => _notes[e.entryId] = callFailure(error));
    }
  }

  Future<void> _resume(UiHistoryEntry e) async {
    setState(() {
      _working.add(e.entryId);
      _notes.remove(e.entryId);
    });
    try {
      if (e.locator != null) {
        await withDecisions(_shell!.services.calls, () => _history.resume(e));
      } else if (!await _playFromLibrary(e) && mounted) {
        setState(() => _notes[e.entryId] = _missing);
      }
    } catch (error) {
      if (mounted) setState(() => _notes[e.entryId] = callFailure(error));
    }
    if (mounted) setState(() => _working.remove(e.entryId));
  }

  /// Plays the entry's episode from wherever the library has it; false
  /// when the library no longer has it.
  Future<bool> _playFromLibrary(UiHistoryEntry e) async {
    final services = _shell!.services;
    final work = await services.data.work(e.workId!);
    if (work == null) return false;
    final episode = (await services.data.episodes(work.workId))
        .where((x) => x.episodeId == e.libraryEpisodeId)
        .firstOrNull;
    if (episode == null) return false;
    await services.actions.play(work, episode: episode);
    return true;
  }

  Future<void> _remove(UiHistoryEntry e) async {
    setState(() {
      _working.add(e.entryId);
      _notes.remove(e.entryId);
    });
    try {
      await _history.remove([e]);
      if (mounted) setState(() => _gone.add(e.entryId));
    } catch (error) {
      if (mounted) setState(() => _notes[e.entryId] = callFailure(error));
    }
    if (mounted) setState(() => _working.remove(e.entryId));
  }

  /// Its row has faded out.
  void _forget(String id) => setState(() {
        _gone.remove(id);
        _entries = [
          for (final e in _entries)
            if (e.entryId != id) e
        ];
        if (_hover == id) _hover = null;
      });

  Future<void> _clear() async {
    final chosen = await chooseSheet(
      title: '清空观看记录？',
      choices: const [SheetChoice('清空', danger: true)],
    );
    if (chosen != 0 || !mounted) return;
    setState(() {
      _clearing = true;
      _clearNote = null;
    });
    try {
      await _history.clear();
      if (mounted) await _reload();
    } catch (e) {
      if (mounted) setState(() => _clearNote = callFailure(e));
    }
    if (mounted) setState(() => _clearing = false);
  }

  @override
  Future<void> debug(Map<String, String> p) async {
    UiHistoryEntry at(String i) => _shown[int.parse(i)];
    if (p['reload'] == 'true') await _reload();
    if (p['more'] == 'true') await _more();
    if (p['hover'] case final i?) {
      setState(() => _hover = i == 'none' ? null : at(i).entryId);
    }
    if (p['open'] case final i?) await _open(at(i));
    if (p['resume'] case final i?) unawaited(_resume(at(i)));
    if (p['remove'] case final i?) await _remove(at(i));
    if (p['clear'] == 'ask') unawaited(_clear());
  }

  @override
  Map<String, Object?> debugStatus() {
    final shown = _shown;
    final error = _error ?? _moreError;
    return {
      'entries': shown.length,
      'distinct': {for (final e in shown) e.entryId}.length,
      'groups': groupHistory(shown).length,
      'more': _cursor != null,
      'error': error == null ? null : '$error',
      if (_clearNote != null) 'clearNote': _clearNote,
      if (_notes.isNotEmpty) 'notes': {..._notes},
    };
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (_error != null) {
      children.add(
          _Failed(text: callFailure(_error!), busy: _reading, onRetry: _retry));
    } else if (_read && _entries.isEmpty) {
      children.add(const _Empty());
    } else {
      for (final (i, group) in groupHistory(_entries).indexed) {
        children.add(_Fade(
          key: ValueKey('day:${group.label}'),
          gone: group.entries.every((e) => _gone.contains(e.entryId)),
          child: _DayHead(
            label: group.label,
            first: i == 0,
            trailing: i == 0
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_clearNote != null) ...[
                      Text(_clearNote!,
                          style: NextText.sans(12, color: NextColors.amber)),
                      const SizedBox(width: 12),
                    ],
                    PillButton(label: '清空', busy: _clearing, onTap: _clear),
                  ])
                : null,
          ),
        ));
        for (final e in group.entries) {
          final id = e.entryId;
          final working = _working.contains(id);
          children.add(_Fade(
            key: ValueKey(id),
            gone: _gone.contains(id),
            onGone: () => _forget(id),
            child: _EntryRow(
              entry: e,
              hover: _hover == id,
              note: _notes[id],
              onOpen: e.workId != null ? () => _open(e) : null,
              onResume: e.playable && !working ? () => _resume(e) : null,
              onRemove: working ? null : () => _remove(e),
            ),
          ));
        }
      }
      if (_moreError != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 20),
          child: _Failed(
              text: callFailure(_moreError!), busy: _reading, onRetry: _retry),
        ));
      } else if (_cursor != null) {
        children.add(const Padding(
          padding: EdgeInsets.fromLTRB(14, 24, 0, 0),
          child: Align(alignment: Alignment.centerLeft, child: ThinkingDots()),
        ));
      }
    }
    return AnimatedOpacity(
      opacity: _read ? 1 : 0,
      duration: const Duration(milliseconds: 240),
      child: ListView.builder(
        key: const PageStorageKey('activity.history'),
        controller: _scroll,
        // Rows carry 14 of their own on each side, so their text lines up
        // with the page's edge.
        padding: EdgeInsets.fromLTRB(
            NextMetrics.gutter - 14, widget.top, 56 - 14, 64),
        itemCount: children.length,
        itemBuilder: (context, i) => Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _width),
            child: children[i],
          ),
        ),
      ),
    );
  }
}

class _DayHead extends StatelessWidget {
  const _DayHead({required this.label, required this.first, this.trailing});
  final String label;
  final bool first;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(14, first ? 0 : 30, 14, 8),
        child: SizedBox(
          height: 30,
          child: Row(children: [
            Expanded(
              child: Text(label,
                  style: NextText.sans(12.5,
                      weight: FontWeight.w500,
                      color: NextColors.p3,
                      letterSpacing: 0.4)),
            ),
            if (trailing != null) trailing!,
          ]),
        ),
      );
}

/// One entry: its picture with how far it went, the work and episode,
/// when. Hovered, the time gives way to going on with it and forgetting it.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.hover,
    this.note,
    this.onOpen,
    this.onResume,
    this.onRemove,
  });
  final UiHistoryEntry entry;

  /// Shown as hovered (debug).
  final bool hover;

  /// What went wrong with it last.
  final String? note;
  final VoidCallback? onOpen;
  final VoidCallback? onResume;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final playable = entry.playable;
    final episode = entry.episode;
    final at = entry.at;
    final progress = entry.progress ?? 0;
    final seen = progress >= _seen;
    return Pressable(
      onTap: onOpen ?? onResume,
      pressScale: 0.99,
      semanticLabel: entry.title,
      builder: (context, hovered) {
        final active = hovered || hover;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0x0DFFFFFF) : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Opacity(
              opacity: playable ? 1 : 0.45,
              child: WideCard(
                image: entry.still,
                poster: entry.poster,
                workId: entry.workId,
                width: 128,
                height: 72,
                progress: seen || progress == 0 ? null : progress,
                label: seen
                    ? const NextIcon(NextGlyph.check,
                        size: 13, color: NextColors.paper, stroke: 2.6)
                    : null,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NextText.sans(14.5,
                          weight: FontWeight.w500,
                          color: playable ? NextColors.paper : NextColors.p2)),
                  if (episode != null && episode.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(episode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NextText.sans(12.5, color: NextColors.p3)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 80,
              height: 32,
              child: Stack(alignment: Alignment.centerRight, children: [
                AnimatedOpacity(
                  opacity: active ? 0 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: note != null
                      ? Text(note!,
                          maxLines: 1,
                          style: NextText.sans(12, color: NextColors.amber))
                      : Text(at == null ? '' : _clock(at),
                          style: NextText.num(12.5,
                              weight: FontWeight.w400, color: NextColors.p3)),
                ),
                IgnorePointer(
                  ignoring: !active,
                  child: AnimatedOpacity(
                    opacity: active ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (playable) ...[
                        NextIconButton(
                            glyph: NextGlyph.play,
                            label: '继续',
                            onTap: onResume),
                        const SizedBox(width: 6),
                      ],
                      NextIconButton(
                          glyph: NextGlyph.close,
                          label: '删除',
                          onTap: onRemove),
                    ]),
                  ),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

/// Fades a forgotten row out, then folds its space away.
class _Fade extends StatefulWidget {
  const _Fade(
      {super.key, required this.gone, required this.child, this.onGone});
  final bool gone;
  final Widget child;
  final VoidCallback? onGone;

  @override
  State<_Fade> createState() => _FadeState();
}

class _FadeState extends State<_Fade> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360), value: 1);
  late final _opacity =
      CurvedAnimation(parent: _c, curve: const Interval(0.45, 1));
  late final _size = CurvedAnimation(
      parent: _c, curve: const Interval(0, 0.6, curve: NextMotion.ease));

  @override
  void didUpdateWidget(_Fade old) {
    super.didUpdateWidget(old);
    if (widget.gone && !old.gone) {
      _c.reverse().whenComplete(() {
        if (mounted) widget.onGone?.call();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
        sizeFactor: _size,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: _opacity, child: widget.child),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 72, 14, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const NextIcon(NextGlyph.video, size: 36, color: NextColors.p4),
            const SizedBox(height: 16),
            Text('没有观看记录', style: NextText.sans(14.5, color: NextColors.p3)),
          ],
        ),
      );
}

class _Failed extends StatelessWidget {
  const _Failed(
      {required this.text, required this.busy, required this.onRetry});
  final String text;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(14, color: NextColors.p3)),
          ),
          const SizedBox(width: 14),
          PillButton(label: '重试', busy: busy, onTap: onRetry),
        ]),
      );
}
