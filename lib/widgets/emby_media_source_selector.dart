import 'package:flutter/material.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/services/emby_media_selection_controller.dart';
import 'package:nipaplay/themes/cupertino/widgets/emby_media_selection_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/emby_media_selection_dialog.dart';
import 'package:nipaplay/utils/media_path_name.dart';

/// Returns whether an episode should expose the independent media selector.
bool shouldShowEmbyMediaSelectionEntry({
  required bool isEmby,
  required bool isWindows,
  required bool isIOS,
  required bool isLargeScreen,
}) =>
    isEmby && (isWindows || isIOS) && !isLargeScreen;

/// Presents the media selector with the requested visual container.
Future<bool?> showEmbyMediaSelection({
  required BuildContext context,
  required bool useCupertino,
  required EmbyMediaSelectionController controller,
}) {
  Widget buildPanel(
    ValueChanged<bool> close, {
    required bool showTitle,
  }) =>
      EmbyMediaSelectionPanel(
        controller: controller,
        onClose: close,
        showTitle: showTitle,
      );

  if (useCupertino) {
    return showEmbyMediaSelectionSheet(
      context: context,
      isSaving: () => controller.state.isSaving,
      onDismiss: controller.cancel,
      contentBuilder: (close) => buildPanel(close, showTitle: false),
    );
  }
  return showEmbyMediaSelectionDialog(
    context: context,
    isSaving: () => controller.state.isSaving,
    onDismiss: controller.cancel,
    contentBuilder: (close) => buildPanel(close, showTitle: true),
  );
}

/// Updates the remembered label only after the selection was persisted.
void updateEmbySavedSourceLabelAfterSelection(
  bool? result,
  EmbyMediaSelectionController controller,
  ValueChanged<String> onUpdate,
) {
  if (result != true) return;
  final selectedId = controller.state.selectedSourceId;
  for (final source in controller.state.sources) {
    if (source.source.id == selectedId) {
      onUpdate(source.displayName);
      return;
    }
  }
}

/// Compact episode action that opens media source and track preferences.
class EmbyMediaSelectionEntry extends StatelessWidget {
  const EmbyMediaSelectionEntry({
    super.key,
    required this.onOpen,
    this.savedSourceLabel,
  });

  final VoidCallback onOpen;
  final String? savedSourceLabel;

