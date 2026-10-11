// Opt-in, isolated real-media experiment; never connects to a running NipaPlay.
// ignore_for_file: avoid_print, use_super_parameters
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/external_player_session/mpv_session.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/next/capabilities/classic_playback_controls.dart';
import 'package:nipaplay/next/capabilities/playback_capability.dart';
import 'package:nipaplay/next/capabilities/playback_controls_capability.dart';
import 'package:nipaplay/next/capabilities/video_player_state_port.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/services/episode_file_selection_service.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';
import '../security/memory_vault.dart';

class _DirectHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

Future<dynamic> _ipc(MpvSession session, List<Object> command) async {
  final socket = await Socket.connect(
      InternetAddress(session.ipcPath!, type: InternetAddressType.unix), 0);
  try {
    socket.writeln(jsonEncode({'command': command, 'request_id': 93}));
    await socket.flush();
    await for (final line in socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 5))) {
      final result = jsonDecode(line) as Map;
      if (result['request_id'] != 93) continue;
      if (result['error'] != 'success') {
        throw StateError('mpv IPC: ${result['error']}');
      }
      return result['data'];
    }
    throw StateError('No mpv IPC reply.');
  } finally {
    socket.destroy();
  }
}

// Supplies actual mpv metadata/frames to the Classic state bridge without a UI.
class _MpvDelegate extends Fake implements AbstractPlayer {
  _MpvDelegate(this.session, this.root);
  MpvSession session;
  final Directory root;
  List<Map> nativeTracks = [];
  List<int> audio = [0];
  List<int> subtitles = [];
  Future<void> commands = Future.value();

  Future<void> readTracks() async {
    nativeTracks = (await _ipc(session, ['get_property', 'track-list']) as List)
        .cast<Map>();
  }

  @override
  PlayerMediaInfo get mediaInfo => PlayerMediaInfo(
        duration: session.duration.inMilliseconds,
        video: [
          PlayerVideoStreamInfo(
              codec: PlayerVideoCodecParams(width: 854, height: 480))
        ],
        audio: [
          for (final t in nativeTracks.where((t) => t['type'] == 'audio'))
            PlayerAudioStreamInfo(
                codec: PlayerAudioCodecParams(name: t['codec'] as String?),
                title: t['title'] as String?,
                language: t['lang'] as String?,
                rawRepresentation: 'audio')
        ],
        subtitle: [
          for (final t in nativeTracks.where((t) => t['type'] == 'sub'))
            PlayerSubtitleStreamInfo(
                title: t['title'] as String?,
                language: t['lang'] as String?,
                rawRepresentation: 'subtitle')
        ],
      );
  @override
  List<int> get activeAudioTracks => audio;
  @override
  set activeAudioTracks(List<int> value) {
    audio = value;
    final id = nativeTracks
        .where((t) => t['type'] == 'audio')
        .elementAt(value.single)['id'] as int;
    commands = commands.then((_) async {
      await _ipc(session, ['set_property', 'aid', id]);
    });
  }

  @override
  List<int> get activeSubtitleTracks => subtitles;
  @override
  set activeSubtitleTracks(List<int> value) {
    subtitles = value;
    final id = value.isEmpty
        ? 'no'
        : nativeTracks
            .where((t) => t['type'] == 'sub')
            .elementAt(value.single)['id'];
    commands = commands.then((_) async {
      await _ipc(session, ['set_property', 'sid', id as Object]);
    });
  }

  @override
  bool get supportsExternalSubtitles => false;
  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {}
  @override
  void setProperty(String key, String value) {}
  @override
  String? getProperty(String key) => null;
  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    final path = '${root.path}/mpv-frame.png';
    await _ipc(session, ['screenshot-to-file', path, 'video']);
    return PlayerFrame(
        width: 854,
        height: 480,
        bytes: Uint8List.fromList(await File(path).readAsBytes()));
  }
}

class _FramePlayer extends Player {
  _FramePlayer(_MpvDelegate delegate) : super.withDelegate(delegate);
  @override
  String getPlayerKernelName() => 'Erika';
}

