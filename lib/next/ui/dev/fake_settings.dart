import 'dart:async';
import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';

import '../../settings/presentation.dart';
import '../../ui_data/host_settings.dart';
import '../data/core_settings.dart' show memoryHeading;
import '../data/settings_data.dart';

/// The scripted settings world: the registry's real contracts when the
/// core can describe them (values start at their defaults, nothing is
/// written back), otherwise a sample of them; accounts, sources, memory
/// and the host's own settings in memory. Debug lab profiles only.
final class FakeSettings implements NextSettingsData {
  FakeSettings({this.describe});

  /// The real `settings.describe` rows, read once (contracts only).
  final Future<List<Map>> Function()? describe;

  @override
  final FakeHostSettings host = FakeHostSettings();
  final _changes = StreamController<void>.broadcast();
  final _memoryChanges = StreamController<void>.broadcast();
  List<Map<String, Object?>>? _rows;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<void> get memoryChanges => _memoryChanges.stream;

  void _changed() => _changes.add(null);

  static String _anonymous(Object? v) =>
      '$v'.replaceAll(RegExp(r'/Users/[^/]+/'), '/Users/hikari/');

  /// Settings Nipa changed: value, the one before, why, how long ago.
  static const _byNipa = <String, (Object?, Object?, String, Duration)>{
    'danmaku.opacity': (0.62, 0.85, '你说晚上弹幕太晃眼，调淡了一些。', Duration(hours: 2)),
    'player.autoNextCountdownSeconds': (
      3,
      10,
      '你说片尾不想等，倒计时缩到 3 秒。',
      Duration(hours: 26)
    ),
    'subtitle.scale': (1.15, 1.0, '客厅电视上字幕看不清，放大了一点。', Duration(days: 3)),
    'danmaku.blockWords': (
      ['剧透', '前方高能'],
      ['剧透'],
      '你让我把“前方高能”也屏蔽掉。',
      Duration(days: 5)
    ),
  };

  /// What this world has set, apart from Nipa.
  static final _values = <String, Object?>{
    'download.directory': '/Users/hikari/Movies/NipaPlay',
    'player.screenshotDirectory': '/Users/hikari/Pictures/NipaPlay',
    'appearance.customBackgroundPath': '',
    'labs_use_next_interface': true,
    'danmaku.merge': true,
    'download.enabled': true,
  };

  Future<List<Map<String, Object?>>> _load() async {
    if (_rows case final rows?) return rows;
    List<Map>? real;
    try {
      real = await describe?.call();
    } catch (_) {}
    final now = DateTime.now();
    final rows = <Map<String, Object?>>[];
    for (final source in real ?? _sample) {
      final row = <String, Object?>{
        for (final e in source.entries)
          if (e.key != 'provenance' && e.key != 'value' && e.key != 'revision')
            '${e.key}': e.value,
      };
      final key = row['key'] as String;
      if (real == null) row.addAll(settingPresentation(key, row));
      if (row['default'] is String) row['default'] = _anonymous(row['default']);
      row['value'] = _values.containsKey(key) ? _values[key] : row['default'];
      row['revision'] = 0;
      if (_byNipa[key] case (final v, final before, final why, final ago)) {
        row['value'] = v;
        row['revision'] = 1;
        row['provenance'] = {
          'changedBy': 'agent',
          'origin': 'mcp',
          'reason': why,
          'previousValue': before,
          'changedAt': now.subtract(ago).toUtc().toIso8601String(),
          'revision': 1,
        };
      }
      rows.add(row);
    }
    return _rows = rows;
  }

