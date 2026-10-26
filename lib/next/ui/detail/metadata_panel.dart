import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui_data/found.dart';
import '../../ui_data/ui_data.dart';
import '../data/work_manage.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';

/// Full source records are read only on the detail page, never carried through
/// every home/library card. Each provider keeps its own labels and credits.
class WorkMetadataPanel extends StatefulWidget {
  const WorkMetadataPanel({super.key, required this.work, this.manage});
  final UiWork work;
  final NextWorkManage? manage;

  @override
  State<WorkMetadataPanel> createState() => _WorkMetadataPanelState();
}

class _WorkMetadataPanelState extends State<WorkMetadataPanel> {
  UiManagedWork? _managed;
  Object? _error;
  bool _allFiles = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WorkMetadataPanel old) {
    super.didUpdateWidget(old);
    if (old.work != widget.work || old.manage != widget.manage) {
      _load();
    }
  }

  Future<void> _load() async {
    final work = widget.work;
    try {
      final result = await widget.manage?.work(work);
      if (mounted && identical(work, widget.work)) {
        setState(() {
          _managed = result;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && identical(work, widget.work)) {
        setState(() => _error = error);
      }
    }
  }

  Widget _heading(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Text(title, style: NextText.sans(18, weight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    final metadata = _managed?.metadata ?? widget.work.details;
    final sources = _maps(metadata['sources']);
    final files = _managed?.files.toSet().toList() ?? const <UiFile>[];
    if (sources.isEmpty && files.isEmpty && _error == null) {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final source in sources) _SourceDetails(source: source),
      if (files.isNotEmpty) ...[
        _heading('媒体文件 · ${files.length}'),
        for (final file in _allFiles ? files : files.take(3))
          _FileDetails(file: file),
        if (files.length > 3)
          Align(
              alignment: Alignment.centerLeft,
              child: NextButton.ghost(
                  label: _allFiles ? '收起文件' : '查看全部 ${files.length} 个文件',
                  onTap: () => setState(() => _allFiles = !_allFiles))),
      ],
      if (_error != null)
        Align(
            alignment: Alignment.centerLeft,
            child: NextButton.ghost(label: '重试读取详细资料', onTap: _load)),
    ]);
  }
}

List<Map> _maps(Object? value) =>
    value is List ? value.whereType<Map>().toList() : const [];
String _words(Object? value) {
  if (value == null) return '';
  if (value is String || value is num) return '$value';
  if (value is List) {
    return value.map(_words).where((s) => s.isNotEmpty).join('、');
  }
  if (value is Map) {
    return _words(
        value['name'] ?? value['v'] ?? value['value'] ?? value['title']);
  }
  return '';
}

class _SourceDetails extends StatefulWidget {
  const _SourceDetails({required this.source});
  final Map source;
  @override
  State<_SourceDetails> createState() => _SourceDetailsState();
}

class _SourceDetailsState extends State<_SourceDetails> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final provider = '${source['provider'] ?? ''}';
    final fields = source['fields'] as Map? ?? const {};
    final credits = fields['credits'] as Map? ?? const {};
    final cast = _maps(credits['cast']);
    final crew = _maps(credits['crew']);
    final staff = _maps(fields['staff']);
    final characters = _maps(fields['characters']);
    final rating = fields['rating'] as Map?;
    final id = '${source['externalId'] ?? ''}';
    final url = switch (provider) {
      'tmdb' => ['tv', 'movie'].contains(source['objectType'])
          ? 'https://www.themoviedb.org/${source['objectType']}/$id'
          : source['scope'] is String &&
                  RegExp(r'^tv/\d+/season/\d+(?:/episode/\d+)?$')
                      .hasMatch(source['scope'] as String)
              ? 'https://www.themoviedb.org/${source['scope']}'
              : null,
      'bangumi' => 'https://bgm.tv/subject/$id',
      _ => null,
    };
    final facts = <String, Object?>{
      '原名': fields['originalTitle'],
      '类型': fields['genres'],
      '首播': fields['firstAirDate'] ?? fields['releaseDate'],
      '最近播出': fields['lastAirDate'],
      '状态': fields['status'],
      '制作公司': fields['studios'] ?? fields['studio'],
      '播出平台': fields['networks'] ?? fields['platform'],
      '国家 / 地区': fields['countries'],
      '原始语言': fields['originalLanguage'],
      '集数': fields['episodeCount'],
      '季数': fields['seasonCount'],
      if (fields['runtimeMs'] is num)
        '时长': '${((fields['runtimeMs'] as num) / 60000).round()} 分钟',
      '标签': fields['tags'],
      'IMDb': (fields['externalIds'] as Map?)?['imdb_id'],
      'TVDB': (fields['externalIds'] as Map?)?['tvdb_id'],
      '创作': fields['creators'],
      for (final info in _maps(fields['infobox']))
        '${info['key']}': info['value'],
    };
    Widget line(String label, Object? value) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('$label  ${_words(value)}',
              style: NextText.sans(13.5, color: NextColors.p2, height: 1.65)),
        );
    Widget people(String title, List<Map> rows, String Function(Map) label) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 10),
              child: Text(title,
                  style: NextText.sans(15, weight: FontWeight.w600))),
          Wrap(spacing: 10, runSpacing: 8, children: [
            for (final person in _expanded ? rows : rows.take(18))
              Container(
                  width: 210,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0x0DFFFFFF),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(label(person),
                      style: NextText.sans(13,
                          color: NextColors.p2, height: 1.5))),
          ]),
        ]);
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(Found.source(provider),
              style: NextText.sans(19, weight: FontWeight.w600)),
          const SizedBox(width: 12),
          if (rating != null)
            Text(
                '${rating['value']} / ${rating['max'] ?? 10}${rating['count'] == null ? '' : ' · ${rating['count']} 人评分'}',
                style: NextText.num(14, color: NextColors.p2)),
        ]),
        if (url != null)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: NextButton.ghost(
                  label: '查看来源 · $id',
                  height: 30,
                  onTap: () => launchUrl(Uri.parse(url),
                      mode: LaunchMode.externalApplication))),
        const SizedBox(height: 12),
        if (_words(fields['tagline']).isNotEmpty) line('简介', fields['tagline']),
        for (final fact in facts.entries)
          if (_words(fact.value).isNotEmpty) line(fact.key, fact.value),
        if (_words(fields['overview']).isNotEmpty)
          line('故事', fields['overview']),
        if (cast.isNotEmpty)
          people('演员 / 配音', cast,
              (p) => '${_words(p['name'])}\n${_words(p['role'])}'),
        if (crew.isNotEmpty)
          people(
              '制作人员',
              crew,
              (p) =>
                  '${_words(p['name'])}\n${_words(p['role'] ?? p['department'])}'),
        if (staff.isNotEmpty)
          people('制作人员', staff,
              (p) => '${_words(p['name'])}\n${_words(p['relation'])}'),
        if (characters.isNotEmpty)
          people(
              '角色与声优',
              characters,
              (p) =>
                  '${_words(p['name'])} · ${_words(p['relation'])}\n${_words(p['actors'])}'),
        if ([cast, crew, staff, characters].any((r) => r.length > 18))
          NextButton.ghost(
              label: _expanded ? '收起演职员' : '查看全部演职员',
              onTap: () => setState(() => _expanded = !_expanded)),
        if (fields['detailErrors'] is List &&
            (fields['detailErrors'] as List).isNotEmpty)
          Text('部分演职员资料尚未获取', style: NextText.sans(12, color: NextColors.p3)),
      ]),
    );
  }
}

