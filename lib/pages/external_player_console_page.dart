import 'package:flutter/material.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/models/external_player_session.dart';
import 'package:nipaplay/services/external_player_console_service.dart';

/// Console for the single external-player session managed on Linux.
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
                constraints: const BoxConstraints(maxWidth: 760),
                child: session == null
                    ? const _EmptyConsole()
                    : _ConsoleCard(
                        session: session,
                        isPaused: session.isPaused ?? false,
                        danmakuOpacity: session.danmakuOpacity ?? 1.0,
                        supportsDanmakuOpacity: service.supportsDanmakuOpacity,
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
    required this.isPaused,
    required this.danmakuOpacity,
    required this.supportsDanmakuOpacity,
  });

  final ExternalPlayerSession session;
  final bool isPaused;
  final double danmakuOpacity;
  final bool supportsDanmakuOpacity;

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
                session.animeTitle,
                localizations.externalPlayerConsoleUnknownAnime,
              ),
            ),
            _detailRow(
              context,
              localizations.externalPlayerConsoleEpisode,
              _nonEmptyOr(
                session.episodeTitle,
                localizations.externalPlayerConsoleUnknownEpisode,
              ),
            ),
            _detailRow(
              context,
              localizations.externalPlayerConsoleEpisodeId,
              session.episodeId?.toString() ?? '-',
            ),
            _detailRow(
              context,
              localizations.externalPlayerConsoleProcessId,
              session.processId.toString(),
            ),
            _detailRow(
              context,
              localizations.externalPlayerConsoleMediaPath,
              session.mediaPath,
            ),
            const SizedBox(height: 20),
            _buildProgress(context),
            const SizedBox(height: 20),
            _buildDanmakuOpacity(context),
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
    final supportsProgress = session.ipcPath != null;
    final hasProgress =
        session.position != null && session.duration > Duration.zero;
    final progressText = !supportsProgress
        ? localizations.externalPlayerConsoleProgressUnsupported
        : !hasProgress
            ? localizations.externalPlayerConsoleProgressLoading
            : '${_formatDuration(session.position!)} / '
                '${_formatDuration(session.duration)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.externalPlayerConsoleProgress,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: supportsProgress ? session.fraction : 0,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
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

  String _nonEmptyOr(String? value, String fallback) {
    return value == null || value.trim().isEmpty ? fallback : value;
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
