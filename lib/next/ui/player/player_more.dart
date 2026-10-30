import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart' show Failure;

import '../../player/ports/session_playback.dart';
import '../data/gui_calls.dart';
import '../data/settings_data.dart';
import '../settings/controls.dart' show FieldControl, NextToggle, PillButton;
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import '../widgets/progress.dart';
import 'gif_dialog.dart';
import 'menu_controls.dart';
import 'playback.dart';
import 'player_menus.dart' show TimedLine;
import 'player_settings.dart';

enum _Page {
  root,
  rate,
  audio,
  fit,
  danmaku,
  chapters,
  playback,
  quality,
  info,
  danmakuStyle,
  blockWords,
  danmakuTracks,
  danmakuList,
  send,
}

/// What the bar has no room for: the speed, the audio track, how the
/// picture fits, the danmaku's look and tracks, how seeking goes, the
/// stream's quality, what plays; a still of the picture, picture in
/// picture. Each choice is Classic's own setting, set as its player menu
/// sets it.
class MoreMenu extends StatefulWidget {
  const MoreMenu({
    super.key,
    required this.playback,
    required this.settings,
    required this.calls,
    required this.onScreenshot,
    required this.onPictureInPicture,
  });
  final NextPlayback playback;
  final NextSettingsData settings;
  final GuiCalls calls;
  final VoidCallback onScreenshot;
  final VoidCallback onPictureInPicture;

  @override
  State<MoreMenu> createState() => MoreMenuState();
}

class MoreMenuState extends State<MoreMenu> {
  _Page _page = _Page.root;
  List<AudioChoice> _audio = const [];

  NextPlayback get _playback => widget.playback;
  SessionPlayback? get _session =>
      _playback is SessionPlayback ? _playback as SessionPlayback : null;

  @override
  void initState() {
    super.initState();
    _audio = _readAudio();
  }

  List<AudioChoice> _readAudio() {
    try {
      return _playback.audio();
    } catch (e) {
      debugPrint('[NextPlayer] audio tracks: $e');
      return const [];
    }
  }

  static const _underDanmaku = {
    _Page.danmakuStyle,
    _Page.blockWords,
    _Page.danmakuTracks,
    _Page.danmakuList,
    _Page.send,
  };

  /// Esc on a page goes back a page; false on the menu itself.
  bool back() {
    if (_page == _Page.root) return false;
    setState(() =>
        _page = _underDanmaku.contains(_page) ? _Page.danmaku : _Page.root);
    return true;
  }

  void _open(_Page page) => setState(() => _page = page);

  void _set(Future<void> Function() change) => unawaited(
      change().catchError((Object e) => debugPrint('[NextPlayer] more: $e')));

  static String rateText(double rate) {
    var t = rate.toStringAsFixed(2);
    if (t.endsWith('0')) t = t.substring(0, t.length - 1);
    return '$t×';
  }

  static const fitLabels = {
    VideoAspectMode.contain: '适应',
    VideoAspectMode.cover: '裁剪',
    VideoAspectMode.fill: '拉伸',
    VideoAspectMode.fitWidth: '等宽',
    VideoAspectMode.fitHeight: '等高',
    VideoAspectMode.none: '原始',
    VideoAspectMode.scaleDown: '限制',
    VideoAspectMode.ratio16x9: '16:9',
    VideoAspectMode.ratio4x3: '4:3',
  };

  /// What [NextPlayback.danmakuAreas] are called, in their order.
  static const areaLabels = ['单行', '1/8', '1/4', '1/3', '2/3', '全屏'];

  /// How a Jellyfin or Emby stream's qualities are called.
  static const qualityLabels = {
    'original': '原画',
    'auto': '自动',
    'bandwidth40m': '4K · 40 Mbps',
    'bandwidth20m': '1080p · 20 Mbps',
    'bandwidth10m': '1080p · 10 Mbps',
    'bandwidth5m': '720p · 5 Mbps',
    'bandwidth2m': '480p · 2 Mbps',
    'bandwidth1m': '360p · 1 Mbps',
  };

