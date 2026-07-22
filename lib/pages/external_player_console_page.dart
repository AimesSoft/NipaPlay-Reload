import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:nipaplay/constants/danmaku/mode.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/models/danmaku/blocked_item.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_editable_slider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_page_scaffold.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

/// mpv 外部播放会话的桌面控制台。
class ExternalPlayerConsolePage extends StatelessWidget {
  const ExternalPlayerConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ExternalPlayerConsoleService.instance,
      builder: (context, _) {
        final hasSession = ExternalPlayerConsoleService.hasActiveSession;
        final animeTitle = ExternalPlayerConsoleService.animeTitle;
        final episodeTitle = ExternalPlayerConsoleService.episodeTitle;
        final subtitle = <String>[
          if (animeTitle != null && animeTitle.trim().isNotEmpty) animeTitle,
          if (episodeTitle != null && episodeTitle.trim().isNotEmpty)
            episodeTitle,
        ].join(' · ');

        return fluent.FluentTheme(
          data: fluent.FluentThemeData(
            brightness: Theme.of(context).brightness,
            accentColor: fluent.AccentColor.swatch({
              'normal': AppAccentColors.current,
              'default': AppAccentColors.current,
            }),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: NipaplayLargeScreenPageScaffold(
                title: context.l10n.externalPlayerConsoleTitle,
                subtitle: hasSession && subtitle.isNotEmpty ? subtitle : null,
                padding: const EdgeInsets.fromLTRB(34, 24, 34, 28),
                headerBottomSpacing: 18,
                showBackgroundEffects: false,
                child: hasSession
                    ? _ConsoleWorkspace(
                        processId: ExternalPlayerConsoleService.processId,
                        mediaPath: ExternalPlayerConsoleService.mediaPath,
                        animeTitle: animeTitle,
                        episodeTitle: episodeTitle,
                        episodeId: ExternalPlayerConsoleService.episodeId,
                        danmakuList:
                            ExternalPlayerConsoleService.displayDanmakuList,
                        isPaused:
                            ExternalPlayerConsoleService.isPaused ?? false,
                        supportsSessionControl:
                            ExternalPlayerConsoleService.ipcPath != null,
                        position: ExternalPlayerConsoleService.position,
                        duration: ExternalPlayerConsoleService.duration,
                        fraction: ExternalPlayerConsoleService.fraction,
                        danmakuStyle: ExternalPlayerConsoleService.danmakuStyle,
                        blockedItems: ExternalPlayerConsoleService.blockedItems,
                      )
                    : NipaplayLargeScreenEmptyState(
                        icon: Icons.subtitles_outlined,
                        title: context.l10n.externalPlayerConsoleEmptyTitle,
                        subtitle:
                            context.l10n.externalPlayerConsoleEmptyDescription,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConsoleWorkspace extends StatelessWidget {
  const _ConsoleWorkspace({
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 980;
        final controlPanels = <Widget>[
          _buildSessionPanel(context),
          const SizedBox(height: 14),
          _buildAppearancePanel(context),
          const SizedBox(height: 14),
          _buildRulesPanel(context),
        ];
        final listPanel = NipaplayLargeScreenPanel(
          padding: const EdgeInsets.all(16),
          child: _DanmakuList(
            sessionId: processId,
            items: danmakuList,
            fillAvailableHeight: useTwoColumns,
          ),
        );

        if (!useTwoColumns) {
          return SingleChildScrollView(
            key: const Key('external-player-console-single-column'),
            padding: const EdgeInsets.only(right: 4),
            child: Column(
              children: [
                ...controlPanels,
                const SizedBox(height: 14),
                listPanel,
              ],
            ),
          );
        }

        return Row(
          key: const Key('external-player-console-two-column'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 9,
              child: ListView(
                padding: const EdgeInsets.only(right: 4),
                children: controlPanels,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(flex: 11, child: listPanel),
          ],
        );
      },
    );
  }

  Widget _buildSessionPanel(BuildContext context) {
    final localizations = context.l10n;
    return NipaplayLargeScreenPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NipaplayLargeScreenSectionHeader(
            title: _localized(context, '播放会话', '播放工作階段', 'Playback Session'),
            subtitle: _localized(
              context,
              'mpv 播放状态与精确定位',
              'mpv 播放狀態與精確定位',
              'mpv status and precise seeking',
            ),
          ),
          const SizedBox(height: 16),
          _DetailRow(
            label: localizations.externalPlayerConsoleAnime,
            value: _nonEmptyOr(
              animeTitle,
              localizations.externalPlayerConsoleUnknownAnime,
            ),
          ),
          _DetailRow(
            label: localizations.externalPlayerConsoleEpisode,
            value: _nonEmptyOr(
              episodeTitle,
              localizations.externalPlayerConsoleUnknownEpisode,
            ),
          ),
          _DetailRow(
            label: localizations.externalPlayerConsoleEpisodeId,
            value: episodeId?.toString() ?? '-',
          ),
          _DetailRow(
            label: localizations.externalPlayerConsoleProcessId,
            value: processId?.toString() ?? '-',
          ),
          _DetailRow(
            label: localizations.externalPlayerConsoleMediaPath,
            value: mediaPath ?? '-',
          ),
          const SizedBox(height: 16),
          Text(
            localizations.externalPlayerConsoleProgress,
            style: _sectionLabelStyle(context),
          ),
          const SizedBox(height: 10),
          _SeekProgress(
            sessionId: processId,
            supportsProgress: supportsSessionControl,
            position: position,
            duration: duration,
            fraction: fraction,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              NipaplayLargeScreenActionButton(
                icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                label: isPaused
                    ? localizations.externalPlayerConsoleResume
                    : localizations.externalPlayerConsolePause,
                onPressed: supportsSessionControl
                    ? ExternalPlayerConsoleService.togglePause
                    : null,
                compact: true,
              ),
              NipaplayLargeScreenActionButton(
                icon: Icons.close_rounded,
                label: localizations.externalPlayerConsoleClose,
                onPressed: ExternalPlayerConsoleService.closePlayerAndConsole,
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppearancePanel(BuildContext context) {
    final localizations = context.l10n;
    return NipaplayLargeScreenPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NipaplayLargeScreenSectionHeader(
            title: _localized(context, '弹幕显示', '彈幕顯示', 'Danmaku Appearance'),
            subtitle: _localized(
              context,
              '修改后会立即重新生成并加载弹幕',
              '修改後會立即重新產生並載入彈幕',
              'Changes are regenerated and loaded immediately',
            ),
          ),
          const SizedBox(height: 16),
          _ConsoleSlider(
            label: localizations.danmakuOpacityTitle,
            valueText: '${(danmakuStyle.opacity * 100).round()}%',
            value: danmakuStyle.opacity,
            min: 0,
            max: 1,
            divisions: 100,
            onChanged: (value) {
              danmakuStyle.opacity = value;
              ExternalPlayerConsoleService.queueDanmakuRefresh();
            },
          ),
          const SizedBox(height: 12),
          _ConsoleSlider(
            sliderKey: const Key('external-player-danmaku-font-size'),
            label: localizations.danmakuFontSizeTitle,
            valueText: '${danmakuStyle.danmakuFontSize.toStringAsFixed(1)}px',
            value: danmakuStyle.danmakuFontSize
                .clamp(
                  DanmakuStyle.minDanmakuFontSize,
                  DanmakuStyle.maxDanmakuFontSize,
                )
                .toDouble(),
            min: DanmakuStyle.minDanmakuFontSize,
            max: DanmakuStyle.maxDanmakuFontSize,
            divisions: 96,
            onChanged: (value) {
              danmakuStyle.danmakuFontSize = value;
              ExternalPlayerConsoleService.queueDanmakuRefresh();
            },
          ),
          const SizedBox(height: 12),
          _ConsoleSlider(
            label: localizations.danmakuOutlineWidthTitle,
            valueText: danmakuStyle.outlineWidth.toStringAsFixed(1),
            value: danmakuStyle.outlineWidth
                .clamp(0.0, DanmakuStyle.maxOutlineWidth)
                .toDouble(),
            min: 0,
            max: DanmakuStyle.maxOutlineWidth,
            divisions: 10,
            onChanged: (value) {
              danmakuStyle.outlineWidth = value;
              ExternalPlayerConsoleService.queueDanmakuRefresh();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRulesPanel(BuildContext context) {
    return NipaplayLargeScreenPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NipaplayLargeScreenSectionHeader(
            title: _localized(context, '同步与过滤', '同步與過濾', 'Sync & Filters'),
            subtitle: _localized(
              context,
              '校正时间偏移并管理当前会话的屏蔽规则',
              '校正時間偏移並管理目前工作階段的封鎖規則',
              'Correct timing and manage filters for this session',
            ),
          ),
          const SizedBox(height: 16),
          _DanmakuOffsetControl(
            sessionId: processId,
            offset: danmakuStyle.danmakuOffset,
            initialOffset: 0,
          ),
          const SizedBox(height: 20),
          _DanmakuBlockRuleEditor(
            enabled: danmakuList.isNotEmpty,
            items: blockedItems,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.58),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 2,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsoleSlider extends StatelessWidget {
  const _ConsoleSlider({
    this.sliderKey,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final Key? sliderKey;
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: _sectionLabelStyle(context))),
            Text(
              valueText,
              style: TextStyle(color: muted, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        NipaplayLargeScreenEditableSlider(
          key: sliderKey,
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueText,
          onChanged: onChanged,
        ),
      ],
    );
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
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.offset != widget.offset) {
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
      return localizations
          .externalPlayerConsoleDanmakuOffsetCurrentAdvance(seconds);
    }
    if (widget.offset > 0) {
      return localizations
          .externalPlayerConsoleDanmakuOffsetCurrentDelay(seconds);
    }
    return localizations.externalPlayerConsoleDanmakuOffsetCurrentNone;
  }

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    final step = _formatSeconds(_stepSeconds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.externalPlayerConsoleDanmakuOffsetTitle,
          style: _sectionLabelStyle(context),
        ),
        const SizedBox(height: 4),
        Text(
          _currentOffsetText(context),
          key: const Key('external-player-danmaku-offset-current'),
          style: _mutedStyle(context),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            KeyedSubtree(
              key: const Key('external-player-danmaku-offset-advance'),
              child: NipaplayLargeScreenActionButton(
                icon: Icons.fast_rewind_rounded,
                label: localizations
                    .externalPlayerConsoleDanmakuOffsetAdvance(step),
                onPressed: () =>
                    ExternalPlayerConsoleService.adjustDanmakuOffset(
                  -_stepSeconds,
                ),
                compact: true,
              ),
            ),
            KeyedSubtree(
              key: const Key('external-player-danmaku-offset-delay'),
              child: NipaplayLargeScreenActionButton(
                icon: Icons.fast_forward_rounded,
                label:
                    localizations.externalPlayerConsoleDanmakuOffsetDelay(step),
                onPressed: () =>
                    ExternalPlayerConsoleService.adjustDanmakuOffset(
                  _stepSeconds,
                ),
                compact: true,
              ),
            ),
            KeyedSubtree(
              key: const Key('external-player-danmaku-offset-reset'),
              child: NipaplayLargeScreenActionButton(
                icon: Icons.restart_alt_rounded,
                label: localizations.externalPlayerConsoleDanmakuOffsetReset,
                onPressed: widget.offset == widget.initialOffset
                    ? null
                    : ExternalPlayerConsoleService.resetDanmakuOffset,
                compact: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeyedSubtree(
              key: const Key('external-player-danmaku-offset-apply'),
              child: NipaplayLargeScreenActionButton(
                icon: Icons.done_rounded,
                label: localizations.externalPlayerConsoleDanmakuOffsetApply,
                onPressed: _applyCustomOffset,
                compact: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ConsoleTextField(
                key: const Key('external-player-danmaku-offset-input'),
                controller: _controller,
                hintText:
                    localizations.externalPlayerConsoleDanmakuOffsetCustomHint,
                prefixIcon: Icons.timelapse_rounded,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                errorText: _invalid
                    ? localizations.externalPlayerConsoleDanmakuOffsetInvalid
                    : null,
                onSubmitted: (_) => _applyCustomOffset(),
              ),
            ),
          ],
        ),
      ],
    );
  }
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
    final added = valid &&
        ExternalPlayerConsoleService.addBlockedItem(value, _selectedType);
    setState(() => _hasInputError = !added);
    if (added) _controller.clear();
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
    final localizations = context.l10n;
    final borderColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.externalPlayerConsoleDanmakuKeywordFilter,
          style: _sectionLabelStyle(context),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          key: const Key('external-player-danmaku-block-mode'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: BlockedItemType.values.map((type) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ChoiceButton(
                  icon: _typeIcon(type),
                  label: _typeLabel(context, type),
                  selected: _selectedType == type,
                  onPressed: widget.enabled
                      ? () => setState(() {
                            _selectedType = type;
                            _hasInputError = false;
                          })
                      : null,
                ),
              );
            }).toList(growable: false),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ConsoleTextField(
                key: const Key('external-player-danmaku-keyword-input'),
                controller: _controller,
                enabled: widget.enabled,
                hintText: localizations.externalPlayerConsoleDanmakuKeywordHint,
                prefixIcon: _typeIcon(_selectedType),
                errorText: _hasInputError
                    ? localizations.externalPlayerConsoleDanmakuBlockInvalid
                    : null,
                onChanged: (_) {
                  if (_hasInputError) {
                    setState(() => _hasInputError = false);
                  }
                },
                onSubmitted: (_) => _addItem(),
              ),
            ),
            const SizedBox(width: 8),
            KeyedSubtree(
              key: const Key('external-player-danmaku-keyword-add'),
              child: NipaplayLargeScreenActionButton(
                icon: Icons.add_rounded,
                label: localizations.externalPlayerConsoleDanmakuKeywordAdd,
                onPressed: widget.enabled ? _addItem : null,
                compact: true,
              ),
            ),
          ],
        ),
        if (widget.items.isNotEmpty) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: borderColor)),
              child: Column(
                children: List.generate(widget.items.length, (index) {
                  final item = widget.items[index];
                  return Container(
                    key: ValueKey(
                      'external-player-danmaku-block-item-${item.type.name}-${item.value}',
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                    decoration: BoxDecoration(
                      border: index == widget.items.length - 1
                          ? null
                          : Border(bottom: BorderSide(color: borderColor)),
                    ),
                    child: Row(
                      children: [
                        Icon(_typeIcon(item.type), size: 19),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _typeLabel(context, item.type),
                                style: _mutedStyle(context),
                              ),
                            ],
                          ),
                        ),
                        NipaplayLargeScreenIconButton(
                          icon: Icons.delete_outline_rounded,
                          tooltip: localizations
                              .externalPlayerConsoleDanmakuBlockRemove,
                          onPressed: () =>
                              ExternalPlayerConsoleService.removeBlockedItem(
                                  item),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DanmakuList extends StatefulWidget {
  const _DanmakuList({
    required this.sessionId,
    required this.items,
    required this.fillAvailableHeight,
  });

  final int? sessionId;
  final List<DisplayDanmakuItem> items;
  final bool fillAvailableHeight;

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
  double _itemExtent = 72;

  int? get _firstActiveIndex {
    final index = widget.items.indexWhere((item) => item.isActive);
    return index < 0 ? null : index;
  }

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
      _scrollController
          .animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      )
          .whenComplete(() {
        if (mounted && generation == _scrollGeneration) {
          _programmaticScroll = false;
        }
      });
    });
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

  void _toggleFollowPlayback() {
    setState(() => _followPlayback = !_followPlayback);
    if (_followPlayback && _firstActiveIndex != null) {
      _scheduleScrollTo(_firstActiveIndex!);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    final activeCount = widget.items.where((item) => item.isActive).length;
    final followDescription = _followPlayback
        ? localizations.externalPlayerConsoleDanmakuFollowEnabled
        : localizations.externalPlayerConsoleDanmakuFollowDisabled;
    final list = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        _itemExtent = compact ? 104 : 72;
        final borderColor =
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.09);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: borderColor)),
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: Scrollbar(
                controller: _scrollController,
                child: ListView.builder(
                  controller: _scrollController,
                  itemExtent: _itemExtent,
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) {
                    final displayItem = widget.items[index];
                    final item = displayItem.item;
                    return _DanmakuRow(
                      item: item,
                      itemId: '${displayItem.index}-${item.danmakuId ?? ''}',
                      startTime: displayItem.startTime,
                      active: displayItem.isActive,
                      blocked: displayItem.isBlocked,
                      compact: compact,
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NipaplayLargeScreenSectionHeader(
          title: localizations.externalPlayerConsoleDanmakuList,
          subtitle: localizations.externalPlayerConsoleDanmakuStats(
            widget.items.length,
            activeCount,
          ),
          trailing: NipaplayLargeScreenIconButton(
            icon: _followPlayback
                ? Icons.my_location_rounded
                : Icons.location_disabled_outlined,
            tooltip: followDescription,
            onPressed: widget.items.isEmpty ? null : _toggleFollowPlayback,
          ),
        ),
        const SizedBox(height: 12),
        if (widget.items.isEmpty && widget.fillAvailableHeight)
          Expanded(
            child: NipaplayLargeScreenEmptyState(
              icon: Icons.speaker_notes_off_outlined,
              title: localizations.externalPlayerConsoleDanmakuEmpty,
              subtitle: _localized(
                context,
                '当前播放会话没有可显示的弹幕。',
                '目前播放工作階段沒有可顯示的彈幕。',
                'There are no danmaku comments for this session.',
              ),
            ),
          )
        else if (widget.items.isEmpty)
          SizedBox(
            height: 430,
            child: NipaplayLargeScreenEmptyState(
              icon: Icons.speaker_notes_off_outlined,
              title: localizations.externalPlayerConsoleDanmakuEmpty,
              subtitle: _localized(
                context,
                '当前播放会话没有可显示的弹幕。',
                '目前播放工作階段沒有可顯示的彈幕。',
                'There are no danmaku comments for this session.',
              ),
            ),
          )
        else if (widget.fillAvailableHeight)
          Expanded(child: list)
        else
          SizedBox(height: 430, child: list),
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
      DanmakuMode.top => localizations.externalPlayerConsoleDanmakuTypeTop,
      DanmakuMode.bottom =>
        localizations.externalPlayerConsoleDanmakuTypeBottom,
    };
    final rgb = item.colorRgb & 0xFFFFFF;
    final colorText = '#${rgb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
    final color = Color(0xFF000000 | rgb);
    final divider = theme.colorScheme.onSurface.withValues(alpha: 0.08);

    return Container(
      key: ValueKey('external-player-danmaku-$itemId'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: active
            ? AppAccentColors.current.withValues(alpha: 0.15)
            : blocked
                ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
                : null,
        border: Border(
          bottom: BorderSide(color: divider),
          left: BorderSide(
            color: active ? AppAccentColors.current : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(_formatDanmakuTime(startTime),
                        style: theme.textTheme.labelMedium),
                    const SizedBox(width: 10),
                    Text(type, style: _mutedStyle(context)),
                    const Spacer(),
                    if (blocked) _BlockedIndicator(itemId: itemId),
                    if (blocked && active) const SizedBox(width: 6),
                    if (active) _ActiveIndicator(itemId: itemId),
                  ],
                ),
                const SizedBox(height: 5),
                Text(item.content,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _DanmakuColor(color: color, label: colorText),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '${localizations.externalPlayerConsoleDanmakuSender}: $sender',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _mutedStyle(context),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(_formatDanmakuTime(startTime),
                      style: theme.textTheme.labelMedium),
                ),
                SizedBox(
                    width: 112,
                    child: _DanmakuColor(color: color, label: colorText)),
                SizedBox(
                    width: 64, child: Text(type, style: _mutedStyle(context))),
                SizedBox(
                  width: 120,
                  child: Text(
                    sender,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mutedStyle(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.content,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                if (blocked) _BlockedIndicator(itemId: itemId),
                if (blocked && active) const SizedBox(width: 6),
                if (active) _ActiveIndicator(itemId: itemId),
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
              color: Theme.of(context).colorScheme.onSurface.withValues(
                    alpha: 0.25,
                  ),
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

class _ActiveIndicator extends StatelessWidget {
  const _ActiveIndicator({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.externalPlayerConsoleDanmakuActive,
      child: Icon(
        Icons.motion_photos_on_rounded,
        key: ValueKey('external-player-danmaku-active-$itemId'),
        size: 18,
        color: AppAccentColors.current,
      ),
    );
  }
}

class _BlockedIndicator extends StatelessWidget {
  const _BlockedIndicator({required this.itemId});

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

class _SeekProgressState extends State<_SeekProgress> {
  double? _dragFraction;
  final TextEditingController _timestampController = TextEditingController();
  bool _timestampInvalid = false;

  @override
  void didUpdateWidget(_SeekProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _dragFraction = null;
      _timestampController.clear();
      _timestampInvalid = false;
    }
  }

  @override
  void dispose() {
    _timestampController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    final hasProgress =
        widget.position != null && widget.duration > Duration.zero;
    final canSeek = widget.supportsProgress && hasProgress;
    final fraction =
        (_dragFraction ?? widget.fraction ?? 0).clamp(0.0, 1.0).toDouble();
    final displayPosition = _dragFraction == null || !hasProgress
        ? widget.position
        : Duration(
            milliseconds: (widget.duration.inMilliseconds * fraction).round(),
          );
    final progressText = !widget.supportsProgress
        ? localizations.externalPlayerConsoleProgressUnsupported
        : !hasProgress
            ? localizations.externalPlayerConsoleProgressLoading
            : '${_formatDuration(displayPosition!)} / ${_formatDuration(widget.duration)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NipaplayLargeScreenEditableSlider(
          value: fraction,
          min: 0,
          max: 1,
          label: hasProgress ? _formatDuration(displayPosition!) : null,
          onChangeStart:
              canSeek ? (value) => setState(() => _dragFraction = value) : null,
          onChanged:
              canSeek ? (value) => setState(() => _dragFraction = value) : null,
          onChangeEnd: canSeek
              ? (value) {
                  ExternalPlayerConsoleService.seekToFraction(value);
                  setState(() => _dragFraction = null);
                }
              : null,
        ),
        const SizedBox(height: 6),
        Text(progressText, style: _mutedStyle(context)),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ConsoleTextField(
                key: const Key('external-player-timestamp-input'),
                controller: _timestampController,
                enabled: widget.supportsProgress,
                hintText: localizations.externalPlayerConsoleTimestampHint,
                prefixIcon: Icons.schedule_rounded,
                keyboardType: TextInputType.datetime,
                errorText: _timestampInvalid
                    ? localizations.externalPlayerConsoleTimestampInvalid
                    : null,
                onChanged: (_) {
                  if (_timestampInvalid) {
                    setState(() => _timestampInvalid = false);
                  }
                },
                onSubmitted:
                    widget.supportsProgress ? (_) => _seekToTimestamp() : null,
              ),
            ),
            const SizedBox(width: 8),
            KeyedSubtree(
              key: const Key('external-player-timestamp-seek'),
              child: NipaplayLargeScreenActionButton(
                icon: Icons.my_location_rounded,
                label: localizations.externalPlayerConsoleTimestampSeek,
                onPressed: widget.supportsProgress ? _seekToTimestamp : null,
                compact: true,
              ),
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

  static String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.current;
    return NipaplayLargeScreenFocusableAction(
      onActivate: onPressed,
      borderRadius: BorderRadius.circular(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      style: NipaplayLargeScreenFocusableStyle(
        idleBackgroundDark: selected
            ? accent.withValues(alpha: 0.24)
            : Colors.white.withValues(alpha: 0.08),
        idleBackgroundLight: selected
            ? accent.withValues(alpha: 0.16)
            : Colors.black.withValues(alpha: 0.04),
        focusStrokeColor: accent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ConsoleTextField extends StatelessWidget {
  const _ConsoleTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.enabled = true,
    this.keyboardType,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final bool enabled;
  final TextInputType? keyboardType;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = Theme.of(context).colorScheme.onSurface;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color.withValues(alpha: 0.10)),
    );
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.075)
            : Colors.white.withValues(alpha: 0.72),
        prefixIcon: Icon(prefixIcon, size: 19),
        hintText: hintText,
        errorText: errorText,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: AppAccentColors.current, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

TextStyle _sectionLabelStyle(BuildContext context) {
  return TextStyle(
    color: Theme.of(context).colorScheme.onSurface,
    fontSize: 15,
    fontWeight: FontWeight.w800,
  );
}

TextStyle _mutedStyle(BuildContext context) {
  return TextStyle(
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.60),
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );
}

String _nonEmptyOr(String? value, String fallback) {
  return value == null || value.trim().isEmpty ? fallback : value;
}

String _formatSeconds(double value) {
  final text = value.toStringAsFixed(3);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _formatDanmakuTime(Duration value) {
  final hours = value.inHours.toString().padLeft(2, '0');
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final milliseconds =
      value.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
  return '$hours:$minutes:$seconds.$milliseconds';
}

String _localized(
  BuildContext context,
  String simplified,
  String traditional,
  String english,
) {
  return switch (context.l10n.localeName) {
    'en' => english,
    'zh_Hant' => traditional,
    _ => simplified,
  };
}
