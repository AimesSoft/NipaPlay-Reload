import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/models/trending_bangumi.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/services/trending_bangumi_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('desktop ranking actions stay beside the section title', () {
    final source = File(
      'lib/themes/nipaplay/widgets/dashboard_home_page_trending.dart',
    ).readAsStringSync();
    final desktopSection = source.substring(
      source.indexOf('Widget _buildTrendingSection()'),
      source.indexOf('Widget _buildTrendingErrorState()'),
    );

    expect(desktopSection, contains('mainAxisSize: MainAxisSize.min'));
    expect(desktopSection, contains('const SizedBox(width: 48)'));
    expect(desktopSection, isNot(contains('const Spacer()')));
  });

  test('desktop ranking windows use plain NipaPlay dropdown layouts', () {
    final source = File(
      'lib/themes/nipaplay/widgets/dashboard_home_page_trending.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('backdropBlurSigma: 34')));
    expect(source, contains('class _NipaplayTrendingFilterControls'));
    expect(source, contains('BlurDropdown<TrendingRankingKind>'));
    expect(source, contains('class _NipaplayFullTrendingView'));
    expect(source, contains('compact: true'));
    expect(source, contains('crossAxisAlignment: CrossAxisAlignment.end'));
    expect(source, contains('SliverGridDelegateWithMaxCrossAxisExtent'));
  });

  group('TrendingBangumiQuery', () {
    test('builds all supported endpoint paths', () {
      expect(
        const TrendingBangumiQuery(
          kind: TrendingRankingKind.allHot,
          period: TrendingPeriod.month,
        ).apiPath,
        '/api/v2/trending/all/hot/month',
      );
      expect(
        const TrendingBangumiQuery(
          kind: TrendingRankingKind.allRising,
          period: TrendingPeriod.quarter,
        ).apiPath,
        '/api/v2/trending/all/rising/quarter',
      );
      expect(
        const TrendingBangumiQuery(
          kind: TrendingRankingKind.newAnimeHot,
          scope: TrendingNewAnimeScope.previousSeason,
        ).apiPath,
        '/api/v2/trending/new-anime/hot/previous-season',
      );
    });
  });

  group('TrendingBangumiResult', () {
    test('parses ranking metadata and item metrics', () {
      final result = TrendingBangumiResult.fromJson({
        'summary': {
          'title': '全站飙升榜',
          'rankingType': 'rising',
          'period': 'week',
          'dateFrom': '2026-07-20',
          'dateTo': '2026-07-26',
        },
        'bangumiList': [
          {
            'animeId': 123,
            'animeTitle': '测试番剧',
            'imageUrl': 'https://example.com/cover.jpg',
            'airDay': 2,
            'rating': 8.6,
            'isOnAir': true,
            'isFavorited': false,
            'isRestricted': false,
            'rank': 1,
            'heat': '98.7',
            'activeDays': 7,
            'previousHeat': '40.1',
            'heatDelta': '58.6',
            'heatGrowthRate': '146.1%',
          },
        ],
      });

      expect(result.summary.rankingType, 'rising');
      expect(result.summary.dateTo, '2026-07-26');
      expect(result.items, hasLength(1));
      expect(result.items.single.rank, 1);
      expect(result.items.single.anime.id, 123);
      expect(result.items.single.anime.name, '测试番剧');
      expect(result.items.single.heatGrowthRate, '146.1%');
    });

    test('round trips cached ranking data', () {
      final original = TrendingBangumiResult.fromJson({
        'summary': {'rankingType': 'hot', 'period': 'month'},
        'bangumiList': [
          {
            'animeId': 456,
            'animeTitle': '缓存番剧',
            'imageUrl': 'https://example.com/cached.jpg',
            'rank': 2,
            'heat': '88.8',
          },
        ],
      });

      final restored = TrendingBangumiResult.fromJson(original.toJson());

      expect(restored.items.single.anime.id, 456);
      expect(restored.items.single.anime.nameCn, '缓存番剧');
      expect(restored.items.single.rank, 2);
      expect(restored.items.single.heat, '88.8');
    });
  });

  group('TrendingBangumiService retry', () {
    test('retries transient HTTP and API errors before succeeding', () async {
      SharedPreferences.setMockInitialValues({
        'dandanplay_app_secret': 'test-secret',
        'dandanplay_server_url': 'https://example.test',
      });
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response('temporarily unavailable', 503);
        }
        if (requestCount == 2) {
          return http.Response(
            json.encode({
              'success': false,
              'errorMessage': 'temporary ranking error',
            }),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(json.encode({
            'success': true,
            'summary': {'rankingType': 'hot', 'period': 'week'},
            'bangumiList': [
              {
                'animeId': 789,
                'animeTitle': '重试成功',
                'imageUrl': 'https://example.test/retry.jpg',
                'rank': 1,
                'heat': '99.9',
              },
            ],
          })),
          200,
        );
      });
      final delays = <Duration>[];
      final retries = <TrendingRetryProgress>[];
      final service = TrendingBangumiService.forTesting(
        client: client,
        delay: (duration) async => delays.add(duration),
      );

      final result = await service.fetch(
        const TrendingBangumiQuery(kind: TrendingRankingKind.allHot),
        forceRefresh: true,
        onRetry: retries.add,
      );

      expect(requestCount, 3);
      expect(retries.map((progress) => progress.retryNumber), [1, 2]);
      expect(retries.every((progress) => progress.maxRetries == 2), isTrue);
      expect(delays, const [
        Duration(milliseconds: 500),
        Duration(milliseconds: 1200),
      ]);
      expect(result.items.single.anime.id, 789);
    });

    test('does not retry a non-transient client response', () async {
      SharedPreferences.setMockInitialValues({
        'dandanplay_app_secret': 'test-secret',
        'dandanplay_server_url': 'https://example.test',
      });
      var requestCount = 0;
      final service = TrendingBangumiService.forTesting(
        client: MockClient((request) async {
          requestCount++;
          return http.Response('unauthorized', 401);
        }),
        delay: (_) async {},
      );

      await expectLater(
        service.fetch(
          const TrendingBangumiQuery(kind: TrendingRankingKind.allHot),
          forceRefresh: true,
        ),
        throwsA(isA<Exception>()),
      );
      expect(requestCount, 1);
    });
  });

  test('existing Home order automatically includes the ranking section',
      () async {
    SharedPreferences.setMockInitialValues({
      'home_sections_order': <String>[
        'continue_watching',
        'today_series',
        'local_library',
      ],
      'home_sections_disabled': <String>[],
    });

    final settings = HomeSectionsSettingsProvider();
    await Future<void>.delayed(Duration.zero);

    expect(settings.orderedSections, contains(HomeSectionType.trending));
    expect(settings.isSectionEnabled(HomeSectionType.trending), isTrue);
  });
}
