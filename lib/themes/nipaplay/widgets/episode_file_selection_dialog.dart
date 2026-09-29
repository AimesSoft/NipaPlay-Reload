import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/models/episode_file_candidate.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class EpisodeFileSelectionDialog extends StatefulWidget {
  const EpisodeFileSelectionDialog({
    super.key,
    required this.candidates,
    required this.onUnmatch,
  });

  final List<EpisodeFileCandidate> candidates;
  final Future<bool> Function(EpisodeFileCandidate) onUnmatch;

  static Future<EpisodeFileCandidate?> show({
    required BuildContext context,
    required List<EpisodeFileCandidate> candidates,
    required Future<bool> Function(EpisodeFileCandidate) onUnmatch,
  }) {
    // PlaybackService can present from the root navigator, above page scopes.
    final surface = context
            .getInheritedWidgetOfExactType<AppDisplaySurfaceScope>()
            ?.surface ??
        (globals.isTelevision
            ? AppDisplaySurface.television
            : globals.isPhone
                ? AppDisplaySurface.phone
                : AppDisplaySurface.desktopTablet);
    return BlurDialog.show<EpisodeFileCandidate>(
      context: context,
      title: '选择播放文件',
      displaySurface: surface,
      desktopMaxWidth: 640,
      contentWidget: AppDisplaySurfaceScope(
        surface: surface,
        child: EpisodeFileSelectionDialog(
          candidates: candidates,
          onUnmatch: onUnmatch,
        ),
      ),
    );
  }

  @override
  State<EpisodeFileSelectionDialog> createState() =>
      _EpisodeFileSelectionDialogState();
}

class _EpisodeFileSelectionDialogState
    extends State<EpisodeFileSelectionDialog> {
  late final List<EpisodeFileCandidate> _candidates =
      List.of(widget.candidates);
  bool _busy = false;
  String? _error;

  Future<void> _unmatch(EpisodeFileCandidate candidate) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await widget.onUnmatch(candidate)) {
        throw StateError('匹配信息已发生变化');
      }
      if (!mounted) return;
      setState(() => _candidates
          .removeWhere((item) => item.identity == candidate.identity));
    } catch (_) {
      if (mounted) setState(() => _error = '解除匹配失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodyMedium ??
          TextStyle(color: colors.onSurface, fontSize: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.candidates.first.history.animeName} · '
            '${widget.candidates.first.history.episodeTitle ?? '当前剧集'}',
            style:
                TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text('此剧集匹配了多个视频文件，请选择要播放的文件。',
              style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(height: 16),
          if (_candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('已解除所有文件的匹配', textAlign: TextAlign.center),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight:
                      math.min(420, MediaQuery.sizeOf(context).height * 0.48)),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _candidates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final candidate = _candidates[index];
                  return Material(
                    key: ValueKey(candidate.identity),
                    color:
                        colors.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _busy
                          ? null
                          : () => Navigator.of(context).pop(candidate),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: colors.primary
                                              .withValues(alpha: 0.16),
                                          border: Border.all(
                                            color: colors.primary
                                                .withValues(alpha: 0.55),
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${index + 1}#',
                                          style: TextStyle(
                                            color: colors.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          candidate.sourceLabel,
                                          style: TextStyle(
                                            color: colors.onSurface,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(candidate.displayPath,
                                      style: TextStyle(
                                          color: colors.onSurfaceVariant,
                                          fontSize: 13,
                                          height: 1.4)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            AdaptiveMediaIconButton(
                              key: ValueKey('unmatch:${candidate.identity}'),
                              desktopIcon: Icons.close_rounded,
                              phoneIcon: CupertinoIcons.xmark,
                              color: colors.error,
                              tooltip: '解除此文件的匹配',
                              onPressed:
                                  _busy ? null : () => _unmatch(candidate),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const Center(child: AdaptiveMediaActivityIndicator(size: 18)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: colors.error)),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: AdaptiveMediaActionButton(
              label: '取消',
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
