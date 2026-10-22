import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/utils/video_player_state.dart';

import '../../danmaku_abstraction/danmaku_kernel_factory.dart';
import 'application_settings.dart';
import 'registry.dart';

/// What is in effect for one setting while the application runs, beside the
/// value that is stored. [value] is null when it is not known ([state]
/// `unknown`) or when the stored value is not in use at all (`inactive`).
final class Effective {
  const Effective._(this.value, this.state, this.source, this.reason, this.detail);

  /// The running value equals the stored one.
  const Effective.same(Object? value, {String source = 'live', String? detail})
      : this._(value, 'same', source, null, detail);

  /// The running value is not the stored one.
  const Effective.differs(Object? value, String reason, String detail,
      {String source = 'live'})
      : this._(value, 'differs', source, reason, detail);

  /// The stored value is not in use: another setting, the kernel or the
  /// platform stops it from having an effect.
  const Effective.inactive(String reason, String detail)
      : this._(null, 'inactive', null, reason, detail);

  /// The running value cannot be read; [reason] says why.
  const Effective.unknown(String reason, String detail)
      : this._(null, 'unknown', null, reason, detail);

  final Object? value;

  /// `same`, `differs`, `inactive` or `unknown`.
  final String state;

  /// Where [value] was read: `live` (the running component), `startup` (the
  /// stored value as the registry started, which is what a restart-only
  /// setting loaded) or `storage` (no separate running value is observable;
  /// the setter that saves it is the one the running component uses).
  final String? source;
  final String? reason, detail;

  JsonMap toJson() => {
        'effective': value,
        'effectiveState': state,
        'effectiveSource': source,
        'effectiveReason': reason,
        'effectiveDetail': detail,
      };
}

/// Settings read once when the application starts. Their stored value moves on
/// while the loaded one stays until the next start.
const startupLoadedSettings = {
  'general.startupWindowState',
  'general.startupWindowPosition',
  'general.startupWindowWidth',
  'general.startupWindowHeight',
  'player.androidAudioOutput',
  'appearance.remoteAccessQrVisible',
  'appearance.animeDetailDisplayMode',
};

/// Settings read when their page or window is created.
const pageLoadedSettings = {
  'appearance.classicLibrarySection',
  'appearance.classicLibrarySectionOrder',
  'diagnostics.logViewerAutoScroll',
  'diagnostics.logViewerShowTimestamp',
};

typedef _Live = Object? Function(VideoPlayerState video);

String _argb(Object color) {
  final value = (color as dynamic).toARGB32() as int;
  return ApplicationSettings.settingColorHex(value);
}

