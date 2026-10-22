import 'package:nipa_harness/nipa_harness.dart';

import '../state/change_history.dart';

/// Describes who submitted a task, from the real [Invocation] in force at
/// submission. Nothing here is inferred from titles or inputs.
final class JobOrigins {
  /// Thread currently attributed to an invocation origin (conversation host).
  String? Function(String origin)? threadFor;

  /// Reads a task, to say which event or schedule a hook run belongs to.
  Future<Job> Function(String jobId)? lookup;

  Future<JsonMap?> of(String type, JsonMap details) async {
    if (type == 'harness.hook') {
      return {
        'kind': 'host',
        'trigger': details['event'] == 'schedule' ? 'schedule' : 'hook',
        if (details['event'] is String) 'event': details['event'],
        if (details['event'] == 'schedule') 'scheduleId': details['objectId'],
      };
    }
    final origin = BodyChanges.invocation?.origin;
    if (origin == null) return {'kind': 'host'};
    return describe(origin);
  }

  Future<JsonMap> describe(String origin) async {
    String rest(String prefix) => origin.substring(prefix.length);
    JsonMap thread(JsonMap base) {
      final id = threadFor?.call(origin);
      return {...base, if (id != null) 'threadId': id};
    }

    if (origin == 'gui') return {'kind': 'user'};
    if (origin.startsWith('harness_cli:chat:')) {
      return thread(
          {'kind': 'conversation', 'sessionId': rest('harness_cli:chat:')});
    }
    if (origin.startsWith('harness_cli:helper:')) {
      return thread(
          {'kind': 'subagent', 'helperJobId': rest('harness_cli:helper:')});
    }
    if (origin.startsWith('codex_native:')) {
      return {'kind': 'subagent', 'threadId': rest('codex_native:')};
    }
    if (origin.startsWith('hook:')) {
      final hookJobId = rest('hook:');
      JsonMap? run;
      try {
        final job = await lookup?.call(hookJobId);
        if (job != null) {
          run = {
            if (job.details['event'] is String) 'event': job.details['event'],
            if (job.input['scheduleId'] is String)
              'scheduleId': job.input['scheduleId'],
          };
        }
      } on Failure {
        // The hook task is gone; the id alone stays.
      }
      return {'kind': 'script', 'hookJobId': hookJobId, ...?run};
    }
    if (origin == 'harness_cli') return {'kind': 'cli'};
    if (origin.startsWith('mesh:')) {
      return {'kind': 'device', 'deviceId': rest('mesh:')};
    }
    if (origin == 'mcp') return {'kind': 'mcp'};
    if (origin == 'application' ||
        origin.startsWith('application:') ||
        origin == 'task_engine' ||
        origin == 'migration') {
      return {'kind': 'host', 'source': origin};
    }
    return {'kind': 'other', 'source': origin};
  }
}
