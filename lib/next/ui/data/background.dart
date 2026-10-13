import 'package:nipa_harness/nipa_harness.dart';

import 'gui_calls.dart';

/// Background work as a whole: `task.control` to pause, resume or cancel
/// any of it together, `task.resources` for how much runs at once, and
/// the `tasks.*Concurrency` settings to change that.
final class NextBackground {
  NextBackground(this.calls);
  final GuiCalls calls;

  /// Sends [command] (`pause`, `resume` or `cancel`) to each task; what
  /// each one did with it.
  Future<List<UiControlResult>> control(
      Iterable<String> taskIds, String command) async {
    final ids = taskIds.toList();
    if (ids.isEmpty) return const [];
    final r = await calls.call('task.control', {
      'entries': [
        for (final id in ids) {'jobId': id, 'command': command}
      ]
    });
    return [
      for (final row in (r['results'] as List).cast<Map>())
        UiControlResult(
          taskId: '${row['jobId']}',
          accepted: row['accepted'] == true,
          supported: row['controlSupported'] != false,
        ),
    ];
  }

  /// How much of each kind of work runs at once, and how much waits.
  Future<List<UiPool>> pools() async {
    final r = await calls.call('task.resources', {});
    final pools = <String, UiPool>{};
    for (final p in (r['pools'] as List).cast<Map>()) {
      final kind = UiPool.kindOf('${p['type']}');
      if (kind == null) continue;
      final pool = UiPool(
        kind: kind,
        capacity: (p['capacity'] as num?)?.toInt() ?? 1,
        active: (p['active'] as num?)?.toInt() ?? 0,
        queued: (p['queued'] as num?)?.toInt() ?? 0,
      );
      // Classic's scanner and Next's indexer are both 扫描; the
      // changeable one is Next's.
      final had = pools[kind];
      pools[kind] = had == null
          ? pool
          : UiPool(
              kind: kind,
              capacity: p['type'] == 'media.scan' ? pool.capacity : had.capacity,
              active: had.active + pool.active,
              queued: had.queued + pool.queued);
    }
    return [
      for (final kind in UiPool.kinds)
        if (pools[kind] case final pool?) pool
    ];
  }

  /// Changes how many of [kind] run at once (`settings.set`).
  Future<void> setCapacity(String kind, int value) => calls.call(
      'settings.set', {'key': 'tasks.${kind}Concurrency', 'value': value});

  /// A task's question, when it waits for the person (`task.get`).
  Future<Decision?> question(String taskId) async {
    final job = (await calls.call('task.get', {'jobId': taskId}))['job'] as Map;
    final decision = job['decision'];
    return decision is Map ? decisionOf(decision) : null;
  }
}

final class UiControlResult {
  const UiControlResult(
      {required this.taskId, required this.accepted, this.supported = true});
  final String taskId;
  final bool accepted;

  /// The task can be controlled this way at all.
  final bool supported;
}

/// A kind of background work and how much of it runs at once.
final class UiPool {
  const UiPool(
      {required this.kind,
      required this.capacity,
      this.active = 0,
      this.queued = 0});

  /// `scan`, `metadata` or `helper` (the `tasks.*Concurrency` settings).
  final String kind;
  final int capacity;
  final int active;
  final int queued;

  static const kinds = ['scan', 'metadata', 'helper'];

  static String? kindOf(String type) => switch (type) {
        'media.scan' || 'media.scan_classic' => 'scan',
        'media.metadata.refresh' => 'metadata',
        'agent.helper' => 'helper',
        _ => null,
      };

  String get title => switch (kind) {
        'scan' => '扫描',
        'metadata' => '识别',
        _ => '帮手',
      };
}