/// Running values held by the player state, in the representation the
/// registry stores.
final Map<String, _Live> _live = {
  'player.pauseOnBackground': (v) => v.pauseOnBackground,
  'player.desktopHoverSettingsMenuEnabled': (v) => v.desktopHoverSettingsMenuEnabled,
  'player.instantHidePlayerUiEnabled': (v) => v.instantHidePlayerUiEnabled,
  'player.showMenuQuickControls': (v) => v.showPlayerMenuQuickControls,
  'player.topSendDanmakuButtonVisible': (v) => v.playerTopSendDanmakuButtonVisible,
  'player.topSkipButtonVisible': (v) => v.playerTopSkipButtonVisible,
  'player.topResizeButtonVisible': (v) => v.playerTopResizeButtonVisible,
  'player.topFrameStepButtonsVisible': (v) => v.playerTopFrameStepButtonsVisible,
  'player.chapterMarkersEnabled': (v) => v.chapterMarkersEnabled,
  'player.minimalProgressBarEnabled': (v) => v.minimalProgressBarEnabled,
  'player.useHardwareDecoder': (v) => v.useHardwareDecoder,
  'player.introSkipEnabled': (v) => v.introSkipEnabled,
  'player.timelinePreviewEnabled': (v) => v.timelinePreviewEnabled,
  'player.autoFullscreenEnabled': (v) => v.autoFullscreenEnabled,
  'player.doubleResolutionPlaybackEnabled': (v) => v.doubleResolutionPlaybackEnabled,
  'player.screenshotCropLetterbox': (v) => v.screenshotCropLetterbox,
  'player.playbackEndAction': (v) => v.playbackEndAction.name,
  'player.videoAspectMode': (v) => v.videoAspectMode.name,
  'player.screenshotSaveTarget': (v) => v.screenshotSaveTarget.name,
  'player.screenshotQuality': (v) => v.screenshotQuality.name,
  'player.screenshotFormat': (v) => v.screenshotFormat.name,
  'player.crtProfile': (v) => v.crtProfile.name,
  'player.erikaUpscalerMode': (v) => v.erikaUpscalerMode.name,
  'player.autoNextCountdownSeconds': (v) => v.autoNextCountdownSeconds,
  'player.precacheBufferSizeMb': (v) => v.precacheBufferSizeMb,
  'player.precacheBufferDurationSeconds': (v) => v.precacheBufferDurationSeconds,
  'player.volumeBoost': (v) => v.volumeBoost,
  'seek.stepSeconds': (v) => v.seekStepSeconds,
  'seek.speedBoostRate': (v) => v.speedBoostRate,
  'seek.skipSeconds': (v) => v.skipSeconds,
  'danmaku.visible': (v) => v.danmakuVisible,
  'danmaku.showDensityChart': (v) => v.showDanmakuDensityChart,
  'danmaku.randomColor': (v) => v.danmakuRandomColorEnabled,
  'danmaku.stacking': (v) => v.danmakuStacking,
  'danmaku.merge': (v) => v.mergeDanmaku,
  'danmaku.blockTop': (v) => v.blockTopDanmaku,
  'danmaku.blockBottom': (v) => v.blockBottomDanmaku,
  'danmaku.blockScroll': (v) => v.blockScrollDanmaku,
  'danmaku.rememberOffset': (v) => v.rememberDanmakuOffset,
  'danmaku.spoilerPreventionEnabled': (v) => v.spoilerPreventionEnabled,
  'danmaku.spoilerAiDebugPrintResponse': (v) => v.spoilerAiDebugPrintResponse,
  'danmaku.opacity': (v) => v.danmakuOpacity,
  'danmaku.speedMultiplier': (v) => v.danmakuSpeedMultiplier,
  'danmaku.displayArea': (v) => v.danmakuDisplayArea,
  'danmaku.trackGap': (v) => v.danmakuDfmPlusTrackGap,
  'danmaku.fontFamily': (v) => v.danmakuFontFamily,
  'danmaku.fontFilePath': (v) => v.danmakuFontFilePath,
  'subtitle.scale': (v) => v.subtitleScale,
  'subtitle.srtScale': (v) => v.srtSubtitleScale,
  'subtitle.delaySeconds': (v) => v.subtitleDelaySeconds,
  'subtitle.srtDelaySeconds': (v) => v.srtSubtitleDelaySeconds,
  'subtitle.position': (v) => v.subtitlePosition,
  'subtitle.marginX': (v) => v.subtitleMarginX,
  'subtitle.marginY': (v) => v.subtitleMarginY,
  'subtitle.opacity': (v) => v.subtitleOpacity,
  'subtitle.borderSize': (v) => v.subtitleBorderSize,
  'subtitle.shadowOffset': (v) => v.subtitleShadowOffset,
  'subtitle.alignX': (v) => v.subtitleAlignX.name,
  'subtitle.alignY': (v) => v.subtitleAlignY.name,
  'subtitle.overrideMode': (v) => v.subtitleOverrideMode.name,
  'subtitle.bold': (v) => v.subtitleBold,
  'subtitle.italic': (v) => v.subtitleItalic,
  'subtitle.color': (v) => _argb(v.subtitleColor),
  'subtitle.borderColor': (v) => _argb(v.subtitleBorderColor),
  'subtitle.shadowColor': (v) => _argb(v.subtitleShadowColor),
  'subtitle.externalColor': (v) => _argb(v.externalSubtitleColor),
  'subtitle.fontName': (v) => v.subtitleFontName,
  'subtitle.externalFontName': (v) => v.externalSubtitleFontName,
  'subtitle.fontDir': (v) => v.subtitleFontDir,
};

const _kernelNames = {
  'MDK': 'mdk',
  'Video Player': 'videoPlayer',
  'Media Kit': 'mediaKit',
  'Erika': 'erika',
};

bool _sameValue(Object? a, Object? b) {
  if (a is num && b is num) return (a.toDouble() - b.toDouble()).abs() < 1e-6;
  return jsonEncode(a) == jsonEncode(b);
}

/// Reads another setting's stored value.
typedef ReadOther = Future<Object?> Function(String key);

/// Works out [Effective] for registry entries. Everything here reads state;
/// nothing is written.
abstract final class EffectiveRules {
  static const _externalDependents = {
    'player.externalPath',
    'player.externalType',
    'player.externalDanmakuOverlay',
    'player.externalAutoSwitchToDanmakuConsole',
    'player.externalShrinkWindow',
    'player.externalConsoleWindowMode',
  };
  static const _titanCounterparts = {
    'danmaku.opacity': 'danmaku.titan.opacity',
    'danmaku.fontSize': 'danmaku.titan.fontSize',
    'danmaku.fontFamily': 'danmaku.titan.fontFamily',
  };

