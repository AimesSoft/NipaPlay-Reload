
// lib/pages/external_player_console_page.dart
// 掌管 Linux 平台下外部播放器会话的控制台页面


import 'package:flutter/material.dart';
import 'package:nipaplay/constants/danmaku/mode.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/external_player_session.dart';
import 'package:nipaplay/services/external_player_console_service.dart';


/// 一个用于显示外部播放器会话信息的控制台页面
class ExternalPlayerConsolePage extends StatelessWidget {
  const ExternalPlayerConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = ExternalPlayerConsoleService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final session = service.session;
        return SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: session == null
                    ? const _EmptyConsole()
                    : _ConsoleCard(
                        session: session,
                        mediaPath: service.mediaPath,
                        animeTitle: service.animeTitle,
                        episodeTitle: service.episodeTitle,
                        episodeId: service.episodeId,
                        danmakuList: service.danmakuList,
                        danmakuStartTime: service.danmakuStartTime,
                        isPaused: session.isPaused ?? false,
                        danmakuOpacity: service.danmakuOpacity,
                        danmakuOutlineEnabled: service.danmakuOutlineEnabled,
                        supportsDanmakuOpacity: service.supportsDanmakuOpacity,
                        supportsDanmakuOutline: service.supportsDanmakuOutline,
                        activeDanmakuIndices: service.activeDanmakuIndices,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyConsole extends StatelessWidget {
  const _EmptyConsole();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.subtitles_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 20),
          Text(
            context.l10n.externalPlayerConsoleEmptyTitle,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.externalPlayerConsoleEmptyDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ConsoleCard extends StatelessWidget {
  const _ConsoleCard({
    required this.session,
    required this.mediaPath,
    required this.animeTitle,
    required this.episodeTitle,
    required this.episodeId,
    required this.danmakuList,
    required this.danmakuStartTime,
    required this.isPaused,
    required this.danmakuOpacity,
    required this.danmakuOutlineEnabled,
    required this.supportsDanmakuOpacity,
    required this.supportsDanmakuOutline,
    required this.activeDanmakuIndices,
  });

  final ExternalPlayerSession session;
  final String? mediaPath;
  final String? animeTitle;
  final String? episodeTitle;
  final int? episodeId;
  final List<DanmakuItem> danmakuList;
  final Duration Function(DanmakuItem) danmakuStartTime;
  final bool isPaused;
  final double danmakuOpacity;
  final bool danmakuOutlineEnabled;
  final bool supportsDanmakuOpacity;
  final bool supportsDanmakuOutline;
  final List<int> activeDanmakuIndices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = context.l10n;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.subtitles_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    localizations.externalPlayerConsoleTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _detailRow(
              context,
              localizations.externalPlayerConsoleAnime,
              _nonEmptyOr(
                animeTitle,
                localizations.externalPlayerConsoleUnknownAnime,
              ),
            ),
            _detailRow(
              context,
              localizations.externalPlayerConsoleEpisode,
              _nonEmptyOr(
                episodeTitle,
                localizations.externalPlayerConsoleUnknownEpisode,
              ),
            ),
            _detailRow(
              context,
              localizations.externalPlayerConsoleEpisodeId,
              episodeId?.toString() ?? '-',
            ),
            _detailRow(
              context,
              localizations.externalPlayerConsoleProcessId,
              session.processId.toString(),
            ),
            _detailRow(
              context,
              localizations.externalPlayerConsoleMediaPath,
              mediaPath ?? '-',
            ),
            const SizedBox(height: 20),
            _buildProgress(context),
            const SizedBox(height: 20),
            _buildDanmakuOpacity(context),
            const SizedBox(height: 8),
            _buildDanmakuOutline(context),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: session.ipcPath == null
                        ? null
                        : ExternalPlayerConsoleService.togglePause,
                    icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(
                      isPaused
                          ? localizations.externalPlayerConsoleResume
                          : localizations.externalPlayerConsolePause,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed:
                        ExternalPlayerConsoleService.closePlayerAndConsole,
                    icon: const Icon(Icons.close),
                    label: Text(localizations.externalPlayerConsoleClose),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Divider(color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            _DanmakuList(
              session: session,
              items: danmakuList,
              startTimeFor: danmakuStartTime,
              activeIndices: activeDanmakuIndices,
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                SelectableText(value),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 140, child: Text(label)),
              Expanded(child: SelectableText(value)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.externalPlayerConsoleProgress,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        _SeekProgress(session: session),
      ],
    );
  }

  Widget _buildDanmakuOpacity(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizations.danmakuOpacityTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text(
              '${(danmakuOpacity * 100).round()}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Slider(
          value: danmakuOpacity,
          min: 0,
          max: 1,
          divisions: 100,
          label: '${(danmakuOpacity * 100).round()}%',
          onChanged: supportsDanmakuOpacity
              ? ExternalPlayerConsoleService.setDanmakuOpacity
              : null,
        ),
      ],
    );
  }

  Widget _buildDanmakuOutline(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = context.l10n;
    return Row(
      children: [
        Expanded(
          child: Text(
            localizations.danmakuOutlineEnabledTitle,
            style: theme.textTheme.titleMedium,
          ),
        ),
        Switch(
          value: danmakuOutlineEnabled,
          onChanged: supportsDanmakuOutline
              ? ExternalPlayerConsoleService.setDanmakuOutlineEnabled
              : null,
        ),
      ],
    );
  }

  String _nonEmptyOr(String? value, String fallback) {
    return value == null || value.trim().isEmpty ? fallback : value;
  }
}


/// 显示当前外部播放会话保存的源弹幕
class _DanmakuList extends StatefulWidget {
  const _DanmakuList({
    required this.session,
    required this.items,
    required this.startTimeFor,
    required this.activeIndices,
  });

