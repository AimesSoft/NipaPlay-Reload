import 'dart:async';

import 'package:flutter/material.dart' show TextField, InputDecoration;
import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart' show Failure, FailureCode;

import '../../ui_data/ui_data.dart';
import '../data/batch_manage.dart';
import '../data/gui_calls.dart';
import '../data/work_manage.dart' show UiProvider;
import '../settings/controls.dart' show BusyDots, PillButton;
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/progress.dart';
import '../widgets/segmented.dart';
import '../widgets/sheet.dart';

/// What can be done to several works at once.
enum BatchOp {
  refresh('刷新资料'),
  match('匹配'),
  unmatch('解除匹配');

  const BatchOp(this.label);
  final String label;
}

/// Handles for `ext.nipaplay.nextui` (`batch`) in lab profiles.
abstract interface class BatchSheetDebug {
  /// `confirm=true` presses the sheet's main button; the match sheet also
  /// takes `provider=`, `expand=N|none`, `pick=N:K|N:skip`, `query=N:text`
  /// and `back=true`.
  Future<void> debug(Map<String, String> p);
  Map<String, Object?> debugStatus();
}

/// Puts up [op]'s sheet for [works].
Future<void> openBatch(NextBatch batch, BatchOp op, List<UiWork> works) =>
    showNextSheet<void>(
      width: op == BatchOp.match ? 600 : 520,
      (context, close) => switch (op) {
        BatchOp.refresh =>
          RefreshSheet(batch: batch, works: works, onClose: close),
        BatchOp.match => MatchSheet(batch: batch, works: works, onClose: close),
        BatchOp.unmatch =>
          UnmatchSheet(batch: batch, works: works, onClose: close),
      },
    );

String _source(String provider) {
  for (final p in UiProvider.values) {
    if (p.name == provider) return p.label;
  }
  final host = Uri.tryParse(provider)?.host ?? '';
  return host.isEmpty ? provider : host;
}

String _said(Object error) => callFailure(error);

/// Why a picked work cannot be changed: its devices', or that none here
/// holds it in a catalogue.
String _awayWord(UiBatchWork w) => w.away.firstOrNull ?? '不能管理';

// —— 刷新资料 ——

/// The picked works that are matched, each to be read again from its
/// sources; once asked, how each one went.
class RefreshSheet extends StatefulWidget {
  const RefreshSheet(
      {super.key,
      required this.batch,
      required this.works,
      required this.onClose});
  final NextBatch batch;
  final List<UiWork> works;
  final VoidCallback onClose;

  @override
  State<RefreshSheet> createState() => _RefreshSheetState();
}

