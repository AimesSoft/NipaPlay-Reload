import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import './abstract_player.dart';
import './player_enums.dart';
import './player_data_models.dart';

/// MediaKit播放器适配器
class MediaKitPlayerAdapter implements AbstractPlayer {
  final Player _player;
  late final VideoController _controller;
  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  
  String _currentMedia = '';
  PlayerMediaInfo _mediaInfo = PlayerMediaInfo(duration: 0);
  PlayerPlaybackState _state = PlayerPlaybackState.stopped;
  List<int> _activeSubtitleTracks = [];
  List<int> _activeAudioTracks = [];
  
  String? _lastKnownActiveSubtitleId; 
  StreamSubscription<Track>? _trackSubscription; 
  bool _isDisposed = false;
  bool _currentMediaHasNoInitiallyEmbeddedSubtitles = false;
  String _mediaPathForSubtitleStatusCheck = "";

  final Map<PlayerMediaType, List<String>> _decoders = {
    PlayerMediaType.video: [],
    PlayerMediaType.audio: [],
    PlayerMediaType.subtitle: [],
    PlayerMediaType.unknown: [],
  };
  final Map<String, String> _properties = {};
  
  MediaKitPlayerAdapter() : _player = Player(
    configuration: PlayerConfiguration(
      libass: true,
      bufferSize: 32 * 1024 * 1024,
      logLevel: MPVLogLevel.debug,
    )
  ) {
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    _initializeHardwareDecoding();
    _initializeCodecs();
    _setupSubtitleFonts();
    _controller.waitUntilFirstFrameRendered.then((_) {
      _updateTextureIdFromController();
    });
    _addEventListeners();
    _setupDefaultTrackSelectionBehavior();
  }
  
  void _initializeHardwareDecoding() {
    try {
      (_player.platform as dynamic)?.setProperty('hwdec', 'auto-copy');
      debugPrint('MediaKit: 设置硬件解码模式为 auto-copy');
    } catch (e) {
      debugPrint('MediaKit: 设置硬件解码模式失败: $e');
    }
  }
  
  void _initializeCodecs() {
    try {
      final videoDecoders = ['auto'];
      setDecoders(PlayerMediaType.video, videoDecoders);
      debugPrint('MediaKit: 设置默认解码器配置完成');
    } catch (e) {
      debugPrint('设置解码器失败: $e');
    }
  }
  
  void _setupSubtitleFonts() {
    try {
      final dynamic platform = _player.platform;
      if (platform != null) {
        try {
          platform.setProperty?.call("embeddedfonts", "yes");
          platform.setProperty?.call("sub-ass-force-style", "");
          platform.setProperty?.call("sub-ass-override", "no");
          platform.setProperty?.call("sub-font", "subfont");
          platform.setProperty?.call("sub-fonts-dir", "assets");
          platform.setProperty?.call("sub-fallback-fonts", "Source Han Sans SC,思源黑体,微软雅黑,Microsoft YaHei,Noto Sans CJK SC,华文黑体,STHeiti");
          platform.setProperty?.call("sub-codepage", "auto");
          platform.setProperty?.call("sub-auto", "fuzzy");
          platform.setProperty?.call("sub-ass-vsfilter-aspect-compat", "yes");
          platform.setProperty?.call("sub-ass-vsfilter-blur-compat", "yes");
          debugPrint('MediaKit: 设置内嵌字体和字幕选项完成');
        } catch (e) {
          debugPrint('MediaKit: 调用setProperty方法失败: $e');
        }
      } else {
        debugPrint('MediaKit: 无法设置字体回退和字幕选项，platform实例为null');
      }
    } catch (e) {
      debugPrint('设置字体回退和字幕选项失败: $e');
    }
  }
  
  void _updateTextureIdFromController() {
    try {
      _textureIdNotifier.value = _controller.id.value;
      debugPrint('MediaKit: 成功获取纹理ID从VideoController: ${_controller.id.value}');
      if (_textureIdNotifier.value == null) {
        _controller.id.addListener(() {
          if (_controller.id.value != null && _textureIdNotifier.value == null) {
            _textureIdNotifier.value = _controller.id.value;
            debugPrint('MediaKit: 纹理ID已更新: ${_controller.id.value}');
          }
        });
      }
    } catch (e) {
      debugPrint('获取纹理ID失败: $e');
    }
  }
  
  void _addEventListeners() {
    _player.stream.playing.listen((playing) {
      _state = playing 
          ? PlayerPlaybackState.playing 
          : (_player.state.position.inMilliseconds > 0 
              ? PlayerPlaybackState.paused 
              : PlayerPlaybackState.stopped);
    });
    
    _player.stream.tracks.listen(_updateMediaInfo);
    
    _trackSubscription = _player.stream.track.listen((trackEvent) {
      // debugPrint('MediaKitAdapter: Active track changed event received. Subtitle ID from event: ${trackEvent.subtitle.id}, Title: ${trackEvent.subtitle.title}');
      // The listener callback itself is not async, so we don't await _handleActiveSubtitleTrackDataChange here.
      // _handleActiveSubtitleTrackDataChange will run its async operations independently.
      _handleActiveSubtitleTrackDataChange(trackEvent.subtitle);
    }, onError: (error) {
      debugPrint('MediaKitAdapter: Error in player.stream.track: $error');
    }, onDone: () {
      debugPrint('MediaKitAdapter: player.stream.track was closed.');
    });

    _player.stream.error.listen((error) {
      debugPrint('MediaKit错误: $error');
    });
    
    _player.stream.duration.listen((duration) {
      if (duration.inMilliseconds > 0 && _mediaInfo.duration != duration.inMilliseconds) {
        _mediaInfo = _mediaInfo.copyWith(duration: duration.inMilliseconds);
      }
    });
    
    _player.stream.log.listen((log) {
      //debugPrint('MediaKit日志: [${log.prefix}] ${log.text}');
    });
  }
  