  /// The stream's choices, when a Jellyfin or Emby server sends what plays.
  Map<String, Object?>? get _stream {
    final s = _session;
    if (s == null || s.sources.plan?.serverSession == null) return null;
    try {
      return s.sources.streamOptions();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = NextMotion.reduced(context);
    return PlayerMenuSurface(
      width: _page == _Page.root ? 300 : 320,
      child: AnimatedSize(
        duration: reduced ? Duration.zero : const Duration(milliseconds: 220),
        curve: NextMotion.ease,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 160),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, if (current != null) current],
          ),
          child: KeyedSubtree(
            key: ValueKey(_page),
            child: switch (_page) {
              _Page.root => _root(),
              _Page.rate => _rate(),
              _Page.audio => _audioPage(),
              _Page.fit => _fit(),
              _Page.chapters => _chapters(),
              _Page.danmaku => _DanmakuPage(
                  playback: _playback,
                  settings: widget.settings,
                  onBack: back,
                  onOpen: _open,
                  set: _set),
              _Page.playback => _playbackPage(),
              _Page.quality => _quality(),
              _Page.info => _PlaybackInfo(playback: _playback, onBack: back),
              _Page.danmakuStyle => _danmakuStyle(),
              _Page.blockWords => PlayerSettings(
                  data: widget.settings,
                  builder: (context, m) => PlayerSettingsPage(
                    title: '屏蔽词',
                    onBack: back,
                    children: [
                      PlayerSettingWords(model: m, setting: 'danmaku.blockWords')
                    ],
                  ),
                ),
              _Page.danmakuTracks => _DanmakuTracks(
                  playback: _playback, calls: widget.calls, onBack: back),
              _Page.danmakuList =>
                _DanmakuList(playback: _playback, onBack: back),
              _Page.send => _SendDanmaku(calls: widget.calls, onBack: back),
            },
          ),
        ),
      ),
    );
  }

  Widget _root() => PlaybackSelector<(double, bool, VideoAspectMode)>(
        playback: _playback,
        selector: (s) => (s.rate, s.canFit, s.fit),
        builder: (context, v, _) {
          final (rate, canFit, fit) = v;
          final audio = _audio.where((a) => a.selected).firstOrNull;
          final stream = _stream;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            PlayerMenuLink(
                label: '倍速',
                value: rateText(rate),
                onTap: () => _open(_Page.rate)),
            if (_audio.length > 1)
              PlayerMenuLink(
                  label: '音轨',
                  value: audio?.label,
                  onTap: () => _open(_Page.audio)),
            if (canFit)
              PlayerMenuLink(
                  label: '画面',
                  value: fitLabels[fit],
                  onTap: () => _open(_Page.fit)),
            if (_playback.offersDanmaku)
              PlayerMenuLink(label: '弹幕', onTap: () => _open(_Page.danmaku)),
            if (stream != null)
              PlayerMenuLink(
                  label: '清晰度',
                  value: qualityLabels[stream['quality']],
                  onTap: () => _open(_Page.quality)),
            PlayerMenuLink(
                label: '播放设置', onTap: () => _open(_Page.playback)),
            if (_session != null)
              PlayerMenuLink(label: '播放信息', onTap: () => _open(_Page.info)),
            if (_playback.offersScreenshot || _playback.canPictureInPicture)
              const PlayerMenuDivider(),
            if (_playback.offersScreenshot)
              MenuItem(label: '截图', onTap: widget.onScreenshot),
            if (_playback.canPictureInPicture)
              MenuItem(label: '画中画', onTap: widget.onPictureInPicture),
            if (_session case final next?) ...[
              PlayerMenuLink(label: '章节', onTap: () => _open(_Page.chapters)),
              MenuItem(label: '逐帧后退（,）', onTap: () => _set(() async {
                await next.inspection.inspect('playback.navigate', {'frameDelta': -1});
              })),
              MenuItem(label: '逐帧前进（.）', onTap: () => _set(() async {
                await next.inspection.inspect('playback.navigate', {'frameDelta': 1});
              })),
              MenuItem(label: '截取 GIF', onTap: () => _set(() => showNextGifDialog(context, next))),
              if (next.canPictureInPicture)
                MenuItem(label: next.windows.detached ? '返回主窗口' : '分离窗口',
                    onTap: () => _set(next.windows.detached ? next.windows.returnToMain : next.detach)),
            ],
          ]);
        },
      );

  Widget _chapters() {
    final chapters = _session?.session?.media.value?.chapters;
    return _list<int>(title: '章节',
      options: [for (final (i, c) in (chapters ?? []).indexed)
        (i, '${c.title.isEmpty ? '章节 ${i + 1}' : c.title} · ${c.startMs ~/ 60000}:${((c.startMs ~/ 1000) % 60).toString().padLeft(2, '0')}')],
      selected: (_) => false,
      onTap: (index) => _set(() async {
        await _playback.inspection.inspect('playback.navigate', {'chapterIndex': index});
        back();
      }));
  }

  Widget _list<T>({
    required String title,
    required List<(T, String)> options,
    required bool Function(T) selected,
    required void Function(T) onTap,
    List<Widget> header = const [],
  }) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Align(
            alignment: Alignment.centerLeft,
            child: PlayerMenuBack(title, onTap: back)),
        ...header,
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (option, label) in options)
                MenuItem(
                  label: label,
                  selected: selected(option),
                  trailing: selected(option)
                      ? const NextIcon(NextGlyph.check,
                          size: 15, color: NextColors.paper)
                      : null,
                  onTap: () => onTap(option),
                ),
            ]),
          ),
        ),
      ]);

  Widget _rate() => PlaybackSelector<double>(
        playback: _playback,
        selector: (s) => s.rate,
        builder: (context, rate, _) {
          bool same(double a, double b) => (a - b).abs() < 0.001;
          final rates = [
            ...NextPlayback.rates,
            if (!NextPlayback.rates.any((r) => same(r, rate))) rate,
          ]..sort();
          return _list<double>(
            title: '倍速',
            header: [
              PlayerSettingRow(
                label: '自定义',
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FieldControl(
                    value: rateText(rate).replaceAll('×', ''),
                    width: 88,
                    numeric: true,
                    align: TextAlign.right,
                    hint: '0.01–5',
                    onCommit: (text) {
                      final v = double.tryParse(text.trim());
                      if (v == null || v <= 0) return;
                      _set(() => _playback.setRate(v.clamp(0.01, 5).toDouble()));
                    },
                  ),
                ),
              ),
              const PlayerMenuDivider(),
            ],
            options: [for (final r in rates) (r, rateText(r))],
            selected: (r) => same(r, rate),
            onTap: (r) {
              back();
              _set(() => _playback.setRate(r));
            },
          );
        },
      );

  Widget _audioPage() => _list<AudioChoice>(
        title: '音轨',
        options: [for (final a in _audio) (a, a.label)],
        selected: (a) => a.selected,
        onTap: (a) {
          back();
          _set(() async {
            await _playback.chooseAudio(a);
            // The player switches without Classic notifying.
            if (mounted) setState(() => _audio = _readAudio());
          });
        },
      );

  Widget _fit() => PlaybackSelector<VideoAspectMode>(
        playback: _playback,
        selector: (s) => s.fit,
        builder: (context, fit, _) => _list<VideoAspectMode>(
          title: '画面',
          options: [
            for (final mode in VideoAspectMode.values)
              (mode, fitLabels[mode] ?? mode.name)
          ],
          selected: (mode) => mode == fit,
          onTap: (mode) {
            back();
            _set(() => _playback.setFit(mode));
          },
        ),
      );

  /// Classic's 播放设置: how far ← and → go, how fast → held plays.
  Widget _playbackPage() => PlayerSettings(
        data: widget.settings,
        builder: (context, m) => PlayerSettingsPage(
          title: '播放设置',
          onBack: back,
          children: [
            PlayerSettingStepper(
                model: m,
                setting: 'seek.stepSeconds',
                label: '快进快退',
                min: 1,
                max: 120,
                step: 1,
                rest: 10,
                unit: DialUnit.length),
            PlayerSettingStepper(
                model: m,
                setting: 'seek.speedBoostRate',
                label: '长按倍速',
                min: 1.25,
                max: 5,
                step: 0.25,
                rest: 2,
                unit: DialUnit.times),
            PlayerSettingToggle(
                model: m,
                setting: 'player.timelinePreviewEnabled',
                label: '进度条预览'),
            PlayerSettingToggle(
                model: m,
                setting: 'danmaku.showDensityChart',
                label: '进度条上的弹幕密度'),
          ],
        ),
      );

  Widget _quality() {
    final stream = _stream;
    final session = _session;
    if (stream == null || session == null) {
      return _list<String>(
          title: '清晰度',
          options: const [],
          selected: (_) => false,
          onTap: (_) {});
    }
    final qualities = [
      for (final q in (stream['qualities'] as List?) ?? const [])
        if (qualityLabels.containsKey(q)) '$q'
    ]..sort((a, b) => qualityLabels.keys
        .toList()
        .indexOf(a)
        .compareTo(qualityLabels.keys.toList().indexOf(b)));
    return _list<String>(
      title: '清晰度',
      options: [for (final q in qualities) (q, qualityLabels[q]!)],
      selected: (q) => q == stream['quality'],
      onTap: (q) {
        back();
        _set(() => session.sources
            .selectStream({'quality': q, 'transcode': q != 'original'}));
      },
    );
  }

  /// The rest of Classic's 弹幕设置: outline, shadow, font, colours, how
  /// the tracks are spaced.
  Widget _danmakuStyle() => PlayerSettings(
        data: widget.settings,
        builder: (context, m) => PlayerSettingsPage(
          title: '弹幕样式',
          onBack: back,
          children: [
            PlayerSettingChoices(
                model: m,
                setting: 'danmaku.outlineStyle',
                label: '描边',
                options: const [
                  ('none', '无'),
                  ('stroke', '标准'),
                  ('uniform', '均匀'),
                ]),
            PlayerSettingChoices(
                model: m,
                setting: 'danmaku.outlineWidth',
                label: '描边粗细',
                options: const [(0.0, '无'), (1.0, '细'), (2.0, '粗')]),
            PlayerSettingChoices(
                model: m,
                setting: 'danmaku.shadowStyle',
                label: '阴影',
                options: const [
                  ('none', '无'),
                  ('soft', '柔和'),
                  ('medium', '标准'),
                  ('strong', '增强'),
                ]),
            PlayerSettingField(
                model: m,
                setting: 'danmaku.fontFamily',
                label: '字体',
                hint: '系统默认'),
            PlayerSettingSlider(
                model: m,
                setting: 'danmaku.trackGap',
                label: '轨道间距',
                min: 0,
                max: 2,
                step: 0.05,
                unit: DialUnit.decimal),
            PlayerSettingToggle(
                model: m, setting: 'danmaku.stacking', label: '弹幕堆叠'),
            PlayerSettingToggle(
                model: m, setting: 'danmaku.randomColor', label: '随机颜色'),
          ],
        ),
      );
}