class _RefreshSheetState extends State<RefreshSheet>
    implements BatchSheetDebug {
  List<UiBatchWork>? _works;
  Object? _error;
  bool _starting = false, _started = false, _checking = false;
  final _jobs = <String, List<UiBatchJob>>{};
  final _states = <String, UiJobState>{};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    widget.batch.read(widget.works).then((works) {
      if (mounted) setState(() => _works = works);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  List<UiBatchWork> get _matched => [
        for (final w in _works ?? const <UiBatchWork>[])
          if (w.matched) w
      ];

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final started = await widget.batch.refresh(_matched);
      if (!mounted) return;
      setState(() {
        _started = true;
        for (final MapEntry(key: id, value: s) in started.entries) {
          if (s.failure case final failure?) {
            _states[id] = UiJobState(UiJobStep.failed, failure: failure);
          } else {
            _jobs[id] = s.jobs;
            _states[id] = const UiJobState(UiJobStep.waiting);
          }
        }
      });
      _poll =
          Timer.periodic(const Duration(milliseconds: 1500), (_) => _check());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// Reads the jobs still going; a work is done when all of its are.
  Future<void> _check() async {
    if (_checking) return;
    final waiting = [
      for (final e in _jobs.entries)
        if (_states[e.key]!.step == UiJobStep.waiting) e
    ];
    if (waiting.isEmpty) {
      _poll?.cancel();
      return;
    }
    _checking = true;
    try {
      for (final MapEntry(key: id, value: jobs) in waiting) {
        final states =
            await Future.wait([for (final j in jobs) widget.batch.job(j)]);
        if (!mounted) return;
        final failed =
            states.where((s) => s.step == UiJobStep.failed).firstOrNull;
        setState(() => _states[id] = failed ??
            (states.every((s) => s.step == UiJobStep.done)
                ? const UiJobState(UiJobStep.done)
                : const UiJobState(UiJobStep.waiting)));
      }
    } catch (e) {
      _poll?.cancel();
      if (mounted) setState(() => _error = e);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final works = _works;
    final matched = _matched;
    return _Frame(
      title: BatchOp.refresh.label,
      count: works == null ? null : matched.length,
      onClose: widget.onClose,
      body: works == null
          ? _Waiting(error: _error)
          : Column(mainAxisSize: MainAxisSize.min, children: [
              for (final w in matched)
                _Row(
                  image: w.work.artwork.poster,
                  tint: w.work.artwork.tint,
                  title: w.work.title,
                  subtitle: Text([
                    ...w.providers.map(_source).toSet(),
                    ...w.away,
                  ].join(' · ')),
                  trailing: _stateMark(_states[w.work.workId]),
                ),
              for (final w in works)
                if (!w.matched)
                  _Row(
                    image: w.work.artwork.poster,
                    tint: w.work.artwork.tint,
                    title: w.work.title,
                    subtitle: Text(w.reachable ? '未匹配' : _awayWord(w)),
                    dim: true,
                  ),
            ]),
      footer: _Footer(
        said: works == null ? null : _error,
        buttons: _started
            ? [PillButton(label: '完成', primary: true, onTap: widget.onClose)]
            : [
                PillButton(label: '取消', onTap: widget.onClose),
                PillButton(
                  label: '刷新',
                  primary: true,
                  busy: _starting,
                  onTap: matched.isEmpty ? null : _start,
                ),
              ],
      ),
    );
  }

  @override
  Future<void> debug(Map<String, String> p) async {
    if (p['confirm'] == 'true') {
      _started ? widget.onClose() : await _start();
    }
  }

  @override
  Map<String, Object?> debugStatus() => {
        'sheet': 'refresh',
        'started': _started,
        'rows': [
          for (final w in _works ?? const <UiBatchWork>[])
            '${w.work.title}: ${w.matched ? _stateWord(_states[w.work.workId]) : w.reachable ? 'unmatched' : _awayWord(w)}'
        ],
        'error': _error == null ? null : _said(_error!),
      };
}

Widget? _stateMark(UiJobState? state) => switch (state?.step) {
      null => null,
      UiJobStep.waiting => const BusyDots(),
      UiJobStep.done =>
        const NextIcon(NextGlyph.check, size: 15, color: NextColors.mint),
      UiJobStep.failed => Text(_said(state!.failure!),
          style: NextText.sans(12, color: NextColors.accent2)),
    };

String _stateWord(UiJobState? state) => switch (state?.step) {
      null => 'ready',
      UiJobStep.waiting => 'waiting',
      UiJobStep.done => 'done',
      UiJobStep.failed => 'failed (${_said(state!.failure!)})',
    };

// —— 匹配 ——

enum _Phase { choosing, previewing, preview, applying, done }

/// A picked work and what it is to be matched to.
class _Pick {
  _Pick(this.work) : query = work.work.title;
  final UiBatchWork work;
  String query;

  /// What the search found; null while searching.
  List<UiBatchCandidate>? found;
  Object? error;

  /// Index into [found]; null skips the work.
  int? chosen;
  int _searches = 0;

  UiBatchCandidate? get candidate => chosen == null ? null : found![chosen!];
}

/// Each picked work with the work a provider knows by its name (the first
/// found, or another, or none), then what matching them touches, then
/// the change.
class MatchSheet extends StatefulWidget {
  const MatchSheet(
      {super.key,
      required this.batch,
      required this.works,
      required this.onClose});
  final NextBatch batch;
  final List<UiWork> works;
  final VoidCallback onClose;

  @override
  State<MatchSheet> createState() => _MatchSheetState();
}

class _MatchSheetState extends State<MatchSheet> implements BatchSheetDebug {
  UiProvider _provider = UiProvider.dandanplay;
  List<_Pick>? _picks;

  /// Picked works this device's catalogue does not hold.
  List<UiBatchWork> _away = const [];
  Object? _error;
  int? _open;
  _Phase _phase = _Phase.choosing;
  UiAssociationPreview? _preview;

  @override
  void initState() {
    super.initState();
    widget.batch.read(widget.works).then((works) {
      if (!mounted) return;
      setState(() {
        _picks = [
          for (final w in works)
            if (w.reachable) _Pick(w)
        ];
        _away = [
          for (final w in works)
            if (!w.reachable) w
        ];
      });
      _searchAll();
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  /// Searches every work, three at a time.
  Future<void> _searchAll() async {
    final queue = [..._picks!];
    Future<void> next() async {
      while (queue.isNotEmpty) {
        await _search(queue.removeAt(0));
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) next()]);
  }

  Future<void> _search(_Pick pick) async {
    if (!mounted) return;
    final n = ++pick._searches;
    setState(() {
      pick.found = null;
      pick.error = null;
      pick.chosen = null;
    });
    try {
      final found = await widget.batch.search(_provider, pick.query);
      if (!mounted || n != pick._searches) return;
      setState(() {
        pick.found = found;
        pick.chosen = pick.work.matched || found.isEmpty ? null : 0;
      });
    } catch (e) {
      if (!mounted || n != pick._searches) return;
      setState(() {
        pick.found = const [];
        pick.error = e;
      });
    }
  }

  void _setProvider(UiProvider provider) {
    if (provider == _provider) return;
    setState(() {
      _provider = provider;
      _open = null;
    });
    _searchAll();
  }

  List<(UiBatchWork, UiBatchCandidate)> get _pairs => [
        for (final p in _picks ?? const <_Pick>[])
          if (p.candidate case final c?) (p.work, c)
      ];

  Future<void> _toPreview() async {
    setState(() {
      _phase = _Phase.previewing;
      _error = null;
      _open = null;
    });
    try {
      final preview = await widget.batch.previewMatch(_pairs);
      if (mounted) {
        setState(() {
          _preview = preview;
          _phase = _Phase.preview;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _phase = _Phase.choosing;
        });
      }
    }
  }

  Future<void> _apply() async {
    setState(() {
      _phase = _Phase.applying;
      _error = null;
    });
    final applied = await _carryOut(widget.batch, _preview!);
    if (!mounted) return;
    setState(() {
      _preview = applied.$1;
      _error = applied.$2;
      _phase = applied.$2 == null ? _Phase.done : _Phase.preview;
    });
  }

  @override
  Widget build(BuildContext context) {
    final picks = _picks;
    final preview = _preview;
    final showing = _phase == _Phase.choosing || _phase == _Phase.previewing
        ? null
        : preview;
    final chosen = {
      for (final (w, c) in _pairs) w.work.workId: c,
    };
    return _Frame(
      title: BatchOp.match.label,
      count: picks == null ? null : _pairs.length,
      onClose: widget.onClose,
      trailing: _phase == _Phase.choosing && picks != null
          ? Segmented<UiProvider>(
              value: _provider,
              options: [
                for (final p in UiProvider.values)
                  (
                    p,
                    p.label,
                    (c) => Text(p.label, style: NextText.sans(12, color: c))
                  ),
              ],
              onChanged: _setProvider,
            )
          : null,
      body: picks == null
          ? _Waiting(error: _error)
          : showing != null
              ? _PreviewView(
                  preview: showing,
                  done: _phase == _Phase.done,
                  trailing: (g) => switch (chosen[g.id]) {
                    final c? => Row(mainAxisSize: MainAxisSize.min, children: [
                        _Fit(fitted: g.fitted!, missed: g.missed!),
                        const SizedBox(width: 12),
                        _Poster(c.image, small: true),
                      ]),
                    null => null,
                  },
                )
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final (i, pick) in picks.indexed) ...[
                    _row(i, pick),
                    if (_open == i)
                      _Choices(
                        pick: pick,
                        onPick: (k) => setState(() {
                          pick.chosen = k;
                          _open = null;
                        }),
                        onQuery: (text) {
                          pick.query = text;
                          _search(pick);
                        },
                      ),
                  ],
                  for (final w in _away)
                    _Row(
                      image: w.work.artwork.poster,
                      tint: w.work.artwork.tint,
                      title: w.work.title,
                      subtitle: Text(_awayWord(w)),
                      dim: true,
                    ),
                ]),
      footer: _Footer(
        said: picks == null ? null : _error,
        buttons: switch (_phase) {
          _Phase.choosing || _Phase.previewing => [
              PillButton(label: '取消', onTap: widget.onClose),
              PillButton(
                label: '预览',
                primary: true,
                busy: _phase == _Phase.previewing,
                onTap: _pairs.isEmpty ? null : _toPreview,
              ),
            ],
          _Phase.preview || _Phase.applying => [
              PillButton(
                label: '返回',
                onTap: _phase == _Phase.applying
                    ? null
                    : () => setState(() {
                          _phase = _Phase.choosing;
                          _error = null;
                        }),
              ),
              PillButton(
                label: '匹配',
                primary: true,
                busy: _phase == _Phase.applying,
                onTap: showing!.empty ? null : _apply,
              ),
            ],
          _Phase.done => [
              PillButton(label: '完成', primary: true, onTap: widget.onClose)
            ],
        },
      ),
    );
  }

  Widget _row(int i, _Pick pick) {
    final found = pick.found;
    final c = pick.candidate;
    return _Row(
      image: pick.work.work.artwork.poster,
      tint: pick.work.work.artwork.tint,
      title: pick.work.work.title,
      open: _open == i,
      onTap: found == null && _open != i
          ? null
          : () => setState(() => _open = _open == i ? null : i),
      subtitle: switch ((found, c)) {
        (null, _) => const Align(
            alignment: Alignment.centerLeft, child: ThinkingDots(size: 4)),
        (_, final to?) => Row(children: [
            const NextIcon(NextGlyph.chevronRight,
                size: 11, color: NextColors.p3),
            const SizedBox(width: 4),
            Flexible(
              child: Text('${to.title}${to.year == null ? '' : '  ${to.year}'}',
                  style: NextText.sans(12, color: NextColors.p2)),
            ),
          ]),
        _ when pick.error != null => Text(_said(pick.error!),
            style: NextText.sans(12, color: NextColors.accent2)),
        _ when pick.work.matched => const Text('已匹配'),
        ([], _) => const Text('没有结果'),
        _ => const Text('跳过'),
      },
      trailing: c == null ? null : _Poster(c.image, small: true),
    );
  }

  @override
  Future<void> debug(Map<String, String> p) async {
    final picks = _picks;
    if (p['provider'] case final name?) {
      _setProvider(UiProvider.values.byName(name));
    }
    if (p['expand'] case final n?) {
      setState(() => _open = n == 'none' ? null : int.parse(n));
    }
    if (p['pick'] case final pick?) {
      final [row, k] = pick.split(':');
      setState(() =>
          picks![int.parse(row)].chosen = k == 'skip' ? null : int.parse(k));
    }
    if (p['query'] case final query?) {
      final at = query.indexOf(':');
      final pick = picks![int.parse(query.substring(0, at))];
      pick.query = query.substring(at + 1);
      await _search(pick);
    }
    if (p['back'] == 'true') setState(() => _phase = _Phase.choosing);
    if (p['confirm'] == 'true') {
      switch (_phase) {
        case _Phase.choosing:
          await _toPreview();
        case _Phase.preview:
          await _apply();
        case _Phase.done:
          widget.onClose();
        case _Phase.previewing || _Phase.applying:
          break;
      }
    }
  }

  @override
  Map<String, Object?> debugStatus() => {
        'sheet': 'match',
        'phase': _phase.name,
        'provider': _provider.name,
        'rows': [
          for (final p in _picks ?? const <_Pick>[])
            '${p.work.work.title} → ${p.found == null ? '…' : p.candidate?.title ?? (p.error == null ? 'skip' : _said(p.error!))}'
                ' (${p.found?.length ?? 0} found)',
          for (final w in _away) '${w.work.title}: ${_awayWord(w)}',
        ],
        if (_preview case final preview?) 'preview': _previewStatus(preview),
        'error': _error == null ? null : _said(_error!),
      };
}

// —— 解除匹配 ——

/// The picked works that are matched, what letting go of their matches
/// touches, then the change.
class UnmatchSheet extends StatefulWidget {
  const UnmatchSheet(
      {super.key,
      required this.batch,
      required this.works,
      required this.onClose});
  final NextBatch batch;
  final List<UiWork> works;
  final VoidCallback onClose;

  @override
  State<UnmatchSheet> createState() => _UnmatchSheetState();
}

class _UnmatchSheetState extends State<UnmatchSheet>
    implements BatchSheetDebug {
  /// Read, with nothing matched among them.
  bool _none = false;

  /// Picked works no device that has them can change now.
  List<UiBatchWork> _away = const [];
  UiAssociationPreview? _preview;
  Object? _error;
  bool _applying = false, _done = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final read = await widget.batch.read(widget.works);
      final works = [
        for (final w in read)
          if (w.matched) w
      ];
      if (mounted) {
        setState(() => _away = [
              for (final w in read)
                if (!w.reachable) w
            ]);
      }
      if (works.isEmpty) {
        if (mounted) setState(() => _none = true);
        return;
      }
      final preview = await widget.batch.previewUnmatch(works);
      if (mounted) setState(() => _preview = preview);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _apply() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    final applied = await _carryOut(widget.batch, _preview!);
    if (!mounted) return;
    setState(() {
      _applying = false;
      _preview = applied.$1;
      _error = applied.$2;
      _done = applied.$2 == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return _Frame(
      title: BatchOp.unmatch.label,
      count: preview?.works.length,
      onClose: widget.onClose,
      body: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_none)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('没有已匹配的作品',
                textAlign: TextAlign.center,
                style: NextText.sans(13.5, color: NextColors.p3)),
          )
        else if (preview == null)
          _Waiting(error: _error)
        else
          _PreviewView(
            preview: preview,
            done: _done,
            trailing: (g) => g.providers.isEmpty
                ? null
                : Text(g.providers.map(_source).toSet().join(' · '),
                    style: NextText.sans(12, color: NextColors.p3)),
          ),
        for (final w in _away)
          _Row(
            image: w.work.artwork.poster,
            tint: w.work.artwork.tint,
            title: w.work.title,
            subtitle: Text(_awayWord(w)),
            dim: true,
          ),
      ]),
      footer: _Footer(
        said: preview == null ? null : _error,
        buttons: _done || _none || preview == null
            ? [
                PillButton(
                    label: _done ? '完成' : '关闭',
                    primary: _done,
                    onTap: widget.onClose)
              ]
            : [
                PillButton(label: '取消', onTap: widget.onClose),
                PillButton(
                  label: BatchOp.unmatch.label,
                  danger: true,
                  busy: _applying,
                  onTap: _apply,
                ),
              ],
      ),
    );
  }

  @override
  Future<void> debug(Map<String, String> p) async {
    if (p['confirm'] == 'true') {
      _done || _none ? widget.onClose() : await _apply();
    }
  }

  @override
  Map<String, Object?> debugStatus() => {
        'sheet': 'unmatch',
        'none': _none,
        'done': _done,
        'away': [for (final w in _away) '${w.work.title}: ${_awayWord(w)}'],
        if (_preview case final preview?) 'preview': _previewStatus(preview),
        'error': _error == null ? null : _said(_error!),
      };
}

