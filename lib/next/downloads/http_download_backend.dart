import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/system_proxy_service.dart';
import 'package:path/path.dart' as p;

import 'download_backend.dart';
import 'download_paths.dart';

/// A plain HTTP(S) file download: one URL, one file. The agent chose HTTP
/// explicitly (`backend: {kind: "http"}`); nothing here guesses what the file
/// is. Sessions are the backend's own (a JSON file each under [stateDirectory]),
/// the partial data lives next to the final path as `NAME.nipaplay-part` and is
/// renamed only once complete and, if asked, checksum-verified, so the media
/// scanner never sees half a file.
final class HttpDownloadBackend implements DownloadBackend {
  HttpDownloadBackend(
      {required this.defaultDirectory,
      this.stateDirectory,
      HttpClient Function()? clientFactory,
      DateTime Function()? clock,
      Duration Function(int failures)? retryDelay,
      this.connectTimeout = const Duration(seconds: 30),
      this.idleTimeout = const Duration(seconds: 60)})
      : _clientFactory = clientFactory,
        _now = clock ?? (() => DateTime.now().toUtc()),
        _retryDelay = retryDelay ?? _defaultRetryDelay;

  static const kind = 'http';
  static const partSuffix = '.nipaplay-part';
  static const checksumAlgorithms = ['md5', 'sha1', 'sha256'];

  /// The download directory setting builtin uses.
  final Future<String> Function() defaultDirectory;

  /// Where sessions are kept; the runtime sets it once the data root is known.
  Directory? stateDirectory;
  final HttpClient Function()? _clientFactory;
  final DateTime Function() _now;
  final Duration Function(int failures) _retryDelay;
  final Duration connectTimeout, idleTimeout;

  static Duration _defaultRetryDelay(int failures) =>
      Duration(seconds: [1, 2, 5, 10, 30][(failures - 1).clamp(0, 4)]);

  final _sessions = <String, _Session>{};
  Future<void>? _loaded;
  bool _closed = false;

  @override
  DownloadBackendRef get reference => const DownloadBackendRef(kind: kind);
  @override
  String? get credentialRef => null;

  /// Validates [source] and derives the identity: `http-` plus the SHA-1 of
  /// the request URL without fragment, scheme and host lower-cased, default
  /// port dropped. The prefix keeps it apart from BT info hashes.
  static DownloadRequest prepare(String source,
      {String? downloadDirectory,
      bool? createFolderForTask,
      JsonMap? checksum}) {
    final uri = _parse(source);
    if (checksum != null) {
      final algorithm = checksum['algorithm'];
      final value = checksum['value'];
      final length = const {'md5': 32, 'sha1': 40, 'sha256': 64}[algorithm];
      if (length == null ||
          value is! String ||
          !RegExp('^[0-9a-fA-F]{$length}\$').hasMatch(value)) {
        throw const Failure(FailureCode.invalidInput,
            'checksum needs algorithm md5, sha1 or sha256 and a hexadecimal value of that length.');
      }
    }
    final normalized = _normalize(uri);
    return DownloadRequest(
        source: source.trim(),
        infoHash: 'http-${sha1.convert(utf8.encode(normalized))}',
        title: _urlName(uri) ?? uri.host,
        downloadDirectory: downloadDirectory,
        createFolderForTask: createFolderForTask,
        checksum: checksum == null
            ? null
            : {
                'algorithm': checksum['algorithm'],
                'value': (checksum['value'] as String).toLowerCase()
              });
  }

  static Uri _parse(String source) {
    final uri = Uri.tryParse(source.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const Failure(FailureCode.invalidInput,
          'The http backend only downloads http:// and https:// addresses.');
    }
    if (uri.host.isEmpty) {
      throw const Failure(
          FailureCode.invalidInput, 'The address must contain a host.');
    }
    return uri;
  }

  static String _normalize(Uri uri) {
    final defaultPort = uri.scheme == 'https' ? 443 : 80;
    final path = uri.path.isEmpty ? '/' : uri.normalizePath().path;
    return '${uri.scheme}://${uri.userInfo.isEmpty ? '' : '${uri.userInfo}@'}'
        '${uri.host}${uri.port == defaultPort ? '' : ':${uri.port}'}$path'
        '${uri.hasQuery ? '?${uri.query}' : ''}';
  }

