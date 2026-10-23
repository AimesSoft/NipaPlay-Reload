import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/services/media_server_transport.dart';

/// A session's captured server identity, independent of Classic's mutable
/// singleton sync services. Payloads contain actual clock samples.
final class ServerProgress {
  ServerProgress(
      {required this.session,
      required this.baseUrl,
      required this.prefix,
      required this.headers,
      this.selection = const {},
      this.createTransport = MediaServerTransport.fromStoredSettings});
  final PlaybackSession session;
  final String baseUrl, prefix;
  final Map<String, String> headers;
  final JsonMap selection;
  final Future<MediaServerTransport> Function() createTransport;

  Uri _uri(String path) {
    final base = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final included = prefix.isNotEmpty &&
        Uri.parse(base).path.toLowerCase().endsWith(prefix.toLowerCase());
    return Uri.parse('$base${included ? '' : prefix}$path');
  }

  Future<void> send(String kind, JsonMap sample) async {
    final payload = <String, Object?>{
      'ItemId': session.itemId,
      'MediaSourceId': session.mediaSourceId,
      'PlaySessionId': session.playSessionId,
      'PositionTicks': (sample['positionMs'] as int) * 10000,
      'IsPaused': sample['paused'],
      'IsMuted': sample['muted'],
      'VolumeLevel': sample['volume'],
      'PlaybackRate': sample['rate'],
      'CanSeek': true,
      'PlayMethod': session.isTranscoding ? 'Transcode' : 'DirectPlay',
      if (selection['audioIndex'] != null)
        'AudioStreamIndex': selection['audioIndex'],
      if (selection['subtitleIndex'] != null)
        'SubtitleStreamIndex': selection['subtitleIndex'],
    };
    final suffix =
        switch (kind) { 'start' => '', 'stop' => '/Stopped', _ => '/Progress' };
    final transport = await createTransport();
    try {
      final request = http.Request('POST', _uri('/Sessions/Playing$suffix'))
        ..headers.addAll({...headers, 'Content-Type': 'application/json'})
        ..body = jsonEncode(payload);
      final response =
          await transport.send(request, timeout: const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Remote progress HTTP ${response.statusCode}');
      }
    } finally {
      transport.close();
    }
  }

  Future<void> stopTranscoding() async {
    if (!session.isTranscoding) return;
    final transport = await createTransport();
    try {
      final authorization = headers.entries
          .where((entry) => const {'authorization', 'x-emby-authorization'}
              .contains(entry.key.toLowerCase()))
          .map((entry) => entry.value)
          .join(',');
      final deviceId = RegExp(r'DeviceId="([^"]+)"', caseSensitive: false)
              .firstMatch(authorization)
              ?.group(1) ??
          Uri.tryParse(session.streamUrl)?.queryParameters['DeviceId'];
      final uri = _uri('/Videos/ActiveEncodings').replace(queryParameters: {
        if (deviceId != null) 'DeviceId': deviceId,
        if (session.playSessionId != null)
          'PlaySessionId': session.playSessionId!,
      });
      final response = await transport.send(
          http.Request('DELETE', uri)..headers.addAll(headers),
          timeout: const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Stop transcoding HTTP ${response.statusCode}');
      }
    } finally {
      transport.close();
    }
  }
}
