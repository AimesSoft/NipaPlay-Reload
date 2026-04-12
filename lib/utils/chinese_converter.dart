import 'package:flutter/material.dart';
import 'package:nipaplay/l10n/app_locale_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:pinyin/pinyin.dart';
import 'package:nipaplay/constants/settings_keys.dart';

class ChineseConverter {
  // pinyin库v3.3.0中，ChineseHelper已经内置了简繁转换功能，不需要手动加载字典
  static void _ensureDictLoaded() {
    // 不需要任何操作，ChineseHelper已经内置了简繁转换功能
  }

  static String convert(String? text, {String config = 's2t'}) {
    if (text == null || text.isEmpty) return text ?? '';

    try {
      _ensureDictLoaded();
      final result = ChineseHelper.convertToTraditionalChinese(text);
      print('简转繁转换: $text -> $result');
      return result;
    } catch (e) {
      print('简转繁失败: $e');
      return text; // 转换失败时返回原文本
    }
  }

  static Future<String> convertAsync(String? text,
      {String config = 's2t'}) async {
    if (text == null || text.isEmpty) return text ?? '';

    try {
      _ensureDictLoaded();
      final result = ChineseHelper.convertToTraditionalChinese(text);
      print('简转繁转换 (async): $text -> $result');
      return result;
    } catch (e) {
      print('简转繁失败 (async): $e');
      return text; // 转换失败时返回原文本
    }
  }

  static Future<Map<String, dynamic>> convertAnimeData(
      Map<String, dynamic> data, BuildContext? context) async {
    bool isTraditional = await isTraditionalChineseEnvironment(context);

    if (!isTraditional) {
      return data; // 非繁体中文环境，不转换
    }

    // 转换番剧基本信息
    if (data.containsKey('animeTitle')) {
      data['animeTitle'] = convert(data['animeTitle']);
    }
    if (data.containsKey('animeTitleTranslate')) {
      data['animeTitleTranslate'] = convert(data['animeTitleTranslate']);
    }
    if (data.containsKey('summary')) {
      data['summary'] = convert(data['summary']);
    }
    if (data.containsKey('name_cn')) {
      data['name_cn'] = convert(data['name_cn']);
    }

    // 转换剧集信息
    if (data.containsKey('episodes') && data['episodes'] is List) {
      final episodes = data['episodes'] as List;
      for (int i = 0; i < episodes.length; i++) {
        if (episodes[i] is Map<String, dynamic>) {
          final episode = episodes[i] as Map<String, dynamic>;
          if (episode.containsKey('episodeTitle')) {
            episode['episodeTitle'] = convert(episode['episodeTitle']);
          }
        }
      }
    }

    return data;
  }

  // 转换BangumiAnime对象
  static Future<BangumiAnime> convertAnime(BangumiAnime anime) async {
    try {
      // 从shared preferences获取语言设置
      bool isTraditional = await isTraditionalChineseEnvironment(null);

      if (!isTraditional) {
        return anime; // 非繁体中文环境，不转换
      }

      // 创建新的BangumiAnime对象进行转换
      final convertedAnime = BangumiAnime(
        id: anime.id,
        name: convert(anime.name),
        nameCn: convert(anime.nameCn),
        imageUrl: anime.imageUrl,
        summary: anime.summary != null ? convert(anime.summary) : null,
        airDate: anime.airDate,
        airWeekday: anime.airWeekday,
        rating: anime.rating,
        ratingDetails: anime.ratingDetails,
        tags: anime.tags,
        metadata: anime.metadata,
        isNSFW: anime.isNSFW,
        platform: anime.platform,
        totalEpisodes: anime.totalEpisodes,
        typeDescription: anime.typeDescription != null
            ? convert(anime.typeDescription)
            : null,
        bangumiUrl: anime.bangumiUrl,
        isOnAir: anime.isOnAir,
        isFavorited: anime.isFavorited,
        titles: anime.titles,
        searchKeyword: anime.searchKeyword,
        episodeList: anime.episodeList != null
            ? anime.episodeList!.map((ep) {
                return EpisodeData(
                  id: ep.id,
                  title: convert(ep.title),
                  airDate: ep.airDate,
                );
              }).toList()
            : null,
        language: 'zh_Hant', // 设置语言为繁体中文
      );

      return convertedAnime;
    } catch (e) {
      print('转换BangumiAnime失败: $e');
      return anime; // 转换失败时返回原对象
    }
  }

