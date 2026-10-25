import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../data/downloads.dart';
import '../data/gui_calls.dart';
import '../settings/controls.dart' show PillButton;
import '../settings/settings_layout.dart';
import '../shell/shell_controller.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/drop_zone.dart';
import '../widgets/icons.dart';
import '../widgets/progress.dart';
import 'download_sheet.dart';
import 'limits_sheet.dart';
import 'new_download.dart';
import 'units.dart';

/// Every download NipaPlay keeps, newest first, each opening to its own
/// sheet. A torrent file dropped anywhere on it starts a new one.
class DownloadList extends StatefulWidget {
  const DownloadList({super.key, this.top = 0});

  /// Room left above for the page's own heading.
  final double top;

  @override
  State<DownloadList> createState() => DownloadListState();
}

/// What the debug driver may do with the list.
abstract interface class DownloadListDebug {
  Future<void> debug(Map<String, String> p);
  Map<String, Object?> debugStatus();
}

class DownloadListState extends State<DownloadList>
    implements DownloadListDebug {
  List<UiDownload>? _list;
  Object? _error;
  Timer? _poll;
  NextShellController? _shell;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell = shell;
    _load();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (TickerMode.valuesOf(context).enabled) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _shell!.services.downloads.list();
      if (mounted) {
        setState(() {
          _list = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _new([String? source]) async {
    final shell = _shell!;
    await newDownload(shell.services,
        source: source,
        onSettings: () =>
            shell.openSettings(section: SettingsSection.downloads));
    await _load();
  }

  Future<void> _open(UiDownload d) async {
    await openDownload(_shell!.services, d.jobId);
    await _load();
  }

  String? _said;

  Future<void> _pause(UiDownload d, bool paused) async {
    setState(() => _said = null);
    try {
      await _shell!.services.downloads.setPaused([d.jobId], paused);
    } catch (e) {
      if (mounted) setState(() => _said = callFailure(e));
    }
    await _load();
  }

  @override
  Future<void> debug(Map<String, String> p) async {
    if (p['new'] case final source?) {
      unawaited(_new(source == 'true' ? null : source));
    }
    if (p['open'] case final i?) unawaited(_open(_list![int.parse(i)]));
    if (p['limits'] == 'true') unawaited(openLimits(_shell!.services));
  }

  @override
  Map<String, Object?> debugStatus() => {
        'downloads': [
          for (final d in _list ?? const <UiDownload>[])
            '${d.title} ${d.state.name} ${((d.progress ?? 0) * 100).floor()}%'
        ],
        'error': _error?.toString(),
      };

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final shell = NextShellScope.of(context);
    final art = {
      for (final t in shell.tasks.value)
        if (t.artwork != null) t.taskId: t.artwork!
    };
    return NextDropZone(
      onDrop: (paths) {
        final torrent =
            paths.where((p) => p.toLowerCase().endsWith('.torrent')).firstOrNull;
        if (torrent != null) _new(torrent);
      },
      builder: (context, over) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: over ? const Color(0x0FFF2E55) : const Color(0x00FF2E55),
        child: ListView(
          key: const PageStorageKey('activity/downloads'),
          padding: EdgeInsets.fromLTRB(
              NextLayout.gutter(context), widget.top, NextLayout.end(context), 64),
          children: [
            _header(list),
            const SizedBox(height: 22),
            if (list == null && _error == null)
              const SizedBox(height: 120, child: Center(child: ThinkingDots()))
            else if (list == null)
              Row(children: [
                Text(callFailure(_error!),
                    style: NextText.sans(14, color: NextColors.p3)),
                const SizedBox(width: 12),
                PillButton(label: '重试', onTap: _load),
              ])
            else if (list.isEmpty)
              _Empty(over: over, onNew: _new)
            else
              Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(children: [
                    for (final d in list)
                      _DownloadRow(
                        download: d,
                        artwork: art[d.jobId],
                        onOpen: () => _open(d),
                        onPause: d.running ? () => _pause(d, true) : null,
                        onResume: d.state == UiDownloadState.paused
                            ? () => _pause(d, false)
                            : null,
                      ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(List<UiDownload>? list) {
    final running =
        list?.where((d) => d.state == UiDownloadState.downloading).toList() ??
            const [];
    final rate = running.fold<int>(0, (n, d) => n + d.down);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Row(children: [
          if (running.isNotEmpty) ...[
            Text('↓', style: NextText.sans(13, color: NextColors.accent2)),
            const SizedBox(width: 5),
            Text(rateText(rate), style: NextText.num(14)),
            const SizedBox(width: 10),
            Text('${running.length} 个在下载',
                style: NextText.sans(13, color: NextColors.p3)),
          ],
          const Spacer(),
          if (_said != null) ...[
            Text(_said!, style: NextText.sans(12.5, color: NextColors.accent2)),
            const SizedBox(width: 12),
          ],
          PillButton(label: '限速', onTap: () => openLimits(_shell!.services)),
          const SizedBox(width: 8),
          PillButton(label: '新建下载', primary: true, onTap: _new),
        ]),
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.download,
    required this.onOpen,
    this.artwork,
    this.onPause,
    this.onResume,
  });
  final UiDownload download;
  final UiArtwork? artwork;
  final VoidCallback onOpen;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final d = download;
    final p = d.progress;
    final line = [
      downloadWord(d),
      if (p != null && d.state != UiDownloadState.finished)
        '${(p * 100).floor()}%',
      if (d.size > 0)
        d.state == UiDownloadState.finished
            ? bytesText(d.size)
            : '${bytesText(d.done)} / ${bytesText(d.size)}',
      if (d.state == UiDownloadState.downloading && d.down > 0)
        '↓ ${rateText(d.down)}',
      if (d.state == UiDownloadState.downloading && d.remaining != null)
        '还要 ${leftText(d.remaining!)}',
    ].join('  ·  ');
    return Pressable(
      onTap: onOpen,
      semanticLabel: d.title,
      pressScale: 0.995,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: hovered ? const Color(0x0DFFFFFF) : const Color(0x05FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: hovered ? NextColors.line2 : NextColors.line),
        ),
        child: Row(children: [
          if (artwork?.backdrop ?? artwork?.poster case final image?)
            Container(
              width: 80,
              height: 45,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(7)),
              clipBehavior: Clip.antiAlias,
              child: NextImage(image, tint: artwork!.tint),
            )
          else
            const TorrentTile(width: 80, height: 45),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(d.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(14, weight: FontWeight.w600)),
                const SizedBox(height: 8),
                ThinBar(
                  progress: p ?? 0,
                  live: d.state == UiDownloadState.downloading,
                  fill: switch (d.state) {
                    UiDownloadState.downloading => null,
                    UiDownloadState.finished => NextColors.mint,
                    UiDownloadState.failed => NextColors.accent,
                    _ => NextColors.p3,
                  },
                  track: const Color(0x1AFFFFFF),
                ),
                const SizedBox(height: 7),
                Text(line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.num(12,
                        color: d.state == UiDownloadState.failed
                            ? NextColors.accent2
                            : NextColors.p3)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          if (onPause != null)
            _Round(glyph: NextGlyph.pause, label: '暂停', onTap: onPause!)
          else if (onResume != null)
            _Round(glyph: NextGlyph.play, label: '继续', onTap: onResume!),
          const SizedBox(width: 8),
          NextIcon(NextGlyph.chevronRight,
              size: 13, color: hovered ? NextColors.p2 : NextColors.p4),
        ]),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.glyph, required this.label, required this.onTap});
  final NextGlyph glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered ? const Color(0x1FFFFFFF) : const Color(0x0DFFFFFF),
            border: Border.all(color: NextColors.line),
          ),
          child: NextIcon(glyph,
              size: 12, color: hovered ? NextColors.paper : NextColors.p2),
        ),
      );
}

/// Nothing downloaded yet: a quiet place to drop a torrent.
class _Empty extends StatelessWidget {
  const _Empty({required this.over, required this.onNew});
  final bool over;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 760,
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: over ? NextColors.accentSoft : const Color(0x05FFFFFF),
            border: Border.all(
                color: over ? const Color(0x59FF2E55) : NextColors.line),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Spacer(),
            const TorrentTile(width: 56, height: 56),
            const SizedBox(height: 18),
            PillButton(label: '新建下载', onTap: onNew),
            const Spacer(),
          ]),
        ),
      );
}
