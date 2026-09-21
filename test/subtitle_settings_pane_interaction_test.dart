import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_player_slider.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_subtitle_settings_pane.dart';
import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

/// 字幕设置面板交互测试（spec SUB-01/SUB-02/SUB-03，AC-1/5/6 的
/// 可自动化子集）。
///
/// 边界说明：VideoPlayerState 的 setSubtitlePosition、pathSubtitle* 等
/// 均为 extension 方法（Dart extension 不参与动态分发，mock 无法覆盖），
/// 因此「onChangeEnd 恰好提交一次到内核」与外挂叠层手势（OVER 系列）
/// 无法在 widget 层用 fake 验证——改由 analyze 结构断言 + 真机验收，
/// 见 spec 的「人类验证层」。本文件覆盖：
///  - SUB-01：拖动过程只更新预览，onChanged 全程零内核调用、滑块跟手；
///  - SUB-02：色块命中区可点，弹出 HSV 调色板；
///  - SUB-03：键盘弹出时底部 padding 增加一个键盘高度。
class _FakePlayer implements Player {
  @override
  PlayerMediaInfo get mediaInfo =>
      PlayerMediaInfo(duration: 0, subtitle: const [], audio: const []);

  @override
  String getPlayerKernelName() => 'Media Kit';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeVideoPlayerState extends ChangeNotifier implements VideoPlayerState {
  _FakeVideoPlayerState();

  final _FakePlayer _player = _FakePlayer();

  /// 真实 extension 方法被调用时记录（用于证明 onChanged 未触碰内核）。
  final List<String> extensionCalls = [];

  final double _position = 80;

  @override
  Player get player => _player;

  @override
  double get subtitlePosition => _position;
  @override
  double get subtitleScale => 1;
  @override
  double get srtSubtitleScale => 1;
  @override
  double get subtitleMarginX => 10;
  @override
  double get subtitleMarginY => 10;
  @override
  double get subtitleOpacity => 1;
  @override
  double get subtitleBorderSize => 2;
  @override
  double get subtitleShadowOffset => 1;
  @override
  double get subtitleDelaySeconds => 0;
  @override
  bool get subtitleBold => false;
  @override
  bool get subtitleItalic => false;
  @override
  SubtitleStyleOverrideMode get subtitleOverrideMode =>
      SubtitleStyleOverrideMode.auto;
  @override
  SubtitleAlignX get subtitleAlignX => SubtitleAlignX.center;
  @override
  SubtitleAlignY get subtitleAlignY => SubtitleAlignY.bottom;
  @override
  Color get subtitleColor => Colors.white;
  @override
  Color get subtitleBorderColor => Colors.black;
  @override
  Color get subtitleShadowColor => Colors.black;
  @override
  String get subtitleFontName => '';
  @override
  String get subtitleFontDir => '';
  @override
  bool get hasSubtitleDelayDurationLimit => false;
  @override
  double get subtitleDelayCustomLimitSeconds => 600;
  @override
  double get subtitleDelaySliderMinSeconds => -60;
  @override
  double get subtitleDelaySliderMaxSeconds => 60;
  @override
  int get subtitleDelaySliderDivisions => 120;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // extension 方法（setSubtitlePosition 等）会落到这里；记录名字以便
    // 断言「拖动过程零内核调用」。
    final name = invocation.memberName.toString();
    extensionCalls.add(name);
    if (invocation.isMethod) {
      final args = invocation.positionalArguments;
      if (args.isNotEmpty && args.first is double) {
        return Future<void>.value();
      }
    }
    return super.noSuchMethod(invocation);
  }
}

Widget _wrap(Widget pane, _FakeVideoPlayerState state,
    {required double keyboardInset}) {
  return ChangeNotifierProvider<VideoPlayerState>.value(
    value: state,
    child: ChangeNotifierProvider<SubtitleSettingsPaneController>(
      create: (_) => SubtitleSettingsPaneController(videoState: state),
      child: MaterialApp(
        // MaterialApp 按 View 重置自身 MediaQuery；viewInsets 必须在
        // builder（Navigator 之下没有别的 MediaQuery 拦截）注入。
        // Scaffold 设 resizeToAvoidBottomInset: false——否则 Scaffold
        // 会吞掉 body 的 viewInsets（真机上面板在 Cupertino 弹层路由
        // 中，不经 Scaffold 键盘避让，行为等价）。
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: child!,
        ),
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: pane,
        ),
      ),
    ),
  );
}

