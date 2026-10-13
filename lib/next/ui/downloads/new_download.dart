import 'dart:async';

import 'package:flutter/material.dart' show InputBorder, InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart';

import '../data/downloads.dart';
import '../data/gui_calls.dart';
import '../data/services.dart';
import '../settings/controls.dart' show PillButton;
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/drop_zone.dart';
import '../widgets/icons.dart';
import '../widgets/progress.dart';
import '../widgets/sheet.dart';
import 'download_sheet.dart';
import 'units.dart';

/// A new download from a magnet, a torrent's address or a .torrent file:
/// its files to choose (for a magnet), where it goes, then its own sheet.
/// [onSettings] opens the 下载 settings when the downloader is off.
Future<void> newDownload(NextUiServices services,
    {String? source, VoidCallback? onSettings}) async {
  final jobId = await showNextSheet<String>(
    width: 600,
    (context, close) => NewDownloadSheet(
        services: services,
        source: source,
        onDone: close,
        onSettings: onSettings == null
            ? null
            : () {
                close();
                onSettings();
              }),
  );
  if (jobId != null) await openDownload(services, jobId);
}

/// What the debug driver may do with the new download sheet.
abstract interface class NewDownloadDebug {
  Future<void> debug(Map<String, String> p);
  Map<String, Object?> debugStatus();
}

class NewDownloadSheet extends StatefulWidget {
  const NewDownloadSheet({
    super.key,
    required this.services,
    required this.onDone,
    this.source,
    this.onSettings,
  });
  final NextUiServices services;
  final ValueChanged<String?> onDone;
  final String? source;
  final VoidCallback? onSettings;

  @override
  State<NewDownloadSheet> createState() => _NewDownloadSheetState();
}

enum _Kind { none, magnet, link, file, unknown }