/// Applies [preview]; when what it touches changed meanwhile, the preview
/// read again with the conflict to say, for the person to look again.
Future<(UiAssociationPreview, Object?)> _carryOut(
    NextBatch batch, UiAssociationPreview preview) async {
  try {
    await batch.apply(preview);
    return (preview, null);
  } catch (e) {
    if (e is! Failure || e.code != FailureCode.conflict) return (preview, e);
    try {
      return (await batch.again(preview), e);
    } catch (again) {
      return (preview, again);
    }
  }
}

Map<String, Object?> _previewStatus(UiAssociationPreview p) => {
      'episodes': p.episodes,
      'files': p.files,
      'progress': p.progress,
      'keeps': p.keeps,
      'empty': p.empty,
      'groups': [
        for (final g in p.groups)
          '${g.title}${g.work == null ? ' (other${g.device == null ? '' : ' on ${g.device}'})' : ''}: ${_counts(g)}'
              '${g.fitted == null ? '' : ' fits ${g.fitted}/${g.fitted! + g.missed!}'}'
              '${g.providers.isEmpty ? '' : ' [${g.providers.join(',')}]'}'
      ],
    };

String _counts(UiAssociationGroup g) => [
      if (g.episodes > 0) '${g.episodes} 集',
      if (g.files > 0) '${g.files} 个文件',
      if (g.progress > 0) '${g.progress} 条进度',
    ].join(' · ');