class _FileDetails extends StatelessWidget {
  const _FileDetails({required this.file});
  final UiFile file;
  @override
  Widget build(BuildContext context) {
    String rate(Object? value) => value is num && value > 0
        ? '${(value / 1000000).toStringAsFixed(2)} Mb/s'
        : '';
    final tech = file.technical;
    final lines = <String>[
      [
        if (file.device != null) file.device!,
        if (file.size != null)
          '${(file.size! / (1024 * 1024)).toStringAsFixed(1)} MiB',
        if (file.duration != null) '${file.duration!.inMinutes} 分钟',
        _words(tech['container']),
        rate(tech['bitrate'])
      ].where((s) => s.isNotEmpty).join(' · '),
      for (final v in _maps(tech['video']))
        [
          '视频',
          _words(v['codec']),
          if (v['width'] is num && v['height'] is num)
            '${v['width']} × ${v['height']}',
          if (v['fps'] is num && (v['fps'] as num) > 0)
            '${(v['fps'] as num).toStringAsFixed(3)} fps',
          _words(v['pixelFormat']),
          _words(v['colorSpace']),
          rate(v['bitrate'])
        ].where((s) => s.isNotEmpty).join(' · '),
      for (final a in _maps(tech['audio']))
        [
          '音频',
          _words(a['codec']),
          if (a['channels'] is num) '${a['channels']} 声道',
          if (a['sampleRate'] is num) '${a['sampleRate']} Hz',
          uiLanguageName(a['language'] as String?),
          rate(a['bitrate'])
        ].where((s) => s.isNotEmpty).join(' · '),
      if (tech.isEmpty) '编码、分辨率与码率尚未探测',
    ];
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(file.name, style: NextText.sans(14, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final line in lines.where((s) => s.isNotEmpty))
            Text(line,
                style: NextText.sans(12.5, color: NextColors.p2, height: 1.7)),
        ]));
  }
}
