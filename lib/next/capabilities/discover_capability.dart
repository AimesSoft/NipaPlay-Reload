import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/trending_bangumi.dart';
import 'package:nipaplay/services/search_service.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/trending_bangumi_service.dart';
import 'package:nipaplay/services/random_recommendation_service.dart';
import 'classic_home.dart';

const _search = ObjectSchema({
  'tags': ArraySchema(StringSchema(minLength: 1),
      description:
          'Text tags: 1–10, each at most 50 characters. Exclusive with advanced fields.'),
  'keyword': StringSchema(),
  'year': IntegerSchema(),
  'minRate': IntegerSchema(minimum: 0, maximum: 10),
  'maxRate': IntegerSchema(minimum: 0, maximum: 10),
  'type': IntegerSchema(),
  'tagIds': ArraySchema(IntegerSchema()),
  'month': IntegerSchema(minimum: 1, maximum: 12),
  'restricted': BooleanSchema(),
  'sort': IntegerSchema(),
  'source': StringSchema(minLength: 1),
});
const _trending = ObjectSchema({
  'kind': StringSchema(values: ['allHot', 'allRising', 'newAnimeHot']),
  'range': StringSchema(
      values: ['week', 'month', 'quarter', 'currentSeason', 'previousSeason']),
  'limit': IntegerSchema(minimum: 1, maximum: 50),
  'forceRefresh': BooleanSchema(),
  'filterAdultContent': BooleanSchema(),
});

