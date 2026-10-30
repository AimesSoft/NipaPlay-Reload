import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/downloads/download_source.dart';

void main() {
  const info = 'd6:lengthi4e4:name11:episode.mkve';
  final torrent = Uint8List.fromList(ascii.encode('d4:info${info}e'));
  final hash = sha1.convert(ascii.encode(info)).toString();
  test('magnet hex and base32 normalize to the same stable content identity',
      () async {
    final sources = DownloadSources(Directory('/unused'));
    final a =
        await sources.prepare('magnet:?xt=urn:btih:${'0' * 40}&dn=Episode');
    final b = await sources.prepare('magnet:?xt=urn:btih:${'A' * 32}');
    expect(a.infoHash, b.infoHash);
    expect(a.title, 'Episode');
    await expectLater(
        sources.prepare('magnet:?xt=urn:btih:bad'), throwsA(isA<Failure>()));
    await expectLater(sources.prepare('ftp://example.com/file.torrent'),
        throwsA(isA<Failure>()));
    await expectLater(
        sources.prepare('magnet:?xt=urn:btih:${'0' * 40}&dn='),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', FailureCode.invalidInput)));
    for (final source in [
      'http:///file.torrent',
      'file://remote/file.torrent',
      'file:///tmp/file.torrent?query=1'
    ]) {
      await expectLater(
          sources.prepare(source),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.invalidInput)));
    }
  });
  test('local metadata is hashed verbatim and cached for recovery', () async {
    final root = await Directory.systemTemp.createTemp('torrent-source-');
    addTearDown(() => root.delete(recursive: true));
    final file =
        await File('${root.path}/picked.torrent').writeAsBytes(torrent);
    final sources = DownloadSources(Directory('${root.path}/cache'));
    final request = await sources.prepare(file.path);
    await file.delete();
    expect(request.infoHash, hash);
    expect(request.title, 'episode.mkv');
    expect(await File(request.source).readAsBytes(), torrent);
    expect(torrentInfoHash(torrent), hash);
  });
  test('HTTP torrent metadata is bounded, validated and cached', () async {
    final root = await Directory.systemTemp.createTemp('torrent-url-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await root.delete(recursive: true);
    });
    server.listen((request) async {
      if (request.uri.path == '/missing') {
        request.response.statusCode = 404;
      } else {
        request.response.add(torrent);
      }
      await request.response.close();
    });
    final sources = DownloadSources(root,
        clientFactory: () => HttpClient()..findProxy = (_) => 'DIRECT');
    final request = await sources
        .prepare('http://127.0.0.1:${server.port}/$hash.torrent');
    expect(request.infoHash, hash);
    expect(request.title, 'episode.mkv');
    expect(await File(request.source).readAsBytes(), torrent);
    await expectLater(
        sources.prepare('http://127.0.0.1:${server.port}/missing'),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', FailureCode.unavailable)));
  });
  test('malformed and ambiguous metadata fail at the source boundary', () {
    for (final value in [
      'd4:infoi1ee',
      'd4:infod',
      'd4:info${info}4:info${info}e',
      'd4:info${info}etrailing',
      'd4:infod4:name99:shorte',
      'l${info}e',
      'd3:fooi1ee'
    ]) {
      expect(() => torrentInfoHash(Uint8List.fromList(ascii.encode(value))),
          throwsA(isA<Failure>()),
          reason: value);
    }
  });

  test('unreachable torrent URL reports unavailable rather than internal',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);
    final sources = DownloadSources(Directory('/unused'),
        clientFactory: () => HttpClient()..findProxy = (_) => 'DIRECT');
    await expectLater(
        sources.prepare('http://127.0.0.1:$port/file.torrent'),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', FailureCode.unavailable)));
  });
}
