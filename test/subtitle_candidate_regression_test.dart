import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/utils/subtitle_manager.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';
import 'package:nipaplay/services/remote_subtitle_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends Fake implements MediaKitPlayerAdapter {
  final selected = <String>[];
  @override
  bool get supportsExternalSubtitles => true;
  @override
  List<int> get activeSubtitleTracks => [];
  @override
  PlayerMediaInfo get mediaInfo => PlayerMediaInfo(duration: 10000);
  @override
  void setMedia(String path, PlayerMediaType type) {
    selected.add(path);
  }

  @override
  void setProperty(String name, String value) {}
}

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
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('review957_');
  });

  test('registering an alternate ASS must preserve native primary selection',
      () async {
    const ass =
        '[Script Info]\nScriptType: v4.00+\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:00.00,0:00:05.00,Default,,0,0,0,,Hello\n';
    final primary = File('${dir.path}/Show.SC.ass')..writeAsStringSync(ass);
    final alternate = File('${dir.path}/Show.TC.ass')..writeAsStringSync(ass);
    final delegate = _Player();
    final manager = SubtitleManager(player: Player.withDelegate(delegate));
    manager.setCurrentVideoPath('${dir.path}/Show.mkv');
    manager.setExternalSubtitle(primary.path);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(delegate.selected.last, primary.path);
    await manager.registerExternalSubtitleCandidate(alternate.path);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(delegate.selected.last, primary.path);
    expect(manager.getAllActiveExternalSubtitlePaths(), [primary.path]);
    expect(
        manager.subtitleTrackInfo['external_subtitle']!['path'], primary.path);
    await manager.addExternalSubtitleToStack(alternate.path);
    expect(delegate.selected.last, alternate.path);
    expect(manager.getAllActiveExternalSubtitlePaths(), [alternate.path]);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs
        .getKeys()
        .firstWhere((key) => key.startsWith('external_subtitles_'));
    final entries = json.decode(prefs.getString(raw)!) as List;
    expect(entries.singleWhere((e) => e['path'] == primary.path)['isActive'],
        false);
    expect(entries.singleWhere((e) => e['path'] == alternate.path)['isActive'],
        true);
  });

  test('restoring episode 1 must not activate episode 2 subtitles', () async {
    final video = File('${dir.path}/Show.01.mkv')..writeAsStringSync('video');
    final alternate = File('${dir.path}/Show.01.eng.srt')
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:05,000\nALT\n');
    final primary = File('${dir.path}/Show.01.srt')
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:05,000\nONE\n');
    File('${dir.path}/Show.02.srt')
        .writeAsStringSync('1\n00:00:00,000 --> 00:00:05,000\nTWO\n');
    final manager = SubtitleManager(player: Player.withDelegate(_Player()));
    manager.setCurrentVideoPath(video.path);
    await manager.saveVideoSubtitleMapping(video.path, primary.path);
    await manager.autoDetectAndLoadSubtitle(video.path);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(manager.getAllActiveExternalSubtitlePaths(), [primary.path]);
    final prefs = await SharedPreferences.getInstance();
    final entries = json
        .decode(prefs.getString('external_subtitles_Show.01.mkv-5')!) as List;
    expect(entries.map((e) => e['path']),
        containsAll([primary.path, alternate.path]));
    expect(entries.length, 2);
  });

  test('remote binary sub must cache its paired idx as well', () async {
    PathProviderPlatform.instance = _Paths(dir.path);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path.endsWith('.sub')) {
        request.response.add([0, 0, 1, 0xba, 0, 0, 0, 0]);
      } else {
        request.response.write('# VobSub index file, v7\n');
      }
      await request.response.close();
    });
    SharedRemoteSubtitleCandidate candidate(String ext) =>
        SharedRemoteSubtitleCandidate(
          shareId: 'test',
          fileName: 'Show$ext',
          subtitleUri: Uri.parse('http://127.0.0.1:${server.port}/Show$ext'),
          authorizationHeader: null,
          isLikelyMatch: true,
          name: 'Show$ext',
          extension: ext,
        );
    final sub = candidate('.sub'), idx = candidate('.idx');
    final path = await RemoteSubtitleService.instance
        .ensureSubtitleCached(sub, allCandidates: [sub, idx]);
    expect(File(p.setExtension(path, '.idx')).existsSync(), isTrue);
  });

  test('automatic alternate subtitle must be present in the menu data',
      () async {
    final video = File('${dir.path}/Show.mkv')..writeAsStringSync('video');
    final primary = File('${dir.path}/Show.ass')
      ..writeAsStringSync('[Script Info]\n');
    final alternate = File('${dir.path}/Show.ssa')
      ..writeAsStringSync('[Script Info]\n');
    final manager = SubtitleManager(player: Player.withDelegate(_Player()));
    manager.setCurrentVideoPath(video.path);
    await manager.autoDetectAndLoadSubtitle(video.path);
    final prefs = await SharedPreferences.getInstance();
    final entries =
        json.decode(prefs.getString('external_subtitles_Show.mkv-5')!) as List;
    expect(entries.map((s) => s['path']),
        containsAll([primary.path, alternate.path]));
    expect(entries.singleWhere((s) => s['path'] == alternate.path)['isActive'],
        false);
    expect(manager.getAllActiveExternalSubtitlePaths(), [primary.path]);
  });
  test('fresh fuzzy detection excludes other episodes, seasons and series',
      () async {
    final video = File('${dir.path}/Show.S01E01.mkv')
      ..writeAsStringSync('video');
    final primary = File('${dir.path}/Show.S01E01.SC.srt')
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:05,000\nONE\n');
    final alternate = File('${dir.path}/Show.S01E01.TC.srt')
      ..writeAsStringSync(primary.readAsStringSync());
    for (final name in [
      'Show.S01E02.SC',
      'Show.S02E01.SC',
      'Other.S01E01.SC'
    ]) {
      File('${dir.path}/$name.srt')
          .writeAsStringSync(primary.readAsStringSync());
    }
    final manager = SubtitleManager(player: Player.withDelegate(_Player()));
    manager.setCurrentVideoPath(video.path);
    await manager.autoDetectAndLoadSubtitle(video.path);
    expect(manager.getAllActiveExternalSubtitlePaths(), [primary.path]);
    final prefs = await SharedPreferences.getInstance();
    final entries =
        json.decode(prefs.getString('external_subtitles_Show.S01E01.mkv-5')!)
            as List;
    expect(entries.map((s) => s['path']),
        unorderedEquals([primary.path, alternate.path]));
  });

  test('episode change cancels delayed automatic activation', () async {
    final video = File('${dir.path}/Show.01.mkv')..writeAsStringSync('video');
    final primary = File('${dir.path}/Show.01.srt')
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:05,000\nONE\n');
    final manager = SubtitleManager(player: Player.withDelegate(_Player()));
    manager.setCurrentVideoPath(video.path);
    await manager.saveVideoSubtitleMapping(video.path, primary.path);
    final pending = manager.autoDetectAndLoadSubtitle(video.path);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    manager.clearExternalSubtitle();
    manager.setCurrentVideoPath('${dir.path}/Show.02.mkv');
    await pending;
    expect(manager.getAllActiveExternalSubtitlePaths(), isEmpty);
  });

  test('explicit native switching retains app-rendered stack', () async {
    final delegate = _Player();
    final manager = SubtitleManager(player: Player.withDelegate(delegate));
    final srt = File('${dir.path}/Show.srt')
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:05,000\nONE\n');
    final ass = File('${dir.path}/Show.ass')
      ..writeAsStringSync('[Script Info]\n');
    final ssa = File('${dir.path}/Show.ssa')
      ..writeAsStringSync('[Script Info]\n');
    await manager.addExternalSubtitleToStack(ass.path);
    await manager.addExternalSubtitleToStack(srt.path);
    await manager.addExternalSubtitleToStack(ssa.path);
    expect(delegate.selected.last, ssa.path);
    expect(manager.getAllActiveExternalSubtitlePaths(),
        unorderedEquals([srt.path, ssa.path]));
  });

  test(
      'local VobSub recognizes uppercase companions and text SUB remains standalone',
      () {
    final sub = File('${dir.path}/Show.SUB')
      ..writeAsBytesSync([0, 0, 1, 0xba, 0, 0]);
    expect(isVobSubPairComplete(sub.path), false);
    final idx = File('${dir.path}/Show.IDX')
      ..writeAsStringSync('# VobSub index file, v7\n');
    expect(isVobSubPairComplete(sub.path), true);
    expect(isVobSubPairComplete(idx.path), true);
    expect(canonicalSubtitlePath(sub.path), idx.path);
    final text = File('${dir.path}/MicroDVD.sub')
      ..writeAsStringSync('{0}{50}Text');
    expect(isVobSubPairComplete(text.path), true);
    expect(canonicalSubtitlePath(text.path), text.path);
  });
  test('binary SUB mounts the paired IDX directly in the native player',
      () async {
    final sub = File('${dir.path}/Show.sub')
      ..writeAsBytesSync([0, 0, 1, 0xba, 0, 0]);
    final idx = File('${dir.path}/Show.idx')
      ..writeAsBytesSync([0xff, 0xfe, 35, 0, 10, 0]);
    final delegate = _Player();
    final manager = SubtitleManager(player: Player.withDelegate(delegate));
    await manager.addExternalSubtitleToStack(sub.path);
    expect(delegate.selected, [idx.path]);
    expect(manager.getAllActiveExternalSubtitlePaths(), [idx.path]);
  });

  test('shared stream auto-loads only server-matched candidates', () async {
    PathProviderPlatform.instance = _Paths(dir.path);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final downloaded = <String>[];
    server.listen((request) async {
      if (request.uri.path.endsWith('/subtitles')) {
        request.response.write(json.encode({
          'items': [
            {'name': 'Show.01.SC.srt', 'isLikelyMatch': true},
            {'name': 'Show.01.TC.srt', 'isLikelyMatch': true},
            {'name': 'Show.02.SC.srt', 'isLikelyMatch': false},
          ]
        }));
      } else if (request.uri.path.endsWith('/subtitle')) {
        downloaded.add(request.uri.queryParameters['name']!);
        request.response.write('1\n00:00:00,000 --> 00:00:05,000\nONE\n');
      } else {
        request.response.write('{"items":[]}');
      }
      await request.response.close();
    });
    final video =
        'http://127.0.0.1:${server.port}/api/media/local/share/episodes/123/stream';
    final manager = SubtitleManager(player: Player.withDelegate(_Player()));
    manager.setCurrentVideoPath(video);
    await manager.autoDetectAndLoadSubtitle(video);
    expect(manager.getAllActiveExternalSubtitlePaths().length, 1);
    expect(downloaded, unorderedEquals(['Show.01.SC.srt', 'Show.01.TC.srt']));
    final prefs = await SharedPreferences.getInstance();
    final key =
        prefs.getKeys().firstWhere((k) => k.startsWith('external_subtitles_'));
    final entries = json.decode(prefs.getString(key)!) as List;
    expect(entries.where((e) => e['isActive'] == true).length, 1);
    expect(entries.map((e) => e['name']),
        unorderedEquals(['Show.01.SC.srt', 'Show.01.TC.srt']));
    downloaded.clear();
    manager.clearExternalSubtitle();
    await manager.autoDetectAndLoadSubtitle(video);
    expect(manager.getAllActiveExternalSubtitlePaths().length, 1);
    expect(downloaded, isEmpty);
  });
}
