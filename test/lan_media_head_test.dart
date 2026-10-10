import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/local_media_share_api.dart';
import 'package:nipaplay/services/local_media_share_service.dart';
import 'package:shelf/shelf.dart';

class _ShareFixture implements LocalMediaShareService {
  _ShareFixture(this.episode);
  final SharedEpisodeInfo episode;
  final seen = <(String, bool)>[];
  final delegate = LocalMediaShareService.instance;
  @override
  SharedEpisodeInfo? getEpisodeByShareId(String shareId) =>
      shareId == 'id' ? episode : null;
  @override
  Future<Response> buildStreamResponse(
      Request request, SharedEpisodeInfo episode,
      {bool headOnly = false}) {
    seen.add(('stream', headOnly));
    return delegate.buildStreamResponse(request, episode, headOnly: headOnly);
  }

  @override
  Future<Response> buildSubtitleResponse(
      Request request, SharedEpisodeInfo episode,
      {required String subtitleName, bool headOnly = false}) {
    seen.add(('subtitle', headOnly));
    return delegate.buildSubtitleResponse(request, episode,
        subtitleName: subtitleName, headOnly: headOnly);
  }

  @override
  Future<Response> buildExternalAudioResponse(
      Request request, SharedEpisodeInfo episode,
      {required String audioName, bool headOnly = false}) {
    seen.add(('audio_file', headOnly));
    return delegate.buildExternalAudioResponse(request, episode,
        audioName: audioName, headOnly: headOnly);
  }

  @override
  Future<Response> buildFontResponse(Request request, SharedEpisodeInfo episode,
      {required String fontName, bool headOnly = false}) {
    seen.add(('font', headOnly));
    return delegate.buildFontResponse(request, episode,
        fontName: fontName, headOnly: headOnly);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'C12/C13 GET, explicit HEAD and Range for media, subtitles, audio and fonts',
      () async {
    final dir = await Directory.systemTemp.createTemp('lan-head-');
    addTearDown(() => dir.delete(recursive: true));
    final video = File('${dir.path}/episode.mkv');
    await video.writeAsString('0123456789');
    for (final name in ['episode.srt', 'episode.flac', 'font.ttf']) {
      await File('${dir.path}/$name').writeAsString('0123456789');
    }
    final fixture = _ShareFixture(SharedEpisodeInfo(
        shareId: 'id',
        historyItem: WatchHistoryItem(
          filePath: video.path,
          animeName: 'Episode',
          animeId: 1,
          duration: 1000,
          lastPosition: 1,
          watchProgress: 0.1,
          lastWatchTime: DateTime(2026),
        )));
    final api = LocalMediaShareApi(service: fixture);
    for (final (route, name) in [
      ('stream', ''),
      ('subtitle', 'episode.srt'),
      ('audio_file', 'episode.flac'),
      ('font', 'font.ttf')
    ]) {
      final uri = Uri.parse('http://host/episodes/id/$route')
          .replace(queryParameters: {'name': name});
      final head = await api.router.call(Request('HEAD', uri));
      expect(fixture.seen.last, (route, true));
      expect(head.statusCode, 200);
      expect(head.headers['content-length'], '10');
      expect(await head.readAsString(), '');
      final get = await api.router.call(Request('GET', uri));
      expect(fixture.seen.last, (route, false));
      expect(get.headers['content-type'], head.headers['content-type']);
      expect(get.headers['content-disposition'],
          head.headers['content-disposition']);
      expect(await get.readAsString(), '0123456789');
    }
    for (final method in ['GET', 'HEAD']) {
      final response = await api.router.call(Request(
          method, Uri.parse('http://host/episodes/id/stream'),
          headers: {'range': 'bytes=2-5'}));
      expect(response.statusCode, 206);
      expect(response.headers['content-length'], '4');
      expect(response.headers['content-range'], 'bytes 2-5/10');
      expect(await response.readAsString(), method == 'GET' ? '2345' : '');
    }
  });
}
