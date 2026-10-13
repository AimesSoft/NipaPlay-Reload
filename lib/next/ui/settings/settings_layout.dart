import '../data/settings_data.dart';

/// The page's sections, in the rail's order. Gaps in the rail fall between
/// [rail]'s lists.
enum SettingsSection {
  accounts('账号'),
  sources('媒体来源'),
  playback('播放'),
  danmaku('弹幕与字幕'),
  downloads('下载'),
  network('网络'),
  storage('存储'),
  devices('设备'),
  nipa('Nipa'),
  general('通用'),
  shortcuts('快捷键'),
  about('关于'),
  classic('经典界面');

  const SettingsSection(this.title);
  final String title;

  static const rail = [
    [accounts, sources],
    [playback, danmaku, downloads, network, storage],
    [devices, nipa],
    [general, shortcuts, about],
    [classic],
  ];
}

/// A titled run of registry settings in a section. [folded] groups wait
/// behind “更多”.
final class SettingsGroup {
  const SettingsGroup(this.title, this.matches, {this.folded = false});
  final String title;

  /// Exact keys, or prefixes ending in `.` or `*`.
  final List<String> matches;
  final bool folded;

  bool has(String key) => matches.any((m) => _matches(m, key));

  /// How precisely [key] is named here, lower first: an exact key, then
  /// the longest prefix.
  int rank(String key) {
    for (final (i, m) in matches.indexed) {
      if (m == key) return i;
    }
    var best = 1 << 20;
    for (final (i, m) in matches.indexed) {
      if (_matches(m, key)) {
        final r = 1000 + (200 - m.length) * 100 + i;
        if (r < best) best = r;
      }
    }
    return best;
  }

  static bool _matches(String pattern, String key) {
    if (pattern.endsWith('*')) {
      return key.startsWith(pattern.substring(0, pattern.length - 1));
    }
    if (pattern.endsWith('.')) return key.startsWith(pattern);
    return pattern == key;
  }
}

/// Where each registry setting goes. The registry decides what exists;
/// this only arranges it. A setting no rule names lands in 通用 › 其他, so
/// a new one appears here as soon as Nipa can see it.
abstract final class SettingsLayout {
  /// Shown elsewhere on the page in its own form (the 经典界面 button).
  static const hidden = {'labs_use_next_interface'};

  static const _sections = <(String, SettingsSection)>[
    ('player.screenshot*', SettingsSection.storage),
    ('player.', SettingsSection.playback),
    ('playback.', SettingsSection.playback),
    ('seek.', SettingsSection.playback),
    ('danmaku.', SettingsSection.danmaku),
    ('subtitle.', SettingsSection.danmaku),
    ('next.heroOpeningSeconds', SettingsSection.danmaku),
    ('plugins.githubProxyUrl', SettingsSection.network),
    ('plugins.', SettingsSection.danmaku),
    ('download.', SettingsSection.downloads),
    ('network.', SettingsSection.network),
    ('shortcuts.', SettingsSection.shortcuts),
    ('general.autoCheckUpdates', SettingsSection.about),
    ('general.defaultHomeTab', SettingsSection.classic),
    ('appearance.', SettingsSection.classic),
    ('webdavQuick.', SettingsSection.classic),
    ('next.harnessPath', SettingsSection.nipa),
  ];

  static SettingsSection sectionOf(String key) {
    for (final (pattern, section) in _sections) {
      if (SettingsGroup._matches(pattern, key)) return section;
    }
    return SettingsSection.general;
  }

