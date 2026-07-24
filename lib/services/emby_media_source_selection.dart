import 'package:nipaplay/models/media_server_playback.dart';

typedef EmbyMediaSourceChooser = Future<PlaybackMediaSource?> Function(
  List<PlaybackMediaSource> sources,
  String? selectedSourceId,
);

typedef EmbyPlaybackSessionReloader = Future<PlaybackSession> Function(
  String mediaSourceId,
);

typedef EmbyMediaSourceChanged = Future<void> Function(
  String? previousSourceId,
  String selectedSourceId,
);

String embyItemIdFromVideoPath(String videoPath) {
  final path = videoPath.replaceFirst('emby://', '');
  return path.split('/').where((segment) => segment.isNotEmpty).lastOrNull ??
      path;
}

Future<void> clearEmbySelectionsForSourceChange({
  required String itemId,
  required void Function(String itemId) clearAudio,
  required void Function(String itemId) clearSubtitle,
}) async {
  clearAudio(itemId);
  clearSubtitle(itemId);
}

/// Selects an Emby media version, resolves its playback session, and only then
/// starts playback. A cancelled chooser never starts playback.
Future<bool> selectAndPlayEmbySource({
  required PlaybackSession initialSession,
  required EmbyMediaSourceChooser chooseSource,
  required EmbyPlaybackSessionReloader reloadSession,
  EmbyMediaSourceChanged? onSourceChanged,
  required Future<void> Function(PlaybackSession session) startPlayback,
}) async {
  var session = initialSession;
  final sources = initialSession.mediaSources;

  if (sources.length > 1) {
    final selected = await chooseSource(sources, initialSession.mediaSourceId);
    if (selected == null) return false;

    if (selected.id != initialSession.mediaSourceId) {
      session = await reloadSession(selected.id);
      await onSourceChanged?.call(
        initialSession.mediaSourceId,
        selected.id,
      );
    }
  }

  await startPlayback(session);
  return true;
}
