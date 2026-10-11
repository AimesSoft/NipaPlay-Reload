import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/services/emby_player_menu_selection.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/emby_media_source_selection.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/remote_subtitle_service.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path/path.dart' as p;

import 'playback_controls_capability.dart';

final class ClassicPlaybackControls implements PlaybackControlsPort {
  ClassicPlaybackControls(this.state);
  final VideoPlayerState state;

  void _requireVideo() {
    if (!state.hasVideo) {
      throw const Failure(
          FailureCode.unavailable, 'No internal video is loaded.');
    }
  }

  bool get _emby => state.currentVideoPath?.startsWith('emby://') == true;
  String get _itemId {
    final path = state.currentVideoPath;
    if (path == null ||
        !(path.startsWith('emby://') || path.startsWith('jellyfin://'))) {
      throw const Failure(
          FailureCode.unavailable, 'No Jellyfin/Emby stream is loaded.');
    }
    return path.substring(path.indexOf('://') + 3).split('/').last;
  }

  Future<List<PlaybackMediaSource>> _sources() async {
    final itemId = _itemId;
    return _emby
        ? EmbyService.instance.getPlaybackMediaSources(itemId)
        : JellyfinService.instance.getPlaybackMediaSources(itemId);
  }

  JsonMap _source(PlaybackMediaSource source) => {
        'id': source.id,
        'name': source.name,
        'container': source.container,
        'bitrate': source.bitRate,
        'size': source.size,
        'tracks': [
          for (final stream in source.mediaStreams)
            if (stream['Type'] == 'Audio' || stream['Type'] == 'Subtitle')
              {
                'kind': (stream['Type'] as String).toLowerCase(),
                'origin': 'server',
                'index': stream['Index'],
                'title': stream['Title'] ?? stream['DisplayTitle'],
                'language': stream['Language'],
                'codec': stream['Codec'],
                'external': stream['IsExternal'] == true,
                'default': stream['IsDefault'] == true,
              }
        ],
      };

  @override
  Future<JsonMap> tracks(JsonMap input) async {
    _requireVideo();
    final info = state.player.mediaInfo;
    final result = <JsonMap>[
      for (final entry in (info.audio ?? []).asMap().entries)
        {
          'kind': 'audio',
          'origin': 'embedded',
          'index': entry.key,
          'title': entry.value.title,
          'language': entry.value.language,
          'selected': state.player.activeAudioTracks.contains(entry.key),
        },
      for (final entry in (info.subtitle ?? []).asMap().entries)
        {
          'kind': 'subtitle',
          'origin': 'embedded',
          'index': entry.key,
          'title': entry.value.title,
          'language': entry.value.language,
          'selected': state.player.activeSubtitleTracks.contains(entry.key),
        },
      for (final entry in state.subtitleTrackInfo.values)
        if (entry['path'] is String)
          {
            'kind': 'subtitle',
            'origin': 'external',
            'path': entry['path'],
            'title': entry['title'] ?? entry['name'],
            'selected':
                state.activeExternalSubtitlePaths.contains(entry['path']),
          },
    ];
    if (state.currentVideoPath?.startsWith('jellyfin://') == true || _emby) {
      final sources = await _sources();
      final selectedId = state.currentPlaybackSession?.mediaSourceId;
      final hasSelectedSource =
          sources.any((source) => source.id == selectedId);
      for (final source in sources) {
        if (source.id == selectedId ||
            (!hasSelectedSource && source == sources.first)) {
          result.addAll((_source(source)['tracks'] as List).cast<JsonMap>());
        }
      }
    }
    return {'tracks': result};
  }

