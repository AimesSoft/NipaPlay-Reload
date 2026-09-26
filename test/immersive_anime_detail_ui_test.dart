import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/full_backup_service.dart';
import 'package:nipaplay/services/incremental_sync_repository.dart';
import 'package:nipaplay/themes/nipaplay/widgets/adaptive_media_detail_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/immersive_anime_detail_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/immersive_backdrop_focus.dart';
import 'package:nipaplay/themes/nipaplay/widgets/immersive_episode_rail.dart';
import 'package:nipaplay/themes/nipaplay/widgets/immersive_media_detail_route.dart';
import 'package:nipaplay/themes/nipaplay/widgets/immersive_portrait_backdrop_color.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('immersive anime detail lab switch defaults to disabled', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = LabsSettingsProvider();
    await provider.ready;

    expect(provider.enableImmersiveAnimeDetail, isFalse);

    await provider.setEnableImmersiveAnimeDetail(true);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(SettingsKeys.labsEnableImmersiveAnimeDetail),
      isTrue,
    );
  });

  test('immersive anime detail lab switch is restored before route decisions',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsKeys.labsEnableImmersiveAnimeDetail: true,
    });

    final restartedProvider = LabsSettingsProvider();
    await restartedProvider.ready;

    expect(restartedProvider.isLoaded, isTrue);
    expect(restartedProvider.enableImmersiveAnimeDetail, isTrue);
  });

  test('media detail actions do not claim simulated native glass support', () {
    expect(
      AdaptiveMediaDetailActionButton.supportsNativeLiquidGlass,
      isFalse,
    );
  });

  test('detail-rich poster region moves cover display centre upward', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.grey, BlendMode.src);
    for (var row = 35; row < 90; row += 8) {
      for (var column = 10; column < 90; column += 8) {
        canvas.drawRect(
          Rect.fromLTWH(column.toDouble(), row.toDouble(), 4, 4),
          Paint()..color = Colors.pinkAccent,
        );
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 200);
    addTearDown(() {
      image.dispose();
      picture.dispose();
    });

    final alignment = await chooseImmersiveBackdropAlignment(
      image,
      const Size(160, 90),
    );
    expect(alignment.x, 0);
    expect(alignment.y, lessThan(-0.2));
  });

  testWidgets('raw image uses the selected cover alignment', (tester) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 200);
    addTearDown(() {
      image.dispose();
      picture.dispose();
    });
    const alignment = Alignment(0, -0.6);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 160,
          height: 90,
          child: SafeRawImage(
            image: image,
            fit: BoxFit.cover,
            alignment: alignment,
          ),
        ),
      ),
    );
    expect(tester.widget<RawImage>(find.byType(RawImage)).alignment, alignment);
  });

  test('portrait color samples the visible cover edge, not cropped poster end',
      () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 100, 160),
      Paint()..color = Colors.blue,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 160, 100, 40),
      Paint()..color = Colors.red,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 200);
    addTearDown(() {
      image.dispose();
      picture.dispose();
    });

    // A 1:1 hero displays y=50..150, so the red source-image bottom is hidden.
    final color = await extractImmersivePortraitBackdropColor(
      image,
      const Size(100, 100),
    );
    final hsl = HSLColor.fromColor(color);
    expect(hsl.hue, closeTo(HSLColor.fromColor(Colors.blue).hue, 5));
    expect(hsl.lightness, greaterThan(0.22));
    expect(immersivePortraitSecondaryTextContrast(color), greaterThan(4.5));
  });

  test('portrait fill follows the chosen display centre', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.red, BlendMode.src);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()..color = Colors.blue,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 200);
    addTearDown(() {
      image.dispose();
      picture.dispose();
    });

    final upper = await extractImmersivePortraitBackdropColor(
      image,
      const Size(100, 100),
      alignment: Alignment.topCenter,
    );
    final lower = await extractImmersivePortraitBackdropColor(
      image,
      const Size(100, 100),
      alignment: Alignment.bottomCenter,
    );
    expect(HSLColor.fromColor(upper).hue,
        closeTo(HSLColor.fromColor(Colors.blue).hue, 5));
    expect(HSLColor.fromColor(lower).hue,
        closeTo(HSLColor.fromColor(Colors.red).hue, 5));
  });

  test('local portrait poster supplies the lower background color', () async {
    final directory = await Directory.systemTemp.createTemp('nipaplay-hero-');
    addTearDown(() => directory.delete(recursive: true));
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.purple, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 200);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final posterFile = File('${directory.path}/poster.png');
    await posterFile.writeAsBytes(png!.buffer.asUint8List());

    final color = await loadImmersivePortraitBackdropColor(
      posterFile.path,
      const Size(390, 422),
    );
    expect(HSLColor.fromColor(color).hue,
        closeTo(HSLColor.fromColor(Colors.purple).hue, 5));
    expect(HSLColor.fromColor(color).lightness, greaterThan(0.22));
  });

  test('a colourful area is not washed out by neutral poster pixels', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.grey, BlendMode.src);
    canvas.drawRect(
      const Rect.fromLTWH(0, 130, 42, 30),
      Paint()..color = Colors.pinkAccent,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 200);
    addTearDown(() {
      image.dispose();
      picture.dispose();
    });

    final color = await extractImmersivePortraitBackdropColor(
      image,
      const Size(100, 100),
    );
    final hsl = HSLColor.fromColor(color);
    expect(hsl.hue, closeTo(HSLColor.fromColor(Colors.pinkAccent).hue, 10));
    expect(hsl.saturation, greaterThan(0.4));
    expect(immersivePortraitSecondaryTextContrast(color), greaterThan(4.5));
  });

  test('poster-derived fill preserves secondary text contrast', () {
    for (final posterColor in <Color>[
      Colors.white,
      Colors.yellow,
      Colors.cyanAccent,
      Colors.pinkAccent,
      Colors.purple,
      Colors.black,
    ]) {
      final fill = toneImmersivePortraitBackdropColor(posterColor);
      expect(
        immersivePortraitSecondaryTextContrast(fill),
        greaterThanOrEqualTo(4.5),
        reason: 'Low-contrast fill derived from $posterColor',
      );
    }
    final neutralFill = toneImmersivePortraitBackdropColor(Colors.white);
    expect((neutralFill.r - neutralFill.b).abs(), lessThan(0.01));
    final blueFill = toneImmersivePortraitBackdropColor(Colors.blue);
    final pinkFill = toneImmersivePortraitBackdropColor(Colors.pinkAccent);
    expect(
      (HSLColor.fromColor(blueFill).hue - HSLColor.fromColor(pinkFill).hue)
          .abs(),
      greaterThan(80),
    );
  });

  test('anime background survives model cache backup and sync round trips',
      () async {
    const animeId = -991234;
    const backgroundUrl = 'https://example.com/custom-background.jpg';
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final anime = BangumiAnime(
      id: animeId,
      name: 'Test Anime',
      nameCn: '测试动画',
      imageUrl: 'https://example.com/poster.jpg',
      backgroundImageUrl: backgroundUrl,
      summary: '完整媒体信息',
      tags: const <String>['测试'],
      episodeList: <EpisodeData>[
        EpisodeData(id: 1, title: '第一话'),
      ],
    );

    await BangumiService.instance.saveCustomAnimeDetail(animeId, anime);
    final exported =
        await BangumiService.instance.exportAnimeDetailsForBackup();
    const key = '${BangumiService.backupAnimeDetailKeyPrefix}$animeId';
    expect(exported[key]['backgroundImageUrl'], backgroundUrl);
    expect(exported[key]['summary'], '完整媒体信息');
    expect(exported[key]['episodes'], hasLength(1));

    final backupService = FullBackupService();
    final backup = await backupService.collectBackupData(
      categories: const <BackupCategory>{BackupCategory.mediaLibraries},
    );
    expect(
      backup[BackupCategory.mediaLibraries.name][key]['backgroundImageUrl'],
      backgroundUrl,
    );
    final state = IncrementalSyncCodec.flattenBackup(
      backup,
      const <BackupCategory>{BackupCategory.mediaLibraries},
    );
    final inflated = IncrementalSyncCodec.inflateState(state);
    expect(
      inflated[BackupCategory.mediaLibraries.name][key]['backgroundImageUrl'],
      backgroundUrl,
    );

    await BangumiService.instance.deleteAnimeDetailFromBackupKey(key);
    final restoreResult = await backupService.restoreFromData(
      backupData: backup,
      categories: const <BackupCategory>{BackupCategory.mediaLibraries},
    );
    expect(restoreResult.success, isTrue);
    expect(
      BangumiService.instance
          .getAnimeDetailsFromMemory(animeId)
          ?.backgroundImageUrl,
      backgroundUrl,
    );
  });

  test('clearing anime background restores poster fallback metadata', () async {
    const animeId = -991235;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final anime = BangumiAnime(
      id: animeId,
      name: 'Test Anime',
      nameCn: '测试动画',
      imageUrl: 'https://example.com/poster.jpg',
      backgroundImageUrl: 'https://example.com/background.jpg',
    );
    await BangumiService.instance.saveCustomAnimeDetail(animeId, anime);
    final updated = await BangumiService.instance.updateBackgroundImageUrl(
      animeId,
      null,
    );
    expect(updated.backgroundImageUrl, isNull);
    expect(updated.imageUrl, 'https://example.com/poster.jpg');
  });

  test('home recommendation hero preserves poster ratio before cover crop', () {
    final source = File(
      'lib/themes/nipaplay/widgets/dashboard_home_page_build_hero.dart',
    ).readAsStringSync();
    expect(source, contains('fit: BoxFit.cover'));
    expect(source, contains('memCacheWidth: 1280'));
    expect(source, isNot(contains('memCacheHeight: 720')));
    expect(RegExp(r'smartCrop: true').allMatches(source), hasLength(2));
    expect(
        const CachedNetworkImageWidget(imageUrl: 'poster').smartCrop, isFalse);
  });

  test('immersive episode time is limited to reliable local history', () {
    final source = File('lib/pages/anime_detail_page.dart').readAsStringSync();
    expect(source, contains('_hasReliableLocalDuration(history)'));
    expect(
      source,
      isNot(contains('_sharedEpisodeMap[episode.id]?.duration')),
    );
  });

  test('immersive backdrop keeps source ratio at a high-DPI decode width', () {
    expect(resolveImmersiveBackdropDecodeWidth(800, 1), 1280);
    expect(resolveImmersiveBackdropDecodeWidth(1920, 1), 1920);
    expect(resolveImmersiveBackdropDecodeWidth(1280, 2), 2560);
    expect(resolveImmersiveBackdropDecodeWidth(1920, 2), 3840);
    expect(resolveImmersiveBackdropDecodeWidth(3840, 2), 3840);

    final source = File(
      'lib/themes/nipaplay/widgets/immersive_anime_detail_scaffold.dart',
    ).readAsStringSync();
    expect(source, contains('fit: BoxFit.cover'));
    expect(source, contains('memCacheWidth: targetWidth'));
    expect(source, contains('maxDecodeEdge: immersiveBackdropMaxDecodeWidth'));
    expect(source, contains('filterQuality: FilterQuality.high'));
    expect(source, isNot(contains('memCacheHeight:')));
  });

  test('immersive backdrop prefers Bangumi large cover API', () {
    final source = File('lib/pages/anime_detail_page.dart').readAsStringSync();
    expect(source, contains("'type': 'large'"));
    expect(source, contains('/v0/subjects/\$subjectId/image'));
  });

  test('real proxy summary is normalized without introducing blank lines', () {
    const realBocchiSummary =
        '作为网络吉他手“吉他英雄”而广受好评的后藤一里，在现实中却是个什么都不会的沟通障碍者。一里有着组建乐队的梦想，但因为不敢向人主动搭话而一直没有成功，直到一天在公园中被伊地知虹夏发现并邀请进入缺少吉他手的“结束乐队”。可是，完全没有和他人合作经历的一里，在人前完全发挥不出原本的实力。为了努力克服沟通障碍，一里与“结束乐队”的成员们一同开始努力……';
    expect(normalizeImmersiveSummaryText(realBocchiSummary), realBocchiSummary);
    expect(
      normalizeImmersiveSummaryText('第一段<br><br>\n\n第二段'),
      '第一段 第二段',
    );
  });

  test('immersive detail route animates both entry and exit', () {
    final route = ImmersiveMediaDetailPageRoute<void>(
      enableAnimation: true,
      builder: (_) => const SizedBox(),
    );

    expect(route.transitionDuration, const Duration(milliseconds: 360));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 280));
  });

  testWidgets('immersive detail transition reverses when the page is popped',
      (tester) async {
    late BuildContext navigationContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            navigationContext = context;
            return const Scaffold(body: Text('媒体库'));
          },
        ),
      ),
    );

    Navigator.of(navigationContext).push<void>(
      ImmersiveMediaDetailPageRoute<void>(
        enableAnimation: true,
        builder: (_) => const Scaffold(body: Text('媒体详情')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(ScaleTransition), findsWidgets);
    expect(find.text('媒体详情'), findsOneWidget);
    await tester.pumpAndSettle();

    Navigator.of(navigationContext).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('媒体详情'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('媒体详情'), findsNothing);
    expect(find.text('媒体库'), findsOneWidget);
  });

  testWidgets('unavailable episode uses a grey circular exclamation badge',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 240,
            child: ImmersiveEpisodeCard(
              episodeLabel: '第 2 话',
              title: '尚未入库',
              isUnavailable: true,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ImmersiveEpisodeUnavailableBadge), findsOneWidget);
    expect(find.text('!'), findsOneWidget);
  });

  testWidgets('small landscape keeps actions fixed while details scroll',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ImmersiveAnimeDetailScaffold(
          title: '尺寸较小的 Pad 媒体详情页',
          subtitle: 'A deliberately long subtitle for layout verification',
          metadata: const <String>['TV动画', '2026', '共 24 集', '测试工作室'],
          rating: 8.8,
          description: List<String>.filled(
            20,
            '这是一段足够长的简介，用来确认只有标题与简介区域滚动。',
          ).join(),
          descriptionExpanded: true,
          onToggleDescription: () {},
          onBack: () {},
          actions: const SizedBox(
            height: 52,
            child: Text('固定观看按钮'),
          ),
          episodeRail: const ColoredBox(color: Colors.transparent),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final actions = find.byKey(const ValueKey('immersive-fixed-actions'));
    final scroll = find.byKey(
      const ValueKey('immersive-description-scroll'),
    );
    final before = tester.getTopLeft(actions);
    expect(tester.getBottomRight(actions).dy, lessThanOrEqualTo(600));

    await tester.drag(scroll, const Offset(0, -140));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(actions).dy, closeTo(before.dy, 0.1));
    expect(find.text('固定观看按钮'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded summary hugs its toggle and gently moves actions down',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 文本需长于自适应行数上限（非紧凑档 5 行），确保出现“查看更多”。
    const realBocchiSummary =
        '作为网络吉他手“吉他英雄”而广受好评的后藤一里，在现实中却是个什么都不会的沟通障碍者。一里有着组建乐队的梦想，但因为不敢向人主动搭话而一直没有成功，直到一天在公园中被伊地知虹夏发现并邀请进入缺少吉他手的“结束乐队”。可是，完全没有和他人合作经历的一里，在人前完全发挥不出原本的实力。为了努力克服沟通障碍，一里与“结束乐队”的成员们一同开始努力……'
        '之后众人为了参加音乐节而开始自主练习，一里一边打工攒钱购买新设备，一边在文化祭的舞台上克服了当众演奏的恐惧。乐队逐渐积累了名气，也迎来了与虹夏姐姐凉之间的纠葛，以及面对毕业、就业等现实选择的考验。最终“结束乐队”站上了更大的舞台，一里也在同伴的陪伴下一点点走出自己的壳。';
    var expanded = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: StatefulBuilder(
          builder: (context, setState) => ImmersiveAnimeDetailScaffold(
            title: '孤独摇滚！',
            subtitle: 'ぼっち・ざ・ろっく! / Bocchi the Rock!',
            metadata: const <String>['TV动画', '2022', '共 12 集'],
            rating: 8.4,
            description: realBocchiSummary,
            descriptionExpanded: expanded,
            onToggleDescription: () => setState(() => expanded = !expanded),
            onBack: () {},
            actions: const SizedBox(
              height: 52,
              child: Text('观看按钮行'),
            ),
            episodeRail: const ColoredBox(color: Colors.transparent),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final actions = find.byKey(const ValueKey('immersive-fixed-actions'));
    final collapsedActionTop = tester.getTopLeft(actions).dy;
    await tester.tap(find.text('查看更多'));
    await tester.pumpAndSettle();

    final description = find.text(realBocchiSummary);
    final collapseLabel = find.text('收起');
    final gap = tester.getTopLeft(collapseLabel).dy -
        tester.getBottomLeft(description).dy;
    final expandedActionTop = tester.getTopLeft(actions).dy;

    expect(gap, lessThan(14));
    // 新布局：展开后简介占满剩余空间、超出部分由简介区内部滚动承载，
    // 按钮行位置保持稳定——不允许反跳到收起位置上方，也不越过剧集栏
    // （railHeight 235，剧集栏顶部即 800 - 235 = 565）。
    expect(expandedActionTop, greaterThanOrEqualTo(collapsedActionTop));
    expect(tester.getBottomRight(actions).dy, lessThan(800 - 235.0));
    expect(tester.takeException(), isNull);
  });

  for (final size in <Size>[
    const Size(1280, 800),
    const Size(800, 1100),
    const Size(390, 844),
  ]) {
    testWidgets('immersive scaffold renders at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ImmersiveAnimeDetailScaffold(
            title: '魔法少女小圆',
            subtitle: '魔法少女まどか☆マギカ',
            metadata: const <String>['TV动画', '2011', '共 12 集'],
            rating: 8.6,
            description: '这是一段用于验证响应式排版的真实简介占位文本。',
            onBack: () {},
            actions: AdaptiveMediaDetailActionButton(
              icon: Icons.play_arrow,
              label: '开始观看',
              emphasis: MediaDetailActionEmphasis.primary,
              onPressed: () {},
            ),
            episodeRail: const ColoredBox(
              color: Colors.transparent,
              child: Center(child: Text('剧集轨道')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('魔法少女小圆'), findsOneWidget);
      expect(find.text('开始观看'), findsOneWidget);
      expect(find.text('剧集轨道'), findsOneWidget);
      if (size.height > size.width) {
        final poster = tester.widget<Positioned>(
          find.byKey(const ValueKey('immersive-portrait-poster')),
        );
        expect(poster.height, size.height / 2);
        expect(
          find.byKey(const ValueKey('immersive-portrait-color-fill')),
          findsOneWidget,
        );
        final seam = tester.widget<Positioned>(
          find.byKey(const ValueKey('immersive-portrait-seam')),
        );
        expect(seam.top! + seam.height!, size.height / 2);
      }
      if (size.width < 600) {
        expect(
          find.byKey(const ValueKey('immersive-phone-scroll')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone keeps the scrollable detail layout after rotation',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: AppDisplaySurfaceScope(
        surface: AppDisplaySurface.phone,
        child: ImmersiveAnimeDetailScaffold(
          title: '魔法少女小圆',
          onBack: () {},
          actions: const Text('观看'),
          episodeRail: const Center(child: Text('剧集轨道')),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('immersive-phone-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait tablet keeps actions visible below the half-page hero',
      (tester) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: ImmersiveAnimeDetailScaffold(
        title: '魔法少女小圆',
        subtitle: 'Puella Magi Madoka Magica',
        metadata: const ['TV动画', '2011', '共 12 集'],
        description: List.filled(30, '简介内容。').join(),
        onToggleDescription: () {},
        onBack: () {},
        actions: const Text('观看'),
        episodeRail: const Center(child: Text('剧集轨道')),
      ),
    ));
    await tester.pumpAndSettle();

    final poster = tester.widget<Positioned>(
      find.byKey(const ValueKey('immersive-portrait-poster')),
    );
    expect(poster.height, 512);
    final actions = find.byKey(const ValueKey('immersive-fixed-actions'));
    expect(tester.getBottomLeft(actions).dy, lessThan(1024));
    expect(find.byKey(const ValueKey('immersive-phone-scroll')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
