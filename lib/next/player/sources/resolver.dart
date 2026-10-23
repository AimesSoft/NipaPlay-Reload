import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/models/media_server_playback.dart' as server;
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/dandanplay_remote_service.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/services/media_server_playback_client.dart';
import 'package:nipaplay/services/playback_source_service.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/utils/media_source_utils.dart';

import '../kernel/driver.dart';
import 'server_progress.dart';

/// Immutable, per-open source facts. Authenticated URLs never enter facts or
/// the resume key. The selected stream is owned by this session alone.
final class SourcePlan {
  const SourcePlan(
      {required this.item,
      required this.source,
      required this.detail,
      this.serverSession,
      this.selection = const {},
      this.progress});
  final PlayableItem item;
  final ResolvedSource source;
  final PlaybackDetailContext detail;
  final server.PlaybackSession? serverSession;
  final JsonMap selection;
  final ServerProgress? progress;
  bool get isServer => serverSession != null;
}

/// Reuses Classic's data clients and source/episode resolvers, without its
/// player, singleton playback synchronizers or UI state.
class NextSourceResolver {
  NextSourceResolver({this.context});
  final BuildContext? Function()? context;
  Future<SourcePlan?> Function(PlayableItem)? specialSource;

  Future<SourcePlan> resolve(PlayableItem item,
      {Duration? start,
      JsonMap selection = const {},
      bool direct = false}) async {
    final special = await specialSource?.call(item);
    if (special != null) return special;
    final path = item.videoPath;
    final uri = Uri.tryParse(path);
    final scheme = uri?.scheme ?? '';
    if (scheme == 'mesh') {
      throw const Failure(
          FailureCode.notFound, 'The Mesh episode is unavailable.');
    }
    final isServer = scheme == 'jellyfin' || scheme == 'emby';
    String actual = item.actualPlayUrl ?? path;
    server.PlaybackSession? session;
    ServerProgress? progress;
    int? audio, subtitle;
    String? external;
    JsonMap chosen = selection;
    if (isServer) {
      final emby = scheme == 'emby';
      final MediaServerPlaybackClient playback =
          emby ? EmbyService.instance : JellyfinService.instance;
      if (emby) {
        await EmbyTranscodeProvider().initialize();
      } else {
        await JellyfinTranscodeProvider().initialize();
      }
      final itemId = path.substring(path.indexOf('://') + 3).split('/').last;
      final transcodeEnabled = emby
          ? EmbyTranscodeProvider().transcodeEnabled
          : JellyfinTranscodeProvider().transcodeEnabled;
      final quality =
          JellyfinVideoQuality.values.byName(selection['quality'] as String? ??
              (!transcodeEnabled
                      ? JellyfinVideoQuality.original
                      : emby
                          ? EmbyTranscodeProvider().currentVideoQuality
                          : JellyfinTranscodeProvider().currentVideoQuality)
                  .name);
      session = await playback.createPlaybackSession(
          itemId: itemId,
          quality: quality,
          startPositionMs: start?.inMilliseconds,
          mediaSourceId: selection['mediaSourceId'] as String?,
          audioStreamIndex: selection['audioIndex'] as int?,
          subtitleStreamIndex: selection['subtitleIndex'] as int?,
          burnInSubtitle: selection['burnIn'] == true);
      // Jellyfin's direct-play fast path omits PlaybackInfo. Fetch versions
      // through the same catalogue client so direct streams expose tracks too.
      var versions = session.mediaSources;
      if (versions.isEmpty) {
        versions = emby
            ? await EmbyService.instance.getPlaybackMediaSources(itemId)
            : await JellyfinService.instance.getPlaybackMediaSources(itemId);
      }
      final selected =
          versions.where((v) => v.id == session!.mediaSourceId).firstOrNull ??
              versions.firstOrNull;
      if (selected != null && selected.id != session.mediaSourceId) {
        session = await playback.createPlaybackSession(
            itemId: itemId,
            quality: quality,
            startPositionMs: start?.inMilliseconds,
            mediaSourceId: selected.id,
            audioStreamIndex: selection['audioIndex'] as int?,
            subtitleStreamIndex: selection['subtitleIndex'] as int?,
            burnInSubtitle: selection['burnIn'] == true);
      }
      session =
          session.copyWith(mediaSources: versions, selectedSource: selected);
      actual = session.streamUrl;
      if (!session.isTranscoding && selected != null) {
        int ordinal(String kind, int index) {
          final at = selected.mediaStreams
              .where((t) => t['Type'] == kind && t['IsExternal'] != true)
              .toList()
              .indexWhere((t) => t['Index'] == index);
          if (at < 0) {
            throw const Failure(FailureCode.notFound,
                'The server track is not in this media version.');
          }
          return at;
        }

        if (selection['audioIndex'] case final int index) {
          audio = ordinal('Audio', index);
        }
        if (selection['subtitleIndex'] case final int index) {
          if (index == -1) {
            subtitle = -1;
          } else {
            final track = selected.mediaStreams
                .where((t) => t['Type'] == 'Subtitle' && t['Index'] == index)
                .firstOrNull;
            if (track == null) {
              throw const Failure(FailureCode.notFound,
                  'The server subtitle is not in this version.');
            }
            if (track['IsExternal'] == true) {
              external = emby
                  ? await EmbyService.instance.downloadSubtitleFile(
                      itemId, index, track['Codec'] as String,
                      mediaSourceId: selected.id)
                  : await JellyfinService.instance.downloadSubtitleFile(
                      itemId, index, track['Codec'] as String,
                      mediaSourceId: selected.id);
              if (external == null) {
                throw const Failure(FailureCode.unavailable,
                    'The selected server subtitle could not be downloaded.');
              }
            } else {
              subtitle = ordinal('Subtitle', index);
            }
          }
        }
      }
      chosen = {
        ...selection,
        'quality': quality.name,
        'mediaSourceId': session.mediaSourceId,
        'transcode': emby
            ? EmbyTranscodeProvider().transcodeEnabled
            : JellyfinTranscodeProvider().transcodeEnabled,
        'burnIn': selection['burnIn'] == true
      };
      // Capture account/endpoint/headers now; a later source switch cannot
      // send this session's progress to the newly active account.
      progress = ServerProgress(
          session: session,
          selection: chosen,
          baseUrl: emby
              ? EmbyService.instance.serverUrl!
              : JellyfinService.instance.serverUrl!,
          prefix: emby ? '/emby' : '',
          headers: emby
              ? await EmbyService.instance.buildAuthorizationHeaders()
              : await JellyfinService.instance.buildAuthorizationHeaders());
    } else if (scheme == 'dandanplay') {
      final remote = DandanplayRemoteService.instance;
      await remote.loadSavedSettings();
      final identifier = path.substring('dandanplay://'.length);
      final parts = identifier.split('/');
      final byId = parts.first == 'id' ||
          parts.first == 'stream' && parts.length > 1 && parts[1] == 'id';
      actual = remote.buildEpisodeStreamUrl(
              hash: byId ? null : parts.last,
              entryId: byId ? parts.last : null) ??
          '';
    } else if (MediaSourceUtils.isNewWebDavPath(path)) {
      await MediaSourceUtils.prepareRemotePath(path);
      actual = MediaSourceUtils.resolveWebDavPathToUrl(path) ?? '';
    } else if (MediaSourceUtils.isNewSmbPath(path)) {
      await SMBProxyService.instance.initialize();
      actual = MediaSourceUtils.resolveSmbPathToUrl(path) ?? '';
      direct = true;
    } else if (scheme == 'file') {
      actual = uri!.toFilePath(windows: Platform.isWindows);
    }
    if (actual.isEmpty) {
      throw const Failure(FailureCode.notFound,
          'The media source could not resolve this file.');
    }
    final c = context?.call();
    final detailItem = scheme == 'dandanplay'
        ? PlayableItem(
            videoPath: actual,
            title: item.title,
            subtitle: item.subtitle,
            animeId: item.animeId,
            episodeId: item.episodeId,
            historyItem: item.historyItem)
        : item;
    var detail = item.detailContext ??
        (c != null && c.mounted
            ? await PlaybackSourceService.resolve(c, detailItem)
            : PlaybackSourceService.fallback(detailItem));
    if (scheme == 'dandanplay') {
      final original = detail;
      detail = PlaybackDetailContext(
          sourceKind: original.sourceKind,
          sourceLabel: original.sourceLabel,
          sourceKey: original.sourceKey,
          title: original.title,
          subtitle: original.subtitle,
          animeId: original.animeId,
          imageUrl: original.imageUrl,
          isIdentified: original.isIdentified,
          episodeLoader: () async => compute(
              _dandanEpisodes, await original.episodeLoader(),
              debugLabel: 'next.dandan.episodes'));
    }
    final actualUri = Uri.tryParse(actual);
    final local =
        actualUri?.scheme.isEmpty == true || actualUri?.scheme == 'file';
    final host = actualUri?.host.toLowerCase();
    return SourcePlan(
        item: item,
        detail: detail,
        serverSession: session,
        selection: chosen,
        progress: progress,
        source: ResolvedSource(
            locator: scheme == 'file' ? actual : path,
            uri: actual,
            kind: local ? 'local' : (isServer ? scheme : 'network'),
            direct: direct ||
                const {'localhost', '127.0.0.1', '::1'}.contains(host),
            audioTrack: audio,
            subtitleTrack: subtitle,
            externalSubtitle: external));
  }
}

List<PlaybackDetailEpisode> _dandanEpisodes(
        List<PlaybackDetailEpisode> episodes) =>
    [
      for (final episode in episodes)
        PlaybackDetailEpisode(
            id: episode.id,
            videoPath:
                'dandanplay://${Uri.parse(episode.videoPath).path.split('/api/v1/stream/').last}',
            title: episode.title,
            subtitle: episode.subtitle,
            animeId: episode.animeId,
            episodeId: episode.episodeId,
            historyItem: episode.historyItem,
            mediaKey: null,
            progress: episode.progress)
    ];