  @override
  Widget build(BuildContext context) {
    final label = savedSourceLabel?.trim();
    return TextButton(
      onPressed: onOpen,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text('版本与轨道'),
          if (label != null && label.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Shared progressive-disclosure content for media source and track choices.
class EmbyMediaSelectionPanel extends StatefulWidget {
  const EmbyMediaSelectionPanel({
    super.key,
    required this.controller,
    required this.onClose,
    this.showTitle = true,
  });

  final EmbyMediaSelectionController controller;
  final ValueChanged<bool> onClose;
  final bool showTitle;

  @override
  State<EmbyMediaSelectionPanel> createState() =>
      _EmbyMediaSelectionPanelState();
}

class _EmbyMediaSelectionPanelState extends State<EmbyMediaSelectionPanel> {
  int _tabIndex = 0;
  Object? _localError;

  Future<void> _apply() async {
    setState(() => _localError = null);
    try {
      final saved = await widget.controller.apply();
      if (!mounted) return;
      if (saved) {
        widget.onClose(true);
      } else {
        setState(() {
          _localError =
              widget.controller.state.error ?? StateError('无法保存 Emby 媒体偏好');
        });
      }
    } catch (error) {
      if (mounted) setState(() => _localError = error);
    }
  }

  void _cancel() {
    widget.controller.cancel();
    widget.onClose(false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showTitle)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Text(
                  '版本与轨道',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            Expanded(child: _buildBody(context, state)),
            _buildActions(context, state),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, EmbyMediaSelectionState state) {
    if (state.isLoading && state.sources.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载版本信息…'),
          ],
        ),
      );
    }

    final effectiveError = _localError ?? state.error;
    if (state.sources.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 36),
              const SizedBox(height: 12),
              Text(
                effectiveError?.toString() ?? '没有可用的媒体版本',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => widget.controller.load(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final selected = _selectedSource(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (effectiveError != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              effectiveError.toString(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 720) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 300,
                      child: _buildSourceList(state),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildDetails(state, selected)),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  _buildSourceList(state, shrinkWrap: true),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 360,
                    child: _buildDetails(state, selected),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSourceList(
    EmbyMediaSelectionState state, {
    bool shrinkWrap = false,
  }) {
    final list = ListView.separated(
      padding: const EdgeInsets.all(12),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: state.sources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final source = state.sources[index];
        final selected = source.source.id == state.selectedSourceId;
        return Material(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: state.isSaving
                ? null
                : () {
                    setState(() => _localError = null);
                    widget.controller.selectSource(source.source.id);
                  },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (source.summary.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            source.summary,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return shrinkWrap ? list : Scrollbar(child: list);
  }

  Widget _buildDetails(
    EmbyMediaSelectionState state,
    EmbyMediaSourceDescriptor? source,
  ) {
    if (source == null) {
      return const Center(child: Text('请选择一个媒体版本'));
    }
    const tabs = ['概览', '音轨', '字幕'];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (var index = 0; index < tabs.length; index++)
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => _tabIndex = index),
                    style: TextButton.styleFrom(
                      foregroundColor: _tabIndex == index
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    child: Text(tabs[index]),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: [
              _overview(source),
              _audioTracks(state, source),
              _subtitleTracks(state, source),
            ],
          ),
        ),
      ],
    );
  }

  Widget _overview(EmbyMediaSourceDescriptor source) {
    final video = source.videoTracks.firstOrNull;
    final details = <String>[
      if (video?.width != null && video?.height != null)
        '${video!.width} × ${video.height}',
      if (video?.codec != null) video!.codec!.toUpperCase(),
      if (video?.profile != null) video!.profile!,
      if (video?.frameRate != null)
        '${video!.frameRate!.toStringAsFixed(2)} fps',
      if (video?.bitDepth != null) '${video!.bitDepth} bit',
      if (video?.hdr != null) video!.hdr!,
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (details.isNotEmpty) ...[
          Text('视频', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(details.join(' · ')),
        ],
      ],
    );
  }

  Widget _audioTracks(
    EmbyMediaSelectionState state,
    EmbyMediaSourceDescriptor source,
  ) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _trackChoice(
          label: '跟随该版本默认',
          selected: state.audio.mode == EmbyTrackPreferenceMode.followDefault,
          enabled: !state.isSaving,
          onTap: () => widget.controller
              .selectAudio(const EmbyTrackPreference.followDefault()),
        ),
        for (final track in source.audioTracks)
          _trackChoice(
            label: _audioLabel(track),
            selected: _matchesTrack(
                state.audio, source.source.id, track.index, track.fingerprint),
            enabled: !state.isSaving,
            onTap: () => widget.controller.selectAudio(
              EmbyTrackPreference.track(
                track.fingerprint,
                sourceIndex: track.index,
                mediaSourceId: source.source.id,
              ),
            ),
          ),
      ],
    );
  }

  Widget _subtitleTracks(
    EmbyMediaSelectionState state,
    EmbyMediaSourceDescriptor source,
  ) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _trackChoice(
          label: '跟随该版本默认',
          selected:
              state.subtitle.mode == EmbyTrackPreferenceMode.followDefault,
          enabled: !state.isSaving,
          onTap: () => widget.controller
              .selectSubtitle(const EmbyTrackPreference.followDefault()),
        ),
        _trackChoice(
          label: '关闭字幕',
          selected: state.subtitle.mode == EmbyTrackPreferenceMode.disabled,
          enabled: !state.isSaving,
          onTap: () => widget.controller
              .selectSubtitle(const EmbyTrackPreference.disabled()),
        ),
        for (final track in source.subtitleTracks)
          _trackChoice(
            label: _subtitleLabel(track),
            selected: _matchesTrack(state.subtitle, source.source.id,
                track.index, track.fingerprint),
            enabled: !state.isSaving,
            onTap: () => widget.controller.selectSubtitle(
              EmbyTrackPreference.track(
                track.fingerprint,
                sourceIndex: track.index,
                mediaSourceId: source.source.id,
              ),
            ),
          ),
      ],
    );
  }

  Widget _trackChoice({
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      enabled: enabled,
      selected: selected,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 20,
      ),
      title: Text(label),
      onTap: () {
        setState(() => _localError = null);
        onTap();
      },
    );
  }

  Widget _buildActions(BuildContext context, EmbyMediaSelectionState state) {
    return Container(
      key: const ValueKey<String>('emby-media-selection-actions'),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: state.isSaving ? null : _cancel,
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: state.isSaving ? null : _apply,
            child: state.isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('应用'),
          ),
        ],
      ),
    );
  }

  EmbyMediaSourceDescriptor? _selectedSource(EmbyMediaSelectionState state) {
    for (final source in state.sources) {
      if (source.source.id == state.selectedSourceId) return source;
    }
    return state.sources.firstOrNull;
  }

  bool _matchesTrack(
    EmbyTrackPreference preference,
    String mediaSourceId,
    int index,
    EmbyTrackFingerprint fingerprint,
  ) {
    if (preference.mode != EmbyTrackPreferenceMode.track) return false;
    if (preference.mediaSourceId == mediaSourceId &&
        preference.sourceIndex == index) {
      return true;
    }
    return preference.fingerprint == fingerprint;
  }

  String _audioLabel(EmbyAudioTrackDescriptor track) {
    final parts = <String>[
      if (track.language?.trim().isNotEmpty == true) track.language!.trim(),
      if (track.title?.trim().isNotEmpty == true) track.title!.trim(),
      if (track.codec?.trim().isNotEmpty == true) track.codec!.trim(),
      if (track.channels != null) _channelLabel(track.channels!),
    ];
    return parts.isEmpty ? '音轨 ${track.index}' : parts.join(' · ');
  }

  String _subtitleLabel(EmbySubtitleTrackDescriptor track) {
    final parts = <String>[
      if (track.language?.trim().isNotEmpty == true) track.language!.trim(),
      if (track.title?.trim().isNotEmpty == true) track.title!.trim(),
      if (track.codec?.trim().isNotEmpty == true) track.codec!.trim(),
      if (track.isExternal) '外挂',
      if (track.isForced) '强制',
    ];
    return parts.isEmpty ? '字幕 ${track.index}' : parts.join(' · ');
  }

  String _channelLabel(int channels) {
    if (channels == 1) return '1.0ch';
    if (channels == 2) return '2.0ch';
    if (channels == 6) return '5.1ch';
    if (channels == 8) return '7.1ch';
    return '${channels}ch';
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String embyMediaSourceLabel(
  PlaybackMediaSource source, {
  required int index,
}) {
  final path = source.path?.trim();
  if (path != null && path.isNotEmpty) {
    final name = mediaPathName(path);
    if (name.isNotEmpty) return name;
  }

  final container = source.container?.trim().toUpperCase();
  return [
    '版本 ${index + 1}',
    if (container != null && container.isNotEmpty) container,
  ].join(' · ');
}

class EmbyMediaSourceSelector extends StatelessWidget {
  const EmbyMediaSourceSelector({
    super.key,
    required this.sources,
    required this.selectedSourceId,
    required this.onSelected,
  });

  final List<PlaybackMediaSource> sources;
  final String? selectedSourceId;
  final ValueChanged<PlaybackMediaSource> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < sources.length; index++)
          Padding(
            padding:
                EdgeInsets.only(bottom: index == sources.length - 1 ? 0 : 8),
            child: Semantics(
              selected: sources[index].id == selectedSourceId,
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelected(sources[index]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          sources[index].id == selectedSourceId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: sources[index].id == selectedSourceId
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            embyMediaSourceLabel(sources[index], index: index),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
