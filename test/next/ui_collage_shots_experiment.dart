// Run explicitly: pictures of a poster that is a contact sheet (弹弹play's
// poster for 躲在超市后门抽烟的两人: stills on white, a white gap left over),
// laid out again from its stills, and of the detail page around it; for
// looking at, not a regression suite. Uses the e2e13 lab profile's pictures.
//
//   flutter test --no-pub test/next/ui_collage_shots_experiment.dart
//
// Writes PNGs to /tmp/nipa-next/collage-shots, and the same at 1000 px on
// the long side to /tmp/nipa-next/collage-shots/small.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nipaplay/next/ui/library/fan_cover.dart';
import 'package:nipaplay/next/ui/theme/tokens.dart';
import 'package:nipaplay/next/ui/widgets/artwork.dart';
import 'package:nipaplay/next/ui/widgets/cards.dart';
import 'package:nipaplay/next/ui/widgets/poster_art.dart';
import 'package:nipaplay/next/ui/widgets/still_mosaic.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

import 'found_cards_support.dart';

const _art =
    '~/Library/Application Support/NipaPlay/LabProfiles/e2e13/data/next/artwork';
const _sheet =
    '$_art/35ef417581925c7e27589fe2cf15b1ead915a24caf2b7675ffabdbf579c48fba.jpg';
const _otherPoster =
    '~/Library/Application Support/NipaPlay/LabProfiles/e2e11/data/next/artwork/f7d96260698b8445c14287f4a54d14a0d28ead17abd39728923171e6a5a2374f.jpg';
const _out = '/tmp/nipa-next/collage-shots';

/// Episode titles and stills as the e2e13 library has them; the first lost
/// its file.
const _episodes = [
  ('第1话 在超市后门吸烟的二人', null),
  ('第2话 在超市后门相伴的二人', '5abf601b262892997ee13e8ae9a34c27424f1dd114703d270dc344a8658535b5.png'),
  ('第3话 在超市后门赠予的二人', '61c0b7357e3dbfcdc2231e8aa0fef53c84c61c15835654814de5efde3be2c139.png'),
  ('第4话 在超市后门学习的一人', '0b2a1b8f5d3764d95aae7a3dad89ef07f601d892b93940c23e19fe259c5e63ec.png'),
  ('第5话 在超市后门画画的二人', '9528ea95bdd359dab93c0b8791c61907589e9cb585bed50ca897e6dcd09aef6a.png'),
  ('第6话 在超市后门残留的气味', 'ee4aaea0b4bb992a55a4f22dad2249416b60bc0a1e8f3f219a482e4c5de6a058.png'),
  ('第7话 在超市后门与夏日的尽头', '81f3bd86302b762b9ba05771fb4f067854a60b1ad5f28d4ce4cb07aa88f958c7.png'),
  ('第8话 在超市后门寻找的二人', '7753991092f3218d4bc15d5c455aa6d79c45afe2470849a5ad8ad5963d6d42ef.png'),
  ('第9话 在超市后门相触的二人', '17b21b485251c720994ce91ddcc5211b7014863ab0f142be8ba41efaa402ed88.png'),
];

const _overview = '在社畜之路上一路狂奔、疲惫不堪的中年男子佐佐木。'
    '他平日里那点隐秘的慰藉，无非是自己常抽的香烟，以及常去的超市里，那位女店员山田小姐亲切而灿烂的笑容。';

const _fontFiles = {
  'PingFang SC': [
    '/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc',
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
  ],
  'CupertinoSystemText': ['/System/Library/Fonts/SFNS.ttf'],
  'CupertinoSystemDisplay': ['/System/Library/Fonts/SFNS.ttf'],
  'Songti SC': ['/System/Library/Fonts/Supplemental/Songti.ttc'],
};

Future<void> _loadFonts() async {
  for (final MapEntry(key: family, value: files) in _fontFiles.entries) {
    final file = files.map(File.new).where((f) => f.existsSync()).firstOrNull;
    if (file == null) continue;
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    await loader.load();
  }
}

final class _Library implements NextUiData {
  _Library(this.only, this.list);
  final UiWork only;
  final List<UiEpisode> list;
  @override
  Future<UiWork?> work(String workId) async =>
      workId == only.workId ? only : null;
  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async =>
      workId == only.workId ? list : const [];
  @override
  Future<UiHome> home() async => const UiHome();
  @override
  Stream<List<UiTask>> tasks() => Stream.value(const []);
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<List<UiWork>> library() async => [only];
  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      const [];
}