class _NewDownloadSheetState extends State<NewDownloadSheet>
    implements NewDownloadDebug {
  NextDownloads get _downloads => widget.services.downloads;
  late final _text = TextEditingController(text: widget.source ?? '');
  final _focus = FocusNode(debugLabel: 'download.source');
  UiDownloadPlaces? _places;
  String? _folder;
  bool _folders = false;
  UiTorrentPreview? _preview;
  bool _previewing = false;
  Set<int> _chosen = {};
  Timer? _wait;
  bool _adding = false;
  String? _said;
  bool _off = false;
  bool _over = false;

  @override
  void initState() {
    super.initState();
    _downloads.places().then((p) {
      if (mounted) setState(() => _places = p);
    }, onError: (Object _) {});
    _text.addListener(_changed);
    if (widget.source != null) _changed();
  }

  @override
  void dispose() {
    _wait?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _source => _text.text.trim();

  _Kind get _kind {
    final s = _source;
    if (s.isEmpty) return _Kind.none;
    if (s.startsWith('magnet:?')) return _Kind.magnet;
    final uri = Uri.tryParse(s);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return _Kind.link;
    }
    if (s.startsWith('/') && s.toLowerCase().endsWith('.torrent')) {
      return _Kind.file;
    }
    return _Kind.unknown;
  }

  String? _lastPreviewed;

  void _changed() {
    if (_source == _lastPreviewed) return;
    _wait?.cancel();
    setState(() {
      _said = null;
      _off = false;
      if (_kind != _Kind.magnet) {
        _preview = null;
        _previewing = false;
      }
    });
    if (_kind != _Kind.magnet) return;
    _wait = Timer(const Duration(milliseconds: 500), _loadPreview);
  }

  Future<void> _loadPreview() async {
    final source = _source;
    _lastPreviewed = source;
    setState(() => _previewing = true);
    try {
      final preview = await _downloads.preview(source);
      if (!mounted || source != _source) return;
      setState(() {
        _preview = preview;
        _chosen = {for (final f in preview.files) f.index};
      });
    } catch (e) {
      if (mounted && source == _source) _fail(e);
    } finally {
      if (mounted && source == _source) setState(() => _previewing = false);
    }
  }

  void _fail(Object e) => setState(() {
        _off = e is Failure && e.code == FailureCode.unavailable;
        _said = e is Failure && e.code == FailureCode.invalidInput
            ? '认不出这个链接'
            : _off
                ? '下载已关闭'
                : callFailure(e);
      });

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) _text.text = text;
  }

  Future<void> _pickFile() async {
    final path = await widget.services.settings.pickPath(directory: false);
    if (path != null) _text.text = path;
  }

  Future<void> _pickFolder() async {
    setState(() => _folders = false);
    final path = await widget.services.settings.pickPath(directory: true);
    if (path != null && mounted) setState(() => _folder = path);
  }

  bool get _ready =>
      !_adding &&
      (_kind == _Kind.magnet || _kind == _Kind.link || _kind == _Kind.file) &&
      (_preview == null || _chosen.isNotEmpty);

  Future<void> _add() async {
    setState(() {
      _adding = true;
      _said = null;
    });
    try {
      final preview = _preview;
      final id = await _downloads.add(
        _source,
        folder: _folder,
        files: preview != null && _chosen.length < preview.files.length
            ? (_chosen.toList()..sort())
            : null,
      );
      widget.onDone(id);
    } catch (e) {
      if (mounted) _fail(e);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  // —— debug ——

  @override
  Future<void> debug(Map<String, String> p) async {
    if (p['source'] case final s?) _text.text = s;
    if (p['folders'] case final open?) setState(() => _folders = open == 'true');
    if (p['files'] == 'video' && _preview != null) {
      setState(() => _chosen = {
            for (final f in _preview!.files)
              if (f.video) f.index
          });
    }
    if (p['add'] == 'true' && _ready) unawaited(_add());
  }

  @override
  Map<String, Object?> debugStatus() => {
        'kind': _kind.name,
        'preview': _preview?.name,
        'chosen': _chosen.length,
        'said': _said,
        'ready': _ready,
      };

  @override
  Widget build(BuildContext context) => NextDropZone(
        onDrop: (paths) {
          final torrent = paths
              .where((p) => p.toLowerCase().endsWith('.torrent'))
              .firstOrNull;
          if (torrent != null) _text.text = torrent;
        },
        builder: (context, over) {
          if (over != _over) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _over = over);
            });
          }
          return SheetSurface(
            padding: const EdgeInsets.fromLTRB(26, 22, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text('新建下载',
                        style: NextText.sans(17, weight: FontWeight.w600)),
                  ),
                  NextIconButton(
                      glyph: NextGlyph.close,
                      label: '关闭',
                      onTap: () => widget.onDone(null)),
                ]),
                const SizedBox(height: 16),
                Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _field()),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Row(children: [
                    _Ghost(label: '粘贴', onTap: _paste),
                    const SizedBox(width: 6),
                    _Ghost(label: '种子文件', onTap: _pickFile),
                    const Spacer(),
                    if (_said != null) ...[
                      Text(_said!,
                          style:
                              NextText.sans(12.5, color: NextColors.accent2)),
                      if (_off && widget.onSettings != null) ...[
                        const SizedBox(width: 10),
                        PillButton(label: '打开', onTap: widget.onSettings),
                      ],
                    ],
                  ]),
                ),
                if (_previewing || _preview != null) ...[
                  const SizedBox(height: 16),
                  Container(height: 1, color: NextColors.line),
                  const SizedBox(height: 10),
                  Flexible(child: _files()),
                ],
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _place(),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Row(children: [
                    if (_preview case final p?)
                      Text(
                          '${_chosen.length} / ${p.files.length}  ·  '
                          '${bytesText(_size(p))}',
                          style: NextText.num(12.5, color: NextColors.p3)),
                    const Spacer(),
                    PillButton(label: '取消', onTap: () => widget.onDone(null)),
                    const SizedBox(width: 8),
                    PillButton(
                        label: '下载',
                        primary: true,
                        busy: _adding,
                        onTap: _ready ? _add : null),
                  ]),
                ),
              ],
            ),
          );
        },
      );

  int _size(UiTorrentPreview p) => p.files
      .where((f) => _chosen.contains(f.index))
      .fold<int>(0, (n, f) => n + f.size);

  Widget _field() {
    final focused = _focus.hasFocus;
    return ListenableBuilder(
      listenable: _focus,
      builder: (context, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _over
              ? NextColors.accentSoft
              : focused
                  ? const Color(0x14FFFFFF)
                  : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: _over || _focus.hasFocus
                  ? const Color(0x59FF2E55)
                  : NextColors.line),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: NextIcon(NextGlyph.torrent,
                size: 16, color: _over ? NextColors.accent2 : NextColors.p3),
          ),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              autofocus: widget.source == null,
              minLines: 2,
              maxLines: 3,
              cursorColor: NextColors.accent,
              cursorWidth: 1.5,
              style: NextText.mono(12.5, color: NextColors.paper, height: 1.6),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '磁力链接、种子地址，或拖入种子文件',
                hintStyle: NextText.sans(13.5, color: NextColors.p4),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _files() {
    final p = _preview;
    if (p == null) {
      return const SizedBox(height: 80, child: Center(child: ThinkingDots()));
    }
    final videos = {
      for (final f in p.files)
        if (f.video) f.index
    };
    final all = _chosen.length == p.files.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 6, 6),
          child: Row(children: [
            NextCheck(
              on: all,
              some: _chosen.isNotEmpty && !all,
              label: '全部',
              onTap: () => setState(() => _chosen =
                  all ? {} : {for (final f in p.files) f.index}),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(13.5, weight: FontWeight.w600)),
            ),
            if (videos.isNotEmpty && videos.length < p.files.length)
              _Ghost(
                  label: '只要视频',
                  onTap: () => setState(() => _chosen = {...videos})),
          ]),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(right: 6),
            children: [
              for (final f in p.files)
                DownloadFileRow(
                  file: f,
                  included: _chosen.contains(f.index),
                  progress: false,
                  onToggle: () => setState(() {
                    if (!_chosen.remove(f.index)) _chosen.add(f.index);
                  }),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _place() {
    final places = _places;
    final folder = _folder ?? places?.folder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Pressable(
          onTap: () => setState(() => _folders = !_folders),
          semanticLabel: '存到',
          pressScale: 0.99,
          builder: (context, hovered) => Row(children: [
            Text('存到', style: NextText.sans(13, color: NextColors.p3)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(folder == null ? '' : _short(folder),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(13,
                      color: hovered ? NextColors.paper : NextColors.p2)),
            ),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: _folders ? 0.25 : 0,
              duration: const Duration(milliseconds: 180),
              child: const NextIcon(NextGlyph.chevronRight,
                  size: 12, color: NextColors.p3),
            ),
          ]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: NextMotion.ease,
          alignment: Alignment.topLeft,
          child: !_folders
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8, left: 40),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final f in {
                      if (places != null) places.folder,
                      ...?places?.recent
                    })
                      _Ghost(
                        label: _short(f),
                        on: f == folder,
                        onTap: () => setState(() {
                          _folder = f;
                          _folders = false;
                        }),
                      ),
                    _Ghost(label: '选择…', onTap: _pickFolder),
                  ]),
                ),
        ),
      ],
    );
  }

  /// The last two parts of a folder.
  static String _short(String path) {
    final parts =
        path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).toList();
    return parts.length <= 2
        ? parts.join(' / ')
        : parts.skip(parts.length - 2).join(' / ');
  }
}

class _Ghost extends StatelessWidget {
  const _Ghost({required this.label, this.onTap, this.on = false});
  final String label;
  final VoidCallback? onTap;
  final bool on;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on
                ? NextColors.accentSoft
                : hovered
                    ? const Color(0x14FFFFFF)
                    : const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
                color: on ? const Color(0x59FF2E55) : NextColors.line),
          ),
          child: Text(label,
              style: NextText.sans(12,
                  color: on ? NextColors.accent2 : NextColors.p2)),
        ),
      );
}
