import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../detail/episodes.dart' show HeatPainter;
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import '../widgets/progress.dart';
import '../widgets/words.dart';
import '../../player/ports/session_playback.dart';
import '../../player/subtitles/look.dart';
import '../data/settings_data.dart';
import 'menu_controls.dart';
import 'playback.dart';
import 'player_settings.dart';

/// Off, the video's own tracks, and subtitle files; the one on is ticked.
/// Choosing one turns the others off. With one on, how early or late it
/// comes and how large it is, and the pages Classic's menu has: its style,
/// its lines.
class SubtitleMenu extends StatefulWidget {
  const SubtitleMenu({
    super.key,
    required this.playback,
    required this.settings,
    required this.onDone,
  });
  final NextPlayback playback;
  final NextSettingsData settings;
  final VoidCallback onDone;

  @override
  State<SubtitleMenu> createState() => SubtitleMenuState();
}

enum _SubtitlePage { root, style, lines }

class SubtitleMenuState extends State<SubtitleMenu> {
  List<SubtitleChoice>? _choices;
  bool _failed = false;
  _SubtitlePage _page = _SubtitlePage.root;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Esc on a page goes back to the list; false on the list itself.
  bool back() {
    if (_page == _SubtitlePage.root) return false;
    setState(() => _page = _SubtitlePage.root);
    return true;
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
    final on = choices?.where((c) => c.selected && !c.off).firstOrNull;
    final reduced = NextMotion.reduced(context);
    final Widget page;
    switch (_page) {
      case _SubtitlePage.style when on != null:
        page = SubtitleStylePage(
            playback: widget.playback,
            settings: widget.settings,
            on: on,
            onBack: back);
      case _SubtitlePage.lines when on != null:
        page = SubtitleLinesPage(
            playback: widget.playback, onBack: back, onDone: widget.onDone);
      default:
        page = _root(choices, on);
    }
    return PlayerMenuSurface(
      width: _page == _SubtitlePage.root ? 248 : 320,
      child: AnimatedSize(
        duration: reduced ? Duration.zero : const Duration(milliseconds: 220),
        curve: NextMotion.ease,
        alignment: Alignment.topCenter,
        child: KeyedSubtree(key: ValueKey(_page), child: page),
      ),
    );
  }

  Widget _root(List<SubtitleChoice>? choices, SubtitleChoice? on) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        const Align(
            alignment: Alignment.centerLeft, child: PlayerMenuHeading('字幕')),
        if (choices == null)
          const SizedBox(height: 38, child: Center(child: PulseDot()))
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
        if (on != null) ...[
          const PlayerMenuDivider(),
          _SubtitleLook(playback: widget.playback, on: on),
          PlayerMenuLink(
              label: '样式',
              onTap: () => setState(() => _page = _SubtitlePage.style)),
          PlayerMenuLink(
              label: '字幕列表',
              onTap: () => setState(() => _page = _SubtitlePage.lines)),
        ],
        const PlayerMenuDivider(),
        MenuItem(
          label: _failed ? '这个文件用不了' : '添加字幕文件…',
          onTap: () => unawaited(_add()),
        ),
      ]);
}

/// The subtitle on: earlier or later, smaller or larger.
class _SubtitleLook extends StatelessWidget {
  const _SubtitleLook({required this.playback, required this.on});
  final NextPlayback playback;
  final SubtitleChoice on;

  void _set(Future<void> Function() change) => unawaited(change().catchError(
      (Object e) => debugPrint('[NextPlayer] subtitle look: $e')));