/// 位置滑块识别特征：min=0、max=100、divisions=100（其余滑块不同）。
Finder positionSlider() => find.byWidgetPredicate(
      (w) =>
          w is CupertinoPlayerSlider &&
          w.min == VideoPlayerState.minSubtitlePosition &&
          w.max == VideoPlayerState.maxSubtitlePosition &&
          w.divisions == 100,
    );

double _maxContentBottomPadding(WidgetTester tester) {
  // 内容区 SliverPadding 是 EdgeInsets.only(bottom: 12[+inset])；
  // 顶部“回到默认”用 fromLTRB(left/right=20)，据此排除。
  return tester
      .widgetList<SliverPadding>(find.byType(SliverPadding))
      .map((s) => s.padding)
      .whereType<EdgeInsets>()
      .where((p) => p.left == 0 && p.right == 0)
      .map((p) => p.bottom)
      .reduce((a, b) => a > b ? a : b);
}

void main() {
  testWidgets('SUB-01 拖动字幕位置滑块只更新预览，零内核调用', (tester) async {
    final state = _FakeVideoPlayerState();
    await tester.pumpWidget(
        _wrap(const CupertinoSubtitleSettingsPane(), state, keyboardInset: 0));
    await tester.pumpAndSettle();

    final slider = tester.widget<CupertinoPlayerSlider>(positionSlider());
    expect(slider.value, 80);

    slider.onChangeStart?.call(80);
    await tester.pump();
    tester.widget<CupertinoPlayerSlider>(positionSlider()).onChanged(55);
    await tester.pump();
    tester.widget<CupertinoPlayerSlider>(positionSlider()).onChanged(30);
    await tester.pump();

    // AC-1/AC-2 核心：拖动过程绝不触发 setSubtitlePosition
    //（真实路径经 extension → noSuchMethod，一律被记录）
    expect(state.extensionCalls.where((c) => c.contains('setSubtitlePosition')),
        isEmpty);
    // 预览值实时驱动滑块与数值文本（跟手）
    expect(tester.widget<CupertinoPlayerSlider>(positionSlider()).value, 30);
    expect(find.text('30%'), findsOneWidget);
  });

  testWidgets('SUB-02 点击颜色色块弹出 HSV 调色板', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _FakeVideoPlayerState();
    await tester.pumpWidget(
        _wrap(const CupertinoSubtitleSettingsPane(), state, keyboardInset: 0));
    await tester.pumpAndSettle();

    // 色块 = 20x20 的颜色容器（CupertinoButton 44pt 命中区包裹）。
    final swatch = find.byKey(const Key('subtitleColorSwatch'));
    expect(swatch, findsWidgets);
    await tester.tap(swatch.first);
    await tester.pumpAndSettle();

    expect(find.text('选择颜色'), findsOneWidget,
        reason: 'AC-5：点色块任意位置都应弹出调色板');
    expect(find.text('色相'), findsOneWidget);
    expect(find.text('饱和'), findsOneWidget);
    expect(find.text('亮度'), findsOneWidget);
    expect(find.text('十六进制'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.byType(CupertinoTextField),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SUB-03 键盘弹出为输入框垫出键盘高度', (tester) async {
    final state = _FakeVideoPlayerState();
    await tester.pumpWidget(
        _wrap(const CupertinoSubtitleSettingsPane(), state, keyboardInset: 0));
    await tester.pumpAndSettle();
    expect(_maxContentBottomPadding(tester), 12);

    await tester.pumpWidget(
        _wrap(const CupertinoSubtitleSettingsPane(), state, keyboardInset: 300));
    await tester.pumpAndSettle();
    expect(_maxContentBottomPadding(tester), 312,
        reason: 'AC-6：底部 padding 必须加上键盘高度，输入框才能滚出键盘');
  });
}
