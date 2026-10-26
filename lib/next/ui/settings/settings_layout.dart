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
  sync('同步'),
  nipa('梨花'),
  general('通用'),
  shortcuts('快捷键'),
  plugins('插件'),
  about('关于'),
  classic('经典界面');

  const SettingsSection(this.title);
  final String title;

  static const rail = [
    [accounts, sources],
    [playback, danmaku, downloads, network, storage],
    [devices, sync, nipa],
    [general, shortcuts, plugins, about],
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
  /// Shown elsewhere on the page in its own form (the 经典界面 button;
  /// each plugin's switch, on its row in 插件).
  static const hidden = {'labs_use_next_interface', 'plugins.enabled.*'};

  static const _sections = <(String, SettingsSection)>[
    ('player.screenshot*', SettingsSection.storage),
    ('player.', SettingsSection.playback),
    ('playback.', SettingsSection.playback),
    ('seek.', SettingsSection.playback),
    ('danmaku.', SettingsSection.danmaku),
    ('subtitle.', SettingsSection.danmaku),
    ('next.heroOpeningSeconds', SettingsSection.danmaku),
    ('plugins.githubProxyUrl', SettingsSection.network),
    ('plugins.', SettingsSection.plugins),
    ('sync.', SettingsSection.sync),
    ('download.', SettingsSection.downloads),
    ('network.', SettingsSection.network),
    ('shortcuts.', SettingsSection.shortcuts),
    ('general.autoCheckUpdates', SettingsSection.about),
    ('general.defaultHomeTab', SettingsSection.classic),
    ('appearance.', SettingsSection.classic),
    ('webdavQuick.', SettingsSection.classic),
    ('next.harnessPath', SettingsSection.nipa),
    ('library.notifyNipaEnabled', SettingsSection.nipa),
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
      SettingsGroup('', ['library.notifyNipaEnabled']),
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
    SettingsSection.plugins: [
      SettingsGroup('设置', ['plugins.settings.', 'plugins.']),
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
      !s.runtime &&
      s.kind != UiSettingKind.other &&
      !hidden.any((h) => SettingsGroup._matches(h, s.key));

  /// The group naming [key] most precisely, else the last.
  static int _place(List<SettingsGroup> groups, String key) {
    var best = -1, bestRank = 1 << 20;
    for (final (i, g) in groups.indexed) {
      final r = g.rank(key);
      if (r < bestRank) {
        best = i;
        bestRank = r;
      }
    }
    return best < 0 ? groups.length - 1 : best;
  }

  /// Whether [key] waits behind “更多”.
  static bool folded(String key) {
    final groups = SettingsLayout.groups[sectionOf(key)];
    return groups != null && groups[_place(groups, key)].folded;
  }

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
      buckets[_place(groups, s.key)].add(s);
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

/// What a setting is called on the page, where the registry's title does
/// not read well yet.
abstract final class SettingWords {
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
    if (s.key == 'next.harnessPath') return '梨花的文件夹';
    return s.title;
  }
}