// —— Pieces ——

/// What a change of matches touches: the totals, each picked work, and
/// others it reaches. Once done, each row ticked.
class _PreviewView extends StatelessWidget {
  const _PreviewView(
      {required this.preview, required this.done, required this.trailing});
  final UiAssociationPreview preview;
  final bool done;
  final Widget? Function(UiAssociationGroup group) trailing;

  @override
  Widget build(BuildContext context) {
    final others = [
      for (final g in preview.groups)
        if (g.work == null) g
    ];
    Widget row(UiAssociationGroup g) {
      final counts = [
        _counts(g),
        if (g.device case final device?) device,
        ...g.away,
      ].where((t) => t.isNotEmpty).join(' · ');
      return _Row(
        image: g.work?.artwork.poster,
        tint: g.work?.artwork.tint,
        title: g.title ?? '',
        subtitle: counts.isEmpty ? null : Text(counts),
        trailing: done
            ? const NextIcon(NextGlyph.check, size: 15, color: NextColors.mint)
            : trailing(g),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              for (final (n, label) in [
                (preview.episodes, '集'),
                (preview.files, '个文件'),
                (preview.progress, '条进度'),
              ]) ...[
                Text('$n', style: NextText.num(22, weight: FontWeight.w600)),
                const SizedBox(width: 5),
                Text(label, style: NextText.sans(12.5, color: NextColors.p3)),
                const SizedBox(width: 22),
              ],
            ],
          ),
        ),
        for (final g in preview.groups)
          if (g.work != null) row(g),
        if (others.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
            child: Text('其他作品',
                style: NextText.sans(12.5,
                    weight: FontWeight.w500, color: NextColors.p3)),
          ),
          for (final g in others) row(g),
        ],
      ],
    );
  }
}

