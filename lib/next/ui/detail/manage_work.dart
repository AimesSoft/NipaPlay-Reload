import 'package:flutter/material.dart' show TextField, InputDecoration;
import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../data/work_manage.dart';
import '../settings/controls.dart';
import '../settings/section_accounts.dart' show ConfirmPill;
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/devices.dart';
import '../widgets/icons.dart';
import '../widgets/segmented.dart';
import 'manage_sheet.dart';

enum WorkSection { match, info, art, episodes }

/// Debug handles of a management sheet (`ext.nipaplay.nextui` `manage`).
abstract interface class ManageSheetDebug {
  Map<String, Object?> debugStatus();
  Future<void> debugDo(Map<String, String> p);
}

/// The work's sheet: what it is matched to (or a work of its own), its
/// words, its pictures, and which file is which episode.
class WorkManageSheet extends StatefulWidget {
  const WorkManageSheet({
    super.key,
    required this.work,
    required this.manage,
    required this.section,
    this.revision = 0,
    required this.onClose,
    required this.onChanged,
    required this.onReplaced,
    required this.onRemoved,
  });
  final UiWork work;
  final NextWorkManage manage;
  final WorkSection section;
  final VoidCallback onClose;

  /// The page read again: so does the sheet (background changes).
  final int revision;

  /// Something changed: the page reads again.
  final VoidCallback onChanged;

  /// The work is now another one (a work of its own was made of it).
  final ValueChanged<String> onReplaced;

  /// A work of its own was taken out of the library.
  final ValueChanged<UiUndo> onRemoved;

  @override
  State<WorkManageSheet> createState() => WorkManageSheetState();
}

typedef _Ask = ({
  String title,
  List<String> items,
  String action,
  Future<void> Function() run
});

/// A change of matches put up to confirm: as NipaPlay previewed it, and
/// how to preview it again.
final class _Impact {
  const _Impact({
    required this.title,
    this.image,
    required this.action,
    this.danger = false,
    required this.done,
    required this.plan,
    required this.preview,
    this.after,
    this.notice,
  });
  final String title;
  final String? image;
  final String action;
  final bool danger;
  final String done;
  final UiAssociation plan;
  final Future<UiAssociation> Function() preview;
  final VoidCallback? after;
  final String? notice;

  /// Previewed again after something changed in between.
  _Impact again(UiAssociation plan) => _Impact(
        title: title,
        image: image,
        action: action,
        danger: danger,
        done: done,
        plan: plan,
        preview: preview,
        after: after,
        notice: '刚刚有了变化，再试一次',
      );
}

