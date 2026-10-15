import 'package:flutter/material.dart' show TextField, InputDecoration;
import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../data/work_manage.dart';
import '../settings/controls.dart';
import '../settings/section_accounts.dart' show ConfirmPill;
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/words.dart';
import 'manage_sheet.dart';
import 'manage_work.dart' show ManageSheetDebug;

enum EpisodeSection { danmaku, subtitles, files }

/// An episode's sheet: its danmaku tracks, its subtitles, its files.
class EpisodeManageSheet extends StatefulWidget {
  const EpisodeManageSheet({
    super.key,
    required this.work,
    required this.episode,
    required this.manage,
    required this.section,
    this.revision = 0,
    required this.onClose,
    required this.onChanged,
    required this.onBlockWords,
    required this.onEpisodes,
  });
  final UiWork work;
  final UiEpisode episode;
  final NextWorkManage manage;
  final EpisodeSection section;
  final VoidCallback onClose;

  /// The page read again: so does the sheet (background changes).
  final int revision;
  final VoidCallback onChanged;

  /// The settings' blocked words.
  final VoidCallback onBlockWords;

  /// The work's sheet at 剧集, where files and episodes are paired.
  final VoidCallback onEpisodes;

  @override
  State<EpisodeManageSheet> createState() => EpisodeManageSheetState();
}

typedef _Ask = ({
  String title,
  List<String> items,
  String action,
  Future<void> Function() run
});

