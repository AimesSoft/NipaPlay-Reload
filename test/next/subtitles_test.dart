import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/subtitles/library.dart';
import 'package:nipaplay/next/subtitles/capability.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'media_test_support.dart';

void main() {
  late MediaFixture f;
  late SubtitleLibrary library;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    f = MediaFixture();
    await f.open();
    library = SubtitleLibrary(f.service, f.root,
        probe: (_) async => {
              'subtitles': [
                {
                  'index': 0,
                  'streamIndex': 2,
                  'language': 'jpn',
                  'title': 'Japanese',
                  'format': 'ass'
                }
              ]
            });
  });
  tearDown(() async {
    await library.close();
    await f.close();
  });

  test(
      'import survives deleted original and database restart, invalid batch preserves prior track and choice',
      () async {
    final id = await f.file('show01.mkv');
    await library.inspect(id, '${f.media.path}/show01.mkv');
    final source = File('${f.root.path}/incoming.srt');
    await source.writeAsString('1\n00:00:00,000 --> 00:00:04,000\n字幕持久保存\n');
    final harness = Harness([SubtitleCapability(library)]);
    final result = await harness.invokeJson(
        'subtitle.import',
        {
          'entries': [
            {
              'fileId': id,
              'filePath': source.path,
              'language': 'zh-Hans',
              'source': {'label': 'test'}
            }
          ]
        },
        Invocation(origin: 'mcp'));
    expect(result, isA<Completed>());
    final imported =
        ((result as Completed).value.toJson()['entries'] as List).single as Map;
    final track = imported['track'] as Map;
    await library.select(id, track['id'] as String);
    await source.delete();
    await f.reopen();
    final reopened = SubtitleLibrary(f.service, f.root,
        probe: (_) async => {'subtitles': []});
    var facts = await reopened.facts(id);
    expect(
        (facts['tracks'] as List).where((t) => t['origin'] == 'import').length,
        1);
    expect(
        await File(track['path'] as String).readAsString(), contains('字幕持久保存'));
    final invalid = File('${f.root.path}/invalid.srt');
    await invalid.writeAsString('an HTML error page, no timed cues');
    final failed = await Harness([SubtitleCapability(reopened)]).invokeJson(
        'subtitle.import',
        {
          'entries': [
            {
              'fileId': id,
              'filePath': invalid.path,
              'language': 'zh',
              'source': {'label': 'test'}
            }
          ]
        },
        Invocation(origin: 'mcp'));
    expect(
        ((failed as Completed).value.toJson()['entries'] as List)
            .single['saved'],
        false);
    facts = await reopened.facts(id);
    expect((facts['selection'] as Map)['trackId'], track['id']);
    await reopened.close();
  });

  test(
      'sidecar references disappear honestly while explicit disable survives rescan',
      () async {
    final id = await f.file('show01.mkv');
    final sidecar = File('${f.media.path}/show01.chs.ass');
    await sidecar.writeAsString('[Script Info]\n');
    await library.inspect(id, '${f.media.path}/show01.mkv');
    var facts = await library.facts(id);
    expect(
        (facts['tracks'] as List)
            .where((t) => t['origin'] == 'embedded')
            .single['language'],
        'ja');
    expect(
        (facts['tracks'] as List)
            .where((t) => t['origin'] == 'sidecar')
            .single['language'],
        'zh-Hans');
    await library.select(id, null);
    await sidecar.delete();
    await library.inspect(id, '${f.media.path}/show01.mkv');
    facts = await library.facts(id);
    expect(
        (facts['tracks'] as List)
            .where((t) => t['origin'] == 'sidecar')
            .single['available'],
        false);
    expect((facts['selection'] as Map)['basis'], 'explicit');
    expect((facts['selection'] as Map)['trackId'], null);
  });

  test('language-only Subs ownership requires exactly one video', () async {
    final id = await f.file('movie.mkv');
    final subs = await Directory('${f.media.path}/Subs').create();
    await File('${subs.path}/English.srt')
        .writeAsString('1\n00:00:00,000 --> 00:00:01,000\nhello\n');
    await library.inspect(id, '${f.media.path}/movie.mkv');
    expect(
        (await library.facts(id))['tracks'],
        contains(isA<Map>().having(
            (m) => m['matchBasis'], 'basis', 'single_video_subdirectory')));
    await f.file('another.mkv');
    await library.inspect(id, '${f.media.path}/movie.mkv');
    expect(
        ((await library.facts(id))['tracks'] as List)
            .where((t) => t['origin'] == 'sidecar' && t['available'] == true),
        isEmpty);
  });

  test(
      'missing Classic map never treats pathless embedded tracks as a saved choice',
      () async {
    final id = await f.file('embedded.mkv');
    final l = SubtitleLibrary(f.service, f.root,
        probe: (_) async => {
              'subtitles': [
                {'index': 0, 'language': 'und', 'title': null, 'format': 'ass'},
                {'index': 1, 'language': 'eng', 'title': null, 'format': 'ass'}
              ]
            });
    await l.inspect(id, '${f.media.path}/embedded.mkv');
    final selection = (await l.facts(id))['selection'] as Map;
    expect(selection['basis'], 'language_preference');
    expect(selection['trackId'], 'embedded:1');
    await l.close();
  });

  test(
      'indexing reads Classic choices without pruning or rewriting their preferences',
      () async {
    final id = await f.file('classic.mkv');
    final path = '${f.media.path}/classic.mkv';
    final missing = '${f.root.path}/missing.srt';
    await SubtitleService().addExternalSubtitle(
        path, {'path': missing, 'name': 'saved English.srt', 'isActive': true});
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
    await library.inspect(id, path);
    expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, before);
    expect(
        ((await library.facts(id))['tracks'] as List)
            .where((t) => t['origin'] == 'classic')
            .single['available'],
        false);
  });

  test(
      'WebVTT copies original bytes and retains playable timed cues after source removal',
      () async {
    final id = await f.file('vtt.mkv');
    final source = File('${f.root.path}/english.vtt');
    await source.writeAsString(
        'WEBVTT\n\ncue-id\n00:01.000 --> 00:03.000 align:start\n<v Narrator>Hello</v>\n');
    final result = await library.importSubtitle({
      'fileId': id,
      'filePath': source.path,
      'language': 'en',
      'source': {'label': 'test'}
    }, Invocation(origin: 'mcp'));
    final track = result['track'] as Map;
    await source.delete();
    expect(await File(track['path'] as String).readAsString(),
        startsWith('WEBVTT'));
    expect(await File(track['playbackPath'] as String).readAsString(),
        contains('00:00:01,000 --> 00:00:03,000\nHello'));
  });
}