  // ---------------------------------------------------------------- client

  HttpClient _client() {
    final client = (_clientFactory ?? _systemClient)();
    client.autoUncompress = false;
    client.connectionTimeout = connectTimeout;
    return client;
  }

  /// The same proxy resolution the rest of the app uses: the HTTP proxy
  /// setting, else the system proxy; certificate trust comes from the global
  /// HttpOverrides. Loopback is never proxied.
  static HttpClient _systemClient() => HttpClient()
    ..findProxy = (uri) => uri.host == 'localhost' ||
            InternetAddress.tryParse(uri.host)?.isLoopback == true
        ? 'DIRECT'
        : AppHttpProxy.findProxy(uri, SystemProxyService.instance.findProxy);

  Future<_Opened> _open(Uri uri,
      {int offset = 0,
      String? ifRange,
      Future<void>? abort,
      String method = 'GET',
      String? range}) async {
    final client = _client();
    abort?.then((_) => client.close(force: true));
    try {
      final request = method == 'HEAD'
          ? await client.headUrl(uri).timeout(connectTimeout)
          : await client.getUrl(uri).timeout(connectTimeout);
      request.followRedirects = true;
      request.maxRedirects = 10;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (range != null) {
        request.headers.set(HttpHeaders.rangeHeader, range);
      } else if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        if (ifRange != null) request.headers.set('if-range', ifRange);
      }
      final response = await request.close().timeout(connectTimeout);
      var finalUri = uri;
      for (final hop in response.redirects) {
        finalUri = finalUri.resolveUri(hop.location);
      }
      return _Opened(client, response, finalUri);
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  Future<void> _ensureProxySettings() async {
    if (_clientFactory == null) await SystemProxyService.instance.initialize();
  }

  // --------------------------------------------------------------- preview

  /// Facts about [source] without downloading it or creating a task: HEAD,
  /// or a GET of `Range: bytes=0-0` (closed after the headers) when the
  /// server will not answer HEAD.
  Future<JsonMap> preview(String source) async {
    final uri = _parse(source);
    await _ensureProxySettings();
    _Opened? opened;
    var method = 'HEAD';
    try {
      try {
        opened = await _open(uri, method: 'HEAD');
        if (opened.response.statusCode >= 400) {
          opened.client.close(force: true);
          opened = null;
        }
      } on Exception catch (_) {
        opened = null;
      }
      if (opened == null) {
        method = 'GET';
        opened = await _open(uri, method: 'GET', range: 'bytes=0-0');
      }
      final r = opened.response;
      final headers = r.headers;
      final partial = r.statusCode == HttpStatus.partialContent;
      final rangeTotal = partial
          ? _contentRange(headers.value(HttpHeaders.contentRangeHeader))?.total
          : null;
      final length = rangeTotal ?? (r.contentLength >= 0 ? r.contentLength : null);
      final advertised =
          (headers.value(HttpHeaders.acceptRangesHeader) ?? '').toLowerCase();
      return {
        'backend': kind,
        'url': uri.toString(),
        'finalUrl': opened.uri.toString(),
        'redirects': r.redirects.length,
        'statusCode': r.statusCode,
        'method': method == 'HEAD' ? 'HEAD' : 'GET Range 0-0',
        'contentLength': method == 'GET' && !partial && r.statusCode == 200
            ? (r.contentLength >= 0 ? r.contentLength : null)
            : length,
        'contentType': headers.value(HttpHeaders.contentTypeHeader),
        'acceptRanges':
            method == 'GET' ? partial : advertised.contains('bytes'),
        'fileName': _responseName(headers, opened.uri),
        'lastModified': headers.value(HttpHeaders.lastModifiedHeader),
        'etag': headers.value(HttpHeaders.etagHeader),
      };
    } on Exception catch (error) {
      throw _classify(error, 'Preview');
    } finally {
      if (opened != null) opened.client.close(force: true);
    }
  }

  // ----------------------------------------------------------------- state

  @override
  Future<void> initialize() => _loaded ??= _load();

  Future<void> _load() async {
    final directory = stateDirectory;
    if (directory == null) {
      throw const Failure(FailureCode.internal,
          'The http download backend has no state directory.');
    }
    await _ensureProxySettings();
    if (!await directory.exists()) return;
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final session = _Session.fromJson(
            jsonDecode(await entry.readAsString()) as JsonMap, _now());
        session.bytes = await _diskBytes(session);
        _sessions[session.id] = session;
      } on Object {
        // An unreadable record is not a download; leave the file alone.
      }
    }
    for (final session in _sessions.values) {
      if (!session.paused && !session.finished && session.failure == null) {
        _start(session, null);
      }
    }
  }

  Future<int> _diskBytes(_Session s) async {
    final done = File(s.filePath);
    if (s.finished) return await done.exists() ? await done.length() : 0;
    final part = File(s.partPath);
    return await part.exists() ? await part.length() : 0;
  }

  Future<void> _persist(_Session s) async {
    final directory = stateDirectory!;
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, '${s.id}.json'));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(s.toJson()), flush: true);
    await temp.rename(file.path);
  }

  Future<void> close() async {
    _closed = true;
    for (final session in _sessions.values) {
      session.stop?.complete();
    }
    await Future.wait([
      for (final session in _sessions.values)
        if (session.worker != null) session.worker!
    ]);
  }

  // --------------------------------------------------------------- reading

  @override
  Future<List<DownloadSnapshot>> list() async {
    await initialize();
    return [for (final s in _sessions.values) _snapshot(s, observe: false)];
  }

  @override
  Future<DownloadSnapshot> read(String handle) async {
    await initialize();
    return _snapshot(_session(handle));
  }

  _Session _session(String handle) =>
      _sessions[handle] ??
      (throw const Failure(
          FailureCode.notFound, 'HTTP download session is missing.'));

  @override
  Future<int?> readSize(DownloadFile file) async {
    final local = File(file.location.path);
    return await local.exists() ? await local.length() : null;
  }

  DownloadSnapshot _snapshot(_Session s, {bool observe = true}) {
    final now = _now();
    final size = s.expectedSize;
    final progressBase = s.lastProgress != null &&
            s.lastProgress!.isAfter(s.idleSince)
        ? s.lastProgress!
        : s.idleSince;
    final previousBytes = s.readBytes ?? s.bytes;
    final sampleSeconds = s.readAt == null
        ? 0.0
        : now.difference(s.readAt!).inMilliseconds / 1000;
    if (observe) {
      s.readBytes = s.bytes;
      s.readAt = now;
    }
    s.samples.removeWhere(
        (sample) => now.difference(sample.at) > const Duration(seconds: 5));
    final speed = s.finished || s.paused || s.samples.isEmpty
        ? 0
        : ((s.received - s.samples.first.received) /
                (now.difference(s.samples.first.at).inMilliseconds / 1000)
                    .clamp(1.0, 5.0))
            .round();
    final state = s.failure != null
        ? 'failed'
        : s.finished
            ? 'finished'
            : s.verifying
                ? 'verifying'
                : s.paused
                    ? 'paused'
                    : s.lastError != null
                        ? 'retrying'
                        : 'downloading';
    final file = DownloadFile(
        location: DownloadLocation(path: s.filePath, isLocal: true),
        expectedSize: size ?? 0,
        isVideo: TorrentTaskFile.videoExtensions
            .contains(p.extension(s.fileName).toLowerCase()),
        completedBytes: s.finished || size != null ? s.bytes : null);
    return DownloadSnapshot(
      handle: s.id,
      infoHash: s.infoHash,
      title: s.fileName,
      output: DownloadLocation(path: s.outputDirectory, isLocal: true),
      completed: s.bytes,
      total: size ?? 0,
      finished: s.finished,
      paused: s.paused,
      state: state,
      downloadSpeedBytesPerSecond: speed,
      failure: s.failure,
      checksum: s.checksum,
      health: {
        'observedAt': now.toIso8601String(),
        'observingSince': s.idleSince.toIso8601String(),
        'lastProgressAt': s.lastProgress?.toIso8601String(),
        'secondsWithoutProgress': now.difference(progressBase).inSeconds,
        'sampleSeconds': sampleSeconds,
        'checkedBytesChange': s.bytes - previousBytes,
        'connectedPeers': null,
        'seenPeers': null,
        'connectingPeers': null,
        'queuedPeers': null,
        'deadPeers': null,
        'sources': null,
        'seeders': null,
        'pieceAvailability': null,
        'availabilityReason': 'HTTP downloads have a single server, no peers',
        'fileSelectionSupported': false,
        'filePrioritySupported': false,
        'http': {
          'url': s.url,
          'finalUrl': s.finalUrl,
          'statusCode': s.statusCode,
          'contentType': s.contentType,
          'acceptRanges': s.acceptRanges,
          'resume': s.resume,
          'etag': s.etag,
          'lastModified': s.lastModified,
          'partialFile': s.finished ? null : s.partPath,
          'retries': s.retries,
          'lastError': s.lastError,
          'lastErrorAt': s.lastErrorAt?.toIso8601String(),
        },
      },
      files: [file],
    );
  }

  // ------------------------------------------------------------------- add

  @override
  Future<DownloadSnapshot> add(DownloadRequest request,
      {Future<void>? stopRequested}) async {
    await initialize();
    final uri = _parse(request.source);
    final id = request.infoHash.startsWith('http-')
        ? request.infoHash.substring(5)
        : sha1.convert(utf8.encode(_normalize(uri))).toString();
    final known = _sessions[id];
    if (known != null) return _snapshot(known);
    var stopped = false;
    final abort = Completer<void>();
    unawaited(stopRequested?.then((_) {
      stopped = true;
      if (!abort.isCompleted) abort.complete();
    }));
    _Opened opened;
    var handedOver = false;
    try {
      opened = await _open(uri, abort: abort.future);
    } on Exception catch (error) {
      if (stopped) throw const DownloadAddStopped();
      throw _classify(error, 'Download');
    }
    try {
      final status = opened.response.statusCode;
      if (status != 200) {
        final failure = _statusFailure(status, opened.response.reasonPhrase);
        throw failure ?? _transientStatus(status, opened.response.reasonPhrase);
      }
      final headers = opened.response.headers;
      final name = _responseName(headers, opened.uri);
      var directory = request.downloadDirectory ?? await defaultDirectory();
      if (request.createFolderForTask == true) {
        directory = p.join(directory, p.withoutExtension(name));
      }
      final created = !await Directory(directory).exists();
      await Directory(directory).create(recursive: true);
      final fileName = await _freeName(directory, name);
      final advertised =
          (headers.value(HttpHeaders.acceptRangesHeader) ?? '').toLowerCase();
      final session = _Session(
          id: id,
          infoHash: request.infoHash,
          url: request.source.trim(),
          outputDirectory: p.normalize(directory),
          fileName: fileName,
          createdFolder: created && request.createFolderForTask == true,
          checksumRequest: request.checksum,
          now: _now());
      session.finalUrl = opened.uri.toString();
      session.statusCode = status;
      session.expectedSize =
          opened.response.contentLength >= 0 ? opened.response.contentLength : null;
      session.contentType = headers.value(HttpHeaders.contentTypeHeader);
      session.etag = headers.value(HttpHeaders.etagHeader);
      session.lastModified = headers.value(HttpHeaders.lastModifiedHeader);
      session.acceptRanges = advertised.isEmpty
          ? null
          : advertised.contains('bytes')
              ? true
              : false;
      if (stopped) throw const DownloadAddStopped();
      await _persist(session);
      _sessions[id] = session;
      handedOver = true;
      _start(session, opened);
      return _snapshot(session);
    } finally {
      if (!handedOver) opened.client.close(force: true);
    }
  }

  /// A name that exists neither as a file nor as a partial file, nor in
  /// another session: an existing file is never overwritten, the new one gets
  /// ` (1)`, ` (2)` ... before its extension.
  Future<String> _freeName(String directory, String name) async {
    final extension = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    for (var n = 0;; n++) {
      final candidate = n == 0 ? name : '$stem ($n)$extension';
      final path = p.join(directory, candidate);
      if (!await FileSystemEntity.isLink(path) &&
          !await File(path).exists() &&
          !await Directory(path).exists() &&
          !await File('$path$partSuffix').exists() &&
          !_sessions.values.any((s) => s.filePath == p.normalize(path))) {
        return candidate;
      }
    }
  }

  // ------------------------------------------------------------- controls

  @override
  Future<void> pause(String handle) async {
    final s = _session(handle);
    s.paused = true;
    await _stop(s);
    await _persist(s);
  }

  @override
  Future<void> resume(String handle) async {
    final s = _session(handle);
    if (s.failure != null) {
      throw Failure(FailureCode.conflict,
          'The download failed (${s.failure!.message}); remove it and add it again.');
    }
    final wasPaused = s.paused;
    s.paused = false;
    if (wasPaused) {
      s.idleSince = _now();
      s.lastProgress = null;
    }
    await _persist(s);
    if (!s.finished) _start(s, null);
  }

  @override
  Future<void> remove(String handle) async {
    final s = _session(handle);
    await _stop(s);
    _sessions.remove(handle);
    final record = File(p.join(stateDirectory!.path, '$handle.json'));
    if (await record.exists()) await record.delete();
  }

  @override
  Future<void> delete(String handle) async {
    final s = _session(handle);
    await checkedDownloadPath(s.outputDirectory, s.filePath);
    await checkedDownloadPath(s.outputDirectory, s.partPath);
    await remove(handle);
    for (final path in [s.filePath, s.partPath]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    if (s.createdFolder) {
      final directory = Directory(s.outputDirectory);
      if (await directory.exists() && await directory.list().isEmpty) {
        await directory.delete();
      }
    }
  }

  Future<void> _stop(_Session s) async {
    s.stop?.complete();
    await s.worker;
  }

  // ---------------------------------------------------------------- worker

  void _start(_Session s, _Opened? first) {
    if (s.worker != null || _closed) {
      first?.client.close(force: true);
      return;
    }
    final stop = s.stop = Completer<void>();
    s.worker = _work(s, first, stop).whenComplete(() {
      s.worker = null;
      s.stop = null;
    });
  }

  Future<void> _work(_Session s, _Opened? first, Completer<void> stop) async {
    var failures = 0;
    while (!stop.isCompleted && !_closed) {
      _Opened? opened = first;
      first = null;
      final before = s.received;
      try {
        var offset = 0;
        if (opened == null) {
          offset = await _partBytes(s);
          if (offset > 0 && s.acceptRanges == false) {
            await _truncate(s);
            offset = 0;
          }
          opened = await _open(Uri.parse(s.url),
              offset: offset,
              ifRange: s.etag != null && !s.etag!.startsWith('W/')
                  ? s.etag
                  : s.lastModified,
              abort: stop.future);
        }
        final outcome = await _receive(s, opened, offset, stop);
        if (outcome == _Outcome.aborted) return;
        if (outcome == _Outcome.restart) continue;
        s.lastError = null;
        await _finalize(s);
        return;
      } on Failure catch (failure) {
        if (!failure.retryable) {
          s.failure = failure;
          s.lastError = null;
          await _persist(s);
          return;
        }
        s.noteError(failure.message, _now());
      } on Exception catch (error) {
        if (stop.isCompleted) return;
        final failure = _classify(error, 'Download');
        if (!failure.retryable) {
          s.failure = failure;
          await _persist(s);
          return;
        }
        s.noteError(failure.message, _now());
      } finally {
        opened?.client.close(force: true);
      }
      if (stop.isCompleted) return;
      failures = s.received > before ? 1 : failures + 1;
      s.retries++;
      await Future.any(
          [Future<void>.delayed(_retryDelay(failures)), stop.future]);
    }
  }

  Future<int> _partBytes(_Session s) async {
    final part = File(s.partPath);
    return await part.exists() ? await part.length() : 0;
  }

  Future<void> _truncate(_Session s) async {
    final part = File(s.partPath);
    if (await part.exists()) await part.writeAsBytes(const [], flush: true);
    s.bytes = 0;
  }

  Future<_Outcome> _receive(
      _Session s, _Opened opened, int offset, Completer<void> stop) async {
    final response = opened.response;
    final status = response.statusCode;
    if (status == HttpStatus.requestedRangeNotSatisfiable && offset > 0) {
      if (s.expectedSize == offset) return _Outcome.done;
      await _truncate(s);
      return _Outcome.restart;
    }
    if (status != 200 && status != 206) {
      throw _statusFailure(status, response.reasonPhrase) ??
          _transientStatus(status, response.reasonPhrase);
    }
    var start = offset;
    final headers = response.headers;
    if (status == 206) {
      final range = _contentRange(headers.value(HttpHeaders.contentRangeHeader));
      if (range == null || range.start != offset) {
        await _truncate(s);
        s.resume = 'rejected';
        return _Outcome.restart;
      }
      if (range.total != null) s.expectedSize = range.total;
      s.resume = 'confirmed';
    } else {
      if (offset > 0) {
        // Range ignored (or the file changed under If-Range): from the top.
        await _truncate(s);
        start = 0;
        s.resume = 'ignored';
      }
      if (response.contentLength >= 0) s.expectedSize = response.contentLength;
      s.etag = headers.value(HttpHeaders.etagHeader) ?? s.etag;
      s.lastModified =
          headers.value(HttpHeaders.lastModifiedHeader) ?? s.lastModified;
    }
    s.statusCode = status;
    s.finalUrl = opened.uri.toString();
    s.bytes = start;
    final file = await File(s.partPath)
        .open(mode: start > 0 ? FileMode.append : FileMode.write);
    final done = Completer<void>();
    var aborted = false;
    late final StreamSubscription<List<int>> subscription;
    subscription = response.timeout(idleTimeout).listen((chunk) {
      subscription.pause();
      file.writeFrom(chunk).then((_) {
        final now = _now();
        s.bytes += chunk.length;
        s.received += chunk.length;
        s.lastProgress = now;
        s.lastError = null;
        s.samples.add((at: now, received: s.received));
        if (!done.isCompleted) subscription.resume();
      }, onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      });
    },
        onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true);
    unawaited(stop.future.then((_) {
      aborted = true;
      opened.client.close(force: true);
      unawaited(subscription.cancel());
      if (!done.isCompleted) done.complete();
    }));
    try {
      await done.future;
    } finally {
      unawaited(subscription.cancel());
      await file.close();
    }
    if (aborted) return _Outcome.aborted;
    final expected = s.expectedSize;
    if (expected != null && s.bytes != expected) {
      if (s.bytes > expected) await _truncate(s);
      throw Failure(FailureCode.unavailable,
          'The server ended the transfer at ${s.bytes} of $expected bytes.',
          retryable: true);
    }
    return _Outcome.done;
  }

  Future<void> _finalize(_Session s) async {
    s.verifying = true;
    try {
      final requested = s.checksumRequest;
      final algorithm = (requested?['algorithm'] as String?) ?? 'sha256';
      final path = s.partPath;
      final actual =
          await Isolate.run(() => _hashFile(path, algorithm));
      final expected = requested?['value'] as String?;
      final matched = expected == null ? null : expected == actual;
      s.checksum = {
        'algorithm': algorithm,
        'requested': expected != null,
        'expected': expected,
        'actual': actual,
        'matched': matched,
        if (matched == false) 'file': s.partPath,
      };
      if (matched == false) {
        s.failure = Failure(FailureCode.conflict,
            'Checksum mismatch ($algorithm): expected $expected, actual $actual. The downloaded data is kept at ${s.partPath}.',
            details: {'checksum': s.checksum});
      } else {
        if (await FileSystemEntity.type(s.filePath, followLinks: false) !=
            FileSystemEntityType.notFound) {
          s.failure = Failure(FailureCode.conflict,
              'A file appeared at ${s.filePath} during the download; the data is kept at ${s.partPath}.');
        } else {
          await File(s.partPath).rename(s.filePath);
          s.expectedSize = s.bytes;
          s.finished = true;
        }
      }
    } on FileSystemException catch (error) {
      s.noteError(error.toString(), _now());
    } finally {
      s.verifying = false;
      await _persist(s);
    }
  }

  // ----------------------------------------------------------- classifying

  Failure _classify(Exception error, String what) {
    if (error is Failure) return error;
    if (error is HandshakeException || error is CertificateException) {
      return Failure(FailureCode.unavailable, '$what failed: $error');
    }
    return Failure(FailureCode.unavailable, '$what failed: $error',
        retryable: true);
  }

  /// Statuses where asking again will not help; null for the rest.
  Failure? _statusFailure(int status, String reason) {
    if (status < 400 || status >= 500) return null;
    if (status == 408 || status == 429) return null;
    return Failure(
        status == 404 || status == 410
            ? FailureCode.notFound
            : FailureCode.unavailable,
        'The server answered HTTP $status $reason.');
  }

  Failure _transientStatus(int status, String reason) => Failure(
      FailureCode.unavailable, 'The server answered HTTP $status $reason.',
      retryable: true);

  // ---------------------------------------------------------------- naming

  static String _responseName(HttpHeaders headers, Uri finalUri) {
    final raw = _sanitize(
        _dispositionName(headers.value('content-disposition')) ?? '');
    if (raw.isNotEmpty) return raw;
    final fromUrl = _sanitize(_urlName(finalUri) ?? '');
    return fromUrl.isNotEmpty ? fromUrl : 'download';
  }

  static String? _urlName(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty);
    if (segments.isEmpty) return null;
    try {
      return Uri.decodeComponent(segments.last);
    } on ArgumentError {
      return segments.last;
    }
  }

  static String? _dispositionName(String? header) {
    if (header == null) return null;
    final extended = RegExp(r'(?:^|[;\s])filename\*\s*=\s*([^;]+)',
            caseSensitive: false)
        .firstMatch(header);
    if (extended != null) {
      final parts = extended.group(1)!.trim().split("'");
      if (parts.length >= 3) {
        final charset = parts[0].toLowerCase();
        final encoded = parts.sublist(2).join("'");
        final bytes = <int>[];
        for (var i = 0; i < encoded.length; i++) {
          if (encoded[i] == '%' && i + 2 < encoded.length + 0) {
            final value = int.tryParse(encoded.substring(i + 1, i + 3), radix: 16);
            if (value != null) {
              bytes.add(value);
              i += 2;
              continue;
            }
          }
          bytes.addAll(utf8.encode(encoded[i]));
        }
        return charset.contains('8859') || charset == 'latin1'
            ? latin1.decode(bytes)
            : utf8.decode(bytes, allowMalformed: true);
      }
    }
    final plain = RegExp(
            r'(?:^|[;\s])filename\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^;]+))',
            caseSensitive: false)
        .firstMatch(header);
    if (plain == null) return null;
    return plain.group(1)?.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!) ??
        plain.group(2)!.trim();
  }

  /// A server-given name becomes one path component: directories dropped,
  /// control characters (and on Windows the characters it forbids) replaced.
  static String _sanitize(String name) {
    var base = name.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).lastOrNull ?? '';
    base = base.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '_');
    if (Platform.isWindows) base = base.replaceAll(RegExp(r'[:*?"<>|]'), '_');
    base = base.trim();
    if (base == '.' || base == '..') return '';
    if (utf8.encode(base).length > 200) {
      final extension = p.extension(base);
      final stem = p.basenameWithoutExtension(base);
      var cut = stem;
      while (utf8.encode('$cut$extension').length > 200 && cut.isNotEmpty) {
        cut = cut.substring(0, cut.length - 1);
      }
      base = '$cut$extension';
    }
    return base;
  }

  static ({int start, int? total})? _contentRange(String? header) {
    final match = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$')
        .firstMatch((header ?? '').trim());
    if (match == null) return null;
    return (
      start: int.parse(match.group(1)!),
      total: match.group(3) == '*' ? null : int.parse(match.group(3)!)
    );
  }
}

