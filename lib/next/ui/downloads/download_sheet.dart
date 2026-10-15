import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart' show JsonMap;

import '../data/downloads.dart';
import '../data/gui_calls.dart';
import '../data/services.dart';
import '../settings/controls.dart' show PillButton, StateDot;
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/progress.dart';
import '../widgets/sheet.dart';
import 'units.dart';

/// A download's own sheet: how far, how fast, from how many, and each of
/// its files to keep or leave out; pause, go on, delete.
Future<void> openDownload(NextUiServices services, String jobId) =>
    showNextSheet<void>(
      width: 660,
      (context, close) =>
          DownloadSheet(services: services, jobId: jobId, onClose: close),
    );

/// What the debug driver may do with an open download sheet.
abstract interface class DownloadSheetDebug {
  Future<void> debug(Map<String, String> p);
  Map<String, Object?> debugStatus();
}

class DownloadSheet extends StatefulWidget {
  const DownloadSheet(
      {super.key,
      required this.services,
      required this.jobId,
      required this.onClose});
  final NextUiServices services;
  final String jobId;
  final VoidCallback onClose;

  @override
  State<DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<DownloadSheet>
    implements DownloadSheetDebug {
  NextDownloads get _downloads => widget.services.downloads;
  UiDownload? _d;
  Object? _readError;
  Timer? _poll;

  /// The person's choice of files, until the downloader has it.
  Set<int>? _chosen;
  Timer? _send;
  String? _said;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _read();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _read());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _send?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    try {
      final d = await _downloads.read(widget.jobId);
      if (mounted) {
        setState(() {
          _d = d;
          _readError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _readError = e);
    }
  }

  Set<int> get _included =>
      _chosen ??
      {
        for (final f in _d?.files ?? const <UiDownloadFile>[])
          if (f.included) f.index
      };

  void _choose(Set<int> next) {
    setState(() {
      _chosen = next;
      _said = null;
    });
    _send?.cancel();
    _send = Timer(const Duration(milliseconds: 700), () async {
      try {
        await _downloads.select(widget.jobId, next.toList()..sort());
        await _read();
        if (mounted) setState(() => _chosen = null);
      } catch (e) {
        if (mounted) {
          setState(() {
            _chosen = null;
            _said = callFailure(e);
          });
        }
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      await action();
      await _read();
    } catch (e) {
      if (mounted) setState(() => _said = callFailure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause(bool paused) =>
      _run(() => _downloads.setPaused([widget.jobId], paused));

  Future<void> _delete() async {
    final d = _d;
    final choice = await chooseSheet(
      title: '删除下载',
      choices: [
        const SheetChoice('只移除任务', detail: '文件留在原处'),
        SheetChoice('连同文件删除',
            detail: d == null || d.done == 0 ? null : bytesText(d.done),
            danger: true),
      ],
    );
    if (choice == null) return;
    await _remove(files: choice == 1);
  }

  /// With [files], the capability's own question (the files) comes up;
  /// what its option starts is a deletion task, not this download.
  Future<void> _remove({required bool files}) async {
    final calls = widget.services.calls;
    JsonMap? done;
    await _run(() async {
      try {
        done = await withDecisions(
            calls, () => _downloads.remove(widget.jobId, files: files));
      } on DeletionNeeded catch (asked) {
        final items = asked.items;
        final i = await chooseSheet(
          title: asked.prompt,
          detail: items.isEmpty
              ? null
              : (items.length > 4 ? [...items.take(3), '…'] : items)
                  .join('\n'),
          choices: [
            for (final o in asked.options)
              SheetChoice(o.label, detail: o.detail, danger: true)
          ],
        );
        if (i == null) return;
        done = await withDecisions(calls, () => calls.choose(asked.options[i]));
      }
    });
    if (done != null && _said == null) widget.onClose();
  }

  Future<void> _play(UiDownloadFile f) =>
      _run(() => _downloads.play(widget.jobId, f.index));

  // —— debug ——

  @override
  Future<void> debug(Map<String, String> p) async {
    final d = _d;
    if (d == null) return;
    switch (p['files']) {
      case 'all':
        _choose({for (final f in d.files) f.index});
      case 'video':
        _choose({
          for (final f in d.files)
            if (f.video) f.index
        });
      case 'none':
        _choose({});
    }
    if (p['toggle'] case final i?) {
      final index = int.parse(i);
      final next = {..._included};
      if (!next.remove(index)) next.add(index);
      _choose(next);
    }
    if (p['pause'] case final v?) unawaited(_pause(v == 'true'));
    switch (p['delete']) {
      case 'ask':
        unawaited(_delete());
      case 'task':
        unawaited(_remove(files: false));
      case 'files':
        unawaited(_remove(files: true));
      // As if its option were chosen at once.
      case 'request':
        unawaited(_run(() async {
          try {
            await _downloads.remove(widget.jobId, files: true);
          } on DeletionNeeded catch (asked) {
            await widget.services.calls.choose(asked.options.first);
          }
        }).then((_) {
          if (mounted && _said == null) widget.onClose();
        }));
    }
  }

  @override
  Map<String, Object?> debugStatus() => {
        'download': _d?.title,
        'state': _d?.state.name,
        'files': _d?.files.length,
        'included': _included.length,
        'said': _said,
      };

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return SheetSurface(
      padding: const EdgeInsets.fromLTRB(28, 24, 20, 18),
      child: d == null
          ? SizedBox(
              height: 160,
              child: Center(
                child: _readError == null
                    ? const ThinkingDots()
                    : Text(callFailure(_readError!),
                        style: NextText.sans(13, color: NextColors.p3)),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _head(d),
                const SizedBox(height: 20),
                _numbers(d),
                const SizedBox(height: 14),
                _bar(d),
                const SizedBox(height: 10),
                _facts(d),
                const SizedBox(height: 18),
                _controls(d),
                if (d.files.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(height: 1, color: NextColors.line),
                  const SizedBox(height: 8),
                  Flexible(child: _files(d)),
                ],
              ],
            ),
    );
  }

  Widget _head(UiDownload d) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 12),
              child: Text(d.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(17,
                      weight: FontWeight.w600, height: 1.35)),
            ),
          ),
          NextIconButton(
              glyph: NextGlyph.close, label: '关闭', onTap: widget.onClose),
        ],
      );