class WorkManageSheetState extends State<WorkManageSheet>
    with ManageRunner<WorkManageSheet>
    implements ManageSheetDebug {
  late WorkSection _section = widget.section;
  UiManagedWork? _data;
  bool _readFailed = false;

  // 匹配
  UiProvider? _provider;
  late final _query = TextEditingController(text: widget.work.title);
  List<UiMatchCandidate>? _results;
  bool _searching = false, _searchFailed = false;
  UiMatchCandidate? _picked;
  List<UiCandidateEpisode>? _pickedEpisodes;
  bool _pickFailed = false;
  final _assign = <UiFile, UiCandidateEpisode>{};

  // 资料
  final _drafts = <UiTextField, String>{};

  // 剧集: drafts by the episode's first file.
  final _titles = <String, String>{};
  final _numbers = <String, String>{};
  List<UiCandidateEpisode>? _matchEpisodes;
  String? _matchEpisodesFor;

  _Ask? _ask;
  _Impact? _impact;

  /// Debug: a picture shown as when hovered.
  UiArtKind? _hoverArt;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(WorkManageSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) _section = widget.section;
    if (oldWidget.revision != widget.revision && _data != null) _read();
  }

  @override
  void dispose() {
    _query.dispose();
    disposeRunner();
    super.dispose();
  }

  Future<void> _read() async {
    try {
      final data = await widget.manage.work(widget.work);
      if (!mounted) return;
      setState(() {
        _data = data;
        _readFailed = false;
        _provider ??= data.match?.provider ?? UiProvider.dandanplay;
      });
      final match = data.match;
      final ref = match == null ? null : '${match.candidate.ref}';
      if (match != null && ref != _matchEpisodesFor) {
        _matchEpisodesFor = ref;
        try {
          final episodes =
              await widget.manage.candidateEpisodes(match.candidate);
          if (mounted) setState(() => _matchEpisodes = episodes);
        } on UiManageError {
          // Read again with the work next time.
          _matchEpisodesFor = null;
        }
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

  List<(WorkSection, String)> get _sections {
    final kind = _data?.kind;
    return [
      (WorkSection.match, '匹配'),
      if (kind != UiWorkKind.files) ...[
        (WorkSection.info, '资料'),
        (WorkSection.art, '图片'),
      ],
      (WorkSection.episodes, '剧集'),
    ];
  }

  // —— 匹配 ——

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searchFailed = false;
      _picked = null;
    });
    try {
      final results = await widget.manage.search(_provider!, query);
      if (mounted) setState(() => _results = results);
    } on UiManageError {
      if (mounted) setState(() => _searchFailed = true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  static bool _sameRef(Map a, Map b) =>
      a['provider'] == b['provider'] &&
      '${a['externalId']}' == '${b['externalId']}' &&
      a['objectType'] == b['objectType'];

  bool _isCurrent(UiMatchCandidate c) {
    final ref = _data?.match?.candidate.ref;
    return ref != null && _sameRef(ref, c.ref);
  }

  /// The chosen film, when the candidate is one: its one episode is the
  /// film itself.
  UiCandidateEpisode? get _film =>
      _pickedEpisodes?.where((e) => e.movie).firstOrNull;

  /// A candidate chosen: its episodes, each file given the one its
  /// episode's recorded season and number are ([uiPairEpisode]) until the
  /// viewer says otherwise; a file nothing fits is the viewer's to choose.
  /// A film is its own one episode: the files of a work that is one
  /// episode are it; of several, which is the film is the viewer's to say.
  Future<void> _pick(UiMatchCandidate candidate) async {
    setState(() {
      _picked = candidate;
      _pickedEpisodes = null;
      _pickFailed = false;
      _assign.clear();
    });
    try {
      final episodes = await widget.manage.candidateEpisodes(candidate);
      if (!mounted || !identical(_picked, candidate)) return;
      final data = _data!;
      setState(() {
        _pickedEpisodes = episodes;
        if (_film case final film?) {
          if (data.episodes.length == 1) {
            for (final f in data.episodes.single.files) {
              _assign[f] = film;
            }
          }
          return;
        }
        for (final e in data.episodes) {
          final pick = uiPairEpisode(episodes, e.season, e.number);
          if (pick == null) continue;
          for (final f in e.files) {
            _assign[f] = pick;
          }
        }
      });
    } on UiManageError {
      if (mounted) setState(() => _pickFailed = true);
    }
  }

  /// NipaPlay's preview of a change of matches, put up to confirm.
  Future<void> _preview(Future<UiAssociation> Function() preview,
      {required String title,
      String? image,
      required String action,
      bool danger = false,
      required String done,
      VoidCallback? after}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final plan = await preview();
      if (!mounted) return;
      setState(() => _impact = _Impact(
          title: title,
          image: image,
          action: action,
          danger: danger,
          done: done,
          plan: plan,
          preview: preview,
          after: after));
    } on UiManageError {
      if (mounted) say('没能完成', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Does what was previewed; when something changed since, reads the
  /// work again and previews it again.
  Future<void> _apply() async {
    final impact = _impact!;
    setState(() => busy = true);
    try {
      await impact.plan.apply();
      if (!mounted) return;
      setState(() => _impact = null);
      say(impact.done);
      impact.after?.call();
    } on UiManageError catch (e) {
      if (!mounted) return;
      if (!e.conflict) {
        setState(() => _impact = null);
        say('没能完成', error: true);
        return;
      }
      await _read();
      try {
        final plan = await impact.preview();
        if (mounted) setState(() => _impact = impact.again(plan));
      } on UiManageError {
        if (!mounted) return;
        setState(() => _impact = null);
        say('刚刚有了变化，再试一次', error: true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
      await reload();
    }
  }

  void _match() {
    final picked = _picked!;
    final files = Map.of(_assign);
    _preview(() => widget.manage.previewMatch(_data!, picked, files),
        title: picked.title,
        image: picked.image,
        action: '匹配',
        done: '已匹配',
        after: () => setState(() {
              _picked = null;
              _results = null;
            }));
  }

  void _unmatch() {
    final match = _data!.match!;
    _preview(() => widget.manage.previewUnmatch(_data!),
        title: match.title,
        image: match.image,
        action: '解除匹配',
        danger: true,
        done: '已解除匹配');
  }

  Future<void> _makeLocal() async {
    final data = _data!;
    String? id;
    await run(() async {
      id = await widget.manage.createLocal(data, widget.work.title);
    });
    if (id != null) widget.onReplaced(id!);
  }

  /// The page takes over: it shows the way back.
  Future<void> _removeWork() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      widget.onRemoved(await widget.manage.removeLocal(_data!));
    } on UiManageError catch (e) {
      if (mounted) say(e.conflict ? '刚刚有了变化，再试一次' : '没能完成', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // —— 资料 ——

  String _value(UiTextField f) =>
      _drafts[f] ?? _data?.text[f]?.value ?? '';

  bool get _textChanged => _drafts.entries
      .any((e) => e.value != (_data?.text[e.key]?.value ?? ''));

  Future<void> _saveText() async {
    final values = {
      for (final e in _drafts.entries)
        if (e.value != (_data?.text[e.key]?.value ?? ''))
          e.key: e.value.trim().isEmpty ? null : e.value.trim()
    };
    final ok = await run(() => widget.manage.editText(_data!, values),
        done: '已保存');
    if (ok && mounted) setState(_drafts.clear);
  }

  // —— 图片 ——

  Future<void> _replaceArt(UiArtKind kind) async {
    final file =
        await widget.manage.pickFile(const ['jpg', 'jpeg', 'png', 'webp']);
    if (file == null) return;
    await run(() => widget.manage.setArt(_data!, kind, file), done: '已更换');
  }

  // —— 剧集 ——

  static String _key(UiManagedEpisode e) =>
      e.files.firstOrNull?.path ?? '${e.season}/${e.number}';

  bool get _episodesChanged =>
      _data?.episodes.any((e) =>
          (_titles[_key(e)] != null && _titles[_key(e)] != (e.title ?? '')) ||
          (_numbers[_key(e)] != null && _numbers[_key(e)] != e.number)) ??
      false;

  Future<void> _saveEpisodes() async {
    final data = _data!;
    final bool ok;
    if (data.kind == UiWorkKind.local) {
      ok = await run(
          () => widget.manage.saveLocal(data, [
                for (final e in data.episodes)
                  UiLocalEpisodeEdit(
                    number: _numbers[_key(e)]?.trim().isNotEmpty == true
                        ? _numbers[_key(e)]!.trim()
                        : e.number,
                    season: e.season,
                    title: _titles[_key(e)] ?? e.title,
                    files: e.files,
                    handle: e.handle,
                  )
              ]),
          done: '已保存');
    } else {
      ok = await run(
          () => widget.manage.editEpisodeTitles({
                for (final e in data.episodes)
                  if (_titles[_key(e)] case final t? when t != (e.title ?? ''))
                    e: t.trim().isEmpty ? null : t.trim()
              }),
          done: '已保存');
    }
    if (ok && mounted) {
      setState(() {
        _titles.clear();
        _numbers.clear();
      });
    }
  }

  void _relink(UiManagedEpisode e, UiCandidateEpisode to) {
    final match = _data!.match!;
    _preview(
        () => widget.manage.previewMatch(
            _data!, match.candidate, {for (final f in e.files) f: to}),
        title: '${match.title}  ${to.label}',
        image: match.image,
        action: '更改',
        done: '已更改');
  }

  Future<void> _removeEpisode(UiManagedEpisode e) async {
    UiUndo? undo;
    await run(() async {
      undo = await widget.manage.removeLocal(_data!, episode: e);
    });
    if (undo != null && mounted) {
      say('已移除 ${e.label}',
          action: ('撤回', () => run(() => widget.manage.restore(undo!))));
    }
  }

  Future<void> _addFile() async {
    final path = await widget.manage
        .pickFile(const ['mp4', 'mkv', 'mov', 'avi', 'webm', 'ts', 'm2ts']);
    if (path == null) return;
    await run(() => widget.manage.addFile(_data!, path), done: '已添加');
  }

  // —— Debug ——

  @override
  Map<String, Object?> debugStatus() => {
        'sheet': 'work',
        'section': _section.name,
        'kind': _data?.kind.name,
        'match': _data?.match?.title,
        'results': _results?.length,
        'picked': _picked?.title,
        'assigned': {
          for (final e in _assign.entries) e.key.name: e.value.label
        },
        'episodes': _data?.episodes.length,
        'drafts': {for (final e in _drafts.entries) e.key.name: e.value},
        'note': note?.text,
        'asking': _ask?.title,
        'impact': switch (_impact) {
          final i? => {
              'title': i.title,
              'works': i.plan.works,
              'episodes': i.plan.episodes,
              'files': i.plan.files,
              'watched': i.plan.watched,
              'sources': i.plan.sources,
              'devices': i.plan.devices,
              'notice': i.notice,
            },
          null => null,
        },
        'device': _data?.device,
        'away': _data?.away,
        'unavailable': _data?.unavailable,
        'titlesEdited': [
          for (final (i, e)
              in (_data?.episodes ?? const <UiManagedEpisode>[]).indexed)
            if (e.titleEdited) i
        ],
        'busy': busy,
      };

  @override
  Future<void> debugDo(Map<String, String> p) async {
    if (p['section'] case final s?) {
      setState(() => _section = WorkSection.values.byName(s));
    }
    if (p['provider'] case final v?) {
      setState(() => _provider = UiProvider.values.byName(v));
    }
    if (p['query'] case final q?) {
      _query.text = q;
      await _search();
    }
    if (p['pick'] case final i?) await _pick(_results![int.parse(i)]);
    if (p['assign'] case final d?) {
      // `N:K`: file N is the candidate's episode K; `N:skip`: it stays.
      final at = d.indexOf(':');
      final file = _data!.files[int.parse(d.substring(0, at))];
      final to = d.substring(at + 1);
      setState(() {
        if (to == 'skip') {
          _assign.remove(file);
        } else {
          _assign[file] = _pickedEpisodes![int.parse(to)];
        }
      });
    }
    if (p['back'] == 'true') setState(() => _picked = null);
    if (p['match'] == 'true') _match();
    if (p['local'] == 'true') await _makeLocal();
    if (p['draft'] case final d?) {
      final at = d.indexOf(':');
      setState(() => _drafts[UiTextField.values.byName(d.substring(0, at))] =
          d.substring(at + 1));
    }
    if (p['title'] case final d?) {
      final at = d.indexOf(':');
      final e = _data!.episodes[int.parse(d.substring(0, at))];
      setState(() => _titles[_key(e)] = d.substring(at + 1));
    }
    if (p['number'] case final d?) {
      final at = d.indexOf(':');
      final e = _data!.episodes[int.parse(d.substring(0, at))];
      setState(() => _numbers[_key(e)] = d.substring(at + 1));
    }
    if (p['save'] == 'true') {
      await (_section == WorkSection.info ? _saveText() : _saveEpisodes());
    }
    if (p['unmatch'] == 'true') _unmatch();
    if (p['restoreTitle'] case final i?) {
      await run(
          () => widget.manage.clearEpisodeTitle(_data!.episodes[int.parse(i)]),
          done: '已恢复');
    }
    if (p['clear'] case final f?) {
      await run(() => widget.manage.clearText(_data!, UiTextField.values.byName(f)),
          done: '已恢复');
    }
    if (p['art'] case final k?) await _replaceArt(UiArtKind.values.byName(k));
    if (p['hoverArt'] case final k?) {
      setState(() => _hoverArt =
          k == 'none' ? null : UiArtKind.values.byName(k));
    }
    if (p['clearArt'] case final k?) {
      await run(() => widget.manage.clearArt(_data!, UiArtKind.values.byName(k)),
          done: '已恢复');
    }
    if (p['refresh'] == 'true') {
      await run(() => widget.manage.refresh(_data!), done: '正在刷新');
    }
    if (p['removeEpisode'] case final i?) {
      await _removeEpisode(_data!.episodes[int.parse(i)]);
    }
    if (p['relink'] case final d?) {
      final at = d.indexOf(':');
      _relink(_data!.episodes[int.parse(d.substring(0, at))],
          _matchEpisodes![int.parse(d.substring(at + 1))]);
    }
    if (p['apply'] case final a?) {
      // The preview arrives a moment after it was asked for.
      for (var i = 0; i < 20 && _impact == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (a == 'yes') {
        await _apply();
      } else {
        setState(() => _impact = null);
      }
    }
    if (p['undo'] == 'true') note?.action?.$2();
    if (p['removeWork'] == 'true') await _removeWork();
  }

  // —— Building ——

  @override
  Widget build(BuildContext context) {
    final work = widget.work;
    final sections = _sections;
    final section = sections.any((s) => s.$1 == _section)
        ? _section
        : WorkSection.match;
    return ManageFrame<WorkSection>(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 40,
          height: 60,
          child: NextImage(work.artwork.poster ?? work.artwork.backdrop,
              shape: ArtShape.poster, tint: work.artwork.tint),
        ),
      ),
      caption: work.originalTitle,
      title: work.title,
      device: _data?.device,
      section: section,
      sections: sections,
      onSection: (s) => setState(() => _section = s),
      onClose: widget.onClose,
      note: note,
      confirm: _ask != null
          ? ConfirmCard(
              title: _ask!.title,
              items: _ask!.items,
              action: _ask!.action,
              onCancel: () => setState(() => _ask = null),
              onConfirm: () async {
                final ask = _ask!;
                await run(ask.run);
                if (mounted) setState(() => _ask = null);
              },
            )
          : _impact != null
              ? ImpactCard(
                  key: ValueKey(_impact),
                  title: _impact!.title,
                  image: _impact!.image,
                  plan: _impact!.plan,
                  action: _impact!.action,
                  danger: _impact!.danger,
                  notice: _impact!.notice,
                  onCancel: () => setState(() => _impact = null),
                  onConfirm: _apply,
                )
              : null,
      body: _data == null
          ? Center(
              child: _readFailed
                  ? Text('暂时读不到', style: NextText.sans(13, color: NextColors.p3))
                  : const SizedBox.shrink())
          : !_data!.editable
              ? Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const NextIcon(NextGlyph.device,
                        size: 15, color: NextColors.p3, stroke: 1.9),
                    const SizedBox(width: 8),
                    Text(_data!.unavailable!,
                        style: NextText.sans(13, color: NextColors.p3)),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
                  children: switch (section) {
                    WorkSection.match => _matchSection(),
                    WorkSection.info => _infoSection(),
                    WorkSection.art => _artSection(),
                    WorkSection.episodes => _episodeSection(),
                  },
                ),
    );
  }

  List<Widget> _matchSection() {
    final data = _data!;
    final picked = _picked;
    if (picked != null) return _assignSection(picked);
    final match = data.match;
    return [
      if (match != null) ...[
        const ManageHeading('现在'),
        ManageGroup(children: [
          _CandidateRow(
            title: match.title,
            subtitle: [
              match.provider.label,
              if (match.year != null) '${match.year}',
            ].join(' · '),
            image: match.image,
            trailing: PillButton(
                label: '解除匹配', onTap: busy ? null : _unmatch),
          ),
        ]),
      ] else if (data.kind == UiWorkKind.local) ...[
        const ManageHeading('现在'),
        ManageGroup(children: [
          _CandidateRow(
            title: widget.work.title,
            subtitle: '本地作品 · ${data.episodes.length} 集',
            image: widget.work.artwork.poster,
            trailing: ConfirmPill(
                label: '移除作品', confirm: '确认移除', onConfirm: _removeWork),
          ),
        ]),
      ] else if (data.here) ...[
        const SizedBox(height: 12),
        Row(children: [
          PillButton(label: '作为本地作品', busy: busy, onTap: _makeLocal),
        ]),
      ],
      for (final reason in data.away) ...[
        const SizedBox(height: 12),
        AwayNote(reason),
      ],
      ManageHeading('搜索',
          trailing: Segmented<UiProvider>(
            value: _provider!,
            options: [
              for (final p in UiProvider.values)
                (
                  p,
                  p.label,
                  (color) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(p.label,
                            style: NextText.sans(12, color: color)),
                      )
                )
            ],
            onChanged: (p) {
              setState(() => _provider = p);
              if (_results != null) _search();
            },
          )),
      _SearchField(controller: _query, onSubmit: _search, busy: _searching),
      const SizedBox(height: 12),
      if (_searchFailed)
        _quiet('暂时搜不了')
      else if (_results case final results?)
        if (results.isEmpty)
          _quiet('没有找到')
        else
          ManageGroup(children: [
            for (final c in results)
              _CandidateRow(
                title: c.title,
                subtitle: [
                  if (c.originalTitle != null && c.originalTitle != c.title)
                    c.originalTitle!,
                  if (c.year != null) '${c.year}',
                  if (c.movie) '电影',
                ].join(' · '),
                image: c.image,
                trailing: _isCurrent(c)
                    ? const NextIcon(NextGlyph.check,
                        size: 16, color: NextColors.accent)
                    : c.elsewhere
                        ? const TagChip('已在片库')
                        : const NextIcon(NextGlyph.chevronRight,
                            size: 15, color: NextColors.p3),
                onTap: () => _pick(c),
              ),
          ]),
    ];
  }

  /// Which file is which of the chosen work's episodes, then 匹配. For a
  /// film, which files are it; the others stay as they are.
  List<Widget> _assignSection(UiMatchCandidate picked) {
    final episodes = _pickedEpisodes;
    final files = _data!.files;
    final film = _film;
    return [
      const SizedBox(height: 8),
      Row(children: [
        NextIconButton(
            glyph: NextGlyph.chevronLeft,
            label: '返回',
            size: 28,
            onTap: () => setState(() => _picked = null)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(picked.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NextText.sans(14, weight: FontWeight.w600)),
        ),
        TagChip(picked.provider.label),
      ]),
      ManageHeading(film == null ? '剧集' : '文件'),
      if (_pickFailed)
        _quiet('暂时读不到')
      else if (episodes == null)
        const SizedBox(height: 40)
      else if (episodes.isEmpty)
        _quiet('没有剧集')
      else if (files.isEmpty)
        _quiet('这台设备上没有文件')
      else ...[
        ManageGroup(children: [
          for (final f in files)
            _FileChoiceRow(
              file: f,
              device: _data!.device,
              value: _assign[f],
              options: episodes,
              skip: film != null,
              onChanged: (e) => setState(() {
                if (e == null) {
                  _assign.remove(f);
                } else {
                  _assign[f] = e;
                }
              }),
            ),
        ]),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: PillButton(
            label: '匹配',
            primary: true,
            busy: busy,
            onTap: (film == null
                    ? _assign.length == files.length
                    : _assign.isNotEmpty)
                ? _match
                : null,
          ),
        ),
      ],
    ];
  }

  List<Widget> _infoSection() {
    final data = _data!;
    Widget field(UiTextField f, String label, {int lines = 1}) {
      final edited = data.text[f]?.edited ?? false;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ManageHeading(label,
              trailing: edited
                  ? _SmallLink('恢复',
                      onTap: () => run(() => widget.manage.clearText(data, f),
                          done: '已恢复'))
                  : null),
          LiveTextField(
            key: ValueKey('${f.name}/${data.text[f]?.value}'),
            value: _value(f),
            width: null,
            lines: lines,
            onChanged: (v) => setState(() => _drafts[f] = v),
          ),
        ],
      );
    }

    return [
      field(UiTextField.title, '标题'),
      field(UiTextField.originalTitle, '原名'),
      field(UiTextField.overview, '简介', lines: 6),
      const SizedBox(height: 18),
      Row(children: [
        if (data.kind == UiWorkKind.matched)
          PillButton(
              label: '刷新资料',
              onTap: busy
                  ? null
                  : () => run(() => widget.manage.refresh(data),
                      done: '正在刷新')),
        const Spacer(),
        PillButton(
            label: '保存',
            primary: _textChanged,
            busy: busy,
            onTap: _textChanged ? _saveText : null),
      ]),
    ];
  }

  List<Widget> _artSection() {
    final data = _data!;
    final tint = widget.work.artwork.tint;
    Widget tile(UiArtKind kind, String label, double w, double h,
            ArtShape shape) =>
        _ArtTile(
          label: label,
          art: data.art[kind],
          width: w,
          height: h,
          shape: shape,
          tint: tint,
          hovered: _hoverArt == kind,
          onReplace: data.here ? () => _replaceArt(kind) : null,
          onRestore: () =>
              run(() => widget.manage.clearArt(data, kind), done: '已恢复'),
        );
    const inner = ManageLayer.width - 44;
    return [
      const ManageHeading('背景'),
      tile(UiArtKind.backdrop, '背景', inner, inner * 9 / 16, ArtShape.wide),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 128,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ManageHeading('海报'),
                tile(UiArtKind.poster, '海报', 128, 192, ArtShape.poster),
              ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const ManageHeading('Logo'),
            tile(UiArtKind.logo, 'Logo', inner - 144, 192, ArtShape.logo),
          ]),
        ),
      ]),
    ];
  }

  List<Widget> _episodeSection() {
    final data = _data!;
    final local = data.kind == UiWorkKind.local;
    final titled = data.kind != UiWorkKind.files;
    final relink = data.kind == UiWorkKind.matched ? _matchEpisodes : null;
    return [
      const SizedBox(height: 10),
      for (final reason in data.away) ...[
        AwayNote(reason),
        const SizedBox(height: 12),
      ],
      if (data.episodes.isEmpty)
        _quiet('这台设备上没有文件')
      else
        ManageGroup(children: [
          for (final (i, e) in data.episodes.indexed)
            _EpisodeEditRow(
              key: ValueKey(_key(e)),
              episode: e,
              index: i,
              device: data.device,
              local: local,
              titled: titled,
              film: widget.work.film,
              title: _titles[_key(e)] ?? e.title ?? '',
              number: _numbers[_key(e)] ?? e.number,
              onTitle: (v) => setState(() => _titles[_key(e)] = v),
              onNumber: (v) => setState(() => _numbers[_key(e)] = v),
              relink: relink,
              onRelink: (to) => _relink(e, to),
              onRestore: titled && e.titleEdited
                  ? () {
                      setState(() => _titles.remove(_key(e)));
                      run(() => widget.manage.clearEpisodeTitle(e),
                          done: '已恢复');
                    }
                  : null,
              onRemove: local && data.episodes.length > 1
                  ? () => _removeEpisode(e)
                  : null,
            ),
        ]),
      const SizedBox(height: 16),
      Row(children: [
        if (local && data.here)
          PillButton(label: '添加文件', onTap: busy ? null : _addFile),
        const Spacer(),
        if (titled)
          PillButton(
              label: '保存',
              primary: _episodesChanged,
              busy: busy,
              onTap: _episodesChanged ? _saveEpisodes : null),
      ]),
    ];
  }

  Widget _quiet(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
            child: Text(text, style: NextText.sans(13, color: NextColors.p3))),
      );
}

