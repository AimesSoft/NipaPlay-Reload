import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../data/discover.dart';
import '../data/work_manage.dart';
import '../settings/settings_layout.dart' show SettingsSection;
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/art_origin.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/poster_art.dart';
import '../widgets/words.dart';
import '../widgets/work_title.dart';
import 'collection.dart';
import 'detail_backdrop.dart';
import 'docking_title.dart';
import 'episodes.dart';
import 'manage_episode.dart';
import 'manage_sheet.dart';
import 'manage_work.dart';

/// A work's page (INTERACTION.md「详情」): full-bleed backdrop, the work on
/// the left (original title, logo or Songti title, one meta line, two lines
/// of overview, continue / ask Nipa / ⋯), a season's episodes below.
/// Scrolling moves the backdrop at 0.3× and docks the title in the top bar.
/// A work found on 发现 and not in the library has no episodes yet: its
/// page offers “让 Nipa 准备” instead of playing.
class WorkDetailPage extends StatefulWidget {
  const WorkDetailPage({super.key, required this.work, this.origin});
  final UiWork work;

  /// The picture it was opened from (see `workRoute`).
  final ArtOriginState? origin;

  @override
  State<WorkDetailPage> createState() => _WorkDetailPageState();
}

/// Handles for `ext.nipaplay.nextui` in lab profiles.
abstract interface class WorkDetailDebug {
  ScrollController get debugScroll;
  void debugSeason(int? season);
  void debugMenu(bool open);
  void debugOverview(bool open);
  void debugSeasons(bool open);
  Map<String, Object?> debugStatus();

  /// The management sheets: `open=work|episode|none`, `section=`,
  /// `episode=<index in the season>`, `tileMenu=<index>|none`,
  /// `restore=true` (the removed work back); the rest goes to the open
  /// sheet.
  Future<Map<String, Object?>> debugManage(Map<String, String> p);
}

