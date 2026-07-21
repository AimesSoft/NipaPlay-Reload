
// lib/pages/external_player_console_page.dart
// 掌管 Linux 平台下外部播放器会话的控制台页面


import 'package:flutter/material.dart';
import 'package:nipaplay/constants/danmaku/mode.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/models/danmaku/blocked_item.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/services/external_player_console_service.dart';


/// 一个用于显示外部播放器会话信息的控制台页面
class ExternalPlayerConsolePage extends StatelessWidget {
  const ExternalPlayerConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ExternalPlayerConsoleService.instance,
      builder: (context, _) {
        return SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: !ExternalPlayerConsoleService.hasActiveSession
                    ? const _EmptyConsole()
                    : _ConsoleCard(
                        processId: ExternalPlayerConsoleService.processId,
                        mediaPath: ExternalPlayerConsoleService.mediaPath,
                        animeTitle: ExternalPlayerConsoleService.animeTitle,
                        episodeTitle: ExternalPlayerConsoleService.episodeTitle,
                        episodeId: ExternalPlayerConsoleService.episodeId,
                        danmakuList: ExternalPlayerConsoleService.displayDanmakuList,
                        isPaused: ExternalPlayerConsoleService.isPaused ?? false,
                        supportsSessionControl: ExternalPlayerConsoleService.ipcPath != null,
                        position: ExternalPlayerConsoleService.position,
                        duration: ExternalPlayerConsoleService.duration,
                        fraction: ExternalPlayerConsoleService.fraction,
                        danmakuStyle: ExternalPlayerConsoleService.danmakuStyle,
                        blockedItems: ExternalPlayerConsoleService.blockedItems,
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
    required this.processId,
    required this.mediaPath,
    required this.animeTitle,
    required this.episodeTitle,
    required this.episodeId,
    required this.danmakuList,
    required this.isPaused,
    required this.supportsSessionControl,
    required this.position,
    required this.duration,
    required this.fraction,
    required this.danmakuStyle,
    required this.blockedItems,
  });

  final int? processId;
  final String? mediaPath;
  final String? animeTitle;
  final String? episodeTitle;
  final int? episodeId;
  final List<DisplayDanmakuItem> danmakuList;
  final bool isPaused;
  final bool supportsSessionControl;
  final Duration? position;
  final Duration duration;
  final double? fraction;
  final DanmakuStyle danmakuStyle;
  final List<BlockedDanmakuItem> blockedItems;

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
              processId?.toString() ?? '-',
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
            _buildDanmakuFontSize(context),
            const SizedBox(height: 8),
            _buildDanmakuOutlineWidth(context),
            const SizedBox(height: 8),
            _DanmakuOffsetControl(
              sessionId: processId,
              offset: danmakuStyle.danmakuOffset,
              initialOffset: 0.0,
            ),
            const SizedBox(height: 8),
            _DanmakuBlockRuleEditor(
              enabled: danmakuList.isNotEmpty,
              items: blockedItems,
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: !supportsSessionControl
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
              sessionId: processId,
              items: danmakuList,
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
        _SeekProgress(
          sessionId: processId,
          supportsProgress: supportsSessionControl,
          position: position,
          duration: duration,
          fraction: fraction,
        ),
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
              '${(danmakuStyle.opacity * 100).round()}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Slider(
          value: danmakuStyle.opacity,
          min: 0,
          max: 1,
          divisions: 100,
          label: '${(danmakuStyle.opacity * 100).round()}%',
          onChanged: (value) {
            danmakuStyle.opacity = value;
            ExternalPlayerConsoleService.queueDanmakuRefresh();
          },
        ),
      ],
    );
  }

  Widget _buildDanmakuOutlineWidth(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizations.danmakuOutlineWidthTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text(
              danmakuStyle.outlineWidth.toStringAsFixed(1),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Slider(
          value: danmakuStyle.outlineWidth.clamp(
            0.0,
            DanmakuStyle.maxOutlineWidth,
          ).toDouble(),
          min: 0.0,
          max: DanmakuStyle.maxOutlineWidth,
          divisions: 10,
          label: danmakuStyle.outlineWidth.toStringAsFixed(1),
          onChanged: (value) {
            danmakuStyle.outlineWidth = value;
            ExternalPlayerConsoleService.queueDanmakuRefresh();
          },
        ),
      ],
    );
  }

  Widget _buildDanmakuFontSize(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizations.danmakuFontSizeTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text(
              '${danmakuStyle.danmakuFontSize.toStringAsFixed(1)}px',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Slider(
          key: const Key('external-player-danmaku-font-size'),
          value: danmakuStyle.danmakuFontSize.clamp(
            DanmakuStyle.minDanmakuFontSize,
            DanmakuStyle.maxDanmakuFontSize,
          ).toDouble(),
          min: DanmakuStyle.minDanmakuFontSize,
          max: DanmakuStyle.maxDanmakuFontSize,
          divisions: 96,
          label: '${danmakuStyle.danmakuFontSize.toStringAsFixed(1)}px',
          onChanged: (value) {
            danmakuStyle.danmakuFontSize = value;
            ExternalPlayerConsoleService.queueDanmakuRefresh();
          },
        ),
      ],
    );
  }

  String _nonEmptyOr(String? value, String fallback) {
    return value == null || value.trim().isEmpty ? fallback : value;
  }
}