/// A small text link in a heading: “恢复”.
class _SmallLink extends StatelessWidget {
  const _SmallLink(this.text, {required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: text,
        pressScale: 0.98,
        builder: (context, hovered) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 7),
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: NextColors.accent),
          ),
          Text(text,
              style: NextText.sans(12,
                  color: hovered ? NextColors.paper : NextColors.p2)),
        ]),
      );
}

class _SearchField extends StatelessWidget {
  const _SearchField(
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
          if (busy)
            Text('…', style: NextText.sans(13, color: NextColors.p3))
        ]),
      );
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.title,
    required this.subtitle,
    this.image,
    this.trailing,
    this.onTap,
  });
  final String title;
  final String subtitle;
  final String? image;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget row(bool hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          decoration: BoxDecoration(
            color: hovered ? const Color(0x0DFFFFFF) : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                  width: 34,
                  height: 51,
                  child: NextImage(image, shape: ArtShape.poster)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NextText.sans(13.5, weight: FontWeight.w600)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NextText.sans(12, color: NextColors.p3)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ]),
        );
    if (onTap == null) return row(false);
    return Pressable(
        onTap: onTap,
        semanticLabel: title,
        pressScale: 0.99,
        builder: (context, hovered) => row(hovered));
  }
}

String _short(String text, [int max = 18]) =>
    text.characters.length <= max
        ? text
        : '${text.characters.take(max - 1)}…';

