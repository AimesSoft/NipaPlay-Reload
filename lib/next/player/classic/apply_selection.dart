import 'package:nipaplay/utils/video_player_state.dart';

/// Puts one subtitle on screen: Next's choice is a single track. Classic lets
/// an app-rendered external subtitle (SRT/VTT) stack on top of an embedded
/// track, so applying a choice also turns off what it did not choose.
extension NextSubtitleSelection on VideoPlayerState {
  /// An embedded track is the choice: external subtitles come off. (Not through
  /// [removeExternalSubtitle], which reports back as a user's selection.)
  Future<void> applyNextEmbeddedSubtitle(int index) async {
    for (final path in activeExternalSubtitlePaths.toList()) {
      await subtitleManager.removeExternalSubtitleFromStack(path);
    }
    player.activeSubtitleTracks = [index];
  }

  /// An external subtitle is the choice: the embedded track goes off when the
  /// subtitle is drawn by the app. One drawn by the kernel replaces the
  /// kernel's own track when it loads.
  Future<void> applyNextExternalSubtitle(String path, String title) async {
    await addNextSubtitle(path, title);
    if (externalSubtitleRenderedInApp(path) &&
        player.activeSubtitleTracks.isNotEmpty) {
      player.activeSubtitleTracks = [];
    }
  }
}
