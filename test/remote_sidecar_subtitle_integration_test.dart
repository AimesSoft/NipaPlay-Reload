import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/dandanplay_remote_service.dart';
import 'package:nipaplay/utils/subtitle_manager.dart';
import 'package:nipaplay/utils/storage_service.dart';
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
  void setMedia(String path, PlayerMediaType type) => selected.add(path);
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

  for (final protocol in [true, false]) {
    test(
        'Dandanplay ${protocol ? 'protocol' : 'HTTP'} subtitles switch languages in the player',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('dandan_sidecar_');
      final oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(directory.path);
      final oldStorage = StorageService.debugAppStorageDirectoryOverride;
      StorageService.debugAppStorageDirectoryOverride = directory;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final downloaded = <String>[];
      server.listen((request) async {
        expect(request.headers.value('authorization'), 'Bearer fixture-token');
        if (request.uri.path == '/api/v1/library') {
          request.response.write('[]');
        } else if (request.uri.path == '/api/v1/subtitle/info/entry') {
          request.response.write(jsonEncode({
            'subtitles': [
              {'fileName': '字幕.SC.ass'},
              {'fileName': '字幕.JP.ass'},
            ]
          }));
        } else if (request.uri.path == '/api/v1/subtitle/file/entry') {
          final name = request.uri.queryParameters['fileName']!;
          downloaded.add(name);
          request.response.write('[Script Info]\nScriptType: v4.00+\n[Events]\n'
              'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
              'Dialogue: 0,0:00:00.00,0:00:05.00,Default,,0,0,0,,$name\n');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      addTearDown(() async {
        await DandanplayRemoteService.instance.disconnect();
        await server.close(force: true);
        PathProviderPlatform.instance = oldPaths;
        StorageService.debugAppStorageDirectoryOverride = oldStorage;
        await directory.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({
        'dandanplay_remote_base_url': 'http://127.0.0.1:${server.port}',
        'dandanplay_remote_api_token': 'fixture-token',
      });
      await DandanplayRemoteService.instance.loadSavedSettings();
      final delegate = _Player();
      final manager = SubtitleManager(player: Player.withDelegate(delegate));
      final video = protocol
          ? 'dandanplay://id/entry'
          : 'http://127.0.0.1:${server.port}/api/v1/stream/id/entry';
      manager.setCurrentVideoPath(video);
      await manager.autoDetectAndLoadSubtitle(video);
      expect(downloaded, unorderedEquals(['字幕.SC.ass', '字幕.JP.ass']));
      final prefs = await SharedPreferences.getInstance();
      final key = prefs
          .getKeys()
          .singleWhere((key) => key.startsWith('external_subtitles_'));
      final entries = jsonDecode(prefs.getString(key)!) as List;
      final simplified =
          entries.singleWhere((entry) => entry['name'] == '字幕.SC.ass')['path']
              as String;
      final japanese =
          entries.singleWhere((entry) => entry['name'] == '字幕.JP.ass')['path']
              as String;
      expect(simplified, isNot(japanese));
      await manager.addExternalSubtitleToStack(simplified,
          displayName: '字幕.SC.ass');
      expect(delegate.selected.last, simplified);
      await manager.addExternalSubtitleToStack(japanese,
          displayName: '字幕.JP.ass');
      expect(delegate.selected.last, japanese);
      expect(manager.getAllActiveExternalSubtitlePaths(), [japanese]);
      expect(File(japanese).readAsStringSync(), contains('字幕.JP.ass'));
      manager.setCurrentVideoPath('');
      manager.clearExternalSubtitle();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
  }
  test('authenticated DAV auto-discovers ASS and applies a different language',
      () async {
    final directory = await Directory.systemTemp.createTemp('dav_sidecar_');
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    final oldStorage = StorageService.debugAppStorageDirectoryOverride;
    StorageService.debugAppStorageDirectoryOverride = directory;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    final downloaded = <String>[];
    final authorization = 'Basic ${base64Encode(utf8.encode('user:password'))}';
    const names = [
      'Show 01.mkv',
      'Show 01.SC.ass',
      'Show 01.JP.ass',
      'Show 02.SC.ass'
    ];
    server.listen((request) async {
      final requestPath = '/${request.uri.pathSegments.join('/')}';
      requests.add('${request.method} $requestPath');
      if (request.headers.value('authorization') == null) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.set('www-authenticate', 'Basic realm="DAV"');
        await request.response.close();
        return;
      }
      expect(request.headers.value('authorization'), authorization);
      if (request.method == 'PROPFIND') {
        request.response.statusCode = HttpStatus.multiStatus;
        request.response.headers.contentType =
            ContentType('application', 'xml');
        request.response.write(
            '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">'
            '<d:response><d:href>/dav/Anime/</d:href><d:propstat>'
            '<d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>'
            '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>'
            '${names.map((name) => '<d:response><d:href>${Uri(path: '/dav/Anime/$name')}</d:href>'
                '<d:propstat><d:prop><d:displayname>$name</d:displayname>'
                '<d:resourcetype/><d:getcontentlength>512</d:getcontentlength></d:prop>'
                '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>').join()}'
            '</d:multistatus>');
      } else if (request.uri.path.endsWith('.ass')) {
        downloaded.add(requestPath);
        request.response.write('[Script Info]\nScriptType: v4.00+\n[Events]\n'
            'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
            'Dialogue: 0,0:00:00.00,0:00:05.00,Default,,0,0,0,,$requestPath\n');
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      PathProviderPlatform.instance = oldPaths;
      StorageService.debugAppStorageDirectoryOverride = oldStorage;
      SharedPreferences.setMockInitialValues({'webdav_connections': '[]'});
      await WebDAVService.instance.initialize();
      await directory.delete(recursive: true);
    });
    final connection = WebDAVConnection(
        id: 'dav-test',
        name: 'DAV test',
        url: 'http://127.0.0.1:${server.port}/dav',
        username: 'user',
        password: 'password');
    SharedPreferences.setMockInitialValues({
      'webdav_connections': jsonEncode([connection.toJson()]),
    });
    final delegate = _Player();
    final manager = SubtitleManager(player: Player.withDelegate(delegate));
    const video = 'webdav://dav-test/Anime/Show 01.mkv';
    manager.setCurrentVideoPath(video);
    await manager.autoDetectAndLoadSubtitle(video);
    expect(
        downloaded,
        unorderedEquals(
            ['/dav/Anime/Show 01.SC.ass', '/dav/Anime/Show 01.JP.ass']));
    final active = manager.getAllActiveExternalSubtitlePaths().single;
    expect(File(active).readAsStringSync(), contains('Show 01.'));
    expect(delegate.selected.last, active);
    final prefs = await SharedPreferences.getInstance();
    final key = prefs
        .getKeys()
        .singleWhere((key) => key.startsWith('external_subtitles_'));
    final entries = jsonDecode(prefs.getString(key)!) as List;
    final simplified = entries.singleWhere(
        (entry) => entry['name'] == 'Show 01.SC.ass')['path'] as String;
    await manager.addExternalSubtitleToStack(simplified,
        displayName: 'Show 01.SC.ass');
    expect(delegate.selected.last, simplified);
    final alternate = entries.singleWhere(
        (entry) => entry['name'] == 'Show 01.JP.ass')['path'] as String;
    await manager.addExternalSubtitleToStack(alternate,
        displayName: 'Show 01.JP.ass');
    expect(delegate.selected.last, alternate);
    expect(manager.getAllActiveExternalSubtitlePaths(), [alternate]);
    expect(File(alternate).readAsStringSync(), contains('Show 01.JP.ass'));
    expect(requests.first, 'PROPFIND /dav/Anime/');
    manager.setCurrentVideoPath('');
    manager.clearExternalSubtitle();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });
}
