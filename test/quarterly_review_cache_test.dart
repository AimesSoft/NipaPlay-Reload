import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/services/quarterly_review_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('review windows include the first seven days of the next month', () {
    expect(QuarterlyReviewCache.visibleReviewSeason(DateTime(2026, 3, 1)),
        DateTime(2026, 1));
    expect(QuarterlyReviewCache.visibleReviewSeason(DateTime(2026, 4, 7)),
        DateTime(2026, 1));
    expect(
        QuarterlyReviewCache.visibleReviewSeason(DateTime(2026, 4, 8)), isNull);
    expect(QuarterlyReviewCache.visibleReviewSeason(DateTime(2026, 7, 7)),
        DateTime(2026, 4));
    expect(QuarterlyReviewCache.visibleReviewSeason(DateTime(2026, 10, 7)),
        DateTime(2026, 7));
    expect(QuarterlyReviewCache.visibleReviewSeason(DateTime(2027, 1, 7)),
        DateTime(2026, 10));
    expect(
        QuarterlyReviewCache.visibleReviewSeason(DateTime(2027, 1, 8)), isNull);
    expect(
        QuarterlyReviewCache.daysUntilReviewCloses(
            DateTime(2026, 1), DateTime(2026, 3, 31)),
        8);
    expect(
        QuarterlyReviewCache.daysUntilReviewCloses(
            DateTime(2026, 1), DateTime(2026, 4, 7)),
        1);
    expect(
        QuarterlyReviewCache.daysUntilReviewCloses(
            DateTime(2026, 10), DateTime(2027, 1, 7)),
        1);
  });

  test('broadcast start also qualifies after an early preview', () {
    final preview = DateTime(2026, 6, 24);
    final broadcast = DateTime(2026, 7, 5);
    final anime = BangumiAnime(
      id: 812348,
      name: 'Early preview',
      nameCn: '提前预播',
      imageUrl: '',
      airDate: '2026-06-24',
      metadata: const ['放送开始：2026年7月5日'],
    );
    expect(QuarterlyReviewCache.broadcastStartDate(anime), broadcast);
    expect(
        QuarterlyReviewCache.matchingReviewDate(
            preview, broadcast, DateTime(2026, 7)),
        broadcast);
    expect(
        QuarterlyReviewCache.matchingReviewDate(
            preview, broadcast, DateTime(2026, 4)),
        preview);
    expect(
        QuarterlyReviewCache.broadcastStartDate(
            anime.copyWith(metadata: const ['制作公司: 测试', '放送开始：无效日期'])),
        isNull);
  });

  test('persists a season, expires it, and limits background probes', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = QuarterlyReviewCache.forTesting();
    addTearDown(cache.dispose);
    final now = DateTime.now();
    final reviewSeason = QuarterlyReviewCache.visibleReviewSeason(now) ??
        DateTime(now.year, QuarterlyReviewCache.seasonMonth(now));
    final season = reviewSeason.month;
    final anime = BangumiAnime(
      id: 812345,
      name: 'Review test',
      nameCn: '回顾测试',
      imageUrl: 'https://example.com/poster.jpg',
      airDate: '${reviewSeason.year}-$season-01',
      bangumiUrl: 'https://bgm.tv/subject/987654',
    );

    await cache.recordAnime(anime);
    await cache.recordCollection(987654, 'review-test-user', {
      'rate': 9,
      'comment': '看完了',
      'updated_at': '2026-09-01T12:00:00Z',
    });
    final current = await cache.itemsFor({anime.id}, now, 'review-test-user');
    expect(current, hasLength(1));
    expect(current.single.rating, 9);
    expect(current.single.comment, '看完了');
    expect(current.single.commentAt, isNotNull);
    await cache.recordCollection(987654, 'review-test-user', {
      'rating': {'score': 8},
      'comment': '重看',
      'updated_at': 1790000000,
    });
    expect(
        (await cache.itemsFor({anime.id}, now, 'review-test-user'))
            .single
            .commentAt,
        1790000000000);
    expect(
        (await cache.itemsFor({anime.id}, now, null)).single.comment, isNull);

    final secondAnime = BangumiAnime(
      id: 812346,
      name: 'Second review test',
      nameCn: '第二部',
      imageUrl: '',
      airDate: '${reviewSeason.year}-$season-02',
      bangumiUrl: 'https://bgm.tv/subject/987655',
    );
    await cache.recordAnime(secondAnime);
    expect(
        await cache
            .reserveCollectionProbe({secondAnime.id}, 'review-test-user', now),
        987655);
    expect(
        await cache
            .reserveCollectionProbe({secondAnime.id}, 'review-test-user', now),
        isNull);

    final previewDate = DateTime(reviewSeason.year, reviewSeason.month - 1, 20);
    final broadcastDate = DateTime(reviewSeason.year, reviewSeason.month, 3);
    final existingDetail = BangumiAnime(
      id: 812347,
      name: 'Existing detail',
      nameCn: '已有详情缓存',
      imageUrl: '',
      airDate: previewDate.toIso8601String().split('T').first,
      metadata: ['放送开始: ${broadcastDate.toIso8601String().split('T').first}'],
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'bangumi_detail_${existingDetail.id}',
        json.encode({
          'timestamp': now.millisecondsSinceEpoch,
          'animeDetail': existingDetail.toJson(),
        }));
    await cache.adoptExistingDetails({existingDetail.id});
    final imported = await cache.itemsFor({existingDetail.id}, now, null);
    expect(imported, hasLength(1));
    expect(imported.single.airDate, broadcastDate);
    expect(imported.single.dateLabel, '放送开始');

    final probeDay = DateTime(2030, 1, 1, 8);
    expect(await cache.reserveMetadataProbe({10, 20, 30}, probeDay), 30);
    expect(
        await cache.reserveMetadataProbe(
            {10, 20, 30}, probeDay.add(const Duration(hours: 1))),
        isNull);
    expect(
        await cache.reserveMetadataProbe(
            {10, 20, 30}, probeDay.add(const Duration(hours: 5))),
        20);
    expect(
        await cache.reserveMetadataProbe(
            {10, 20, 30}, probeDay.add(const Duration(hours: 10))),
        isNull);
    expect(
        await cache.reserveMetadataProbe(
            {secondAnime.id}, probeDay.add(const Duration(days: 1))),
        secondAnime.id);

    final graceEnd = DateTime(reviewSeason.year, season + 3, 7, 23, 59);
    expect(await cache.itemsFor({anime.id}, graceEnd, 'review-test-user'),
        hasLength(1));
    final afterGrace = DateTime(reviewSeason.year, season + 3, 8);
    expect(await cache.itemsFor({anime.id}, afterGrace, 'review-test-user'),
        isEmpty);
    final stored = json.decode(prefs.getString('quarterly_review_cache_v1')!)
        as Map<String, dynamic>;
    expect((stored['anime'] as Map).containsKey('${anime.id}'), isFalse);
    expect(
        (stored['collections'] as Map).containsKey('review-test-user:987654'),
        isFalse);

    final nextSeason = DateTime(reviewSeason.year, season + 3);
    final preview = BangumiAnime(
      id: 812349,
      name: 'Preview retained for broadcast',
      nameCn: '跨季度预播',
      imageUrl: '',
      airDate: DateTime(reviewSeason.year, season, 15)
          .toIso8601String()
          .split('T')
          .first,
      metadata: ['放送开始: ${nextSeason.toIso8601String().split('T').first}'],
    );
    await cache.recordAnime(preview);
    final nextReview = await cache.itemsFor({preview.id}, afterGrace, null);
    expect(nextReview, hasLength(1));
    expect(nextReview.single.airDate, nextSeason);
    expect(nextReview.single.dateLabel, '放送开始');
  });

  test('edited comments persist, refresh their time and stay account-scoped',
      () async {
    SharedPreferences.setMockInitialValues({});
    final cache = QuarterlyReviewCache.forTesting();
    addTearDown(cache.dispose);
    final now = DateTime.now();
    final season = QuarterlyReviewCache.visibleReviewSeason(now) ??
        DateTime(now.year, QuarterlyReviewCache.seasonMonth(now));
    final anime = BangumiAnime(
      id: 812345,
      name: 'Comment editing',
      nameCn: '编辑短评',
      imageUrl: '',
      airDate: '${season.year}-${season.month}-01',
      bangumiUrl: 'https://bgm.tv/subject/987654',
    );
    await cache.recordAnime(anime);
    for (final username in ['review-user', 'other-user']) {
      await cache.recordCollection(987654, username,
          {'rate': 8, 'comment': '原来的短评', 'updated_at': 1700000000});
    }
    final previousRevision = cache.revision.value;
    await cache.recordCollectionPatch(987654, 'review-user',
        rating: 9, comment: '  新短评\n完整内容  ');
    expect(cache.revision.value, greaterThan(previousRevision));
    final reloaded = QuarterlyReviewCache.forTesting();
    addTearDown(reloaded.dispose);
    final edited =
        (await reloaded.itemsFor({anime.id}, now, 'review-user')).single;
    expect(edited.rating, 9);
    expect(edited.comment, '新短评\n完整内容');
    expect(edited.commentAt, greaterThanOrEqualTo(now.millisecondsSinceEpoch));
    expect(
        (await reloaded.itemsFor({anime.id}, now, 'other-user')).single.comment,
        '原来的短评');

    await reloaded.recordCollectionPatch(987654, 'review-user', comment: '');
    final cleared =
        (await reloaded.itemsFor({anime.id}, now, 'review-user')).single;
    expect(cleared.comment, isNull);
    expect(cleared.rating, 9);
  });

  test('initial collections are paced, deduplicated and resume after restart',
      () async {
    SharedPreferences.setMockInitialValues({});
    var cache = QuarterlyReviewCache.forTesting();
    addTearDown(() => cache.dispose());
    final season = QuarterlyReviewCache.visibleReviewSeason(DateTime.now()) ??
        DateTime(DateTime.now().year,
            QuarterlyReviewCache.seasonMonth(DateTime.now()));
    final probeAt = DateTime(season.year, season.month + 2, 28, 12);
    final ids = <int>{};
    for (var i = 0; i < 25; i++) {
      final id = 820000 + i;
      ids.add(id);
      await cache.recordAnime(BangumiAnime(
        id: id,
        name: 'Anime $i',
        nameCn: '',
        imageUrl: '',
        airDate: DateTime(season.year, season.month, 1)
            .toIso8601String()
            .split('T')
            .first,
        bangumiUrl: 'https://bgm.tv/subject/${100000 + i}',
      ));
    }
    // A second media ID referring to the same subject must not request twice.
    ids.add(830000);
    await cache.recordAnime(BangumiAnime(
      id: 830000,
      name: 'Duplicate subject',
      nameCn: '',
      imageUrl: '',
      airDate: DateTime(season.year, season.month, 1)
          .toIso8601String()
          .split('T')
          .first,
      bangumiUrl: 'https://bgm.tv/subject/100000',
    ));

    for (var i = 0; i < QuarterlyReviewCache.initialCollectionDailyLimit; i++) {
      final now = probeAt.add(Duration(seconds: i * 2));
      expect(
          await cache.reserveCollectionProbe(ids, 'first-user', now,
              initialOnly: true),
          100000 + i);
      expect(
          await cache.reserveCollectionProbe(ids, 'first-user', now,
              initialOnly: true),
          isNull);
      // Remember even an empty/404 result; leave one failed attempt unfinished.
      if (i != 1) await cache.recordCollection(100000 + i, 'first-user', null);
      if (i == 2) {
        cache.dispose();
        cache = QuarterlyReviewCache.forTesting();
        await cache.load();
      }
    }
    expect(
        await cache.reserveCollectionProbe(
            ids, 'first-user', probeAt.add(const Duration(minutes: 1)),
            initialOnly: true),
        isNull);
    expect(
        await cache.reserveCollectionProbe(
            ids, 'first-user', probeAt.add(const Duration(minutes: 1))),
        isNull);
    expect(
        await cache.reserveCollectionProbe(
            ids, 'first-user', probeAt.add(const Duration(days: 1, minutes: 1)),
            initialOnly: true),
        100001);
    expect(
        await cache.reserveCollectionProbe(ids, 'second-user',
            probeAt.add(const Duration(days: 1, minutes: 2)),
            initialOnly: true),
        100000);
  });

  test('collection errors back off across app restarts', () async {
    SharedPreferences.setMockInitialValues({});
    var cache = QuarterlyReviewCache.forTesting();
    addTearDown(() => cache.dispose());
    final now = DateTime.now();
    final season = QuarterlyReviewCache.visibleReviewSeason(now) ??
        DateTime(now.year, QuarterlyReviewCache.seasonMonth(now));
    final probeAt = DateTime(season.year, season.month + 2, 28, 12);
    await cache.recordAnime(BangumiAnime(
      id: 840000,
      name: 'Backoff',
      nameCn: '',
      imageUrl: '',
      airDate: season.toIso8601String().split('T').first,
      bangumiUrl: 'https://bgm.tv/subject/200000',
    ));
    await cache.deferCollectionProbes(probeAt);
    expect(
        await cache.reserveCollectionProbe(
            {840000}, 'user', probeAt.add(const Duration(minutes: 30)),
            initialOnly: true),
        isNull);
    await cache.deferCollectionProbes(probeAt, statusCode: 429);
    cache.dispose();
    cache = QuarterlyReviewCache.forTesting();
    await cache.load();
    expect(
        await cache.reserveCollectionProbe(
            {840000}, 'user', probeAt.add(const Duration(hours: 23)),
            initialOnly: true),
        isNull);
    expect(
        await cache.reserveCollectionProbe(
            {840000}, 'user', probeAt.add(const Duration(days: 1, minutes: 1)),
            initialOnly: true),
        200000);
  });
}