  final ExternalPlayerSession session;
  final List<DanmakuItem> items;
  final Duration Function(DanmakuItem) startTimeFor;
  final List<int> activeIndices;

  @override
  State<_DanmakuList> createState() => _DanmakuListState();
}

class _DanmakuListState extends State<_DanmakuList> {
  final ScrollController _scrollController = ScrollController();
  bool _followPlayback = true;
  bool _programmaticScroll = false;
  int _scrollGeneration = 0;
  int? _lastFirstActiveIndex;
  int? _pendingScrollIndex;
  double _itemExtent = 64;

  @override
  void initState() {
    super.initState();
    _lastFirstActiveIndex = _firstActiveIndex;
    if (_lastFirstActiveIndex != null) {
      _scheduleScrollTo(_lastFirstActiveIndex!);
    }
  }

  @override
  void didUpdateWidget(_DanmakuList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _followPlayback = true;
      _lastFirstActiveIndex = null;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    }

    final firstActiveIndex = _firstActiveIndex;
    if (firstActiveIndex == _lastFirstActiveIndex) return;
    _lastFirstActiveIndex = firstActiveIndex;
    if (_followPlayback && firstActiveIndex != null) {
      _scheduleScrollTo(firstActiveIndex);
    }
  }

  int? get _firstActiveIndex {
    return widget.activeIndices.isEmpty ? null : widget.activeIndices.first;
  }

  void _scheduleScrollTo(int index) {
    _pendingScrollIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_followPlayback || !_scrollController.hasClients) return;
      final pendingIndex = _pendingScrollIndex;
      _pendingScrollIndex = null;
      if (pendingIndex == null) return;