  void _printAllTracksInfo(Tracks tracks) {
    StringBuffer sb = StringBuffer();
    sb.writeln('============ MediaKit所有轨道信息 ============');
    final realVideoTracks = _filterRealTracks<VideoTrack>(tracks.video);
    final realAudioTracks = _filterRealTracks<AudioTrack>(tracks.audio);
    final realSubtitleTracks = _filterRealTracks<SubtitleTrack>(tracks.subtitle);
    sb.writeln('视频轨道数: ${tracks.video.length}, 音频轨道数: ${tracks.audio.length}, 字幕轨道数: ${tracks.subtitle.length}');
    sb.writeln('真实视频轨道数: ${realVideoTracks.length}, 真实音频轨道数: ${realAudioTracks.length}, 真实字幕轨道数: ${realSubtitleTracks.length}');
    for (int i = 0; i < tracks.video.length; i++) {
      final track = tracks.video[i];
      sb.writeln('V[$i] ID:${track.id} 标题:${track.title ?? 'N/A'} 语言:${track.language ?? 'N/A'} 编码:${track.codec ?? 'N/A'}');
    }
    for (int i = 0; i < tracks.audio.length; i++) {
      final track = tracks.audio[i];
      sb.writeln('A[$i] ID:${track.id} 标题:${track.title ?? 'N/A'} 语言:${track.language ?? 'N/A'} 编码:${track.codec ?? 'N/A'}');
    }
    for (int i = 0; i < tracks.subtitle.length; i++) {
      final track = tracks.subtitle[i];
      sb.writeln('S[$i] ID:${track.id} 标题:${track.title ?? 'N/A'} 语言:${track.language ?? 'N/A'}');
    }
    sb.writeln('原始API: V=${_player.state.tracks.video.length} A=${_player.state.tracks.audio.length} S=${_player.state.tracks.subtitle.length}');
    sb.writeln('============================================');
    debugPrint(sb.toString());
  }
  
  List<T> _filterRealTracks<T>(List<T> tracks) { 
    return tracks.where((track) {
      final String id = (track as dynamic).id as String;
      if (id == 'auto' || id == 'no') {
        return false;
      }
        final intId = int.tryParse(id);
      return intId != null && intId >= 0; 
    }).toList();
  }
  
  int _mapRealIndexToOriginal<T>(List<T> originalTracks, List<T> realTracks, int realIndex) {
    if (realIndex < 0 || realIndex >= realTracks.length) {
      return -1;
    }
    final String realTrackId = (realTracks[realIndex] as dynamic).id as String;
    for (int i = 0; i < originalTracks.length; i++) {
      if (((originalTracks[i] as dynamic).id as String) == realTrackId) { 
        return i;
      }
    }
    return -1;
  }
  
  void _updateMediaInfo(Tracks tracks) {
    debugPrint('MediaKitAdapter: _updateMediaInfo CALLED. Received tracks: Video=${tracks.video.length}, Audio=${tracks.audio.length}, Subtitle=${tracks.subtitle.length}');
    _printAllTracksInfo(tracks);
    
    final realVideoTracks = _filterRealTracks<VideoTrack>(tracks.video);
    final realAudioTracks = _filterRealTracks<AudioTrack>(tracks.audio);
    final realIncomingSubtitleTracks = _filterRealTracks<SubtitleTrack>(tracks.subtitle); 

    // Initial assessment for embedded subtitles when a new main media's tracks are first processed.
    if (_mediaPathForSubtitleStatusCheck == _currentMedia && _currentMedia.isNotEmpty) {
      if (realIncomingSubtitleTracks.isEmpty) {
        _currentMediaHasNoInitiallyEmbeddedSubtitles = true;
        debugPrint('MediaKitAdapter: _updateMediaInfo - Initial track assessment for $_currentMedia: NO initially embedded subtitles found.');
      } else {
        // Check if all "real" incoming tracks are just 'auto' or 'no' which can happen
        // if the file has tracks but they are not yet fully parsed/identified by media_kit.
        // In this specific initial check, we are more interested if there's any track that is NOT 'auto'/'no'.
        // The _filterRealTracks already filters these out, so if realIncomingSubtitleTracks is not empty,
        // it means there's at least one track that media_kit considers a potential real subtitle track.
        _currentMediaHasNoInitiallyEmbeddedSubtitles = false;
        debugPrint('MediaKitAdapter: _updateMediaInfo - Initial track assessment for $_currentMedia: Potential initially embedded subtitles PRESENT (count: ${realIncomingSubtitleTracks.length}).');
      }
      _mediaPathForSubtitleStatusCheck = ""; // Consumed the check for this media load.
    }

    List<PlayerVideoStreamInfo>? videoStreams;
    if (realVideoTracks.isNotEmpty) {
      videoStreams = realVideoTracks.map((track) =>
        PlayerVideoStreamInfo(
          codec: PlayerVideoCodecParams(
            width: 0,
            height: 0,
            name: track.title ?? track.language ?? 'Unknown Video',
          ),
          codecName: track.codec ?? 'Unknown',
        )
      ).toList();
    }
    
    List<PlayerAudioStreamInfo>? audioStreams;
    if (realAudioTracks.isNotEmpty) {
      audioStreams = [];
      for (int i = 0; i < realAudioTracks.length; i++) {
        final track = realAudioTracks[i];
        final title = track.title ?? track.language ?? 'Audio Track ${i + 1}';
        final language = track.language ?? '';
        audioStreams.add(
          PlayerAudioStreamInfo(
            codec: PlayerAudioCodecParams(
              name: title,
              channels: 0,
              sampleRate: 0,
              bitRate: null,
            ),
            title: title,
            language: language,
            metadata: {
              'id': track.id.toString(),
              'title': title,
              'language': language,
              'index': i.toString(),
            },
            rawRepresentation: 'Audio: $title (ID: ${track.id})',
          )
        );
      }
    }
    
    List<PlayerSubtitleStreamInfo>? resolvedSubtitleStreams;
    if (realIncomingSubtitleTracks.isNotEmpty) {
      if (_currentMediaHasNoInitiallyEmbeddedSubtitles && 
          realIncomingSubtitleTracks.every((track) {
            final String id = (track as dynamic).id as String;
            // Heuristic: external subtitles added by media_kit often get numeric IDs like "1", "2", etc.
            // and might all have a similar title like "external" or the filename.
            // We are trying to catch situations where media_kit adds multiple entries for the *same* external file.
            return int.tryParse(id) != null; // Check if ID is purely numeric
          })) {
        // Current media has no initially embedded subtitles, AND all incoming "real" subtitle tracks have numeric IDs.
        // This suggests they might be multiple representations of the same loaded external subtitle.
        // Consolidate to the one with the smallest numeric ID.
        SubtitleTrack trackToKeep = realIncomingSubtitleTracks.reduce((a, b) {
            int idA = int.parse((a as dynamic).id as String); // Safe due to .every() check
            int idB = int.parse((b as dynamic).id as String); // Safe due to .every() check
            return idA < idB ? a : b;
        });
        
        final title = trackToKeep.title ?? (trackToKeep.language != null && trackToKeep.language!.isNotEmpty ? trackToKeep.language! : 'Subtitle Track 1');
        final language = trackToKeep.language ?? '';
        final trackIdStr = (trackToKeep as dynamic).id as String;

        resolvedSubtitleStreams = [
          PlayerSubtitleStreamInfo(
            title: title,
            language: language,
            metadata: {
              'id': trackIdStr,
              'title': title,
              'language': language,
              'index': '0', // Since we are consolidating to one
            },
            rawRepresentation: 'Subtitle: $title (ID: $trackIdStr)',
          )
        ];
        debugPrint('MediaKitAdapter: _updateMediaInfo - Current media determined to have NO embedded subs. Consolidating ${realIncomingSubtitleTracks.length} incoming external-like tracks (numeric IDs) to 1 (Kept ID: $trackIdStr).');
      } else {
        // Media either has initially embedded subtitles, or incoming tracks don't all fit the "duplicate external" heuristic.
        // Process all incoming real subtitle tracks.
        resolvedSubtitleStreams = [];
        for (int i = 0; i < realIncomingSubtitleTracks.length; i++) {
          final track = realIncomingSubtitleTracks[i]; // This is media_kit's SubtitleTrack
          final trackIdStr = (track as dynamic).id as String;

          // Normalize here BEFORE creating PlayerSubtitleStreamInfo
          final normInfo = _normalizeSubtitleTrackInfoHelper(track.title, track.language, i);
          
          resolvedSubtitleStreams.add(
            PlayerSubtitleStreamInfo(
              title: normInfo.title,       // Use normalized title
              language: normInfo.language, // Use normalized language
              metadata: {
                'id': trackIdStr,
                'title': normInfo.title, // Store normalized title in metadata too
                'language': normInfo.language, // Store normalized language
                'original_mk_title': track.title ?? '',    // Keep original for reference
                'original_mk_language': track.language ?? '', // Keep original for reference
              'index': i.toString(),
            },
              rawRepresentation: 'Subtitle: ${normInfo.title} (ID: $trackIdStr) Language: ${normInfo.language}',
            )
          );
        }
        debugPrint('MediaKitAdapter: _updateMediaInfo - Populating subtitles from ${realIncomingSubtitleTracks.length} incoming tracks (media may have embedded subs or tracks are diverse). Resulting count: ${resolvedSubtitleStreams.length}');
      }
    } else { // realIncomingSubtitleTracks is empty
      // If incoming tracks are empty (e.g. subtitles turned off)
      if (!_currentMediaHasNoInitiallyEmbeddedSubtitles && _mediaInfo.subtitle != null && _mediaInfo.subtitle!.isNotEmpty) {
        // Preserve the existing list if the media was known to have embedded subtitles.
        resolvedSubtitleStreams = _mediaInfo.subtitle;
        debugPrint('MediaKitAdapter: _updateMediaInfo - Incoming event has NO subtitles, but media was determined to HAVE embedded subs and _mediaInfo already had ${resolvedSubtitleStreams?.length ?? 0}. PRESERVING existing subtitle list.');
      } else {
        // Media has no embedded subtitles, or _mediaInfo was already empty.
        resolvedSubtitleStreams = null; 
        debugPrint('MediaKitAdapter: _updateMediaInfo - Incoming event has NO subtitles. (Media determined to have NO embedded subs, or _mediaInfo was also empty). Setting subtitles to null/empty.');
      }
    }

    final currentDuration = _mediaInfo.duration > 0 
        ? _mediaInfo.duration 
        : _player.state.duration.inMilliseconds;
    
    _mediaInfo = PlayerMediaInfo(
      duration: currentDuration,
      video: videoStreams,
      audio: audioStreams,
      subtitle: resolvedSubtitleStreams, // Use the resolved list
    );
    
    _ensureDefaultTracksSelected();
    
    // If _mediaInfo was just updated (potentially preserving subtitle list),
    // it's crucial to re-sync the active subtitle track based on the *current* player state.
    // _handleActiveSubtitleTrackDataChange is better for reacting to live changes,
    // but after _mediaInfo is rebuilt, a direct sync is good.
    final currentActualPlayerSubtitleId = _player.state.track.subtitle.id;
    debugPrint('MediaKitAdapter: _updateMediaInfo - Triggering sync with current actual player subtitle ID: $currentActualPlayerSubtitleId');
    _performSubtitleSyncLogic(currentActualPlayerSubtitleId);
  }

