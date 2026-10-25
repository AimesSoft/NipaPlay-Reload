import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';

/// A device of the account that runs, or last ran, Nipa.
final class NipaPeer {
  const NipaPeer({
    required this.id,
    required this.name,
    required this.online,
    required this.runs,
    required this.busy,
    this.reason,
  });

  final String id, name;

  /// The device answers now.
  final bool online;

  /// Nipa runs there (as it last said, for a device that does not answer).
  final bool runs;
  final bool busy;
  final String? reason;

  /// Nipa there can be spoken with now.
  bool get usable => online && runs;
}

/// Which device's Nipa serves this device. A device that cannot run Nipa (an
/// iPad) has no Nipa of its own; its person picks a device of the account
/// whose Nipa runs, and the conversation panel is a conversation with her.
/// The choice is this device's own, kept in its folder; nothing sets it for
/// the account.
final class NipaPeers {
  NipaPeers(
      {required this.root,
      required this.devices,
      required Stream<void> hostChanges}) {
    hostChanges.listen((_) => _notify());
  }

  /// Where this device keeps its own choice.
  final Directory root;

  /// The other devices and whether Nipa runs on each (`MeshRuntime.agentDevices`).
  final Future<List<JsonMap>> Function() devices;
  final _changes = StreamController<void>.broadcast();

  /// Fires when the choice, or what is known of the devices, changes.
  Stream<void> get changes => _changes.stream;

  File get _file => File('${root.path}/nipa-peer.json');
  String? _chosen;
  bool _loaded = false;
  List<NipaPeer> _peers = const [];

  /// Read once before the first use.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (await _file.exists()) {
        final saved = jsonDecode(await _file.readAsString());
        if (saved is Map && saved['deviceId'] is String) {
          _chosen = saved['deviceId'] as String;
          _chosenName = saved['name'] as String?;
        }
      }
    } on FormatException {
      // A damaged choice is no choice.
    }
    _notify();
  }

  /// The device chosen, or null while none is.
  String? get chosen => _chosen;

  /// Devices that run Nipa, as last read by [refresh], plus the chosen one
  /// even when it does not.
  List<NipaPeer> get peers => _peers;

  NipaPeer? get chosenPeer =>
      _peers.where((peer) => peer.id == _chosen).firstOrNull;

  /// The chosen device's name as last known, even once it is gone.
  String? _chosenName;
  String? get chosenName => chosenPeer?.name ?? _chosenName;

  Future<void> choose(String? deviceId) async {
    await load();
    _chosen = deviceId;
    _chosenName = _peers.where((p) => p.id == deviceId).firstOrNull?.name;
    if (deviceId == null) {
      if (await _file.exists()) await _file.delete();
    } else {
      await root.create(recursive: true);
      final pending = File('${_file.path}.pending');
      await pending.writeAsString(
          jsonEncode({'deviceId': deviceId, 'name': _chosenName}),
          flush: true);
      await pending.rename(_file.path);
    }
    _notify();
  }

  /// Asks the devices (the settings page opens; the mesh says something
  /// changed).
  Future<void> refresh() async {
    await load();
    final List<JsonMap> listed;
    try {
      listed = await devices();
    } on Failure {
      return;
    }
    final found = <NipaPeer>[];
    for (final device in listed) {
      final agent = device['agent'];
      final runs = agent is Map && agent['runs'] == true;
      final id = device['deviceId'] as String;
      if (!runs && id != _chosen) continue;
      found.add(NipaPeer(
          id: id,
          name: (device['name'] as String?) ?? '设备',
          online: device['online'] == true,
          runs: runs,
          busy: agent is Map && agent['busy'] == true,
          reason: agent is Map ? agent['reason'] as String? : null));
    }
    _peers = found;
    final name = chosenPeer?.name;
    if (name != null && name != _chosenName) _chosenName = name;
    _notify();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> close() => _changes.close();
}