  static Future<Effective> resolve(SettingEntry entry, Object? stored,
      {required Map<String, Object?> startup, required ReadOther readOther}) async {
    final key = entry.key;
    final video = ApplicationSettings.video;

    // Settings another setting or the platform switches off.
    if (_externalDependents.contains(key) &&
        await readOther('player.externalEnabled') != true) {
      return const Effective.inactive('inactive_dependency',
          'player.externalEnabled is false, so the external player is not used.');
    }
    if (key == 'player.hwdecMode' && video != null && !video.useHardwareDecoder) {
      return const Effective.inactive('overridden',
          'player.useHardwareDecoder is false; the hardware decoding mode is not used.');
    }
    if (key == 'player.autoNextCountdownSeconds' &&
        await readOther('player.playbackEndAction') != 'autoNext') {
      return const Effective.inactive('inactive_dependency',
          'player.playbackEndAction is not autoNext, so no countdown runs.');
    }
    final titan = _titanCounterparts[key];
    if (titan != null &&
        (DanmakuKernelFactory.activePluginRenderer?.usesTitanSettings ?? false)) {
      return Effective.inactive('overridden',
          'The active plugin danmaku renderer reads $titan instead of $key.');
    }
    if (key == 'subtitle.scale' && video != null) {
      final kernel = video.player.getPlayerKernelName();
      if (kernel != 'Media Kit' && kernel != 'Erika') {
        return Effective.inactive('kernel_unsupported',
            'The $kernel kernel does not scale subtitles; only Media Kit and Erika do. subtitle.srtScale scales subtitles drawn over the video.');
      }
    }

    if (key == 'player.kernel') {
      if (video == null) return _noPlayer;
      final running = _kernelNames[video.player.getPlayerKernelName()];
      if (running == null) {
        return const Effective.unknown('no_runtime_probe',
            'The running player kernel has no known name.');
      }
      return _compare(entry, stored, running,
          'The current player instance runs the $running kernel; the stored kernel is used when media is next opened.');
    }
    if (key == 'playback.rate') {
      if (video == null) return _noPlayer;
      final running = video.effectivePlaybackRate;
      if (video.isSpeedBoostActive) {
        return Effective.differs(running, 'speed_boost_active',
            'Long-press speed boost is active; the player runs at $running while the stored rate is ${video.playbackRate}.');
      }
      return _compare(entry, stored, video.playbackRate, null);
    }
    if (key == 'network.httpProxy') {
      return _compare(entry, stored, AppHttpProxy.endpoint,
          'Application requests use this value now; the video player takes it when media is next opened.',
          sameDetail: true);
    }

    if (startupLoadedSettings.contains(key) && startup.containsKey(key)) {
      return _compare(entry, stored, startup[key],
          'Loaded when the application started; it is read again at the next start.',
          source: 'startup');
    }
    if (pageLoadedSettings.contains(key)) {
      return const Effective.unknown('loaded_when_page_created',
          'Read when the page or window is created; there is no single running value before then.');
    }

    final live = _live[key];
    if (live != null) {
      if (video == null) return _noPlayer;
      return _compare(entry, stored, live(video), null);
    }

    if (entry.storageKey.startsWith('@runtime:')) {
      return Effective.same(stored);
    }
    switch (entry.apply) {
      case 'reload_player':
        return const Effective.unknown('applies_at_next_open',
            'The stored value is used when media is next opened; the value used by media already open is not recorded.');
      case 'restart_app':
        return const Effective.unknown('no_runtime_probe',
            'Applied at the next application start; the loaded value is not recorded.');
      default:
        return Effective.same(stored, source: 'storage');
    }
  }

  static const _noPlayer = Effective.unknown('player_not_attached',
      'No player state is attached to the settings, so the running value cannot be read.');

  static Effective _compare(
      SettingEntry entry, Object? stored, Object? running, String? note,
      {String source = 'live', bool sameDetail = false}) {
    if (_sameValue(stored, running)) {
      return Effective.same(running,
          source: source, detail: sameDetail ? note : null);
    }
    final reason = switch (entry.apply) {
      'restart_app' => 'restart_required',
      'reload_player' => 'reload_required',
      _ => 'runtime_adjusted',
    };
    final base = switch (reason) {
      'restart_required' => 'Stored value changed after the application started.',
      'reload_required' => 'Stored value applies when media is next opened.',
      _ => 'The running value differs from the stored one; the player adjusts values to the current state.',
    };
    return Effective.differs(running, reason, note == null ? base : '$base $note',
        source: source);
  }
}
