import 'dart:math' as math;

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/playback/unified_playback_entry_model.dart';

class AdaptivePlaybackEntryView extends material.StatelessWidget {
  const AdaptivePlaybackEntryView({
    super.key,
    required this.content,
    required this.mascotScale,
    required this.onMascotTap,
    required this.onSelectFile,
    required this.onOpenUrlInput,
  });

  final UnifiedPlaybackEntryContent content;
  final material.Animation<double> mascotScale;
  final material.VoidCallback onMascotTap;
  final material.VoidCallback onSelectFile;
  final material.VoidCallback onOpenUrlInput;

  @override
  material.Widget build(material.BuildContext context) {
    final surface = AppDisplaySurfaceScope.of(context);
    final shared = _PlaybackEntryRendererData(
      content: content,
      mascotScale: mascotScale,
      onMascotTap: onMascotTap,
      onSelectFile: onSelectFile,
      onOpenUrlInput: onOpenUrlInput,
    );

    return switch (surface) {
      AppDisplaySurface.phone => _CupertinoPlaybackEntryRenderer(data: shared),
      AppDisplaySurface.desktopTablet ||
      AppDisplaySurface.television =>
        _NipaplayPlaybackEntryRenderer(data: shared),
    };
  }
}

class _PlaybackEntryRendererData {
  const _PlaybackEntryRendererData({
    required this.content,
    required this.mascotScale,
    required this.onMascotTap,
    required this.onSelectFile,
    required this.onOpenUrlInput,
  });

  final UnifiedPlaybackEntryContent content;
  final material.Animation<double> mascotScale;
  final material.VoidCallback onMascotTap;
  final material.VoidCallback onSelectFile;
  final material.VoidCallback onOpenUrlInput;
}

class _CupertinoPlaybackEntryRenderer extends material.StatelessWidget {
  const _CupertinoPlaybackEntryRenderer({required this.data});

  final _PlaybackEntryRendererData data;

