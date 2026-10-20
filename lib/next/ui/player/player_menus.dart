import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import '../widgets/progress.dart';
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

/// The episodes the player goes through, the one playing marked; a click
/// plays another.
class EpisodeMenu extends StatefulWidget {
  const EpisodeMenu({super.key, required this.playback, required this.onDone});
  final NextPlayback playback;
  final VoidCallback onDone;

  @override
  State<EpisodeMenu> createState() => _EpisodeMenuState();
}

class _EpisodeMenuState extends State<EpisodeMenu> {
  List<EpisodeChoice>? _episodes;
  final _scroll = ScrollController();

  static const _row = 58.0;

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
    List<EpisodeChoice> episodes;
    try {
      episodes = await widget.playback.episodes();
    } catch (e) {
      debugPrint('[NextPlayer] episodes: $e');
      episodes = const [];
    }
    if (!mounted) return;
    setState(() => _episodes = episodes);
    // Opened at the one playing.
    final at = episodes.indexWhere((e) => e.current);
    if (at > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(math.min(
              (at - 1) * _row, _scroll.position.maxScrollExtent));
        }
      });
    }
  }

  void _play(EpisodeChoice e) {
    widget.onDone();
    unawaited(widget.playback.play(e).catchError(
        (Object err) => debugPrint('[NextPlayer] play episode: $err')));
  }

  @override
  Widget build(BuildContext context) {
    final episodes = _episodes;
    final height = MediaQuery.sizeOf(context).height;
    return _MenuSurface(
      width: 340,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Align(alignment: Alignment.centerLeft, child: _Heading('剧集')),
        if (episodes == null)
          const SizedBox(height: 58, child: Center(child: PulseDot()))
        else if (episodes.isEmpty)
          SizedBox(
            height: 58,
            child: Center(
              child: Text('没有别的剧集',
                  style: NextText.sans(13, color: NextColors.p3)),
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: math.min(_row * 7.5, height * 0.56)),
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
                itemExtent: _row,
                itemCount: episodes.length,
                itemBuilder: (context, i) => _EpisodeRow(
                  number: i + 1,
                  episode: episodes[i],
                  onTap: () => _play(episodes[i]),
                ),
              ),
            ),
          ),
      ]),
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
