import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/widgets/nipaplay_theme/manual_danmaku_dialog.dart';

/// 手动弹幕匹配器
/// 
/// 提供手动搜索和匹配弹幕的功能，参考jellyfin_dandanplay_matcher的实现方式
class ManualDanmakuMatcher {
  static final ManualDanmakuMatcher instance = ManualDanmakuMatcher._internal();
  
  ManualDanmakuMatcher._internal();

  /// 搜索动画
  /// 
  /// 根据关键词搜索动画列表
  Future<List<Map<String, dynamic>>> searchAnime(String keyword) async {
    if (keyword.trim().isEmpty) {
      return [];
    }

    try {
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/search/anime';
      
      final url = 'https://api.dandanplay.net/api/v2/search/anime?keyword=${Uri.encodeComponent(keyword)}';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'X-AppId': DandanplayService.appId,
          'X-Signature': DandanplayService.generateSignature(
            DandanplayService.appId, 
            timestamp, 
            apiPath, 
            appSecret
          ),
          'X-Timestamp': '$timestamp',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['animes'] != null && data['animes'] is List) {
          return List<Map<String, dynamic>>.from(data['animes']);
        }
      }
      
        return [];
    } catch (e) {
      debugPrint('搜索动画时出错: $e');
      rethrow;
    }
  }

  /// 获取动画剧集列表
  /// 
  /// 根据动画ID获取剧集信息
  Future<List<Map<String, dynamic>>> getAnimeEpisodes(int animeId) async {
    try {
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/bangumi/$animeId';
      
      final url = 'https://api.dandanplay.net/api/v2/bangumi/$animeId';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'X-AppId': DandanplayService.appId,
          'X-Signature': DandanplayService.generateSignature(
            DandanplayService.appId, 
            timestamp, 
            apiPath, 
            appSecret
          ),
          'X-Timestamp': '$timestamp',
        },
      );
      
      if (response.statusCode == 200) {
      final data = json.decode(response.body);
        
        if (data['episodes'] != null && data['episodes'] is List) {
          return List<Map<String, dynamic>>.from(data['episodes']);
        }
      }
      
      return [];
    } catch (e) {
      debugPrint('获取剧集信息时出错: $e');
      rethrow;
    }
  }

  /// 显示手动匹配弹幕对话框
  /// 
  /// 返回选择的结果：{anime: 动画信息, episode: 剧集信息}
  static Future<Map<String, dynamic>?> showMatchDialog(
    BuildContext context, {
    String? initialVideoTitle,
  }) async {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ManualDanmakuMatchDialog(
        initialVideoTitle: initialVideoTitle,
      ),
    );
  }

  /// 显示手动匹配弹幕对话框（实例方法，为了兼容性）
  /// 
  /// 返回选择的结果：{anime: 动画信息, episode: 剧集信息}
  Future<Map<String, dynamic>?> showManualMatchDialog(
    BuildContext context, {
    String? initialVideoTitle,
  }) async {
    debugPrint('=== ManualDanmakuMatcher.showManualMatchDialog() 被调用 ===');
    print('=== 强制输出：ManualDanmakuMatcher.showManualMatchDialog() 被调用！ ===');
    return await showMatchDialog(
      context,
      initialVideoTitle: initialVideoTitle,
    );
  }

  /// 获取弹幕数据
  /// 
  /// 根据episodeId获取弹幕内容
  Future<Map<String, dynamic>> getDanmaku(String episodeId, int animeId) async {
    try {
      return await DandanplayService.getDanmaku(episodeId, animeId);
    } catch (e) {
      debugPrint('获取弹幕数据时出错: $e');
      rethrow;
    }
  }

  /// 自动匹配弹幕
  /// 
  /// 根据视频文件名自动匹配合适的弹幕
  /// 返回匹配结果，包含弹幕数据和匹配信息
  Future<Map<String, dynamic>> autoMatch(String videoFileName) async {
    // 实现自动匹配逻辑
    // 这里可以使用视频文件名进行智能匹配
    // 目前先返回空结果，后续可以扩展
    
    Map<String, dynamic> result = {
      'success': false,
      'message': '自动匹配功能待实现',
      'danmaku': null,
      'matchInfo': null,
    };
    
    return result;
  }
}