Future<String> _hashFile(String path, String algorithm) async {
  final hash = switch (algorithm) {
    'md5' => md5,
    'sha1' => sha1,
    _ => sha256,
  };
  return (await hash.bind(File(path).openRead()).first).toString();
}

enum _Outcome { done, aborted, restart }

final class _Opened {
  _Opened(this.client, this.response, this.uri);
  final HttpClient client;
  final HttpClientResponse response;
  final Uri uri;
}

final class _Session {
  _Session(
      {required this.id,
      required this.infoHash,
      required this.url,
      required this.outputDirectory,
      required this.fileName,
      required this.createdFolder,
      required this.checksumRequest,
      required DateTime now})
      : idleSince = now;

  final String id, infoHash, url, outputDirectory;
  final bool createdFolder;
  final JsonMap? checksumRequest;
  String fileName;
  String get filePath => p.normalize(p.join(outputDirectory, fileName));
  String get partPath => '$filePath${HttpDownloadBackend.partSuffix}';
  int? expectedSize;
  String? finalUrl, contentType, etag, lastModified;
  int? statusCode;
  bool? acceptRanges;
  String resume = 'untested';
  bool paused = false, finished = false;
  Failure? failure;
  JsonMap? checksum;

  // This process only.
  int bytes = 0;
  int received = 0;
  int retries = 0;
  bool verifying = false;
  String? lastError;
  DateTime? lastErrorAt, lastProgress;
  DateTime idleSince;
  int? readBytes;
  DateTime? readAt;
  final samples = <({DateTime at, int received})>[];
  Future<void>? worker;
  Completer<void>? stop;

