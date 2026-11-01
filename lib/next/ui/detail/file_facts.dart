import '../../ui_data/ui_data.dart';

/// What a work's page says of its files: a few marks beside its meta line
/// (the picture most of its files have, HDR, more than two channels) and
/// the 文件 rows (picture, audio, subtitles, the files themselves). A file
/// whose streams were never read says only its size; nothing is guessed.
({List<String> badges, List<UiFact> rows}) fileSummary(
    List<UiFileFacts> files) {
  if (files.isEmpty) return (badges: const [], rows: const []);
  final known = [
    for (final f in files)
      if (f.known) f
  ];
  final rows = <UiFact>[];
  void add(String label, List<String> perFile) {
    final value = _common(perFile, files.length > 1);
    if (value != null) rows.add((label: label, value: value));
  }

  add('画质', [
    for (final f in known)
      if (_picture(f) case final p?) p
  ]);
  add('音轨', [
    for (final f in known)
      if (f.audio.isNotEmpty) f.audio.map(_audio).join('\n')
  ]);
  add('字幕', [for (final f in known) f.subtitles.isEmpty ? '无' : _subtitles(f)]);
  final size = files.fold<int>(0, (n, f) => n + (f.size ?? 0));
  final containers = {
    for (final f in known)
      if (_container(f.container) case final c?) c
  };
  final devices = <String, int>{};
  for (final f in files) {
    devices.update(f.device ?? '本机', (n) => n + 1, ifAbsent: () => 1);
  }
  rows.add((
    label: '文件',
    value: [
      if (files.length > 1) '${files.length} 个文件',
      if (containers.length == 1) containers.single,
      if (size > 0) '${files.length > 1 ? '共 ' : ''}${_bytes(size)}',
      if (devices.length > 1 || !devices.containsKey('本机'))
        devices.length == 1
            ? '在 ${devices.keys.single}'
            : devices.entries.map((e) => '${e.key} ${e.value}').join('、'),
    ].join(' · ')
  ));

  // The marks are the most common file's.
  final picture = _most([for (final f in known) f]);
  final video = picture?.video;
  final res = video == null ? null : _resolution(video.width, video.height);
  final channels = picture?.audio
      .map((a) => a.channels ?? 0)
      .fold<int>(0, (a, b) => a > b ? a : b);
  return (
    badges: [
      if (res != null) res,
      if (video != null)
        if (_hdr(video.colorSpace, video.colorTransfer) case final hdr?) hdr,
      if (channels != null && channels > 2) _channels(channels),
    ],
    rows: [
      for (final r in rows)
        if (r.value.isNotEmpty) r
    ],
  );
}

/// One value when every file says the same; otherwise each, most common
/// first, with how many files say it.
String? _common(List<String> values, bool many) {
  if (values.isEmpty) return null;
  final counts = <String, int>{};
  for (final v in values) {
    counts.update(v, (n) => n + 1, ifAbsent: () => 1);
  }
  if (counts.length == 1) return counts.keys.single;
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted
      .take(3)
      .map((e) => '${e.key.replaceAll('\n', '、')}（${e.value} 个文件）')
      .join('\n');
}

UiFileFacts? _most(List<UiFileFacts> files) {
  if (files.isEmpty) return null;
  final counts = <String, (int, UiFileFacts)>{};
  for (final f in files) {
    final key = '${_picture(f)}|${f.audio.length}';
    counts.update(key, (e) => (e.$1 + 1, e.$2), ifAbsent: () => (1, f));
  }
  return counts.values.reduce((a, b) => b.$1 > a.$1 ? b : a).$2;
}

String? _picture(UiFileFacts f) {
  final v = f.video;
  if (v == null) return null;
  final depth = switch (v.pixelFormat?.toLowerCase() ?? '') {
    final p when p.contains('12') => '12-bit',
    final p when p.contains('10') || p == 'p010' => '10-bit',
    _ => null,
  };
  final codec = _codec(v.codec);
  return [
    if (_resolution(v.width, v.height) case final r?) r,
    if (codec != null) depth == null ? codec : '$codec $depth',
    if (_hdr(v.colorSpace, v.colorTransfer) case final hdr?) hdr,
  ].join(' · ');
}

String? _resolution(int? width, int? height) {
  final w = width ?? 0, h = height ?? 0;
  if (w <= 0 && h <= 0) return null;
  if (w >= 3200 || h >= 2000) return '4K';
  if (w >= 1800 || h >= 1000) return '1080p';
  if (w >= 1200 || h >= 700) return '720p';
  return h > 0 ? '${h}p' : null;
}

String? _hdr(String? space, String? transfer) {
  final s = '${space ?? ''} ${transfer ?? ''}'.toLowerCase();
  if (s.contains('pq') || s.contains('smpte2084')) return 'HDR';
  if (s.contains('hlg') || s.contains('arib-std-b67')) return 'HLG';
  return null;
}