class _WorkDetailPageState extends State<WorkDetailPage>
    with SingleTickerProviderStateMixin
    implements WorkDetailDebug {
  late UiWork _work = widget.work;

  /// The work shown: another one once a work of its own is made of it.
  late String _workId = widget.work.workId;
  List<UiEpisode>? _episodes;
  int? _season;
  bool _overviewOpen = false;
  bool _menuOpen = false;
  bool _seasonsOpen = false;

  /// The open management sheet: the work's at a section, or an
  /// episode's.
  WorkSection? _workSheet;
  (UiEpisode, EpisodeSection)? _episodeSheet;
  final _sheetKey = GlobalKey();

  /// The episode whose ⋯ menu is open, and where each one hangs.
  String? _tileMenu;
  final _tileLinks = <String, LayerLink>{};

  /// Taken out of the library from its sheet: the page stays, with the
  /// way back.
  UiUndo? _removed;

  /// Counts the page's reads: an open sheet reads again with it.
  int _revision = 0;

  /// A short word after the ⋯ menu did something, gone after a moment.
  String? _said;
  Timer? _saidTimer;

  late final bool _found = Found.isFound(widget.work);

  final _scroll = ScrollController();
  late final AnimationController _dock = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));
  late final Animation<double> _docked = CurvedAnimation(
      parent: _dock, curve: NextMotion.ease, reverseCurve: Curves.easeInCubic);
  late final Animation<double> _barTitle =
      CurvedAnimation(parent: _dock, curve: const Interval(0.5, 1));
  final _menuLink = LayerLink();
  final _seasonLink = LayerLink();

  NextShellController? _shell;
  StreamSubscription<void>? _changes;
  Animation<double>? _route;
  late Animation<double> _flight;
  late Animation<double> _content;
  late ArtOriginState? _origin = widget.origin;
  Rect? _lastRect;
  bool _flies = false;

  /// Scrolled this far, the title docks in the top bar.
  static const _dockAt = 56.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (!identical(shell, _shell)) {
      _shell = shell;
      _changes?.cancel();
      _changes = shell.services.data.changes.listen((_) => _load());
      _load();
    }
    final route = ModalRoute.of(context)!.animation!;
    if (!identical(route, _route)) {
      _route?.removeStatusListener(_routeStatus);
      _route = route..addStatusListener(_routeStatus);
      // Starts and lands gently both ways; the words leave first on return.
      _flight = CurvedAnimation(
          parent: route,
          curve: Curves.fastOutSlowIn,
          reverseCurve: Curves.fastOutSlowIn);
      _content = CurvedAnimation(
          parent: route,
          curve: const Interval(0.35, 1, curve: Curves.easeOut),
          reverseCurve: const Interval(0.75, 1, curve: Curves.easeIn));
    }
    _flies = widget.origin != null && !NextMotion.reduced(context);
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_routeStatus);
    _changes?.cancel();
    _saidTimer?.cancel();
    _scroll.dispose();
    _dock.dispose();
    final origin = _origin;
    if (origin != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => origin.hidden = false);
    }
    super.dispose();
  }

  void _routeStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) _origin?.hidden = false;
  }

  Future<void> _load() async {
    if (_found) return _loadFound();
    final data = _shell!.services.data;
    final id = _workId;
    final work = await data.work(id);
    if (!mounted || id != _workId) return;
    if (work == null) {
      // Removed with the way back, or a sheet still open on it: the page
      // stays until that is done.
      if (_removed != null || _workSheet != null || _episodeSheet != null) {
        return;
      }
      // Gone from the library: nothing to show any more.
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop();
      }
      return;
    }
    final episodes = await data.episodes(id);
    if (!mounted) return;
    setState(() {
      _work = work;
      _episodes = episodes;
      _revision++;
    });
  }

  /// A found work: what its page needs, read once (the library's changes
  /// do not touch it).
  Future<void> _loadFound() async {
    if (_episodes != null) return;
    _episodes = const [];
    try {
      final work = await _shell!.services.discover.details(widget.work);
      if (mounted) setState(() => _work = work);
    } catch (error) {
      debugPrint('[NextUi] found work details failed: $error');
    }
  }

  /// The picture flown from, this frame. Coming back after its page was
  /// rebuilt, the same work's picture nearest to where it was.
  ArtFrame? _source() {
    final shell = _shell!;
    final reference = shell.origins.reference?.call();
    if (reference == null) return null;
    var frame = _origin?.frame(reference);
    if (frame == null &&
        _route!.status == AnimationStatus.reverse &&
        _lastRect != null) {
      final found = shell.origins.find(_work.workId, near: _lastRect);
      if (found != null && !identical(found, _origin)) {
        _origin = found;
        if (found.lifts) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => found.hidden = true);
        }
        frame = found.frame(reference);
      }
    }
    if (frame != null) _lastRect = frame.rect;
    return frame;
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      final dock = n.metrics.pixels > _dockAt;
      if (dock && !_dock.isForwardOrCompleted) {
        _dock.forward();
      } else if (!dock && _dock.isForwardOrCompleted) {
        _dock.reverse();
      }
    }
    // The page draws its own bar scrim under the docked title.
    return true;
  }

  // —— Data ——

  static int _seasonOrder(int? s) => s == null ? -1 : (s == 0 ? 1 << 20 : s);

  List<int?> get _seasons {
    final seasons = {for (final e in _episodes ?? const <UiEpisode>[]) e.season}
        .toList()
      ..sort((a, b) => _seasonOrder(a).compareTo(_seasonOrder(b)));
    return seasons;
  }

  int? get _currentSeason {
    final seasons = _seasons;
    if (_season != null && seasons.contains(_season)) return _season;
    final next = _work.next?.season;
    if (seasons.contains(next)) return next;
    return seasons.firstOrNull;
  }

  String? get _original {
    final original = _work.originalTitle;
    return original == null || original.isEmpty || original == _work.title
        ? null
        : original;
  }

  /// Episodes NipaPlay cannot play yet (or never heard of): “下载全部”.
  bool get _missing {
    final episodes = _episodes;
    if (episodes == null) return false;
    final count = _work.episodeCount;
    return episodes.any((e) => !e.playable) ||
        (count != null && episodes.length < count);
  }

  // —— Actions ——

  void _downloadAll() {
    final shell = _shell!;
    setState(() => _menuOpen = false);
    shell.sayAbout(_work, '把《${_work.title}》剩下的集都下载下来');
  }

  /// A work not in the library: Nipa is asked, in your words, to get it.
  void _prepare() => _shell!.sayAbout(_work, '帮我准备《${_work.title}》');

  /// The season's episodes on disk, for “都看过了” / “标成没看过”.
  List<UiEpisode> get _seasonOnDisk => [
        for (final e in _episodes ?? const <UiEpisode>[])
          if (e.season == _currentSeason && e.playable) e
      ];

  NextWorkManage? get _manage => _found ? null : _shell!.services.manage;

  /// Managing the work, in the ⋯ menu's second part.
  List<(String, VoidCallback)> get _manageItems => _manage == null
      ? const []
      : [
          ('匹配作品…', () => _openWork(WorkSection.match)),
          ('编辑资料…', () => _openWork(WorkSection.info)),
          ('剧集与文件…', () => _openWork(WorkSection.episodes)),
        ];

  void _openWork(WorkSection section) => setState(() {
        _menuOpen = false;
        _tileMenu = null;
        _episodeSheet = null;
        _workSheet = section;
      });

  void _openEpisode(UiEpisode episode, EpisodeSection section) =>
      setState(() {
        _tileMenu = null;
        _workSheet = null;
        _episodeSheet = (episode, section);
      });

  void _closeSheets() {
    setState(() {
      _workSheet = null;
      _episodeSheet = null;
    });
    _load();
  }

  /// A work of its own was made of this one: the page shows it instead.
  void _replaced(String workId) {
    setState(() => _workId = workId);
    _load();
  }

  void _removedWork(UiUndo undo) {
    setState(() {
      _workSheet = null;
      _removed = undo;
    });
    _load();
  }

  Future<void> _undoRemove() async {
    final undo = _removed;
    if (undo == null) return;
    try {
      await _manage!.restore(undo);
      if (!mounted) return;
      setState(() => _removed = null);
      _load();
    } on UiManageError {
      _note('没能撤回。');
    }
  }

  void _note(String text) {
    _saidTimer?.cancel();
    setState(() => _said = text);
    _saidTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _said = null);
    });
  }

  /// An episode's ⋯: its danmaku, subtitles and files; watched or not.
  List<(String, VoidCallback)> _episodeItems(UiEpisode e) => [
        ('弹幕…', () => _openEpisode(e, EpisodeSection.danmaku)),
        ('字幕…', () => _openEpisode(e, EpisodeSection.subtitles)),
        ('文件…', () => _openEpisode(e, EpisodeSection.files)),
        if (e.playable && (e.progress ?? 0) < 1)
          ('看过了', () {
            setState(() => _tileMenu = null);
            _mark([e], true);
          })
        else if ((e.progress ?? 0) >= 1)
          ('标成没看过', () {
            setState(() => _tileMenu = null);
            _mark([e], false);
          }),
      ];

  /// The ⋯ menu: download the rest, mark the current episode or the season
  /// watched (or the season not watched, once it all is).
  List<(String, VoidCallback)> get _menuItems {
    if (_found) return const [];
    final next = _work.next;
    final season = _seasonOnDisk;
    final seasonName =
        _seasons.length > 1 ? Words.season(_currentSeason) : '这一季';
    final allWatched =
        season.isNotEmpty && season.every((e) => (e.progress ?? 0) >= 1);
    final unwatched = [
      for (final e in season)
        if ((e.progress ?? 0) < 1) e
    ];
    return [
      if (_missing) ('下载全部', _downloadAll),
      if (next != null && next.playable && (next.progress ?? 0) < 1)
        ('${Words.episode(next.number)}看过了', () => _mark([next], true)),
      if (unwatched.length > 1)
        ('$seasonName都看过了', () => _mark(unwatched, true)),
      if (allWatched) ('$seasonName标成没看过', () => _mark(season, false)),
    ];
  }

  /// Through `history.mark_watched_batch`, like the agent. The page follows
  /// the library's change; a refusal (no watch record yet) is said briefly.
  Future<void> _mark(List<UiEpisode> episodes, bool watched) async {
    setState(() => _menuOpen = false);
    final done =
        await _shell!.services.actions.markWatched(episodes, watched: watched);
    if (!mounted || done) return;
    _saidTimer?.cancel();
    setState(() => _said = '这几集还没法标记。');
    _saidTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _said = null);
    });
  }

  // —— Debug ——

  @override
  ScrollController get debugScroll => _scroll;

  @override
  void debugSeason(int? season) => setState(() => _season = season);

  @override
  void debugMenu(bool open) => setState(() => _menuOpen = open);

  @override
  void debugOverview(bool open) => setState(() => _overviewOpen = open);

  @override
  void debugSeasons(bool open) => setState(() => _seasonsOpen = open);

  @override
  Future<Map<String, Object?>> debugManage(Map<String, String> p) async {
    final shown = [
      for (final e in _episodes ?? const <UiEpisode>[])
        if (e.season == _currentSeason) e
    ];
    if (p['tileMenu'] case final i?) {
      setState(() => _tileMenu =
          i == 'none' ? null : shown[int.parse(i)].episodeId);
    }
    switch (p['open']) {
      case 'work':
        _openWork(WorkSection.values.byName(p['section'] ?? 'match'));
      case 'episode':
        _openEpisode(shown[int.parse(p['episode'] ?? '0')],
            EpisodeSection.values.byName(p['section'] ?? 'danmaku'));
      case 'none':
        _closeSheets();
    }
    if (p['restore'] == 'true') await _undoRemove();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final sheet = _sheetKey.currentState;
    final rest = {
      for (final e in p.entries)
        if (!const {'op', 'open', 'episode', 'tileMenu', 'restore'}
                .contains(e.key) &&
            !(e.key == 'section' && p['open'] != null))
          e.key: e.value
    };
    if (sheet is ManageSheetDebug && rest.isNotEmpty) {
      await (sheet as ManageSheetDebug).debugDo(rest);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return {
      ...debugStatus(),
      if (_sheetKey.currentState case final ManageSheetDebug s)
        'sheet': s.debugStatus(),
    };
  }

  @override
  Map<String, Object?> debugStatus() => {
        'work': _work.title,
        'episodes': _episodes?.length,
        'season': _currentSeason,
        'seasons': _seasons,
        'scroll': _scroll.hasClients ? _scroll.offset : null,
        'maxScroll':
            _scroll.hasClients ? _scroll.position.maxScrollExtent : null,
        'docked': _dock.value,
        'flies': _flies,
        'menu': _menuOpen,
        'menuItems': [
          for (final (label, _) in [..._menuItems, ..._manageItems]) label
        ],
        'tileMenu': _tileMenu,
        'removed': _removed != null,
        'found': _found,
        'note': _said,
      };

  // —— Building ——

  @override
  Widget build(BuildContext context) {
    final reduced = NextMotion.reduced(context);
    final content = _flies ? _content : kAlwaysCompleteAnimation;
    return Listener(
      onPointerDown: (e) {
        if (e.buttons & kBackMouseButton != 0) Navigator.of(context).maybePop();
      },
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final copyTop = (size.height / 6).clamp(120.0, 160.0);
        final column = _column(size);
        final titleTop = copyTop +
            (_original == null ? 0 : 18) +
            WorkTitle.marginsOf(_work).top;
        return Stack(fit: StackFit.expand, children: [
          RepaintBoundary(
            child: DetailBackdrop(
              image: _work.artwork.backdrop ?? _work.artwork.poster,
              soft: _work.artwork.backdrop == null,
              tint: _work.artwork.tint,
              size: size,
              scroll: _scroll,
              route: _route!,
              flight: _flight,
              flies: _flies,
              source: _source,
              parallax: !reduced,
            ),
          ),
          FadeTransition(
            opacity: _removed != null
                ? const AlwaysStoppedAnimation(0.35)
                : content,
            child: IgnorePointer(
              ignoring: _removed != null,
              child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(
                          left: NextMetrics.gutter, top: copyTop),
                      // Loose, so the column is its own width and the title
                      // wraps here as it does where it is painted.
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: _copy(column),
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 48, bottom: 30),
                        child: _episodesBlock(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
          if (_standingPoster(size) case final poster?) poster,
          FadeTransition(
            opacity: _removed != null
                ? const AlwaysStoppedAnimation(0.35)
                : content,
            child: IgnorePointer(
                child: _bar(size, column, titleTop, reduced)),
          ),
          Positioned(
            left: NextMetrics.gutter - 9,
            top: NextMetrics.topBar + 8,
            child: FadeTransition(
              opacity: content,
              child: NextIconButton(
                glyph: NextGlyph.chevronLeft,
                label: '返回',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          if (_menuOpen)
            ..._popover(_menuLink, _menu(), () => _menuOpen = false),
          if (_seasonsOpen)
            ..._popover(_seasonLink, _seasonMenu(), () => _seasonsOpen = false),
          if (_tileMenu case final id?)
            if (_episodes?.where((e) => e.episodeId == id).firstOrNull
                case final e?)
              ..._popover(_tileLinks[id]!, _episodeMenu(e),
                  () => _tileMenu = null,
                  up: true),
          if (_removed != null) _removedBar(),
          if (_sheet() case final sheet?) Positioned.fill(child: sheet),
        ]);
      }),
    );
  }

  /// A work with only a poster (most works found on 发现): the poster
  /// stands on the right, sharp over its own blur, when there is room.
  Widget? _standingPoster(Size size) {
    final poster = _work.artwork.poster;
    if (_work.artwork.backdrop != null || poster == null) return null;
    final height = math.min(size.height * 0.56, 480.0);
    final width = height * 2 / 3;
    final room = size.width - NextMetrics.gutter - 600 - 64;
    if (room < width + 56) return null;
    final content = _flies ? _content : kAlwaysCompleteAnimation;
    return Positioned(
      right: math.max(72.0, (room - width) / 2),
      top: (size.height / 6).clamp(120.0, 160.0) - 8,
      child: AnimatedBuilder(
        animation: _scroll,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _scroll.hasClients ? -_scroll.offset : 0),
          child: child,
        ),
        child: FadeTransition(
          opacity: content,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 60,
                    offset: Offset(0, 24)),
              ],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: PosterArt(poster, tint: _work.artwork.tint),
            ),
          ),
        ),
      ),
    );
  }

  /// The words' column: 600 wide, narrower in a narrow window. The title
  /// is painted apart from the column, so both are given this width.
  static double _column(Size size) =>
      math.max(0.0, math.min(600.0, size.width - NextMetrics.gutter * 2));

  /// The bar scrim and the docking title (not interactive).
  Widget _bar(Size size, double column, double titleTop, bool reduced) =>
      Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 96,
          child: FadeTransition(
            opacity: _docked,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xE608080B), Color(0x0008080B)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: NextMetrics.gutter,
          top: 0,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: column),
            child: DockingTitle(
              scroll: _scroll,
              dock: _docked,
              top: titleTop,
              left: NextMetrics.gutter,
              viewWidth: size.width,
              reduced: reduced,
              child: WorkTitle(work: _work, margins: false),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: NextMetrics.topBar,
          child: Center(
            child: FadeTransition(
              opacity: _barTitle,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: math.max(0, size.width - 640)),
                child: Text(_work.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.serif(16,
                        weight: FontWeight.w700, letterSpacing: 0.6)),
              ),
            ),
          ),
        ),
      ]);

  Widget _copy(double width) {
    final work = _work;
    final original = _original;
    final overview = work.overview;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Leaves with the title when it docks, instead of passing under
          // the top bar's tabs.
          if (original != null)
            FadeTransition(
              opacity: ReverseAnimation(_docked),
              child: SizedBox(
                height: 18,
                child: Text(original,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(13,
                        color: NextColors.p3, letterSpacing: 2.6, height: 1.4)),
              ),
            ),
          // Room for the title, which is painted above the content so it can
          // dock in the top bar.
          Padding(
            padding: WorkTitle.marginsOf(work),
            child: Visibility.maintain(
                visible: false, child: WorkTitle(work: work, margins: false)),
          ),
          MetaLine(work, allRatings: true, studio: true, genres: false),
          if (overview != null && overview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Overview(
                text: overview,
                open: _overviewOpen,
                onToggle: () => setState(() => _overviewOpen = !_overviewOpen),
              ),
            ),
          const SizedBox(height: 26),
          _actions(),
        ],
      ),
    );
  }

  Widget _actions() {
    final shell = _shell!;
    final work = _work;
    final next = work.next;
    final episodes = _episodes;
    final started = episodes != null
        ? episodes.any((e) => (e.progress ?? 0) > 0)
        : (next?.progress ?? 0) > 0;
    final menu = [..._menuItems, ..._manageItems];
    final row = Row(children: [
      if (_found) ...[
        NextButton(label: '让 Nipa 准备', onTap: _prepare),
        const SizedBox(width: 12),
      ] else if (next != null && next.playable) ...[
        PlayButton(
          label: started ? '继续 ${Words.episode(next.number)}' : '播放',
          onTap: () => shell.play(work, episode: next),
        ),
        const SizedBox(width: 12),
      ],
      NextButton.ghost(
        label: '问 Nipa',
        leading: const NipaAvatar(size: 20),
        onTap: () => shell.openChat(about: work),
      ),
      CollectionButton(work: work),
      if (menu.isNotEmpty) ...[
        const SizedBox(width: 12),
        CompositedTransformTarget(
          link: _menuLink,
          child: RoundGhostButton(
            label: '更多',
            onTap: () => setState(() => _menuOpen = !_menuOpen),
            child: Text('⋯',
                style: NextText.sans(15,
                    weight: FontWeight.w600, color: NextColors.paper)),
          ),
        ),
      ],
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: _said == null
              ? const SizedBox(height: 0)
              : Padding(
                  padding: const EdgeInsets.only(top: 12, left: 4),
                  child: Text(_said!,
                      style: NextText.sans(13, color: NextColors.p2)),
                ),
        ),
      ],
    );
  }

  Widget _menu() {
    final watch = _menuItems, manage = _manageItems;
    return MenuPanel(width: 188, children: [
      for (final (label, onTap) in watch) MenuItem(label: label, onTap: onTap),
      if (watch.isNotEmpty && manage.isNotEmpty) const _MenuLine(),
      for (final (label, onTap) in manage) MenuItem(label: label, onTap: onTap),
    ]);
  }

  Widget _episodeMenu(UiEpisode e) {
    final items = _episodeItems(e);
    return MenuPanel(width: 168, children: [
      for (final (i, (label, onTap)) in items.indexed) ...[
        if (i == 3) const _MenuLine(),
        MenuItem(label: label, onTap: onTap),
      ],
    ]);
  }

  /// The open sheet, over the page.
  Widget? _sheet() {
    final manage = _manage;
    if (manage == null) return null;
    if (_workSheet case final section?) {
      return ManageLayer(
        key: const ValueKey('work-sheet'),
        onClose: _closeSheets,
        child: WorkManageSheet(
          key: _sheetKey,
          work: _work,
          manage: manage,
          section: section,
          revision: _revision,
          onClose: _closeSheets,
          onChanged: _load,
          onReplaced: _replaced,
          onRemoved: _removedWork,
        ),
      );
    }
    if (_episodeSheet case (final episode, final section)) {
      final shell = _shell!;
      return ManageLayer(
        key: const ValueKey('episode-sheet'),
        onClose: _closeSheets,
        child: EpisodeManageSheet(
          key: _sheetKey,
          work: _work,
          episode: episode,
          manage: manage,
          section: section,
          revision: _revision,
          onClose: _closeSheets,
          onChanged: _load,
          onBlockWords: () {
            _closeSheets();
            shell.openSettings(
                section: SettingsSection.danmaku, key: 'danmaku.blockWords');
          },
          onEpisodes: () => _openWork(WorkSection.episodes),
        ),
      );
    }
    return null;
  }

  /// Taken out of the library: a quiet bar with the way back.
  Widget _removedBar() => Positioned(
        left: 0,
        right: 0,
        bottom: 36,
        child: Center(
          child: Glass(
            radius: BorderRadius.circular(24),
            padding: const EdgeInsets.fromLTRB(22, 8, 8, 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('已从片库移除',
                  style: NextText.sans(13.5, color: NextColors.p2)),
              const SizedBox(width: 16),
              NextButton(label: '撤回', onTap: _undoRemove),
            ]),
          ),
        ),
      );

  Widget _seasonMenu() {
    final current = _currentSeason;
    return MenuPanel(width: 148, children: [
      for (final s in _seasons)
        MenuItem(
          label: Words.season(s),
          selected: s == current,
          onTap: () => setState(() {
            _season = s;
            _seasonsOpen = false;
          }),
        ),
    ]);
  }

  /// A menu under [link]'s target; a click outside or Esc closes it.
  List<Widget> _popover(LayerLink link, Widget menu, VoidCallback close,
          {bool up = false}) =>
      [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(close),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: link,
            targetAnchor: up ? Alignment.topRight : Alignment.bottomLeft,
            followerAnchor: up ? Alignment.bottomRight : Alignment.topLeft,
            offset: Offset(0, up ? -10 : 10),
            child: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  setState(close);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: _PopIn(child: menu),
            ),
          ),
        ),
      ];

  Widget _episodesBlock() {
    final episodes = _episodes;
    if (episodes == null || episodes.isEmpty) return const SizedBox.shrink();
    final shell = _shell!;
    final seasons = _seasons;
    final season = _currentSeason;
    final shown = [
      for (final e in episodes)
        if (e.season == season) e
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: NextMetrics.gutter),
          child: CompositedTransformTarget(
            link: _seasonLink,
            child: SeasonHeader(
              season: season,
              onTap: seasons.length > 1
                  ? () => setState(() => _seasonsOpen = !_seasonsOpen)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 14),
        EpisodeRow(
          key: ValueKey('${_work.workId}/$season'),
          work: _work,
          episodes: shown,
          currentId: _work.next?.episodeId,
          onPlay: (episode) => shell.play(_work, episode: episode),
          moreLink: _manage == null
              ? null
              : (e) => _tileLinks[e.episodeId] ??= LayerLink(),
          onMore: _manage == null
              ? null
              : (e) => setState(() => _tileMenu =
                  _tileMenu == e.episodeId ? null : e.episodeId),
          menuFor: _tileMenu,
        ),
      ],
    );
  }
}

