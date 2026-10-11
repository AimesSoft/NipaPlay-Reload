import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/discover.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/shelf.dart';
import '../widgets/words.dart';

/// 发现: this season's new series by weekday (today first), and the
/// rankings by where they come from. Posters open the work's page; a work
/// not in the library offers “让 Nipa 准备” there.
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

/// Handles for `ext.nipaplay.nextui` in lab profiles.
abstract interface class DiscoverDebug {
  void debugChoose({int? day, String? source, int? list});
  Map<String, Object?> debugStatus();
}

class _DiscoverPageState extends State<DiscoverPage> implements DiscoverDebug {
  NextShellController? _shell;
  UiDiscover? _data;
  bool _failed = false;
  DateTime? _loadedAt;

  /// The weekday shown (0 = Sunday); null: today.
  int? _day;
  String? _source;
  int _list = 0;

  /// Coming back after this long reads the calendar and rankings again.
  static const _stale = Duration(minutes: 15);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shell = NextShellScope.of(context);
    final shown = TickerMode.valuesOf(context).enabled;
    final loadedAt = _loadedAt;
    if (shown &&
        (loadedAt == null || DateTime.now().difference(loadedAt) > _stale)) {
      _loadedAt = DateTime.now();
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final data = await _shell!.services.discover.discover();
      if (!mounted) return;
      setState(() {
        _data = data;
        _failed = false;
      });
    } catch (error) {
      debugPrint('[NextUi] discover failed: $error');
      _loadedAt = null;
      if (mounted) setState(() => _failed = true);
    }
  }

  // —— Debug ——

  @override
  void debugChoose({int? day, String? source, int? list}) => setState(() {
        if (day != null) _day = day;
        if (source != null) {
          _source = source;
          _list = 0;
        }
        if (list != null) _list = list;
      });

  @override
  Map<String, Object?> debugStatus() => {
        'loaded': _data != null,
        'failed': _failed,
        'signedOut': _data?.signedOut,
        'today': _data?.today,
        'day': _day ?? _data?.today,
        'calendar': [for (final f in _calendar()) f.work.title],
        'sources': _sources(),
        'source': _currentSource(),
        'list': _ranking()?.title,
        'ranking': [
          for (final f in _ranking()?.items ?? const []) f.work.title
        ],
      };

  // —— What to show ——

  List<UiFound> _calendar() {
    final data = _data;
    if (data == null) return const [];
    return data.days[_day ?? data.today] ?? const [];
  }

  List<String> _sources() => {
        for (final r in _data?.rankings ?? const <UiRanking>[]) r.source
      }.toList();

  String? _currentSource() {
    final sources = _sources();
    return sources.contains(_source) ? _source : sources.firstOrNull;
  }

  List<UiRanking> _lists() => [
        for (final r in _data?.rankings ?? const <UiRanking>[])
          if (r.source == _currentSource()) r
      ];

  UiRanking? _ranking() {
    final lists = _lists();
    if (lists.isEmpty) return null;
    return lists[_list.clamp(0, lists.length - 1)];
  }

  // —— Building ——

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return CustomScrollView(
      key: const PageStorageKey('discover'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              NextMetrics.gutter, NextMetrics.topBar + 40, 56, 32),
          sliver: SliverToBoxAdapter(
            child:
                Text('发现', style: NextText.sans(28, weight: FontWeight.w600)),
          ),
        ),
        if (data == null && _failed)
          _note('现在看不到，过一会儿再来。',
              action:
                  NextButton.ghost(label: '再试一次', height: 38, onTap: _retry))
        else if (data == null)
          const SliverToBoxAdapter(child: SizedBox.shrink())
        else if (data.signedOut)
          _note('登录弹弹play 之后，这里会有新番和排行榜。',
              action: NextButton(
                  label: '登录弹弹play',
                  height: 38,
                  onTap: () => _shell!.services.actions.login('dandanplay')))
        else ...[
          SliverToBoxAdapter(child: _calendarShelf(data)),
          const SliverToBoxAdapter(child: SizedBox(height: 44)),
          if (_ranking() != null)
            SliverToBoxAdapter(child: _rankingShelf(_ranking()!)),
          const SliverToBoxAdapter(child: SizedBox(height: 64)),
        ],
      ],
    );
  }

  void _retry() {
    setState(() => _failed = false);
    _loadedAt = DateTime.now();
    unawaited(_load());
  }

  Widget _note(String text, {required Widget action}) => SliverPadding(
        padding: const EdgeInsets.only(left: NextMetrics.gutter),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: NextText.sans(14.5, color: NextColors.p2)),
              const SizedBox(height: 18),
              action,
            ],
          ),
        ),
      );

  static const _weekdays = [1, 2, 3, 4, 5, 6, 0];
  static const _dayNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

  Widget _calendarShelf(UiDiscover data) {
    final day = _day ?? data.today;
    final shows = _calendar();
    final tabs = _Tabs(
      labels: [
        for (final d in _weekdays) d == data.today ? '今天' : _dayNames[d]
      ],
      selected: _weekdays.indexOf(day),
      onSelect: (i) => setState(() => _day = _weekdays[i]),
    );
    return _Switching(
      id: 'day-$day',
      empty: shows.isEmpty,
      emptyText: '这天没有新番。',
      title: '新番日历',
      trailing: tabs,
      height: _posterHeight + 12 + 22 + 4 + 20,
      count: shows.length,
      builder: (context, i) => _poster(shows[i]),
    );
  }

  Widget _rankingShelf(UiRanking ranking) {
    final sources = _sources();
    final lists = _lists();
    final source = _currentSource();
    final trailing = Row(mainAxisSize: MainAxisSize.min, children: [
      if (sources.length > 1)
        _Tabs(
          labels: sources,
          selected: sources.indexOf(source!),
          onSelect: (i) => setState(() {
            _source = sources[i];
            _list = 0;
          }),
        )
      else
        Text(source!, style: NextText.sans(13.5, color: NextColors.p3)),
      if (lists.isNotEmpty) ...[
        Container(
          width: 1,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 18),
          color: NextColors.line2,
        ),
        if (lists.length > 1)
          _Tabs(
            labels: [for (final l in lists) l.title],
            selected: lists.indexOf(ranking),
            onSelect: (i) => setState(() => _list = i),
            quiet: true,
          )
        else
          Text(ranking.title,
              style: NextText.sans(13,
                  weight: FontWeight.w600, color: NextColors.paper)),
      ],
    ]);
    return _Switching(
      id: '${ranking.source}/${ranking.title}',
      empty: ranking.items.isEmpty,
      emptyText: '这份榜单还空着。',
      title: '排行榜',
      trailing: trailing,
      height: _posterHeight + 12 + 22 + 4 + 20,
      count: ranking.items.length,
      gap: 10,
      builder: (context, i) =>
          _Ranked(rank: i + 1, child: _poster(ranking.items[i])),
    );
  }

  static const _posterWidth = 150.0;
  static const _posterHeight = 225.0;

  Widget _poster(UiFound found) {
    final shell = _shell!;
    final work = found.work;
    return PosterCard(
      workId: work.workId,
      image: work.artwork.poster,
      tint: work.artwork.tint,
      title: work.title,
      reason: found.followed ? '在追' : null,
      width: _posterWidth,
      height: _posterHeight,
      onOpen: () => shell.openWork(work),
      onPlay: !Found.isFound(work) && Words.canPlay(work)
          ? () => shell.play(work)
          : null,
    );
  }
}