/// How danmaku look while this plays, and for what plays next: how
/// opaque and large, how much of the screen they take, how fast they run,
/// the kinds kept away, how early or late they come; the pages behind:
/// their style, blocked words, tracks, the list, sending one.
class _DanmakuPage extends StatefulWidget {
  const _DanmakuPage({
    required this.playback,
    required this.settings,
    required this.onBack,
    required this.onOpen,
    required this.set,
  });
  final NextPlayback playback;
  final NextSettingsData settings;
  final VoidCallback onBack;
  final void Function(_Page page) onOpen;
  final void Function(Future<void> Function() change) set;

  @override
  State<_DanmakuPage> createState() => _DanmakuPageState();
}

class _DanmakuPageState extends State<_DanmakuPage> {
  NextPlayback get _playback => widget.playback;
  SessionPlayback? get _session =>
      _playback is SessionPlayback ? _playback as SessionPlayback : null;

  // A block takes effect in Classic's merged list, which does not always
  // notify; the page reads it again once it is set.
  void _block(DanmakuLane lane, bool on) => widget.set(() async {
        await _playback.block(lane, on);
        if (mounted) setState(() {});
      });

  void _write(String key, Object? value) => widget.set(() async {
        await _session?.danmaku.writeSetting(key, value);
        if (mounted) setState(() {});
      });

