import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/random_recommendation_service.dart';

void main() {
  group('DailyRandomRecommendations', () {
    test('parses server groups and anime fields', () {
      final payload = DailyRandomRecommendations.fromJson({
        'success': true,
        'date': '2026-06-28',
        'generatedAt': '2026-06-28T08:00:00.000Z',
        'groups': [
          {
            'index': 0,
            'id': '2026-06-28-1',
            'items': [
              {
                'tag': '治愈',
                'anime': {
                  'animeId': 123,
                  'bangumiId': '456',
                  'animeTitle': '测试番剧',
                  'type': 'tv',
                  'typeDescription': 'TV',
                  'imageUrl': 'https://example.com/cover.jpg',
                  'startDate': '2026-06-28',
                  'episodeCount': 12,
                  'rating': 8.5,
                  'isFavorited': false,
                  'rank': 10,
                  'searchKeyword': '测试',
                  'isOnAir': true,
                  'isRestricted': false,
                  'intro': '简介',
                },
              },
            ],
          },
        ],
      });

      expect(payload.date, '2026-06-28');
      expect(payload.groups, hasLength(1));
      expect(payload.groups.single.items, hasLength(1));

      final item = payload.groups.single.items.single;
      expect(item.tag, '治愈');
      expect(item.anime.animeId, 123);
      expect(item.anime.animeTitle, '测试番剧');
      expect(item.anime.imageUrl, 'https://example.com/cover.jpg');
    });

    test('rejects payloads without usable groups', () {
      expect(
        () => DailyRandomRecommendations.fromJson({
          'success': true,
          'date': '2026-06-28',
          'generatedAt': '2026-06-28T08:00:00.000Z',
          'groups': const [],
        }),
        throwsFormatException,
      );
    });
  });
}