  @override
  Widget build(BuildContext context) =>
      PlaybackSelector<(PlayerDial?, PlayerDial?)>(
        playback: playback,
        selector: (_) => (
          playback.canDelaySubtitles(on) ? playback.subtitleDelay(on) : null,
          playback.canScaleSubtitles(on) ? playback.subtitleScale(on) : null,
        ),
        builder: (context, look, _) => Column(children: [
          if (look.$1 case final delay?)
            PlayerMenuRow(
              label: '偏移',
              child: Align(
                alignment: Alignment.centerRight,
                child: PlayerMenuStepper(
                  label: '偏移',
                  dial: delay,
                  onChanged: (v) =>
                      _set(() => playback.setSubtitleDelay(on, v)),
                ),
              ),
            ),
          if (look.$2 case final scale?)
            PlayerMenuRow(
              label: '大小',
              child: Align(
                alignment: Alignment.centerRight,
                child: PlayerMenuStepper(
                  label: '大小',
                  dial: scale,
                  rest: 1,
                  onChanged: (v) =>
                      _set(() => playback.setSubtitleScale(on, v)),
                ),
              ),
            ),
        ]),
      );
}

/// How the subtitle on looks, as Classic's 字幕设置 sets it: a file
/// NipaPlay draws over the video takes its own colour, font, place and
/// outline; one the kernel draws takes what that kernel can draw (all of
/// it with mpv, colours and weight with MDK), and nothing else is shown.
class SubtitleStylePage extends StatelessWidget {
  const SubtitleStylePage({
    super.key,
    required this.playback,
    required this.settings,
    required this.on,
    required this.onBack,
  });
  final NextPlayback playback;
  final NextSettingsData settings;
  final SubtitleChoice on;
  final VoidCallback onBack;

  static const _text = [
    0xFFFFFFFF,
    0xFFFFF3B0,
    0xFFFFD84D,
    0xFF8FE3FF,
    0xFFFFA8C8,
  ];
  static const _dark = [0xFF000000, 0xFF2B2B33, 0xFF1B2A4A, 0xFFFFFFFF];