  // Made async to handle potential future from getProperty
  Future<void> _handleActiveSubtitleTrackDataChange(SubtitleTrack subtitleData) async { 
    String? idToProcess = subtitleData.id;
    final originalEventId = subtitleData.id; // Keep original event id for logging
    debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Received event with subtitle ID: "$originalEventId"');

    if (idToProcess == 'auto') {
      try {
        final dynamic platform = _player.platform;
        // Check if platform and getProperty method exist to avoid runtime errors
        if (platform != null && platform.getProperty != null) { 
          // Correctly call getProperty with the string literal 'sid'
          var rawSidProperty = platform.getProperty('sid'); 
          
          dynamic resolvedSidValue;
          if (rawSidProperty is Future) {
            debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - platform.getProperty(\'sid\') returned a Future. Awaiting...');
            resolvedSidValue = await rawSidProperty;
          } else {
            debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - platform.getProperty(\'sid\') returned a direct value.');
            resolvedSidValue = rawSidProperty;
          }

          String? actualMpvSidString;
          if (resolvedSidValue != null) {
            actualMpvSidString = resolvedSidValue.toString(); // Convert to string, as SID can be int or string 'no'/'auto'
          }
          
          debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Event ID is "auto". Queried platform for actual "sid", got: "$actualMpvSidString" (raw value from getProperty: $resolvedSidValue)');
          
          if (actualMpvSidString != null && actualMpvSidString.isNotEmpty && actualMpvSidString != 'auto' && actualMpvSidString != 'no') {
            // We got a valid, specific track ID from mpv
            idToProcess = actualMpvSidString;
            debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Using mpv-queried SID: "$idToProcess" instead of event ID "auto"');
          } else {
            // Query didn't yield a specific track, or it was still 'auto'/'no'/null. Stick with the event's ID.
            debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Queried SID is "$actualMpvSidString". Sticking with event ID "$originalEventId".');
          }
        } else {
           debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Player platform or getProperty method is null. Cannot query actual "sid". Processing event ID "$originalEventId" as is.');
        }
      } catch (e, s) {
        debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Error querying "sid" from platform: $e\nStack trace:\n$s. Processing event ID "$originalEventId" as is.');
      }
    }

    if (_lastKnownActiveSubtitleId != idToProcess) {
      _lastKnownActiveSubtitleId = idToProcess; // Update last known with the ID we decided to process
      _performSubtitleSyncLogic(idToProcess);
    } else {
      debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Process ID ("$idToProcess") is the same as last known ("$_lastKnownActiveSubtitleId"). No sync triggered.');
    }
  }

