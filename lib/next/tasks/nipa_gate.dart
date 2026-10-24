import 'dart:async';

import 'package:nipa_harness/nipa_harness.dart';

/// Nipa runs only while Next's interface is open: in Classic there is no
/// Nipa (user decision D1, docs/next/design/player-core.md). Her own work
/// waits for it to open, without polling.
final class NipaGate {
  Completer<void>? _closed = Completer<void>();

  bool get open => _closed == null;
  Future<void> get opened => _closed?.future ?? Future.value();

  void set(bool open) {
    if (open) {
      _closed?.complete();
      _closed = null;
    } else {
      _closed ??= Completer<void>();
    }
  }
}

/// Task types that are Nipa's own work, or a question she has NipaPlay ask
/// the person: a helper turn, a task handed to another device's Nipa, a
/// program she runs, a hook run, a deletion or setting she asked for.
const nipaTaskTypes = {
  'agent.helper',
  'agent.delegate',
  'program',
  'harness.hook',
  'disk_deletion',
  'setting_consent',
};

/// Runs [inner] once [gate] is open (or the task is asked to stop): left
/// from a Next session, such a task waits through Classic.
final class NipaGatedExecutor implements JobExecutor {
  NipaGatedExecutor(this.inner, this.gate);
  final JobExecutor inner;
  final NipaGate gate;

  @override
  String get type => inner.type;

  Future<void> _ready(JobContext context) =>
      gate.open ? Future.value() : Future.any([gate.opened, context.stopRequested]);

  @override
  Future<void> execute(JobContext context) async {
    await _ready(context);
    await inner.execute(context);
  }

  @override
  Future<void> recover(JobContext context) async {
    await _ready(context);
    await inner.recover(context);
  }
}
