import 'dart:async';
import 'dart:convert';
import 'dart:io';

String? headlessFfprobe;

Future<int?> probeMediaDuration(String path) async =>
    (await probeMediaInfo(path))['durationMs'] as int?;

/// Duration and subtitle streams from ffprobe, in the shape the Flutter
/// probe gives; without ffprobe nothing is known.
Future<Map<String, Object?>> probeMediaInfo(String path) async {
  final executable = headlessFfprobe;
  if (executable == null) return {'durationMs': null};
  final process = await Process.start(executable, [
    '-v',
    'error',
    '-show_entries',
    'format=duration,format_name,bit_rate:stream=index,codec_type,codec_name,width,height,avg_frame_rate,pix_fmt,bit_rate,sample_rate,channels,color_space:stream_tags=language,title',
    '-of',
    'json',
    path
  ]);
  final output = utf8.decoder.bind(process.stdout).join();
  final errors = process.stderr.drain<void>();
  int code;
  try {
    code = await process.exitCode.timeout(const Duration(seconds: 15));
  } on TimeoutException {
    process.kill();
    await process.exitCode;
    await output;
    await errors;
    return {'durationMs': null};
  }
  final text = await output;
  await errors;
  if (code != 0) return {'durationMs': null};
  final json = jsonDecode(text) as Map;
  final duration = (json['format'] as Map?)?['duration'];
  final streams = [
    for (final s in (json['streams'] as List? ?? const []).whereType<Map>())
      if (s['codec_type'] == 'subtitle') s
  ];
  int? positive(Object? value) {
    final n = int.tryParse('$value');
    return n != null && n > 0 ? n : null;
  }

  double? fps(Object? value) {
    final parts = '$value'.split('/');
    final a = double.tryParse(parts.first),
        b = parts.length == 2 ? double.tryParse(parts.last) : 1;
    return a != null && b != null && b > 0 && a > 0 ? a / b : null;
  }

  final all = (json['streams'] as List? ?? const []).whereType<Map>();
  return {
    'technical': {
      'container': (json['format'] as Map?)?['format_name'],
      'bitrate': positive((json['format'] as Map?)?['bit_rate']),
      'video': [
        for (final s in all.where((s) => s['codec_type'] == 'video'))
          {
            'codec': s['codec_name'],
            'width': s['width'],
            'height': s['height'],
            'fps': fps(s['avg_frame_rate']),
            'pixelFormat': s['pix_fmt'],
            'bitrate': positive(s['bit_rate']),
            'colorSpace': s['color_space'],
          }
      ],
      'audio': [
        for (final s in all.where((s) => s['codec_type'] == 'audio'))
          {
            'codec': s['codec_name'],
            'channels': s['channels'],
            'sampleRate': positive(s['sample_rate']),
            'bitrate': positive(s['bit_rate']),
            'language': (s['tags'] as Map?)?['language'],
            'title': (s['tags'] as Map?)?['title'],
          }
      ],
    },
    'durationMs':
        duration == null ? null : (double.parse('$duration') * 1000).round(),
    'subtitles': [
      for (final (i, s) in streams.indexed)
        {
          'index': i,
          'streamIndex': s['index'],
          'language': (s['tags'] as Map?)?['language'] ?? 'und',
          'title': (s['tags'] as Map?)?['title'],
          'format': s['codec_name'],
        }
    ],
  };
}
