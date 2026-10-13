import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../ui_data/ui_data.dart';
import '../conversation/chat_port.dart';
import '../conversation/chat_context.dart';
import '../data/discover.dart';
import '../data/ui_actions.dart';

/// Development-only data for screenshots and experiments, built from the
/// concept's TMDB sample set. Never used by production code paths (see
/// `NextUiDev`).
final class FakeWorld implements NextUiData, NextUiActions, NextDiscoverData {
  FakeWorld._(this.dir, this._meta, this._found,
      {required bool tasks, int? followupAfter}) {
    if (tasks) {
      _tasks['fake-task-frieren'] = _FakeTask(
          'fake-task-frieren', '葬送的芙莉莲', sample('frieren').artwork, 0.47);
      _helpers.add(_FakeHelper('fake-helper-dungeon', '补全《迷宫饭》的弹幕',
          'fake-thread-weekend', DateTime.now().subtract(const Duration(minutes: 2))));
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
    _followupAfter = followupAfter;
  }

  static FakeWorld? load(String dir, {bool tasks = true, int? followupAfter}) {
    final file = File('$dir/meta.json');
    if (!file.existsSync()) return null;
    final meta = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    // Works the library does not have, for the 发现 page (posters only).
    final found = File('$dir/discover/meta.json');
    return FakeWorld._(
        dir,
        meta,
        found.existsSync()
            ? jsonDecode(found.readAsStringSync()) as Map<String, dynamic>
            : const {},
        tasks: tasks,
        followupAfter: followupAfter);
  }

  final String dir;
  final Map<String, dynamic> _meta;
  final Map<String, dynamic> _found;
  final _changes = StreamController<void>.broadcast();
  final _taskStream = StreamController<List<UiTask>>.broadcast();
  final _tasks = <String, _FakeTask>{};

  /// Helpers Nipa sent off, by the scripted world.
  final _helpers = <_FakeHelper>[];
  Timer? _ticker;
  int? _followupAfter;

  static const _continueAt = <String, (int, double?)>{
    'kusuriya': (31, 0.62),
    'oshinoko': (14, 0.28),
    'dungeon': (13, null),
    'bocchi': (9, 0.8),
    'edgerunners': (6, 0.45),
  };

  /// The sample a sentence names, by title or a recognisable short name.
  String? _named(String text) {
    const aliases = {'孤独摇滚': 'bocchi', '芙莉莲': 'frieren', '迷宫饭': 'dungeon'};
    for (final e in aliases.entries) {
      if (text.contains(e.key)) return e.value;
    }
    for (final entry in [..._meta.entries, ..._found.entries]) {
      final title = (entry.value as Map)['title'] as String;
      if (text.contains(title)) return entry.key;
    }
    return null;
  }

  /// Cards revealed per turn by the scripted conversation.
  final _cards = <String, List<UiCard>>{};

  static const _overrides = <String, Map<String, Object>>{
    'frieren': {
      'genres': ['奇幻', '冒险'],
      'episodes': 28,
      'overview':
          '打倒魔王之后，“那之后”的故事。活了上千年的精灵魔法使，重新走一遍和同伴们走过的路，慢慢明白人类为什么把短短十年看得那么重。',
    },
  };

  static const _genreNames = {
    '动作冒险': '冒险',
    'Sci-Fi & Fantasy': '奇幻',
    'War & Politics': '战争',
  };

  /// Second ratings, as the detail page shows them side by side.
  static const _douban = {
    'frieren': 9.2,
    'bocchi': 9.5,
    'kusuriya': 8.9,
    'dungeon': 9.0,
    'violet': 8.7,
  };

  /// Watch progress per episode number; the first unfinished one is next.
  final _watched = <String, Map<int, double>>{
    'frieren': {1: 1, 2: 1, 3: 0.49},
    'dungeon': {for (var n = 1; n <= 13; n++) n: 1.0},
  };

  /// Short reactions viewers left, drifting over the hero. Most works have
  /// none, so the sky stays empty for them.
  static const _danmaku = {
    'frieren': ['画面好美', '音乐好好听', '一起看', '好治愈', '这段好温柔', '名场面'],
    'bocchi': ['好燃', '笑死', '一起看'],
    'violet': ['好哭', '画面好美'],
  };

  static const _tints = {
    'frieren': 0xFF3C5A6E,
    'bocchi': 0xFF6E3C55,
    'kusuriya': 0xFF2E3B4E,
    'dungeon': 0xFF5A4630,
    'oshinoko': 0xFF283A78,
    'spyfamily': 0xFF6E5A3C,
    'violet': 0xFF4A5A6E,
    'lycoris': 0xFF6E3C3C,
    'changan': 0xFF4E3A2A,
    'edgerunners': 0xFF2A5A6E,
    'sintel': 0xFF3A4A3A,
  };

  UiWork sample(String key, {UiEpisode? next}) {
    // A work only found on 发现: what discovery knows of it.
    if (!_meta.containsKey(key)) return _discovered(key)!.work;
    final m = _meta[key] as Map<String, dynamic>;
    final o = _overrides[key] ?? const {};
    String? file(String field) => m[field] == null ? null : '$dir/${m[field]}';
    final genres = (o['genres'] as List<String>?) ??
        [
          for (final g in (m['genres'] as List).cast<String>())
            _genreNames[g] ?? g
        ];
    return UiWork(
      workId: 'fake:$key',
      title: m['title'] as String,
      originalTitle: m['original'] as String?,
      year: int.tryParse('${m['year'] ?? ''}'),
      genres: genres,
      episodeCount: (o['episodes'] as int?) ?? m['episodes'] as int?,
      studio: m['studio'] as String?,
      overview: (o['overview'] as String?) ?? m['overview'] as String?,
      ratings: [
        if (m['rating'] != null)
          UiRating('TMDB', (m['rating'] as num).toDouble()),
        if (_douban[key] case final douban?) UiRating('豆瓣', douban),
      ],
      artwork: UiArtwork(
        backdrop: file('backdrop'),
        poster: file('poster'),
        logo: file('logo'),
        tint: _tints[key],
      ),
      next: next ?? _episode(key, 1),
      danmaku: _danmaku[key] ?? const [],
    );
  }

  UiEpisode _episode(String key, int n,
      {double? progress, int season = 1, int? number}) {
    final eps = (_meta[key]['eps'] as List?)?.cast<Map<String, dynamic>>();
    final e = eps?.where((e) => e['n'] == n).firstOrNull;
    return UiEpisode(
      episodeId: 'fake:$key:$n',
      workId: 'fake:$key',
      number: number ?? n,
      season: season,
      title: e?['name'] as String?,
      runtime: Duration(minutes: (e?['runtime'] as int?) ?? 24),
      still: e?['still'] == null ? null : '$dir/${e!['still']}',
      progress: progress,
      heat: _heat(key, n),
      // Episodes with a still stand for the ones on disk.
      playable: eps == null || e != null,
    );
  }

  /// A plausible danmaku density: a few peaks over a quiet floor.
  static List<double> _heat(String key, int n) {
    final random = math.Random(key.hashCode * 31 + n);
    final peaks = [
      for (var i = 0; i < 4; i++)
        (
          random.nextDouble() * 60,
          3 + random.nextDouble() * 6,
          0.4 + random.nextDouble() * 0.6
        )
    ];
    final raw = [
      for (var i = 0; i < 60; i++)
        0.15 +
            0.1 * random.nextDouble() +
            peaks.fold<double>(
                0,
                (sum, p) =>
                    sum +
                    p.$3 * math.exp(-math.pow(i - p.$1, 2) / (2 * p.$2 * p.$2)))
    ];
    final top = raw.reduce(math.max);
    return [for (final v in raw) v / top];
  }

  /// All episodes, seasons split evenly where the sample has several.
  List<UiEpisode> _episodesOf(String key) {
    final m = _meta[key] as Map<String, dynamic>;
    final total = (_overrides[key]?['episodes'] as int?) ??
        (m['episodes'] as int?) ??
        (m['eps'] as List?)?.length ??
        1;
    final seasons = (m['seasons'] as int?) ?? 1;
    final perSeason = (total / seasons).ceil();
    final watched = _watched[key] ?? _continued(key);
    return [
      for (var n = 1; n <= total; n++)
        _episode(key, n,
            progress: watched[n],
            season: (n - 1) ~/ perSeason + 1,
            number: (n - 1) % perSeason + 1)
    ];
  }

  /// Where “继续观看” left off: every episode before it watched.
  static Map<int, double> _continued(String key) {
    final at = _continueAt[key];
    if (at == null) return const {};
    final (n, p) = at;
    return {for (var i = 1; i < n; i++) i: 1.0, if (p != null) n: p};
  }

  /// The detail's view of a work: where watching continues.
  UiWork _detailed(String key) {
    final episodes = _episodesOf(key);
    return sample(key,
        next: episodes.where((e) => (e.progress ?? 0) < 1).firstOrNull);
  }

  UiShelfItem _continue(String key, int ep, double? progress, String caption,
      {String? badge}) {
    final episode = _episode(key, ep, progress: progress);
    return UiShelfItem(sample(key, next: episode),
        episode: episode, caption: caption, badge: badge);
  }

  /// An episode out today, not on disk yet.
  UiShelfItem _airing(String key, int ep, String caption) {
    final e = _episode(key, ep);
    final episode = UiEpisode(
        episodeId: e.episodeId,
        workId: e.workId,
        number: e.number,
        season: e.season,
        title: e.title,
        runtime: e.runtime,
        heat: e.heat);
    return UiShelfItem(sample(key, next: episode),
        episode: episode, caption: caption);
  }

  @override
  Future<UiHome> home() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return UiHome(
      hero: UiHero(sample('frieren'), note: '准备好了，第一集随时可以看。'),
      shelves: [
        UiShelf(
          id: 'continue',
          title: '继续观看',
          kind: UiShelfKind.continueWatching,
          items: [
            _continue('kusuriya', 31, 0.62, '第 31 集 · 剩 9 分钟'),
            _continue('oshinoko', 14, 0.28, '第 14 集 · 剩 17 分钟'),
            _continue('dungeon', 13, null, '第 13 集', badge: '新'),
            _continue('bocchi', 9, 0.8, '第 9 集 · 剩 4 分钟'),
            _continue('edgerunners', 6, 0.45, '第 6 集'),
          ],
        ),
        UiShelf(
          id: 'airing',
          title: '今天更新',
          kind: UiShelfKind.airing,
          items: [
            _airing('kusuriya', 32, '第 32 集 · 今天 23:00'),
            _airing('oshinoko', 15, '第 15 集 · 今天 23:30'),
            _airing('dungeon', 14, '第 14 集 · 今天'),
          ],
        ),
        UiShelf(
          id: 'tonight',
          title: '适合今晚',
          kind: UiShelfKind.agent,
          items: [
            UiShelfItem(sample('spyfamily'), caption: '每集都能单独看'),
            UiShelfItem(sample('violet'), caption: '想安静一会儿的时候'),
            UiShelfItem(sample('lycoris'), caption: '十三集，一个周末'),
            UiShelfItem(sample('changan'), caption: '一集一个时辰'),
            UiShelfItem(sample('bocchi'), caption: '还差最后四集'),
          ],
        ),
        UiShelf(
          id: 'recent',
          title: '最近添加',
          kind: UiShelfKind.recent,
          items: [
            UiShelfItem(sample('frieren'), caption: '第 1 集可以看了'),
            UiShelfItem(sample('sintel'), caption: '电影'),
            UiShelfItem(sample('changan')),
            UiShelfItem(sample('violet')),
            UiShelfItem(sample('lycoris')),
          ],
        ),
      ],
    );
  }