  // 检查是否为繁体中文环境
  static Future<bool> isTraditionalChineseEnvironment(
      BuildContext? context) async {
    if (context != null) {
      final locale = Localizations.localeOf(context);
      final isTraditional = AppLocaleUtils.isTraditionalChineseLocale(locale);
      print('简转繁环境检查 (context): locale=$locale, isTraditional=$isTraditional');
      return isTraditional;
    } else {
      // 如果没有context，从shared preferences获取语言设置
      try {
        final prefs = await SharedPreferences.getInstance();
        final languageMode = prefs.getString(SettingsKeys.appLanguageMode);
        bool isTraditional = false;

        if (languageMode == 'traditional') {
          isTraditional = true;
        } else if (languageMode == 'auto') {
          // 如果是自动模式，根据系统语言判断
          final systemLocale =
              WidgetsBinding.instance.platformDispatcher.locale;
          isTraditional =
              AppLocaleUtils.isTraditionalChineseLocale(systemLocale);
        }

        print(
            '简转繁环境检查 (prefs): languageMode=$languageMode, isTraditional=$isTraditional');
        return isTraditional;
      } catch (e) {
        print('获取语言设置失败: $e');
        return false;
      }
    }
  }

  // 示例：在fromJson中使用转换
  static Map<String, dynamic> convertFromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> convertedJson = Map.from(json);

    // 检查是否需要转换
    SharedPreferences.getInstance().then((prefs) {
      final languageCode = prefs.getString('language_code');
      if (languageCode == 'zh_Hant') {
        // 转换name_cn字段
        if (convertedJson.containsKey('name_cn')) {
          convertedJson['name_cn'] = convert(convertedJson['name_cn']);
        }
        // 转换summary字段
        if (convertedJson.containsKey('summary')) {
          convertedJson['summary'] = convert(convertedJson['summary']);
        }
        // 转换其他文本字段
        if (convertedJson.containsKey('animeTitle')) {
          convertedJson['animeTitle'] = convert(convertedJson['animeTitle']);
        }
      }
    });

    return convertedJson;
  }

  // 示例：fromJson方法中使用转换
  static Future<BangumiAnime> fromJson(Map<String, dynamic> json) async {
    // 先创建基本对象
    var anime = BangumiAnime(
      id: json['id'],
      name: json['name'],
      nameCn: json['name_cn'],
      imageUrl: json['imageUrl'],
      summary: json['summary'],
      airDate: json['airDate'],
      airWeekday: json['airWeekday'],
      rating: json['rating'],
      ratingDetails: json['ratingDetails'],
      tags: json['tags'],
      metadata: json['metadata'],
      isNSFW: json['isNSFW'],
      platform: json['platform'],
      totalEpisodes: json['totalEpisodes'],
      typeDescription: json['typeDescription'],
      bangumiUrl: json['bangumiUrl'],
      isOnAir: json['isOnAir'],
      isFavorited: json['isFavorited'],
      titles: json['titles'],
      searchKeyword: json['searchKeyword'],
      episodeList: json['episodeList'] != null
          ? (json['episodeList'] as List)
              .map((ep) => EpisodeData.fromJson(ep))
              .toList()
          : null,
    );

    // 检查是否需要转换
    bool isTraditional = await isTraditionalChineseEnvironment(null);
    if (isTraditional) {
      // 转换字段
      anime = BangumiAnime(
        id: anime.id,
        name: convert(anime.name),
        nameCn: convert(anime.nameCn),
        imageUrl: anime.imageUrl,
        summary: anime.summary != null ? convert(anime.summary) : null,
        airDate: anime.airDate,
        airWeekday: anime.airWeekday,
        rating: anime.rating,
        ratingDetails: anime.ratingDetails,
        tags: anime.tags,
        metadata: anime.metadata,
        isNSFW: anime.isNSFW,
        platform: anime.platform,
        totalEpisodes: anime.totalEpisodes,
        typeDescription: anime.typeDescription != null
            ? convert(anime.typeDescription)
            : null,
        bangumiUrl: anime.bangumiUrl,
        isOnAir: anime.isOnAir,
        isFavorited: anime.isFavorited,
        titles: anime.titles,
        searchKeyword: anime.searchKeyword,
        episodeList: anime.episodeList != null
            ? anime.episodeList!
                .map((ep) => EpisodeData(
                      id: ep.id,
                      title: convert(ep.title),
                      airDate: ep.airDate,
                    ))
                .toList()
            : null,
      );
    }

    return anime;
  }
}
