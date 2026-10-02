import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/widgets/embedded_subtitle_overlay.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whole-block embedded subtitle mode tests:
/// 1. Kernel contract — enabling the mode writes sub-visibility=no and the
///    app polls sub-text; disabling restores kernel rendering and clears
///    the residue text.
/// 2. External ASS gate — while a kernel-rendered external ASS/SSA is
///    active, the mode steps aside: sub-visibility stays on, the plain-text
///    block stays hidden, polling clears residue; clearing the external
///    resumes the mode.
/// 3. Rendering — the bilingual block renders both lines at slider 0 and
///    100 (line gap can never collapse), with kana-based line-order
///    auto-correction.
class _FakeMediaKitDelegate extends Fake implements MediaKitPlayerAdapter {
  _FakeMediaKitDelegate({this.liveProperties = const {}});

  Map<String, String> liveProperties;
  final Map<String, String> writtenProperties = {};

  @override
  void setProperty(String key, String value) {
    writtenProperties[key] = value;
  }

  @override
  Future<String?> getLiveProperty(String name) async {
    return liveProperties[name];
  }

  // The external subtitle selection/clear paths touch these members
  // (guards evaluate before short-circuiting); leaving them unimplemented
  // would abort setExternalSubtitle and keep stale state.
  @override
  bool get supportsExternalSubtitles => true;

  @override
  List<int> get activeSubtitleTracks => const [];

  @override
  void setMedia(String path, PlayerMediaType type) {}

  // The player= setter probes buffering state through the facade.
  @override
  ValueListenable<bool> get buffering => ValueNotifier<bool>(false);
}

Future<VideoPlayerState> _buildVideoPlayerState(
    AbstractPlayer delegate) async {
  // Construct the state against the inert video_player kernel (no native
  // library loads in the test env); the Media Kit fake delegate is swapped
  // in right after, which is what the assertions below observe.
  SharedPreferences.setMockInitialValues(<String, Object>{
    'player_kernel_type': PlayerKernelType.videoPlayer.index,
  });
  await PlayerFactory.initialize();
  final videoState = VideoPlayerState();
  final player = Player.withDelegate(delegate);
  videoState.player = player;
  // In production player_kernel_manager syncs the managers with the player
  // facade on kernel swaps; tests must do it manually, otherwise
  // SubtitleManager still holds the un-materialized lazy delegate (kernel
  // name "未知") and the external-ASS gate never engages.
  videoState.subtitleManager.updatePlayer(player);
  return videoState;
}