/// Under a work being matched: another name to search by, what was
/// found, and skipping it.
class _Choices extends StatelessWidget {
  const _Choices(
      {required this.pick, required this.onPick, required this.onQuery});
  final _Pick pick;
  final ValueChanged<int?> onPick;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(56, 2, 0, 10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NextColors.line),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _QueryField(initial: pick.query, onSubmit: onQuery),
          const SizedBox(height: 6),
          if (pick.found == null)
            const SizedBox(height: 64, child: Center(child: ThinkingDots())),
          for (final (k, c) in (pick.found ?? const []).indexed)
            _Row(
              image: c.image,
              title: c.title,
              subtitle: Text([
                if (c.originalTitle case final o? when o != c.title) o,
                if (c.year case final y?) '$y',
                if (c.inLibrary) '已在媒体库',
              ].join(' · ')),
              trailing: pick.chosen == k ? const _Tick() : null,
              onTap: () => onPick(k),
            ),
          _Row(
            title: '跳过',
            poster: false,
            trailing: pick.chosen == null ? const _Tick() : null,
            onTap: () => onPick(null),
          ),
        ]),
      );
}

class _QueryField extends StatefulWidget {
  const _QueryField({required this.initial, required this.onSubmit});
  final String initial;
  final ValueChanged<String> onSubmit;