  @override
  Future<List<UiSetting>> settings() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return [for (final row in await _load()) UiSetting.fromRow(row)];
  }

  @override
  Future<UiSetting> set(String key, Object? value) async {
    await Future<void>.delayed(const Duration(milliseconds: 160));
    final row = (await _load()).firstWhere((r) => r['key'] == key,
        orElse: () =>
            throw const Failure(FailureCode.notFound, 'Setting not found.'));
    final setting = UiSetting.fromRow(row);
    if (setting.kind == UiSettingKind.number && value is num) {
      if ((setting.min != null && value < setting.min!) ||
          (setting.max != null && value > setting.max!)) {
        throw const Failure(FailureCode.invalidInput, 'Out of range.');
      }
    }
    final revision = (row['revision'] as int) + 1;
    row['provenance'] = {
      'changedBy': 'user',
      'origin': 'gui',
      'previousValue': row['value'],
      'changedAt': DateTime.now().toUtc().toIso8601String(),
      'revision': revision,
    };
    row['value'] = value;
    row['revision'] = revision;
    return UiSetting.fromRow(row);
  }

  @override
  Future<void> reset(List<String> keys) async {
    for (final row in await _load()) {
      if (keys.contains(row['key'])) {
        await set(row['key'] as String, row['default']);
      }
    }
  }

  @override
  Future<String?> pickPath({required bool directory}) async =>
      directory ? '/Users/hikari/Movies/Anime' : '/Users/hikari/Fonts/思源黑体.otf';

  // —— 账号 ——

  final _accounts = <String, String?>{
    'dandanplay': 'hikari',
    'bangumi': 'hikari_bgm',
  };
  DateTime _synced = DateTime.now().subtract(const Duration(hours: 3));

  @override
  Future<List<UiAccount>> accounts() async => [
        for (final p in ['dandanplay', 'bangumi'])
          UiAccount(
              provider: p,
              loggedIn: _accounts[p] != null,
              username: _accounts[p]),
      ];

  @override
  Future<void> login(String provider) async {
    // The login window, as if the person signed in after a moment.
    Timer(const Duration(milliseconds: 1600), () {
      _accounts[provider] = provider == 'dandanplay' ? 'hikari' : 'hikari_bgm';
      _changed();
    });
  }

  @override
  Future<void> logout(String provider) async {
    _accounts[provider] = null;
    _changed();
  }

  @override
  Future<UiBangumiSync> bangumiSync() async =>
      UiBangumiSync(last: _synced, works: 42);

  @override
  Future<void> syncBangumi({bool full = false}) async {
    Timer(Duration(milliseconds: full ? 3000 : 1800), () {
      _synced = DateTime.now();
      _changed();
    });
  }

  // —— 媒体来源 ——

  final _sources = <UiMediaSource>[
    const UiMediaSource(
        sourceId: 'jellyfin',
        type: 'jellyfin',
        name: '客厅 Jellyfin',
        url: 'http://192.168.1.20:8096',
        username: 'hikari',
        state: UiSourceState.connected,
        selected: ['anime', 'movies']),
    const UiMediaSource(
        sourceId: 'smb',
        type: 'smb',
        name: '家里的 NAS',
        url: 'smb://192.168.1.8:445',
        username: 'media',
        state: UiSourceState.connected,
        selected: ['Anime']),
    const UiMediaSource(
        sourceId: 'webdav',
        type: 'webdav',
        name: '网盘',
        url: 'https://dav.example.net/remote.php/dav',
        username: 'hikari'),
    const UiMediaSource(
        sourceId: 'emby',
        type: 'emby',
        name: '书房 Emby',
        url: 'http://study.local:8096',
        username: 'hikari',
        state: UiSourceState.failed),
  ];

  static const _libraries = <String, List<UiSourceLibrary>>{
    'jellyfin': [
      UiSourceLibrary(id: 'anime', name: '番剧'),
      UiSourceLibrary(id: 'movies', name: '电影'),
      UiSourceLibrary(id: 'docs', name: '纪录片'),
      UiSourceLibrary(id: 'live', name: '演唱会'),
    ],
    'smb': [
      UiSourceLibrary(id: 'Anime', name: 'Anime'),
      UiSourceLibrary(id: 'Movies', name: 'Movies'),
      UiSourceLibrary(id: 'Downloads', name: 'Downloads'),
    ],
    'webdav': [UiSourceLibrary(id: '/video', name: 'video')],
  };

  int _index(String id) => _sources.indexWhere((s) => s.sourceId == id);

  UiMediaSource _with(UiMediaSource s,
          {UiSourceState? state,
          List<String>? selected,
          UiSourceDraft? draft}) =>
      UiMediaSource(
        sourceId: s.sourceId,
        type: s.type,
        name: draft?.name ?? s.name,
        url: draft == null
            ? s.url
            : UiMediaSource.byHost(s.type)
                ? 'smb://${draft.host ?? ''}${draft.port == null ? '' : ':${draft.port}'}'
                : draft.url ?? s.url,
        username: draft?.username ?? s.username,
        state: state ?? s.state,
        selected: selected ?? s.selected,
      );

  @override
  Future<List<UiMediaSource>> sources() async => [..._sources];

  @override
  Future<UiMediaSource> addSource(UiSourceDraft draft) async {
    final source = _with(
        UiMediaSource(
            sourceId: 'new-${_sources.length}',
            type: draft.type,
            name: draft.name),
        draft: draft);
    _sources.add(source);
    _changed();
    return source;
  }

  @override
  Future<UiMediaSource> updateSource(String id, UiSourceDraft draft) async {
    final i = _index(id);
    _sources[i] =
        _with(_sources[i], draft: draft, state: UiSourceState.unverified);
    _changed();
    return _sources[i];
  }

  @override
  Future<void> removeSource(String id) async {
    _sources.removeAt(_index(id));
    _changed();
  }

  @override
  Future<UiSourceLogin> loginSource(String id) async {
    final i = _index(id);
    final quick = _sources[i].type == 'jellyfin';
    Timer(Duration(milliseconds: quick ? 6000 : 1500), () {
      final at = _index(id);
      if (at < 0) return;
      _sources[at] = _with(_sources[at], state: UiSourceState.connected);
      _changed();
    });
    return UiSourceLogin(code: quick ? '428913' : null);
  }

  @override
  Future<UiSourceCheck> checkSource(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final s = _sources[_index(id)];
    return s.state == UiSourceState.failed
        ? const UiSourceCheck(ok: false, message: '连不上')
        : const UiSourceCheck(ok: true);
  }

  @override
  Future<List<UiSourceLibrary>> libraries(String id) async =>
      _libraries[_sources[_index(id)].type == 'jellyfin' ? 'jellyfin' : id] ??
      const [];

  @override
  Future<void> selectLibraries(String id, List<String> ids) async {
    final i = _index(id);
    _sources[i] = _with(_sources[i], selected: ids);
  }

  // —— 记忆 ——

  final _memory = <String, String>{
    'preferences.md': '# 偏好\n\n'
        '- 喜欢日常系和乐队番，不太看恐怖片。（10月2日，你说的）\n'
        '- 晚上看弹幕要淡一点。（10月12日）\n'
        '- 片尾直接进下一集，不用等。\n'
        '- 字幕在客厅电视上要大一些。\n',
    'MEMORY.md': '- [看番口味](topics/taste.md) — 喜欢的类型和制作公司\n'
        '- [客厅的电视](topics/living-room.md) — 怎么在那边看\n'
        '- [补番计划](topics/backlog.md) — 想补的老番\n',
    'topics/taste.md': '# 看番口味\n\n'
        '喜欢京阿尼和 CloverWorks 的作品；《孤独摇滚！》看了三遍。\n'
        '对机战兴趣一般，除非朋友推荐。\n',
    'topics/living-room.md': '# 客厅的电视\n\n'
        '周末晚上在客厅用 Jellyfin 看，网络偶尔慢，先缓存再看。\n',
    'topics/backlog.md': '# 补番计划\n\n'
        '- 《星际牛仔》\n- 《少女终末旅行》\n- 《来自深渊》第二季\n',
  };

  static String _revision(String content) =>
      base64Url.encode(utf8.encode('${content.hashCode}'));

  @override
  Future<List<UiMemoryFile>> memories() async => [
        for (final e
            in (_memory.entries.toList()
              ..sort((a, b) => _order(a.key).compareTo(_order(b.key)))))
          UiMemoryFile(
              path: e.key,
              bytes: utf8.encode(e.value).length,
              revision: _revision(e.value),
              title:
                  e.key.startsWith('topics/') ? memoryHeading(e.value) : null),
      ];

  static String _order(String path) => switch (path) {
        'preferences.md' => '0',
        'MEMORY.md' => '2',
        _ => '1$path',
      };

  @override
  Future<UiMemoryDoc> memory(String path) async {
    final content = _memory[path] ??
        (throw const Failure(
            FailureCode.notFound, 'Memory file does not exist.'));
    return UiMemoryDoc(
        path: path, content: content, revision: _revision(content));
  }

  @override
  Future<void> editMemory(UiMemoryDoc doc, String content) async {
    if (_revision(_memory[doc.path] ?? '') != doc.revision) {
      throw const Failure(FailureCode.conflict, 'Memory changed.');
    }
    _memory[doc.path] = content;
    _changed();
  }

  @override
  Future<void> forgetMemory(UiMemoryDoc doc) async {
    _memory.remove(doc.path);
    _changed();
  }

  // —— 关于 ——

  @override
  Future<UiAbout> about() async => const UiAbout(version: '1.9.3');

  /// Debug: `model=key|nokey|codex|nocodex`, `mesh=online|offline|unavailable`,
  /// `keys=both|spoiler|tmdb|none`, `remote=on|off|problem|unsupported`,
  /// `trusted=0..3`; `remember=<topic>` is Nipa writing a note;
  /// `codex=none|downloading|verifying|ready|failed|path`.
  Map<String, Object?> scenario(Map<String, String> p) {
    if (p['model'] case final m?) host.modelState = m;
    if (p['codex'] case final c?) {
      host.codexState = c;
      if (c == 'downloading') host._received = 46137344;
    }
    if (p['mesh'] case final m?) host.meshState = m;
    if (p['keys'] case final k?) {
      host.spoilerKey = k == 'both' || k == 'spoiler';
      host.tmdbKey = k == 'both' || k == 'tmdb';
    }
    if (p['remote'] case final r?) host.remoteState = r;
    if (p['trusted'] case final n?) host.trust(int.parse(n));
    if (p['remember'] case final topic?) {
      _memory['topics/$topic.md'] =
          '# $topic\n\n${DateTime.now().toIso8601String().substring(0, 16)}\n';
      _memoryChanges.add(null);
    }
    if (p['account'] case final a?) {
      final [provider, state] = a.split(':');
      _accounts[provider] = state == 'out'
          ? null
          : provider == 'dandanplay'
              ? 'hikari'
              : 'hikari_bgm';
      _changed();
    }
    host.changed();
    return {
      'model': host.modelState,
      'mesh': host.meshState,
      'keys': {'spoiler': host.spoilerKey, 'tmdb': host.tmdbKey},
      'remote': host.remoteState,
      'trusted': host.trusted.length,
      'codex': host.codexState
    };
  }

  void dispose() {
    _changes.close();
    _memoryChanges.close();
    host.dispose();
  }

  static const _sample = <Map<String, Object?>>[
    {
      'key': 'labs_use_next_interface',
      'title': '使用 Next 界面',
      'type': 'boolean',
      'default': false,
      'apply': 'immediate',
      'value': true,
      'revision': 0
    },
    {
      'key': 'player.introSkipEnabled',
      'title': '跳过片头片尾',
      'type': 'boolean',
      'default': true,
      'apply': 'immediate',
      'value': true,
      'revision': 0
    },
    {
      'key': 'player.autoFullscreenEnabled',
      'title': '播放自动全屏',
      'type': 'boolean',
      'default': false,
      'apply': 'immediate',
      'value': false,
      'revision': 0
    },
    {
      'key': 'playback.rate',
      'title': '播放速度',
      'type': 'number',
      'minimum': 0.01,
      'maximum': 5.0,
      'step': 0.05,
      'default': 1.0,
      'apply': 'immediate',
      'value': 1.0,
      'revision': 0
    },
    {
      'key': 'seek.skipSeconds',
      'title': '跳过时间（秒）',
      'type': 'integer',
      'minimum': 10,
      'maximum': 600,
      'default': 90,
      'apply': 'immediate',
      'value': 90,
      'revision': 0
    },
    {
      'key': 'player.autoNextCountdownSeconds',
      'title': '自动下一话倒计时',
      'type': 'integer',
      'minimum': 0,
      'maximum': 15,
      'default': 3,
      'apply': 'immediate',
      'value': 3,
      'revision': 0
    },
    {
      'key': 'player.minimalProgressBarColor',
      'title': '最小进度条颜色',
      'type': 'integer',
      'enum': [4294931060, 4282435583, 4285398889, 4283236273, 4294967295],
      'minimum': 0,
      'maximum': 4294967295,
      'default': 4294931060,
      'apply': 'immediate',
      'value': 4294931060,
      'revision': 0
    },
    {
      'key': 'player.playbackEndAction',
      'title': '播放结束行为',
      'type': 'string',
      'enum': ['autoNext', 'loop', 'pause', 'exitPlayer'],
      'default': 'autoNext',
      'apply': 'immediate',
      'value': 'autoNext',
      'revision': 0
    },
    {
      'key': 'player.hwdecMode',
      'title': '硬件解码模式',
      'type': 'string',
      'enum': [
        'no',
        'auto',
        'autoSafe',
        'autoCopy',
        'd3d12va',
        'd3d12vaCopy',
        'd3d11va',
        'd3d11vaCopy',
        'dxva2',
        'dxva2Copy',
        'videotoolbox',
        'videotoolboxCopy',
        'vaapi',
        'vaapiCopy',
        'nvdec',
        'nvdecCopy',
        'drm',
        'drmCopy',
        'vulkan',
        'vulkanCopy',
        'vdpau',
        'vdpauCopy',
        'mediacodec',
        'mediacodecCopy',
        'cuda',
        'cudaCopy',
        'crystalhd',
        'rkmpp',
        'amf',
        'amfCopy',
        'qsv',
        'qsvCopy'
      ],
      'default': 'auto',
      'apply': 'reload_player',
      'value': 'auto',
      'revision': 0
    },
    {
      'key': 'player.videoAspectMode',
      'title': '视频画面适配模式',
      'type': 'string',
      'enum': [
        'contain',
        'cover',
        'fill',
        'fitWidth',
        'fitHeight',
        'none',
        'scaleDown',
        'ratio16x9',
        'ratio4x3'
      ],
      'default': 'contain',
      'apply': 'immediate',
      'value': 'contain',
      'revision': 0
    },
    {
      'key': 'player.screenshotQuality',
      'title': '截图质量',
      'type': 'string',
      'enum': ['standard', 'high', 'ultra', 'max'],
      'default': 'ultra',
      'apply': 'immediate',
      'value': 'ultra',
      'revision': 0
    },
    {
      'key': 'player.screenshotFormat',
      'title': '截图格式',
      'type': 'string',
      'enum': ['jpeg', 'png'],
      'default': 'jpeg',
      'apply': 'immediate',
      'value': 'jpeg',
      'revision': 0
    },
    {
      'key': 'player.externalEnabled',
      'title': '使用外部播放器',
      'type': 'boolean',
      'default': false,
      'apply': 'immediate',
      'value': false,
      'revision': 0
    },
    {
      'key': 'player.kernel',
      'title': '播放器内核',
      'type': 'string',
      'enum': ['mdk', 'videoPlayer', 'mediaKit', 'erika'],
      'default': 'mdk',
      'apply': 'reload_player',
      'value': 'erika',
      'revision': 0
    },
    {
      'key': 'danmaku.visible',
      'title': '显示弹幕',
      'type': 'boolean',
      'default': true,
      'apply': 'immediate',
      'value': true,
      'revision': 0
    },
    {
      'key': 'danmaku.merge',
      'title': '合并弹幕',
      'type': 'boolean',
      'default': false,
      'apply': 'immediate',
      'value': false,
      'revision': 0
    },
    {
      'key': 'danmaku.blockTop',
      'title': '屏蔽顶部弹幕',
      'type': 'boolean',
      'default': false,
      'apply': 'immediate',
      'value': false,
      'revision': 0
    },
    {
      'key': 'danmaku.blockBottom',
      'title': '屏蔽底部弹幕',
      'type': 'boolean',
      'default': false,
      'apply': 'immediate',
      'value': false,
      'revision': 0
    },
    {
      'key': 'danmaku.opacity',
      'title': '弹幕透明度',
      'type': 'number',
      'minimum': 0,
      'maximum': 1,
      'step': 0.01,
      'default': 1.0,
      'apply': 'immediate',
      'value': 1.0,
      'revision': 0
    },
    {
      'key': 'danmaku.fontSize',
      'title': '弹幕字体大小',
      'type': 'number',
      'minimum': 0,
      'maximum': 60.0,
      'step': 1,
      'default': 0.0,
      'apply': 'immediate',
      'value': 0.0,
      'revision': 0
    },
    {
      'key': 'danmaku.speedMultiplier',
      'title': '弹幕速度倍率',
      'type': 'number',
      'minimum': 0.5,
      'maximum': 2,
      'step': 0.01,
      'default': 1.0,
      'apply': 'immediate',
      'value': 1.0,
      'revision': 0
    },
    {
      'key': 'danmaku.displayArea',
      'title': '弹幕显示区域',
      'type': 'number',
      'minimum': 0,
      'maximum': 1,
      'step': 0.1,
      'default': 1.0,
      'apply': 'immediate',
      'value': 1.0,
      'revision': 0
    },
    {
      'key': 'danmaku.outlineWidth',
      'title': '弹幕描边档位',
      'type': 'number',
      'enum': [0.0, 1.0, 2.0],
      'minimum': 0,
      'maximum': 2,
      'default': 2.0,
      'apply': 'immediate',
      'value': 1.0,
      'revision': 0
    },
    {
      'key': 'danmaku.blockWords',
      'title': '弹幕屏蔽词',
      'type': 'array',
      'items': {'type': 'string'},
      'default': [],
      'apply': 'immediate',
      'value': [],
      'revision': 0
    },
    {
      'key': 'subtitle.scale',
      'title': '字幕大小',
      'type': 'number',
      'minimum': 0.5,
      'maximum': 2.5,
      'step': 0.05,
      'default': 1.0,
      'apply': 'immediate',
      'value': 1.0,
      'revision': 0
    },
    {
      'key': 'subtitle.bold',
      'title': '字幕加粗',
      'type': 'boolean',
      'default': false,
      'apply': 'immediate',
      'value': false,
      'revision': 0
    },
    {
      'key': 'subtitle.color',
      'title': '字幕颜色',
      'type': 'string',
      'pattern': '^#[0-9A-Fa-f]{8}\$',
      'default': '#FFFFFFFF',
      'apply': 'immediate',
      'value': '#FFFFFFFF',
      'revision': 0
    },
    {
      'key': 'subtitle.fontName',
      'title': '字幕字体',
      'type': 'string',
      'default': '',
      'apply': 'immediate',
      'value': '',
      'revision': 0
    },
    {
      'key': 'player.screenshotDirectory',
      'title': '截图保存目录',
      'type': 'string',
      'default': '',
      'apply': 'immediate',
      'value': '/Users/hikari/Pictures/NipaPlay',
      'revision': 0
    },
    {
      'key': 'appearance.accentColor',
      'title': '主题色',
      'type': 'string',
      'enum': ['rose', 'blue', 'green'],
      'default': 'rose',
      'apply': 'immediate',
      'value': 'rose',
      'revision': 0
    },
    {
      'key': 'appearance.themeMode',
      'title': '主题模式',
      'type': 'string',
      'enum': ['system', 'light', 'dark'],
      'default': 'system',
      'apply': 'immediate',
      'value': 'dark',
      'revision': 0
    },
    {
      'key': 'appearance.blurPower',
      'title': '背景毛玻璃',
      'type': 'number',
      'enum': [0, 5, 15, 25, 50, 100],
      'minimum': 0,
      'maximum': 100,
      'default': 0.0,
      'apply': 'immediate',
      'value': 0.0,
      'revision': 0
    },
    {
      'key': 'language.mode',
      'title': '语言',
      'type': 'string',
      'enum': ['auto', 'simplified', 'traditional', 'english'],
      'default': 'auto',
      'apply': 'immediate',
      'value': 'simplified',
      'revision': 0
    },
    {
      'key': 'general.desktopExitBehavior',
      'title': '关闭窗口时',
      'type': 'string',
      'enum': ['askEveryTime', 'minimizeToTrayOrTaskbar', 'closePlayer'],
      'default': 'askEveryTime',
      'apply': 'immediate',
      'value': 'askEveryTime',
      'revision': 0
    },
    {
      'key': 'general.startupWindowState',
      'title': '启动窗口状态',
      'type': 'string',
      'enum': ['windowed', 'maximized'],
      'default': 'maximized',
      'apply': 'restart_app',
      'value': 'maximized',
      'revision': 0
    },
    {
      'key': 'general.autoCheckUpdates',
      'title': '自动检查更新',
      'type': 'boolean',
      'default': true,
      'apply': 'immediate',
      'value': true,
      'revision': 0
    },
    {
      'key': 'network.httpProxy',
      'title': '统一 HTTP 代理',
      'type': 'string',
      'default': '',
      'apply': 'reload_player',
      'value': '',
      'revision': 0
    },
    {
      'key': 'network.allowInvalidCertificates',
      'title': '允许自签名证书（全局）',
      'type': 'boolean',
      'default': false,
      'apply': 'immediate',
      'value': false,
      'revision': 0
    },
    {
      'key': 'plugins.githubProxyUrl',
      'title': 'GitHub 代理',
      'type': 'string',
      'default': '',
      'apply': 'immediate',
      'value': '',
      'revision': 0
    },
    {
      'key': 'diagnostics.fileLog',
      'title': '写入日志文件',
      'type': 'boolean',
      'default': true,
      'apply': 'immediate',
      'value': true,
      'revision': 0
    },
    {
      'key': 'shortcuts.play_pause',
      'title': '快捷键 play_pause',
      'type': 'string',
      'default': '空格',
      'apply': 'immediate',
      'value': '空格',
      'revision': 0
    },
    {
      'key': 'shortcuts.fullscreen',
      'title': '快捷键 fullscreen',
      'type': 'string',
      'default': 'Enter',
      'apply': 'immediate',
      'value': 'Enter',
      'revision': 0
    },
    {
      'key': 'shortcuts.toggle_danmaku',
      'title': '快捷键 toggle_danmaku',
      'type': 'string',
      'default': 'D',
      'apply': 'immediate',
      'value': 'D',
      'revision': 0
    },
    {
      'key': 'shortcuts.next_episode',
      'title': '快捷键 next_episode',
      'type': 'string',
      'default': 'Shift+→',
      'apply': 'immediate',
      'value': 'Shift+→',
      'revision': 0
    },
    {
      'key': 'download.enabled',
      'title': '启用下载器',
      'type': 'boolean',
      'default': true,
      'apply': 'immediate',
      'value': true,
      'revision': 0
    },
    {
      'key': 'download.createFolderForTask',
      'title': '下载时创建同名文件夹',
      'type': 'boolean',
      'default': true,
      'apply': 'immediate',
      'value': true,
      'revision': 0
    },
    {
      'key': 'download.autoScanCompletedTasks',
      'title': '完成后自动加入媒体库',
      'type': 'boolean',
      'default': true,
      'apply': 'immediate',
      'value': true,
      'revision': 0
    },
    {
      'key': 'download.directory',
      'title': '默认下载目录',
      'type': 'string',
      'default': '',
      'apply': 'immediate',
      'value': '/Users/hikari/Movies/NipaPlay',
      'revision': 0
    },
    {
      'key': 'next.heroOpeningSeconds',
      'title': '开头弹幕时长',
      'type': 'integer',
      'minimum': 30,
      'maximum': 300,
      'default': 180,
      'apply': 'immediate',
      'value': 180,
      'revision': 0
    },
  ];
}