  void _performSubtitleSyncLogic(String? activeMpvSid) {
    debugPrint('MediaKitAdapter: _performSubtitleSyncLogic CALLED. Using MPV SID: "${activeMpvSid ?? "null"}"');
    try {
      // It's crucial to call _ensureDefaultTracksSelected *before* we potentially clear _activeSubtitleTracks
      // if activeMpvSid is null/no/auto, especially if _activeSubtitleTracks is currently empty.
      // This gives our logic a chance to pick a default if MPV hasn't picked one yet.
      // However, _ensureDefaultTracksSelected itself might call _player.setSubtitleTrack, which would trigger
      // _handleActiveSubtitleTrackDataChange and then _performSubtitleSyncLogic again. To avoid re-entrancy or loops,
      // _ensureDefaultTracksSelected should ideally only set a track if no track is effectively selected by MPV.
      // The check `if (_player.state.track.subtitle.id == 'auto' || _player.state.track.subtitle.id == 'no')`
      // inside _ensureDefaultTracksSelected helps with this.

      final List<PlayerSubtitleStreamInfo>? realSubtitleTracksInMediaInfo = _mediaInfo.subtitle;
      debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - Current _mediaInfo.subtitle track count: ${realSubtitleTracksInMediaInfo?.length ?? 0}');

      List<int> newActiveTrackIndices = []; 

      if (activeMpvSid != null && activeMpvSid != 'no' && activeMpvSid != 'auto' && activeMpvSid.isNotEmpty) {
        if (realSubtitleTracksInMediaInfo != null && realSubtitleTracksInMediaInfo.isNotEmpty) {
          int foundRealIndex = -1;
          for (int i = 0; i < realSubtitleTracksInMediaInfo.length; i++) {
            final mediaInfoTrackMpvId = realSubtitleTracksInMediaInfo[i].metadata['id'];
            debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - Comparing MPV SID "$activeMpvSid" with mediaInfo track MPV ID "$mediaInfoTrackMpvId" at _mediaInfo.subtitle index $i');
            if (mediaInfoTrackMpvId == activeMpvSid) {
              foundRealIndex = i; 
              debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - Match found! Index in _mediaInfo.subtitle: $foundRealIndex');
              break;
            }
          }
          if (foundRealIndex != -1) {
            newActiveTrackIndices = [foundRealIndex];
          } else {
            debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - No match found for MPV SID "$activeMpvSid" in _mediaInfo.subtitle.');
          }
        } else {
          debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - No real subtitle tracks in _mediaInfo to match MPV SID "$activeMpvSid".');
        }
      } else {
        debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - MPV SID is "${activeMpvSid ?? "null"}" (null, no, auto, or empty). Clearing active tracks.');
      }

      bool hasChanged = false;
      if (newActiveTrackIndices.length != _activeSubtitleTracks.length) {
        hasChanged = true;
      } else {
        for (int i = 0; i < newActiveTrackIndices.length; i++) {
          if (newActiveTrackIndices[i] != _activeSubtitleTracks[i]) {
            hasChanged = true;
            break;
          }
        }
      }

      debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - Calculated newActiveTrackIndices: $newActiveTrackIndices, Current _activeSubtitleTracks: $_activeSubtitleTracks, HasChanged: $hasChanged');

      if (hasChanged) {
        _activeSubtitleTracks = List<int>.from(newActiveTrackIndices); 
        debugPrint('MediaKitAdapter: _activeSubtitleTracks UPDATED (by _performSubtitleSyncLogic). New state: $_activeSubtitleTracks, Based on MPV SID: $activeMpvSid');
      } else {
        debugPrint('MediaKitAdapter: _activeSubtitleTracks UNCHANGED (by _performSubtitleSyncLogic). Current state: $_activeSubtitleTracks, Based on MPV SID: $activeMpvSid');
      }

    } catch (e, s) {
      debugPrint('MediaKitAdapter: Error in _performSubtitleSyncLogic: $e\nStack trace:\n$s');
      if (_activeSubtitleTracks.isNotEmpty) {
        _activeSubtitleTracks = []; 
        debugPrint('MediaKitAdapter: _activeSubtitleTracks cleared due to error in _performSubtitleSyncLogic.');
      }
    }
  }
  
  // Helper inside MediaKitPlayerAdapter to check for Chinese subtitle
  bool _isChineseSubtitle(PlayerSubtitleStreamInfo subInfo) {
    final title = (subInfo.title ?? '').toLowerCase();
    final lang = (subInfo.language ?? '').toLowerCase();
    // Also check metadata which might have more accurate original values from media_kit tracks
    final metadataTitle = (subInfo.metadata['title'] as String? ?? '').toLowerCase();
    final metadataLang = (subInfo.metadata['language'] as String? ?? '').toLowerCase();

    final patterns = [
      'chi', 'chs', 'zh', '中文', '简体', '繁体', 'simplified', 'traditional', 
      'zho', 'zh-hans', 'zh-cn', 'zh-sg', 'sc', 'zh-hant', 'zh-tw', 'zh-hk', 'tc'
    ];

    for (var p in patterns) {
      if (title.contains(p) || lang.contains(p) || metadataTitle.contains(p) || metadataLang.contains(p)) {
        return true;
      }
    }
    return false;
  }

