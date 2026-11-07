import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'details.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/utils/media_source_utils.dart';

import '../kernel/driver.dart';

/// Immutable, per-open source facts. Authenticated URLs never enter facts or
/// the resume key. The selected stream is owned by this session alone.
final class SourcePlan {
  const SourcePlan({
    required this.item,
    required this.source,
    required this.detail,
    this.resumePosition,
  });
  final PlayableItem item;
  final ResolvedSource source;
  final PlaybackDetailContext detail;
  final Duration? resumePosition;
}

/// Reuses Classic's data clients and source/episode resolvers, without its
/// player, singleton playback synchronizers or UI state.
class NextSourceResolver {
  NextSourceResolver({this.context});
  final BuildContext? Function()? context;
  Future<SourcePlan?> Function(PlayableItem)? specialSource;

  Future<SourcePlan> resolve(PlayableItem item,
      {Duration? start, bool direct = false}) async {
    final special = await specialSource?.call(item);
    if (special != null) return special;
    final path = item.videoPath;
    final uri = Uri.tryParse(path);
    final scheme = uri?.scheme ?? '';
    if (scheme == 'mesh') {
      throw const Failure(
          FailureCode.notFound, 'The Mesh episode is unavailable.');
    }
    if (!{
          '',
          'file',
          'http',
          'https',
          'webdav',
          'smb',
          'rtsp',
          'rtmp',
          'content'
        }.contains(scheme) &&
        !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      throw const Failure(
          FailureCode.invalidInput, 'Unsupported media source.');
    }
    String actual = item.actualPlayUrl ?? path;
    if (MediaSourceUtils.isNewWebDavPath(path)) {
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
    final detail = await SourceDetails.resolve(item);
    final actualUri = Uri.tryParse(actual);
    final local =
        actualUri?.scheme.isEmpty == true || actualUri?.scheme == 'file';
    final host = actualUri?.host.toLowerCase();
    return SourcePlan(
        item: item,
        detail: detail,
        source: ResolvedSource(
          locator: scheme == 'file' ? actual : path,
          uri: actual,
          kind: local ? 'local' : 'network',
          direct:
              direct || const {'localhost', '127.0.0.1', '::1'}.contains(host),
        ));
  }
}
