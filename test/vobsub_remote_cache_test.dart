import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/remote_subtitle_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory dir;
  late HttpServer server;
  late PathProviderPlatform previousPaths;
  late List<int> bitmap;
  late String index;
  late bool failBitmap;
  late List<String> requests;
  final service = RemoteSubtitleService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('vobsub_cache_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
    bitmap = [0, 0, 1, 0xba, 0, 0, 0, 1];
    index = '# VobSub index file, v7\nid: en, index: 0\n';
    failBitmap = false;
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri.path);
      if (request.uri.path.endsWith('.sub')) {
        if (failBitmap) {
          request.response.statusCode = 503;
        } else {
          request.response.add(bitmap);
        }
      } else {
        request.response.write(index);
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    PathProviderPlatform.instance = previousPaths;
    await dir.delete(recursive: true);
  });
  SharedRemoteSubtitleCandidate candidate(String extension,
          {String source = 'A', int? size}) =>
      SharedRemoteSubtitleCandidate(
        shareId: source,
        fileName: 'Show$extension',
        name: 'Show$extension',
        subtitleUri:
            Uri.parse('http://127.0.0.1:${server.port}/$source/Show$extension'),
        authorizationHeader: null,
        isLikelyMatch: true,
        extension: extension,
        fileSize: size,
      );
  Future<void> completePair(String path) async {
    expect(p.extension(path), '.idx');
    expect(await File(path).readAsString(), index);
    expect(await File(p.setExtension(path, '.sub')).readAsBytes(), bitmap);
    expect(await service.lookupDisplayName(path), 'Show.idx');
  }

  for (final entry in ['.sub', '.idx']) {
    test('$entry entry publishes a complete pair and repairs a missing member',
        () async {
      final idx = candidate('.idx'), sub = candidate('.sub');
      final all = [idx, sub];
      final path = await service.ensureSubtitleCached(
          entry == '.sub' ? sub : idx,
          allCandidates: all);
      await completePair(path);
      final count = requests.length;
      expect(await service.ensureSubtitleCached(idx, allCandidates: all), path);
      expect(requests.length, count);
      await File(p.setExtension(path, '.sub')).delete();
      final repaired =
          await service.ensureSubtitleCached(idx, allCandidates: all);
      await completePair(repaired);
      expect(requests.length, greaterThan(count));
      // A truncated MPEG-PS file can still have a valid header. Verify the
      // generation digest, not just existence and the first four bytes.
      await File(p.setExtension(repaired, '.sub'))
          .writeAsBytes([0, 0, 1, 0xba]);
      await completePair(
          await service.ensureSubtitleCached(idx, allCandidates: all));
    });
  }

  test('failed second download is never published and a retry succeeds',
      () async {
    final idx = candidate('.idx'), sub = candidate('.sub');
    failBitmap = true;
    await expectLater(
        service.ensureSubtitleCached(idx, allCandidates: [idx, sub]),
        throwsA(anything));
    expect(
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => p.basename(f.path) == 'current'),
        isEmpty);
    failBitmap = false;
    await completePair(
        await service.ensureSubtitleCached(idx, allCandidates: [idx, sub]));
  });

  test('refresh preserves the complete pair referenced by existing mappings',
      () async {
    final idx = candidate('.idx'), sub = candidate('.sub');
    final old =
        await service.ensureSubtitleCached(idx, allCandidates: [idx, sub]);
    final oldBytes = await File(p.setExtension(old, '.sub')).readAsBytes();
    bitmap = [...bitmap, 42];
    index += '# refreshed\n';
    final fresh = await service.ensureSubtitleCached(idx,
        allCandidates: [idx, sub], forceRefresh: true);
    expect(fresh, isNot(old));
    await completePair(fresh);
    expect(await File(p.setExtension(old, '.sub')).readAsBytes(), oldBytes);
    failBitmap = true;
    await expectLater(
        service.ensureSubtitleCached(idx,
            allCandidates: [idx, sub], forceRefresh: true),
        throwsA(anything));
    expect(await service.ensureSubtitleCached(idx, allCandidates: [idx, sub]),
        fresh);
  });

  test('text SUB stays standalone and binary SUB rejects a missing index',
      () async {
    bitmap = utf8.encode('{0}{50}MicroDVD subtitle');
    final sub = candidate('.sub');
    final path = await service.ensureSubtitleCached(sub);
    expect(p.extension(path), '.sub');
    expect(await File(path).readAsString(), '{0}{50}MicroDVD subtitle');
    bitmap = [0, 0, 1, 0xba, 0];
    await expectLater(service.ensureSubtitleCached(sub, forceRefresh: true),
        throwsStateError);
  });

  test(
      'same names across sources remain isolated and pair only in their directory',
      () async {
    final idxA = candidate('.idx'), subA = candidate('.sub');
    final idxB = candidate('.idx', source: 'B'),
        subB = candidate('.sub', source: 'B');
    await expectLater(service.ensureSubtitleCached(idxA, allCandidates: [subB]),
        throwsStateError);
    final a =
        await service.ensureSubtitleCached(idxA, allCandidates: [subA, subB]);
    bitmap = [...bitmap, 99];
    final b =
        await service.ensureSubtitleCached(idxB, allCandidates: [subA, subB]);
    expect(a, isNot(b));
    expect(await File(p.setExtension(a, '.sub')).length(), 8);
    await completePair(b);
  });

  test('concurrent SUB and IDX requests return the same complete pair',
      () async {
    final idx = candidate('.idx'), sub = candidate('.sub');
    final paths = await Future.wait([
      service.ensureSubtitleCached(sub, allCandidates: [idx, sub]),
      service.ensureSubtitleCached(idx, allCandidates: [idx, sub]),
      service.ensureSubtitleCached(sub, allCandidates: [idx, sub]),
    ]);
    expect(paths.toSet().length, 1);
    await completePair(paths.first);
  });

  test('declared-size truncation cannot publish a pair', () async {
    final idx = candidate('.idx'), sub = candidate('.sub', size: 100);
    await expectLater(
        service.ensureSubtitleCached(idx, allCandidates: [idx, sub]),
        throwsStateError);
    expect(
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => p.basename(f.path) == 'current'),
        isEmpty);
  });
}
