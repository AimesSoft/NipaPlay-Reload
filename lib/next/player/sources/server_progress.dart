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
      this.createTransport = MediaServerTransport.fromStoredSettings});
  final PlaybackSession session;
  final String baseUrl, prefix;
  final Map<String, String> headers;
  final Future<MediaServerTransport> Function() createTransport;

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
    };
    final suffix =
        switch (kind) { 'start' => '', 'stop' => '/Stopped', _ => '/Progress' };
    final transport = await createTransport();
    try {
      final request = http.Request(
          'POST',
          Uri.parse(
              '${baseUrl.replaceFirst(RegExp(r"/+$"), "")}$prefix/Sessions/Playing$suffix'))
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
      final uri = Uri.parse('${baseUrl.replaceFirst(RegExp(r"/+$"), "")}'
              '$prefix/Videos/ActiveEncodings')
          .replace(queryParameters: {
        if (session.playSessionId != null)
          'PlaySessionId': session.playSessionId!,
      });
      await transport.send(http.Request('DELETE', uri)..headers.addAll(headers),
          timeout: const Duration(seconds: 5));
    } finally {
      transport.close();
    }
  }
}