  @override
  Future<List<UiWork>> library() async =>
      [for (final key in _meta.keys) sample(key)];

  @override
  Future<UiWork?> work(String workId) async {
    final key = workId.startsWith('fake:') ? workId.substring(5) : workId;
    return _meta.containsKey(key) ? _detailed(key) : null;
  }

  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async {
    final key = workId.startsWith('fake:') ? workId.substring(5) : workId;
    if (!_meta.containsKey(key)) return const [];
    return [
      for (final e in _episodesOf(key))
        if (season == null || e.season == season) e
    ];
  }

  /// Cards whose state moves (the preparation follows the fake download).
  final _liveCards = <String, List<UiCard> Function()>{};

  @override
  Future<List<UiCard>> cards({required String threadId, String? turnId}) async {
    if (turnId != null && _liveCards.containsKey(turnId)) {
      return _liveCards[turnId]!();
    }
    if (turnId != null && _cards.containsKey(turnId)) return _cards[turnId]!;
    if (_cards.containsKey(threadId)) return _cards[threadId]!;
    // A real chat host with scripted data: every turn shows three picks.
    if (!threadId.startsWith('fake-')) return _picks();
    return const [];
  }

  List<UiCard> _picks() => [
        UiCandidatesCard([
          UiCandidate(
              sample('bocchi', next: _episode('bocchi', 9, progress: 0.8)),
              reason: '接着看第 9 集'),
          UiCandidate(sample('spyfamily'), reason: '每集都能单独看'),
          UiCandidate(sample('dungeon', next: _episode('dungeon', 13)),
              reason: '刚更新了第 13 集'),
        ])
      ];

  List<UiCard> _preparation(String key, double progress,
          {String version = '简中内嵌 · 1080p'}) =>
      [
        UiWorkCard(sample(key)),
        UiPreparationCard(
          '正在准备',
          [
            const UiStep('找到作品', UiStepState.done),
            UiStep('选好版本', UiStepState.done, detail: version),
            if (progress < 1)
              UiStep('下载', UiStepState.running,
                  detail: '${(progress * 100).round()}% · '
                      '还要 ${((1 - progress) * 380 / 60).ceil()} 分钟',
                  progress: progress)
            else
              const UiStep('下载', UiStepState.done),
            UiStep('补上弹幕',
                progress < 1 ? UiStepState.waiting : UiStepState.running),
          ],
          work: sample(key),
        ),
      ];

  /// A download the scripted conversation adds; its card follows it.
  String _startTask(String key) {
    final id = 'fake-task-$key';
    _tasks.putIfAbsent(
        id, () => _FakeTask(id, sample(key).title, sample(key).artwork, 0.02));
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _taskStream.add(_taskList());
    return id;
  }

  double _progressOf(String taskId) => _tasks[taskId]?.progress ?? 1;

