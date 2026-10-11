import 'dart:convert';
import 'dart:io';

import '../../lib/next/chat/liveness.dart';

// Offline experiment, without connecting to a provider or touching its rollout.
Future<void> main(List<String> args) async {
  final evidence = ChatLiveness();
  DateTime? previousEvent, contentStart;
  var events = 0, longEventGaps = 0;
  var maxEventGapSeconds = 0;
  final contentPauses = <Map<String, Object?>>[];
  final reasoning = <String, DateTime>{};
  final thinking = <Map<String, Object?>>[];
  await for (final line in File(args.single)
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    final row = jsonDecode(line) as Map;
    final time = DateTime.parse('2026-10-11T${row['t']}');
    final message = Map<String, dynamic>.from(row['m'] as Map);
    if (previousEvent != null) {
      final gap = time.difference(previousEvent).inSeconds;
      if (gap > maxEventGapSeconds) maxEventGapSeconds = gap;
    }
    if (previousEvent != null &&
        time.difference(previousEvent).inSeconds >= 180) {
      longEventGaps++;
      print(jsonEncode({
        'kind': 'eventPause',
        'at': time.toIso8601String(),
        'evidence': evidence.snapshot(time)
      }));
    }
    final before = evidence.lastContentAt;
    evidence.observe(message, time);
    contentStart ??= evidence.startedAt;
    if (evidence.lastContentAt != before) {
      if (contentStart != null &&
          time.difference(contentStart).inSeconds >= 180) {
        contentPauses.add({
          'from': contentStart.toIso8601String(),
          'to': time.toIso8601String(),
          'seconds': time.difference(contentStart).inSeconds,
          // Evidence immediately before the next content arrives.
          'lastEventAgoSeconds': previousEvent == null
              ? null
              : time.difference(previousEvent).inSeconds,
          'latestError': evidence.latestError,
          'reasoningDeltasSoFar': evidence.reasoningDeltaCount
        });
      }
      contentStart = time;
    }
    final method = message['method'];
    final params = message['params'] as Map? ?? {};
    if (method == 'item/started' && params['item']['type'] == 'reasoning') {
      reasoning[params['item']['id'] as String] = time;
    }
    if (method == 'item/completed' && params['item']['type'] == 'reasoning') {
      final start = reasoning.remove(params['item']['id']);
      if (start != null && time.difference(start).inSeconds >= 180) {
        thinking.add({
          'from': start.toIso8601String(),
          'to': time.toIso8601String(),
          'seconds': time.difference(start).inSeconds
        });
      }
    }
    previousEvent = time;
    events++;
  }
  print(jsonEncode({
        'events': events,
        'maxEventGapSeconds': maxEventGapSeconds,
    'eventPausesAtLeast180s': longEventGaps,
    'contentPausesAtLeast180s': contentPauses,
    'longReasoningItems': thinking,
    'finalEvidence': evidence.snapshot(previousEvent!)
  }));
  if (contentStart != null &&
      previousEvent.difference(contentStart).inSeconds >= 180) {
    print(jsonEncode({
      'kind': 'contentPauseAtLogEnd',
      'from': contentStart.toIso8601String(),
      'to': previousEvent.toIso8601String(),
      'evidence': evidence.snapshot(previousEvent)
    }));
  }
  print(jsonEncode({
    'kind': 'silenceAfterLogEnds',
    'evidence': evidence.snapshot(previousEvent.add(const Duration(minutes: 3)))
  }));
}