  /// What this page and its style page set, back to NipaPlay's own.
  static const _resettable = [
    'danmaku.opacity',
    'danmaku.fontSize',
    'danmaku.displayArea',
    'danmaku.speedMultiplier',
    'danmaku.blockTop',
    'danmaku.blockBottom',
    'danmaku.blockScroll',
    'danmaku.merge',
    'danmaku.outlineStyle',
    'danmaku.outlineWidth',
    'danmaku.shadowStyle',
    'danmaku.fontFamily',
    'danmaku.trackGap',
    'danmaku.stacking',
    'danmaku.randomColor',
  ];

  @override
  Widget build(BuildContext context) => PlaybackSelector<
          (PlayerDial, PlayerDial, double, PlayerDial, int, double, bool, int)>(
        playback: _playback,
        selector: (_) => (
          _playback.danmakuOpacity,
          _playback.danmakuSize,
          _playback.danmakuArea,
          _playback.danmakuOffset,
          [
            for (final (i, lane) in DanmakuLane.values.indexed)
              if (_playback.blocked(lane)) 1 << i
          ].fold(0, (a, b) => a | b),
          _session?.danmaku.number('danmaku.speedMultiplier') ?? 1,
          _session?.danmaku.settings['danmaku.merge'] == true,
          _session?.danmakuPort().registry.length ?? 0,
        ),
        builder: (context, v, _) {
          final (opacity, size, area, offset, _, speed, merge, tracks) = v;
          final session = _session;
          final words =
              (session?.danmaku.settings['danmaku.blockWords'] as List?)
                      ?.length ??
                  0;
          final room = MediaQuery.sizeOf(context).height - 150;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
                alignment: Alignment.centerLeft,
                child: PlayerMenuBack('弹幕', onTap: widget.onBack)),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: math.max(200, math.min(520, room))),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  PlayerMenuRow(
                    label: '透明度',
                    child: PlayerMenuSlider(
                      label: '透明度',
                      dial: opacity,
                      onChanged: (x) =>
                          widget.set(() => _playback.setDanmakuOpacity(x)),
                    ),
                  ),
                  PlayerMenuRow(
                    label: '字号',
                    child: PlayerMenuSlider(
                      label: '字号',
                      dial: size,
                      onChanged: (x) =>
                          widget.set(() => _playback.setDanmakuSize(x)),
                      onEnd: (x) => widget.set(
                          () => _playback.setDanmakuSize(x, done: true)),
                    ),
                  ),
                  if (session != null)
                    PlayerMenuRow(
                      label: '速度',
                      child: PlayerMenuSlider(
                        label: '速度',
                        dial: PlayerDial(speed.clamp(0.5, 2).toDouble(), 0.5,
                            2, 0.05, DialUnit.times),
                        onChanged: (_) {},
                        onEnd: (x) => _write('danmaku.speedMultiplier', x),
                      ),
                    ),
                  PlayerMenuRow(
                    label: '区域',
                    child: PlayerMenuChoices<double>(
                      value: area,
                      options: [
                        for (final (i, a) in NextPlayback.danmakuAreas.indexed)
                          (a, MoreMenuState.areaLabels[i])
                      ],
                      onChanged: (a) =>
                          widget.set(() => _playback.setDanmakuArea(a)),
                    ),
                  ),
                  PlayerMenuRow(
                    label: '屏蔽',
                    child: PlayerMenuChips<DanmakuLane>(
                      options: const [
                        (DanmakuLane.top, '顶部'),
                        (DanmakuLane.bottom, '底部'),
                        (DanmakuLane.scroll, '滚动'),
                      ],
                      on: _playback.blocked,
                      onChanged: _block,
                    ),
                  ),
                  PlayerMenuRow(
                    label: '偏移',
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: PlayerMenuStepper(
                        label: '弹幕偏移',
                        dial: offset,
                        onChanged: _playback.setDanmakuOffset,
                      ),
                    ),
                  ),
                  if (session != null) ...[
                    PlayerSettingRow(
                      label: '合并相同弹幕',
                      labelWidth: 200,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: NextToggle(
                          value: merge,
                          label: '合并相同弹幕',
                          onChanged: (on) => _write('danmaku.merge', on),
                        ),
                      ),
                    ),
                    const PlayerMenuDivider(),
                    PlayerMenuLink(
                        label: '样式',
                        onTap: () => widget.onOpen(_Page.danmakuStyle)),
                    PlayerMenuLink(
                        label: '屏蔽词',
                        value: words == 0 ? null : '$words',
                        onTap: () => widget.onOpen(_Page.blockWords)),
                    PlayerMenuLink(
                        label: '弹幕轨道',
                        value: tracks == 0 ? null : '$tracks',
                        onTap: () => widget.onOpen(_Page.danmakuTracks)),
                    PlayerMenuLink(
                        label: '弹幕列表',
                        onTap: () => widget.onOpen(_Page.danmakuList)),
                    PlayerMenuLink(
                        label: '发送弹幕',
                        onTap: () => widget.onOpen(_Page.send)),
                    const PlayerMenuDivider(),
                    PlayerSettingAction(
                      label: '恢复默认',
                      onTap: () => widget.set(() async {
                        await widget.settings.reset(_resettable);
                        if (mounted) setState(() {});
                      }),
                    ),
                  ],
                  const SizedBox(height: 4),
                ]),
              ),
            ),
          ]);
        },
      );
}

