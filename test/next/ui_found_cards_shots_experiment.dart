// Run explicitly: pictures of cards for works outside the library, for
// looking at, not a regression suite. The found works go through the real
// UiDataService (ui.present → cards()) with a fake provider whose posters
// are the TMDB sample set's; nothing reaches the network.
//
//   flutter test --no-pub test/next/ui_found_cards_shots_experiment.dart
//
// Writes PNGs to /tmp/nipa-next/found-cards.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/media/metadata_provider.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui/theme/tokens.dart';
import 'package:nipaplay/next/ui/widgets/cards.dart';
import 'package:nipaplay/next/ui_data/capability.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import '../security/memory_vault.dart';
import 'found_cards_support.dart';
import 'media_test_support.dart';

const _samples = '/tmp/nipa-next/visual/tmdb';
const _out = '/tmp/nipa-next/found-cards';

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

final class _Provider implements MetadataProvider {
  _Provider(this.id, this.records);
  @override
  final String id;
  final Map<String, MetadataRecord> records;
  @override
  Future<List<MetadataRecord>> search(String query,
          {String kind = 'tv', int? year}) async =>
      [];
  @override
  Future<MetadataRecord> get(ExternalRef ref,
          {String language = 'zh-CN'}) async =>
      records['${ref.objectType}/${ref.externalId}']!;
}

MetadataRecord _record(
        String provider, String type, String id, String title, String poster,
        {int? year, int? episodes, double? rating}) =>
    MetadataRecord(
        ref: ExternalRef(provider, type, id),
        title: title,
        kind: type,
        year: year,
        imageUrl: 'https://image.example/$poster',
        rating: rating == null ? null : {'value': rating, 'max': 10},
        episodeCount: episodes,
        fetchedAt: DateTime.utc(2026, 10, 20));

/// The cards the service gives back for three works outside the library.
Future<List<UiCard>> _presented(Directory root) async {
  sqfliteFfiInit();
  final store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
  final engine = TaskEngine(
      store: store, ownerDeviceId: 'shots', executors: [FakeExecutor()]);
  await engine.start();
  final media = MediaService(
      store: IdentityStore(store.database, 'shots'),
      providers: [
        _Provider('bangumi', {
          'subject/464376': _record('bangumi', 'subject', '464376', '败犬女主太多了！',
              'discover/makeine-poster.jpg',
              year: 2024, episodes: 12, rating: 8.1),
          'subject/378862': _record('bangumi', 'subject', '378862', '我心里危险的东西',
              'discover/bokuyaba-poster.jpg',
              year: 2023, episodes: 12, rating: 8.6),
        }),
        _Provider('tmdb', {
          'tv/90937': _record(
              'tmdb', 'tv', '90937', '长安十二时辰', 'changan-poster.jpg',
              year: 2019, episodes: 48, rating: 8.3),
        }),
      ],
      classic: MemoryClassic(),
      authorizedRoots: () => [root.path]);
  final service = http.runWithClient(
      () => UiDataService(
          media,
          engine,
          StateCapability([
            StateView(
                name: 'library.files',
                description: 'shots',
                fields: const ObjectSchema({}),
                read: (offset, limit) async => [])
          ]),
          StateSources(),
          root,
          MemoryVault()),
      () => MockClient((request) async => http.Response.bytes(
          File('$_samples${request.url.path}').readAsBytesSync(), 200)));
  await File('${root.path}/journal.jsonl').writeAsString('${jsonEncode({
        'event': 'chat.turn_boundary',
        'origin': 'harness_cli:chat:shots',
        'threadId': 'thread',
        'turnId': 'turn',
        'phase': 'started'
      })}\n');
  final outcome = await Harness([UiDataCapability(service)]).invokeJson(
      'ui.present',
      {
        'cards': [
          {
            'kind': 'candidates',
            'items': [
              {
                'ref': {
                  'provider': 'bangumi',
                  'objectType': 'subject',
                  'externalId': '464376'
                },
                'reason': '轻松，一集二十分钟'
              },
              {
                'ref': {
                  'provider': 'bangumi',
                  'objectType': 'subject',
                  'externalId': '378862'
                },
                'reason': '甜，不用动脑'
              },
            ]
          },
          {
            'kind': 'work',
            'ref': {
              'provider': 'tmdb',
              'objectType': 'tv',
              'externalId': '90937',
              'scope': ''
            }
          },
        ]
      },
      Invocation(origin: 'harness_cli:chat:shots'));
  if (outcome is! Completed) throw StateError('$outcome');
  final cards = await service.cards(threadId: 'thread');
  await service.close();
  await engine.close();
  return cards;
}

void main() {
  final shoot = File('$_samples/changan-poster.jpg').existsSync() &&
      File('$_samples/discover/makeine-poster.jpg').existsSync();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nipaplay/next_chrome'),
            (call) async => {'leading': 78.0, 'fullScreen': false});
  });

  /// Pictures asked for under the test's fake clock never arrive: each is
  /// dropped, read again outside it, and looked up anew by the widgets.
  Future<void> settle(WidgetTester tester) async {
    // Frames for what moves (cards rising in, hover), then the pictures.
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

  testWidgets('cards for works outside the library, and the page they open',
      (tester) async {
    final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('found-cards-shots-')))!;
    await tester.runAsync(_loadFonts);
    final presented = (await tester.runAsync(() => _presented(root)))!;
    // A library work beside them, as the library gives it.
    const frieren = UiWork(
      workId: 'w-frieren',
      title: '葬送的芙莉莲',
      year: 2023,
      episodeCount: 28,
      ratings: [UiRating('TMDB', 8.8)],
      artwork: UiArtwork(poster: '$_samples/frieren-poster.jpg'),
      next: UiEpisode(
          episodeId: 'e', workId: 'w-frieren', number: 1, playable: true),
    );
    final picks = presented.first as UiCandidatesCard;
    final cards = [
      UiCandidatesCard([
        ...picks.items,
        const UiCandidate(frieren, reason: '第一集准备好了'),
      ]),
      presented.last,
      const UiWorkCard(frieren),
    ];
    final shell = await pumpFoundCards(tester,
        cards: cards,
        discover: FoundDetails({
          (presented.last as UiWorkCard).work.workId: {
            'overview': '唐天宝三年，上元节前夕，长安城陷入危局。死囚张小敬临危受命，与李必携手在十二个时辰内拯救长安。',
            'originalTitle': '长安十二时辰',
          }
        }),
        pixelRatio: 2,
        onPlay: (_) {},
        above: Text('这三部都很轻松，一集二十分钟出头。前两部还没有，想看哪部我去准备。',
            style: NextText.sans(15.5, color: NextColors.paper, height: 1.7)));
    await shot(tester, '1-cards');

    // Hovering a found poster: no play button, only the page.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
        location: tester.getCenter(find.byType(PosterCard).first));
    await shot(tester, '2-hover-found');
    await mouse.moveTo(tester.getCenter(find.byType(PosterCard).at(2)));
    await shot(tester, '3-hover-library');
    await mouse.removePointer();

    await tester.tap(find.text('长安十二时辰'));
    await tester.pump();
    await shot(tester, '4-found-page');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    shell.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  }, skip: !shoot);
}
