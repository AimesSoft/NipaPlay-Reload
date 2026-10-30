import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:path/path.dart' as p;

import 'download_backend.dart';
import 'download_paths.dart';

/// The login of one qBittorrent. Resolved from the credential vault when
/// needed; never part of a snapshot, a fact or an error message.
final class QbittorrentLogin {
  const QbittorrentLogin(this.username, this.password);
  final String username, password;
}

/// A qBittorrent WebUI (API v2) as a download backend. One instance per
/// qBittorrent: its [id] is the second half of the backend reference
/// (`{kind: "qbittorrent", id}`), so a machine can have several.
///
/// Paths are reported as qBittorrent reports them. When [local] is true the
/// qBittorrent runs on this machine, its paths are paths here and files are
/// read from disk. When it is false they are paths on the machine
/// qBittorrent runs on: reported with `local: false`, never opened, and
/// their sizes are read back from qBittorrent itself. Nothing is copied.
///
/// Plain Dart on purpose (`dart:io` only): the headless host uses it too.
final class QbittorrentDownloadBackend
    implements
        DownloadBackend,
        SelectableDownloadBackend,
        FileDeletingDownloadBackend,
        BandwidthDownloadBackend {
  QbittorrentDownloadBackend({
    required this.id,
    required this.name,
    required Uri address,
    required this.local,
    this.login,
    HttpClient Function()? clientFactory,
    DateTime Function()? clock,
    this.connectTimeout = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 20),
    this.metadataWait = const Duration(seconds: 60),
    this.pollInterval = const Duration(milliseconds: 200),
    this.loginRetryDelay = const Duration(seconds: 30),
    this.statusTimeout = const Duration(seconds: 4),
  })  : _clientFactory = clientFactory,
        _now = clock ?? (() => DateTime.now().toUtc()),
        address = _clean(address);

  static const kind = 'qbittorrent';

  final String id, name;

  /// Where the WebUI is, without credentials, query or fragment.
  final Uri address;

  /// qBittorrent runs on this machine and its paths are paths here.
  final bool local;

  /// The login, read when a session is needed; null for a qBittorrent that
  /// lets this client in without one.
  final Future<QbittorrentLogin?> Function()? login;
  final Duration connectTimeout,
      requestTimeout,
      metadataWait,
      pollInterval,
      loginRetryDelay,
      statusTimeout;
  final HttpClient Function()? _clientFactory;
  final DateTime Function() _now;

  HttpClient? _http;
  String? _cookie;
  String? _basicAuthorization;
  Future<void>? _loggingIn;
  DateTime? _loginBlockedUntil;
  bool? _stopStyle;
  String? _version, _apiVersion;
  bool _initialized = false, _closed = false;

  @override
  DownloadBackendRef get reference => DownloadBackendRef(kind: kind, id: id);
  @override
  String? get credentialRef => '$kind:$id';

  static Uri _clean(Uri uri) => Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.endsWith('/') && uri.path.length > 1
          ? uri.path.substring(0, uri.path.length - 1)
          : uri.path == '/'
              ? ''
              : uri.path);

  /// `http://host:8080` or `https://host/qbt`; anything else is refused so a
  /// typo cannot send a login to the wrong place.
  static Uri parseAddress(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const Failure(FailureCode.invalidInput,
          'The qBittorrent address must be http:// or https:// with a host.');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const Failure(FailureCode.invalidInput,
          'Keep the login out of the address; it is saved separately.');
    }
    return _clean(uri);
  }

  /// Whether an address is this machine (loopback), the default for [local].
  static bool isLoopback(Uri uri) =>
      uri.host == 'localhost' ||
      (InternetAddress.tryParse(uri.host)?.isLoopback ?? false);

  // ------------------------------------------------------------- facts

  /// What is configured, without asking qBittorrent anything.
  JsonMap get identity => {
        'id': id,
        'name': name,
        'address': address.toString(),
        'local': local,
        'online': null,
        'version': _version,
        'apiVersion': _apiVersion,
        'error': null,
      };

  /// What is known of this qBittorrent right now: asked live (one small
  /// request), so `online` is a fact of this moment. Never throws.
  Future<JsonMap> status() async {
    String? error;
    try {
      // Asked for a summary or a screen: short, whatever the request timeout.
      _version = (await _text('app/version').timeout(statusTimeout)).trim();
      _apiVersion ??=
          (await _text('app/webapiVersion').timeout(statusTimeout)).trim();
    } on Failure catch (failure) {
      error = failure.code.wireName;
    } on TimeoutException {
      error = FailureCode.unavailable.wireName;
    } catch (_) {
      error = 'backend_failed';
    }
    return {
      'id': id,
      'name': name,
      'address': address.toString(),
      'local': local,
      'online': error == null,
      'version': error == null ? _version : null,
      'apiVersion': error == null ? _apiVersion : null,
      'error': error,
    };
  }

  // -------------------------------------------------------------- HTTP

  HttpClient _client() {
    final existing = _http;
    if (existing != null) return existing;
    final client = (_clientFactory ?? HttpClient.new)();
    // A WebUI is on this network or one the user named: the system proxy
    // does not apply to it.
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = connectTimeout;
    client.autoUncompress = true;
    return _http = client;
  }

  Uri _uri(String endpoint, [Map<String, String>? query]) => address.replace(
      path: '${address.path}/api/v2/$endpoint',
      queryParameters: query == null || query.isEmpty ? null : query);

  Future<_Reply> _raw(String method, String endpoint,
      {Map<String, String>? query,
      Map<String, String>? form,
      _Multipart? multipart}) async {
    try {
      final request = await _client()
          .openUrl(method, _uri(endpoint, query))
          .timeout(connectTimeout);
      // API credentials and request bodies belong to the configured endpoint.
      request.followRedirects = false;
      final origin = address.replace(path: '').toString();
      // qBittorrent refuses a request whose Origin or Referer is another host.
      request.headers.set(HttpHeaders.refererHeader, origin);
      request.headers.set('origin', origin);
      if (_basicAuthorization != null) {
        request.headers.set(HttpHeaders.authorizationHeader, _basicAuthorization!);
      }
      if (_cookie != null && _cookie!.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, _cookie!);
      }
      if (multipart != null) {
        final body = multipart.encode();
        request.headers.contentType =
            ContentType('multipart', 'form-data', parameters: {
          'boundary': multipart.boundary,
        });
        request.contentLength = body.length;
        request.add(body);
      } else if (form != null) {
        final body = utf8.encode(Uri(queryParameters: form).query);
        request.headers.contentType =
            ContentType('application', 'x-www-form-urlencoded');
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(requestTimeout);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(requestTimeout)) {
        builder.add(chunk);
      }
      // Seedbox panels can protect the entire API with Basic authentication,
      // including qBittorrent's own form login. Retry that same request once,
      // keeping its body, then retain Basic alongside the session cookie.
      if (response.statusCode == HttpStatus.unauthorized &&
          _basicAuthorization == null &&
          (response.headers[HttpHeaders.wwwAuthenticateHeader] ?? const <String>[])
              .any((value) => RegExp(r'(?:^|,)\s*Basic(?:\s|$)', caseSensitive: false)
                  .hasMatch(value))) {
        final credentials = await login?.call();
        if (credentials != null) {
          _basicAuthorization = 'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}';
          return _raw(method, endpoint, query: query, form: form, multipart: multipart);
        }
      }
      return _Reply(response.statusCode, builder.takeBytes(),
          [for (final c in response.cookies) '${c.name}=${c.value}']);
    } on Failure {
      rethrow;
    } on TimeoutException {
      throw const Failure(FailureCode.unavailable,
          'qBittorrent did not answer in time.',
          retryable: true);
    } on IOException catch (error) {
      throw Failure(FailureCode.unavailable, 'qBittorrent is unreachable: $error',
          retryable: true);
    }
  }

  Future<void> _signIn() => _loggingIn ??= _doSignIn().whenComplete(() {
        _loggingIn = null;
      });

  Future<void> _doSignIn() async {
    final blocked = _loginBlockedUntil;
    if (blocked != null && _now().isBefore(blocked)) {
      throw const Failure(FailureCode.unavailable,
          'qBittorrent refused the saved login; not trying again yet.',
          retryable: true);
    }
    final credentials = await login?.call();
    if (credentials == null) {
      _cookie = '';
      return;
    }
    final reply = await _raw('POST', 'auth/login', form: {
      'username': credentials.username,
      'password': credentials.password,
    });
    // Success is 200 "Ok." before qBittorrent 5.3 and 204 from it; a refusal
    // is 200 "Fails." before and 401 from it. 403 is a banned address.
    final ok = reply.status == 204 ||
        (reply.status == 200 && reply.text.trim() == 'Ok.');
    if (ok) {
      _cookie = reply.cookies.join('; ');
      _loginBlockedUntil = null;
      return;
    }
    _cookie = null;
    _loginBlockedUntil = _now().add(loginRetryDelay);
    throw Failure(
        FailureCode.unavailable,
        reply.status == 403
            ? 'qBittorrent refused this address (too many failed logins).'
            : 'qBittorrent rejected the login: a wrong user or password, or its '
                'Host header check refusing this address or port.',
        retryable: true);
  }

  /// One call with the session kept alive: a missing session is opened, and
  /// an expired one (403) is opened again once.
  Future<_Reply> _call(String method, String endpoint,
      {Map<String, String>? query,
      Map<String, String>? form,
      _Multipart? multipart}) async {
    if (_closed) {
      throw const Failure(FailureCode.unavailable, 'qBittorrent is closed.',
          retryable: true);
    }
    if (_cookie == null) await _signIn();
    var reply = await _raw(method, endpoint,
        query: query, form: form, multipart: multipart);
    if (reply.status == 401 || reply.status == 403) {
      _cookie = null;
      await _signIn();
      reply = await _raw(method, endpoint,
          query: query, form: form, multipart: multipart);
      if (reply.status == 401 || reply.status == 403) {
        throw const Failure(FailureCode.unavailable,
            'qBittorrent needs a login this client does not have.',
            retryable: true);
      }
    }
    if (reply.status >= 500) {
      throw Failure(FailureCode.unavailable,
          'qBittorrent answered ${reply.status}.',
          retryable: true);
    }
    return reply;
  }

  Future<String> _text(String endpoint, {Map<String, String>? query}) async {
    final reply = await _call('GET', endpoint, query: query);
    if (reply.status != 200) {
      throw Failure(FailureCode.unavailable,
          'qBittorrent answered ${reply.status} to $endpoint.',
          retryable: true);
    }
    return reply.text;
  }

  Future<Object?> _json(String endpoint, {Map<String, String>? query}) async {
    final reply = await _call('GET', endpoint, query: query);
    if (reply.status == 404) {
      throw const Failure(FailureCode.notFound, 'qBittorrent has no such torrent.');
    }
    if (reply.status != 200) {
      throw Failure(FailureCode.unavailable,
          'qBittorrent answered ${reply.status} to $endpoint.',
          retryable: true);
    }
    try {
      // A seedbox can hold thousands of torrents; decoding stays off the
      // caller's isolate when the answer is large.
      final bytes = reply.body;
      return bytes.length > 64 * 1024
          ? await Isolate.run(() => jsonDecode(utf8.decode(bytes)))
          : jsonDecode(reply.text);
    } on FormatException {
      throw const Failure(FailureCode.unavailable,
          'qBittorrent answered something that is not its API.',
          retryable: true);
    }
  }

  Future<void> _post(String endpoint, Map<String, String> form) async {
    final reply = await _call('POST', endpoint, form: form);
    if (reply.status == 404) {
      throw const Failure(FailureCode.notFound, 'qBittorrent has no such torrent.');
    }
    if (reply.status != 200) {
      throw Failure(FailureCode.unavailable,
          'qBittorrent answered ${reply.status} to $endpoint.',
          retryable: true);
    }
  }

  // ----------------------------------------------------------- session

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _version = (await _text('app/version')).trim();
    _apiVersion = (await _text('app/webapiVersion')).trim();
    final parts = _apiVersion!.split('.').map(int.tryParse).toList();
    if (parts.length >= 2 && parts[0] != null && parts[1] != null) {
      // WebAPI 2.11 (qBittorrent 5) renamed pause/resume to stop/start.
      _stopStyle = parts[0]! > 2 || (parts[0] == 2 && parts[1]! >= 11);
    }
    _initialized = true;
  }

  Future<void> close() async {
    _closed = true;
    _http?.close(force: true);
    _http = null;
    _cookie = null;
    _basicAuthorization = null;
  }

  // ------------------------------------------------------------- reads

  Future<List<Map>> _infos([String? hashes]) async {
    final decoded =
        await _json('torrents/info', query: {if (hashes != null) 'hashes': hashes});
    if (decoded is! List) {
      throw const Failure(FailureCode.unavailable,
          'qBittorrent answered something that is not its API.',
          retryable: true);
    }
    return decoded.cast<Map>();
  }

  Future<Map?> _info(String hash) async {
    final all = await _infos(hash);
    for (final item in all) {
      if ((item['hash'] as String?)?.toLowerCase() == hash.toLowerCase()) {
        return item;
      }
    }
    return null;
  }

  final _filesCache = <String, ({DateTime at, List<Map> files})>{};
  final _remoteFiles = <String, ({String hash, int index, String name})>{};

  Future<List<Map>> _files(String hash, {bool fresh = false}) async {
    final cached = _filesCache[hash];
    if (!fresh &&
        cached != null &&
        _now().difference(cached.at) < const Duration(seconds: 2)) {
      return cached.files;
    }
    final reply = await _call('GET', 'torrents/files', query: {'hash': hash});
    if (reply.status == 404) {
      throw const Failure(
          FailureCode.notFound, 'qBittorrent has no such torrent.');
    }
    // No metadata yet: qBittorrent answers 409 (older versions, an empty list).
    final Object? decoded;
    if (reply.status == 409) {
      decoded = const [];
    } else if (reply.status != 200) {
      throw Failure(FailureCode.unavailable,
          'qBittorrent answered ${reply.status} to torrents/files.',
          retryable: true);
    } else {
      try {
        decoded = jsonDecode(reply.text);
      } on FormatException {
        throw const Failure(FailureCode.unavailable,
            'qBittorrent answered something that is not its API.',
            retryable: true);
      }
    }
    if (decoded is! List) {
      throw const Failure(FailureCode.unavailable,
          'qBittorrent answered something that is not its API.',
          retryable: true);
    }
    final files = decoded.cast<Map>();
    _filesCache[hash] = (at: _now(), files: files);
    return files;
  }

  @override
  Future<List<DownloadSnapshot>> list() async => [
        for (final item in await _infos()) _snapshot(item),
      ];

  @override
  Future<DownloadSnapshot> read(String handle) async {
    final item = await _info(handle);
    if (item == null) {
      throw const Failure(
          FailureCode.notFound, 'qBittorrent has no torrent with this handle.');
    }
    final files = await _files(handle, fresh: true);
    return _snapshot(item, files: files);
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;
  static int _size(Object? value) => _int(value) < 0 ? 0 : _int(value);
  static bool _paused(String state) =>
      state.startsWith('paused') || state.startsWith('stopped');

  final _observations =
      <String, ({DateTime since, DateTime? lastProgress, int bytes, DateTime at, int previous})>{};

  String _join(String base, String name) {
    if (local) return p.normalize(p.join(base, name));
    final windows = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(base) ||
        (base.contains('\\') && !base.contains('/'));
    final separator = windows ? r'\' : '/';
    var root = base;
    while (root.length > 1 && (root.endsWith('/') || root.endsWith(r'\'))) {
      root = root.substring(0, root.length - 1);
    }
    return '$root$separator${windows ? name.replaceAll('/', r'\') : name}';
  }

  DownloadSnapshot _snapshot(Map item, {List<Map>? files}) {
    final hash = (item['hash'] as String).toLowerCase();
    final v1 = ((item['infohash_v1'] as String?) ?? '').toLowerCase();
    final state = (item['state'] as String?) ?? 'unknown';
    final savePath = ((item['save_path'] as String?) ?? '').trim();
    final output = local && savePath.isNotEmpty ? p.normalize(savePath) : savePath;
    final total = _size(item['size']);
    final completed = _size(item['completed']);
    final amountLeft = item['amount_left'];
    final progress = (item['progress'] as num?)?.toDouble() ?? 0;
    final settled = !(state.startsWith('checking') ||
        state == 'metaDL' ||
        state == 'forcedMetaDL' ||
        state == 'allocating' ||
        state == 'moving' ||
        state == 'unknown');
    final finished = settled &&
        state != 'error' &&
        state != 'missingFiles' &&
        (amountLeft is num ? amountLeft <= 0 : progress >= 1) &&
        (total > 0 || _int(item['total_size']) > 0);
    final infoHash = v1.isNotEmpty ? v1 : hash;
    final now = _now();
    final previous = _observations[hash];
    final observation = (
      since: previous?.since ?? now,
      lastProgress: previous != null && completed > previous.bytes
          ? now
          : previous?.lastProgress,
      bytes: completed,
      at: now,
      previous: previous?.bytes ?? completed,
    );
    _observations[hash] = observation;
    final seedsConnected = _int(item['num_seeds']);
    final leechConnected = _int(item['num_leechs']);
    int? known(Object? value) => value is num && value >= 0 ? value.toInt() : null;
    final complete = known(item['num_complete']);
    final incomplete = known(item['num_incomplete']);
    final swarm = complete != null && incomplete != null ? complete + incomplete : null;
    final rows = <DownloadFile>[];
    if (files != null) {
      _remoteFiles.removeWhere((_, entry) => entry.hash == hash);
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        final fileName = (file['name'] as String?) ?? '';
        final size = _int(file['size']);
        final fraction = (file['progress'] as num?)?.toDouble() ?? 0;
        final path = _join(savePath, fileName);
        if (!local) {
          _remoteFiles[path] = (hash: hash, index: index, name: fileName);
        }
        rows.add(DownloadFile(
            location: DownloadLocation(path: path, isLocal: local),
            expectedSize: size,
            completedBytes: fraction >= 1 ? size : (fraction * size).floor(),
            isVideo: TorrentTaskFile.videoExtensions
                .contains(p.extension(fileName).toLowerCase()),
            included: _int(file['priority']) > 0));
      }
    }
    return DownloadSnapshot(
      handle: hash,
      infoHash: infoHash,
      title: (item['name'] as String?) ?? infoHash,
      output: DownloadLocation(path: output, isLocal: local),
      completed: completed,
      total: total,
      finished: finished,
      paused: _paused(state),
      state: state,
      downloadSpeedBytesPerSecond: _int(item['dlspeed']),
      uploadSpeedBytesPerSecond: _int(item['upspeed']),
      error: state == 'error'
          ? 'qBittorrent reports an error for this torrent.'
          : state == 'missingFiles'
              ? 'qBittorrent reports the files of this torrent are missing.'
              : null,
      health: {
        'observedAt': now.toIso8601String(),
        'observingSince': observation.since.toIso8601String(),
        'lastProgressAt': observation.lastProgress?.toIso8601String(),
        'secondsWithoutProgress':
            now.difference(observation.lastProgress ?? observation.since).inSeconds,
        'sampleSeconds': previous == null
            ? 0
            : now.difference(previous.at).inMilliseconds / 1000,
        'checkedBytesChange': completed - observation.previous,
        'connectedPeers': seedsConnected + leechConnected,
        'seenPeers': swarm,
        'connectingPeers': null,
        'queuedPeers': null,
        'deadPeers': null,
        'sources': null,
        'seeders': complete,
        'pieceAvailability': item['availability'],
        'fileSelectionSupported': true,
        'filePrioritySupported': true,
        'qbittorrent': {
          'backend': id,
          'state': state,
          'category': item['category'],
          'tags': item['tags'],
          'ratio': item['ratio'],
          'etaSeconds': item['eta'],
          'connectedSeeds': seedsConnected,
          'connectedLeechers': leechConnected,
          'savePath': savePath,
          'addedOn': item['added_on'],
          'completionOn': item['completion_on'],
          'wantedBytes': total,
          'totalBytes': _int(item['total_size']),
        },
      },
      files: rows,
    );
  }

  // ------------------------------------------------------------ writes

  @override
  Future<DownloadSnapshot> add(DownloadRequest request,
      {Future<void>? stopRequested}) async {
    var stopped = false;
    stopRequested?.then((_) => stopped = true);
    await initialize();
    final hash = request.infoHash.toLowerCase();
    if (await _info(hash) != null) return read(hash);
    final isMagnet = request.source.startsWith('magnet:');
    final selecting = request.fileIndices != null;
    // A .torrent already has its file list: it is added stopped, the
    // selection is made, then it runs. A magnet cannot fetch its metadata
    // while stopped, so it runs and the selection follows the metadata.
    final startStopped = selecting && !isMagnet;
    final multipart = _Multipart();
    if (isMagnet) {
      multipart.field('urls', request.source);
    } else {
      final file = File(request.source);
      if (!await file.exists()) {
        throw const Failure(
            FailureCode.invalidInput, 'The torrent file is missing.');
      }
      multipart.file('torrents', '$hash.torrent', await file.readAsBytes());
    }
    final directory = request.downloadDirectory;
    if (directory != null && directory.isNotEmpty) {
      multipart.field('savepath', directory);
    }
    final category = request.category;
    if (category != null && category.isNotEmpty) {
      multipart.field('category', category);
    }
    if (request.createFolderForTask != null) {
      multipart.field('contentLayout',
          request.createFolderForTask! ? 'Subfolder' : 'NoSubfolder');
    }
    if (startStopped) {
      // `paused` before qBittorrent 5, `stopped` after it.
      multipart.field('paused', 'true');
      multipart.field('stopped', 'true');
    }
    if (stopped) throw const DownloadAddStopped();
    final reply = await _call('POST', 'torrents/add', multipart: multipart);
    if (reply.status == 415) {
      throw const Failure(
          FailureCode.invalidInput, 'qBittorrent did not accept the torrent file.');
    }
    if (reply.status != 200 || reply.text.contains('Fails') || _refused(reply)) {
      throw const Failure(FailureCode.invalidInput,
          'qBittorrent did not add the torrent.');
    }
    Future<void> undo() async {
      try {
        await _post('torrents/delete', {'hashes': hash, 'deleteFiles': 'false'});
      } catch (_) {}
    }

    // The torrent appears in the list shortly after "Ok.".
    final appearBy = _now().add(const Duration(seconds: 20));
    Map? item;
    while (item == null) {
      if (stopped) {
        await undo();
        throw const DownloadAddStopped();
      }
      item = await _info(hash);
      if (item != null) break;
      if (_now().isAfter(appearBy)) {
        throw const Failure(FailureCode.unavailable,
            'qBittorrent accepted the torrent but does not list it yet.',
            retryable: true);
      }
      await Future<void>.delayed(pollInterval);
    }
    final needsMetadata = isMagnet || selecting;
    if (needsMetadata) {
      final until = _now().add(metadataWait);
      while (_pending(item!)) {
        if (stopped) {
          await undo();
          throw const DownloadAddStopped();
        }
        if (_now().isAfter(until)) {
          if (selecting) await undo();
          throw const Failure(FailureCode.unavailable,
              'No metadata arrived for the magnet from qBittorrent yet.',
              retryable: true);
        }
        await Future<void>.delayed(pollInterval);
        item = await _info(hash) ?? item;
      }
    }
    if (selecting) {
      await selectFiles(hash, request.fileIndices!);
      if (startStopped) await resume(hash);
    }
    return read(hash);
  }

  /// qBittorrent 5.3 answers an add with counts (`success_count`,
  /// `pending_count`, `failure_count`) instead of "Ok."; nothing added and
  /// nothing pending is a refusal.
  static bool _refused(_Reply reply) {
    try {
      final decoded = jsonDecode(reply.text);
      return decoded is Map &&
          decoded.containsKey('failure_count') &&
          _int(decoded['success_count']) == 0 &&
          _int(decoded['pending_count']) == 0;
    } on FormatException {
      return false;
    }
  }

  bool _pending(Map item) {
    final state = item['state'];
    return state == 'metaDL' ||
        state == 'forcedMetaDL' ||
        _int(item['total_size']) <= 0 && !_paused('$state') && state != 'error';
  }

  @override
  Future<void> selectFiles(String handle, List<int> indices) async {
    final files = await _files(handle, fresh: true);
    final wanted = indices.toSet();
    if (wanted.any((index) => index < 0 || index >= files.length)) {
      throw const Failure(
          FailureCode.invalidInput, 'File indices must be manifest indices.');
    }
    final enable = <int>[], disable = <int>[];
    for (var index = 0; index < files.length; index++) {
      final priority = _int(files[index]['priority']);
      if (wanted.contains(index) && priority <= 0) enable.add(index);
      if (!wanted.contains(index) && priority > 0) disable.add(index);
    }
    // 0 does not download; 1 is the normal priority.
    if (disable.isNotEmpty) {
      await _post('torrents/filePrio',
          {'hash': handle, 'id': disable.join('|'), 'priority': '0'});
    }
    if (enable.isNotEmpty) {
      await _post('torrents/filePrio',
          {'hash': handle, 'id': enable.join('|'), 'priority': '1'});
    }
    _filesCache.remove(handle);
  }

  /// qBittorrent 5 stops and starts, 4 pauses and resumes; the other
  /// version's endpoint answers 404. What the first call learns is kept.
  Future<void> _toggle(String handle, {required bool pause}) async {
    final first = _stopStyle ?? true;
    for (final stopStyle in [first, !first]) {
      final endpoint = pause
          ? (stopStyle ? 'torrents/stop' : 'torrents/pause')
          : (stopStyle ? 'torrents/start' : 'torrents/resume');
      final reply = await _call('POST', endpoint, form: {'hashes': handle});
      if (reply.status == 200) {
        _stopStyle = stopStyle;
        return;
      }
      if (reply.status != 404) {
        throw Failure(FailureCode.unavailable,
            'qBittorrent answered ${reply.status} to $endpoint.',
            retryable: true);
      }
    }
    throw const Failure(FailureCode.unavailable,
        'qBittorrent has neither stop/start nor pause/resume.');
  }

  @override
  Future<void> pause(String handle) async {
    await _toggle(handle, pause: true);
    _filesCache.remove(handle);
  }

  @override
  Future<void> resume(String handle) async {
    await _toggle(handle, pause: false);
    _filesCache.remove(handle);
  }

  @override
  Future<void> remove(String handle) async {
    await _post('torrents/delete', {'hashes': handle, 'deleteFiles': 'false'});
    _forget(handle);
  }

  void _forget(String handle) {
    _filesCache.remove(handle);
    _observations.remove(handle);
    _remoteFiles.removeWhere((_, entry) => entry.hash == handle);
  }

  @override
  Future<void> delete(String handle) async {
    if (local) {
      // The local boundary: every file of the torrent lies inside its own
      // save path. qBittorrent deletes what it manages; this refuses a
      // listing that points elsewhere.
      final task = await read(handle);
      for (final file in task.files) {
        await checkedDownloadPath(task.output.path, file.location.path);
      }
    }
    await _post('torrents/delete', {'hashes': handle, 'deleteFiles': 'true'});
    _forget(handle);
  }

  /// qBittorrent's WebUI has no call that deletes single files. On this
  /// machine they are deleted from disk (the caller has unselected them
  /// first, so qBittorrent does not fetch them again); on another machine
  /// they cannot be, and that is said.
  @override
  Future<void> deleteFiles(String handle, List<int> indices) async {
    final task = await read(handle);
    final targets = <File>[];
    for (final index in indices) {
      if (index < 0 || index >= task.files.length) {
        throw const Failure(
            FailureCode.invalidInput, 'File indices must be manifest indices.');
      }
      final file = task.files[index];
      if (!file.location.isLocal) {
        throw const Failure(
            FailureCode.invalidInput, 'Only local files can be deleted.');
      }
      final path =
          await checkedDownloadPath(task.output.path, file.location.path);
      if (await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.directory) {
        throw const Failure(
            FailureCode.invalidInput, 'A directory is not a download file.');
      }
      targets.add(File(path));
    }
    for (final file in targets) {
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<int?> readSize(DownloadFile file) async {
    if (file.location.isLocal) {
      final disk = File(file.location.path);
      return await disk.exists() ? await disk.length() : null;
    }
    // Another machine's disk is not read; what qBittorrent says it holds is.
    final entry = _remoteFiles[file.location.path];
    if (entry == null) return null;
    final List<Map> files;
    try {
      files = await _files(entry.hash);
    } on Failure catch (failure) {
      if (failure.code == FailureCode.notFound) return null;
      rethrow;
    }
    if (entry.index >= files.length ||
        files[entry.index]['name'] != entry.name) {
      return null;
    }
    final size = _int(files[entry.index]['size']);
    final fraction = (files[entry.index]['progress'] as num?)?.toDouble() ?? 0;
    return fraction >= 1 ? size : (fraction * size).floor();
  }

  // --------------------------------------------------------- bandwidth

  /// qBittorrent's global speed limits (bytes per second, 0 unlimited).
  /// While its alternative limits are switched on, those apply instead;
  /// `alternativeLimitsActive` says so.
  @override
  Future<JsonMap> bandwidth(JsonMap input) async {
    final download = input['downloadBytesPerSecond'];
    final upload = input['uploadBytesPerSecond'];
    if (download is int) {
      await _post('transfer/setDownloadLimit', {'limit': '$download'});
    }
    if (upload is int) {
      await _post('transfer/setUploadLimit', {'limit': '$upload'});
    }
    final actualDownload = int.tryParse((await _text('transfer/downloadLimit')).trim());
    final actualUpload = int.tryParse((await _text('transfer/uploadLimit')).trim());
    bool? alternative;
    try {
      alternative = (await _text('transfer/speedLimitsMode')).trim() == '1';
    } on Failure {
      alternative = null;
    }
    return {
      'supported': true,
      'sessionInitialized': true,
      'applied': input.isNotEmpty,
      'reason': null,
      'actual': {
        'downloadBytesPerSecond': actualDownload,
        'uploadBytesPerSecond': actualUpload,
      },
      'alternativeLimitsActive': alternative,
    };
  }
}

final class _Reply {
  _Reply(this.status, this.body, this.cookies);
  final int status;
  final Uint8List body;
  final List<String> cookies;
  String get text => utf8.decode(body, allowMalformed: true);
}

final class _Multipart {
  final boundary =
      '----nipaplay${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
  final _parts = <Uint8List>[];

  void field(String name, String value) => _parts.add(Uint8List.fromList(utf8.encode(
      '--$boundary\r\nContent-Disposition: form-data; name="$name"\r\n\r\n$value\r\n')));

  void file(String name, String fileName, List<int> bytes) {
    _parts.add(Uint8List.fromList(utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="$name"; filename="$fileName"\r\n'
        'Content-Type: application/x-bittorrent\r\n\r\n')));
    _parts.add(Uint8List.fromList(bytes));
    _parts.add(Uint8List.fromList(utf8.encode('\r\n')));
  }

  Uint8List encode() {
    final builder = BytesBuilder(copy: false);
    for (final part in _parts) {
      builder.add(part);
    }
    builder.add(utf8.encode('--$boundary--\r\n'));
    return builder.takeBytes();
  }
}