/// The danmaku tracks of what plays, as Classic's 弹幕轨道: each one's
/// source and count, on or off, taken away; a file added.
class _DanmakuTracks extends StatefulWidget {
  const _DanmakuTracks(
      {required this.playback, required this.calls, required this.onBack});
  final NextPlayback playback;
  final GuiCalls calls;
  final VoidCallback onBack;

  @override
  State<_DanmakuTracks> createState() => _DanmakuTracksState();
}

class _DanmakuTracksState extends State<_DanmakuTracks> {
  String? _error;
  bool _adding = false;

  static String _source(Map<String, Object?> t) {
    final source = '${t['source'] ?? t['platform'] ?? ''}';
    return switch (source) {
      'dandanplay' => '弹弹play',
      'local' || 'file' => '本地文件',
      'bilibili' => '哔哩哔哩',
      '' => '弹幕',
      _ => source,
    };
  }

  Future<void> _run(Future<void> Function() change) async {
    setState(() => _error = null);
    try {
      await change();
    } on Failure {
      if (mounted) setState(() => _error = '没有改成，稍后再试');
    } catch (e) {
      debugPrint('[NextPlayer] danmaku track: $e');
      if (mounted) setState(() => _error = '没有改成，稍后再试');
    }
  }

  Future<void> _add() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: '弹幕', extensions: ['xml', 'json'])
    ]);
    if (file == null || !mounted) return;
    setState(() => _adding = true);
    await _run(() => widget.calls.call('danmaku.import', {
          'filePath': file.path,
          'platform': 'local',
          'platformVideoId': file.name,
          'current': true,
        }));
    if (mounted) setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    return ValueListenableBuilder<int>(
      valueListenable: playback.danmakuVersion,
      builder: (context, _, __) {
        final tracks = playback.danmakuPort().registry;
        final total = tracks.fold<int>(
            0, (n, t) => n + ((t['count'] as num?)?.toInt() ?? 0));
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
              alignment: Alignment.centerLeft,
              child: PlayerMenuBack(
                  tracks.isEmpty ? '弹幕轨道' : '弹幕轨道 · $total 条',
                  onTap: widget.onBack)),
          if (tracks.isEmpty)
            SizedBox(
              height: 52,
              child: Center(
                child: Text('还没有弹幕',
                    style: NextText.sans(13, color: NextColors.p3)),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final t in tracks) _track(t),
                ]),
              ),
            ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: Text(error,
                  style: NextText.sans(12, color: NextColors.accent)),
            ),
          const PlayerMenuDivider(),
          MenuItem(
            label: _adding ? '正在添加…' : '添加弹幕文件…',
            onTap: () {
              if (!_adding) unawaited(_add());
            },
          ),
        ]);
      },
    );
  }

  Widget _track(Map<String, Object?> t) {
    final id = t['bindingId'];
    final revision = t['revision'];
    final count = (t['count'] as num?)?.toInt();
    final name = '${t['name'] ?? ''}'.trim();
    final offset = ((t['offsetMs'] as num?)?.toInt() ?? 0) / 1000;
    final managed = id is String && revision is int;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name.isEmpty ? _source(t) : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(13.5, color: NextColors.p2)),
              const SizedBox(height: 2),
              Text(
                  [
                    if (name.isNotEmpty) _source(t),
                    if (count != null) '$count 条',
                    if (offset != 0)
                      '${offset > 0 ? '提前' : '延后'} ${offset.abs().toStringAsFixed(1)} 秒',
                  ].join(' · '),
                  style: NextText.sans(11.5, color: NextColors.p3)),
            ],
          ),
        ),
        if (managed) ...[
          NextToggle(
            value: t['enabled'] == true,
            label: '显示这条轨道',
            onChanged: (on) => unawaited(_run(() => widget.calls.call(
                'danmaku.set_enabled',
                {'bindingId': id, 'revision': revision, 'enabled': on}))),
          ),
          const SizedBox(width: 4),
          NextIconButton(
            glyph: NextGlyph.close,
            size: 28,
            label: '移除这条轨道',
            onTap: () => unawaited(_run(() => widget.calls.call(
                'danmaku.detach', {'bindingId': id, 'revision': revision}))),
          ),
        ],
      ]),
    );
  }
}