  @override
  material.Widget build(material.BuildContext context) {
    final primaryText = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.label,
      context,
    );
    final secondaryText = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );
    final secondaryFill = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondarySystemFill,
      context,
    );

    return material.LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 20.0;
        const topPadding = 72.0;
        final bottomPadding =
            material.MediaQuery.viewPaddingOf(context).bottom + 24;
        final minimumHeight = math.max(
          0.0,
          constraints.maxHeight - topPadding - bottomPadding,
        );
        return material.SingleChildScrollView(
          physics: const cupertino.BouncingScrollPhysics(
            parent: material.AlwaysScrollableScrollPhysics(),
          ),
          padding: material.EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomPadding,
          ),
          child: material.ConstrainedBox(
            constraints: material.BoxConstraints(minHeight: minimumHeight),
            child: material.Center(
              child: material.ConstrainedBox(
                constraints: const material.BoxConstraints(maxWidth: 520),
                child: material.Column(
                  mainAxisSize: material.MainAxisSize.min,
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: [
                    material.Align(
                      child: _PlaybackMascot(
                        scale: data.mascotScale,
                        size: 88,
                        onTap: data.onMascotTap,
                      ),
                    ),
                    const material.SizedBox(height: 14),
                    material.Text(
                      data.content.emptyTitle,
                      textAlign: material.TextAlign.center,
                      style: material.TextStyle(
                        color: primaryText,
                        fontSize: 18,
                        fontWeight: material.FontWeight.w600,
                      ),
                    ),
                    const material.SizedBox(height: 24),
                    cupertino.CupertinoButton.filled(
                      borderRadius: material.BorderRadius.circular(8),
                      onPressed: data.onSelectFile,
                      child: material.Row(
                        mainAxisAlignment: material.MainAxisAlignment.center,
                        children: [
                          const material.Icon(
                            cupertino.CupertinoIcons.folder_open,
                            size: 19,
                          ),
                          const material.SizedBox(width: 8),
                          material.Text(data.content.selectFileLabel),
                        ],
                      ),
                    ),
                    const material.SizedBox(height: 8),
                    material.Text(
                      data.content.selectFileDescription,
                      textAlign: material.TextAlign.center,
                      style: material.TextStyle(
                        color: secondaryText,
                        fontSize: 13,
                      ),
                    ),
                    const material.SizedBox(height: 18),
                    cupertino.CupertinoButton(
                      borderRadius: material.BorderRadius.circular(8),
                      color: secondaryFill,
                      onPressed: data.onOpenUrlInput,
                      child: material.Row(
                        mainAxisAlignment: material.MainAxisAlignment.center,
                        children: [
                          const material.Icon(
                            cupertino.CupertinoIcons.link,
                            size: 19,
                          ),
                          const material.SizedBox(width: 8),
                          material.Text(data.content.enterUrlLabel),
                        ],
                      ),
                    ),
                    const material.SizedBox(height: 8),
                    material.Text(
                      data.content.enterUrlDescription,
                      textAlign: material.TextAlign.center,
                      style: material.TextStyle(
                        color: secondaryText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NipaplayPlaybackEntryRenderer extends material.StatefulWidget {
  const _NipaplayPlaybackEntryRenderer({required this.data});

  final _PlaybackEntryRendererData data;

  @override
  material.State<_NipaplayPlaybackEntryRenderer> createState() =>
      _NipaplayPlaybackEntryRendererState();
}

class _NipaplayPlaybackEntryRendererState
    extends material.State<_NipaplayPlaybackEntryRenderer> {
  @override
  material.Widget build(material.BuildContext context) {
    final data = widget.data;
    final theme = material.Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return material.Center(
      child: material.SingleChildScrollView(
        padding: const material.EdgeInsets.all(32),
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.center,
          children: [
            _PlaybackMascot(
              scale: data.mascotScale,
              size: 120,
              onTap: data.onMascotTap,
            ),
            const material.SizedBox(width: 20),
            material.ConstrainedBox(
              constraints: const material.BoxConstraints(maxWidth: 620),
              child: material.Column(
                mainAxisSize: material.MainAxisSize.min,
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  material.Text(
                    data.content.emptyTitle,
                    style: material.TextStyle(
                      color: textColor,
                      fontSize: 18,
                    ),
                  ),
                  const material.SizedBox(height: 18),
                  AdaptiveMediaActionButton(
                    label: data.content.selectFileLabel,
                    onPressed: data.onSelectFile,
                    desktopIcon: material.Icons.folder_open_rounded,
                    phoneIcon: cupertino.CupertinoIcons.folder_open,
                    emphasis: AdaptiveMediaActionEmphasis.primary,
                  ),
                  const material.SizedBox(height: 8),
                  material.Text(
                    data.content.selectFileDescription,
                    style: material.TextStyle(
                      color: textColor.withValues(alpha: 0.68),
                      fontSize: 14,
                    ),
                  ),
                  const material.SizedBox(height: 18),
                  _PlaybackChoiceDivider(textColor: textColor),
                  const material.SizedBox(height: 18),
                  AdaptiveMediaActionButton(
                    label: data.content.enterUrlLabel,
                    onPressed: data.onOpenUrlInput,
                    desktopIcon: material.Icons.link_rounded,
                    phoneIcon: cupertino.CupertinoIcons.link,
                  ),
                  const material.SizedBox(height: 8),
                  material.Text(
                    data.content.enterUrlDescription,
                    style: material.TextStyle(
                      color: textColor.withValues(alpha: 0.68),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackMascot extends material.StatelessWidget {
  const _PlaybackMascot({
    required this.scale,
    required this.size,
    required this.onTap,
  });

  final material.Animation<double> scale;
  final double size;
  final material.VoidCallback onTap;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Semantics(
      button: true,
      label: '看板娘',
      child: material.GestureDetector(
        onTap: onTap,
        child: material.ScaleTransition(
          scale: scale,
          child: material.Image.asset(
            'assets/girl.png',
            width: size,
            height: size,
            fit: material.BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _PlaybackChoiceDivider extends material.StatelessWidget {
  const _PlaybackChoiceDivider({required this.textColor});

  final material.Color textColor;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Row(
      children: [
        material.Expanded(
          child: material.ColoredBox(
            color: textColor.withValues(alpha: 0.14),
            child: const material.SizedBox(height: 1),
          ),
        ),
        material.Padding(
          padding: const material.EdgeInsets.symmetric(horizontal: 10),
          child: material.Text(
            '或',
            style: material.TextStyle(
              color: textColor.withValues(alpha: 0.56),
              fontSize: 13,
              fontWeight: material.FontWeight.w600,
            ),
          ),
        ),
        material.Expanded(
          child: material.ColoredBox(
            color: textColor.withValues(alpha: 0.14),
            child: const material.SizedBox(height: 1),
          ),
        ),
      ],
    );
  }
}

class AdaptivePlaybackUrlDialogContent extends material.StatefulWidget {
  const AdaptivePlaybackUrlDialogContent({
    super.key,
    required this.content,
    required this.controller,
    required this.focusNode,
    required this.isSubmitting,
    required this.onPaste,
    required this.onEditOneTimeUserAgent,
    required this.onPlay,
  });

  final UnifiedPlaybackEntryContent content;
  final material.TextEditingController controller;
  final material.FocusNode focusNode;
  final ValueListenable<bool> isSubmitting;
  final material.VoidCallback onPaste;
  final material.VoidCallback onEditOneTimeUserAgent;
  final Future<bool> Function() onPlay;

  @override
  material.State<AdaptivePlaybackUrlDialogContent> createState() =>
      _AdaptivePlaybackUrlDialogContentState();
}

class _AdaptivePlaybackUrlDialogContentState
    extends material.State<AdaptivePlaybackUrlDialogContent> {
  @override
  void initState() {
    super.initState();
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.focusNode.requestFocus();
    });
  }

  Future<void> _playAndClose(material.BuildContext context) async {
    final success = await widget.onPlay();
    if (!success || !context.mounted) return;
    material.Navigator.of(context).pop();
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.ValueListenableBuilder<bool>(
      valueListenable: widget.isSubmitting,
      builder: (context, submitting, _) => _AdaptivePlaybackUrlEditor(
        content: widget.content,
        controller: widget.controller,
        focusNode: widget.focusNode,
        isSubmitting: submitting,
        onPaste: widget.onPaste,
        onEditOneTimeUserAgent: widget.onEditOneTimeUserAgent,
        onPlay: () => _playAndClose(context),
      ),
    );
  }
}

class _AdaptivePlaybackUrlEditor extends material.StatelessWidget {
  const _AdaptivePlaybackUrlEditor({
    required this.content,
    required this.controller,
    required this.focusNode,
    required this.isSubmitting,
    required this.onPaste,
    required this.onEditOneTimeUserAgent,
    required this.onPlay,
  });

  final UnifiedPlaybackEntryContent content;
  final material.TextEditingController controller;
  final material.FocusNode focusNode;
  final bool isSubmitting;
  final material.VoidCallback onPaste;
  final material.VoidCallback onEditOneTimeUserAgent;
  final material.VoidCallback onPlay;

  @override
  material.Widget build(material.BuildContext context) {
    final isPhone =
        AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone;
    final textColor = isPhone
        ? cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.label,
            context,
          )
        : material.Theme.of(context).colorScheme.onSurface;

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Text(
          content.urlHelp,
          style: material.TextStyle(
            color: textColor.withValues(alpha: 0.72),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const material.SizedBox(height: 10),
        AdaptiveMediaTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: material.TextInputType.url,
          textInputAction: material.TextInputAction.go,
          onSubmitted: (_) => onPlay(),
          decoration: material.InputDecoration(
            hintText: content.urlPlaceholder,
            hintStyle: material.TextStyle(
              color: textColor.withValues(alpha: 0.42),
              fontSize: 14,
            ),
            filled: true,
            fillColor: isPhone
                ? cupertino.CupertinoDynamicColor.resolve(
                    cupertino.CupertinoColors.tertiarySystemGroupedBackground,
                    context,
                  )
                : material.Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.94),
            contentPadding: const material.EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
        const material.SizedBox(height: 10),
        material.Wrap(
          alignment: material.WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            AdaptiveMediaActionButton(
              label: content.oneTimeUserAgentLabel,
              onPressed: isSubmitting ? null : onEditOneTimeUserAgent,
              desktopIcon: material.Icons.http_rounded,
              phoneIcon: cupertino.CupertinoIcons.globe,
              compact: true,
            ),
            AdaptiveMediaActionButton(
              label: content.pasteLabel,
              onPressed: isSubmitting ? null : onPaste,
              desktopIcon: material.Icons.content_paste_rounded,
              phoneIcon: cupertino.CupertinoIcons.doc_on_clipboard,
              compact: true,
            ),
            AdaptiveMediaActionButton(
              label:
                  isSubmitting ? content.processingLabel : content.playUrlLabel,
              onPressed: isSubmitting ? null : onPlay,
              desktopIcon: material.Icons.play_arrow_rounded,
              phoneIcon: cupertino.CupertinoIcons.play_fill,
              emphasis: AdaptiveMediaActionEmphasis.primary,
              compact: true,
            ),
          ],
        ),
      ],
    );
  }
}
