/// Evidence from the wire. No timeout here decides what the user should do.
final class ChatLiveness {
  DateTime? startedAt, lastEventAt, lastContentAt, endedAt;
  String? turnId, status, latestError;
  int eventCount = 0, contentCount = 0;
  int reasoningDeltaCount = 0;

  void starting(DateTime now) {
    startedAt = now;
    lastEventAt = null;
    lastContentAt = null;
    endedAt = null;
    turnId = null;
    status = 'starting';
    latestError = null;
    eventCount = contentCount = 0;
    reasoningDeltaCount = 0;
  }

  void observe(Map<String, dynamic> message, DateTime now) {
    final method = message['method'];
    final params = message['params'] as Map? ?? {};
    if (method == 'turn/started') {
      if (startedAt == null || endedAt != null) starting(now);
      turnId = params['turn']['id'] as String;
      status = params['turn']['status'] as String? ?? 'inProgress';
    }
    lastEventAt = now;
    eventCount++;
    if (const {
          'item/agentMessage/delta',
          'item/commandExecution/outputDelta',
          'item/fileChange/outputDelta',
        }.contains(method) &&
        (params['delta'] as String? ?? '').isNotEmpty) {
      lastContentAt = now;
      contentCount++;
    }
    if (method == 'item/reasoning/textDelta' ||
        method == 'item/reasoning/summaryTextDelta') {
      reasoningDeltaCount++;
    }
    if (method == 'item/completed') {
      final item = params['item'] as Map;
      final text = switch (item['type']) {
        'agentMessage' => item['text'] as String? ?? '',
        'commandExecution' => item['aggregatedOutput'] as String? ?? '',
        _ => '',
      };
      if (text.isNotEmpty) {
        lastContentAt = now;
        contentCount++;
      }
    }
    if (method == 'error') {
      latestError = params['error']['message'] as String;
    } else if (message['error'] case final Map error) {
      latestError = error['message'] as String;
    }
    if (method == 'turn/completed') {
      final turn = params['turn'] as Map;
      turnId = turn['id'] as String;
      status = turn['status'] as String;
      endedAt = now;
      if (turn['error'] case final Map error) {
        latestError = error['message'] as String;
      }
    }
  }

  Map<String, Object?> snapshot(DateTime now) => {
        'turnId': turnId,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'endedAt': endedAt?.toUtc().toIso8601String(),
        'lastEventAt': lastEventAt?.toUtc().toIso8601String(),
        'lastContentAt': lastContentAt?.toUtc().toIso8601String(),
        'status': status,
        'elapsedMs': startedAt == null
            ? null
            : (endedAt ?? now).difference(startedAt!).inMilliseconds,
        'lastEventAgoMs': (lastEventAt ?? startedAt) == null
            ? null
            : now.difference(lastEventAt ?? startedAt!).inMilliseconds,
        'lastContentAgoMs': (lastContentAt ?? startedAt) == null
            ? null
            : now.difference(lastContentAt ?? startedAt!).inMilliseconds,
        'hasContent': lastContentAt != null,
        'eventCount': eventCount,
        'contentCount': contentCount,
        'reasoningDeltaCount': reasoningDeltaCount,
        'latestError': latestError,
      };
}
