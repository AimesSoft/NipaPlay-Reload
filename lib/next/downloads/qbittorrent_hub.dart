import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_vault.dart';

import 'download_backend.dart';
import 'qbittorrent_download_backend.dart';

/// One configured qBittorrent: what the person typed, without the login.
final class QbittorrentEntry implements JsonEncodable {
  const QbittorrentEntry(
      {required this.id,
      required this.name,
      required this.address,
      required this.local,
      this.hasLogin = false});
  final String id, name, address;

  /// qBittorrent runs on this computer: its paths are paths here.
  final bool local;

  /// A login is saved in the vault (never its content).
  final bool hasLogin;

  factory QbittorrentEntry.fromJson(JsonMap json) => QbittorrentEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      local: json['local'] as bool? ?? false,
      hasLogin: json['hasLogin'] as bool? ?? false);
  @override
  JsonMap toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'local': local,
        'hasLogin': hasLogin,
      };
}

/// The qBittorrents the person has added. Names, addresses and whether the
/// qBittorrent is on this computer live in a JSON file in the data root; the
/// login (user name and password together) only in the credential vault, under
/// a reference nothing the agent can call ever reads. Plain Dart: the
/// headless host uses it too.
final class QbittorrentHub {
  QbittorrentHub(
      {required this.file,
      required this.vault,
      this.clientFactory,
      this.metadataWait = const Duration(seconds: 60)});
  final File file;
  final CredentialVault vault;
  final HttpClient Function()? clientFactory;
  final Duration metadataWait;

  /// A configured downloader appeared, changed or went away.
  void Function(QbittorrentDownloadBackend backend)? onRegistered;
  void Function(DownloadBackendRef ref)? onRemoved;

  final _entries = <String, QbittorrentEntry>{};
  final _backends = <String, QbittorrentDownloadBackend>{};
  final _changes = StreamController<void>.broadcast();
  Future<void>? _loaded;
  Future<void> _serial = Future.value();

  Stream<void> get changes => _changes.stream;
  List<QbittorrentEntry> get entries => List.unmodifiable(_entries.values);
  Iterable<QbittorrentDownloadBackend> get backends => _backends.values;
  QbittorrentDownloadBackend? backend(String id) => _backends[id];

  static CredentialRef reference(String id) => CredentialRef('qbittorrent', id);

  Future<void> load() => _loaded ??= _load();

  Future<void> _load() async {
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      for (final raw in ((decoded as Map)['entries'] as List).cast<Map>()) {
        final entry = QbittorrentEntry.fromJson(raw.cast<String, Object?>());
        _entries[entry.id] = entry;
        _backends[entry.id] = _build(entry);
      }
    } on FormatException {
      // An unreadable file is the same as none: nothing is configured.
    } on TypeError {
      _entries.clear();
      _backends.clear();
    }
  }

  QbittorrentDownloadBackend _build(QbittorrentEntry entry) =>
      QbittorrentDownloadBackend(
        id: entry.id,
        name: entry.name,
        address: QbittorrentDownloadBackend.parseAddress(entry.address),
        local: entry.local,
        clientFactory: clientFactory,
        metadataWait: metadataWait,
        login: entry.hasLogin ? () => _login(entry.id) : null,
      );

  Future<QbittorrentLogin?> _login(String id) async {
    final secret = await vault.read(reference(id));
    if (secret == null) return null;
    try {
      final decoded = jsonDecode(secret) as Map;
      return QbittorrentLogin(
          decoded['username'] as String, decoded['password'] as String);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> _save() async {
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(
        jsonEncode({
          'entries': [for (final entry in _entries.values) entry.toJson()]
        }),
        flush: true);
    await pending.rename(file.path);
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final run = _serial.then((_) => action());
    _serial = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  String _newId(String name) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stem = base.isEmpty ? 'qbittorrent' : base;
    var id = stem;
    for (var n = 2; _entries.containsKey(id); n++) {
      id = '$stem-$n';
    }
    return id;
  }

  /// Adds a qBittorrent, or changes [id]. [username] and [password] replace
  /// the saved login when [password] is given; with both null the login stays
  /// as it was; an empty [username] and [password] remove it.
  Future<QbittorrentEntry> save(
          {String? id,
          required String name,
          required String address,
          required bool local,
          String? username,
          String? password}) =>
      _locked(() async {
        await load();
        final clean = name.trim();
        if (clean.isEmpty) {
          throw const Failure(FailureCode.invalidInput, 'Give it a name.');
        }
        final uri = QbittorrentDownloadBackend.parseAddress(address);
        final previous = id == null ? null : _entries[id];
        if (id != null && previous == null) {
          throw const Failure(
              FailureCode.notFound, 'No such qBittorrent is configured.');
        }
        final entryId = id ?? _newId(clean);
        var hasLogin = previous?.hasLogin ?? false;
        if (password != null || username != null) {
          final user = (username ?? '').trim();
          final secret = password ?? '';
          if (user.isEmpty && secret.isEmpty) {
            await vault.delete(reference(entryId));
            hasLogin = false;
          } else if (password != null) {
            await vault.write(reference(entryId),
                jsonEncode({'username': user, 'password': secret}));
            hasLogin = true;
          } else if (previous?.hasLogin == true) {
            // A new user name with the saved password.
            final saved = await _login(entryId);
            await vault.write(
                reference(entryId),
                jsonEncode(
                    {'username': user, 'password': saved?.password ?? ''}));
          }
        }
        final entry = QbittorrentEntry(
            id: entryId,
            name: clean,
            address: uri.toString(),
            local: local,
            hasLogin: hasLogin);
        _entries[entryId] = entry;
        final old = _backends[entryId];
        final built = _build(entry);
        _backends[entryId] = built;
        await _save();
        unawaited(old?.close());
        onRegistered?.call(built);
        _changes.add(null);
        return entry;
      });

  /// The saved user name, so an editor can show it (the password is never
  /// read back).
  Future<String?> username(String id) async {
    final login = await _login(id);
    return login?.username;
  }

  Future<void> remove(String id) => _locked(() async {
        await load();
        if (_entries.remove(id) == null) return;
        final old = _backends.remove(id);
        await vault.delete(reference(id));
        await _save();
        unawaited(old?.close());
        onRemoved?.call(DownloadBackendRef(kind: QbittorrentDownloadBackend.kind, id: id));
        _changes.add(null);
      });

  Future<void> close() async {
    await _changes.close();
    for (final backend in _backends.values) {
      await backend.close();
    }
  }
}
