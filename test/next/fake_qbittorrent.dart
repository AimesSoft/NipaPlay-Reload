import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nipaplay/next/downloads/download_source.dart';

/// A valid single- or multi-file torrent: `files` are (path inside, size).
Uint8List testTorrent(String name, List<(String, int)> files) {
  String s(String text) => '${utf8.encode(text).length}:$text';
  final total = files.fold<int>(0, (n, f) => n + f.$2);
  final pieces = (total / 16384).ceil().clamp(1, 1 << 20);
  final info = BytesBuilder()..add(ascii.encode('d'));
  if (files.length == 1 && files.single.$1 == name) {
    info.add(ascii.encode('6:lengthi${files.single.$2}e'));
  } else {
    info.add(ascii.encode('5:filesl'));
    for (final f in files) {
      final parts = f.$1.split('/');
      info.add(ascii.encode(
          'd6:lengthi${f.$2}e4:pathl${parts.map(s).join()}ee'));
    }
    info.add(ascii.encode('e'));
  }
  info.add(ascii.encode('4:name${s(name)}12:piece lengthi16384e6:pieces${pieces * 20}:'));
  info.add(Uint8List(pieces * 20));
  info.add(ascii.encode('e'));
  final out = BytesBuilder()
    ..add(ascii.encode('d4:info'))
    ..add(info.toBytes())
    ..add(ascii.encode('e'));
  return out.toBytes();
}

final class FakeFile {
  FakeFile(this.name, this.size, {this.progress = 0, this.priority = 1});
  final String name;
  final int size;
  double progress;
  int priority;
}

final class FakeTorrent {
  FakeTorrent(this.hash, this.name, this.savePath, this.files,
      {this.hasMetadata = true});
  final String hash;
  String name, savePath;
  String category = '';
  String? contentLayout;
  bool paused = false;
  bool hasMetadata;
  List<FakeFile> files;
  int dlspeed = 0, upspeed = 0;
}

/// Just enough of qBittorrent's WebUI API v2 for the backend: v4 answers
/// pause/resume, v5 stop/start (the other pair is a 404, as in the real one).
final class FakeQbittorrent {
  FakeQbittorrent(
      {this.v5 = true, this.username = 'nipa', this.password = 'secret'});
  final bool v5;
  final String username, password;
  late HttpServer server;
  final torrents = <String, FakeTorrent>{};
  final requests = <String>[];
  final origins = <String?>[];
  final authorizations = <String?>[];
  bool requireBasicAuth = false;
  String basePath = '';
  int basicChallenges = 0;
  String? sid;
  int logins = 0, rejectedLogins = 0;
  bool requireAuth = true;
  int downloadLimit = 0, uploadLimit = 0;

  /// Metadata of a magnet that arrives after this long (null: only by [reveal]).
  Duration? metadataDelay = const Duration(milliseconds: 150);

  /// What a magnet turns out to contain.
  final magnetContents = <String, ({String name, List<(String, int)> files})>{};

  Uri get address => Uri.parse('http://127.0.0.1:${server.port}$basePath');