  @override
  Widget build(BuildContext context) {
    final p = playback;
    final session = p is SessionPlayback ? p : null;
    final overlay = p.drawnOver(on) != null;
    final kernel = overlay
        ? const <String>{}
        : session?.kernelSubtitleStyle ?? const <String>{};
    bool has(String key) => overlay
        ? const {
            'subtitle.bold',
            'subtitle.italic',
            'subtitle.opacity',
            'subtitle.alignX',
            'subtitle.borderSize',
            'subtitle.shadowOffset',
          }.contains(key)
        : kernel.contains(key);
    return PlayerSettings(
      data: settings,
      builder: (context, m) {
        final rows = <Widget>[
          if (overlay) ...[
            PlayerSettingColor(
                model: m,
                setting: 'subtitle.externalColor',
                label: '颜色',
                swatches: _text),
            PlayerSettingField(
                model: m,
                setting: 'subtitle.externalFontName',
                label: '字体',
                hint: '默认'),
          ] else ...[
            if (has('subtitle.color'))
              PlayerSettingColor(
                  model: m,
                  setting: 'subtitle.color',
                  label: '文字',
                  swatches: _text),
            if (has('subtitle.borderColor'))
              PlayerSettingColor(
                  model: m,
                  setting: 'subtitle.borderColor',
                  label: '描边',
                  swatches: _dark),
            if (has('subtitle.shadowColor'))
              PlayerSettingColor(
                  model: m,
                  setting: 'subtitle.shadowColor',
                  label: '阴影',
                  swatches: _dark),
            if (has('subtitle.fontName'))
              PlayerSettingField(
                  model: m,
                  setting: 'subtitle.fontName',
                  label: '字体',
                  hint: '默认'),
          ],
          if (has('subtitle.bold'))
            PlayerSettingToggle(model: m, setting: 'subtitle.bold', label: '粗体'),
          if (has('subtitle.italic'))
            PlayerSettingToggle(
                model: m, setting: 'subtitle.italic', label: '斜体'),
          if (has('subtitle.opacity'))
            PlayerSettingSlider(
                model: m,
                setting: 'subtitle.opacity',
                label: '不透明度',
                min: 0,
                max: 1,
                step: 0.05,
                unit: DialUnit.percent),
          if (has('subtitle.borderSize'))
            PlayerSettingSlider(
                model: m,
                setting: 'subtitle.borderSize',
                label: '描边粗细',
                min: 0,
                max: overlay ? 8 : 10,
                step: 0.5,
                unit: DialUnit.points),
          if (has('subtitle.shadowOffset'))
            PlayerSettingSlider(
                model: m,
                setting: 'subtitle.shadowOffset',
                label: '阴影偏移',
                min: 0,
                max: 10,
                step: 0.5,
                unit: DialUnit.points),
          if (overlay && session != null)
            _OverlayPlace(playback: session, on: on),
          if (has('subtitle.position'))
            PlayerSettingSlider(
                model: m,
                setting: 'subtitle.position',
                label: '位置',
                min: 0,
                max: 100,
                step: 1,
                unit: DialUnit.points),
          if (has('subtitle.alignX'))
            PlayerSettingChoices(
                model: m,
                setting: 'subtitle.alignX',
                label: '水平对齐',
                options: const [
                  ('left', '左'),
                  ('center', '中'),
                  ('right', '右'),
                ]),
          if (has('subtitle.alignY'))
            PlayerSettingChoices(
                model: m,
                setting: 'subtitle.alignY',
                label: '垂直对齐',
                options: const [
                  ('top', '上'),
                  ('center', '中'),
                  ('bottom', '下'),
                ]),
          if (has('subtitle.marginX'))
            PlayerSettingSlider(
                model: m,
                setting: 'subtitle.marginX',
                label: '左右边距',
                min: 0,
                max: 300,
                step: 1,
                unit: DialUnit.points),
          if (has('subtitle.marginY'))
            PlayerSettingSlider(
                model: m,
                setting: 'subtitle.marginY',
                label: '上下边距',
                min: 0,
                max: 300,
                step: 1,
                unit: DialUnit.points),
          if (has('subtitle.overrideMode')) ...[
            const PlayerSettingHeading('ASS 字幕'),
            PlayerSettingChoices(
                model: m,
                setting: 'subtitle.overrideMode',
                label: '样式',
                options: const [
                  ('auto', '自动'),
                  ('none', '原样'),
                  ('scale', '缩放'),
                  ('force', '覆盖'),
                ]),
          ],
        ];
        final keys = [
          if (overlay) ...['subtitle.externalColor', 'subtitle.externalFontName'],
          for (final key in SubtitleLook.kernelStyleKeys.keys)
            if (has(key)) key,
        ];
        return PlayerSettingsPage(title: '字幕样式', onBack: onBack, children: [
          ...rows,
          if (keys.isNotEmpty) ...[
            const PlayerMenuDivider(),
            PlayerSettingAction(
                label: '恢复默认', onTap: () => unawaited(m.reset(keys))),
          ],
        ]);
      },
    );
  }
}

/// A file drawn over the video: how high it sits and how far sideways,
/// kept for that file.
class _OverlayPlace extends StatelessWidget {
  const _OverlayPlace({required this.playback, required this.on});
  final SessionPlayback playback;
  final SubtitleChoice on;

  @override
  Widget build(BuildContext context) => PlaybackSelector<OverlayPlacement?>(
        playback: playback,
        selector: (_) => playback.overlayPlacement(on),
        builder: (context, place, _) {
          if (place == null) return const SizedBox.shrink();
          void set(OverlayPlacement next) => unawaited(playback
              .setOverlayPlacement(on, next)
              .catchError((Object e) =>
                  debugPrint('[NextPlayer] subtitle place: $e')));
          return Column(mainAxisSize: MainAxisSize.min, children: [
            PlayerSettingRow(
              label: '位置',
              child: PlayerMenuSlider(
                label: '位置',
                dial: PlayerDial(place.position.clamp(0, 100).toDouble(), 0,
                    100, 1, DialUnit.points),
                onChanged: (_) {},
                onEnd: (v) => set(place.copyWith(position: v)),
              ),
            ),
            PlayerSettingRow(
              label: '左右',
              child: Align(
                alignment: Alignment.centerRight,
                child: PlayerMenuStepper(
                  label: '左右',
                  dial: PlayerDial(place.marginX.clamp(-400, 400).toDouble(),
                      -400, 400, 10, DialUnit.points),
                  onChanged: (v) => set(place.copyWith(marginX: v)),
                ),
              ),
            ),
          ]);
        },
      );
}

