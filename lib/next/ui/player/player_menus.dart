import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../detail/episodes.dart' show HeatPainter;
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import '../widgets/progress.dart';
import '../widgets/words.dart';
import 'playback.dart';

/// The frosted surface the player's menus sit on, as the shell's popovers.
class _MenuSurface extends StatelessWidget {
  const _MenuSurface({required this.width, required this.child});
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => Glass(
        blur: 30,
        color: const Color(0xD1121218),
        borderColor: const Color(0x1AFFFFFF),
        radius: BorderRadius.circular(16),
        shadows: const [
          BoxShadow(
              color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 12))
        ],
        padding: const EdgeInsets.all(6),
        child: SizedBox(width: width, child: child),
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Text(text,
            style: NextText.sans(12,
                weight: FontWeight.w600,
                letterSpacing: 0.8,
                color: NextColors.p3)),
      );
}

/// Off, the video's own tracks, and subtitle files; the one on is ticked.
/// Choosing one turns the others off.
class SubtitleMenu extends StatefulWidget {
  const SubtitleMenu({super.key, required this.playback, required this.onDone});
  final NextPlayback playback;
  final VoidCallback onDone;

  @override
  State<SubtitleMenu> createState() => _SubtitleMenuState();
}

class _SubtitleMenuState extends State<SubtitleMenu> {
  List<SubtitleChoice>? _choices;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final choices = await widget.playback.subtitles();
      if (mounted) setState(() => _choices = choices);
    } catch (e) {
      debugPrint('[NextPlayer] subtitles: $e');
      if (mounted) setState(() => _choices = const [SubtitleChoice.off()]);
    }
  }

  Future<void> _choose(SubtitleChoice choice) async {
    widget.onDone();
    try {
      await widget.playback.choose(choice);
    } catch (e) {
      debugPrint('[NextPlayer] choose subtitle: $e');
    }
  }

  Future<void> _add() async {
    final ok = await widget.playback.addSubtitleFile();
    if (!mounted) return;
    if (ok) return widget.onDone();
    setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final choices = _choices;
    return _MenuSurface(
      width: 248,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Align(alignment: Alignment.centerLeft, child: _Heading('字幕')),
        if (choices == null)
          const SizedBox(
              height: 38, child: Center(child: PulseDot()))
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final c in choices)
                  MenuItem(
                    label: c.label,
                    selected: c.selected,
                    trailing: c.selected
                        ? const NextIcon(NextGlyph.check,
                            size: 15, color: NextColors.paper)
                        : null,
                    onTap: () => unawaited(_choose(c)),
                  ),
              ]),
            ),
          ),
        Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            color: NextColors.line),
        MenuItem(
          label: _failed ? '这个文件用不了' : '添加字幕文件…',
          onTap: () => unawaited(_add()),
        ),
      ]),
    );
  }
}

/// The episodes of what plays, the one playing marked; a click plays
/// another. A file the library knows shows its work's episodes as the
/// detail page does (stills, progress, where the danmaku gather) and
/// plays them as the shell plays anything; a file only Classic knows
/// goes through Classic's playlist.
class EpisodeMenu extends StatefulWidget {
  const EpisodeMenu({
    super.key,
    required this.playback,
    required this.shell,
    required this.onDone,
  });
  final NextPlayback playback;
  final NextShellController shell;
  final VoidCallback onDone;

  @override
  State<EpisodeMenu> createState() => _EpisodeMenuState();
}

/// The library's side: the work, the episodes shown, the one playing.
final class _Known {
  const _Known(this.work, this.episodes, this.currentId, this.heading);
  final UiWork work;
  final List<UiEpisode> episodes;
  final String? currentId;
  final String heading;
}

class _EpisodeMenuState extends State<EpisodeMenu> {
  _Known? _known;
  List<EpisodeChoice>? _episodes;
  final _scroll = ScrollController();