  @override
  Future<JsonMap> selectTrack(JsonMap input) async {
    _requireVideo();
    final kind = input['kind'] as String;
    final index = (input['index'] as num).toInt();
    if (kind == 'audio' && index < 0) {
      throw const Failure(FailureCode.invalidInput,
          'An audio track index must be nonnegative.');
    }
    if (input['origin'] == 'server') {
      return selectStream(
          {kind == 'audio' ? 'audioIndex' : 'subtitleIndex': index});
    }
    final info = state.player.mediaInfo;
    final count = kind == 'audio'
        ? (info.audio?.length ?? 0)
        : (info.subtitle?.length ?? 0);
    if (index >= count) {
      throw const Failure(
          FailureCode.notFound, 'The requested embedded track does not exist.');
    }
    if (kind == 'audio') {
      state.selectEmbeddedAudioTrack(index);
      if (_emby) {
        await state.persistCurrentEmbyManualPatch(EmbyManualSelectionPatch(
            audio: preferenceForEmbyNativeAudio(info.audio![index])));
      }
    } else {
      // SRT overlays coexist with embedded subtitles in the Classic menu.
      final external = state.getActiveExternalSubtitlePath();
      if (external != null && p.extension(external).toLowerCase() != '.srt') {
        state.setExternalSubtitle('');
      }
      state.selectEmbeddedSubtitleTrack(index);
      state.onSubtitleTrackChanged();
      if (_emby) {
        await state.persistCurrentEmbyManualPatch(EmbyManualSelectionPatch(
            subtitle: index < 0
                ? const EmbyTrackPreference.disabled()
                : preferenceForEmbyNativeSubtitle(info.subtitle![index])));
      }
    }
    return tracks({});
  }