  void noteError(String message, DateTime now) {
    lastError = message;
    lastErrorAt = now;
  }

  JsonMap toJson() => {
        'id': id,
        'infoHash': infoHash,
        'url': url,
        'outputDirectory': outputDirectory,
        'fileName': fileName,
        'createdFolder': createdFolder,
        'checksumRequest': checksumRequest,
        'expectedSize': expectedSize,
        'finalUrl': finalUrl,
        'contentType': contentType,
        'etag': etag,
        'lastModified': lastModified,
        'statusCode': statusCode,
        'acceptRanges': acceptRanges,
        'resume': resume,
        'paused': paused,
        'finished': finished,
        'checksum': checksum,
        if (failure != null)
          'failure': {
            'code': failure!.code.wireName,
            'message': failure!.message,
          },
      };

  factory _Session.fromJson(JsonMap json, DateTime now) {
    final s = _Session(
        id: json['id'] as String,
        infoHash: json['infoHash'] as String,
        url: json['url'] as String,
        outputDirectory: json['outputDirectory'] as String,
        fileName: json['fileName'] as String,
        createdFolder: json['createdFolder'] as bool,
        checksumRequest: (json['checksumRequest'] as Map?)?.cast<String, Object?>(),
        now: now)
      ..expectedSize = json['expectedSize'] as int?
      ..finalUrl = json['finalUrl'] as String?
      ..contentType = json['contentType'] as String?
      ..etag = json['etag'] as String?
      ..lastModified = json['lastModified'] as String?
      ..statusCode = json['statusCode'] as int?
      ..acceptRanges = json['acceptRanges'] as bool?
      ..resume = json['resume'] as String? ?? 'untested'
      ..paused = json['paused'] as bool
      ..finished = json['finished'] as bool
      ..checksum = (json['checksum'] as Map?)?.cast<String, Object?>();
    if (json['failure'] case final Map failure) {
      s.failure = Failure(
          FailureCode.values.firstWhere(
              (c) => c.wireName == failure['code'],
              orElse: () => FailureCode.unavailable),
          failure['message'] as String,
          details: s.checksum == null ? const {} : {'checksum': s.checksum});
    }
    return s;
  }
}