class EpisodeManageSheetState extends State<EpisodeManageSheet>
    with ManageRunner<EpisodeManageSheet>
    implements ManageSheetDebug {
  late EpisodeSection _section = widget.section;
  UiManagedEpisode? _data;
  bool _readFailed = false;

  int? _expanded;
  bool _adding = false;
  late final _query = TextEditingController(
      text: '${widget.work.title} ${widget.episode.number}');
  List<UiDanmakuCandidate>? _found;
  bool _searching = false, _searchFailed = false;

  /// The imported subtitle whose language and title are open.
  String? _editing;

  _Ask? _ask;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(EpisodeManageSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) _section = widget.section;
    if (oldWidget.revision != widget.revision && _data != null) _read();
    if (oldWidget.episode.episodeId != widget.episode.episodeId) {
      _data = null;
      _expanded = null;
      _found = null;
      _adding = false;
      _query.text = '${widget.work.title} ${widget.episode.number}';
      _read();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    disposeRunner();
    super.dispose();
  }

  Future<void> _read() async {
    try {
      final data = await widget.manage.episode(widget.work, widget.episode);
      if (mounted) {
        setState(() {
          _data = data;
          _readFailed = false;
        });
      }
    } on UiManageError {
      if (mounted) setState(() => _readFailed = true);
    }
  }

  @override
  Future<void> reload() async {
    await _read();
    widget.onChanged();
  }

  // —— 弹幕 ——

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searchFailed = false;
    });
    try {
      final found = await widget.manage.searchDanmaku(query);
      if (mounted) setState(() => _found = found);
    } on UiManageError {
      if (mounted) setState(() => _searchFailed = true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(UiDanmakuCandidate found) async {
    final ok = await run(() => widget.manage.addDanmaku(_data!, found),
        done: '正在添加');
    if (ok && mounted) {
      setState(() {
        _adding = false;
        _found = null;
      });
    }
  }

  Future<void> _importDanmaku() async {
    final path = await widget.manage.pickFile(const ['xml', 'json']);
    if (path == null) return;
    await run(() => widget.manage.importDanmaku(_data!, path), done: '已导入');
  }

  Future<void> _offset(UiDanmakuTrack t, Duration to) =>
      run(() => widget.manage.setDanmaku(t, offset: to));

  // —— 字幕 ——

  Future<void> _importSubtitle(UiSubtitles s) async {
    final path = await widget.manage
        .pickFile(const ['ass', 'ssa', 'srt', 'vtt', 'sub', 'sup', 'idx']);
    if (path == null) return;
    await run(() => widget.manage.importSubtitle(s, path), done: '已导入');
  }

  Future<void> _askCopies(UiSubtitles s) async {
    await run(() async {
      final confirm = await widget.manage.deleteSubtitleCopies(s);
      if (mounted) {
        setState(() => _ask = (
              title: '删除这些字幕文件？',
              items: confirm.items,
              action: '删除',
              run: confirm.run
            ));
      }
    });
  }

  // —— 文件 ——

  Future<void> _reveal(UiFile f) async {
    try {
      await widget.manage.reveal(f);
    } on UiManageError {
      if (mounted) say('没能打开', error: true);
    }
  }

  Future<void> _askDelete(UiFile f) async {
    await run(() async {
      final confirm = await widget.manage.deleteFile(f);
      if (mounted) {
        setState(() => _ask = (
              title: switch (f.device) {
                null => '从磁盘删除？',
                final device => '从${uiSpaced(device, before: true)}删除？',
              },
              items: confirm.items,
              action: '删除',
              run: confirm.run
            ));
      }
    });
  }

  // —— Debug ——

  @override
  Map<String, Object?> debugStatus() => {
        'sheet': 'episode',
        'section': _section.name,
        'episode': widget.episode.number,
        'danmaku': [
          for (final t in _data?.danmaku ?? const <UiDanmakuTrack>[])
            {
              'source': t.source,
              'count': t.count,
              'enabled': t.enabled,
              'offsetMs': t.offset.inMilliseconds,
              'loading': t.loading,
            }
        ],
        'subtitles': [
          for (final s in _data?.subtitles ?? const <UiSubtitles>[])
            {
              'tracks': [for (final t in s.tracks) t.id],
              'selected': s.selected,
              'explicit': s.explicit,
              'detached': s.detached.length,
            }
        ],
        'files': [for (final f in _data?.files ?? const <UiFile>[]) f.name],
        'locations': [
          for (final f in _data?.locations ?? const <UiFile>[])
            '${f.device ?? '本机'}  ${f.path}'
        ],
        'device': _data?.device,
        'away': _data?.away,
        'unavailable': _data?.unavailable,
        'found': _found?.length,
        'note': note?.text,
        'asking': _ask?.title,
        'busy': busy,
      };

  @override
  Future<void> debugDo(Map<String, String> p) async {
    final data = _data;
    if (p['section'] case final s?) {
      setState(() => _section = EpisodeSection.values.byName(s));
    }
    if (p['expand'] case final i?) {
      setState(() => _expanded = int.tryParse(i));
    }
    if (p['toggle'] case final i?) {
      final t = data!.danmaku[int.parse(i)];
      await run(() => widget.manage.setDanmaku(t, enabled: !t.enabled));
    }
    if (p['offset'] case final d?) {
      final at = d.indexOf(':');
      await _offset(data!.danmaku[int.parse(d.substring(0, at))],
          Duration(milliseconds: int.parse(d.substring(at + 1))));
    }
    if (p['removeTrack'] case final i?) {
      await run(() => widget.manage.removeDanmaku(data!.danmaku[int.parse(i)]),
          done: '已移除');
    }
    if (p['add'] case final open?) setState(() => _adding = open == 'true');
    if (p['query'] case final q?) {
      _query.text = q;
      await _search();
    }
    if (p['found'] case final i?) await _add(_found![int.parse(i)]);
    if (p['import'] case final path?) {
      await run(() => widget.manage.importDanmaku(data!, path), done: '已导入');
    }
    if (p['importSubtitle'] case final path?) {
      await run(() => widget.manage.importSubtitle(data!.subtitles.first, path),
          done: '已导入');
    }
    if (p['subtitle'] case final v?) {
      final s = data!.subtitles.first;
      await switch (v) {
        'auto' => run(() => widget.manage.automaticSubtitle(s)),
        'off' => run(() => widget.manage.selectSubtitle(s, null)),
        _ => run(() => widget.manage.selectSubtitle(s, v)),
      };
    }
    if (p['edit'] case final id?) setState(() => _editing = id);
    if (p['language'] case final d?) {
      final at = d.indexOf(':');
      final s = data!.subtitles.first;
      final t = s.tracks.firstWhere((t) => t.id == d.substring(0, at));
      await run(() => widget.manage
          .editSubtitle(s, t, language: d.substring(at + 1)));
    }
    if (p['detach'] case final id?) {
      final s = data!.subtitles.first;
      await run(() => widget.manage
          .detachSubtitle(s, s.tracks.firstWhere((t) => t.id == id)));
    }
    if (p['copies'] == 'true') await _askCopies(data!.subtitles.first);
    if (p['reveal'] case final i?) await _reveal(data!.locations[int.parse(i)]);
    if (p['deleteFile'] case final i?) {
      await _askDelete(data!.locations[i == 'true' ? 0 : int.parse(i)]);
    }
    if (p['confirm'] case final c?) {
      final ask = _ask;
      if (ask != null && c == 'yes') await run(ask.run, done: '已删除');
      if (mounted) setState(() => _ask = null);
    }
  }

  // —— Building ——

  @override
  Widget build(BuildContext context) {
    final e = widget.episode;
    final title = [Words.episode(e.number), if (e.title != null) e.title!]
        .join('  ');
    return ManageFrame<EpisodeSection>(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 80,
          height: 45,
          child: NextImage(e.still ?? widget.work.artwork.backdrop,
              tint: widget.work.artwork.tint),
        ),
      ),
      caption: widget.work.title,
      title: title,
      device: _data?.device,
      section: _section,
      sections: const [
        (EpisodeSection.danmaku, '弹幕'),
        (EpisodeSection.subtitles, '字幕'),
        (EpisodeSection.files, '文件'),
      ],
      onSection: (s) => setState(() => _section = s),
      onClose: widget.onClose,
      note: note,
      confirm: _ask == null
          ? null
          : ConfirmCard(
              title: _ask!.title,
              items: _ask!.items,
              action: _ask!.action,
              onCancel: () => setState(() => _ask = null),
              onConfirm: () async {
                final ask = _ask!;
                await run(ask.run, done: '已删除');
                if (mounted) setState(() => _ask = null);
              },
            ),
      body: _data == null
          ? Center(
              child: _readFailed
                  ? Text('暂时读不到',
                      style: NextText.sans(13, color: NextColors.p3))
                  : const SizedBox.shrink())
          : ListView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
              children: switch (_section) {
                EpisodeSection.files => _fileSection(),
                _ when _data!.unavailable != null => [
                    const SizedBox(height: 18),
                    AwayNote(_data!.unavailable!),
                  ],
                EpisodeSection.danmaku => _danmakuSection(),
                EpisodeSection.subtitles => _subtitleSection(),
              },
            ),
    );
  }

  Widget _quiet(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
            child: Text(text, style: NextText.sans(13, color: NextColors.p3))),
      );

  List<Widget> _danmakuSection() {
    final data = _data!;
    return [
      const SizedBox(height: 10),
      if (data.danmaku.isEmpty)
        _quiet('还没有弹幕')
      else
        ManageGroup(children: [
          for (final (i, t) in data.danmaku.indexed)
            _TrackRow(
              track: t,
              open: _expanded == i,
              onOpen: () =>
                  setState(() => _expanded = _expanded == i ? null : i),
              onEnabled: (v) =>
                  run(() => widget.manage.setDanmaku(t, enabled: v)),
              onOffset: (d) => _offset(t, d),
              onRemove: t.removable
                  ? () => run(() => widget.manage.removeDanmaku(t),
                      done: '已移除')
                  : null,
            ),
        ]),
      const SizedBox(height: 14),
      Row(children: [
        PillButton(
            label: '添加弹幕',
            onTap: () => setState(() => _adding = !_adding)),
        const SizedBox(width: 8),
        if (data.device == null)
          PillButton(label: '导入文件', onTap: busy ? null : _importDanmaku),
        const Spacer(),
        LinkText('屏蔽词', onTap: widget.onBlockWords),
      ]),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: NextMotion.ease,
        alignment: Alignment.topCenter,
        child: !_adding
            ? const SizedBox(width: double.infinity)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  _QueryField(
                      controller: _query, onSubmit: _search, busy: _searching),
                  const SizedBox(height: 10),
                  if (_searchFailed)
                    _quiet('暂时搜不了')
                  else if (_found case final found?)
                    if (found.isEmpty)
                      _quiet('没有找到')
                    else
                      ManageGroup(children: [
                        for (final f in found)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                            child: Row(children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(f.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: NextText.sans(13,
                                            height: 1.4)),
                                    const SizedBox(height: 3),
                                    Text(f.source,
                                        style: NextText.sans(11.5,
                                            color: NextColors.p3)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              PillButton(
                                  label: '添加',
                                  onTap: busy ? null : () => _add(f)),
                            ]),
                          ),
                      ]),
                ],
              ),
      ),
    ];
  }

  List<Widget> _subtitleSection() {
    final data = _data!;
    if (data.subtitles.isEmpty) return [_quiet('这台设备上没有文件')];
    return [
      for (final s in data.subtitles) ...[
        if (data.subtitles.length > 1)
          ManageHeading(s.file.name)
        else
          const SizedBox(height: 10),
        ManageGroup(children: [
          _Choice(
            label: '自动',
            selected: !s.explicit,
            onTap: () => run(() => widget.manage.automaticSubtitle(s)),
          ),
          _Choice(
            label: '关闭',
            selected: s.explicit && s.selected == null,
            onTap: () => run(() => widget.manage.selectSubtitle(s, null)),
          ),
          for (final t in s.tracks)
            _Choice(
              label: uiLanguageName(t.language),
              detail: t.title,
              tags: [
                if (t.format != null) t.format!.toUpperCase(),
                switch (t.kind) {
                  UiSubtitleKind.embedded => '内嵌',
                  UiSubtitleKind.external => '外挂',
                  UiSubtitleKind.imported => '导入',
                },
              ],
              selected: s.selected == t.id,
              automatic: !s.explicit,
              enabled: t.available,
              onTap: () => run(() => widget.manage.selectSubtitle(s, t.id)),
              onMore: t.editable
                  ? () => setState(
                      () => _editing = _editing == t.id ? null : t.id)
                  : null,
              below: _editing == t.id ? _subtitleEditor(s, t) : null,
            ),
        ]),
        if (s.detached.isNotEmpty) ...[
          const SizedBox(height: 12),
          ManageGroup(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(children: [
                Expanded(
                  child: Text('不再使用的字幕 ${s.detached.length} 个',
                      style: NextText.sans(13, color: NextColors.p2)),
                ),
                PillButton(
                    label: '删除',
                    danger: true,
                    onTap: busy ? null : () => _askCopies(s)),
              ]),
            ),
          ]),
        ],
        if (data.device == null) ...[
          const SizedBox(height: 14),
          Row(children: [
            PillButton(
                label: '导入字幕',
                onTap: busy ? null : () => _importSubtitle(s)),
          ]),
        ],
      ],
    ];
  }

  Widget _subtitleEditor(UiSubtitles s, UiSubtitleTrack t) => Padding(
        padding: const EdgeInsets.fromLTRB(44, 0, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            MenuChoice<String>(
              value: uiSubtitleLanguages.any((l) => l.$1 == t.language)
                  ? t.language!
                  : 'und',
              options: uiSubtitleLanguages,
              onChanged: (code) => run(
                  () => widget.manage.editSubtitle(s, t, language: code),
                  done: '已更改'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FieldControl(
                value: t.title ?? '',
                hint: '标题',
                width: 160,
                onCommit: (v) => run(
                    () => widget.manage.editSubtitle(s, t, title: v.trim()),
                    done: '已更改'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Spacer(),
            ConfirmPill(
              label: '解除关联',
              confirm: '确认解除',
              onConfirm: () => run(() => widget.manage.detachSubtitle(s, t),
                  done: '已解除'),
            ),
          ]),
        ]),
      );

  /// Every place a file of the episode is, by device: this one first.
  List<Widget> _fileSection() {
    final data = _data!;
    if (data.locations.isEmpty && data.away.isEmpty) {
      return [_quiet('这台设备上没有文件')];
    }
    final groups = <String?, List<UiFile>>{};
    for (final f in data.locations) {
      (groups[f.device] ??= []).add(f);
    }
    final named = data.away.isNotEmpty || groups.keys.any((d) => d != null);
    return [
      for (final MapEntry(key: device, value: files) in groups.entries) ...[
        if (named)
          ManageHeading(device ?? '本机', glyph: NextGlyph.device)
        else
          const SizedBox(height: 10),
        ManageGroup(children: [for (final f in files) _location(f)]),
      ],
      for (final reason in data.away) ...[
        const SizedBox(height: 16),
        AwayNote(reason),
      ],
      const SizedBox(height: 16),
      Row(children: [LinkText('剧集与文件', onTap: widget.onEpisodes)]),
    ];
  }

  Widget _location(UiFile f) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(f.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(13.5, weight: FontWeight.w600, height: 1.4)),
            const SizedBox(height: 4),
            Text(f.folder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(12, color: NextColors.p3)),
            const SizedBox(height: 10),
            Text(
                [
                  if (f.size != null) fileSize(f.size!),
                  if (f.duration != null) Words.duration(f.duration!),
                  if (f.modified != null)
                    '${f.modified!.year}-${f.modified!.month.toString().padLeft(2, '0')}-${f.modified!.day.toString().padLeft(2, '0')}',
                ].join('  ·  '),
                style: NextText.num(12.5, color: NextColors.p2)),
            const SizedBox(height: 14),
            Row(children: [
              if (f.manager case final manager?)
                PillButton(label: manager.label, onTap: () => _reveal(f)),
              const Spacer(),
              PillButton(
                  label: '删除文件',
                  danger: true,
                  onTap: busy ? null : () => _askDelete(f)),
            ]),
          ],
        ),
      );
}