  Widget _numbers(UiDownload d) {
    final failed = d.state == UiDownloadState.failed;
    final p = d.progress;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(p == null ? '—' : '${(p * 100).floor()}',
          style: NextText.num(40,
              weight: FontWeight.w300,
              color: failed ? NextColors.p3 : NextColors.paper)),
      Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 2),
        child: Text('%', style: NextText.num(16, color: NextColors.p3)),
      ),
      const SizedBox(width: 16),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          StateDot(switch (d.state) {
            UiDownloadState.downloading => d.stalledFor != null
                ? NextColors.amber
                : NextColors.mint,
            UiDownloadState.finished => NextColors.mint,
            UiDownloadState.failed => NextColors.accent,
            _ => NextColors.p4,
          }, glow: d.running || failed),
          const SizedBox(width: 8),
          Text(downloadWord(d),
              style: NextText.sans(13,
                  color: failed ? NextColors.accent2 : NextColors.p2)),
        ]),
      ),
      const Spacer(),
      if (d.live && d.running)
        Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 8),
          child: Row(children: [
            _Rate(arrow: '↓', bytes: d.down),
            const SizedBox(width: 18),
            _Rate(arrow: '↑', bytes: d.up),
            if (d.peers != null) ...[
              const SizedBox(width: 18),
              _Peers(peers: d.peers!, seen: d.seenPeers),
            ],
          ]),
        )
      else if (d.live && d.state == UiDownloadState.finished && d.up > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 8),
          child: _Rate(arrow: '↑', bytes: d.up),
        ),
    ]);
  }

  Widget _bar(UiDownload d) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ThinBar(
          progress: d.progress ?? 0,
          height: 4,
          live: d.state == UiDownloadState.downloading,
          fill: switch (d.state) {
            UiDownloadState.downloading => null,
            UiDownloadState.finished => NextColors.mint,
            UiDownloadState.failed => NextColors.accent,
            _ => NextColors.p3,
          },
          track: const Color(0x1AFFFFFF),
        ),
      );

  Widget _facts(UiDownload d) {
    final parts = [
      if (d.size > 0)
        d.done >= d.size
            ? bytesText(d.size)
            : '${bytesText(d.done)} / ${bytesText(d.size)}',
      if (d.state == UiDownloadState.downloading && d.remaining != null)
        '还要 ${leftText(d.remaining!)}',
      if (d.free != null && d.state != UiDownloadState.finished)
        '剩余空间 ${bytesText(d.free!)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(children: [
        Expanded(
          child: Text(parts.join('  ·  '),
              style: NextText.num(12.5, color: NextColors.p3)),
        ),
        if (d.folder != null)
          Flexible(
            child: Text(_shortPath(d.folder!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: NextText.sans(12, color: NextColors.p4)),
          ),
      ]),
    );
  }

  static String _shortPath(String path) {
    final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty);
    return parts.length <= 2
        ? path
        : '… / ${parts.skip(parts.length - 2).join(' / ')}';
  }

  Widget _controls(UiDownload d) {
    final files = d.files;
    final included = _included;
    final videos = {
      for (final f in files)
        if (f.video) f.index
    };
    final all = files.isNotEmpty && included.length == files.length;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(children: [
        if (d.state == UiDownloadState.paused)
          PillButton(
              label: '继续', primary: true, busy: _busy, onTap: () => _pause(false))
        else if (d.running)
          PillButton(label: '暂停', busy: _busy, onTap: () => _pause(true)),
        if (d.state == UiDownloadState.paused || d.running)
          const SizedBox(width: 8),
        PillButton(label: '删除', danger: true, onTap: _busy ? null : _delete),
        if (_said != null) ...[
          const SizedBox(width: 14),
          Flexible(
            child: Text(_said!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(12.5, color: NextColors.accent2)),
          ),
        ],
        const Spacer(),
        if (files.length > 1 && d.live) ...[
          _TextChoice(
              label: '只要视频',
              on: included.length == videos.length &&
                  included.containsAll(videos) &&
                  !all,
              onTap: videos.isEmpty ? null : () => _choose(videos)),
          const SizedBox(width: 6),
          _TextChoice(
              label: '全部',
              on: all,
              onTap: () => _choose({for (final f in files) f.index})),
        ],
      ]),
    );
  }

  Widget _files(UiDownload d) {
    final included = _included;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(right: 6),
      children: [
        for (final f in d.files)
          DownloadFileRow(
            file: f,
            included: included.contains(f.index),
            onToggle: d.live
                ? () {
                    final next = {...included};
                    if (!next.remove(f.index)) next.add(f.index);
                    _choose(next);
                  }
                : null,
            onPlay: f.playable || f.streamable ? () => _play(f) : null,
          ),
      ],
    );
  }
}