  static const groups = <SettingsSection, List<SettingsGroup>>{
    SettingsSection.playback: [
      SettingsGroup('', [
        'player.kernel',
        'player.playbackEndAction',
        'player.autoNextCountdownSeconds',
        'player.introSkipEnabled',
        'player.autoFullscreenEnabled',
        'player.fastPlaybackStartup',
      ]),
      SettingsGroup('快进与倍速', ['playback.rate', 'seek.']),
      SettingsGroup(
          '画面',
          [
            'player.videoAspectMode',
            'player.erikaUpscalerMode',
            'player.anime4kProfile',
            'player.crtProfile',
            'player.doubleResolutionPlaybackEnabled',
            'player.macosNativeVideoEnabled',
            'player.useHardwareDecoder',
            'player.hwdecMode',
            'player.softDecodePixelFormat',
          ],
          folded: true),
      SettingsGroup(
          '播放界面',
          [
            'player.timelinePreviewEnabled',
            'player.chapterMarkersEnabled',
            'player.minimalProgressBar*',
            'player.top*',
            'player.showMenuQuickControls',
            'player.desktopHoverSettingsMenuEnabled',
            'player.instantHidePlayerUiEnabled',
          ],
          folded: true),
      SettingsGroup('外部播放器', ['player.external*'], folded: true),
      SettingsGroup('其他', ['player.', 'playback.'], folded: true),
    ],
    SettingsSection.danmaku: [
      SettingsGroup('弹幕', [
        'danmaku.visible',
        'danmaku.opacity',
        'danmaku.fontSize',
        'danmaku.displayArea',
        'danmaku.speedMultiplier',
        'danmaku.blockTop',
        'danmaku.blockBottom',
        'danmaku.blockScroll',
        'danmaku.merge',
        'danmaku.convertToSimplified',
        'danmaku.blockWords',
      ]),
      SettingsGroup('字幕', [
        'subtitle.scale',
        'subtitle.position',
        'subtitle.opacity',
        'subtitle.color',
        'subtitle.fontName',
        'subtitle.bold',
      ]),
      SettingsGroup(
          '弹幕样式',
          [
            'danmaku.outlineStyle',
            'danmaku.outlineWidth',
            'danmaku.shadowStyle',
            'danmaku.font*',
            'danmaku.randomColor',
            'danmaku.stacking',
            'danmaku.trackGap',
            'danmaku.showDensityChart',
            'danmaku.timelineEnabled',
            'next.heroOpeningSeconds',
          ],
          folded: true),
      SettingsGroup(
          '匹配',
          [
            'danmaku.autoLoadStrategy',
            'danmaku.autoMatchFirstSearchResultOnHashFail',
            'danmaku.skipMatching',
            'danmaku.rememberOffset',
          ],
          folded: true),
      SettingsGroup('防剧透', ['danmaku.spoiler*'], folded: true),
      SettingsGroup('过滤', ['plugins.'], folded: true),
      SettingsGroup('字幕样式', ['subtitle.'], folded: true),
      SettingsGroup('其他', ['danmaku.'], folded: true),
    ],
    SettingsSection.downloads: [
      SettingsGroup(
          '', ['download.enabled', 'download.directory', 'download.']),
    ],
    SettingsSection.network: [
      SettingsGroup('', ['network.httpProxy', 'network.', 'plugins.']),
    ],
    SettingsSection.storage: [
      SettingsGroup('截图', [
        'player.screenshotDirectory',
        'player.screenshotSaveTarget',
        'player.screenshotFormat',
        'player.screenshotQuality',
        'player.screenshot*',
      ]),
    ],
    SettingsSection.nipa: [
      SettingsGroup('文件夹', ['next.'], folded: true),
    ],
    SettingsSection.general: [
      SettingsGroup('', [
        'language.mode',
        'general.desktopExitBehavior',
        'general.pictureInPicturePosition',
      ]),
      SettingsGroup('启动', ['general.startup*'], folded: true),
      SettingsGroup('诊断', ['diagnostics.'], folded: true),
      SettingsGroup('实验', ['labs.'], folded: true),
      SettingsGroup('其他', ['general.', 'language.', '*'], folded: true),
    ],
    SettingsSection.shortcuts: [
      SettingsGroup('播放', ['shortcuts.']),
    ],
    SettingsSection.about: [
      SettingsGroup('', ['general.autoCheckUpdates']),
    ],
    SettingsSection.classic: [
      SettingsGroup(
          '外观',
          [
            'appearance.themeMode',
            'appearance.accentColor',
            'appearance.uiScale',
            'appearance.background*',
            'appearance.customBackgroundPath',
            'appearance.blurPower',
            'appearance.windowDisplayMode',
            'appearance.folderNameDisplayMode',
          ],
          folded: true),
      SettingsGroup(
          '首页',
          [
            'general.defaultHomeTab',
            'appearance.show*',
            'appearance.home*',
            'appearance.quarterlyReviewSort',
            'appearance.diffuse*',
          ],
          folded: true),
      SettingsGroup('WebDAV', ['webdavQuick.'], folded: true),
      SettingsGroup('其他', ['appearance.', 'general.'], folded: true),
    ],
  };