  @override
  State<_QueryField> createState() => _QueryFieldState();
}

class _QueryFieldState extends State<_QueryField> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NextColors.line2),
        ),
        child: Row(children: [
          const NextIcon(NextGlyph.search, size: 14, color: NextColors.p3),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _text,
              cursorColor: NextColors.accent,
              cursorWidth: 1.5,
              style: NextText.sans(13),
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) widget.onSubmit(text.trim());
              },
              decoration: InputDecoration.collapsed(
                hintText: '搜索',
                hintStyle: NextText.sans(13, color: NextColors.p4),
              ),
            ),
          ),
        ]),
      );
}

/// How many of a work's episodes the candidate fits, and how many none
/// of its does.
class _Fit extends StatelessWidget {
  const _Fit({required this.fitted, required this.missed});
  final int fitted, missed;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        const NextIcon(NextGlyph.check, size: 12, color: NextColors.mint),
        const SizedBox(width: 3),
        Text('$fitted', style: NextText.num(12.5, color: NextColors.p2)),
        if (missed > 0) ...[
          const SizedBox(width: 9),
          const NextIcon(NextGlyph.close, size: 11, color: NextColors.accent2),
          const SizedBox(width: 3),
          Text('$missed', style: NextText.num(12.5, color: NextColors.p2)),
        ],
      ]);
}

