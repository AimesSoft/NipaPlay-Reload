import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// What a file's streams are, as its scan read them: the picture, each
/// audio track and each subtitle (in the file or beside it). Built where the
/// file is (this device's database, or another device's catalogue record),
/// small whatever the file holds.
///
/// [probe] is the file's `probe` attribute (`MediaService.probe`), [tracks]
/// the subtitle library's tracks of the file.
JsonMap fileFactsOf(Map? probe, Iterable<Map> tracks) {
  final technical = probe?['technical'];
  String? text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;
  int? whole(Object? v) => v is num && v > 0 ? v.round() : null;
  return {
    if (whole(probe?['size']) case final size?) 'size': size,
    if (whole(probe?['durationMs']) case final ms?) 'durationMs': ms,
    if (technical is Map) ...{
      'known': true,
      if (text(technical['container']) case final c?) 'container': c,
      if (whole(technical['bitrate']) case final b?) 'bitrate': b,
      if ((technical['video'] as List?)?.whereType<Map>().firstOrNull
          case final v?)
        'video': {
          if (text(v['codec']) case final c?) 'codec': c,
          if (whole(v['width']) case final w?) 'width': w,
          if (whole(v['height']) case final h?) 'height': h,
          if (v['fps'] is num && (v['fps'] as num) > 0) 'fps': v['fps'],
          if (text(v['pixelFormat']) case final p?) 'pixelFormat': p,
          if (text(v['colorSpace']) case final s?) 'colorSpace': s,
          if (text(v['colorTransfer']) case final t?) 'colorTransfer': t,
        },
      'audio': [
        for (final a
            in (technical['audio'] as List? ?? const []).whereType<Map>())
          {
            if (text(a['codec']) case final c?) 'codec': c,
            if (whole(a['channels']) case final n?) 'channels': n,
            if (text(a['language']) case final l?) 'language': l,
            if (text(a['title']) case final t?) 'title': t,
          },
      ],
    },
    'subtitles': [
      for (final t in tracks)
        if (t['available'] != false)
          {
            if (text(t['language']) case final l?) 'language': l,
            // A file beside the video is named by its file name: not a title.
            if (t['origin'] == 'embedded')
              if (text(t['title']) case final title?) 'title': title,
            if (text(t['format']) case final f?) 'format': f.toLowerCase(),
            'external': t['origin'] != 'embedded',
          },
    ],
  };
}

/// Whether [probe] was read before streams were kept (older scans know only
/// a file's size and length): such a file is read again when its page asks.
bool lacksStreams(Map? probe) =>
    probe != null && probe['technical'] is! Map && probe['size'] != null;

/// The files of [workId] on this device, from its database: each file's
/// facts ([fileFactsOf]) with its file id; for a work this device holds
/// without the device network.
Future<List<JsonMap>> localWorkFiles(DatabaseExecutor db, String workId) async {
  final rows = await db.rawQuery(
    'SELECT DISTINCT f.id, f.attributes, s.facts FROM media_entities f '
    'JOIN media_file_episodes fe ON fe.file_id=f.id '
    'JOIN media_entities e ON e.id=fe.episode_id '
    'JOIN media_entities r ON r.id=e.parent_id '
    'LEFT JOIN file_subtitles s ON s.file_id=f.id '
    'WHERE r.parent_id=?',
    [workId],
  );
  return [
    for (final row in rows)
      () {
        final attributes =
            jsonDecode(row['attributes'] as String) as Map? ?? const {};
        final facts = row['facts'] == null
            ? const <String, Object?>{}
            : jsonDecode(row['facts'] as String) as Map;
        final probe = attributes['probe'] as Map?;
        return {
          ...fileFactsOf(
            probe,
            (facts['tracks'] as List? ?? const []).whereType<Map>(),
          ),
          'fileId': row['id'],
          if (lacksStreams(probe)) 'unread': true,
        };
      }(),
  ];
}

/// A file of a work as its page tells of it ([fileFactsOf]).
final class UiFileFacts {
  const UiFileFacts({
    this.size,
    this.container,
    this.video,
    this.audio = const [],
    this.subtitles = const [],
    this.device,
    this.known = false,
  });

  final int? size;
  final String? container;
  final ({
    String? codec,
    int? width,
    int? height,
    double? fps,
    String? pixelFormat,
    String? colorSpace,
    String? colorTransfer,
  })? video;
  final List<({String? codec, int? channels, String? language, String? title})>
      audio;
  final List<({String? language, String? title, String? format, bool external})>
      subtitles;

  /// The other device it is on; null on this one.
  final String? device;

  /// Whether its streams were read (a file scanned before they were kept
  /// knows only its size until it is read again).
  final bool known;

  static UiFileFacts fromJson(Map json) {
    final video = json['video'];
    return UiFileFacts(
      size: json['size'] as int?,
      container: json['container'] as String?,
      known: json['known'] == true,
      device: json['device'] as String?,
      video: video is Map
          ? (
              codec: video['codec'] as String?,
              width: video['width'] as int?,
              height: video['height'] as int?,
              fps: (video['fps'] as num?)?.toDouble(),
              pixelFormat: video['pixelFormat'] as String?,
              colorSpace: video['colorSpace'] as String?,
              colorTransfer: video['colorTransfer'] as String?,
            )
          : null,
      audio: [
        for (final a in (json['audio'] as List? ?? const []).cast<Map>())
          (
            codec: a['codec'] as String?,
            channels: a['channels'] as int?,
            language: a['language'] as String?,
            title: a['title'] as String?,
          )
      ],
      subtitles: [
        for (final t in (json['subtitles'] as List? ?? const []).cast<Map>())
          (
            language: t['language'] as String?,
            title: t['title'] as String?,
            format: t['format'] as String?,
            external: t['external'] == true,
          )
      ],
    );
  }
}

/// A work's files ([UiFileFacts]); [reading] while files scanned before
/// streams were kept are being read again.
final class UiWorkFiles {
  const UiWorkFiles(this.files, {this.reading = false});
  final List<UiFileFacts> files;
  final bool reading;
  static const empty = UiWorkFiles([]);
}