  /// Settings shown on the page: not the player's live state, and only
  /// those a control exists for.
  static bool shown(UiSetting s) =>
      !s.runtime && s.kind != UiSettingKind.other && !hidden.contains(s.key);

  /// [settings] of [section], grouped as above (the registry's order where
  /// no rule orders them). Empty groups are left out.
  static List<(SettingsGroup, List<UiSetting>)> arrange(
      SettingsSection section, Iterable<UiSetting> settings) {
    final groups = SettingsLayout.groups[section] ??
        const [
          SettingsGroup('', ['*'])
        ];
    final buckets = [for (final _ in groups) <UiSetting>[]];
    for (final s in settings) {
      if (!shown(s) || sectionOf(s.key) != section) continue;
      // The group naming it most precisely.
      var best = -1, bestRank = 1 << 20;
      for (final (i, g) in groups.indexed) {
        final r = g.rank(s.key);
        if (r < bestRank) {
          best = i;
          bestRank = r;
        }
      }
      if (best < 0) best = groups.length - 1;
      buckets[best].add(s);
    }
    final order = {for (final (i, s) in settings.indexed) s.key: i};
    return [
      for (final (i, g) in groups.indexed)
        if (buckets[i].isNotEmpty)
          (
            g,
            buckets[i]
              ..sort((a, b) {
                final r = g.rank(a.key).compareTo(g.rank(b.key));
                return r != 0 ? r : order[a.key]!.compareTo(order[b.key]!);
              })
          ),
    ];
  }
}

/// What a value is called. The registry gives only the values themselves
/// for now (Y8_REPORT asks for their titles); these words stand in until
/// it does, and anything unknown shows as it is.
abstract final class SettingWords {
  static const _byKey = <String, Map<String, String>>{
    'player.playbackEndAction': {
      'autoNext': '下一集',
      'loop': '重播',
      'pause': '暂停',
      'exitPlayer': '退出播放'
    },
    'player.kernel': {
      'mdk': 'MDK',
      'videoPlayer': '系统',
      'mediaKit': 'mpv',
      'erika': 'Erika'
    },
    'player.erikaUpscalerMode': {
      'off': '关闭',
      'erikaArtCnnC4F16': '标准',
      'erikaArtCnnC4F32': '高',
      'erikaArtCnnC4F16Ds': '省电'
    },
    'player.videoAspectMode': {
      'contain': '完整',
      'cover': '铺满',
      'fill': '拉伸',
      'fitWidth': '适应宽度',
      'fitHeight': '适应高度',
      'none': '原始',
      'scaleDown': '缩小以适应',
      'ratio16x9': '16:9',
      'ratio4x3': '4:3'
    },
    'player.hwdecMode': {'no': '关闭', 'auto': '自动', 'autoSafe': '自动（稳妥）'},
    'player.screenshotSaveTarget': {
      'ask': '每次询问',
      'photos': '照片',
      'file': '文件夹'
    },
    'player.screenshotQuality': {
      'standard': '标准',
      'high': '高',
      'ultra': '超高',
      'max': '最高'
    },
    'player.screenshotFormat': {'jpeg': 'JPEG', 'png': 'PNG'},
    'player.externalType': {
      'unset': '未选择',
      'mpv': 'mpv',
      'mpvNet': 'mpv.net',
      'potPlayer': 'PotPlayer',
      'vlc': 'VLC',
      'generic': '其他'
    },
    'danmaku.autoLoadStrategy': {
      'remoteAndLocal': '在线和本地',
      'remote': '在线',
      'local': '本地'
    },
    'danmaku.outlineStyle': {'none': '无', 'stroke': '描边', 'uniform': '均匀'},
    'danmaku.shadowStyle': {
      'none': '无',
      'soft': '柔和',
      'medium': '中等',
      'strong': '浓重'
    },
    'danmaku.outlineWidth': {'0.0': '无', '1.0': '细', '2.0': '粗'},
    'danmaku.spoilerAiApiFormat': {'openai': 'OpenAI', 'gemini': 'Gemini'},
    'subtitle.alignX': {'left': '靠左', 'center': '居中', 'right': '靠右'},
    'subtitle.alignY': {'top': '顶部', 'center': '居中', 'bottom': '底部'},
    'subtitle.overrideMode': {
      'auto': '自动',
      'none': '不接管',
      'scale': '仅大小',
      'force': '完全接管'
    },
    'appearance.accentColor': {'rose': '玫瑰', 'blue': '蓝', 'green': '绿'},
    'appearance.folderNameDisplayMode': {'ellipsis': '单行', 'multiline': '多行'},
    'appearance.windowDisplayMode': {'windowed': '窗口', 'filledScreen': '铺满屏幕'},
    'appearance.backgroundRenderMode': {'opacity': '透明度', 'soft_light': '柔光'},
    'language.mode': {
      'auto': '跟随系统',
      'simplified': '简体中文',
      'traditional': '繁體中文',
      'english': 'English'
    },
    'general.desktopExitBehavior': {
      'askEveryTime': '每次询问',
      'minimizeToTrayOrTaskbar': '最小化',
      'closePlayer': '退出'
    },
    'general.startupWindowState': {'windowed': '窗口', 'maximized': '最大化'},
    'general.defaultHomeTab': {
      'home': '主页',
      'video': '视频',
      'webdav': 'WebDAV',
      'media_library': '媒体库',
      'torrent': '下载',
      'account': '账户'
    },
    'webdavQuick.sortPreset': {
      'default': '默认',
      'name_asc': '名称 ↑',
      'name_desc': '名称 ↓',
      'modified_desc': '最近修改',
      'modified_asc': '最早修改',
      'size_desc': '最大',
      'size_asc': '最小'
    },
    'webdavQuick.searchScope': {
      'current_directory': '当前目录',
      'current_with_depth': '当前及子目录',
      'global': '全部'
    },
    'appearance.quarterlyReviewSort': {
      'airDate': '播出时间',
      'commentNewest': '最新评论',
      'commentOldest': '最早评论',
      'ratingHigh': '评分高',
      'ratingLow': '评分低'
    },
    'appearance.blurPower': {'0': '无', '0.0': '无'},
  };