      final target = (pendingIndex * _itemExtent)
          .clamp(0.0, _scrollController.position.maxScrollExtent)
          .toDouble();
      final generation = ++_scrollGeneration;
      _programmaticScroll = true;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ).whenComplete(() {
        if (mounted && generation == _scrollGeneration) {
          _programmaticScroll = false;
        }
      });
    });
  }

  void _toggleFollowPlayback() {
    setState(() => _followPlayback = !_followPlayback);
    if (_followPlayback && _firstActiveIndex != null) {
      _scheduleScrollTo(_firstActiveIndex!);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        !_programmaticScroll &&
        _followPlayback) {
      setState(() => _followPlayback = false);
    }
    return false;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = context.l10n;
    final items = widget.items;
    final activeIndices = widget.activeIndices.toSet();
    final followDescription = _followPlayback
        ? localizations.externalPlayerConsoleDanmakuFollowEnabled
        : localizations.externalPlayerConsoleDanmakuFollowDisabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.view_list_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizations.externalPlayerConsoleDanmakuList,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    localizations.externalPlayerConsoleDanmakuStats(
                      items.length,
                      activeIndices.length,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: followDescription,
              child: IconButton(
                onPressed: items.isEmpty ? null : _toggleFollowPlayback,
                icon: Icon(
                  _followPlayback
                      ? Icons.my_location
                      : Icons.location_disabled_outlined,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              localizations.externalPlayerConsoleDanmakuEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 680;
              _itemExtent = compact ? 106 : 64;
              return Container(
                height: 384,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: Scrollbar(
                    controller: _scrollController,
                    child: ListView.builder(
                      controller: _scrollController,
                      itemExtent: _itemExtent,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        return _DanmakuRow(
                          item: items[index],
                          itemId:
                              '$index-${items[index].danmakuId ?? ''}',
                          startTime: widget.startTimeFor(items[index]),
                          active: activeIndices.contains(index),
                          compact: compact,
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _DanmakuRow extends StatelessWidget {
  const _DanmakuRow({
    required this.item,
    required this.itemId,
    required this.startTime,
    required this.active,
    required this.compact,
  });

  final DanmakuItem item;
  final String itemId;
  final Duration startTime;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = context.l10n;
    final sender = item.senderId ??
        localizations.externalPlayerConsoleDanmakuUnknownSender;
    final type = switch (item.mode) {
      DanmakuMode.scroll ||
      DanmakuMode.reverseScroll ||
      DanmakuMode.advanced =>
        localizations.externalPlayerConsoleDanmakuTypeScroll,
      DanmakuMode.top =>
        localizations.externalPlayerConsoleDanmakuTypeTop,
      DanmakuMode.bottom =>
        localizations.externalPlayerConsoleDanmakuTypeBottom,
    };
    final rgb = item.colorRgb & 0xFFFFFF;
    final colorText = '#${rgb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
    final color = Color(0xFF000000 | rgb);

    return Container(
      key: ValueKey('external-player-danmaku-$itemId'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
            : null,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          left: BorderSide(
            color: active ? theme.colorScheme.primary : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _formatDanmakuTime(startTime),
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      type,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (active) _ActiveDanmakuIndicator(itemId: itemId),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  item.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _DanmakuColor(color: color, label: colorText),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Tooltip(
                        message: sender,
                        child: Text(
                          '${localizations.externalPlayerConsoleDanmakuSender}: $sender',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    _formatDanmakuTime(startTime),
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                SizedBox(
                  width: 112,
                  child: _DanmakuColor(color: color, label: colorText),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    type,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: Tooltip(
                    message: sender,
                    child: Text(
                      sender,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: active
                      ? _ActiveDanmakuIndicator(itemId: itemId)
                      : null,
                ),
              ],
            ),
    );
  }
}

class _DanmakuColor extends StatelessWidget {
  const _DanmakuColor({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline,
              width: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ActiveDanmakuIndicator extends StatelessWidget {
  const _ActiveDanmakuIndicator({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.externalPlayerConsoleDanmakuActive,
      child: Icon(
        Icons.visibility_rounded,
        key: ValueKey('external-player-danmaku-active-$itemId'),
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

String _formatDanmakuTime(Duration value) {
  final hours = value.inHours.toString().padLeft(2, '0');
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final milliseconds = value.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
  return '$hours:$minutes:$seconds.$milliseconds';
}


/// 显示外部播放器进度的滑块组件
class _SeekProgress extends StatefulWidget {
  const _SeekProgress({required this.session});

  final ExternalPlayerSession session;

  @override
  State<_SeekProgress> createState() => _SeekProgressState();
}

/// 显示外部播放器进度的滑块组件的状态类
class _SeekProgressState extends State<_SeekProgress> {
  double? _dragFraction;

  /// 当 widget 更新时, 如果 session 发生变化, 则重置拖动进度
  @override
  void didUpdateWidget(_SeekProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) _dragFraction = null;
  }

  /// 构建进度滑块组件
  @override
  Widget build(BuildContext context) {
    final theme            = Theme.of(context);
    final localizations    = context.l10n;
    final session          = widget.session;
    final supportsProgress = session.ipcPath != null && session.ipcPath!.isNotEmpty;
    final hasProgress      = session.position != null && session.duration > Duration.zero;
    final canSeek          = supportsProgress && hasProgress;
    final fraction         = (_dragFraction ?? session.fraction ?? 0.0).clamp(0.0, 1.0).toDouble();
    final displayPosition  = _dragFraction == null || !hasProgress
        ? session.position
        : Duration(milliseconds: (session.duration.inMilliseconds * fraction).round());
    final progressText = !supportsProgress
        ? localizations.externalPlayerConsoleProgressUnsupported
        : !hasProgress
            ? localizations.externalPlayerConsoleProgressLoading
            : '${_formatDuration(displayPosition!)} / ${_formatDuration(session.duration)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Slider(
          value: fraction,
          min: 0,
          max: 1,
          label: hasProgress ? _formatDuration(displayPosition!) : null,
          onChangeStart: canSeek
              ? (value) => setState(() => _dragFraction = value)
              : null,
          onChanged: canSeek
              ? (value) => setState(() => _dragFraction = value)
              : null,
          onChangeEnd: canSeek
              ? (value) {
                  ExternalPlayerConsoleService.seekToFraction(value);
                  setState(() => _dragFraction = null);
                }
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          progressText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 将给定的 Duration 转换为格式化的字符串 (HH:MM:SS 或 MM:SS)
  static String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
