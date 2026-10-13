import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/subtitles/library_io.dart';
import 'package:nipaplay/next/subtitles/capability.dart';
import 'media_test_support.dart';

void main() {
  late MediaFixture f;
  late SubtitleLibrary library;
  setUp(() async { f = MediaFixture(); await f.open(); library = SubtitleLibrary(f.service, f.root); });
  tearDown(() async { await library.close(); await f.close(); });
  test('headless imported content and explicit default survive source deletion and reopen', () async {
    final id = await f.file('show01.mkv');
    final source = await File('${f.root.path}/provided.srt')
        .writeAsString('1\n00:00:00,000 --> 00:00:01,000\n字幕\n');
    final entries = <JsonMap>[{'fileId': id, 'filePath': source.path,
      'language': 'zh-Hans', 'source': {'label': 'fixture'}}];
    final input = {'entries': entries};
    final imported = await Harness([SubtitleCapability(library)]).invokeJson('subtitle.import', input,
        Invocation(origin: 'mesh:mac')) as Completed;
    final track = ((imported.value.toJson()['entries'] as List).first as Map)['track'] as Map;
    await library.select(id, track['id'] as String);
    await source.delete();
    await library.close();
    await f.reopen();
    library = SubtitleLibrary(f.service, f.root);
    final value = await library.facts(id);
    expect((value['selection'] as Map)['trackId'], track['id']);
    expect(await File(track['path'] as String).readAsString(), contains('字幕'));
    final invalid = await File('${f.root.path}/bad.srt').writeAsString('<html>failed</html>');
    entries.single['filePath'] = invalid.path;
    final failed = await Harness([SubtitleCapability(library)]).invokeJson('subtitle.import', input,
        Invocation(origin: 'mesh:mac')) as Completed;
    expect(((failed.value.toJson()['entries'] as List).first as Map)['saved'], false);
    expect(((await library.facts(id))['selection'] as Map)['trackId'], track['id']);
    expect(await f.jobs.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  test('invalid subtitle selection preserves explicit disable and another file facts', () async {
    final one = await f.file('show01.mkv'), two = await f.file('show02.mkv');
    await library.select(one, null);
    expect(() => library.select(two, 'missing'), throwsA(isA<Failure>()));
    expect(((await library.facts(one))['selection'] as Map)['trackId'], isNull);
    expect(((await library.facts(one))['selection'] as Map)['basis'], 'explicit');
    expect((await library.facts(two))['tracks'], isEmpty);
  });
}