  Future<void> start([int port = 0]) async {
    server = await HttpServer.bind('127.0.0.1', port);
    server.listen((request) async {
      try {
        await _handle(request);
      } catch (_) {
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  Future<void> stop() => server.close(force: true);

  void expireSession() => sid = null;

  String stateOf(FakeTorrent t) {
    if (!t.hasMetadata) return 'metaDL';
    final done = _left(t) == 0;
    if (t.paused) {
      return v5
          ? (done ? 'stoppedUP' : 'stoppedDL')
          : (done ? 'pausedUP' : 'pausedDL');
    }
    return done ? 'stalledUP' : 'downloading';
  }

  int _wanted(FakeTorrent t) => t.files
      .where((f) => f.priority > 0)
      .fold<int>(0, (n, f) => n + f.size);
  int _have(FakeTorrent t) => t.files
      .where((f) => f.priority > 0)
      .fold<int>(0, (n, f) => n + (f.size * f.progress).floor());
  int _left(FakeTorrent t) => _wanted(t) - _have(t);

  void finish(String hash) {
    for (final f in torrents[hash]!.files) {
      f.progress = 1;
    }
  }

  void reveal(String hash) {
    final t = torrents[hash]!;
    final content = magnetContents[hash];
    if (content != null) {
      t.name = content.name;
      t.files = [for (final f in content.files) FakeFile(f.$1, f.$2)];
    }
    t.hasMetadata = true;
  }

  Map<String, Object?> _info(FakeTorrent t) => {
        'hash': t.hash,
        'infohash_v1': t.hash,
        'infohash_v2': '',
        'name': t.name,
        'state': stateOf(t),
        'progress': _wanted(t) == 0 ? 0.0 : _have(t) / _wanted(t),
        'size': t.hasMetadata ? _wanted(t) : -1,
        'total_size': t.hasMetadata ? t.files.fold<int>(0, (n, f) => n + f.size) : -1,
        'completed': _have(t),
        'amount_left': t.hasMetadata ? _left(t) : -1,
        'dlspeed': t.dlspeed,
        'upspeed': t.upspeed,
        'save_path': t.savePath,
        'content_path': '${t.savePath}/${t.name}',
        'category': t.category,
        'tags': '',
        'num_seeds': 1,
        'num_leechs': 0,
        'num_complete': 3,
        'num_incomplete': 1,
        'availability': 1.0,
        'ratio': 0.0,
        'eta': 8640000,
        'added_on': 1700000000,
        'completion_on': -1,
      };

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path;
    requests.add('${request.method} $path');
    origins.add(request.headers.value('origin'));
    final authorization = request.headers.value(HttpHeaders.authorizationHeader);
    authorizations.add(authorization);
    if (requireBasicAuth &&
        authorization != 'Basic ${base64Encode(utf8.encode('$username:$password'))}') {
      basicChallenges++;
      await request.drain<void>();
      response.statusCode = HttpStatus.unauthorized;
      response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="seedbox"');
      return response.close();
    }
    if (!path.startsWith('$basePath/api/v2/')) {
      response.statusCode = 404;
      return response.close();
    }
    final endpoint = path.substring('$basePath/api/v2/'.length);
    final body = await request.fold<BytesBuilder>(
        BytesBuilder(copy: false), (b, chunk) => b..add(chunk));
    final bytes = body.takeBytes();
    final contentType = request.headers.contentType;
    final form = <String, String>{...request.uri.queryParameters};
    final files = <String, Uint8List>{};
    if (contentType?.mimeType == 'application/x-www-form-urlencoded') {
      form.addAll(Uri.splitQueryString(utf8.decode(bytes)));
    } else if (contentType?.mimeType == 'multipart/form-data') {
      _multipart(bytes, contentType!.parameters['boundary']!, form, files);
    }
    Future<void> reply(int status, [Object? json, String? text]) async {
      response.statusCode = status;
      if (json != null) {
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(json));
      } else if (text != null) {
        response.headers.contentType = ContentType.text;
        response.write(text);
      }
      await response.close();
    }

    // qBittorrent 4 answers a login 200 "Ok." / "Fails." with a cookie SID;
    // 5.3 answers 204 / 401 with a cookie QBT_SID_<port>; an unauthenticated
    // call is 403 before 5.3 and 401 in it.
    final cookieName = v5 ? 'QBT_SID_${server.port}' : 'SID';
    if (endpoint == 'auth/login') {
      if (form['username'] == username && form['password'] == password) {
        logins++;
        sid = 'sid${logins}x';
        response.headers.add('set-cookie', '$cookieName=$sid; HttpOnly; path=/');
        return v5 ? reply(204) : reply(200, null, 'Ok.');
      }
      rejectedLogins++;
      return v5 ? reply(401, null, 'Unauthorized') : reply(200, null, 'Fails.');
    }
    if (requireAuth &&
        (sid == null ||
            !(request.headers.value('cookie') ?? '').contains('$cookieName=$sid'))) {
      return v5 ? reply(401, null, 'Unauthorized') : reply(403, null, 'Forbidden');
    }
    switch (endpoint) {
      case 'app/version':
        return reply(200, null, v5 ? 'v5.0.4' : 'v4.6.7');
      case 'app/webapiVersion':
        return reply(200, null, v5 ? '2.11.2' : '2.9.3');
      case 'torrents/info':
        final wanted = form['hashes']?.split('|');
        return reply(200, [
          for (final t in torrents.values)
            if (wanted == null || wanted.contains(t.hash)) _info(t)
        ]);
      case 'torrents/files':
        final t = torrents[form['hash']];
        if (t == null) return reply(404);
        if (!t.hasMetadata) return reply(409);
        return reply(200, [
          for (final (i, f) in t.files.indexed)
            {
              'index': i,
              'name': f.name,
              'size': f.size,
              'progress': f.progress,
              'priority': f.priority,
              'is_seed': false,
              'availability': 1.0,
            }
        ]);
      case 'torrents/add':
        final urls = form['urls'];
        final paused = form['stopped'] == 'true' || form['paused'] == 'true';
        late final FakeTorrent t;
        if (urls != null) {
          final hash = RegExp(r'btih:([0-9a-f]{40})').firstMatch(urls)!.group(1)!;
          final content = magnetContents[hash];
          t = FakeTorrent(hash, hash, form['savepath'] ?? '/downloads', [],
              hasMetadata: false);
          if (content == null) {
            torrents[hash] = t;
          } else {
            torrents[hash] = t;
            if (metadataDelay != null) {
              Timer(metadataDelay!, () {
                if (torrents.containsKey(hash)) reveal(hash);
              });
            }
          }
        } else if (files.containsKey('torrents')) {
          final torrent = files['torrents']!;
          final manifest = torrentManifest(torrent);
          final hash = torrentInfoHash(torrent);
          t = FakeTorrent(
              hash,
              manifest['name'] as String,
              form['savepath'] ?? '/downloads',
              [
                for (final f in (manifest['files'] as List).cast<Map>())
                  FakeFile(f['path'] as String, f['length'] as int)
              ]);
          torrents[hash] = t;
        } else {
          return reply(200, null, 'Fails.');
        }
        t.paused = paused;
        t.category = form['category'] ?? '';
        t.contentLayout = form['contentLayout'];
        return v5
            ? reply(200, {
                'added_torrent_ids': [t.hash],
                'failure_count': 0,
                'pending_count': 0,
                'success_count': 1
              })
            : reply(200, null, 'Ok.');
      case 'torrents/filePrio':
        final t = torrents[form['hash']];
        if (t == null) return reply(404);
        for (final id in form['id']!.split('|')) {
          t.files[int.parse(id)].priority = int.parse(form['priority']!);
        }
        return reply(200);
      case 'torrents/pause' when !v5:
      case 'torrents/stop' when v5:
        for (final h in form['hashes']!.split('|')) {
          torrents[h]?.paused = true;
        }
        return reply(200);
      case 'torrents/resume' when !v5:
      case 'torrents/start' when v5:
        for (final h in form['hashes']!.split('|')) {
          torrents[h]?.paused = false;
        }
        return reply(200);
      case 'torrents/delete':
        for (final h in form['hashes']!.split('|')) {
          torrents.remove(h);
        }
        deletions.add(form['deleteFiles'] ?? '');
        return reply(200);
      case 'transfer/downloadLimit':
        return reply(200, null, '$downloadLimit');
      case 'transfer/uploadLimit':
        return reply(200, null, '$uploadLimit');
      case 'transfer/setDownloadLimit':
        downloadLimit = int.parse(form['limit']!);
        return reply(200);
      case 'transfer/setUploadLimit':
        uploadLimit = int.parse(form['limit']!);
        return reply(200);
      case 'transfer/speedLimitsMode':
        return reply(200, null, '0');
    }
    return reply(404);
  }

  /// The `deleteFiles` value of every delete call, in order.
  final deletions = <String>[];

  static void _multipart(Uint8List bytes, String boundary,
      Map<String, String> form, Map<String, Uint8List> files) {
    final text = latin1.decode(bytes);
    for (final part in text.split('--$boundary')) {
      final split = part.indexOf('\r\n\r\n');
      if (split < 0) continue;
      final head = part.substring(0, split);
      var content = part.substring(split + 4);
      if (content.endsWith('\r\n')) {
        content = content.substring(0, content.length - 2);
      }
      final name = RegExp(r'name="([^"]*)"').firstMatch(head)?.group(1);
      if (name == null) continue;
      if (head.contains('filename=')) {
        files[name] = Uint8List.fromList(latin1.encode(content));
      } else {
        form[name] = utf8.decode(latin1.encode(content));
      }
    }
  }
}