  @override
  Future<JsonMap> loadSubtitle(JsonMap input) async {
    _requireVideo();
    var path = input['path'] as String;
    final uri = Uri.tryParse(path);
    final extension = p.extension(uri?.path ?? path).toLowerCase();
    if (!{'.srt', '.ass', '.ssa', '.vtt', '.sub', '.idx', '.sup'}
        .contains(extension)) {
      throw const Failure(
          FailureCode.invalidInput, 'Unsupported subtitle file extension.');
    }
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final name = p.posix.basename(uri.path);
      path = await RemoteSubtitleService.instance.ensureSubtitleCached(
          SharedRemoteSubtitleCandidate(
              shareId: 'agent',
              fileName: name,
              subtitleUri: uri,
              authorizationHeader: null,
              isLikelyMatch: true,
              name: name,
              extension: p.extension(name)));
    } else if (!p.isAbsolute(path) || !await File(path).exists()) {
      throw const Failure(FailureCode.notFound,
          'Use an accessible absolute subtitle path or HTTP(S) URL.');
    }
    if (input['activate'] != false) {
      await state.addExternalSubtitleToStack(path);
    }
    await state.preloadSubtitleFile(path);
    final saved =
        await SubtitleService().addExternalSubtitles(state.currentVideoPath!, [
      {
        'path': path,
        'name': p.basename(path),
        'type': p.extension(path).replaceFirst('.', ''),
        'addTime': DateTime.now().millisecondsSinceEpoch,
        'isActive': state.activeExternalSubtitlePaths.contains(path),
      }
    ]);
    if (!saved) {
      throw const Failure(FailureCode.unavailable,
          'Classic could not save the external subtitle list.');
    }
    return {
      'path': path,
      'active': state.activeExternalSubtitlePaths.contains(path)
    };
  }

  @override
  Future<JsonMap> removeSubtitle(JsonMap input) async {
    _requireVideo();
    final path = input['path'] as String;
    await state.removeExternalSubtitle(path);
    final subtitles =
        await SubtitleService().loadExternalSubtitles(state.currentVideoPath!);
    final index = subtitles.indexWhere((subtitle) => subtitle['path'] == path);
    if (index >= 0 &&
        !await SubtitleService()
            .removeExternalSubtitle(state.currentVideoPath!, index)) {
      throw const Failure(FailureCode.unavailable,
          'Classic could not update the subtitle list.');
    }
    return {
      'path': path,
      'active': state.activeExternalSubtitlePaths.contains(path)
    };
  }

  @override
  Future<JsonMap> streamOptions(JsonMap input) async {
    final itemId = _itemId;
    final sources = await _sources();
    final session = state.currentPlaybackSession;
    final selectedId =
        sources.any((source) => source.id == session?.mediaSourceId)
            ? session?.mediaSourceId
            : (sources.isEmpty ? null : sources.first.id);
    if (_emby) {
      await EmbyTranscodeProvider().initialize();
    } else {
      await JellyfinTranscodeProvider().initialize();
    }
    return {
      'server': _emby ? 'emby' : 'jellyfin',
      'itemId': itemId,
      'mediaSourceId': selectedId,
      'isTranscoding': session?.isTranscoding,
      'versions': [for (final source in sources) _source(source)],
      'qualities': [
        for (final quality in JellyfinVideoQuality.values) quality.name
      ],
      'quality': (_emby
              ? EmbyTranscodeProvider().currentVideoQuality
              : JellyfinTranscodeProvider().currentVideoQuality)
          .name,
      'transcode': _emby
          ? EmbyTranscodeProvider().transcodeEnabled
          : JellyfinTranscodeProvider().transcodeEnabled,
      'audioIndex': _emby
          ? state.getEmbyServerAudioSelection(itemId)
          : state.getJellyfinServerAudioSelection(itemId),
      'subtitleIndex': _emby
          ? state.getEmbyServerSubtitleSelection(itemId)
          : state.getJellyfinServerSubtitleSelection(itemId),
      'burnIn': _emby
          ? state.getEmbyServerSubtitleBurnIn(itemId)
          : state.getJellyfinServerSubtitleBurnIn(itemId),
    };
  }

  @override
  Future<JsonMap> selectStream(JsonMap input) async {
    _requireVideo();
    final before = await streamOptions({});
    final itemId = _itemId;
    final sources = await _sources();
    if (sources.isEmpty) {
      throw const Failure(FailureCode.unavailable,
          'The server returned no playable media versions.');
    }
    final currentId = before['mediaSourceId'] as String?;
    final sourceId = input['mediaSourceId'] as String? ??
        (sources.any((source) => source.id == currentId)
            ? currentId
            : sources.first.id);
    final matching = sources.where((source) => source.id == sourceId).toList();
    if (matching.isEmpty) {
      throw const Failure(
          FailureCode.notFound, 'The requested media version does not exist.');
    }
    final source = matching.single;
    var audio =
        (input['audioIndex'] as num?)?.toInt() ?? before['audioIndex'] as int?;
    var subtitle = (input['subtitleIndex'] as num?)?.toInt() ??
        before['subtitleIndex'] as int?;
    if (subtitle == -1) subtitle = null;
    final sourceChanged = source.id != before['mediaSourceId'];
    EmbyResolvedTrackBundle? resolved;
    if (_emby && sourceChanged) {
      final descriptor = state.embyMediaSourceDescriptor(source.id);
      if (descriptor == null) {
        throw const Failure(FailureCode.unavailable,
            'The Emby version is not in the current playback session.');
      }
      resolved = await state.resolveCurrentEmbyTracksForSource(descriptor);
      if (!input.containsKey('audioIndex')) audio = resolved.audio.sourceIndex;
      if (!input.containsKey('subtitleIndex')) {
        subtitle = resolved.subtitle.sourceIndex;
      }
    }
    if (!_emby && sourceChanged) {
      if (!input.containsKey('audioIndex')) audio = null;
      if (!input.containsKey('subtitleIndex')) subtitle = null;
    }
    for (final selection in {'Audio': audio, 'Subtitle': subtitle}.entries) {
      if (selection.value != null &&
          !source.mediaStreams.any((stream) =>
              stream['Type'] == selection.key &&
              stream['Index'] == selection.value)) {
        throw Failure(FailureCode.notFound,
            'The ${selection.key} track is not in the selected version.');
      }
    }
    if (_emby) {
      final descriptor =
          describeEmbyMediaSource(source, ordinal: sources.indexOf(source));
      final previous = resolved ?? state.currentEmbyTrackSelection;
      resolved = EmbyResolvedTrackBundle(
        audio: input.containsKey('audioIndex') && audio != null
            ? EmbyResolvedTrackSelection.track(
                sourceIndex: audio,
                fingerprint: preferenceForEmbyServerAudio(descriptor, audio)!
                    .fingerprint)
            : previous?.audio ??
                const EmbyResolvedTrackSelection.followDefault(),
        subtitle: input.containsKey('subtitleIndex')
            ? (subtitle == null
                ? const EmbyResolvedTrackSelection.disabled()
                : EmbyResolvedTrackSelection.track(
                    sourceIndex: subtitle,
                    fingerprint:
                        preferenceForEmbyServerSubtitle(descriptor, subtitle)!
                            .fingerprint))
            : previous?.subtitle ??
                const EmbyResolvedTrackSelection.followDefault(),
      );
    }
    final quality = input['transcode'] == false && !input.containsKey('quality')
        ? JellyfinVideoQuality.original
        : JellyfinVideoQuality.values
            .byName(input['quality'] as String? ?? before['quality'] as String);
    final burn = (input['burnIn'] as bool? ??
            (quality == JellyfinVideoQuality.original || subtitle == null
                ? false
                : before['burnIn'] as bool)) ||
        (quality != JellyfinVideoQuality.original &&
            resolved != null &&
            requiresEmbySubtitleBurnIn(resolved.subtitle));
    if (burn &&
        (subtitle == null || quality == JellyfinVideoQuality.original)) {
      throw const Failure(FailureCode.invalidInput,
          'Burn-in requires a server subtitle track and a transcoding quality.');
    }
    final enabled = input['transcode'] as bool? ??
        (quality != JellyfinVideoQuality.original
            ? true
            : before['transcode'] as bool);
    if (!enabled && (burn || quality != JellyfinVideoQuality.original)) {
      throw const Failure(FailureCode.invalidInput,
          'Burn-in and reduced quality require transcoding.');
    }
    final embyProvider = EmbyTranscodeProvider();
    final jellyfinProvider = JellyfinTranscodeProvider();
    final savedQuality = _emby
        ? await embyProvider.setDefaultVideoQuality(quality)
        : await jellyfinProvider.setDefaultVideoQuality(quality);
    final savedEnabled = _emby
        ? await embyProvider.setTranscodeEnabled(enabled)
        : await jellyfinProvider.setTranscodeEnabled(enabled);
    if (!savedQuality || !savedEnabled) {
      throw const Failure(FailureCode.unavailable,
          'Classic could not save transcoding preferences.');
    }
    final previousSession = state.currentPlaybackSession;
    if (_emby) {
      await state.reloadCurrentEmbyStream(
          quality: quality,
          mediaSourceId: source.id,
          audioStreamIndex: audio,
          serverSubtitleIndex: subtitle,
          burnInSubtitle: burn,
          embyTrackSelection: resolved);
    } else {
      await state.reloadCurrentJellyfinStream(
          quality: quality,
          mediaSourceId: source.id,
          audioStreamIndex: audio,
          serverSubtitleIndex: subtitle,
          burnInSubtitle: burn);
    }
    if (identical(previousSession, state.currentPlaybackSession) ||
        state.status == PlayerStatus.error) {
      throw const Failure(FailureCode.unavailable,
          'Classic could not reload the selected stream.');
    }
    if (!_emby && state.currentPlaybackSession?.isTranscoding == false) {
      await _applyJellyfinDirectTracks(source, audio, subtitle,
          disableSubtitles: input['subtitleIndex'] == -1);
    }
    if (_emby) {
      state.setEmbyServerAudioSelection(itemId, audio);
      state.setEmbyServerSubtitleSelection(itemId, subtitle, burnIn: burn);
      final descriptor = state.embyMediaSourceDescriptor();
      if (descriptor != null) {
        await state.persistCurrentEmbyManualPatch(EmbyManualSelectionPatch(
            source: sourceChanged ? descriptor : null,
            audio: input.containsKey('audioIndex') && audio != null
                ? preferenceForEmbyServerAudio(descriptor, audio)
                : null,
            subtitle: input.containsKey('subtitleIndex')
                ? (subtitle == null
                    ? const EmbyTrackPreference.disabled()
                    : preferenceForEmbyServerSubtitle(descriptor, subtitle))
                : null));
      }
    } else {
      state.setJellyfinServerAudioSelection(itemId, audio);
      state.setJellyfinServerSubtitleSelection(itemId, subtitle, burnIn: burn);
    }
    return streamOptions({});
  }

  Future<void> _applyJellyfinDirectTracks(
      PlaybackMediaSource source, int? audio, int? subtitle,
      {required bool disableSubtitles}) async {
    int nativeIndex(String kind, int serverIndex) {
      final streams = source.mediaStreams
          .where((stream) =>
              stream['Type'] == kind && stream['IsExternal'] != true)
          .toList();
      final index =
          streams.indexWhere((stream) => stream['Index'] == serverIndex);
      if (index < 0) {
        throw const Failure(FailureCode.unavailable,
            'The selected server track cannot be mapped to a native track.');
      }
      return index;
    }

    if (audio != null) {
      await selectTrack({
        'kind': 'audio',
        'origin': 'embedded',
        'index': nativeIndex('Audio', audio)
      });
    }
    if (subtitle != null || disableSubtitles) {
      final stored = await SubtitleService()
          .loadExternalSubtitles(state.currentVideoPath!);
      for (final entry in stored) {
        if (entry['remoteSource']?.toString().contains('Jellyfin') == true &&
            state.activeExternalSubtitlePaths.contains(entry['path'])) {
          await state.removeExternalSubtitle(entry['path'] as String);
        }
      }
    }
    if (disableSubtitles) {
      await selectTrack(
          {'kind': 'subtitle', 'origin': 'embedded', 'index': -1});
    } else if (subtitle != null) {
      final stream = source.mediaStreams.firstWhere((stream) =>
          stream['Type'] == 'Subtitle' && stream['Index'] == subtitle);
      if (stream['IsExternal'] == true) {
        final path = await JellyfinService.instance.downloadSubtitleFile(
            _itemId, subtitle, stream['Codec'] as String,
            mediaSourceId: source.id);
        if (path == null) {
          throw const Failure(FailureCode.unavailable,
              'Classic could not download the selected server subtitle.');
        }
        await loadSubtitle({'path': path});
        final saved = await SubtitleService()
            .addExternalSubtitles(state.currentVideoPath!, [
          {
            'path': path,
            'serverSubtitleIndex': subtitle,
            'remoteSource': 'Jellyfin'
          }
        ]);
        if (!saved) {
          throw const Failure(FailureCode.unavailable,
              'Classic could not save the selected server subtitle.');
        }
      } else {
        await selectTrack({
          'kind': 'subtitle',
          'origin': 'embedded',
          'index': nativeIndex('Subtitle', subtitle)
        });
      }
    }
  }

  @override
  Future<JsonMap> external(JsonMap input) async {
    final command = input['command'];
    if (command != 'state' && !ExternalPlayerConsoleService.hasActiveSession) {
      throw const Failure(
          FailureCode.unavailable, 'No external player session.');
    }
    var telemetry = await ExternalPlayerConsoleService.refreshPlaybackState();
    if (command == 'pause' || command == 'resume' || command == 'seek') {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (!telemetry &&
          ExternalPlayerConsoleService.supportsPlaybackTelemetry &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        telemetry = await ExternalPlayerConsoleService.refreshPlaybackState();
      }
      if (!telemetry) {
        throw const Failure(FailureCode.unavailable,
            'The external player cannot currently report/control playback.',
            retryable: true);
      }
    }
    switch (command) {
      case 'pause':
      case 'resume':
        if (!ExternalPlayerConsoleService.setPaused(command == 'pause')) {
          throw const Failure(FailureCode.unavailable,
              'This external player cannot report/control pause.');
        }
      case 'seek':
        final position = (input['positionMs'] as num?)?.toInt();
        if (position == null) {
          throw const Failure(
              FailureCode.invalidInput, 'seek requires positionMs.');
        }
        if (!ExternalPlayerConsoleService.seekToPosition(
            Duration(milliseconds: position))) {
          throw const Failure(FailureCode.unavailable,
              'This external player does not support seeking.');
        }
      case 'close':
        ExternalPlayerConsoleService.closePlayerAndConsole();
        telemetry = false;
    }
    if (command == 'seek' || command == 'pause' || command == 'resume') {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      telemetry = await ExternalPlayerConsoleService.refreshPlaybackState();
    }
    return {
      'active': ExternalPlayerConsoleService.hasActiveSession,
      'player': ExternalPlayerConsoleService.playerType?.name,
      'processId': ExternalPlayerConsoleService.processId,
      'paused': telemetry ? ExternalPlayerConsoleService.isPaused : null,
      'positionMs': telemetry
          ? ExternalPlayerConsoleService.position?.inMilliseconds
          : null,
      'telemetryAvailable': telemetry,
      'durationMs': telemetry
          ? ExternalPlayerConsoleService.duration.inMilliseconds
          : null,
      'fraction': telemetry ? ExternalPlayerConsoleService.fraction : null,
    };
  }

  @override
  Future<JsonMap> capture(JsonMap input) async {
    _requireVideo();
    final output = input['outputPath'] as String?;
    if (output != null) {
      if (!p.isAbsolute(output)) {
        throw const Failure(
            FailureCode.invalidInput, 'outputPath must be absolute.');
      }
      if (await File(output).exists()) {
        throw const Failure(
            FailureCode.conflict, 'The output file already exists.');
      }
    }
    if (input['kind'] == 'screenshot') {
      final extension =
          output == null ? '.png' : p.extension(output).toLowerCase();
      if (!{'.png', '.jpg', '.jpeg'}.contains(extension)) {
        throw const Failure(
            FailureCode.invalidInput, 'Screenshot output must be PNG or JPEG.');
      }
      final format =
          extension == '.png' ? ScreenshotFormat.png : ScreenshotFormat.jpeg;
      final path = await state.captureScreenshot(
          format: format,
          includeDanmaku: input['includeDanmaku'] as bool?,
          includeSubtitles: input['includeSubtitles'] as bool?,
          temporary: output != null);
      if (path == null) {
        throw const Failure(FailureCode.unavailable,
            'Classic could not capture the rendered video.');
      }
      if (output != null) {
        await File(path).copy(output);
        await File(path).delete();
      }
      final file = File(output ?? path);
      return {
        'path': file.path,
        'bytes': await file.length(),
        'kind': 'screenshot'
      };
    }
    final start = (input['startMs'] as num?)?.toInt();
    final end = (input['endMs'] as num?)?.toInt();
    if (output == null ||
        start == null ||
        end == null ||
        end <= start ||
        end - start > 30000 ||
        end > state.duration.inMilliseconds ||
        p.extension(output).toLowerCase() != '.gif') {
      throw const Failure(FailureCode.invalidInput,
          'GIF requires a .gif outputPath and an interval within the video, at most 30 seconds.');
    }
    final source = state.currentResolvedMediaSource;
    if (!state.player.supportsGifExport || source == null) {
      throw const Failure(FailureCode.unavailable,
          'Classic GIF export is unavailable for this player/source.');
    }
    final result = await state.player.exportGif(GifExportRequest(
        inputUri: source,
        outputPath: output,
        start: Duration(milliseconds: start),
        end: Duration(milliseconds: end),
        framesPerSecond: (input['fps'] as num?)?.toInt() ?? 12,
        outputWidth: (input['width'] as num?)?.toInt() ?? 480,
        outputHeight: (input['height'] as num?)?.toInt() ?? 270,
        quality: GifExportQuality.values
            .byName(input['quality'] as String? ?? 'normal')));
    return {
      'path': result.outputPath,
      'kind': 'gif',
      'bytes': result.fileSize,
      'width': result.width,
      'height': result.height,
      'frames': result.frameCount
    };
  }

  @override
  Future<JsonMap> close(JsonMap input) async {
    if (ExternalPlayerConsoleService.hasActiveSession) {
      return external({'command': 'close'});
    }
    await state.resetPlayer();
    return {'closed': !state.hasVideo};
  }

  @override
  Future<JsonMap> authorizeDirectory(JsonMap input) async => {
        'path': await FilePickerService().pickDirectory(
            initialDirectory: input['initialDirectory'] as String?),
      };
}