/// The lines of the subtitle on, as Classic's 字幕列表: the one showing
/// marked and scrolled to; a click goes there.
class SubtitleLinesPage extends StatefulWidget {
  const SubtitleLinesPage(
      {super.key,
      required this.playback,
      required this.onBack,
      required this.onDone});
  final NextPlayback playback;
  final VoidCallback onBack;
  final VoidCallback onDone;

  @override
  State<SubtitleLinesPage> createState() => _SubtitleLinesPageState();
}

class _SubtitleLinesPageState extends State<SubtitleLinesPage> {
  List<({int startMs, String text, bool current})>? _lines;
  final _scroll = ScrollController();
  static const _row = 52.0;

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
    final lines = <({int startMs, String text, bool current})>[];
    try {
      int? cursor = 0;
      final end = widget.playback.duration.inMilliseconds;
      // A long file is read in pages; four thousand lines is a film's.
      while (cursor != null && lines.length < 4000) {
        final page = await widget.playback.inspection.inspect('subtitle.cues', {
          'startMs': 0,
          'endMs': end > 0 ? end : 24 * 3600 * 1000,
          'limit': 500,
          'cursor': cursor,
        });
        for (final item in (page['items'] as List?) ?? const []) {
          final m = item as Map;
          lines.add((
            startMs: (m['startMs'] as num?)?.toInt() ?? 0,
            text: '${m['text'] ?? ''}'.trim(),
            current: m['current'] == true,
          ));
        }
        cursor = (page['nextCursor'] as num?)?.toInt();
      }
    } catch (e) {
      debugPrint('[NextPlayer] subtitle lines: $e');
    }
    if (!mounted) return;
    setState(() => _lines = lines);
    final now = widget.playback.position.inMilliseconds;
    var at = lines.lastIndexWhere((l) => l.startMs <= now);
    if (at > 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(math.min(
              (at - 2) * _row, _scroll.position.maxScrollExtent));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final height = MediaQuery.sizeOf(context).height;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Align(
          alignment: Alignment.centerLeft,
          child: PlayerMenuBack(
              lines == null || lines.isEmpty
                  ? '字幕列表'
                  : '字幕列表 · ${lines.length}',
              onTap: widget.onBack)),
      if (lines == null)
        const SizedBox(height: 58, child: Center(child: PulseDot()))
      else if (lines.isEmpty)
        SizedBox(
          height: 58,
          child: Center(
            child: Text('这条字幕读不到台词',
                style: NextText.sans(13, color: NextColors.p3)),
          ),
        )
      else
        ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: math.max(200, math.min(440, height - 150))),
          child: PlaybackSelector<int>(
            playback: widget.playback,
            selector: (p) => lines.lastIndexWhere(
                (l) => l.startMs <= p.position.inMilliseconds),
            builder: (context, now, _) => ListView.builder(
              controller: _scroll,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemExtent: _row,
              itemCount: lines.length,
              itemBuilder: (context, i) => TimedLine(
                at: lines[i].startMs,
                text: lines[i].text,
                current: i == now,
                onTap: () =>
                    widget.playback.seek(Duration(milliseconds: lines[i].startMs)),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// A timed line: when, and what.
class TimedLine extends StatelessWidget {
  const TimedLine(
      {super.key,
      required this.at,
      required this.text,
      required this.onTap,
      this.current = false,
      this.dim = false});
  final int at;
  final String text;
  final bool current;
  final bool dim;
  final VoidCallback onTap;

  static String clock(int ms) {
    final s = ms ~/ 1000;
    final h = s ~/ 3600, m = (s ~/ 60) % 60, sec = s % 60;
    final mm = m.toString().padLeft(2, '0'), ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: text,
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
              width: 58,
              child: Text(clock(at),
                  style: NextText.num(12,
                      color: current ? NextColors.accent : NextColors.p3)),
            ),
            Expanded(
              child: Text(text.replaceAll('\n', ' ').replaceAll(r'\N', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(13,
                      height: 1.35,
                      color: current || hovered
                          ? NextColors.paper
                          : dim
                              ? NextColors.p4
                              : NextColors.p2)),
            ),
          ]),
        ),
      );
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

/// What plays, as the library knows it: the work, the episodes of the
/// season playing (all of them when the work has one season, or the one
/// playing is not among them), and the one playing.
final class PlayingWork {
  const PlayingWork(this.work, this.episodes, this.current,
      {this.seasons = false});
  final UiWork work;
  final List<UiEpisode> episodes;
  final UiEpisode? current;

  /// The work has more than one season.
  final bool seasons;

  /// The season playing by name, or 剧集.
  String get heading =>
      seasons && current != null ? Words.season(current!.season) : '剧集';

  /// The numbered episodes after the one playing, in its season, in
  /// order; none when it has no number.
  List<UiEpisode> get _after {
    final now = current, at = current?.number;
    if (now == null || at == null) return const [];
    return [
      for (final e in episodes)
        if (e.number case final n? when e.season == now.season && n > at) e
    ]..sort((a, b) => a.number!.compareTo(b.number!));
  }

  /// What 下一集 plays: the first episode after the one playing, in its
  /// season, that can be played now.
  UiEpisode? get next => _after.where((e) => e.playable).firstOrNull;

  /// One after it in its season is not here yet.
  bool get waiting => next == null && _after.isNotEmpty;

  /// The library's side of the file at [path]; null when the library does
  /// not know it.
  static Future<PlayingWork?> of(NextUiData data, String? path) async {
    if (path == null || data is! NextNowPlaying) return null;
    try {
      final now = await (data as NextNowPlaying).nowPlaying(path);
      if (now == null) return null;
      final (work, all) =
          await (data.work(now.workId), data.episodes(now.workId)).wait;
      if (work == null) return null;
      final current =
          all.where((e) => e.episodeId == now.episodeId).firstOrNull;
      final seasons = {for (final e in all) e.season}.length > 1;
      return PlayingWork(
        work,
        seasons && current != null
            ? [
                for (final e in all)
                  if (e.season == current.season) e
              ]
            : all,
        current,
        seasons: seasons,
      );
    } catch (e) {
      debugPrint('[NextPlayer] library episodes: $e');
      return null;
    }
  }
}

class _EpisodeMenuState extends State<EpisodeMenu> {
  PlayingWork? _known;
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
    final known = await PlayingWork.of(
        widget.shell.services.data, widget.playback.path);
    if (!mounted) return;
    if (known != null && known.episodes.isNotEmpty) {
      setState(() => _known = known);
      return _openAt(
          known.episodes
              .indexWhere((e) => e.episodeId == known.current?.episodeId),
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
            current: e.episodeId == known.current?.episodeId,
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
    return PlayerMenuSurface(
      width: known != null ? 392 : 340,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(
            alignment: Alignment.centerLeft,
            child: PlayerMenuHeading(known?.heading ?? '剧集')),
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
    final title = episode.title ?? Words.episode(episode.number) ?? '';
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
                        : episode.number == null
                            ? const SizedBox.shrink()
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
                    if (Words.runtime(episode.runtime) case final runtime?) ...[
                      const SizedBox(width: 8),
                      Text(runtime,
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