/// A file and the episode it is.
class _FileChoiceRow extends StatelessWidget {
  const _FileChoiceRow({
    required this.file,
    required this.device,
    required this.value,
    required this.options,
    required this.onChanged,
    this.skip = false,
  });
  final UiFile file;

  /// Where the work is (null: here).
  final String? device;
  final UiCandidateEpisode? value;
  final List<UiCandidateEpisode> options;

  /// It may stay as it is (跳过, null): a film's, which may not be it.
  final bool skip;
  final ValueChanged<UiCandidateEpisode?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(12.5,
                        color: NextColors.p2, height: 1.4)),
                if (file.device != device) ...[
                  const SizedBox(height: 3),
                  DeviceMark([UiDevice(name: file.device ?? '本机')], size: 11),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Nothing fits by the records: the viewer chooses.
          MenuChoice<UiCandidateEpisode?>(
            value: value,
            options: [
              if (value == null && !skip) (null, '选择'),
              for (final e in options) (e, _short(e.label)),
              if (skip) (null, '跳过'),
            ],
            onChanged: onChanged,
          ),
        ]),
      );
}

/// An episode in the 剧集 section: its number (a work of its own may
/// change it, or which episode of the match it is), its title, its file.
class _EpisodeEditRow extends StatelessWidget {
  const _EpisodeEditRow({
    super.key,
    required this.episode,
    required this.index,
    required this.device,
    required this.local,
    required this.titled,
    required this.film,
    required this.title,
    required this.number,
    required this.onTitle,
    required this.onNumber,
    required this.relink,
    required this.onRelink,
    required this.onRestore,
    required this.onRemove,
  });
  final UiManagedEpisode episode;
  final int index;