  static const _row = 58.0;
  static const _stillRow = 84.0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final known = await _fromLibrary();
    if (!mounted) return;
    if (known != null) {
      setState(() => _known = known);
      return _openAt(
          known.episodes.indexWhere((e) => e.episodeId == known.currentId),
          _stillRow);
    }
    List<EpisodeChoice> episodes;
    try {
      episodes = await widget.playback.episodes();
    } catch (e) {
      debugPrint('[NextPlayer] episodes: $e');
      episodes = const [];
    }
    if (!mounted) return;
    setState(() => _episodes = episodes);
    _openAt(episodes.indexWhere((e) => e.current), _row);
  }

  /// The work's episodes when the library knows the file: the season of
  /// the one playing.
  Future<_Known?> _fromLibrary() async {
    final path = widget.playback.state.currentVideoPath;
    final data = widget.shell.services.data;
    if (path == null || data is! NextNowPlaying) return null;
    try {
      final now = await (data as NextNowPlaying).nowPlaying(path);
      if (now == null) return null;
      final (work, all) =
          await (data.work(now.workId), data.episodes(now.workId)).wait;
      if (work == null || all.isEmpty) return null;
      final current =
          all.where((e) => e.episodeId == now.episodeId).firstOrNull;
      final seasons = {for (final e in all) e.season}.length > 1;
      return _Known(
        work,
        seasons && current != null
            ? [
                for (final e in all)
                  if (e.season == current.season) e
              ]
            : all,
        current?.episodeId,
        seasons && current != null ? Words.season(current.season) : '剧集',
      );
    } catch (e) {
      debugPrint('[NextPlayer] library episodes: $e');
      return null;
    }
  }

  /// Opened at the one playing.
  void _openAt(int at, double row) {
    if (at <= 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(
            math.min((at - 1) * row, _scroll.position.maxScrollExtent));
      }
    });
  }

  void _play(EpisodeChoice e) {
    widget.onDone();
    unawaited(widget.playback.play(e).catchError(
        (Object err) => debugPrint('[NextPlayer] play episode: $err')));
  }

  void _playKnown(UiWork work, UiEpisode e) {
    widget.onDone();
    widget.shell.play(work, episode: e);
  }

  @override
  Widget build(BuildContext context) {
    final known = _known;
    final episodes = _episodes;
    final height = MediaQuery.sizeOf(context).height;
    final Widget body;
    if (known != null) {
      body = _list(
        maxHeight: math.min(_stillRow * 5.5, height * 0.6),
        extent: _stillRow,
        count: known.episodes.length,
        item: (i) {
          final e = known.episodes[i];
          return _StillRow(
            work: known.work,
            episode: e,
            current: e.episodeId == known.currentId,
            onTap: () => _playKnown(known.work, e),
          );
        },
      );
    } else if (episodes == null) {
      body = const SizedBox(height: 58, child: Center(child: PulseDot()));
    } else if (episodes.isEmpty) {
      body = SizedBox(
        height: 58,
        child: Center(
          child: Text('没有别的剧集',
              style: NextText.sans(13, color: NextColors.p3)),
        ),
      );
    } else {
      body = _list(
        maxHeight: math.min(_row * 7.5, height * 0.56),
        extent: _row,
        count: episodes.length,
        item: (i) => _EpisodeRow(
          number: i + 1,
          episode: episodes[i],
          onTap: () => _play(episodes[i]),
        ),
      );
    }
    return _MenuSurface(
      width: known != null ? 392 : 340,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(
            alignment: Alignment.centerLeft,
            child: _Heading(known?.heading ?? '剧集')),
        body,
      ]),
    );
  }

  Widget _list({
    required double maxHeight,
    required double extent,
    required int count,
    required Widget Function(int i) item,
  }) =>
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        // Rows fade at the edges they scroll past.
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x00FFFFFF),
              Color(0xFFFFFFFF),
              Color(0xFFFFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: [0, 0.035, 0.965, 1],
          ).createShader(rect),
          child: ListView.builder(
            controller: _scroll,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemExtent: extent,
            itemCount: count,
            itemBuilder: (context, i) => item(i),
          ),
        ),
      );
}

