// Run explicitly: pictures of a work's page, for looking at, not a
// regression suite. A film (started and not) and a series, from the library,
// with the people, pictures and facts its sources give; the pictures are the
// TMDB sample set's, nothing reaches the network.
//
//   flutter test --no-pub test/next/ui_detail_shots_experiment.dart
//
// Writes PNGs to /tmp/nipa-next/detail-shots.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:nipaplay/next/ui_data/work_more.dart';

import 'found_cards_support.dart';

const _samples = '/tmp/nipa-next/visual/tmdb';
const _out = '/tmp/nipa-next/detail-shots';

const _fontFiles = {
  'PingFang SC': [
    '/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc',
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
  ],
  'CupertinoSystemText': ['/System/Library/Fonts/SFNS.ttf'],
  'CupertinoSystemDisplay': ['/System/Library/Fonts/SFNS.ttf'],
  'Songti SC': ['/System/Library/Fonts/Supplemental/Songti.ttc'],
  'Menlo': ['/System/Library/Fonts/Menlo.ttc'],
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

String _s(String name) => '$_samples/$name';

UiCredit _person(String name, String role, String picture) =>
    UiCredit(name: name, role: role, image: _s(picture));

/// What the sources of a film say about it, as the page reads it.
final _suzumeMore = UiWorkMore(
  sections: const ['characters', 'cast', 'crew', 'gallery', 'facts', 'links'],
  characters: [
    for (final (name, role, voice, picture) in const [
      ('岩户铃芽', '主角', '原菜乃华', 'suzume-poster.jpg'),
      ('宗像草太', '主角', '松村北斗', 'yourname-poster.jpg'),
      ('岩户环', '配角', '深津绘里', 'violet-poster.jpg'),
      ('大臣', '配角', '山根あん', 'spirited-poster.jpg'),
      ('芹泽朋也', '配角', '神木隆之介', 'bigfish-poster.jpg'),
      ('海部千果', '配角', '花濑琴音', 'hibike-poster.jpg'),
      ('二之宫琉美', '配角', '伊藤沙莉', 'kusuriya-poster.jpg'),
    ])
      UiCharacter(
          name: name,
          role: role,
          image: _s(picture),
          actors: [UiCredit(name: voice, image: _s(picture))]),
  ],
  cast: [
    _person('原菜乃华', '岩户铃芽（配音）', 'suzume-backdrop.jpg'),
    _person('松村北斗', '宗像草太（配音）', 'yourname-backdrop.jpg'),
    _person('深津绘里', '岩户环（配音）', 'violet-backdrop.jpg'),
    _person('染谷将太', '冈部稔（配音）', 'spirited-backdrop.jpg'),
    _person('伊藤沙莉', '二之宫琉美（配音）', 'kusuriya-backdrop.jpg'),
  ],
  crew: [
    _person('新海诚', '导演 · 编剧 · 原作', 'yourname-backdrop2.jpg'),
    _person('田村篤', '角色设计', 'suzume-backdrop2.jpg'),
    _person('RADWIMPS', '音乐', 'violet-backdrop2.jpg'),
    _person('陣内一真', '音乐', 'spirited-backdrop2.jpg'),
  ],
  facts: const [
    (label: '原名', value: 'すずめの戸締まり'),
    (label: '上映', value: '2022-11-11'),
    (label: '时长', value: '2 小时 2 分'),
    (label: '制作公司', value: 'CoMix Wave Films'),
    (label: '导演', value: '新海诚'),
    (label: '国家与语言', value: '日本 · 日语'),
    (label: '票房', value: '\$3.2 亿'),
  ],
  tags: const ['奇幻', '冒险', '公路片'],
  links: const [
    (label: 'TMDB', url: 'https://www.themoviedb.org/movie/916224'),
    (label: 'Bangumi', url: 'https://bgm.tv/subject/361379'),
  ],
);

const _overview =
    '生活在日本九州宁静小镇的17岁少女铃芽，遇见了为了寻找“门”而踏上旅途的青年。'
    '追随着青年的脚步，铃芽来到了山上一片废墟之地，在这里静静伫立着一扇古老的门，'
    '仿佛是坍塌中存留下的唯一遗迹。铃芽仿佛被什么吸引了一般，将手伸向了那扇门……';

UiWork _suzume({double? progress}) => UiWork(
      workId: 'w-suzume',
      title: '铃芽之旅',
      originalTitle: 'すずめの戸締まり',
      year: 2022,
      genres: const ['动画', '奇幻', '冒险'],
      film: true,
      runtime: const Duration(minutes: 122),
      studio: 'CoMix Wave Films',
      overview: _overview,
      ratings: const [UiRating('TMDB', 7.7), UiRating('Bangumi', 7.6)],
      artwork: UiArtwork(
          backdrop: _s('suzume-backdrop.jpg'),
          poster: _s('suzume-poster.jpg'),
          logo: _s('suzume-logo.png')),
      next: UiEpisode(
          episodeId: 'e-suzume',
          workId: 'w-suzume',
          number: 1,
          runtime: const Duration(minutes: 122),
          progress: progress,
          position: progress == null
              ? null
              : Duration(seconds: (progress * 122 * 60).round()),
          playable: true),
    );

final class _Library implements NextUiData, NextWorkDetails {
  _Library(this.works, this.more, this.seasons);
  final Map<String, UiWork> works;
  final Map<String, UiWorkMore> more;
  final Map<String, List<UiEpisode>> seasons;
  @override
  Future<UiWork?> work(String workId) async => works[workId];
  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async =>
      seasons[workId] ?? [if (works[workId]?.next case final e?) e];
  @override
  Future<UiWorkMore> workMore(String workId) async =>
      more[workId] ?? UiWorkMore.empty;
  @override
  Future<UiGallery> gallery(UiGalleryRef ref) async => UiGallery(wide: [
        for (final n in ['suzume-backdrop.jpg', 'suzume-backdrop2.jpg'])
          _s(n)
      ], posters: [
        _s('suzume-poster.jpg')
      ]);
  @override
  Future<UiPerson?> person(UiPersonRef ref) async => null;
  @override
  Future<UiHome> home() async => const UiHome();
  @override
  Stream<List<UiTask>> tasks() => Stream.value(const []);
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<List<UiWork>> library() async => works.values.toList();
  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      const [];
}

void main() {
  final shoot = File(_s('suzume-backdrop.jpg')).existsSync();

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
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_out).create(recursive: true);
      await File('$_out/$name.png').writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> page(WidgetTester tester, String name, UiWork work,
      {UiWorkMore? more, bool scrolled = false}) async {
    await tester.runAsync(_loadFonts);
    final shell = await pumpFoundCards(tester,
        cards: [UiWorkCard(work)],
        discover: FoundDetails(),
        data: _Library({work.workId: work}, {if (more != null) work.workId: more},
            const {}),
        pixelRatio: 2,
        onPlay: (_) {});
    await tester.tap(find.text(work.title).first);
    await tester.pump();
    await shot(tester, name);
    if (scrolled) {
      await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -760));
      await shot(tester, '$name-scrolled');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    shell.dispose();
  }

  testWidgets('a film never started', (tester) async {
    await page(tester, '1-film', _suzume(), more: _suzumeMore, scrolled: true);
  }, skip: !shoot);

  testWidgets('a film halfway', (tester) async {
    await page(tester, '2-film-started', _suzume(progress: 0.42),
        more: _suzumeMore);
  }, skip: !shoot);

  testWidgets('a film its sources say nothing more of', (tester) async {
    await page(tester, '3-film-bare', _suzume(progress: 0.42));
  }, skip: !shoot);
}