class _Video extends VideoPlayerState {
  _Video(Player supplied, this.path, this.session)
      : super.forSettings(supplied) {
    subtitleManager.setCurrentVideoPath(path);
  }
  String path;
  MpvSession session;
  PlaybackSession? mediaSession;
  @override
  PlaybackSession? get currentPlaybackSession => mediaSession;
  @override
  bool get hasVideo => true;
  @override
  String? get currentVideoPath => path;
  @override
  String? get currentResolvedMediaSource => path;
  @override
  Duration get duration => session.duration;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('X13 isolated real playback, tracks, subtitle, capture and Jellyfin',
      () async {
    final oldPrint = debugPrint;
    final oldOverrides = HttpOverrides.current;
    final oldPaths = PathProviderPlatform.instance;
    final oldCredentials = CredentialStore.instance;
    CredentialStore.instance = CredentialStore(MemoryVault(), desktop: true);
    PackageInfo.setMockInitialValues(
        appName: 'NipaPlay X13',
        packageName: 'nipaplay.x13',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    // Classic launch diagnostics include authenticated URLs. Keep them out of logs.
    debugPrint = (String? message, {int? wrapWidth}) {};
    HttpOverrides.global = _DirectHttp();
    SharedPreferences.setMockInitialValues({});
    final root = await Directory('/tmp/nipa-next/x13').create(recursive: true);
    PathProviderPlatform.instance = _Paths(root.path);
    await StorageService.saveCustomStoragePath(root.path);
    final sessions = <MpvSession>[];
    _Video? video;
    try {
      final srt = File('${root.path}/external.srt');
      await srt.writeAsString(
          '1\n00:00:00,000 --> 00:00:20,000\nX13 external subtitle\n');
      final original =
          '${Platform.environment['HOME']}/Documents/nipaplay/downloads/Sintel/Sintel.mp4';
      final local = '${root.path}/first-open.mkv';
      final remux = await Process.run('/opt/homebrew/bin/ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        original,
        '-i',
        srt.path,
        '-map',
        '0:v:0',
        '-map',
        '0:a:0',
        '-map',
        '0:a:0',
        '-map',
        '1:0',
        '-c',
        'copy',
        '-t',
        '20',
        local
      ]);
      expect(remux.exitCode, 0, reason: 'Read-only source remux must succeed.');
      Future<MpvSession> launch(String path) async {
        final session = MpvSession('/opt/homebrew/bin/mpv', path, extraArgs: [
          '--vo=null',
          '--ao=null',
          '--pause',
          '--idle=yes',
          '--keep-open=yes',
          '--no-config'
        ]);
        sessions.add(session);
        await session.launch();
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (!await session.refreshPlaybackState()) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('mpv did not decode the media.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        ExternalPlayerConsoleService.setState(ConsoleState(session: session));
        return session;
      }

      final player = TestPlayer();
      var missingHistoryLookups = 0;
      late MpvSession current;
      PlaybackSession? negotiated;
      final capability = PlaybackCapability(
          player: player,
          usesExternalPlayer: () => true,
          historyItem: (_) async {
            missingHistoryLookups++;
            return null;
          },
          episodeItem: (animeId, episodeId) async => null,
          fileSelection: EpisodeFileSelectionService(),
          start: (item) async {
            var resolved = item.videoPath;
            if (resolved.startsWith('jellyfin://')) {
              final session = await JellyfinService.instance
                  .createPlaybackSession(
                      itemId: resolved.substring('jellyfin://'.length));
              negotiated = session;
              resolved = session.streamUrl;
            }
            current = await launch(resolved);
            player.hasVideo = true;
            player.path = item.videoPath;
            return true;
          });
      final harness = Harness([capability]);
      final opened =
          await invokeCompleted(harness, 'playback.open', {'path': local});
      print(
          'X13 local: history=null path=${opened['path']} decodedDurationMs=${current.duration.inMilliseconds}');
      expect(current.duration.inSeconds, greaterThanOrEqualTo(19));
      final delegate = _MpvDelegate(current, root);
      await delegate.readTracks();
      video = _Video(_FramePlayer(delegate), local, current);
      final controls =
          Harness([PlaybackControlsCapability(ClassicPlaybackControls(video))]);
      final tracks = await invokeCompleted(controls, 'playback.tracks', {});
      print('X13 tracks: ${jsonEncode(tracks)}');
      await invokeCompleted(controls, 'playback.select_track',
          {'kind': 'audio', 'origin': 'embedded', 'index': 1});
      await invokeCompleted(controls, 'playback.select_track',
          {'kind': 'subtitle', 'origin': 'embedded', 'index': 0});
      await delegate.commands;
      final aid = await _ipc(current, ['get_property', 'aid']);
      final sid = await _ipc(current, ['get_property', 'sid']);
      print('X13 actual mpv selection: aid=$aid sid=$sid');
      expect(aid, 2);
      expect(sid, 1);
      final mounted = await invokeCompleted(
          controls, 'playback.load_subtitle', {'path': srt.path});
      print(
          'X13 local subtitle: ${jsonEncode(mounted)} text=${video.subtitleManager.getCurrentExternalSubtitleTextAt(500)}');
      expect(mounted['active'], true);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.write(await srt.readAsString());
        await request.response.close();
      });
      try {
        final remote = await invokeCompleted(controls, 'playback.load_subtitle',
            {'path': 'http://127.0.0.1:${server.port}/remote.srt'});
        print('X13 remote subtitle: ${jsonEncode(remote)}');
        expect(remote['active'], true);
      } finally {
        await server.close(force: true);
      }
      await _ipc(current, ['seek', 10, 'absolute+exact']);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await current.refreshPlaybackState();
      final imagePath =
          '${root.path}/capture-${DateTime.now().millisecondsSinceEpoch}.png';
      final capture = await invokeCompleted(controls, 'playback.capture',
          {'kind': 'screenshot', 'outputPath': imagePath});
      print('X13 Classic PNG from actual mpv frame: ${jsonEncode(capture)}');
      expect(await File(imagePath).length(), greaterThan(1000));
      final gif = await invokeCompleted(controls, 'playback.capture', {
        'kind': 'gif',
        'outputPath':
            '${root.path}/capture-${DateTime.now().millisecondsSinceEpoch}.gif',
        'startMs': 10000,
        'endMs': 11000,
        'width': 320,
        'height': 180,
        'fps': 6,
      });
      print('X13 actual Erika GIF: ${jsonEncode(gif)}');
      expect(gif['frames'], greaterThan(0));
      final resume = await invokeCompleted(
          controls, 'playback.external', {'command': 'resume'});
      final paused = await invokeCompleted(
          controls, 'playback.external', {'command': 'pause'});
      final seek = await invokeCompleted(controls, 'playback.external',
          {'command': 'seek', 'positionMs': 5000});
      print(
          'X13 external: resume=${resume['paused']} pause=${paused['paused']} seek=${jsonEncode(seek)}');
      expect(resume['paused'], false);
      expect(paused['paused'], true);
      expect(seek['positionMs'], closeTo(5000, 100));
      final sharedPort = VideoPlayerStatePort(video);
      await sharedPort.seekTo(const Duration(seconds: 7));
      final sharedState = sharedPort.snapshot();
      print(
          'X13 shared playback port: player=${sharedState.player} positionMs=${sharedState.positionMs}');
      expect(sharedState.player, 'external');
      expect(sharedState.positionMs, closeTo(7000, 100));
      await invokeCompleted(
          controls, 'playback.external', {'command': 'close'});
      print(
          'X13 external closed=${!ExternalPlayerConsoleService.hasActiveSession}');

      final config = (jsonDecode(
              await File('/tmp/nipa-next/testservers.json').readAsString())
          as Map)['jellyfin'] as Map;
      final jellyfin = JellyfinService.instance
        ..serverUrl = config['base_url'] as String
        ..accessToken = config['access_token'] as String
        ..userId = config['user_id'] as String
        ..currentProfile = null
        ..isConnected = true;
      jellyfin.setTranscodePreferences(enabled: false);
      expect(
          await jellyfin.connect(config['base_url'] as String,
              config['user_name'] as String, config['password'] as String),
          true);
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      final request = await client.getUrl(Uri.parse(
          '${config['base_url']}/Users/${jellyfin.userId}/Items?Recursive=true&IncludeItemTypes=Movie,Episode&Limit=1'));
      request.headers
          .set('Authorization', 'MediaBrowser Token="${jellyfin.accessToken}"');
      final response = await request.close();
      expect(response.statusCode, 200);
      final items = (jsonDecode(await utf8.decoder.bind(response).join())
          as Map)['Items'] as List;
      client.close();
      expect(items, isNotEmpty);
      final itemId = (items.first as Map)['Id'] as String;
      final remoteOpened = await invokeCompleted(
          harness, 'playback.open', {'path': 'jellyfin://$itemId'});
      final sources = await jellyfin.getPlaybackMediaSources(itemId);
      print(
          'X13 Jellyfin: history=null path=${remoteOpened['path']} decodedDurationMs=${current.duration.inMilliseconds} versions=${sources.length}');
      expect(current.duration.inSeconds, greaterThan(0));
      expect(missingHistoryLookups, 2);
      video.path = 'jellyfin://$itemId';
      video.mediaSession = negotiated;
      final options =
          await invokeCompleted(controls, 'playback.stream_options', {});
      print(
          'X13 Jellyfin options action: versions=${(options['versions'] as List).length} qualities=${(options['qualities'] as List).length} source=${options['mediaSourceId']}');
      jellyfin.setTranscodePreferences(enabled: true);
      final qualitySession = await jellyfin.createPlaybackSession(
          itemId: itemId,
          mediaSourceId: sources.first.id,
          quality: JellyfinVideoQuality.bandwidth1m);
      print(
          'X13 Jellyfin negotiation: selectedSourceMatches=${qualitySession.mediaSourceId == sources.first.id} isTranscoding=${qualitySession.isTranscoding} protocol=${qualitySession.transcodingProtocol}');
      final embyConfig = (jsonDecode(
              await File('/tmp/nipa-next/testservers.json').readAsString())
          as Map)['emby'] as Map;
      final emby = EmbyService.instance;
      expect(
          await emby.connect(
              embyConfig['base_url'] as String,
              embyConfig['user_name'] as String,
              embyConfig['password'] as String),
          true);
      final embyClient = HttpClient()..findProxy = (_) => 'DIRECT';
      final embyRequest = await embyClient.getUrl(Uri.parse(
          '${emby.serverUrl}/emby/Users/${emby.userId}/Items?Recursive=true&IncludeItemTypes=Movie,Episode&Limit=1'));
      embyRequest.headers.set('X-Emby-Authorization',
          'MediaBrowser Client="X13", Device="X13", DeviceId="x13", Version="1", Token="${emby.accessToken}"');
      final embyResponse = await embyRequest.close();
      expect(embyResponse.statusCode, 200);
      final embyItems =
          (jsonDecode(await utf8.decoder.bind(embyResponse).join())
              as Map)['Items'] as List;
      embyClient.close();
      final embyId = (embyItems.first as Map)['Id'] as String;
      final embySources = await emby.getPlaybackMediaSources(embyId);
      emby.setTranscodePreferences(enabled: true);
      final serverSubtitles = embySources.first.mediaStreams
          .where((stream) => stream['Type'] == 'Subtitle')
          .toList();
      final subtitleIndex = serverSubtitles.isEmpty
          ? null
          : serverSubtitles.first['Index'] as int;
      final embySession = await emby.createPlaybackSession(
          itemId: embyId,
          mediaSourceId: embySources.first.id,
          quality: JellyfinVideoQuality.bandwidth1m,
          subtitleStreamIndex: subtitleIndex,
          burnInSubtitle: subtitleIndex != null);
      print(
          'X13 Emby negotiation: versions=${embySources.length} selectedSourceMatches=${embySession.mediaSourceId == embySources.first.id} isTranscoding=${embySession.isTranscoding} burnInRequested=${subtitleIndex != null} subtitleMethod=${Uri.parse(embySession.streamUrl).queryParameters['SubtitleMethod']}');
      emby.accessToken = null;
      emby.isConnected = false;
      jellyfin.accessToken = null;
      jellyfin.isConnected = false;
    } finally {
      if (ExternalPlayerConsoleService.hasActiveSession) {
        ExternalPlayerConsoleService.closePlayerAndConsole();
      }
      for (final session in sessions) {
        session.terminate();
        session.dispose();
      }
      video?.subtitleManager.dispose();
      await StorageService.clearCustomStoragePath();
      PathProviderPlatform.instance = oldPaths;
      CredentialStore.instance = oldCredentials;
      HttpOverrides.global = oldOverrides;
      debugPrint = oldPrint;
    }
  },
      skip: Platform.environment['X13_EXPERIMENT'] != '1',
      timeout: const Timeout(Duration(minutes: 3)));
}