  void reveal(String key, List<UiCard> cards) {
    _cards[key] = cards;
    _changes.add(null);
  }

  void revealLive(String key, List<UiCard> Function() cards) {
    _liveCards[key] = cards;
    _changes.add(null);
  }

  /// The download behind the scripted preparation.
  double get _frierenProgress => _progressOf('fake-task-frieren');

  // —— Tasks ——

  @override
  Stream<List<UiTask>> tasks() async* {
    yield _taskList();
    yield* _taskStream.stream;
  }

  List<UiTask> _taskList() => [
        for (final t in _tasks.values) t.view,
        for (final h in _helpers) h.view,
      ];

  void _tick() {
    var changed = false;
    for (final h in _helpers) {
      if (h.tick()) changed = true;
    }
    for (final t in _tasks.values) {
      if (t.state == UiTaskState.running && t.progress < 1) {
        t.progress = (t.progress + 0.004).clamp(0, 1);
        changed = true;
      }
    }
    if (changed) {
      _taskStream.add(_taskList());
      // Live cards follow the download, a little less often than the ring.
      if (_liveCards.isNotEmpty && ++_ticks % 3 == 0) _changes.add(null);
    }
  }

  int _ticks = 0;

  @override
  Future<void> pauseTask(String taskId) async {
    _tasks[taskId]?.state = UiTaskState.paused;
    _taskStream.add(_taskList());
  }

  @override
  Future<void> resumeTask(String taskId) async {
    _tasks[taskId]?.state = UiTaskState.running;
    _taskStream.add(_taskList());
  }

  @override
  Future<void> cancelTask(String taskId) async {
    for (final h in _helpers) {
      if (h.id == taskId) h.cancel();
    }
    _tasks.remove(taskId);
    _taskStream.add(_taskList());
  }

  @override
  Future<void> play(UiWork work, {UiEpisode? episode}) async {
    debugPrint(
        '[NextUi dev] play ${work.title} ${episode?.number ?? work.next?.number}');
  }

  @override
  Future<bool> markWatched(List<UiEpisode> episodes,
      {required bool watched}) async {
    for (final e in episodes) {
      final key = e.workId.substring(5);
      final n = int.parse(e.episodeId.split(':').last);
      final marks = _watched[key] ??= {..._continued(key)};
      if (watched) {
        marks[n] = 1;
      } else {
        marks.remove(n);
      }
    }
    _changes.add(null);
    return true;
  }

  @override
  Future<void> login(String provider) async =>
      debugPrint('[NextUi dev] login $provider');

  // —— 发现 ——

  /// Each weekday's new series, library works among them.
  static const _calendar = <int, List<String>>{
    1: ['kusuriya', 'ranma', 'kaiju8', 'dungeon', 'shoshimin', 'yurucamp'],
    2: ['makeine', 'bokuyaba', 'violet', 'kamuy'],
    3: ['girlsband', 'mushoku', 'lycoris'],
    4: ['dandadan', 'spyfamily', 'bluelock', 'jujutsu'],
    5: ['frieren', 'kimetsu', 'chainsaw'],
    6: ['oshinoko', 'bocchi', 'edgerunners'],
    0: ['changan', 'yurucamp', 'kamuy'],
  };

  static const _rankings = [
    ('弹弹play', '本周热播', ['dandadan', 'frieren', 'kusuriya', 'kaiju8',
      'makeine', 'dungeon', 'oshinoko', 'ranma', 'girlsband', 'chainsaw']),
    ('弹弹play', '本周飙升', ['shoshimin', 'ranma', 'bokuyaba', 'makeine',
      'girlsband', 'kamuy', 'yurucamp', 'dandadan']),
    ('弹弹play', '本季新番', ['dandadan', 'ranma', 'kaiju8', 'makeine',
      'shoshimin', 'dungeon', 'kusuriya', 'girlsband']),
    ('Bangumi', '高分', ['frieren', 'bocchi', 'violet', 'kimetsu', 'mushoku',
      'jujutsu', 'bokuyaba', 'kamuy', 'chainsaw', 'changan']),
  ];

  static const _followed = {'kusuriya', 'oshinoko', 'dungeon', 'bocchi',
    'edgerunners', 'frieren'};

  UiFound? _discovered(String key) {
    if (_meta.containsKey(key)) {
      return UiFound(sample(key), followed: _followed.contains(key));
    }
    final m = _found[key] as Map<String, dynamic>?;
    if (m == null) return null;
    return UiFound(UiWork(
      workId: Found.id('fake', key),
      title: m['title'] as String,
      originalTitle: m['original'] as String?,
      year: int.tryParse('${m['year'] ?? ''}'),
      ratings: [
        if (m['rating'] case final num r) UiRating('弹弹play', r.toDouble())
      ],
      artwork: UiArtwork(poster: '$dir/${m['poster']}'),
    ));
  }

  @override
  Future<UiDiscover> discover() async {
    await Future<void>.delayed(const Duration(milliseconds: 160));
    List<UiFound> list(List<String> keys) =>
        [
          for (final k in keys)
            if (_discovered(k) case final found?) found
        ];
    return UiDiscover(
      today: DateTime.now().weekday % 7,
      days: {for (final e in _calendar.entries) e.key: list(e.value)},
      rankings: [
        for (final (source, title, keys) in _rankings)
          UiRanking(source: source, title: title, items: list(keys)),
      ],
    );
  }

  @override
  Future<UiWork> details(UiWork work) async {
    await Future<void>.delayed(const Duration(milliseconds: 240));
    final key = work.workId.split(':').last;
    final m = _found[key] as Map<String, dynamic>? ?? const {};
    return UiWork(
      workId: work.workId,
      title: work.title,
      originalTitle: work.originalTitle,
      year: work.year,
      genres: const ['动画'],
      episodeCount: 12,
      overview: m['overview'] as String?,
      ratings: work.ratings,
      artwork: work.artwork,
    );
  }

  @override
  Stream<void> get changes => _changes.stream;

  void dispose() {
    _ticker?.cancel();
    _changes.close();
    _taskStream.close();
  }
}

class _FakeTask {
  _FakeTask(this.id, this.title, this.artwork, this.progress);
  final String id;
  final String title;
  final UiArtwork artwork;
  double progress;
  UiTaskState state = UiTaskState.running;

  UiTask get view => UiTask(
        taskId: id,
        title: title,
        state: state,
        artwork: artwork,
        progress: progress,
        remaining: Duration(seconds: ((1 - progress) * 380).round()),
      );
}


/// One step of a scripted turn: a shell command, what it printed, how long
/// it took and how it ended. A plain string in a script is a thought.
final class _Run {
  const _Run(this.command, this.output,
      {this.ms = 1400, this.exit = 0, this.then});
  final String command;
  final String output;
  final int ms;
  final int exit;

  /// What it changed in the fake world, once it ends.
  final void Function()? then;
}

/// What Nipa does for one thing you said: its steps (thoughts and
/// commands), its reply and the cards it shows; or a question first, and
/// the rest once you answered.
final class _Script {
  const _Script(this.steps, this.reply, {this.cards, this.ask});
  final List<Object> steps;
  final String reply;
  final List<UiCard> Function()? cards;
  final _Ask? ask;
}

final class _Ask {
  const _Ask(this.header, this.question, this.options, this.then);
  final String header;
  final String question;
  final List<String> options;
  final _Script Function(String choice) then;
}