  void _ensureDefaultTracksSelected() {
    // Audio track selection (existing logic)
    try {
      if (_mediaInfo.audio != null && 
          _mediaInfo.audio!.isNotEmpty && 
          _activeAudioTracks.isEmpty) {
        _activeAudioTracks = [0];
        
        final realAudioTracksInMediaInfo = _mediaInfo.audio!;
        if (realAudioTracksInMediaInfo.isNotEmpty) {
            final firstRealAudioTrackMpvId = realAudioTracksInMediaInfo[0].metadata['id'];
            AudioTrack? actualAudioTrackToSet;
            for(final atd in _player.state.tracks.audio) {
                if (atd.id == firstRealAudioTrackMpvId) {
                    actualAudioTrackToSet = atd;
                    break;
                }
            }
            if (actualAudioTrackToSet != null) {
                 debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - 自动选择第一个有效音频轨道: _mediaInfo index=0, ID=${actualAudioTrackToSet.id}');
                _player.setAudioTrack(actualAudioTrackToSet);
            } else {
                debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - 自动选择音频轨道失败: 未在player.state.tracks.audio中找到ID为 $firstRealAudioTrackMpvId 的轨道');
            }
        }
      }
    } catch (e) {
      debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - 自动选择第一个有效音频轨道失败: $e');
    }

    // Subtitle track selection logic
    // Only attempt to set a default if MPV hasn't already picked a specific track.
    if (_player.state.track.subtitle.id == 'auto' || _player.state.track.subtitle.id == 'no') {
      if (_mediaInfo.subtitle != null && _mediaInfo.subtitle!.isNotEmpty && _activeSubtitleTracks.isEmpty) {
          debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Attempting to select a default subtitle track as current selection is "${_player.state.track.subtitle.id}" and _activeSubtitleTracks is empty.');
          int preferredSubtitleIndex = -1;
          int firstSimplifiedChineseIndex = -1;
          int firstTraditionalChineseIndex = -1;
          int firstGenericChineseIndex = -1;

          for (int i = 0; i < _mediaInfo.subtitle!.length; i++) {
              final subInfo = _mediaInfo.subtitle![i];
              // Use original title and language from metadata for more reliable matching against keywords
              final titleLower = (subInfo.metadata['title'] as String? ?? subInfo.title ?? '').toLowerCase();
              final langLower = (subInfo.metadata['language'] as String? ?? subInfo.language ?? '').toLowerCase();

              bool isSimplified = titleLower.contains('simplified') || titleLower.contains('简体') ||
                                  langLower.contains('zh-hans') || langLower.contains('zh-cn') || langLower.contains('sc');
              
              bool isTraditional = titleLower.contains('traditional') || titleLower.contains('繁体') ||
                                   langLower.contains('zh-hant') || langLower.contains('zh-tw') || langLower.contains('tc');

              if (isSimplified && firstSimplifiedChineseIndex == -1) {
                  firstSimplifiedChineseIndex = i;
              }
              if (isTraditional && firstTraditionalChineseIndex == -1) {
                  firstTraditionalChineseIndex = i;
              }
              // Use the _isChineseSubtitle helper which checks more broadly
              if (_isChineseSubtitle(subInfo) && firstGenericChineseIndex == -1) { 
                  firstGenericChineseIndex = i;
              }
          }

          if (firstSimplifiedChineseIndex != -1) {
              preferredSubtitleIndex = firstSimplifiedChineseIndex;
              debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Found Preferred: Simplified Chinese subtitle at _mediaInfo index: $preferredSubtitleIndex');
          } else if (firstTraditionalChineseIndex != -1) {
              preferredSubtitleIndex = firstTraditionalChineseIndex;
              debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Found Preferred: Traditional Chinese subtitle at _mediaInfo index: $preferredSubtitleIndex');
          } else if (firstGenericChineseIndex != -1) {
              preferredSubtitleIndex = firstGenericChineseIndex;
              debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Found Preferred: Generic Chinese subtitle at _mediaInfo index: $preferredSubtitleIndex');
          }

          if (preferredSubtitleIndex != -1) {
              final selectedMediaInfoTrack = _mediaInfo.subtitle![preferredSubtitleIndex];
              final mpvTrackIdToSelect = selectedMediaInfoTrack.metadata['id'];
              SubtitleTrack? actualSubtitleTrackToSet;
              // Iterate through the player's current actual subtitle tracks to find the matching SubtitleTrack object
              for (final stData in _player.state.tracks.subtitle) { 
                  if (stData.id == mpvTrackIdToSelect) {
                      actualSubtitleTrackToSet = stData;
                      break;
                  }
              }

              if (actualSubtitleTrackToSet != null) {
                  debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Automatically selecting subtitle: _mediaInfo index=$preferredSubtitleIndex, MPV ID=${actualSubtitleTrackToSet.id}, Title=${actualSubtitleTrackToSet.title}');
                  _player.setSubtitleTrack(actualSubtitleTrackToSet);
                  // Note: _activeSubtitleTracks will be updated by the event stream (_handleActiveSubtitleTrackDataChange -> _performSubtitleSyncLogic)
              } else {
                  debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Could not find SubtitleTrackData in player.state.tracks.subtitle for MPV ID "$mpvTrackIdToSelect" (from _mediaInfo index $preferredSubtitleIndex). Cannot auto-select default subtitle.');
              }
          } else {
            debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - No preferred Chinese subtitle track found in _mediaInfo.subtitle. No default selected by this logic.');
          }
      } else {
         debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Conditions not met for default subtitle selection. _mediaInfo.subtitle empty/null: ${_mediaInfo.subtitle == null || _mediaInfo.subtitle!.isEmpty}, _activeSubtitleTracks not empty: ${_activeSubtitleTracks.isNotEmpty}');
      }
    } else {
        debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Player already has a specific subtitle track selected (ID: ${_player.state.track.subtitle.id}). Skipping default selection logic.');
    }
  }
  
  @override
  double get volume => _player.state.volume / 100.0;
  
  @override
  set volume(double value) {
    _player.setVolume(value.clamp(0.0, 1.0) * 100);
  }
  
  @override
  PlayerPlaybackState get state => _state;
  
  @override
  set state(PlayerPlaybackState value) {
    switch (value) {
      case PlayerPlaybackState.stopped:
        _player.stop();
        break;
      case PlayerPlaybackState.paused:
        _player.pause();
        break;
      case PlayerPlaybackState.playing:
        _player.play();
        break;
    }
    _state = value;
  }
  
  @override
  ValueListenable<int?> get textureId => _textureIdNotifier;
  
  @override
  String get media => _currentMedia;
  
  @override
  set media(String value) {
    setMedia(value, PlayerMediaType.video);
  }
  
  @override
  PlayerMediaInfo get mediaInfo => _mediaInfo;
  
  @override
  List<int> get activeSubtitleTracks => _activeSubtitleTracks;
  
