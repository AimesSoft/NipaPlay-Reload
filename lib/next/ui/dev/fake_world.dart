import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../ui_data/ui_data.dart';
import '../conversation/chat_port.dart';
import '../data/ui_actions.dart';

/// Development-only data for screenshots and experiments, built from the
/// concept's TMDB sample set. Never used by production code paths (see
/// `NextUiDev`).
final class FakeWorld implements NextUiData, NextUiActions {
  FakeWorld._(this.dir, this._meta, {required bool tasks, int? followupAfter}) {
    if (tasks) {
      _tasks['fake-task-frieren'] = _FakeTask(
          'fake-task-frieren', '葬送的芙莉莲', sample('frieren').artwork, 0.47);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
    _followupAfter = followupAfter;
  }

  static FakeWorld? load(String dir, {bool tasks = true, int? followupAfter}) {
    final file = File('$dir/meta.json');
    if (!file.existsSync()) return null;
    final meta = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return FakeWorld._(dir, meta, tasks: tasks, followupAfter: followupAfter);
  }

  final String dir;
  final Map<String, dynamic> _meta;
  final _changes = StreamController<void>.broadcast();
  final _taskStream = StreamController<List<UiTask>>.broadcast();
  final _tasks = <String, _FakeTask>{};
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
    for (final key in _meta.keys) {
      final title = (_meta[key] as Map)['title'] as String;
      if (text.contains(title)) return key;
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

  @override
  Future<List<UiCard>> cards({required String threadId, String? turnId}) async {
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

  List<UiCard> _preparation(double progress) => [
        UiWorkCard(sample('frieren')),
        UiPreparationCard(
          '正在准备',
          [
            const UiStep('找到作品', UiStepState.done),
            const UiStep('选好版本', UiStepState.done, detail: '简中内嵌 · 1080p'),
            UiStep('下载', UiStepState.running,
                detail: '${(progress * 100).round()}% · 还要 3 分钟',
                progress: progress),
            const UiStep('补上弹幕', UiStepState.waiting),
          ],
          work: sample('frieren'),
        ),
      ];

  void reveal(String key, List<UiCard> cards) {
    _cards[key] = cards;
    _changes.add(null);
  }

  // —— Tasks ——

  @override
  Stream<List<UiTask>> tasks() async* {
    yield _taskList();
    yield* _taskStream.stream;
  }

  List<UiTask> _taskList() => [for (final t in _tasks.values) t.view];

  void _tick() {
    var changed = false;
    for (final t in _tasks.values) {
      if (t.state == UiTaskState.running && t.progress < 1) {
        t.progress = (t.progress + 0.004).clamp(0, 1);
        changed = true;
      }
    }
    if (changed) _taskStream.add(_taskList());
  }

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
    _tasks.remove(taskId);
    _taskStream.add(_taskList());
  }

  @override
  Future<void> play(UiWork work, {UiEpisode? episode}) async {
    debugPrint(
        '[NextUi dev] play ${work.title} ${episode?.number ?? work.next?.number}');
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

/// A scripted conversation that emits the same display messages as the
/// embedded Codex host, so the interface runs one code path.
final class FakeChatPort implements ChatPort {
  FakeChatPort(this.world) {
    if (world._followupAfter case final seconds?) {
      Timer(Duration(seconds: seconds), wake);
    }
  }

  final FakeWorld world;
  final _display = StreamController<ChatEvent>.broadcast();
  final _questions = StreamController<ChatEvent>.broadcast();
  bool _busy = false;
  int _n = 0;
  final _timers = <Timer>[];

  @override
  bool get available => true;

  @override
  bool get busy => _busy;

  @override
  Stream<ChatEvent> get display => _display.stream;

  @override
  Stream<ChatEvent> get questions => _questions.stream;

  @override
  Future<String?> newThread() async => _busy ? null : 'fake-thread-${++_n}';
  @override
  Future<String?> mainThread() async => _busy ? null : 'fake-main';
  @override
  Future<ChatEvent> listThreads({String? cursor}) async => {
    'data': [{'id': 'fake-main', 'isMain': true}], 'nextCursor': null,
  };
  @override
  Future<String?> switchThread(String threadId) async => _busy ? null : threadId;

  void _at(int ms, void Function() f) =>
      _timers.add(Timer(Duration(milliseconds: ms), f));

  void _emit(String method, Map<String, Object?> params) =>
      _display.add({'method': method, 'params': params});

  @override
  Future<ChatEvent?> startTurn(String threadId, String text) async {
    if (_busy) return null;
    _busy = true;
    final turn = 'fake-turn-${++_n}';
    final msg = 'fake-msg-$_n';
    final tool = 'fake-tool-$_n';
    final String reply;
    final List<UiCard> Function() cards;
    if (text.contains('选')) {
      return _ask(threadId, turn);
    } else if (text.contains('准备') || text.contains('下载')) {
      reply = '好，选了简中内嵌的 1080p，已经在下了。下好以后我再看看弹幕够不够，你先忙。';
      cards = () => world._preparation(0.47);
    } else if (world._named(text) case final key?) {
      final (n, p) = FakeWorld._continueAt[key] ?? (1, null);
      final title = world.sample(key).title;
      reply = '好，《$title》第 $n 集，接着看。';
      cards = () => [
            UiEpisodeCard(
                world.sample(key, next: world._episode(key, n, progress: p)),
                world._episode(key, n, progress: p))
          ];
    } else {
      reply = '这三部都很轻松，一集二十分钟出头。《孤独摇滚！》你还差最后四集，今晚正好看完。';
      cards = world._picks;
    }
    final base = {'threadId': threadId, 'turnId': turn};
    _at(
        0,
        () => _emit('turn/started', {
              'threadId': threadId,
              'turn': {'id': turn, 'status': 'inProgress'}
            }));
    _at(
        900,
        () => _emit('item/started', {
              ...base,
              'item': {'id': tool, 'type': 'commandExecution'}
            }));
    _at(1700, () {
      world.reveal(turn, cards());
      _emit('item/completed', {
        ...base,
        'item': {'id': tool, 'type': 'commandExecution', 'aggregatedOutput': ''}
      });
    });
    var t = 2100;
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
    _at(t + 150, () {
      _busy = false;
      _emit('turn/completed', {
        'threadId': threadId,
        'turn': {'id': turn, 'status': 'completed'}
      });
    });
    return {
      'turn': {'id': turn, 'status': 'inProgress'}
    };
  }

  String? _askThread, _askTurn;

  ChatEvent _ask(String threadId, String turn) {
    _askThread = threadId;
    _askTurn = turn;
    _at(
        0,
        () => _emit('turn/started', {
              'threadId': threadId,
              'turn': {'id': turn, 'status': 'inProgress'}
            }));
    _at(
        1200,
        () => _questions.add({
              'id': 900 + _n,
              'method': 'item/tool/requestUserInput',
              'params': {
                'threadId': threadId,
                'turnId': turn,
                'questions': [
                  {
                    'id': 'version',
                    'header': '版本',
                    'question': '找到两个版本，要哪个？',
                    'options': [
                      {'label': '简中内嵌 1080p'},
                      {'label': '繁中外挂 4K'},
                    ],
                  }
                ],
              },
            }));
    return {
      'turn': {'id': turn, 'status': 'inProgress'}
    };
  }

  @override
  Future<void> answer(
      Object requestId, Map<String, List<String>> answers) async {
    final choice = answers.values.firstOrNull?.firstOrNull ?? '';
    final turn = _askTurn ?? 'fake-turn-answer';
    final threadId = _askThread;
    final reply = '好，就要$choice。下好了叫你。';
    final msg = 'fake-msg-answer-${++_n}';
    final base = {'threadId': threadId, 'turnId': turn};
    _at(
        300,
        () => _emit('item/started', {
              ...base,
              'item': {'id': msg, 'type': 'agentMessage'}
            }));
    for (var i = 0; i < reply.length; i += 2) {
      final delta = reply.substring(i, (i + 2).clamp(0, reply.length));
      _at(
          400 + i * 30,
          () => _emit('item/agentMessage/delta',
              {...base, 'itemId': msg, 'delta': delta}));
    }
    _at(
        1400,
        () => _emit('item/completed', {
              ...base,
              'item': {'id': msg, 'type': 'agentMessage', 'text': reply}
            }));
    _at(1500, () {
      _busy = false;
      _emit('turn/completed', {
        'threadId': threadId,
        'turn': {'id': turn, 'status': 'completed'}
      });
    });
  }

  /// Nipa wakes up on its own (a follow-up), as in state C.
  void wake() {
    if (_busy) {
      _at(3000, wake);
      return;
    }
    _busy = true;
    const thread = 'fake-followup';
    const turn = 'fake-followup-turn';
    const msg = 'fake-followup-msg';
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
    _emit('turn/started', {
      'threadId': thread,
      'turn': {'id': turn, 'status': 'inProgress'}
    });
    _at(
        400,
        () => _emit('item/completed', {
              'threadId': thread,
              'turnId': turn,
              'item': {'id': 'fake-followup-tool', 'type': 'commandExecution'}
            }));
    const result = '《葬送的芙莉莲》的弹幕补好了，第一集随时可以看。';
    _at(
        9000,
        () => _emit('item/completed', {
              'threadId': thread,
              'turnId': turn,
              'item': {'id': msg, 'type': 'agentMessage', 'text': result}
            }));
    _at(9200, () {
      _busy = false;
      _emit('turn/completed', {
        'threadId': thread,
        'turn': {'id': turn, 'status': 'completed'}
      });
    });
  }

  @override
  Future<void> steer(String text) async {}

  @override
  Future<void> interrupt() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _busy = false;
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _display.close();
    _questions.close();
  }
}