final class DiscoverValue implements JsonEncodable {
  const DiscoverValue(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class DiscoverCapability implements Capability {
  @override
  List<Action> get actions => const [
        _DiscoverAction(
            'search_config',
            ObjectSchema({'forceRefresh': BooleanSchema()}),
            'Classic advanced search config: valid years, type/tag/sort IDs. forceRefresh clears its config cache.'),
        _DiscoverAction('search', _search,
            'Classic tag or advanced search; returns ALL results with rating and metadata. Supply tags alone, or advanced fields (keyword/year/minRate/maxRate/type/tagIds/month/restricted/sort/source). Defaults: rates 0–10, sort 0, source anidb. No UI draft or paging required.'),
        _DiscoverAction(
            'search_batch',
            ObjectSchema({'requests': ArraySchema(_search)},
                required: ['requests']),
            'Run independent Classic searches in one call; per-request results or errors, in input order. All inputs validated before any request.'),
        _DiscoverAction('trending', _trending,
            'Complete Classic ranking with summary dates, ranks, heat/growth metrics. Defaults allHot/week/limit=20/filterAdultContent=true. allHot/allRising use week/month/quarter; newAnimeHot uses currentSeason/previousSeason. forceRefresh bypasses cache; Classic may return stale cache on network failure.'),
        _DiscoverAction(
            'trending_batch',
            ObjectSchema({'requests': ArraySchema(_trending)},
                required: ['requests']),
            'Query multiple rankings in one call, in order with per-request errors. Same defaults and range rules as discover.trending; validates all requests first.'),
        _DiscoverAction(
            'calendar',
            ObjectSchema({
              'forceRefresh': BooleanSchema(),
              'filterAdultContent': BooleanSchema()
            }),
            'Full Classic new-series calendar, today and weekday groups; 0=Sunday, 1–6=Monday–Saturday, -1=unknown. Defaults false/true; Classic can use cached data if network fails.'),
        _DiscoverAction(
            'recommendations',
            ObjectSchema({'next': BooleanSchema()}),
            'Returns official daily groups, tags, date, generatedAt and Classic active group. next=true switches Classic to its next cached nonempty group exactly like 换一组. Requires mounted home for next=true.'),
        _DiscoverAction('home', ObjectSchema({}),
            'Read full mounted Classic home data including hero/recent/today/recommendation groups/ranking/review/continue-watching; no network request.'),
        _DiscoverAction('refresh', ObjectSchema({}),
            'Await Classic manual home refresh: remote Resume, history, hero/recent/calendar/random/ranking/review. Returns observed data and loading/errors. refreshed=false means busy/player active; refreshed=true means Classic loaders finished, not proof of fresh network data.'),
      ];
}

final class _DiscoverAction extends Action<DiscoverValue, DiscoverValue> {
  const _DiscoverAction(this.operation, this.input, this.description);
  final String operation, description;
  final ObjectSchema input;
  @override
  ActionSpec get spec => ActionSpec(
      id: 'discover.$operation',
      title: 'Discover $operation',
      description: '${[
        'search',
        'search_batch',
        'search_config',
        'trending',
        'trending_batch',
        'calendar'
      ].contains(operation) ? 'Requires a signed-in Dandanplay account; accounts.login opens user login. ' : ''}$description',
      effect: operation == 'refresh' || operation == 'recommendations'
          ? Effect.write
          : Effect.read,
      input: input,
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  DiscoverValue decodeInput(JsonMap input) => DiscoverValue(input);

  void validateRequest(JsonMap v, String op) {
    if (op == 'search') {
      if (v.containsKey('tags')) {
        final tags = (v['tags'] as List).cast<String>();
        if (v.length != 1 ||
            tags.isEmpty ||
            tags.length > 10 ||
            tags.any(
                (t) => t.trim().isEmpty || t.length > 50 || t.contains(','))) {
          throw const Failure(FailureCode.invalidInput,
              'Supply tags alone: 1–10 nonblank tags, at most 50 characters each, without commas.');
        }
      } else if ((v['minRate'] as num? ?? 0) > (v['maxRate'] as num? ?? 10)) {
        throw const Failure(
            FailureCode.invalidInput, 'minRate must not exceed maxRate.');
      }
    }
    if (op == 'trending') {
      final kind = v['kind'] ?? 'allHot';
      final range =
          v['range'] ?? (kind == 'newAnimeHot' ? 'currentSeason' : 'week');
      if (!(kind == 'newAnimeHot'
              ? ['currentSeason', 'previousSeason']
              : ['week', 'month', 'quarter'])
          .contains(range)) {
        throw const Failure(FailureCode.invalidInput,
            'Ranking kind and range are incompatible.');
      }
    }
  }

  Future<JsonMap> request(String op, JsonMap v) async {
    switch (op) {
      case 'search':
        final result = v.containsKey('tags')
            ? await SearchService.instance
                .searchAnimeByTags((v['tags'] as List).cast<String>())
            : await SearchService.instance.searchAnimeAdvanced(
                keyword: v['keyword'] as String?,
                year: v['year'] as int?,
                minRate: v['minRate'] as int? ?? 0,
                maxRate: v['maxRate'] as int? ?? 10,
                type: v['type'] as int?,
                tagIds: (v['tagIds'] as List?)?.cast<int>(),
                month: v['month'] as int?,
                restricted: v['restricted'] as bool?,
                sort: v['sort'] as int? ?? 0,
                source: v['source'] as String? ?? 'anidb');
        return {
          'animes': result.animes.map((a) => a.toJson()).toList(),
          'hasMore': result.hasMore
        };
      case 'trending':
        final kind =
            TrendingRankingKind.values.byName(v['kind'] as String? ?? 'allHot');
        final range = v['range'] as String? ??
            (kind == TrendingRankingKind.newAnimeHot
                ? 'currentSeason'
                : 'week');
        final query = TrendingBangumiQuery(
            kind: kind,
            period: kind == TrendingRankingKind.newAnimeHot
                ? TrendingPeriod.week
                : TrendingPeriod.values.byName(range),
            scope: kind == TrendingRankingKind.newAnimeHot
                ? TrendingNewAnimeScope.values.byName(range)
                : TrendingNewAnimeScope.currentSeason);
        return (await TrendingBangumiService.instance.fetch(query,
                forceRefresh: v['forceRefresh'] as bool? ?? false,
                filterAdultContent: v['filterAdultContent'] as bool? ?? true,
                limit: v['limit'] as int? ?? 20))
            .toJson();
      default:
        throw StateError(op);
    }
  }

  @override
  Future<Outcome<DiscoverValue>> run(
      DiscoverValue input, Invocation invocation) async {
    final v = input.value;
    if (operation.endsWith('_batch')) {
      final op = operation.replaceFirst('_batch', '');
      final requests = (v['requests'] as List).cast<JsonMap>();
      if (requests.isEmpty || requests.length > 20)
        throw const Failure(FailureCode.invalidInput, 'Supply 1–20 requests.');
      for (final r in requests) {
        validateRequest(r, op);
      }
      final results = await Future.wait(requests.map((r) async {
        try {
          return {'input': r, 'result': await request(op, r)};
        } catch (e) {
          return {'input': r, 'error': e.toString()};
        }
      }));
      return Completed(DiscoverValue({'results': results}));
    }
    validateRequest(v, operation);
    JsonMap result;
    switch (operation) {
      case 'search_config':
        if (v['forceRefresh'] == true)
          await SearchService.instance.clearCache();
        final config = await SearchService.instance.getSearchConfig();
        result = {
          'minYear': config.minYear,
          'maxYear': config.maxYear,
          'types': [
            for (final i in config.types) {'key': i.key, 'value': i.value}
          ],
          'tags': [
            for (final i in config.tags) {'key': i.key, 'value': i.value}
          ],
          'sorts': [
            for (final i in config.sorts) {'key': i.key, 'value': i.value}
          ]
        };
      case 'search' || 'trending':
        result = await request(operation, v);
      case 'calendar':
        final animes = await BangumiService.instance.getCalendar(
            forceRefresh: v['forceRefresh'] as bool? ?? false,
            filterAdultContent: v['filterAdultContent'] as bool? ?? true);
        final today = DateTime.now().weekday % 7;
        result = {
          'todayWeekday': today,
          'animes': animes.map((a) => a.toJson()).toList(),
          'groups': [
            for (final day in [-1, 0, 1, 2, 3, 4, 5, 6])
              {
                'weekday': day,
                'animes': [
                  for (final a in animes)
                    if ((a.airWeekday == null ||
                                a.airWeekday! < 0 ||
                                a.airWeekday! > 6
                            ? -1
                            : a.airWeekday) ==
                        day)
                      a.toJson()
                ],
              }
          ],
          'today': [
            for (final a in animes)
              if (a.airWeekday == today) a.toJson()
          ]
        };
      case 'recommendations':
        final home = classicHome();
        if (v['next'] == true && home == null)
          throw const Failure(FailureCode.unavailable,
              'Classic home is not mounted. Open home first.');
        if (v['next'] == true) {
          result = await home!.recommendations(next: true);
        } else {
          result = (await RandomRecommendationService.instance
                  .fetchDailyRecommendations())
              .toJson();
          result['activeGroupIndex'] =
              home?.homeSnapshot['recommendationGroupIndex'];
        }
      case 'home' || 'refresh':
        final home = classicHome();
        if (home == null)
          throw const Failure(FailureCode.unavailable,
              'Classic home is not mounted. Open home first.');
        result = operation == 'refresh'
            ? await home.refreshHome()
            : home.homeSnapshot;
      default:
        throw StateError(operation);
    }
    return Completed(DiscoverValue(result));
  }
}