/// A scripted conversation that emits the same display messages as the
/// embedded Codex host (turns, user and agent items, thinking, commands and
/// their output, deltas, liveness every second) and keeps a history like
/// Codex's, so the interface runs one code path. What Nipa does depends on
/// what you say: news about updates, picks for a mood, preparing a work,
/// carrying on with one, a question when it has to choose. The harness's
/// main session has some history from the start, and so do two other
/// conversations.
final class FakeChatPort implements ChatPort {
  FakeChatPort(this.world) {
    if (world._followupAfter case final seconds?) {
      Timer(Duration(seconds: seconds), wake);
    }
    _seed();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _liveness());
  }

  final FakeWorld world;
  final _display = StreamController<ChatEvent>.broadcast();
  final _questions = StreamController<ChatEvent>.broadcast();
  bool _busy = false;
  int _n = 0;
  final _timers = <Timer>[];
  late final Timer _clock;

  static const mainId = 'fake-thread-main';
  String? _main = mainId;
  String? _current = mainId;

  /// Codex's history: thread → meta and turns.
  final _threads = <String, Map<String, dynamic>>{};
  String? _turnThread, _turn;
  DateTime _lastEvent = DateTime.now();

  /// Pretends this much more silence (`stall`), until the next event.
  Duration _stall = Duration.zero;

  @override
  bool get available => true;

  @override
  bool get busy => _busy;

  @override
  bool busyOn(String threadId) => _busy && _turnThread == threadId;

  @override
  Stream<ChatEvent> get display => _display.stream;

  @override
  Stream<ChatEvent> get questions => _questions.stream;

  /// The harness's main session (kept by the host in production) and the
  /// one the host has current.
  @override
  Future<String?> mainThread() async {
    if (_busy) return null;
    _main ??= 'fake-thread-${++_n}';
    _thread(_main!);
    return _current = _main;
  }

  @override
  Future<String?> switchThread(String threadId) async =>
      _busy ? null : _current = threadId;

  static int _seconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  Map<String, dynamic> _thread(String id, {DateTime? at}) =>
      _threads.putIfAbsent(id, () {
        final t = _seconds(at ?? DateTime.now());
        return {
          'id': id,
          'preview': '',
          'createdAt': t,
          'updatedAt': t,
          'turns': <Map<String, dynamic>>[],
        };
      });

  Map<String, dynamic> _record(String threadId, String turn, String said,
      {DateTime? at}) {
    final thread = _thread(threadId, at: at);
    if ((thread['preview'] as String).isEmpty) thread['preview'] = said;
    thread['updatedAt'] = _seconds(at ?? DateTime.now());
    final record = <String, dynamic>{
      'id': turn,
      'status': 'inProgress',
      'startedAt': _seconds(at ?? DateTime.now()),
      'items': <Map<String, dynamic>>[
        {
          'type': 'userMessage',
          'id': 'user-$turn',
          'content': [
            {'type': 'text', 'text': said}
          ],
        }
      ],
    };
    (thread['turns'] as List).add(record);
    return record;
  }

  Map<String, dynamic>? _turnRecord(String threadId, String turn) {
    final turns = (_threads[threadId]?['turns'] as List?) ?? const [];
    for (final t in turns.cast<Map<String, dynamic>>()) {
      if (t['id'] == turn) return t;
    }
    return null;
  }

  /// An item the turn's history keeps (thoughts, commands, steered words).
  void _keep(String threadId, String turn, Map<String, dynamic> item) =>
      (_turnRecord(threadId, turn)?['items'] as List?)?.add(item);

  void _finish(String threadId, String turn, String status,
      {String? itemId, String? reply}) {
    final t = _turnRecord(threadId, turn);
    if (t == null) return;
    t['status'] = status;
    t['durationMs'] ??=
        (_seconds(DateTime.now()) - (t['startedAt'] as int)) * 1000;
    if (reply != null) {
      (t['items'] as List)
          .add({'type': 'agentMessage', 'id': itemId, 'text': reply});
    }
  }

  static Map<String, dynamic> _thought(String id, String text) =>
      {'id': id, 'type': 'reasoning', 'summary': [text]};

  static Map<String, dynamic> _command(String id, _Run run,
          {bool done = true}) =>
      {
        'id': id,
        'type': 'commandExecution',
        'command': "/bin/zsh -lc '${run.command}'",
        'status': done ? (run.exit == 0 ? 'completed' : 'failed') : 'inProgress',
        if (done) 'exitCode': run.exit,
        if (done) 'aggregatedOutput': run.output,
      };

  void _seed() {
    final now = DateTime.now();
    void old(String thread, String said, Duration ago, _Script script) {
      final turn = 'fake-turn-seed-${++_n}';
      final at = now.subtract(ago);
      final record = _record(thread, turn, said, at: at);
      var ms = 2000;
      for (final (i, step) in script.steps.indexed) {
        final id = '$turn-$i';
        if (step is String) {
          _keep(thread, turn, _thought(id, step));
          ms += 2500 + step.length * 60;
        } else if (step is _Run) {
          _keep(thread, turn, _command(id, step));
          ms += step.ms + 600;
        }
      }
      record['durationMs'] = ms + script.reply.length * 60;
      _finish(thread, turn, 'completed',
          itemId: 'msg-$turn', reply: script.reply);
      if (script.cards case final cards?) world.revealLive(turn, cards);
    }

    // Other conversations, opened on purpose.
    old('fake-thread-changan', '长安十二时辰值得看吗', const Duration(days: 6),
        _opinion('changan'));
    old('fake-thread-weekend', '找点适合周末一口气看完的',
        const Duration(days: 3, hours: 2), _recommend('周末'));
    // The main session: where everything goes.
    old(mainId, '迷宫饭更新了吗？', const Duration(days: 1, hours: 5),
        _updates('dungeon'));
    old(mainId, '帮我准备一下《葬送的芙莉莲》，按平时的喜好来',
        const Duration(minutes: 40), _prepareFrierenFirst());
  }

  @override
  Future<ChatEvent> listThreads({String? cursor}) async {
    final list = [
      for (final t in _threads.values)
        if ((t['turns'] as List).isNotEmpty)
          {
            for (final e in t.entries)
              if (e.key != 'turns') e.key: e.value,
            'isMain': t['id'] == _main,
            'isCurrent': t['id'] == _current,
          }
    ]..sort((a, b) => (b['updatedAt'] as int).compareTo(a['updatedAt'] as int));
    return {
      'data': list,
      'mainThreadId': _main,
      'currentThreadId': _current,
      'nextCursor': null
    };
  }

  @override
  Future<ChatEvent> readThread(String threadId) async {
    final t = _threads[threadId];
    if (t == null) throw StateError('no such thread');
    return jsonDecode(jsonEncode(t)) as Map<String, dynamic>;
  }

  @override
  Future<String?> newThread() async {
    if (_busy) return null;
    final id = 'fake-thread-${++_n}';
    _thread(id);
    return _current = id;
  }

  void _at(int ms, void Function() f) =>
      _timers.add(Timer(Duration(milliseconds: ms), f));

  void _emit(String method, Map<String, Object?> params) {
    _lastEvent = DateTime.now();
    _stall = Duration.zero;
    _display.add({'method': method, 'params': params});
  }

  void _liveness() {
    if (_display.isClosed) return;
    final now = DateTime.now();
    _display.add({
      'method': 'host/liveness',
      'params': {
        'turnId': _turn,
        'status': _busy ? 'inProgress' : 'completed',
        'lastEventAgoMs':
            (now.difference(_lastEvent) + _stall).inMilliseconds,
      }
    });
  }

  /// Debug: the running turn has been silent for over three minutes.
  void stall() => _stall = const Duration(minutes: 3, seconds: 1);

  void _begin(String threadId, String turn, String said) {
    _busy = true;
    _turnThread = threadId;
    _turn = turn;
    _record(threadId, turn, said);
    _emit('turn/started', {
      'threadId': threadId,
      'turn': {'id': turn, 'status': 'inProgress'}
    });
    final item = {
      'type': 'userMessage',
      'id': 'user-$turn',
      'content': [
        {'type': 'text', 'text': said}
      ],
    };
    _emit('item/started', {'threadId': threadId, 'turnId': turn, 'item': item});
    _emit(
        'item/completed', {'threadId': threadId, 'turnId': turn, 'item': item});
  }

  void _end(String threadId, String turn, {String? itemId, String? reply}) {
    _busy = false;
    _finish(threadId, turn, 'completed', itemId: itemId, reply: reply);
    _emit('turn/completed', {
      'threadId': threadId,
      'turn': {'id': turn, 'status': 'completed'}
    });
  }

  /// Streams [reply] as message [msg] from [t] ms on; returns when it ends.
  int _say(String threadId, String turn, String msg, String reply, int t) {
    final base = {'threadId': threadId, 'turnId': turn};
    _at(
        t,
        () => _emit('item/started', {
              ...base,
              'item': {'id': msg, 'type': 'agentMessage', 'text': ''}
            }));
    for (var i = 0; i < reply.length; i += 2) {
      t += 55;
      final delta = reply.substring(i, (i + 2).clamp(0, reply.length));
      _at(
          t,
          () => _emit('item/agentMessage/delta',
              {...base, 'itemId': msg, 'delta': delta}));
    }
    t += 200;
    _at(
        t,
        () => _emit('item/completed', {
              ...base,
              'item': {'id': msg, 'type': 'agentMessage', 'text': reply}
            }));
    return t;
  }

  /// Plays [steps] from [t] ms on: a thought streams its summary through
  /// `host/reasoning` (as the host coalesces it), a command starts, prints
  /// and ends. Returns when the last one ends.
  int _work(String threadId, String turn, List<Object> steps, int t,
      {void Function()? beforePresent}) {
    final base = {'threadId': threadId, 'turnId': turn};
    for (final step in steps) {
      final id = '$turn-step-${++_n}';
      if (step is String) {
        _at(
            t,
            () => _emit('item/started', {
                  ...base,
                  'item': {'id': id, 'type': 'reasoning', 'summary': []}
                }));
        final parts = step.split('，');
        for (var i = 0; i < parts.length; i++) {
          t += 420;
          final delta = i < parts.length - 1 ? '${parts[i]}，' : parts[i];
          _at(
              t,
              () => _emit('host/reasoning', {
                    'key': '$id:item/reasoning/summaryTextDelta:0',
                    'delta': delta
                  }));
        }
        t += 250;
        _at(t, () {
          _keep(threadId, turn, _thought(id, step));
          _emit('item/completed', {...base, 'item': _thought(id, step)});
        });
      } else if (step is _Run) {
        final present = step.command.contains('ui.present');
        t += 250;
        _at(
            t,
            () => _emit('item/started',
                {...base, 'item': _command(id, step, done: false)}));
        t += present ? 300 : step.ms;
        _at(t, () {
          if (present) beforePresent?.call();
          step.then?.call();
          _emit('item/commandExecution/outputDelta',
              {...base, 'itemId': id, 'delta': step.output});
          _keep(threadId, turn, _command(id, step));
          _emit('item/completed', {...base, 'item': _command(id, step)});
        });
      }
    }
    return t;
  }

  /// Plays [script] in a running turn from [t] ms on, up to the end of the
  /// turn (or its question).
  void _play(String threadId, String turn, _Script script, int t) {
    final msg = 'fake-msg-${++_n}';
    final worked = _work(threadId, turn, script.steps, t,
        beforePresent: script.cards == null
            ? null
            : () => world.revealLive(turn, script.cards!));
    if (script.ask case final ask?) {
      _ask(threadId, turn, ask, worked + 300);
      return;
    }
    final end = _say(threadId, turn, msg, script.reply, worked + 400);
    _at(end + 150, () => _end(threadId, turn, itemId: msg, reply: script.reply));
  }

  @override
  Future<ChatEvent?> startTurn(String threadId, String text) async {
    if (_busy) return null;
    final turn = 'fake-turn-${++_n}';
    _begin(threadId, turn, text);
    final response = {
      'turn': {'id': turn, 'status': 'inProgress'}
    };
    // “慢慢来”: it starts thinking, then nothing more (“好像没有回应”).
    if (text.contains('慢慢')) {
      _work(threadId, turn, const ['想想周末适合看什么，先看看片库'], 300);
      return response;
    }
    _play(threadId, turn, _scriptFor(text), 300);
    return response;
  }

  // —— What Nipa does, by what you said ——

  static bool _any(String text, List<String> words) =>
      words.any(text.contains);

  static String _call(String action, [Map<String, Object?> args = const {}]) =>
      "./nipa call $action '${jsonEncode(args)}'";

  static _Run _present(List<String> kinds) => _Run(
      _call('ui.present', {
        'cards': [
          for (final k in kinds) {'kind': k}
        ]
      }),
      '{"status":"completed"}');

  static String _ok(Object result) =>
      jsonEncode({'status': 'completed', 'result': result});

  int _fallbacks = 0;

  _Script _scriptFor(String text) {
    final said = ChatContext.strip(text);
    final files = ChatContext.files(text);
    if (files.isNotEmpty) return _dropped(files);
    // From a work's page the work is named in the context, not in your words.
    final fromPage = ChatContext.aboutTitle(text) != null;
    final key = world._named(fromPage ? text : said);
    if (fromPage && key != null) return _about(key, said);
    if (_any(said, ['版本', '选个'])) return _pickVersion(key ?? 'frieren');
    if (_any(said, ['准备', '下载', '下好', '弄一下'])) {
      return key == null ? _prepareWhich() : _prepare(key);
    }
    if (_any(said, ['更新', '新的一集', '出了', '新番', '有什么新'])) {
      return _updates(key);
    }
    if (key != null && _any(said, ['值得', '好看吗', '怎么样', '讲什么'])) {
      return _opinion(key);
    }
    if (key != null) return _continue(key);
    if (_any(said, [
      '推荐', '看什么', '轻松', '无聊', '随便', '今晚', '周末', '下饭', //
      '安静', '治愈', '燃', '刺激', '悬疑', '短', '想看', '来点',
    ])) {
      return _recommend(said);
    }
    if (_any(said, ['谢谢', '多谢', '辛苦'])) {
      return const _Script(['道谢而已，简单回一句'], '不客气，看得开心。');
    }
    if (_any(said, ['你是谁', '能做什么', '你会'])) {
      return const _Script(['介绍一下自己，说说能帮上什么'],
          '我是 Nipa，住在 NipaPlay 里。找片、准备下载、补弹幕、记着你看到哪，这些都可以交给我。');
    }
    if (_any(said, ['算了', '不用了', '不看了'])) {
      return const _Script(['不需要了，就停在这里'], '好，那先这样。想看的时候叫我。');
    }
    if (_any(said, ['你好', '在吗', '嗨', 'hi'])) {
      return _Script([
        '打个招呼，顺便看看有什么能接着看的',
        _Run(_call('history.continue_watching', {'limit': 3}),
            _ok({'items': 3, 'first': '药屋少女的呢喃 第 31 集'})),
      ], '在。《药屋少女的呢喃》第 31 集还剩 9 分钟，接着看？还是想换点别的。');
    }
    const replies = [
      '这个我还没太明白。是想找点看的，还是想准备哪一部？',
      '我先记下了。要不要我从片库里挑几部给你？',
      '能再多说一点吗？比如想看什么类型，或者哪一部。',
    ];
    return _Script([
      '这句话不太像要看什么，先看看 NipaPlay 现在的情况，再问清楚',
      const _Run('./nipa status', '{"ok":true,"library":48,"tasks":1}', ms: 700),
    ], replies[_fallbacks++ % replies.length]);
  }

  /// Files dropped into the conversation: a torrent is looked into, a
  /// picture recognised, a video matched.
  _Script _dropped(List<String> files) {
    final torrent =
        files.where((f) => DroppedFile.kindOf(f) == '种子').firstOrNull;
    if (torrent != null) {
      return _Script([
        '拖进来一个种子，先看看里面是什么',
        _Run(_call('download.preview', {'torrent': torrent}),
            _ok({'files': 1, 'name': '迷宫饭 第14集 1080p 简中', 'size': '612 MB'})),
        '是《迷宫饭》第 14 集，正好是今天更新的那一集',
      ], '种子里是《迷宫饭》第 14 集，1080p 简中内嵌。要我加进下载吗？');
    }
    final image = files.where(DroppedFile.isImage).firstOrNull;
    if (image != null) {
      return _Script([
        '一张截图，看看画面是哪部作品的哪一集',
        _Run('python3 -c "from PIL import Image; print(Image.open(\'$image\').size)"',
            '(1920, 1080)', ms: 500),
        _Run(_call('media.library.search', {'query': '芙莉莲'}),
            _ok({'total': 1, 'first': '葬送的芙莉莲'})),
        '是芙莉莲第 3 集的画面，你那集看到一半',
        _present(['episode']),
      ], '这是《葬送的芙莉莲》第 3 集里的一幕。你那集看到一半，要接着看吗？',
          cards: () => [
                UiEpisodeCard(world.sample('frieren'),
                    world._episode('frieren', 3, progress: 0.49))
              ]);
    }
    return _Script([
      '一个视频文件，对一下它是哪部的哪一集',
      _Run(_call('media.hash.match', {'path': files.first}),
          _ok({'matched': true, 'title': '孤独摇滚！', 'episode': 9})),
    ], '这是《孤独摇滚！》第 9 集，片库里已经有了，你看到还剩 4 分钟。');
  }

  /// Latest episode of the works that have one, and when it came.
  static const _latest = <String, (int, String)>{
    'kusuriya': (32, '今天早上'),
    'dungeon': (13, '昨晚'),
    'oshinoko': (15, '前天'),
  };

  _Script _updates(String? key) {
    if (key == null) {
      return _Script([
        '看看片库里最近进来的新一集，再对一下在追的',
        _Run(_call('media.library.works', {'sort': 'updated', 'limit': 20}),
            _ok({'total': 48, 'updated': 3})),
        _Run(_call('history.continue_watching', {'limit': 10}),
            _ok({'items': 5})),
        '有三部在追的更新了，药屋还没看完上一集，提醒一下',
        _present(['episode', 'episode', 'episode']),
      ],
          '这几天有三部更新：《药屋少女的呢喃》第 32 集今天早上出的，你第 31 集还剩 9 分钟；'
          '《迷宫饭》第 13 集是昨晚；【我推的孩子】第 15 集前天就有了。都在片库里。',
          cards: () => [
                for (final k in _latest.keys)
                  UiEpisodeCard(
                      world.sample(k,
                          next: world._episode(k, _latest[k]!.$1)),
                      world._episode(k, _latest[k]!.$1)),
              ]);
    }
    final title = world.sample(key).title;
    final latest = _latest[key];
    if (latest == null) {
      final count = world.sample(key).episodeCount;
      return _Script([
        '看看《$title》最近有没有新的一集',
        _Run(_call('media.library.work', {'title': title}),
            _ok({'title': title, 'episodes': count, 'updated': null})),
        _present(['work']),
      ],
          '《$title》这阵子没有新的一集${count == null ? '' : '，片库里现有 $count 集'}。',
          cards: () => [UiWorkCard(world.sample(key))]);
    }
    final (n, came) = latest;
    final (next, p) = FakeWorld._continueAt[key] ?? (n, null);
    final left = p == null ? null : (24 * (1 - p)).round();
    return _Script([
      '看看《$title》最近一集是什么时候进片库的，再对一下看到哪了',
      _Run(_call('media.library.work', {'title': title}),
          _ok({'title': title, 'latest': n, 'added': came})),
      _Run(_call('history.read', {'title': title}),
          _ok({'next': next, 'progress': p}), ms: 900),
      _present(['episode']),
    ],
        next >= n
            ? '更新了，第 $n 集$came出的，已经在片库里，正好接着看。'
            : '更新了，第 $n 集$came出的，已经在片库里。你第 $next 集'
                '${left == null ? '还没看' : '还剩 $left 分钟'}，'
                '${next == n - 1 ? '看完正好接上' : '中间还差 ${n - next} 集'}。',
        cards: () => [
              UiEpisodeCard(world.sample(key, next: world._episode(key, n)),
                  world._episode(key, n))
            ]);
  }

  _Script _recommend(String said) {
    UiCandidate pick(String key, String reason, {int? ep, double? p}) =>
        UiCandidate(
            world.sample(key,
                next: ep == null ? null : world._episode(key, ep, progress: p)),
            reason: reason);
    if (_any(said, ['周末', '一口气', '追完'])) {
      return _Script([
        '想一口气看完，找集数少、一个周末能看完的',
        _Run(_call('media.library.works', {'maxEpisodes': 13, 'limit': 30}),
            _ok({'total': 9})),
        '去掉已经看过的，留节奏快的和好哭的各一部，再加一部很短的',
        _Run(_call('history.read', {'works': ['lycoris', 'violet', 'edgerunners']}),
            _ok({'watched': []}), ms: 800),
        _present(['candidates']),
      ],
          '一个周末刚好的三部：《莉可丽丝》十三集，节奏快，每集结尾都想接着看；'
          '《紫罗兰永恒花园》也是十三集，慢一点，很好哭；'
          '《赛博朋克：边缘行者》只有十集，一个下午就够。',
          cards: () => [
                UiCandidatesCard([
                  pick('lycoris', '十三集，节奏快'),
                  pick('violet', '十三集，很好哭'),
                  pick('edgerunners', '十集，一个下午'),
                ])
              ]);
    }
    if (_any(said, ['安静', '治愈', '放松', '哭', '感动'])) {
      return _Script([
        '想安静一会儿，找节奏慢、画面好看的',
        _Run(_call('media.library.works', {'genre': '剧情', 'limit': 30}),
            _ok({'total': 14})),
        '芙莉莲的第一集已经准备好了，正好',
        _present(['candidates']),
      ],
          '想安静一会儿的话，《紫罗兰永恒花园》最合适，一集一个故事。'
          '《葬送的芙莉莲》也慢，第一集已经准备好了。',
          cards: () => [
                UiCandidatesCard([
                  pick('violet', '一集一个故事'),
                  pick('frieren', '第一集准备好了'),
                ])
              ]);
    }
    if (_any(said, ['燃', '刺激', '悬疑', '动作', '烧脑'])) {
      return _Script([
        '要刺激一点的，动作和悬疑都看看',
        _Run(_call('media.library.works', {'genre': '悬疑', 'limit': 20}),
            _ok({'total': 6})),
        _Run(_call('media.library.works', {'genre': '动作冒险', 'limit': 20}),
            _ok({'total': 17})),
        '长安一集一个时辰最停不下来，边缘行者只有十集',
        _present(['candidates']),
      ],
          '要刺激的：《长安十二时辰》一集一个时辰，停不下来；'
          '《赛博朋克：边缘行者》节奏很猛，只有十集；《莉可丽丝》枪战多，但不压抑。',
          cards: () => [
                UiCandidatesCard([
                  pick('changan', '一集一个时辰'),
                  pick('edgerunners', '十集，节奏很猛', ep: 6, p: 0.45),
                  pick('lycoris', '枪战多，不压抑'),
                ])
              ]);
    }
    if (_any(said, ['轻松', '下饭', '搞笑', '开心', '短', '来点'])) {
      return _Script([
        '想要轻松的，看看片库和最近在看的，挑一集不长、不用动脑的',
        _Run(_call('media.library.works', {'genre': '喜剧', 'limit': 50}),
            _ok({'total': 12})),
        _Run(_call('history.continue_watching', {'limit': 10}),
            _ok({'items': 5})),
        _present(['candidates']),
      ],
          '这三部都很轻松，一集二十分钟出头。《孤独摇滚！》你还差最后四集，今晚正好看完。',
          cards: world._picks);
    }
    return _Script([
      '没说想看什么，先看看在追的，再从片库里挑一部换换口味',
      _Run(_call('history.continue_watching', {'limit': 10}),
          _ok({'items': 5})),
      _Run(_call('media.library.works', {'unwatched': true, 'limit': 30}),
          _ok({'total': 21})),
      _present(['candidates']),
    ],
        '先把在追的看了？《药屋少女的呢喃》第 31 集还剩 9 分钟，'
        '【我推的孩子】看到第 14 集。想换口味的话，《间谍过家家》每集都能单独看。',
        cards: () => [
              UiCandidatesCard([
                pick('kusuriya', '第 31 集还剩 9 分钟', ep: 31, p: 0.62),
                pick('oshinoko', '看到第 14 集', ep: 14, p: 0.28),
                pick('spyfamily', '每集都能单独看'),
              ])
            ]);
  }

  /// The first time, before the history starts: how Frieren got prepared.
  _Script _prepareFrierenFirst() => _Script([
        '想准备《葬送的芙莉莲》，平时喜欢简中内嵌的 1080p，先查资料，再找资源',
        _Run(_call('media.metadata.search', {'query': '葬送的芙莉莲'}),
            _ok({'title': '葬送的芙莉莲', 'year': 2023, 'episodes': 28})),
        _Run(_call('download.preview', {'query': '葬送的芙莉莲 1080p 简中内嵌'}),
            _ok({'candidates': 3, 'picked': '简中内嵌 1080p'}), ms: 1800),
        _Run(_call('download.add', {'from': 'preview', 'pick': 0}),
            _ok({'task': '下载 葬送的芙莉莲'})),
        _Run(_call('followup.register', {'when': 'download finished'}),
            _ok({}), ms: 600),
        _present(['work', 'preparation']),
      ], '好，选了简中内嵌的 1080p，已经在下了。下好以后我再看看弹幕够不够，你先忙。',
          cards: () => world._preparation('frieren', world._frierenProgress));

  _Script _prepare(String key) {
    final title = world.sample(key).title;
    final busy = world._tasks['fake-task-$key'];
    if (busy != null) {
      final p = busy.progress;
      return _Script([
        '《$title》之前就在准备了，看看下到哪了',
        _Run(_call('task.list', {'kind': 'download'}),
            _ok({'items': 1, 'progress': (p * 100).round()}), ms: 800),
        _present(['preparation']),
      ],
          p >= 1
              ? '《$title》已经下好了，在补弹幕，马上就能看。'
              : '《$title》已经在下了，${(p * 100).round()}%，'
                  '还要 ${((1 - p) * 380 / 60).ceil()} 分钟。下好以后我来补弹幕。',
          cards: () => world._preparation(key, busy.progress));
    }
    final task = 'fake-task-$key';
    return _Script([
      '想准备《$title》，按平时的喜好，简中内嵌、1080p，先确认是哪一部',
      _Run(_call('media.metadata.search', {'query': title}),
          _ok({'title': title, 'episodes': world.sample(key).episodeCount})),
      _Run(_call('download.preview', {'query': '$title 1080p 简中内嵌'}),
          '{"status":"failed","error":{"code":"no_results"}}',
          ms: 1600, exit: 1),
      '简中内嵌的没找到，放宽一点，繁中或者外挂字幕也行',
      _Run(_call('download.preview', {'query': '$title 1080p'}),
          _ok({'candidates': 2, 'picked': '繁中内嵌 1080p'}), ms: 1800),
      _Run(_call('download.add', {'from': 'preview', 'pick': 0}),
          _ok({'task': '下载 $title'}),
          ms: 2400, then: () => world._startTask(key)),
      _Run(_call('followup.register', {'when': 'download finished'}),
          _ok({}), ms: 600),
      _present(['work', 'preparation']),
    ],
        '简中内嵌的没找到，选了繁中内嵌的 1080p，已经在下了。下好以后我把弹幕补上，到时候叫你。',
        cards: () => world._preparation(key, world._progressOf(task),
            version: '繁中内嵌 · 1080p'));
  }

  /// Which one to prepare, from tonight's shelf.
  _Script _prepareWhich() => _Script([
        '没说准备哪一部，看看 Nipa 摆的书架，问一下',
        _Run(_call('ui.shelves.read', {}), _ok({'shelves': 3}), ms: 700),
      ], '',
          ask: _Ask('作品', '准备哪一部？', const ['间谍过家家', '紫罗兰永恒花园', '莉可丽丝'],
              (choice) => _prepare(world._named(choice) ?? 'spyfamily')));

  _Script _pickVersion(String key) => _Script([
        '要先确定版本，找到两个能用的，问问要哪个',
        _Run(_call('download.preview', {'query': world.sample(key).title}),
            _ok({'candidates': 2})),
      ], '',
          ask: _Ask('版本', '找到两个版本，要哪个？', const ['简中内嵌 1080p', '繁中外挂 4K'],
              (choice) => _Script([
                    '就按$choice，加下载',
                    _Run(_call('download.add', {'from': 'preview', 'pick': choice}),
                        _ok({'task': '下载'})),
                  ], '好，就要$choice。下好了叫你。')));

  _Script _continue(String key) {
    final (n, p) = FakeWorld._continueAt[key] ?? (1, null);
    final title = world.sample(key).title;
    final left = p == null ? null : (24 * (1 - p)).round();
    return _Script([
      '想接着看《$title》，查一下看到第几集',
      _Run(_call('history.continue_watching', {'title': title}),
          _ok({'title': title, 'next': n, 'progress': p})),
      _present(['episode']),
    ],
        left == null
            ? '好，《$title》第 $n 集，接着看。'
            : '好，《$title》第 $n 集，还剩 $left 分钟，从停下的地方接着放。',
        cards: () => [
              UiEpisodeCard(
                  world.sample(key, next: world._episode(key, n, progress: p)),
                  world._episode(key, n, progress: p))
            ]);
  }

  _Script _opinion(String key) {
    final work = world.sample(key);
    final rating = work.ratings.firstOrNull?.value;
    final overview = work.overview ?? '';
    final first = overview.split(RegExp('[。！？]')).first;
    return _Script([
      '说说《${work.title}》适不适合，看看资料和评分',
      _Run(_call('media.metadata.search', {'query': work.title}),
          _ok({'title': work.title, 'rating': rating, 'episodes': work.episodeCount})),
      _present(['work']),
    ],
        '《${work.title}》${rating == null ? '' : '评分 ${rating.toStringAsFixed(1)}，'}'
        '${work.episodeCount == null ? '' : '${work.episodeCount} 集。'}'
        '${first.isEmpty ? '' : '$first。'}想看的话我来准备。',
        cards: () => [UiWorkCard(work)]);
  }

  /// Asked from the work's page.
  _Script _about(String key, String said) {
    if (_any(said, ['准备', '下载'])) return _prepare(key);
    if (_any(said, ['更新', '新的一集'])) return _updates(key);
    if (_any(said, ['讲什么', '值得', '好看', '怎么样'])) return _opinion(key);
    final (n, p) = FakeWorld._continueAt[key] ?? (1, null);
    final work = world.sample(key);
    return _Script([
      '在《${work.title}》的页面上问的，看看这部的资料和看到哪了',
      _Run(_call('media.library.work', {'title': work.title}),
          _ok({'title': work.title, 'next': n})),
      _present(['episode']),
    ],
        '《${work.title}》${work.episodeCount ?? 12} 集，节奏不快，适合慢慢看。'
        '想从第 $n 集接着看的话，点一下就行。',
        cards: () => [
              UiEpisodeCard(
                  world.sample(key, next: world._episode(key, n, progress: p)),
                  world._episode(key, n, progress: p))
            ]);
  }

  _Ask? _asking;
  String? _askThread, _askTurn;

  void _ask(String threadId, String turn, _Ask ask, int at) {
    _asking = ask;
    _askThread = threadId;
    _askTurn = turn;
    _at(
        at,
        () => _questions.add({
              'id': 900 + _n,
              'method': 'item/tool/requestUserInput',
              'params': {
                'threadId': threadId,
                'turnId': turn,
                'questions': [
                  {
                    'id': 'q',
                    'header': ask.header,
                    'question': ask.question,
                    'options': [
                      for (final o in ask.options) {'label': o}
                    ],
                  }
                ],
              },
            }));
  }

  @override
  Future<void> answer(
      Object requestId, Map<String, List<String>> answers) async {
    final ask = _asking, thread = _askThread, turn = _askTurn;
    if (ask == null || thread == null || turn == null) return;
    _asking = null;
    final choice = answers.values.firstOrNull?.firstOrNull ?? '';
    final script = choice.isEmpty
        ? const _Script(['没选，先不动'], '好，先不弄了。想好了再说。')
        : ask.then(choice);
    _play(thread, turn, script, 200);
  }

  /// Nipa wakes up on its own (a follow-up) in the main session, as in
  /// state C.
  void wake() {
    if (_busy) {
      _at(3000, wake);
      return;
    }
    final thread = _main ?? 'fake-followup';
    final turn = 'fake-followup-turn-${++_n}';
    world.reveal(turn, [
      UiPreparationCard(
          '正在准备',
          const [
            UiStep('找到作品', UiStepState.done),
            UiStep('下载', UiStepState.done),
            UiStep('补弹幕', UiStepState.running),
          ],
          work: world.sample('frieren')),
    ]);
    _begin(thread, turn, '[NipaPlay followup fake]\n你登记的后续条件已满足。');
    _play(
        thread,
        turn,
        _Script([
          '芙莉莲下好了，按说好的补弹幕，先看看现有的够不够',
          _Run(_call('danmaku.search', {'title': '葬送的芙莉莲', 'episode': 1}),
              _ok({'sources': 2, 'count': 1840}), ms: 2600),
          _Run(_call('danmaku.fetch', {'episode': 1, 'sources': 'all'}),
              _ok({'added': 3210}), ms: 4200),
        ], '《葬送的芙莉莲》的弹幕补好了，第一集随时可以看。'),
        400);
  }

  @override
  Future<void> steer(String text, {String? threadId}) async {
    final thread = _turnThread, turn = _turn;
    if (!_busy || thread == null || turn == null) return;
    final item = <String, dynamic>{
      'type': 'userMessage',
      'id': 'steer-${++_n}',
      'content': [
        {'type': 'text', 'text': text}
      ],
    };
    _keep(thread, turn, item);
    _emit('item/completed', {'threadId': thread, 'turnId': turn, 'item': item});
  }

  @override
  Future<void> interrupt({String? threadId}) async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    final thread = _turnThread, turn = _turn;
    if (!_busy || thread == null || turn == null) return;
    _busy = false;
    _finish(thread, turn, 'interrupted');
    _emit('turn/completed', {
      'threadId': thread,
      'turn': {'id': turn, 'status': 'interrupted'}
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    _display.close();
    _questions.close();
  }
}