/// A shelf whose row changes with its tabs: the new row fades in.
class _Switching extends StatelessWidget {
  const _Switching({
    required this.id,
    required this.empty,
    required this.emptyText,
    required this.title,
    required this.trailing,
    required this.height,
    required this.count,
    required this.builder,
    this.gap = 18,
  });

  final String id;
  final bool empty;
  final String emptyText;
  final String title;
  final Widget trailing;
  final double height;
  final int count;
  final double gap;
  final IndexedWidgetBuilder builder;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [...previous, if (current != null) current],
        ),
        child: KeyedSubtree(
          key: ValueKey(id),
          child: empty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Shelf(
                        title: title,
                        trailing: trailing,
                        height: 0,
                        itemCount: 0,
                        itemBuilder: builder),
                    Padding(
                      padding: const EdgeInsets.only(left: NextMetrics.gutter),
                      child: SizedBox(
                        height: height - 16,
                        child: Text(emptyText,
                            style: NextText.sans(14, color: NextColors.p3)),
                      ),
                    ),
                  ],
                )
              : Shelf(
                  title: title,
                  trailing: trailing,
                  storageKey: 'discover-$id',
                  height: height,
                  gap: gap,
                  itemCount: count,
                  itemBuilder: builder,
                ),
        ),
      );
}

/// Text tabs beside a shelf's title: the chosen one in full white with the
/// crimson dot under it, like the top bar.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.quiet = false,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Second-level tabs: a little smaller.
  final bool quiet;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (final (i, label) in labels.indexed) ...[
            if (i > 0) SizedBox(width: quiet ? 16 : 20),
            Pressable(
              onTap: () => onSelect(i),
              semanticLabel: label,
              pressScale: 0.97,
              builder: (context, hovered) {
                final on = i == selected;
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 160),
                    style: NextText.sans(quiet ? 13 : 14,
                        weight: on ? FontWeight.w600 : FontWeight.w400,
                        color: on
                            ? NextColors.paper
                            : (hovered ? NextColors.p2 : NextColors.p3)),
                    child: Text(label),
                  ),
                  const SizedBox(height: 4),
                  AnimatedOpacity(
                    opacity: on && !quiet ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                          color: NextColors.accent, shape: BoxShape.circle),
                    ),
                  ),
                ]);
              },
            ),
          ],
        ],
      );
}

/// A ranked poster: its place as a big outlined numeral, half behind it.
class _Ranked extends StatelessWidget {
  const _Ranked({required this.rank, required this.child});
  final int rank;
  final Widget child;

  static const _numeral = 58.0;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: _numeral + _DiscoverPageState._posterWidth,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            right: _DiscoverPageState._posterWidth - 18,
            top: _DiscoverPageState._posterHeight - 118,
            child: Text(
              '$rank',
              style: TextStyle(
                fontFamily: NextFonts.num,
                fontFamilyFallback: NextFonts.numFallback,
                fontSize: 124,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -8,
                decoration: TextDecoration.none,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2
                  ..color = rank <= 3 ? NextColors.p2 : NextColors.p4,
              ),
            ),
          ),
          Positioned(left: _numeral, top: 0, child: child),
        ]),
      );
}