void main() {
  final shoot = File(_sheet).existsSync();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nipaplay/next_chrome'),
            (call) async => {'leading': 78.0, 'fullScreen': false});
  });

  /// Pictures asked for under the test's fake clock never arrive: each is
  /// dropped, read again outside it, and looked up anew by the widgets.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final images = [
      for (final e in find.byType(Image).evaluate())
        ((e.widget as Image).image, e)
    ];
    await tester.runAsync(() async {
      for (final (provider, element) in images) {
        final key =
            await provider.obtainKey(createLocalImageConfiguration(element));
        imageCache.evict(key);
        await precacheImage(provider, element)
            .timeout(const Duration(seconds: 5), onTimeout: () {});
      }
    });
    foundTickers.value = false;
    await tester.pump();
    foundTickers.value = true;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester);
    await tester.runAsync(() async {
      final boundary = foundShotKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      await Directory('$_out/small').create(recursive: true);
      await File('$_out/$name.png').writeAsBytes(png);
      final full = img.decodePng(png)!;
      final small = full.width >= full.height
          ? img.copyResize(full, width: 1000)
          : img.copyResize(full, height: 1000);
      await File('$_out/small/$name.png').writeAsBytes(img.encodePng(small));
    });
  }

  testWidgets('a contact sheet poster, laid out again', (tester) async {
    await tester.runAsync(_loadFonts);
    final sheet = (await tester.runAsync(() => PosterSheets.read(_sheet)))!;
    await tester.runAsync(() => PosterSheets.read(_otherPoster));
    expect(sheet.pieces, hasLength(6));
    final stills = [
      for (final (_, still) in _episodes)
        if (still != null) MosaicPiece('$_art/$still')
    ];

    // Cards: the provider's picture as it was, the card now, then stills
    // of the episodes in any number, and the small places a poster goes.
    tester.view.physicalSize = const Size(1280, 860) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    Widget label(String text) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text, style: NextText.sans(12.5, color: NextColors.p3)));
    Widget poster(Widget child, {double width = 150}) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: width, height: width * 1.5, child: child),
        );
    await tester.pumpWidget(RepaintBoundary(
      key: foundShotKey,
      child: ValueListenableBuilder<bool>(
        valueListenable: foundTickers,
        builder: (context, on, child) =>
            TickerMode(enabled: on, child: child!),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: NextColors.ink,
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Column(children: [
                      poster(const NextImage(_sheet, shape: ArtShape.poster),
                          width: 176),
                      label('弹弹play 给的图'),
                    ]),
                    const SizedBox(width: 28),
                    const PosterCard(
                        image: _sheet,
                        tint: 0xfffdfdfd,
                        title: '躲在超市后门抽烟的两人',
                        reason: '片库卡片'),
                    const SizedBox(width: 28),
                    SizedBox(
                      width: 296,
                      child: Column(children: [
                        const WideCard(
                            image: null,
                            poster: _sheet,
                            tint: 0xfffdfdfd,
                            title: '躲在超市后门抽烟的两人',
                            caption: '第 2 集'),
                        label('没有横图的宽卡片'),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: 296,
                          height: 170,
                          child: CategoryCard(
                              title: '本季',
                              count: 3,
                              posters: const [_sheet, _otherPoster],
                              onOpen: () {}),
                        ),
                        label('分类封面'),
                      ]),
                    ),
                    const SizedBox(width: 28),
                    Column(children: [
                      Row(children: [
                        for (final w in [22.0, 36.0, 54.0]) ...[
                          poster(const PosterArt(_sheet, read: false), width: w),
                          const SizedBox(width: 12),
                        ],
                      ]),
                      label('缩略图'),
                    ]),
                  ]),
                  const SizedBox(height: 36),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final n in [0, 1, 2, 3, 5, 7]) ...[
                      Column(children: [
                        poster(StillMosaic(
                            pieces: stills.take(n).toList(),
                            lead: n > 2 ? 0 : null,
                            tint: 0xfffdfdfd)),
                        label('$n 张截图'),
                      ]),
                      const SizedBox(width: 24),
                    ],
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await shot(tester, '1-cards');

    // The work's page, from a card: the poster standing on the right, the
    // backdrop out of focus, the episodes with what is known of them.
    const work = UiWork(
      workId: 'w-smoking',
      title: '躲在超市后门抽烟的两人',
      episodeCount: 12,
      overview: _overview,
      artwork: UiArtwork(poster: _sheet, tint: 0xfffdfdfd),
      next: UiEpisode(
          episodeId: 'e2',
          workId: 'w-smoking',
          number: 2,
          progress: 0.45,
          playable: true),
    );
    final episodes = [
      for (final (i, (title, still)) in _episodes.indexed)
        UiEpisode(
          episodeId: 'e${i + 1}',
          workId: 'w-smoking',
          number: i + 1,
          title: title,
          still: still == null ? null : '$_art/$still',
          runtime: switch (i) {
            0 => null,
            1 || 2 => const Duration(minutes: 23, seconds: 50),
            _ => Duration.zero,
          },
          progress: i == 1 ? 0.45 : null,
          playable: i > 0,
        ),
    ];
    var shell = await pumpFoundCards(tester,
        cards: const [UiWorkCard(work)],
        discover: FoundDetails(),
        data: _Library(work, episodes),
        pixelRatio: 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text(work.title));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '2-detail');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    shell.dispose();

    // A found work whose title takes two lines.
    const found = UiWork(
      workId: 'found:dandanplay:18563',
      title: '佐佐木与文鸟小哔 第二季',
      year: 2026,
      artwork: UiArtwork(poster: _otherPoster, tint: 0xff3a3a40),
    );
    shell = await pumpFoundCards(tester,
        cards: const [UiWorkCard(found)],
        discover: FoundDetails({
          found.workId: {
            'overview': '佐佐木在宠物店买到的，是从异世界转生而来，大名鼎鼎的贤者大人。'
                '「吾名毕耶尔卡洛，乃异界之徒兼星之贤者。」但还是文鸟。佐佐木替这只文鸟取名为小哔。',
          }
        }),
        pixelRatio: 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text(found.title));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '3-found-long-title');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    shell.dispose();
  }, skip: !shoot);
}