/// The comments of what plays, in order, as Classic's 弹幕列表: the ones
/// on now marked; a click goes there.
class _DanmakuList extends StatefulWidget {
  const _DanmakuList({required this.playback, required this.onBack});
  final NextPlayback playback;
  final VoidCallback onBack;

  @override
  State<_DanmakuList> createState() => _DanmakuListState();
}

class _DanmakuListState extends State<_DanmakuList> {
  List<(int, String)>? _items;
  final _scroll = ScrollController();
  static const _row = 44.0;

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
    final items = <(int, String)>[];
    try {
      final end = widget.playback.duration.inMilliseconds;
      int? cursor = 0;
      // Read in pages; past twenty thousand the list stops.
      while (cursor != null && items.length < 20000) {
        final page =
            await widget.playback.inspection.inspect('danmaku.entries', {
          'startMs': 0,
          'endMs': end > 0 ? end : 24 * 3600 * 1000,
          'limit': 500,
          'cursor': cursor,
        });
        for (final item in (page['items'] as List?) ?? const []) {
          final m = item as Map;
          items.add((
            (m['mappedTimeMs'] as num?)?.toInt() ?? 0,
            '${m['text'] ?? ''}',
          ));
        }
        cursor = (page['nextCursor'] as num?)?.toInt();
      }
    } catch (e) {
      debugPrint('[NextPlayer] danmaku list: $e');
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    if (!mounted) return;
    setState(() => _items = items);
    final now = widget.playback.position.inMilliseconds;
    final at = items.lastIndexWhere((e) => e.$1 <= now);
    if (at > 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(
              math.min((at - 3) * _row, _scroll.position.maxScrollExtent));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final height = MediaQuery.sizeOf(context).height;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Align(
          alignment: Alignment.centerLeft,
          child: PlayerMenuBack(
              items == null || items.isEmpty
                  ? '弹幕列表'
                  : '弹幕列表 · ${items.length}',
              onTap: widget.onBack)),
      if (items == null)
        const SizedBox(height: 58, child: Center(child: PulseDot()))
      else if (items.isEmpty)
        SizedBox(
          height: 58,
          child: Center(
            child: Text('还没有弹幕',
                style: NextText.sans(13, color: NextColors.p3)),
          ),
        )
      else
        ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: math.max(200, math.min(440, height - 150))),
          child: PlaybackSelector<int>(
            playback: widget.playback,
            selector: (p) => p.position.inSeconds,
            builder: (context, now, _) => ListView.builder(
              controller: _scroll,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemExtent: _row,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final (at, text) = items[i];
                return TimedLine(
                  at: at,
                  text: text,
                  current: at ~/ 1000 == now,
                  onTap: () =>
                      widget.playback.seek(Duration(milliseconds: at)),
                );
              },
            ),
          ),
        ),
    ]);
  }
}

