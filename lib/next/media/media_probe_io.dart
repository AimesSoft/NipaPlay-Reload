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
    'format=duration:stream=index,codec_type,codec_name:stream_tags=language,title',
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
  return {
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