/// A helper at work in its own conversation: what it is doing changes
/// every few seconds; after a while it comes back with a summary.
class _FakeHelper {
  _FakeHelper(this.id, this.title, this.threadId, this.startedAt);
  final String id;
  final String title;
  final String threadId;
  final DateTime startedAt;
  UiTaskState state = UiTaskState.running;
  bool cancelled = false;
  int _ticks = 0;
  static const _doing = ['在找第 3 集的弹幕', '在导入第 4 集', '在对齐第 6 集的时间轴', '在导入第 9 集'];

  String? get _now => state == UiTaskState.running
      ? _doing[(_ticks ~/ 6) % _doing.length]
      : null;

  bool tick() {
    if (state != UiTaskState.running) return false;
    _ticks++;
    if (_ticks >= 90) state = UiTaskState.finished;
    return _ticks % 6 == 0 || state != UiTaskState.running;
  }

  void cancel() {
    if (state != UiTaskState.running) return;
    state = UiTaskState.failed;
    cancelled = true;
  }

  UiTask get view => UiTask(
        taskId: id,
        title: title,
        state: state,
        kind: UiTaskKind.helper,
        startedAt: startedAt,
        currentActivity: _now,
        summary: state == UiTaskState.finished ? '13 集都补上了，共 4120 条。' : null,
        threadId: threadId,
        cancelled: cancelled,
      );
}
