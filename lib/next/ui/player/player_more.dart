import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import 'menu_controls.dart';
import 'playback.dart';

enum _Page { root, rate, audio, fit, danmaku }

/// What the bar has no room for: the speed, the audio track, how the
/// picture fits, the danmaku's look; a still of the picture, picture in
/// picture. Each choice is Classic's own setting, set as its player menu
/// sets it.
class MoreMenu extends StatefulWidget {
  const MoreMenu({
    super.key,
    required this.playback,
    required this.onScreenshot,
    required this.onPictureInPicture,
  });
  final NextPlayback playback;
  final VoidCallback onScreenshot;
  final VoidCallback onPictureInPicture;

  @override
  State<MoreMenu> createState() => MoreMenuState();
}

class MoreMenuState extends State<MoreMenu> {
  _Page _page = _Page.root;
  List<AudioChoice> _audio = const [];

  NextPlayback get _playback => widget.playback;

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

  /// Esc on a page goes back to the menu; false on the menu itself.
  bool back() {
    if (_page == _Page.root) return false;
    setState(() => _page = _Page.root);
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

  @override
  Widget build(BuildContext context) {
    final reduced = NextMotion.reduced(context);
    return PlayerMenuSurface(
      width: 300,
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
              _Page.danmaku =>
                _DanmakuPage(playback: _playback, onBack: back, set: _set),
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
            if (_playback.offersScreenshot || _playback.canPictureInPicture)
              const PlayerMenuDivider(),
            if (_playback.offersScreenshot)
              MenuItem(label: '截图', onTap: widget.onScreenshot),
            if (_playback.canPictureInPicture)
              MenuItem(label: '画中画', onTap: widget.onPictureInPicture),
          ]);
        },
      );

  Widget _list<T>({
    required String title,
    required List<(T, String)> options,
    required bool Function(T) selected,
    required void Function(T) onTap,
  }) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Align(
            alignment: Alignment.centerLeft,
            child: PlayerMenuBack(title, onTap: back)),
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
}

/// How danmaku look while this plays, and for what plays next: how
/// opaque and large, how much of the screen they take, the kinds kept
/// away, how early or late they come.
class _DanmakuPage extends StatefulWidget {
  const _DanmakuPage(
      {required this.playback, required this.onBack, required this.set});
  final NextPlayback playback;
  final VoidCallback onBack;
  final void Function(Future<void> Function() change) set;

  @override
  State<_DanmakuPage> createState() => _DanmakuPageState();
}

class _DanmakuPageState extends State<_DanmakuPage> {
  NextPlayback get _playback => widget.playback;

  // A block takes effect in Classic's merged list, which does not always
  // notify; the page reads it again once it is set.
  void _block(DanmakuLane lane, bool on) => widget.set(() async {
        await _playback.block(lane, on);
        if (mounted) setState(() {});
      });

  @override
  Widget build(BuildContext context) => PlaybackSelector<
          (PlayerDial, PlayerDial, double, PlayerDial, int)>(
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
        ),
        builder: (context, v, _) {
          final (opacity, size, area, offset, _) = v;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
                alignment: Alignment.centerLeft,
                child: PlayerMenuBack('弹幕', onTap: widget.onBack)),
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
                onChanged: (x) => widget.set(() => _playback.setDanmakuSize(x)),
                onEnd: (x) =>
                    widget.set(() => _playback.setDanmakuSize(x, done: true)),
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
                onChanged: (a) => widget.set(() => _playback.setDanmakuArea(a)),
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
            const SizedBox(height: 4),
          ]);
        },
      );
}