  @override
  set activeSubtitleTracks(List<int> value) {
    try {
      debugPrint('MediaKitAdapter: UI wants to set activeSubtitleTracks (indices in _mediaInfo.subtitle) to: $value');
      final List<PlayerSubtitleStreamInfo>? mediaInfoSubtitles = _mediaInfo.subtitle;

      // Log the current state of _player.state.tracks.subtitle for diagnostics
      if (_player.state.tracks.subtitle.isNotEmpty) {
          debugPrint('MediaKitAdapter: activeSubtitleTracks setter - _player.state.tracks.subtitle (raw from player):');
          for (var track in _player.state.tracks.subtitle) {
              debugPrint('  - ID: ${track.id}, Title: ${track.title ?? 'N/A'}');
          }
      } else {
          debugPrint('MediaKitAdapter: activeSubtitleTracks setter - _player.state.tracks.subtitle is EMPTY.');
      }
      
      if (value.isEmpty) {
        _player.setSubtitleTrack(SubtitleTrack.no());
        debugPrint('MediaKitAdapter: UI set no subtitle track. Telling mpv to use "no".');
        // _activeSubtitleTracks should be updated by _performSubtitleSyncLogic via _handleActiveSubtitleTrackDataChange
        return;
      }
      
      final uiSelectedMediaInfoIndex = value.first;

      // CRITICAL CHECK: If _mediaInfo has been reset (subtitles are null/empty),
      // do not proceed with trying to set a track based on an outdated index.
      if (mediaInfoSubtitles == null || mediaInfoSubtitles.isEmpty) {
          debugPrint('MediaKitAdapter: CRITICAL - UI requested track index $uiSelectedMediaInfoIndex, but _mediaInfo.subtitle is currently NULL or EMPTY. This likely means player state was reset externally (e.g., by SubtitleManager clearing tracks). IGNORING this subtitle change request to prevent player stop/crash. The UI should resync with the new player state via listeners.');
          // DO NOT call _player.setSubtitleTrack() here.
          return; // Exit early
      }

      // Proceed if _mediaInfo.subtitle is valid
      if (uiSelectedMediaInfoIndex >= 0 && uiSelectedMediaInfoIndex < mediaInfoSubtitles.length) {
        final selectedMediaInfoTrack = mediaInfoSubtitles[uiSelectedMediaInfoIndex];
        final mpvTrackIdToSelect = selectedMediaInfoTrack.metadata['id'];

        SubtitleTrack? actualSubtitleTrackToSet;
        for (final stData in _player.state.tracks.subtitle) {
          if (stData.id == mpvTrackIdToSelect) {
            actualSubtitleTrackToSet = stData;
            break;
          }
        }

        if (actualSubtitleTrackToSet != null) {
          debugPrint('MediaKitAdapter: UI selected _mediaInfo index $uiSelectedMediaInfoIndex (MPV ID: $mpvTrackIdToSelect). Setting player subtitle track with SubtitleTrack(id: ${actualSubtitleTrackToSet.id}, title: ${actualSubtitleTrackToSet.title ?? 'N/A'}).');
          _player.setSubtitleTrack(actualSubtitleTrackToSet);
      } else {
          debugPrint('MediaKitAdapter: Could not find SubtitleTrackData in player.state.tracks.subtitle for MPV ID "$mpvTrackIdToSelect" (from UI index $uiSelectedMediaInfoIndex). Setting to "no" as a fallback for this specific failure.');
          _player.setSubtitleTrack(SubtitleTrack.no());
        }
      } else {
        // This case means mediaInfoSubtitles is NOT empty, but the index is out of bounds.
        debugPrint('MediaKitAdapter: Invalid UI track index $uiSelectedMediaInfoIndex for a NON-EMPTY _mediaInfo.subtitle list (length: ${mediaInfoSubtitles.length}). Setting to "no" because the requested index is out of bounds.');
        _player.setSubtitleTrack(SubtitleTrack.no());
      }
    } catch (e, s) {
      debugPrint('MediaKitAdapter: Error in "set activeSubtitleTracks": $e\\nStack trace:\\n$s. Setting to "no" as a safety measure.');
      // Avoid crashing, but set to 'no' if an unexpected error occurs.
      if (!_isDisposed) { // Check if player is disposed before trying to set track
        try {
            _player.setSubtitleTrack(SubtitleTrack.no());
        } catch (playerError) {
            debugPrint('MediaKitAdapter: Further error trying to set SubtitleTrack.no() in catch block: $playerError');
        }
      }
    }
  }
  
  @override
  List<int> get activeAudioTracks => _activeAudioTracks;
  
  @override
  set activeAudioTracks(List<int> value) {
    try {
      _activeAudioTracks = value;
      final List<PlayerAudioStreamInfo>? mediaInfoAudios = _mediaInfo.audio;
      
      if (value.isEmpty) {
        if (mediaInfoAudios != null && mediaInfoAudios.isNotEmpty) {
          final firstRealAudioTrackMpvId = mediaInfoAudios[0].metadata['id'];
          AudioTrack? actualTrackData;
          for(final atd in _player.state.tracks.audio) {
            if (atd.id == firstRealAudioTrackMpvId) {
              actualTrackData = atd;
              break;
            }
          }
          if (actualTrackData != null) {
            debugPrint('默认设置第一个音频轨道 (ID: ${actualTrackData.id})');
            _player.setAudioTrack(actualTrackData);
            _activeAudioTracks = [0];
          }
        }
        return;
      }
      
      final uiSelectedMediaInfoIndex = value.first;
      if (mediaInfoAudios != null && uiSelectedMediaInfoIndex >= 0 && uiSelectedMediaInfoIndex < mediaInfoAudios.length) {
        final selectedMediaInfoTrack = mediaInfoAudios[uiSelectedMediaInfoIndex];
        final mpvTrackIdToSelect = selectedMediaInfoTrack.metadata['id'];

        AudioTrack? actualTrackData;
        for(final atd in _player.state.tracks.audio) {
            if (atd.id == mpvTrackIdToSelect) {
              actualTrackData = atd;
              break;
            }
        }
        if (actualTrackData != null) {
          debugPrint('设置音频轨道: _mediaInfo索引=$uiSelectedMediaInfoIndex, ID=${actualTrackData.id}');
          _player.setAudioTrack(actualTrackData);
        } else {
           _player.setAudioTrack(AudioTrack.auto());
        }
      } else {
         _player.setAudioTrack(AudioTrack.auto());
      }
    } catch (e) {
      debugPrint('设置音频轨道失败: $e');
      _player.setAudioTrack(AudioTrack.auto());
    }
  }
  
  @override
  int get position => _player.state.position.inMilliseconds;
  
  @override
  bool get supportsExternalSubtitles => true;
  
  @override
  Future<int?> updateTexture() async {
    if (_textureIdNotifier.value == null) {
      _updateTextureIdFromController();
    }
    return _textureIdNotifier.value;
  }
  