  /// Where the work is (null: here); files elsewhere say where they are.
  final String? device;
  final bool local;
  final bool titled;

  /// Of a film: its one episode goes without a number.
  final bool film;
  final String title;
  final String number;
  final ValueChanged<String> onTitle;
  final ValueChanged<String> onNumber;
  final List<UiCandidateEpisode>? relink;
  final ValueChanged<UiCandidateEpisode> onRelink;

  /// Back to the sources' title, once it is the viewer's own.
  final VoidCallback? onRestore;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final e = episode;
    // A film has no other episode to be.
    final current =
        relink == null ? null : uiPairEpisode(relink!, e.season, e.number);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (local)
            SizedBox(
              width: 52,
              child: LiveTextField(
                  value: number, width: 52, onChanged: onNumber),
            )
          else
            SizedBox(
              width: 52,
              child: Text(
                  film
                      ? ''
                      : int.tryParse(e.number) != null
                          ? e.number.padLeft(2, '0')
                          : e.number,
                  style: NextText.num(17,
                      weight: FontWeight.w700, color: NextColors.p2)),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: titled
                ? LiveTextField(
                    value: title, width: null, hint: '标题', onChanged: onTitle)
                : Text(e.title ?? (film ? '正片' : e.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(13.5)),
          ),
          if (onRestore != null) ...[
            const SizedBox(width: 8),
            _SmallLink('恢复', onTap: onRestore!),
          ],
          if (relink != null && current != null) ...[
            const SizedBox(width: 8),
            MenuChoice<UiCandidateEpisode>(
              value: current,
              options: [
                for (final c in relink!) (c, c.place)
              ],
              onChanged: onRelink,
            ),
          ],
          if (onRemove != null)
            NextIconButton(
                glyph: NextGlyph.close, size: 28, label: '移除', onTap: onRemove),
        ]),
        for (final f in e.files)
          Padding(
            padding: const EdgeInsets.only(left: 62, top: 6, right: 8),
            child: Row(children: [
              Flexible(
                child: Text(f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(11.5, color: NextColors.p3)),
              ),
              if (f.device != device) ...[
                const SizedBox(width: 8),
                DeviceMark([UiDevice(name: f.device ?? '本机')], size: 11),
              ],
            ]),
          ),
      ]),
    );
  }
}

