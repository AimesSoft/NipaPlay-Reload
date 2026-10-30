import 'dart:async';

import 'package:nipa_harness/nipa_harness.dart';

import '../../downloads/qbittorrent_hub.dart';
import '../../next_core.dart';

/// One qBittorrent the person added, as the settings page shows it.
final class UiDownloader {
  const UiDownloader({
    required this.id,
    required this.name,
    required this.address,
    required this.local,
    required this.hasLogin,
    this.online,
    this.version,
  });
  final String id, name, address;

  /// It runs on this computer (its paths are paths here).
  final bool local;
  final bool hasLogin;

  /// Whether it answered just now; null while that is not known.
  final bool? online;
  final String? version;

  /// “192.168.1.5:8080”.
  String get place {
    final uri = Uri.tryParse(address);
    return uri == null || uri.host.isEmpty
        ? address
        : '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
  }
}

/// The qBittorrents of 设置 › 下载. The GUI and authorized download.backends
/// actions share the same hub; passwords are never returned by the Actions.
abstract interface class NextDownloaders {
  Stream<void> get changes;

  /// What is configured, each asked whether it answers.
  Future<List<UiDownloader>> list();

  /// The saved user name ('' when there is none); never the password.
  Future<String> username(String id);

  /// Adds one, or changes [id]. A [password] replaces the saved login; both
  /// empty remove it; [username] alone changes the name only.
  Future<void> save({
    String? id,
    required String name,
    required String address,
    required bool local,
    String? username,
    String? password,
  });

  Future<void> remove(String id);
}

final class CoreDownloaders implements NextDownloaders {
  CoreDownloaders(this.core);
  final NextCore core;

  Future<QbittorrentHub> _hub() async {
    await core.ready;
    final hub = core.downloads.qbittorrent;
    if (hub == null) {
      throw const Failure(
          FailureCode.unavailable, 'Downloaders are not available here.');
    }
    await hub.load();
    return hub;
  }

  @override
  Stream<void> get changes async* {
    final hub = await _hub();
    yield* hub.changes;
  }

  @override
  Future<List<UiDownloader>> list() async {
    final hub = await _hub();
    return Future.wait([
      for (final entry in hub.entries)
        () async {
          final facts = await hub.backend(entry.id)?.status();
          return UiDownloader(
            id: entry.id,
            name: entry.name,
            address: entry.address,
            local: entry.local,
            hasLogin: entry.hasLogin,
            online: facts?['online'] as bool?,
            version: facts?['version'] as String?,
          );
        }()
    ]);
  }

  @override
  Future<String> username(String id) async =>
      await (await _hub()).username(id) ?? '';

  @override
  Future<void> save({
    String? id,
    required String name,
    required String address,
    required bool local,
    String? username,
    String? password,
  }) async {
    await (await _hub()).save(
        id: id,
        name: name,
        address: address,
        local: local,
        username: username,
        password: password);
    // The runtime asks the new one at its next round; ask now so a task
    // waiting on it does not wait for that.
    unawaited(core.downloads.refresh().catchError((Object _) {}));
  }

  @override
  Future<void> remove(String id) async => (await _hub()).remove(id);
}