  @override
  void setMedia(String path, PlayerMediaType type) {
    if (type == PlayerMediaType.subtitle) {
      debugPrint('MediaKitAdapter: setMedia called for SUBTITLE. Path: "$path"');
      if (path.isEmpty) {
        debugPrint('MediaKitAdapter: setMedia (for subtitle) - Path is empty. Calling player.setSubtitleTrack(SubtitleTrack.no()). Main media and info remain UNCHANGED.');
        if (!_isDisposed) _player.setSubtitleTrack(SubtitleTrack.no());
      } else {
        // Assuming path is a valid file URI or path that media_kit can handle for subtitles
        debugPrint('MediaKitAdapter: setMedia (for subtitle) - Path is "$path". Calling player.setSubtitleTrack(SubtitleTrack.uri(path)). Main media and info remain UNCHANGED.');
        if (!_isDisposed) _player.setSubtitleTrack(SubtitleTrack.uri(path));
      }
      // Player events will handle updating _activeSubtitleTracks via _performSubtitleSyncLogic.
      return; 
    }

    // --- Original logic for Main Video/Audio Media ---
    _currentMedia = path;
    _activeSubtitleTracks = [];
    _activeAudioTracks = [];
    _lastKnownActiveSubtitleId = null; 
    _mediaInfo = PlayerMediaInfo(duration: 0);
    _isDisposed = false;
    
    _currentMediaHasNoInitiallyEmbeddedSubtitles = false; // Reset for new main media. Will be determined by first _updateMediaInfo.
    _mediaPathForSubtitleStatusCheck = path; // Set so _updateMediaInfo can perform initial check.
    
    final mediaOptions = <String, dynamic>{};
    _properties.forEach((key, value) {
      mediaOptions[key] = value;
    });
    
    debugPrint('MediaKitAdapter: 打开媒体 (MAIN VIDEO/AUDIO): $path');
    if (!_isDisposed) _player.open(Media(path, extras: mediaOptions), play: false);
    
    // This delayed block might still be useful for printing initial track info after the player has processed the new media.
    Future.delayed(const Duration(milliseconds: 500), () {
      if(!_isDisposed) { 
      _printAllTracksInfo(_player.state.tracks);
         debugPrint('MediaKitAdapter: setMedia (MAIN VIDEO/AUDIO) - Delayed block executed. Initial track info printed.');
      }
    });
  }
  
  @override
  Future<void> prepare() async {
    await updateTexture();
     if(!_isDisposed) {
    _printAllTracksInfo(_player.state.tracks);
     }
  }
  
  @override
  void seek({required int position}) {
    _player.seek(Duration(milliseconds: position));
  }
  
  @override
  void dispose() {
    _isDisposed = true;
    _trackSubscription?.cancel(); 
    _player.dispose();
    _textureIdNotifier.dispose();
  }
  