String? _codec(String? codec) {
  final c = codec?.toLowerCase().trim() ?? '';
  if (c.isEmpty) return null;
  return const {
        'hevc': 'HEVC',
        'h265': 'HEVC',
        'h264': 'H.264',
        'avc': 'H.264',
        'avc1': 'H.264',
        'av1': 'AV1',
        'vp9': 'VP9',
        'vp8': 'VP8',
        'mpeg2video': 'MPEG-2',
        'mpeg4': 'MPEG-4',
        'vc1': 'VC-1',
      }[c] ??
      c.toUpperCase();
}

String _audio(
    ({String? codec, int? channels, String? language, String? title}) a) {
  final codec = switch (a.codec?.toLowerCase() ?? '') {
    'aac' => 'AAC',
    'flac' => 'FLAC',
    'ac3' => 'AC-3',
    'eac3' => 'E-AC-3',
    'truehd' => 'TrueHD',
    'mlp' => 'TrueHD',
    'dts' => 'DTS',
    'opus' => 'Opus',
    'mp3' => 'MP3',
    'vorbis' => 'Vorbis',
    'alac' => 'ALAC',
    final c when c.startsWith('pcm') => 'PCM',
    '' => null,
    final c => c.toUpperCase(),
  };
  final language = _language(a.language);
  final title = a.title?.trim() ?? '';
  return [
    language ?? '未知语言',
    [
      if (codec != null) codec,
      if (a.channels case final n? when n > 0) _channels(n)
    ].join(' '),
    // A short title says what the track is (评论音轨); a long one is a
    // release's own note.
    if (title.isNotEmpty && title.length <= 16 && title != language) title,
  ].where((p) => p.isNotEmpty).join(' · ');
}

String _channels(int n) => switch (n) {
      1 => '单声道',
      2 => '2.0',
      3 => '2.1',
      6 => '5.1',
      8 => '7.1',
      _ => '$n 声道',
    };

String _subtitles(UiFileFacts f) {
  String name(
      ({String? language, String? title, String? format, bool external}) t) {
    final title = t.title ?? '';
    final bilingual = RegExp(r'([简繁])(?:体)?日|日([简繁])').firstMatch(title);
    final lang = bilingual != null
        ? '${bilingual.group(1) ?? bilingual.group(2)}日双语'
        : _language(t.language) ??
            (title.isNotEmpty && title.length <= 12 ? title : '未知语言');
    final format = switch (t.format ?? '') {
      'ass' || 'ssa' => 'ASS',
      'subrip' || 'srt' => 'SRT',
      'hdmv_pgs_subtitle' || 'pgs' || 'sup' => 'PGS',
      'webvtt' || 'vtt' => 'WebVTT',
      'dvd_subtitle' || 'sub' || 'idx' => 'VobSub',
      _ => null,
    };
    return format == null ? lang : '$lang $format';
  }

  String group(bool external) {
    final names = <String>[
      for (final t in f.subtitles)
        if (t.external == external) name(t)
    ];
    final distinct = names.toSet().toList();
    return distinct.isEmpty
        ? ''
        : '${distinct.join('、')}（${external ? '外挂' : '内嵌'}）';
  }

  return [group(false), group(true)].where((g) => g.isNotEmpty).join('\n');
}

String? _language(String? code) {
  final c = code?.trim().toLowerCase() ?? '';
  return switch (c) {
    'zh-hans' || 'chs' || 'zh-cn' || 'sc' => '简体中文',
    'zh-hant' || 'cht' || 'zh-tw' || 'zh-hk' || 'tc' => '繁体中文',
    'zh' || 'chi' || 'zho' => '中文',
    'ja' || 'jpn' => '日语',
    'en' || 'eng' => '英语',
    'ko' || 'kor' => '韩语',
    'fr' || 'fre' || 'fra' => '法语',
    'de' || 'ger' || 'deu' => '德语',
    'es' || 'spa' => '西班牙语',
    'it' || 'ita' => '意大利语',
    'ru' || 'rus' => '俄语',
    'pt' || 'por' => '葡萄牙语',
    'th' || 'tha' => '泰语',
    'vi' || 'vie' => '越南语',
    'id' || 'ind' => '印尼语',
    'ar' || 'ara' => '阿拉伯语',
    _ => null,
  };
}

String? _container(String? format) {
  final f = format?.toLowerCase() ?? '';
  if (f.isEmpty) return null;
  if (f.contains('matroska')) return 'MKV';
  if (f.contains('mp4') || f.contains('mov')) return 'MP4';
  if (f.contains('mpegts')) return 'TS';
  if (f.contains('avi')) return 'AVI';
  if (f.contains('flv')) return 'FLV';
  if (f.contains('webm')) return 'WebM';
  return f.split(',').first.toUpperCase();
}

String _bytes(int n) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = n.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v >= 100 || u == 0 ? v.round() : v.toStringAsFixed(1)} ${units[u]}';
}