class _Tick extends StatelessWidget {
  const _Tick();

  @override
  Widget build(BuildContext context) =>
      const NextIcon(NextGlyph.check, size: 15, color: NextColors.accent2);
}

/// A sheet of these: its title (and how many), a control beside it, the
/// rows, and what to do.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    required this.onClose,
    required this.body,
    required this.footer,
    this.count,
    this.trailing,
  });
  final String title;
  final int? count;
  final Widget? trailing;
  final VoidCallback onClose;
  final Widget body;
  final Widget footer;

  @override
  Widget build(BuildContext context) => SheetSurface(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(children: [
                Text(title, style: NextText.sans(17, weight: FontWeight.w600)),
                if (count != null) ...[
                  const SizedBox(width: 10),
                  Text('$count', style: NextText.num(15, color: NextColors.p3)),
                ],
                const Spacer(),
                if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
                NextIconButton(
                    glyph: NextGlyph.close, label: '关闭', onTap: onClose),
              ]),
            ),
            const SizedBox(height: 14),
            Flexible(child: SingleChildScrollView(child: body)),
            const SizedBox(height: 14),
            footer,
          ],
        ),
      );
}

/// What went wrong, and the buttons.
class _Footer extends StatelessWidget {
  const _Footer({required this.buttons, this.said});
  final List<Widget> buttons;
  final Object? said;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Row(children: [
          Expanded(
            child: said != null
                ? Text(_said(said!),
                    style: NextText.sans(12.5, color: NextColors.accent2))
                : const SizedBox.shrink(),
          ),
          for (final (i, b) in buttons.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            b,
          ],
        ]),
      );
}

/// Reading what the sheet needs, or why it could not.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 120,
        child: Center(
          child: error == null
              ? const ThinkingDots()
              : Text(_said(error!),
                  style: NextText.sans(13, color: NextColors.accent2)),
        ),
      );
}

class _Poster extends StatelessWidget {
  const _Poster(this.image, {this.tint, this.small = false});
  final String? image;
  final int? tint;
  final bool small;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(small ? 5 : 6),
        child: SizedBox(
          width: small ? 28 : 34,
          height: small ? 42 : 51,
          child: NextImage(image, shape: ArtShape.poster, tint: tint),
        ),
      );
}

/// A work in a sheet: its poster, name and a line under it, and what is
/// at its end.
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.image,
    this.tint,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.open = false,
    this.dim = false,
    this.poster = true,
  });
  final String title;
  final bool poster;
  final String? image;
  final int? tint;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool open;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    Widget row(bool hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          decoration: BoxDecoration(
            color: open || hovered
                ? const Color(0x0DFFFFFF)
                : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Opacity(
            opacity: dim ? 0.45 : 1,
            child: Row(children: [
              if (poster) ...[
                _Poster(image, tint: tint),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NextText.sans(13.5, weight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      DefaultTextStyle(
                        style: NextText.sans(12, color: NextColors.p3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ]),
          ),
        );
    if (onTap == null) return row(false);
    return Pressable(
      onTap: onTap,
      semanticLabel: title,
      pressScale: 0.99,
      builder: (context, hovered) => row(hovered),
    );
  }
}