/// Menus fade in from 0.97, like the shell's popovers.
class _PopIn extends StatelessWidget {
  const _PopIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(
              scale: 0.97 + 0.03 * t,
              alignment: Alignment.topLeft,
              child: child),
        ),
        child: child,
      );
}

/// Two lines of overview with “更多” at the end of the second; open, the
/// whole text with “收起”.
class Overview extends StatefulWidget {
  const Overview(
      {super.key,
      required this.text,
      required this.open,
      required this.onToggle});
  final String text;
  final bool open;
  final VoidCallback onToggle;

  @override
  State<Overview> createState() => _OverviewState();
}

class _OverviewState extends State<Overview> {
  late final _tap = TapGestureRecognizer()..onTap = () => widget.onToggle();

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  static final _style = NextText.sans(14.5, color: NextColors.p2, height: 1.75);
  static final _link = NextText.sans(14.5,
      color: NextColors.paper, weight: FontWeight.w600, height: 1.75);

  bool _fits(String text, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _style),
      maxLines: 2,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    return fits;
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, 520.0);
        final text = widget.text;
        Widget body;
        if (_fits(text, width)) {
          body = Text(text, style: _style);
        } else if (widget.open) {
          body = Text.rich(TextSpan(children: [
            TextSpan(text: text, style: _style),
            TextSpan(text: '  收起', style: _link, recognizer: _tap),
          ]));
        } else {
          // The longest start that leaves room for “… 更多” in two lines.
          final chars = text.characters.toList();
          var lo = 0, hi = chars.length;
          while (lo < hi) {
            final mid = (lo + hi + 1) ~/ 2;
            if (_fits('${chars.take(mid).join().trimRight()}…  更多', width)) {
              lo = mid;
            } else {
              hi = mid - 1;
            }
          }
          body = Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '${chars.take(lo).join().trimRight()}…  ',
                  style: _style),
              TextSpan(text: '更多', style: _link, recognizer: _tap),
            ]),
            maxLines: 2,
          );
        }
        return AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: NextMotion.ease,
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: body),
        );
      });
}

/// A hairline between a menu's parts.
class _MenuLine extends StatelessWidget {
  const _MenuLine();

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        color: NextColors.line,
      );
}