class _QueryField extends StatelessWidget {
  const _QueryField(
      {required this.controller, required this.onSubmit, required this.busy});
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool busy;

  @override
  Widget build(BuildContext context) => Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NextColors.line2),
        ),
        child: Row(children: [
          const NextIcon(NextGlyph.search, size: 15, color: NextColors.p3),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              cursorColor: NextColors.accent,
              cursorWidth: 1.5,
              style: NextText.sans(13.5),
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration.collapsed(
                hintText: '搜索',
                hintStyle: NextText.sans(13, color: NextColors.p4),
              ),
            ),
          ),
          if (busy) Text('…', style: NextText.sans(13, color: NextColors.p3)),
        ]),
      );
}

/// A danmaku track: where it is from, how many, on or off; opened, its
/// timing and the way to take it away.
class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.open,
    required this.onOpen,
    required this.onEnabled,
    required this.onOffset,
    required this.onRemove,
  });
  final UiDanmakuTrack track;
  final bool open;
  final VoidCallback onOpen;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<Duration> onOffset;
  final VoidCallback? onRemove;

  static const _step = Duration(milliseconds: 500);

  static String _offset(Duration d) {
    final ms = d.inMilliseconds;
    if (ms == 0) return '准时';
    final s = (ms.abs() / 1000);
    final text =
        s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(1);
    return ms > 0 ? '提前 $text 秒' : '延后 $text 秒';
  }

  @override
  Widget build(BuildContext context) {
    final t = track;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Pressable(
        onTap: onOpen,
        semanticLabel: t.source,
        pressScale: 1,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
          color: hovered ? const Color(0x08FFFFFF) : const Color(0x00FFFFFF),
          child: Row(children: [
            Expanded(
              child: Opacity(
                opacity: t.enabled ? 1 : 0.5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(t.source,
                          style:
                              NextText.sans(13.5, weight: FontWeight.w600)),
                      if (t.offset != Duration.zero) ...[
                        const SizedBox(width: 8),
                        TagChip(_offset(t.offset), color: NextColors.p2),
                      ],
                    ]),
                    if (t.name != null) ...[
                      const SizedBox(height: 3),
                      Text(t.name!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NextText.sans(12, color: NextColors.p3)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (t.loading)
              Text('…', style: NextText.sans(13, color: NextColors.p3))
            else if (t.count != null)
              Text('${countText(t.count!)} 条',
                  style: NextText.num(12.5, color: NextColors.p2)),
            const SizedBox(width: 12),
            NextToggle(value: t.enabled, onChanged: onEnabled, label: t.source),
          ]),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: NextMotion.ease,
        alignment: Alignment.topCenter,
        child: !open
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 14, 12),
                child: Row(children: [
                  _Step(
                      label: '延后',
                      glyph: NextGlyph.chevronLeft,
                      onTap: () => onOffset(t.offset - _step)),
                  SizedBox(
                    width: 92,
                    child: Center(
                      child: Text(_offset(t.offset),
                          style: NextText.num(12.5, color: NextColors.paper)),
                    ),
                  ),
                  _Step(
                      label: '提前',
                      glyph: NextGlyph.chevronRight,
                      onTap: () => onOffset(t.offset + _step)),
                  if (t.offset != Duration.zero) ...[
                    const SizedBox(width: 8),
                    PillButton(
                        label: '归零', onTap: () => onOffset(Duration.zero)),
                  ],
                  const Spacer(),
                  if (onRemove != null)
                    ConfirmPill(
                        label: '移除', confirm: '确认移除', onConfirm: onRemove!),
                ]),
              ),
      ),
    ]);
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.glyph, required this.onTap});
  final String label;
  final NextGlyph glyph;
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
            color: hovered ? const Color(0x1FFFFFFF) : const Color(0x0FFFFFFF),
            border: Border.all(color: NextColors.line2),
          ),
          child: NextIcon(glyph,
              size: 14, color: hovered ? NextColors.paper : NextColors.p2),
        ),
      );
}