/// A comment of one's own, sent to 弹弹play at where it plays now.
class _SendDanmaku extends StatefulWidget {
  const _SendDanmaku({required this.calls, required this.onBack});
  final GuiCalls calls;
  final VoidCallback onBack;

  @override
  State<_SendDanmaku> createState() => _SendDanmakuState();
}

class _SendDanmakuState extends State<_SendDanmaku> {
  final _text = TextEditingController();
  String _mode = 'scroll';
  int _color = 0xFFFFFFFF;
  bool _sending = false;
  String? _said;

  static const _colors = [
    0xFFFFFFFF,
    0xFFFE0302,
    0xFFFFE133,
    0xFF00CD00,
    0xFF00A0FF,
    0xFFCC0273,
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _said = null;
    });
    String? said;
    try {
      await widget.calls.call(
          'danmaku.send',
          {
            'text': text,
            'mode': _mode,
            'color':
                '#${(_color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
          },
          reportFailure: false);
      _text.clear();
      said = '已发送';
    } on Failure catch (f) {
      said = f.message.contains('login') ? '登录弹弹play后才能发送' : '没有发出去';
    } catch (e) {
      debugPrint('[NextPlayer] send danmaku: $e');
      said = '没有发出去';
    }
    if (mounted) {
      setState(() {
        _sending = false;
        _said = said;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
              alignment: Alignment.centerLeft,
              child: PlayerMenuBack('发送弹幕', onTap: widget.onBack)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: _SendField(
                controller: _text, onSubmitted: () => unawaited(_send())),
          ),
          PlayerSettingRow(
            label: '位置',
            child: PlayerMenuChoices<String>(
              value: _mode,
              options: const [
                ('scroll', '滚动'),
                ('top', '顶部'),
                ('bottom', '底部'),
              ],
              onChanged: (m) => setState(() => _mode = m),
            ),
          ),
          PlayerSettingRow(
            label: '颜色',
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              for (final c in _colors)
                Pressable(
                  onTap: () => setState(() => _color = c),
                  pressScale: 0.9,
                  builder: (context, hovered) => Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(c),
                      border: Border.all(
                          color: c == _color
                              ? NextColors.paper
                              : const Color(0x33FFFFFF),
                          width: c == _color ? 2 : 1),
                    ),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(children: [
              Expanded(
                child: Text(_said ?? '',
                    style: NextText.sans(12, color: NextColors.p3)),
              ),
              PillButton(
                label: _sending ? '发送中' : '发送',
                onTap: () => unawaited(_send()),
              ),
            ]),
          ),
        ],
      );
}