class _Rate extends StatelessWidget {
  const _Rate({required this.arrow, required this.bytes});
  final String arrow;
  final int bytes;

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(arrow,
            style: NextText.sans(12,
                color: bytes > 0 ? NextColors.accent2 : NextColors.p4)),
        const SizedBox(width: 4),
        Text(rateText(bytes),
            style: NextText.num(13,
                color: bytes > 0 ? NextColors.paper : NextColors.p3)),
      ]);
}

/// Connected peers as dots, then the number (of all heard of).
class _Peers extends StatelessWidget {
  const _Peers({required this.peers, this.seen});
  final int peers;
  final int? seen;

  @override
  Widget build(BuildContext context) => Row(children: [
        CustomPaint(size: const Size(14, 12), painter: _PeersGlyph(peers > 0)),
        const SizedBox(width: 6),
        Text('$peers',
            style: NextText.num(13,
                color: peers > 0 ? NextColors.paper : NextColors.p3)),
        if (seen != null && seen! > peers)
          Text(' / $seen', style: NextText.num(12, color: NextColors.p4)),
      ]);
}

class _PeersGlyph extends CustomPainter {
  _PeersGlyph(this.on);
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = on ? NextColors.mint : NextColors.p4;
    final line = Paint()
      ..color = (on ? NextColors.mint : NextColors.p4).withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final a = Offset(2, size.height - 2),
        b = Offset(size.width / 2, 2),
        c = Offset(size.width - 2, size.height - 3);
    canvas
      ..drawLine(a, b, line)
      ..drawLine(b, c, line)
      ..drawLine(a, c, line)
      ..drawCircle(a, 2, p)
      ..drawCircle(b, 2, p)
      ..drawCircle(c, 2, p);
  }

  @override
  bool shouldRepaint(_PeersGlyph old) => old.on != on;
}

class _TextChoice extends StatelessWidget {
  const _TextChoice({required this.label, required this.on, this.onTap});
  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: on ? null : onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on
                ? NextColors.accentSoft
                : hovered
                    ? const Color(0x14FFFFFF)
                    : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(label,
              style: NextText.sans(12,
                  color: on
                      ? NextColors.accent2
                      : onTap == null
                          ? NextColors.p4
                          : NextColors.p2)),
        ),
      );
}
