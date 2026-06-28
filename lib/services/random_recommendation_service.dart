import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/search_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RandomRecommendationService {
  RandomRecommendationService._();

  static final RandomRecommendationService instance =
      RandomRecommendationService._();

  static const String _endpoint =
      'https://nipaplay.aimes-soft.com/api/random-recommendations';
  static const String _cacheKey = 'daily_random_recommendations_cache';
  static const Duration _requestTimeout = Duration(seconds: 8);

  Future<DailyRandomRecommendations> fetchDailyRecommendations() async {
    try {
      final response = await http.get(Uri.parse(_endpoint),
          headers: {'Accept': 'application/json'}).timeout(_requestTimeout);
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = json.decode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic> || data['success'] != true) {
        throw const FormatException('Invalid random recommendations payload');
      }

      final recommendations = DailyRandomRecommendations.fromJson(data);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(recommendations.toJson()));
      return recommendations;
    } catch (e) {
      debugPrint('[RandomRecommendationService] 官方推荐接口不可用，尝试本地缓存: $e');
      final cached = await _readCachedRecommendations();
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  Future<DailyRandomRecommendations?> _readCachedRecommendations() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedString = prefs.getString(_cacheKey);
    if (cachedString == null || cachedString.isEmpty) return null;

    try {
      final data = json.decode(cachedString);
      if (data is! Map<String, dynamic>) return null;
      return DailyRandomRecommendations.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}

class DailyRandomRecommendations {
  final String date;
  final DateTime? generatedAt;
  final List<RandomRecommendationGroup> groups;

  const DailyRandomRecommendations({
    required this.date,
    required this.generatedAt,
    required this.groups,
  });

  factory DailyRandomRecommendations.fromJson(Map<String, dynamic> json) {
    final groups = (json['groups'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(RandomRecommendationGroup.fromJson)
            .where((group) => group.items.isNotEmpty)
            .toList() ??
        [];
    if (groups.isEmpty) {
      throw const FormatException('Random recommendations contain no groups');
    }

    return DailyRandomRecommendations(
      date: json['date']?.toString() ?? '',
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
      groups: groups,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': true,
      'date': date,
      'generatedAt': generatedAt?.toIso8601String(),
      'groups': groups.map((group) => group.toJson()).toList(),
    };
  }
}

class RandomRecommendationGroup {
  final int index;
  final String id;
  final List<RandomRecommendationItem> items;

  const RandomRecommendationGroup({
    required this.index,
    required this.id,
    required this.items,
  });

  factory RandomRecommendationGroup.fromJson(Map<String, dynamic> json) {
    return RandomRecommendationGroup(
      index: (json['index'] as num?)?.toInt() ?? 0,
      id: json['id']?.toString() ?? '',
      items: (json['items'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(RandomRecommendationItem.fromJson)
              .where((item) => item.anime.animeId > 0)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'id': id,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class RandomRecommendationItem {
  final String tag;
  final SearchResultAnime anime;

  const RandomRecommendationItem({
    required this.tag,
    required this.anime,
  });

  factory RandomRecommendationItem.fromJson(Map<String, dynamic> json) {
    final anime = json['anime'];
    if (anime is! Map<String, dynamic>) {
      throw const FormatException('Random recommendation item has no anime');
    }
    return RandomRecommendationItem(
      tag: json['tag']?.toString() ?? '',
      anime: SearchResultAnime.fromJson(anime),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tag': tag,
      'anime': anime.toJson(),
    };
  }
}