class _DanmakuOffsetControl extends StatefulWidget {
  const _DanmakuOffsetControl({
    required this.sessionId,
    required this.offset,
    required this.initialOffset,
  });

  final int? sessionId;
  final double offset;
  final double initialOffset;

  @override
  State<_DanmakuOffsetControl> createState() => _DanmakuOffsetControlState();
}

class _DanmakuOffsetControlState extends State<_DanmakuOffsetControl> {
  static const double _stepSeconds = 0.5;
  late final TextEditingController _controller;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatSeconds(widget.offset));
  }

  @override
  void didUpdateWidget(_DanmakuOffsetControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId || oldWidget.offset != widget.offset) {
      _controller.text = _formatSeconds(widget.offset);
      _invalid = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyCustomOffset() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || !value.isFinite) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    ExternalPlayerConsoleService.setDanmakuOffset(value);
  }

  String _currentOffsetText(BuildContext context) {
    final localizations = context.l10n;
    final seconds = _formatSeconds(widget.offset.abs());
    if (widget.offset < 0) {
      return localizations.externalPlayerConsoleDanmakuOffsetCurrentAdvance(seconds);
    }
    if (widget.offset > 0) {
      return localizations.externalPlayerConsoleDanmakuOffsetCurrentDelay(seconds);
    }
    return localizations.externalPlayerConsoleDanmakuOffsetCurrentNone;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = context.l10n;
    final step = _formatSeconds(_stepSeconds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.externalPlayerConsoleDanmakuOffsetTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          _currentOffsetText(context),
          key: const Key('external-player-danmaku-offset-current'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('external-player-danmaku-offset-advance'),
              onPressed: () => ExternalPlayerConsoleService.adjustDanmakuOffset(-_stepSeconds),
              icon: const Icon(Icons.fast_rewind),
              label: Text(localizations.externalPlayerConsoleDanmakuOffsetAdvance(step)),
            ),
            OutlinedButton.icon(
              key: const Key('external-player-danmaku-offset-delay'),
              onPressed: () => ExternalPlayerConsoleService.adjustDanmakuOffset(_stepSeconds),
              icon: const Icon(Icons.fast_forward),
              label: Text(localizations.externalPlayerConsoleDanmakuOffsetDelay(step)),
            ),
            TextButton(
              key: const Key('external-player-danmaku-offset-reset'),
              onPressed: widget.offset == widget.initialOffset
                  ? null
                  : ExternalPlayerConsoleService.resetDanmakuOffset,
              child: Text(localizations.externalPlayerConsoleDanmakuOffsetReset),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                key: const Key('external-player-danmaku-offset-input'),
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: localizations.externalPlayerConsoleDanmakuOffsetCustomLabel,
                  hintText: localizations.externalPlayerConsoleDanmakuOffsetCustomHint,
                  errorText: _invalid
                      ? localizations.externalPlayerConsoleDanmakuOffsetInvalid
                      : null,
                ),
                onSubmitted: (_) => _applyCustomOffset(),
              ),
            ),
            FilledButton.tonal(
              key: const Key('external-player-danmaku-offset-apply'),
              onPressed: _applyCustomOffset,
              child: Text(localizations.externalPlayerConsoleDanmakuOffsetApply),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatSeconds(double value) {
  final text = value.toStringAsFixed(3);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

class _DanmakuBlockRuleEditor extends StatefulWidget {
  const _DanmakuBlockRuleEditor({
    required this.enabled,
    required this.items,
  });

  final bool enabled;
  final List<BlockedDanmakuItem> items;

  @override
  State<_DanmakuBlockRuleEditor> createState() =>
      _DanmakuBlockRuleEditorState();
}

class _DanmakuBlockRuleEditorState extends State<_DanmakuBlockRuleEditor> {
  final TextEditingController _controller = TextEditingController();
  BlockedItemType _selectedType = BlockedItemType.keyword;
  bool _hasInputError = false;

  void _addItem() {
    final value = _controller.text.trim();
    var valid = value.isNotEmpty;
    if (valid && _selectedType == BlockedItemType.regex) {
      try {
        RegExp(value);
      } on FormatException {
        valid = false;
      }
    }
    final added = valid && ExternalPlayerConsoleService.addBlockedItem(
      value,
      _selectedType,
    );
    setState(() => _hasInputError = !added);
    if (added) {
      _controller.clear();
    }
  }

  String _typeLabel(BuildContext context, BlockedItemType type) {
    final localizations = context.l10n;
    return switch (type) {
      BlockedItemType.keyword =>
        localizations.externalPlayerConsoleDanmakuBlockModeKeyword,
      BlockedItemType.regex =>
        localizations.externalPlayerConsoleDanmakuBlockModeRegex,
      BlockedItemType.userId =>
        localizations.externalPlayerConsoleDanmakuBlockModeSender,
    };
  }

  IconData _typeIcon(BlockedItemType type) {
    return switch (type) {
      BlockedItemType.keyword => Icons.text_fields_rounded,
      BlockedItemType.regex => Icons.data_object_rounded,
      BlockedItemType.userId => Icons.person_outline_rounded,
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.externalPlayerConsoleDanmakuKeywordFilter,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<BlockedItemType>(
            key: const Key('external-player-danmaku-block-mode'),
            segments: BlockedItemType.values.map((type) {
              return ButtonSegment<BlockedItemType>(
                value: type,
                icon: Icon(_typeIcon(type)),
                label: Text(_typeLabel(context, type)),
              );
            }).toList(growable: false),
            selected: {_selectedType},
            showSelectedIcon: false,
            onSelectionChanged: widget.enabled
                ? (selection) {
                    setState(() {
                      _selectedType = selection.single;
                      _hasInputError = false;
                    });
                  }
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('external-player-danmaku-keyword-input'),
                controller: _controller,
                enabled: widget.enabled,
                decoration: InputDecoration(
                  hintText: localizations
                      .externalPlayerConsoleDanmakuKeywordHint,
                  errorText: _hasInputError
                      ? localizations.externalPlayerConsoleDanmakuBlockInvalid
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_hasInputError) {
                    setState(() => _hasInputError = false);
                  }
                },
                onSubmitted: (_) => _addItem(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              key: const Key('external-player-danmaku-keyword-add'),
              onPressed: widget.enabled ? _addItem : null,
              icon: const Icon(Icons.add),
              label: Text(
                localizations.externalPlayerConsoleDanmakuKeywordAdd,
              ),
            ),
          ],
        ),
        if (widget.items.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: List.generate(widget.items.length, (index) {
                final item = widget.items[index];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      key: ValueKey(
                        'external-player-danmaku-block-item-${item.type.name}-${item.value}',
                      ),
                      dense: true,
                      leading: Icon(_typeIcon(item.type)),
                      title: Text(item.value),
                      subtitle: Text(_typeLabel(context, item.type)),
                      trailing: IconButton(
                        tooltip: localizations
                            .externalPlayerConsoleDanmakuBlockRemove,
                        onPressed: () =>
                            ExternalPlayerConsoleService.removeBlockedItem(item),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                    if (index < widget.items.length - 1)
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ],
    );
  }
}


/// 显示当前外部播放会话构建的弹幕展示列表
class _DanmakuList extends StatefulWidget {
  const _DanmakuList({
    required this.sessionId,
    required this.items,
  });

  final int? sessionId;
  final List<DisplayDanmakuItem> items;

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
    if (oldWidget.sessionId != widget.sessionId) {
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
    final index = widget.items.indexWhere((item) => item.isActive);
    return index < 0 ? null : index;
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
    final activeCount = items.where((item) => item.isActive).length;
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
                      activeCount,
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
                        final displayItem = items[index];
                        final item = displayItem.item;
                        return _DanmakuRow(
                          item: item,
                          itemId:
                              '${displayItem.index}-${item.danmakuId ?? ''}',
                          startTime: displayItem.startTime,
                          active: displayItem.isActive,
                          blocked: displayItem.isBlocked,
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
    required this.blocked,
    required this.compact,
  });

  final DanmakuItem item;
  final String itemId;
  final Duration startTime;
  final bool active;
  final bool blocked;
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
            : blocked
                ? theme.colorScheme.surfaceContainerHighest
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
                    if (blocked) _BlockedDanmakuIndicator(itemId: itemId),
                    if (blocked && active) const SizedBox(width: 6),
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
                  width: 64,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (blocked) _BlockedDanmakuIndicator(itemId: itemId),
                      if (blocked && active) const SizedBox(width: 6),
                      if (active) _ActiveDanmakuIndicator(itemId: itemId),
                    ],
                  ),
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
        Icons.motion_photos_on_rounded,
        key: ValueKey('external-player-danmaku-active-$itemId'),
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _BlockedDanmakuIndicator extends StatelessWidget {
  const _BlockedDanmakuIndicator({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.externalPlayerConsoleDanmakuBlocked,
      child: Icon(
        Icons.block_rounded,
        key: ValueKey('external-player-danmaku-blocked-$itemId'),
        size: 18,
        color: Theme.of(context).colorScheme.error,
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
  const _SeekProgress({
    required this.sessionId,
    required this.supportsProgress,
    required this.position,
    required this.duration,
    required this.fraction,
  });

  final int? sessionId;
  final bool supportsProgress;
  final Duration? position;
  final Duration duration;
  final double? fraction;

  @override
  State<_SeekProgress> createState() => _SeekProgressState();
}

/// 显示外部播放器进度的滑块组件的状态类
class _SeekProgressState extends State<_SeekProgress> {
  double? _dragFraction;
  final TextEditingController _timestampController = TextEditingController();
  bool _timestampInvalid = false;

  @override
  void dispose() {
    _timestampController.dispose();
    super.dispose();
  }

  /// 当 widget 更新时, 如果 session 发生变化, 则重置拖动进度
  @override
  void didUpdateWidget(_SeekProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _dragFraction = null;
      _timestampController.clear();
      _timestampInvalid = false;
    }
  }

  /// 构建进度滑块组件
  @override
  Widget build(BuildContext context) {
    final theme            = Theme.of(context);
    final localizations    = context.l10n;
    final supportsProgress = widget.supportsProgress;
    final hasProgress      = widget.position != null && widget.duration > Duration.zero;
    final canSeek          = supportsProgress && hasProgress;
    final fraction         = (_dragFraction ?? widget.fraction ?? 0.0).clamp(0.0, 1.0).toDouble();
    final displayPosition  = _dragFraction == null || !hasProgress
        ? widget.position
        : Duration(milliseconds: (widget.duration.inMilliseconds * fraction).round());
    final progressText = !supportsProgress
        ? localizations.externalPlayerConsoleProgressUnsupported
        : !hasProgress
            ? localizations.externalPlayerConsoleProgressLoading
            : '${_formatDuration(displayPosition!)} / ${_formatDuration(widget.duration)}';

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
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                key: const Key('external-player-timestamp-input'),
                controller: _timestampController,
                enabled: supportsProgress,
                keyboardType: TextInputType.datetime,
                textInputAction: TextInputAction.go,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  labelText: localizations.externalPlayerConsoleTimestampLabel,
                  hintText: localizations.externalPlayerConsoleTimestampHint,
                  errorText: _timestampInvalid
                      ? localizations.externalPlayerConsoleTimestampInvalid
                      : null,
                  prefixIcon: const Icon(Icons.schedule),
                ),
                onChanged: (_) {
                  if (_timestampInvalid) {
                    setState(() => _timestampInvalid = false);
                  }
                },
                onSubmitted: supportsProgress ? (_) => _seekToTimestamp() : null,
              ),
            ),
            FilledButton.tonalIcon(
              key: const Key('external-player-timestamp-seek'),
              onPressed: supportsProgress ? _seekToTimestamp : null,
              icon: const Icon(Icons.my_location),
              label: Text(localizations.externalPlayerConsoleTimestampSeek),
            ),
          ],
        ),
      ],
    );
  }

  void _seekToTimestamp() {
    final succeeded = ExternalPlayerConsoleService.seekToTimestamp(
      _timestampController.text,
    );
    setState(() => _timestampInvalid = !succeeded);
    if (succeeded) FocusScope.of(context).unfocus();
  }

  /// 将给定的 Duration 转换为格式化的字符串 (HH:MM:SS 或 MM:SS)
  static String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