  @override
  GlobalKey get repaintBoundaryKey => _repaintBoundaryKey;
  
  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    try {
      final videoWidth = _player.state.width ?? 1920;
      final videoHeight = _player.state.height ?? 1080;
      debugPrint('MediaKit: 视频原始尺寸: ${videoWidth}x${videoHeight}');
      final actualWidth = width > 0 ? width : videoWidth;
      final actualHeight = height > 0 ? height : videoHeight;
      
      Uint8List? bytes = await _player.screenshot(
        format: 'image/png',
        includeLibassSubtitles: true
      );
      
      if (bytes == null) {
        debugPrint('MediaKit: PNG截图失败，尝试JPEG格式');
        bytes = await _player.screenshot(
          format: 'image/jpeg',
          includeLibassSubtitles: true
        );
      }
      
      if (bytes == null) {
        debugPrint('MediaKit: 所有格式截图失败，尝试原始BGRA格式');
        bytes = await _player.screenshot(
          format: null, 
          includeLibassSubtitles: true
        );
      }
      
      if (bytes != null) {
        debugPrint('MediaKit: 成功获取截图，大小: ${bytes.length} 字节，尺寸: ${actualWidth}x${actualHeight}');
        final String base64Image = base64Encode(bytes);
        if (base64Image.length > 200) {
          debugPrint('MediaKit: 截图BASE64(截断): ${base64Image.substring(0, 100)}...${base64Image.substring(base64Image.length - 100)}');
        } else {
          debugPrint('MediaKit: 截图BASE64: $base64Image');
        }
        if (bytes.length > 16) {
          debugPrint('MediaKit: 截图头16字节: ${bytes.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        }
        return PlayerFrame(
          bytes: bytes,
          width: actualWidth,
          height: actualHeight,
        );
      } else {
        debugPrint('MediaKit: 所有截图方法都失败');
      }
    } catch (e) {
      debugPrint('MediaKit: 截图过程出错: $e');
    }
    return null;
  }
  
  @override
  void setDecoders(PlayerMediaType type, List<String> names) {
    _decoders[type] = names;
  }
  
  @override
  List<String> getDecoders(PlayerMediaType type) {
    return _decoders[type] ?? [];
  }
  
  @override
  String? getProperty(String name) {
    return _properties[name];
  }
  
  @override
  void setProperty(String name, String value) {
    _properties[name] = value;
  }
  
  @override
  Future<void> playDirectly() async {
    await _player.play();
  }
  
  @override
  Future<void> pauseDirectly() async {
    await _player.pause();
  }
  
  void _setupDefaultTrackSelectionBehavior() {
    try {
      final dynamic platform = _player.platform;
      if (platform != null) {
        platform.setProperty?.call("vid", "auto");
        platform.setProperty?.call("aid", "auto"); 
        platform.setProperty?.call("sid", "auto"); 
        
        List<String> preferredSlangs = [
          // Prioritize specific forms of Chinese
          'chi-Hans', 'chi-CN', 'chi-SG', 'zho-Hans', 'zho-CN', 'zho-SG', // Simplified Chinese variants
          'sc', 'simplified', '简体', // Keywords for Simplified
          'chi-Hant', 'chi-TW', 'chi-HK', 'zho-Hant', 'zho-TW', 'zho-HK', // Traditional Chinese variants
          'tc', 'traditional', '繁体', // Keywords for Traditional
          // General Chinese
          'chi', 'zho', 'chinese', '中文', 
          // Other languages as fallback
          'eng', 'en', 'english', 
          'jpn', 'ja', 'japanese'
        ];
        final slangString = preferredSlangs.join(',');
        platform.setProperty?.call("slang", slangString);
        debugPrint('MediaKitAdapter: Set MPV preferred subtitle languages (slang) to: $slangString');

        _player.stream.tracks.listen((tracks) {
          // _updateMediaInfo (called by this listener) will then call _ensureDefaultTracksSelected.
        });
      }
    } catch (e) {
      debugPrint('MediaKitAdapter: 设置默认轨道选择策略失败: $e');
    }
  }
}

// Helper map similar to SubtitleManager's languagePatterns
const Map<String, String> _subtitleNormalizationPatterns = {
  r'simplified|简体|chs|zh-hans|zh-cn|zh-sg|sc': '简体中文',
  r'traditional|繁体|cht|zh-hant|zh-tw|zh-hk|tc': '繁体中文',
  r'chi|zho|chinese|中文': '中文', // General Chinese as a fallback
  r'eng|en|英文|english': '英文',
  r'jpn|ja|日文|japanese': '日语',
  r'kor|ko|韩文|korean': '韩语',
  // Add other languages as needed
};

String _getNormalizedLanguageHelper(String input) { // Renamed to avoid conflict if class has a member with same name
  if (input.isEmpty) return '';
  final lowerInput = input.toLowerCase();
  for (final entry in _subtitleNormalizationPatterns.entries) {
    final pattern = RegExp(entry.key, caseSensitive: false);
    if (pattern.hasMatch(lowerInput)) {
      return entry.value; // Return "简体中文", "繁体中文", "中文", "英文", etc.
    }
  }
  return input; // Return original if no pattern matches
}

// Method to produce normalized title and language for PlayerSubtitleStreamInfo
({String title, String language}) _normalizeSubtitleTrackInfoHelper(String? rawTitle, String? rawLang, int trackIndexForFallback) {
  String originalTitle = rawTitle ?? '';
  String originalLangCode = rawLang ?? '';

  String determinedLanguage = '';

  // Priority 1: Determine language from rawLang
  if (originalLangCode.isNotEmpty) {
    determinedLanguage = _getNormalizedLanguageHelper(originalLangCode);
  }

  // Priority 2: If language from rawLang is generic ("中文") or unrecognized,
  // try to get a more specific one (简体中文/繁体中文) from rawTitle.
  if (originalTitle.isNotEmpty) {
    String langFromTitle = _getNormalizedLanguageHelper(originalTitle);
    if (langFromTitle == '简体中文' || langFromTitle == '繁体中文') {
      if (determinedLanguage != '简体中文' && determinedLanguage != '繁体中文') {
        // Title provides a more specific Chinese variant than lang code did (or lang code was not Chinese)
        determinedLanguage = langFromTitle;
      }
    } else if (determinedLanguage.isEmpty || determinedLanguage == originalLangCode) {
      // If lang code didn't yield a recognized language (or was empty),
      // and title yields a recognized one (even if just "中文" or "英文"), use it.
      if (langFromTitle != originalTitle && _subtitleNormalizationPatterns.containsValue(langFromTitle)) {
         determinedLanguage = langFromTitle;
      }
    }
  }

  // If still no recognized language, use originalLangCode if available, otherwise "未知"
  if (determinedLanguage.isEmpty || (determinedLanguage == originalLangCode && !_subtitleNormalizationPatterns.containsValue(determinedLanguage))) {
    determinedLanguage = originalLangCode.isNotEmpty ? originalLangCode : '未知';
  }
  
  String finalTitle;
  final String finalLanguage = determinedLanguage;

  if (originalTitle.isNotEmpty) {
    String originalTitleAsLang = _getNormalizedLanguageHelper(originalTitle);
    
    // Case 1: The original title string itself IS a direct representation of the final determined language.
    // Example: finalLanguage="简体中文", originalTitle="简体" or "Simplified Chinese".
    // In this scenario, the title should just be the clean, finalLanguage.
    if (originalTitleAsLang == finalLanguage) {
        // Check if originalTitle is essentially just the language or has more info.
        // If originalTitle is "简体中文 (Director's Cut)" -> originalTitleAsLang is "简体中文"
        // originalTitle is NOT simple.
        // If originalTitle is "简体" -> originalTitleAsLang is "简体中文"
        // originalTitle IS simple.
        bool titleIsSimpleRepresentation = true; 
        // A simple heuristic: if stripping common language keywords from originalTitle leaves little else,
        // or if originalTitle does not contain typical annotation markers like '('.
        // This is tricky; for now, if originalTitleAsLang matches finalLanguage,
        // we assume originalTitle might be a shorter/variant form and prefer finalLanguage as the base title.
        // If originalTitle had extra info, it means originalTitleAsLang would likely NOT be finalLanguage,
        // OR originalTitle would be longer.

        if (originalTitle.length > finalLanguage.length + 3 && originalTitle.contains(finalLanguage)) {
            // e.g. originalTitle = "简体中文 (Forced)", finalLanguage = "简体中文"
            finalTitle = originalTitle;
        } else if (finalLanguage.contains(originalTitle) && finalLanguage.length >= originalTitle.length) {
            // e.g. originalTitle = "简体", finalLanguage = "简体中文" -> title should be "简体中文"
             finalTitle = finalLanguage;
        } else if (originalTitle == originalTitleAsLang) { //e.g. originalTitle = "简体中文", finalLanguage = "简体中文"
            finalTitle = finalLanguage;
        }
         else {
            // originalTitle might be "Simplified" and finalLanguage "简体中文".
            // Or, originalTitle is "Chinese (Commentary)" (originalTitleAsLang="中文") and finalLanguage="中文".
            // If originalTitle is more descriptive than just the language it normalizes to.
            finalTitle = originalTitle;
        }

    } else {
      // Case 2: The original title is NOT a direct representation of the final language.
      // Example: finalLanguage="简体中文", originalTitle="Commentary track".
      // Or finalLanguage="印尼语", originalTitle="Bahasa Indonesia". (Here originalTitleAsLang might be "印尼语")
      // We should combine them if originalTitle isn't already reflecting the language.
      if (finalLanguage != '未知' && !originalTitle.toLowerCase().contains(finalLanguage.toLowerCase().substring(0, finalLanguage.length > 2 ? 2:1 )) ) {
         // Avoids "简体中文 (简体中文 Commentary)" if originalTitle was "简体中文 Commentary"
         // Check if originalTitle already contains the language (or part of it)
          bool titleAlreadyHasLang = false;
          for(var patValue in _subtitleNormalizationPatterns.values){
              if (patValue != "未知" && originalTitle.contains(patValue)){
                  titleAlreadyHasLang = true;
                  break;
              }
          }
          if (titleAlreadyHasLang) {
              finalTitle = originalTitle;
          } else {
              finalTitle = "$finalLanguage ($originalTitle)";
          }

      } else {
        finalTitle = originalTitle;
      }
    }
  } else {
    // originalTitle is empty, so title is just the language.
    finalTitle = finalLanguage;
  }

  // Fallback if title somehow ended up empty or generic "n/a"
  if (finalTitle.isEmpty || finalTitle.toLowerCase() == 'n/a') {
    finalTitle = (finalLanguage != '未知' && finalLanguage.isNotEmpty) ? finalLanguage : "轨道 ${trackIndexForFallback + 1}";
  }
   if (finalTitle.isEmpty) finalTitle = "轨道 ${trackIndexForFallback + 1}";


  return (title: finalTitle, language: finalLanguage);
} 