/// A picture of the work: hover to change it or (once changed) restore
/// the sources' one.
class _ArtTile extends StatefulWidget {
  const _ArtTile({
    required this.label,
    required this.art,
    required this.width,
    required this.height,
    required this.shape,
    required this.tint,
    required this.onReplace,
    required this.onRestore,
    this.hovered = false,
  });
  final String label;
  final UiArt? art;
  final double width, height;
  final ArtShape shape;
  final int? tint;
  /// Null when pictures picked here cannot go where the work is.
  final VoidCallback? onReplace;
  final VoidCallback onRestore;
  final bool hovered;

  @override
  State<_ArtTile> createState() => _ArtTileState();
}

class _ArtTileState extends State<_ArtTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final path = widget.art?.path;
    final edited = widget.art?.edited ?? false;
    final logo = widget.shape == ArtShape.logo;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: logo ? const Color(0x14FFFFFF) : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NextColors.line2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (path != null)
            logo
                ? Padding(
                    padding: const EdgeInsets.all(18),
                    child: NextImage(path,
                        shape: ArtShape.logo, fit: BoxFit.contain))
                : NextImage(path, shape: widget.shape, tint: widget.tint),
          if (edited)
            const Positioned(
              top: 10,
              right: 10,
              child: SizedBox(
                width: 7,
                height: 7,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: NextColors.accent),
                ),
              ),
            ),
          AnimatedOpacity(
            opacity: _hover || widget.hovered || path == null ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: Container(
              color: path == null ? null : const Color(0x8C08080B),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (widget.onReplace case final replace?)
                  PillButton(
                      label: path == null ? '选择图片' : '更换', onTap: replace),
                if (edited) ...[
                  if (widget.onReplace != null) const SizedBox(width: 8),
                  PillButton(label: '恢复', onTap: widget.onRestore),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