  static const _common = {
    'system': '跟随系统',
    'light': '浅色',
    'dark': '深色',
    'auto': '自动',
    'none': '无',
    'off': '关闭',
    'on': '开启',
    'center': '居中',
    'topLeft': '左上',
    'topRight': '右上',
    'bottomLeft': '左下',
    'bottomRight': '右下',
  };

  /// What [value] of [key] is called.
  static String choice(String key, Object? value) {
    final text = value is double && value == value.roundToDouble()
        ? '${value.toInt()}'
        : '$value';
    return _byKey[key]?['$value'] ??
        _byKey[key]?[text] ??
        _common['$value'] ??
        text;
  }

  /// Player shortcut names (the registry calls them `快捷键 play_pause`).
  static const _shortcuts = {
    'play_pause': '播放 / 暂停',
    'fullscreen': '全屏',
    'rewind': '后退',
    'forward': '快进',
    'toggle_danmaku': '显示 / 隐藏弹幕',
    'volume_up': '音量加',
    'volume_down': '音量减',
    'speed_up': '加速',
    'speed_down': '减速',
    'speed_reset': '恢复原速',
    'previous_episode': '上一集',
    'next_episode': '下一集',
    'send_danmaku': '发弹幕',
    'skip': '跳过',
    'step_forward': '下一帧',
    'step_backward': '上一帧',
    'resize_to_video': '窗口适配视频',
    'toggle_picture_in_picture': '画中画',
    'toggle_detached_player': '独立窗口',
  };

  /// The setting's name as the page shows it.
  static String title(UiSetting s) {
    if (s.key.startsWith('shortcuts.')) {
      return _shortcuts[s.key.substring('shortcuts.'.length)] ?? s.title;
    }
    if (s.key == 'next.harnessPath') return 'Nipa 的文件夹';
    return s.title;
  }
}
