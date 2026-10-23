import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/media_server_device_id_service.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'application_settings.dart';
import 'effective_value.dart';
import 'registry.dart';
import '../player/danmaku/settings.dart';

/// The identity Jellyfin/Emby requests carry, derived as the media server
/// client does (services/media_server_service_base.dart).
Future<String> effectiveMediaServerDeviceId() async {
  var appName = 'NipaPlay';
  var platform = 'Flutter';
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.appName.isNotEmpty) appName = info.appName;
    if (!kIsWeb && !kDebugMode) {
      platform = Platform.operatingSystem;
      platform = platform[0].toUpperCase() + platform.substring(1);
    }
  } catch (_) {
    appName = 'NipaPlay';
    platform = 'Flutter';
  }
  return MediaServerDeviceIdService.instance
      .getEffectiveDeviceId(appName: appName, platform: platform);
}

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

/// Settings a saved change rebuilds the player for (see [DeferredReloads]).
const _playerRebuilt = {
  'network.httpProxy',
  'player.macosNativeVideoEnabled',
  'player.erikaAndroidOutputMode',
};

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
    final nextDanmaku = NextDanmakuSettings.active;
    if (nextDanmaku != null && NextDanmakuSettings.keys.containsKey(key)) {
      return compareEffective(entry, stored, nextDanmaku.readSetting(key),
          'Next 播放会话的弹幕设置。');
    }

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
      return compareEffective(entry, stored, running,
          'The current player instance runs the $running kernel and the media being watched is not interrupted. When media is next opened, it opens and is then reopened once on a new player on the stored kernel.');
    }
    if (_playerRebuilt.contains(key)) {
      final waiting = DeferredReloads.runningOf(key, PlayerFactory.getKernelType());
      if (waiting.waiting) {
        return Effective.differs(
            waiting.running,
            'reload_required',
            key == 'network.httpProxy'
                ? 'Application requests use the stored proxy now. The player in use was built with the previous one and the media being watched is not interrupted; when media is next opened, it opens and is then reopened once on a new player with the stored proxy.'
                : 'The player in use was built with the previous value and the media being watched is not interrupted. When media is next opened, it opens and is then reopened once on a new player with the stored value.');
      }
      if (key != 'network.httpProxy') {
        return Effective.same(stored);
      }
    }
    if (key == 'playback.rate') {
      if (video == null) return _noPlayer;
      final running = video.effectivePlaybackRate;
      if (video.isSpeedBoostActive) {
        return Effective.differs(running, 'speed_boost_active',
            'Long-press speed boost is active; the player runs at $running while the stored rate is ${video.playbackRate}.');
      }
      return compareEffective(entry, stored, video.playbackRate, null);
    }
    if (key == 'network.bangumiServerUrl') {
      return Effective.same(await NetworkSettings.getBangumiServer(),
          detail: stored == ''
              ? 'The official server is in use; requests go to this address.'
              : 'Requests go to this address.');
    }
    if (key == 'network.mediaServerDeviceId') {
      return Effective.same(await effectiveMediaServerDeviceId(),
          detail: stored == ''
              ? 'No custom ID; the generated one is sent as DeviceId.'
              : 'The custom ID is sent as DeviceId.');
    }
    if (key == 'appearance.largeScreenLayout') {
      return const Effective.unknown('held_by_main_page',
          'The main window holds the layout state, which has no reader; it loads the stored value when it is created and the in-window toggle changes both.');
    }
    if (key == 'network.httpProxy') {
      return compareEffective(entry, stored, AppHttpProxy.endpoint,
          'Application requests use this value now; the player in use already carries it.',
          sameDetail: true);
    }

    final live = _live[key];
    if (live != null) {
      if (video == null) return _noPlayer;
      return compareEffective(entry, stored, live(video), null);
    }
    return baseEffective(entry, stored, startup: startup, readOther: readOther);
  }

  static const _noPlayer = Effective.unknown('player_not_attached',
      'No player state is attached to the settings, so the running value cannot be read.');
}