/// An episode of the library, as on the detail page in small: the still
/// with its number and how far it was watched, the title and runtime, the
/// danmaku heat under them. The one playing is outlined; one NipaPlay has
/// nothing to play from is dimmed.
class _StillRow extends StatelessWidget {
  const _StillRow({
    required this.work,
    required this.episode,
    required this.current,
    required this.onTap,
  });
  final UiWork work;
  final UiEpisode episode;
  final bool current;
  final VoidCallback onTap;

  static const _still = Size(112, 63);

  @override
  Widget build(BuildContext context) {
    final progress = episode.progress;
    final heat = episode.heat;
    final title = episode.title ?? Words.episode(episode.number);
    return Opacity(
      opacity: episode.playable || current ? 1 : 0.5,
      child: Pressable(
        onTap: current || !episode.playable ? null : onTap,
        semanticLabel: title,
        pressScale: 0.99,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: current
                ? const Color(0x14FFFFFF)
                : hovered
                    ? const Color(0x0FFFFFFF)
                    : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Container(
              width: _still.width,
              height: _still.height,
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: current ? NextColors.paper : const Color(0x14FFFFFF),
                    width: current ? 1.5 : 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(fit: StackFit.expand, children: [
                  NextImage(episode.still, tint: work.artwork.tint),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xB3000000), Color(0x00000000)],
                        stops: [0, 0.6],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 6,
                    child: current
                        ? const NextIcon(NextGlyph.play,
                            size: 13, color: NextColors.accent)
                        : Text(episode.number.toString().padLeft(2, '0'),
                            style: NextText.num(16,
                                weight: FontWeight.w700,
                                color: const Color(0xEBFFFFFF))),
                  ),
                  if (progress != null && progress > 0.01 && !current)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ThinBar(
                          progress: progress,
                          height: 2.5,
                          track: const Color(0x33FFFFFF),
                          fill: const Color(0xE6F5F1EA)),
                    ),
                ]),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NextText.sans(13.5,
                              weight: FontWeight.w600,
                              color: current || hovered
                                  ? NextColors.paper
                                  : NextColors.p2)),
                    ),
                    if (episode.runtime != null) ...[
                      const SizedBox(width: 8),
                      Text(Words.runtime(episode.runtime!),
                          style: NextText.sans(11.5,
                              weight: FontWeight.w500, color: NextColors.p3)),
                    ],
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 20,
                    width: double.infinity,
                    child: heat == null || heat.isEmpty
                        ? null
                        : CustomPaint(painter: HeatPainter(heat)),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow(
      {required this.number, required this.episode, required this.onTap});
  final int number;
  final EpisodeChoice episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = episode.current;
    final progress = episode.progress;
    return Pressable(
      onTap: current ? null : onTap,
      semanticLabel: episode.title,
      pressScale: 0.99,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: current
              ? const Color(0x14FFFFFF)
              : hovered
                  ? const Color(0x0FFFFFFF)
                  : const Color(0x00FFFFFF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          SizedBox(
            width: 34,
            child: current
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: NextIcon(NextGlyph.play,
                        size: 13, color: NextColors.accent))
                : Text(number.toString().padLeft(2, '0'),
                    style: NextText.num(16,
                        weight: FontWeight.w700,
                        color: hovered ? NextColors.paper : NextColors.p3)),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(episode.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(13.5,
                        weight: FontWeight.w600,
                        color: current || hovered
                            ? NextColors.paper
                            : NextColors.p2)),
                if (progress != null && progress > 0.01 && !current) ...[
                  const SizedBox(height: 7),
                  ThinBar(
                      progress: progress,
                      height: 2,
                      width: 120,
                      fill: const Color(0xB3F5F1EA)),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