/// The host's own settings, scripted.
final class FakeHostSettings
    implements NextHostSettings, NextHostDeviceSettings, NextHostRuntimeSettings {
  String modelState = 'key';

  /// `none`, `downloading`, `verifying`, `ready`, `failed`, `path`.
  String codexState = 'ready';
  int _received = 0;
  static const _total = 120299266;
  String? _mirror;
  Timer? _download;
  String meshState = 'online';
  bool spoilerKey = true, tmdbKey = false;

  /// `on`, `off`, `problem` (it would not start) or `unsupported`.
  String remoteState = 'on';
  bool _remoteAuto = true, _remoteIpv6 = false, _receiver = true;
  int _remotePort = 1180;
  static const _devices = [
    UiRemoteDevice(clientKey: 'ipad', name: 'iPad'),
    UiRemoteDevice(clientKey: 'tv', name: '客厅的电视'),
    UiRemoteDevice(clientKey: 'phone', name: 'Pixel 9'),
  ];
  final trusted = [..._devices.take(2)];

  void trust(int count) => trusted
    ..clear()
    ..addAll(_devices.take(count));
  bool _programs = true;
  String _name = '这台 Mac';
  bool _loopback = false, _broadcast = true;
  final _addresses = <String>['100.84.12.7:7801'];
  final _changes = StreamController<void>.broadcast();

  void changed() => _changes.add(null);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<UiModelSetup> model() async => switch (modelState) {
        'codex' => const UiModelSetup(
            source: UiModelSource.codex,
            codexAvailable: true,
            inUse: 'gpt-5.5-codex'),
        'nocodex' => const UiModelSetup(
            source: UiModelSource.codex, problem: '这台电脑上没有 Codex'),
        'nokey' => const UiModelSetup(
            source: UiModelSource.nipaplay,
            codexAvailable: true,
            provider: 'DeepSeek',
            baseUrl: 'https://api.deepseek.com/',
            model: 'deepseek-flash',
            problem: '还没有 API key'),
        _ => const UiModelSetup(
            source: UiModelSource.nipaplay,
            codexAvailable: true,
            provider: 'DeepSeek',
            baseUrl: 'https://api.deepseek.com/',
            model: 'deepseek-flash',
            hasKey: true,
            inUse: 'deepseek-flash'),
      };

  @override
  Future<UiCodexRuntime> codexRuntime() async => switch (codexState) {
        'none' => const UiCodexRuntime(
            status: UiCodexStatus.notInstalled,
            version: '0.144.1',
            source: UiCodexSource.managed,
            totalBytes: _total),
        'downloading' => UiCodexRuntime(
            status: UiCodexStatus.downloading,
            version: '0.144.1',
            source: UiCodexSource.managed,
            receivedBytes: _received,
            totalBytes: _total,
            mirror: _mirror),
        'verifying' => const UiCodexRuntime(
            status: UiCodexStatus.verifying,
            version: '0.144.1',
            source: UiCodexSource.managed,
            receivedBytes: _total,
            totalBytes: _total),
        'failed' => const UiCodexRuntime(
            status: UiCodexStatus.failed,
            version: '0.144.1',
            source: UiCodexSource.managed,
            receivedBytes: 48201728,
            totalBytes: _total,
            problem: '下载中断，网络连不上'),
        'path' => const UiCodexRuntime(
            status: UiCodexStatus.notInstalled,
            version: null,
            source: UiCodexSource.path,
            executable: '/opt/homebrew/bin/codex'),
        _ => UiCodexRuntime(
            status: UiCodexStatus.ready,
            version: '0.144.1',
            source: UiCodexSource.managed,
            receivedBytes: _total,
            totalBytes: _total,
            mirror: _mirror,
            licensesDirectory: '/tmp/nipa-next/codex-licenses'),
      };

  /// A download that moves on its own, a little at a time.
  @override
  Future<void> installCodex() async {
    _download?.cancel();
    codexState = 'downloading';
    changed();
    final done = Completer<void>();
    _download = Timer.periodic(const Duration(milliseconds: 250), (t) {
      _received = (_received + _total ~/ 24).clamp(0, _total);
      if (_received >= _total) {
        t.cancel();
        codexState = 'verifying';
        changed();
        Timer(const Duration(milliseconds: 900), () {
          codexState = 'ready';
          changed();
          done.complete();
        });
      } else {
        changed();
      }
    });
    return done.future;
  }

  @override
  Future<void> cancelCodexInstall() async {
    _download?.cancel();
    codexState = 'none';
    changed();
  }

  @override
  Future<void> removeCodex() async {
    _received = 0;
    codexState = 'none';
    changed();
  }

  @override
  Future<void> setCodexRuntime(UiCodexRuntimeChoice choice) async {
    _mirror = (choice.mirror?.isEmpty ?? true) ? null : choice.mirror;
    codexState = switch (choice.source) {
      UiCodexSource.managed => _received >= _total ? 'ready' : 'none',
      _ => 'path',
    };
    changed();
  }

  @override
  Future<void> setModel(UiModelChoice choice) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    modelState = choice.source == UiModelSource.codex
        ? 'codex'
        : (choice.apiKey != null || modelState == 'key')
            ? 'key'
            : 'nokey';
    changed();
  }

  @override
  Future<UiModelCheck> checkModel() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return switch (modelState) {
      'nokey' => const UiModelCheck(ok: false, message: '缺少 API key'),
      'nocodex' => const UiModelCheck(ok: false, message: '找不到 Codex'),
      _ => const UiModelCheck(ok: true, latency: Duration(milliseconds: 420)),
    };
  }

  @override
  Future<UiMeshSetup> mesh() async {
    if (meshState == 'unavailable') {
      return const UiMeshSetup(available: false, problem: '这个版本不能组网');
    }
    final joined = meshState == 'online';
    return UiMeshSetup(
      joined: joined,
      name: _name,
      port: 7801,
      loopbackOnly: _loopback,
      broadcastDiscovery: _broadcast,
      addresses: [..._addresses],
      devices: joined
          ? [
              UiMeshDevice(
                  name: _name,
                  online: true,
                  self: true,
                  roles: const ['播放', '下载'],
                  remotePrograms: _programs),
              const UiMeshDevice(
                  name: '工作站',
                  online: true,
                  roles: ['下载', '存储'],
                  remotePrograms: true),
              const UiMeshDevice(name: '旧笔记本', roles: ['播放']),
            ]
          : const [],
    );
  }

  @override
  Future<void> setMesh(UiMeshChoice choice) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    meshState = choice.joined ? 'online' : 'offline';
    if (choice.name != null && choice.name!.isNotEmpty) _name = choice.name!;
    _loopback = choice.loopbackOnly;
    _broadcast = choice.broadcastDiscovery;
    _addresses
      ..clear()
      ..addAll(choice.addresses);
    changed();
  }

  @override
  Future<bool> remotePrograms() async => _programs;

  @override
  Future<void> setRemotePrograms(bool allowed) async {
    _programs = allowed;
    changed();
  }

  void _device() {
    if (remoteState == 'unsupported') {
      throw UnsupportedError('此宿主不支持设备设置');
    }
  }

  @override
  Future<UiHostKeys> keys() async {
    _device();
    return UiHostKeys(spoilerAi: spoilerKey, tmdb: tmdbKey);
  }

  @override
  Future<void> setKeys({String? spoilerAi, String? tmdb}) async {
    _device();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (spoilerAi != null) spoilerKey = spoilerAi.isNotEmpty;
    if (tmdb != null) tmdbKey = tmdb.isNotEmpty;
    changed();
  }

  @override
  Future<UiRemoteAccess> remoteAccess() async {
    _device();
    return UiRemoteAccess(
      running: remoteState == 'on',
      autoStart: _remoteAuto,
      port: _remotePort,
      ipv6: _remoteIpv6,
      receiverEnabled: _receiver,
      devices: [...trusted],
      problem: remoteState == 'problem' ? '远程访问服务未能启动' : null,
    );
  }

  @override
  Future<void> setRemoteAccess(UiRemoteAccessChoice choice) async {
    _device();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (choice.port < 1 || choice.port > 65535) {
      throw const Failure(FailureCode.invalidInput, 'Port must be 1–65535.');
    }
    _remoteAuto = choice.autoStart;
    _remoteIpv6 = choice.ipv6;
    _receiver = choice.receiverEnabled;
    _remotePort = choice.port;
    // A listener that would not start keeps failing until it is stopped.
    if (remoteState == 'problem' && choice.running) {
      changed();
      throw const Failure(FailureCode.unavailable, '远程访问服务未能启动');
    }
    remoteState = choice.running ? 'on' : 'off';
    changed();
  }

  @override
  Future<void> forgetRemoteDevice(String clientKey) async {
    _device();
    trusted.removeWhere((d) => d.clientKey == clientKey);
    changed();
  }

  void dispose() => _changes.close();
}