Widget _wrap(Widget child, VideoPlayerState videoState) {
  return ChangeNotifierProvider<VideoPlayerState>.value(
    value: videoState,
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('whole-block mode writes sub-visibility and polls sub-text',
      (tester) async {
    final delegate = _FakeMediaKitDelegate(liveProperties: {
      'sub-text': '中文翻译行\n日本語原文行',
    });
    final videoState = await _buildVideoPlayerState(delegate);

    await videoState.setEmbeddedSubtitleOverlayMode(true);
    expect(
      delegate.writtenProperties['sub-visibility'],
      'no',
      reason: 'Enabling whole-block mode must hide kernel rendering',
    );
    videoState.pollEmbeddedSubtitleOverlayText();
    await tester.pump();
    await tester.pump();
    expect(videoState.embeddedSubtitleOverlayText, '中文翻译行\n日本語原文行');

    await videoState.setEmbeddedSubtitleOverlayMode(false);
    expect(
      delegate.writtenProperties['sub-visibility'],
      'yes',
      reason: 'Disabling whole-block mode must restore kernel rendering',
    );
    expect(videoState.embeddedSubtitleOverlayText, isEmpty);
  });

  testWidgets('whole-block mode steps aside for kernel-rendered external ASS',
      (tester) async {
    final delegate = _FakeMediaKitDelegate(liveProperties: {
      'sub-text': '中文翻译行\n日本語原文行',
    });
    final videoState = await _buildVideoPlayerState(delegate);

    // Inject an active kernel-track external ASS without touching the
    // filesystem or the kernel.
    const assPath = 'Z:/sample.chs.ass';
    videoState.setCurrentExternalSubtitlePath(assPath);
    videoState.updateDanmakuTrackInfo('external_subtitle', <String, dynamic>{
      'path': assPath,
      'title': '外挂ASS',
      'isActive': true,
      'isManualSet': true,
    });
    expect(videoState.isKernelRenderedExternalAssActive, isTrue);

    await videoState.setEmbeddedSubtitleOverlayMode(true);
    expect(
      delegate.writtenProperties['sub-visibility'],
      isNot('no'),
      reason: 'External ASS must keep libass script rendering; '
          'sub-visibility must not be turned off',
    );

    // The plain-text block must step back entirely, otherwise \pos
    // positioning and colored annotations get flattened into white
    // centered text drawn on top of the libass render.
    videoState.debugSetEmbeddedSubtitleOverlayText('中文翻译行\n日本語原文行');
    await tester.pumpWidget(_wrap(
      const SizedBox(
        width: 800,
        height: 600,
        child: EmbeddedSubtitleOverlay(),
      ),
      videoState,
    ));
    await tester.pump();
    expect(find.textContaining('中文翻译行'), findsNothing);

    // Polling must not refill the block while the external ASS is active,
    // and must drop any residue collected before the switch.
    videoState.pollEmbeddedSubtitleOverlayText();
    await tester.pump();
    await tester.pump();
    expect(videoState.embeddedSubtitleOverlayText, isEmpty);

    // Clearing the external subtitle hands control back to the mode:
    // sub-visibility=no again and the plain-text block renders.
    videoState.setExternalSubtitle('');
    expect(
      delegate.writtenProperties['sub-visibility'],
      'no',
      reason: 'Whole-block mode must resume after the external is cleared',
    );
    videoState.debugSetEmbeddedSubtitleOverlayText('中文翻译行\n日本語原文行');
    await tester.pump();
    expect(find.textContaining('中文翻译行'), findsNWidgets(2)); // stroke + fill
  });

  testWidgets(
      'bilingual line order auto-corrects: translation above, original below',
      (tester) async {
    final delegate = _FakeMediaKitDelegate(liveProperties: {
      // Kernel event order can put the Japanese line first.
      'sub-text': '日本語原文行テスト\n中文翻译行',
    });
    final videoState = await _buildVideoPlayerState(delegate);
    await videoState.setEmbeddedSubtitleOverlayMode(true);
    videoState.pollEmbeddedSubtitleOverlayText();
    await tester.pump();
    await tester.pump();

    // Kana lines are the original (bottom), pure-Han lines the translation
    // (top) — no manual switch needed.
    expect(videoState.embeddedSubtitleOverlayDisplayText,
        '中文翻译行\n日本語原文行テスト');
    await tester.pumpWidget(_wrap(
      const SizedBox(
        width: 800,
        height: 600,
        child: EmbeddedSubtitleOverlay(),
      ),
      videoState,
    ));
    await tester.pump();
    expect(find.text('中文翻译行\n日本語原文行テスト'), findsNWidgets(2));

    // Already-correct kernel order stays untouched. (Polling throttles on
    // the real clock; tests inject via the debug entry point.)
    videoState.debugSetEmbeddedSubtitleOverlayText('中文翻译行\n日本語原文行テスト');
    await tester.pump();
    expect(videoState.embeddedSubtitleOverlayDisplayText,
        '中文翻译行\n日本語原文行テスト');

    // All-kana (pure Japanese) block: no evidence to reorder, keep as-is.
    videoState.debugSetEmbeddedSubtitleOverlayText('日本語一行目\n日本語二行目');
    await tester.pump();
    expect(videoState.embeddedSubtitleOverlayDisplayText,
        '日本語一行目\n日本語二行目');
  });

  testWidgets('bilingual block renders both lines at slider 0 and 100',
      (tester) async {
    final delegate = _FakeMediaKitDelegate(liveProperties: {
      'sub-text': '中文翻译行\n日本語原文行',
    });
    final videoState = await _buildVideoPlayerState(delegate);
    await videoState.setEmbeddedSubtitleOverlayMode(true);
    videoState.pollEmbeddedSubtitleOverlayText();
    await tester.pump();
    await tester.pump();

    Future<void> pumpAtPosition(double position) async {
      await videoState.setSubtitlePosition(position);
      await tester.pumpWidget(_wrap(
        const SizedBox(
          width: 800,
          height: 600,
          child: EmbeddedSubtitleOverlay(),
        ),
        videoState,
      ));
      await tester.pump();
    }

    // Position 0 (top): both lines must render in full — the whole-block
    // mode can never collapse the authored line gap.
    await pumpAtPosition(0);
    expect(find.textContaining('中文翻译行'), findsNWidgets(2)); // stroke + fill
    expect(find.textContaining('日本語原文行'), findsNWidgets(2));
    final alignAtTop = tester.widget<Align>(
      find.ancestor(
        of: find.textContaining('中文翻译行'),
        matching: find.byType(Align),
      ).first,
    );
    expect((alignAtTop.alignment as Alignment).y, -1);

    // Position 100 (bottom): the same block moved as a whole, both lines
    // still complete.
    await pumpAtPosition(100);
    expect(find.textContaining('中文翻译行'), findsNWidgets(2));
    expect(find.textContaining('日本語原文行'), findsNWidgets(2));
    final alignAtBottom = tester.widget<Align>(
      find.ancestor(
        of: find.textContaining('中文翻译行'),
        matching: find.byType(Align),
      ).first,
    );
    expect((alignAtBottom.alignment as Alignment).y, 1);
  });
}