class _SendField extends StatelessWidget {
  const _SendField({required this.controller, required this.onSubmitted});
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NextColors.line),
        ),
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 1,
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          style: NextText.sans(13.5, color: NextColors.paper),
          cursorColor: NextColors.accent,
          cursorWidth: 1.5,
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration.collapsed(
            hintText: '说点什么',
            hintStyle: NextText.sans(13.5, color: NextColors.p4),
          ),
        ),
      );
}

/// What plays and how, as Classic's 播放信息: the kernel, the source, the
/// picture and sound; the full diagnostics copied for a report.
class _PlaybackInfo extends StatefulWidget {
  const _PlaybackInfo({required this.playback, required this.onBack});
  final NextPlayback playback;
  final VoidCallback onBack;

  @override
  State<_PlaybackInfo> createState() => _PlaybackInfoState();
}

class _PlaybackInfoState extends State<_PlaybackInfo> {
  bool _copied = false;

  static String _source(String? kind) => switch (kind) {
        'local' => '本地文件',
        'jellyfin' => 'Jellyfin',
        'emby' => 'Emby',
        'mesh' => '其他设备',
        null => '—',
        _ => '网络',
      };

  static String _rate(int bits) => bits >= 1000000
      ? '${(bits / 1000000).toStringAsFixed(1)} Mbps'
      : '${(bits / 1000).round()} kbps';

  Future<void> _copy() async {
    try {
      final facts = await widget.playback.diagnostics();
      await Clipboard.setData(ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert(facts)));
      if (mounted) setState(() => _copied = true);
    } catch (e) {
      debugPrint('[NextPlayer] copy diagnostics: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.playback;
    final s = p is SessionPlayback ? p : null;
    final session = s?.session;
    return PlaybackSelector<int>(
      playback: p,
      selector: (_) => session?.media.value.hashCode ?? 0,
      builder: (context, _, __) {
        final media = session?.media.value;
        final plan = s?.sources.plan;
        final audio = media == null
            ? null
            : media.audio
                    .where((a) => media.activeAudio.contains(a.index))
                    .firstOrNull ??
                media.audio.firstOrNull;
        final rows = <(String, String)>[
          if (session != null) ('内核', session.kernelId.label),
          ('来源', _source(plan?.source.kind)),
          if (plan?.serverSession case final server?)
            ('串流', server.isTranscoding ? '转码' : '直接播放'),
          if (media != null) ...[
            if (media.format case final f? when f.isNotEmpty) ('容器', f),
            if (media.width > 0)
              ('分辨率', '${media.width} × ${media.height}'),
            if (media.videoCodec case final c? when c.isNotEmpty)
              ('视频', c),
            if (media.frameRate case final f? when f > 0)
              ('帧率', '${f.toStringAsFixed(f == f.roundToDouble() ? 0 : 2)} fps'),
            if (media.bitRate case final b? when b > 0) ('码率', _rate(b)),
            if (audio != null)
              (
                '音频',
                [
                  if (audio.codec case final c? when c.isNotEmpty) c,
                  if (audio.channels case final ch? when ch > 0) '$ch 声道',
                  if (audio.sampleRate case final r? when r > 0)
                    '${(r / 1000).toStringAsFixed(1)} kHz',
                ].join(' · ')
              ),
          ],
          ('弹幕', '${p.danmakuPort().registry.length} 条轨道'),
        ];
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
              alignment: Alignment.centerLeft,
              child: PlayerMenuBack('播放信息', onTap: widget.onBack)),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 64,
                  child: Text(label,
                      style: NextText.sans(12.5, color: NextColors.p3)),
                ),
                Expanded(
                  child: Text(value.isEmpty ? '—' : value,
                      style: NextText.sans(12.5, color: NextColors.p2)),
                ),
              ]),
            ),
          const PlayerMenuDivider(),
          PlayerSettingAction(
              label: _copied ? '已复制诊断' : '复制诊断',
              onTap: () => unawaited(_copy())),
        ]);
      },
    );
  }
}