/// One choice of a list: a round mark, its name, a detail and tags.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
    this.tags = const [],
    this.enabled = true,
    this.automatic = false,
    this.onMore,
    this.below,
  });
  final String label;
  final String? detail;
  final List<String> tags;
  final bool selected;

  /// Chosen by NipaPlay, not by the viewer: a ring, not a dot.
  final bool automatic;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final Widget? below;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: enabled ? onTap : null,
            semanticLabel: label,
            pressScale: 1,
            builder: (context, hovered) => Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              color:
                  hovered ? const Color(0x08FFFFFF) : const Color(0x00FFFFFF),
              child: Opacity(
                opacity: enabled ? 1 : 0.4,
                child: Row(children: [
                  _Radio(on: selected, ring: automatic),
                  const SizedBox(width: 14),
                  Text(label, style: NextText.sans(13.5)),
                  if (detail != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NextText.sans(12, color: NextColors.p3)),
                    ),
                  ],
                  const Spacer(),
                  for (final tag in tags) ...[
                    TagChip(tag),
                    const SizedBox(width: 6),
                  ],
                  if (onMore != null)
                    Pressable(
                      onTap: onMore,
                      semanticLabel: '更多',
                      builder: (context, hovered) => SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(
                          child: Text('⋯',
                              style: NextText.sans(14,
                                  weight: FontWeight.w600,
                                  color: hovered
                                      ? NextColors.paper
                                      : NextColors.p3)),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 28),
                ]),
              ),
            ),
          ),
          if (below != null) below!,
        ],
      );
}

/// Filled when chosen; a faint hollow ring when “自动” picked it, so only
/// one choice ever looks chosen.
class _Radio extends StatelessWidget {
  const _Radio({required this.on, required this.ring});
  final bool on;
  final bool ring;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: !on
                  ? NextColors.p4
                  : ring
                      ? NextColors.accent.withValues(alpha: 0.55)
                      : NextColors.accent,
              width: 1.5),
        ),
        child: on && !ring
            ? Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: NextColors.accent,
                ),
              )
            : null,
      );
}
