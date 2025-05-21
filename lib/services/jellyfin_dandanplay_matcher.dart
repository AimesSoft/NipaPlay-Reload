import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';

/// 负责将Jellyfin媒体与DandanPlay的内容匹配，以获取弹幕和元数据
class JellyfinDandanplayMatcher {
  static final JellyfinDandanplayMatcher instance = JellyfinDandanplayMatcher._internal();
  
  JellyfinDandanplayMatcher._internal();

  /// 创建一个可播放的历史记录条目
  /// 
  /// 将Jellyfin媒体信息转换为可播放的WatchHistoryItem，同时尝试匹配DandanPlay元数据
  /// 
  /// [context] 用于显示匹配对话框
  /// [episode] Jellyfin剧集信息
  /// [showMatchDialog] 是否显示匹配对话框（默认true）
  Future<WatchHistoryItem?> createPlayableHistoryItem(
      BuildContext context,
      JellyfinEpisodeInfo episode, {
      bool showMatchDialog = true}) async {
    // 1. 先创建基本的WatchHistoryItem
    final historyItem = episode.toWatchHistoryItem();
    
    try {
      // 获取Jellyfin流媒体URL（仅用于日志）
      final streamUrl = getPlayUrl(episode);
      debugPrint('正在为Jellyfin内容创建可播放项: ${episode.seriesName} - ${episode.name}');
      debugPrint('Jellyfin流媒体URL: $streamUrl');
      
      // 2. 通过DandanPlay API匹配内容
      final Map<String, dynamic> dummyVideoInfo = await _matchWithDandanPlay(context, episode, showMatchDialog);
      
      // 3. 如果匹配成功，更新历史条目的元数据
      if (dummyVideoInfo.isNotEmpty && dummyVideoInfo['animeId'] != null) {
        final animeId = dummyVideoInfo['animeId'];
        final episodeId = dummyVideoInfo['episodeId'];
        
        debugPrint('匹配成功! animeId=$animeId, episodeId=$episodeId');
        
        // 使用转换后的数据更新WatchHistoryItem
        final updatedItem = WatchHistoryItem(
          filePath: historyItem.filePath, // 保持原始的jellyfin://协议路径，实际播放时再替换
          animeName: dummyVideoInfo['animeTitle'] ?? historyItem.animeName,
          episodeTitle: dummyVideoInfo['episodeTitle'] ?? historyItem.episodeTitle,
          episodeId: episodeId,
          animeId: animeId,
          watchProgress: historyItem.watchProgress,
          lastPosition: historyItem.lastPosition,
          duration: historyItem.duration,
          lastWatchTime: historyItem.lastWatchTime,
          thumbnailPath: historyItem.thumbnailPath,
          isFromScan: false,
        );
        debugPrint('创建了增强的历史记录项: ${updatedItem.animeName} - ${updatedItem.episodeTitle}');
        return updatedItem;
      } else {
        debugPrint('没有匹配到DandanPlay内容，将使用原始历史记录项');
      }
    } catch (e) {
      debugPrint('Jellyfin媒体匹配失败: $e');
      // 匹配失败仍然返回原始项，不中断播放流程
    }
    
    return historyItem;
  }

  /// 获取播放URL
  /// 
  /// 根据Jellyfin剧集信息获取媒体流URL
  String getPlayUrl(JellyfinEpisodeInfo episode) {
    final url = JellyfinService.instance.getStreamUrl(episode.id);
    debugPrint('Jellyfin流媒体URL: $url');
    return url;
  }

  /// 使用DandanPlay API匹配Jellyfin内容
  /// 
  /// 返回格式化为videoInfo的数据
  Future<Map<String, dynamic>> _matchWithDandanPlay(
      BuildContext context, 
      JellyfinEpisodeInfo episode,
      bool showMatchDialog) async {
    try {
      // 构建匹配的查询参数
      final String seriesName = episode.seriesName ?? '';
      final String episodeName = episode.name ?? '';
      final String queryTitle = '$seriesName $episodeName'.trim();
      
      debugPrint('开始匹配Jellyfin内容: "$queryTitle"');
      
      // 使用DandanPlay的API搜索动画
      final animeMatches = await _searchAnime(queryTitle);
      
      // 如果没有匹配结果
      if (animeMatches.isEmpty) {
        debugPrint('未找到匹配的动画');
        return {};
      }
      
      debugPrint('找到 ${animeMatches.length} 个匹配动画');
      
      // 如果需要显示对话框让用户选择（有多个匹配结果时）
      Map<String, dynamic>? selectedMatch;
      
      if (showMatchDialog && animeMatches.length > 1) {
        selectedMatch = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) => AnimeMatchDialog(
            matches: animeMatches,
            episodeInfo: episode,
          ),
        );
      } else {
        // 没有指定显示对话框或只有一个匹配结果时，使用第一个
        selectedMatch = animeMatches.first;
      }
      
      // 如果选择了匹配项，返回包含匹配信息的videoInfo格式Map
      if (selectedMatch != null) {
        // 获取视频详情来获得更多信息
        final epMatches = await _getAnimeEpisodes(selectedMatch['animeId']);
        
        // 尝试根据集数匹配到具体剧集
        Map<String, dynamic> matchedEpisode = {};
        if (episode.indexNumber != null && epMatches.length >= episode.indexNumber!) {
          // 如果有确切的集数信息，尝试精确匹配
          try {
            matchedEpisode = epMatches.firstWhere(
              (ep) => ep['episodeIndex'] == episode.indexNumber,
              orElse: () => epMatches.isEmpty ? {} : epMatches.first,
            );
          } catch (e) {
            if (epMatches.isNotEmpty) {
              matchedEpisode = epMatches.first;
            }
          }
        } else {
          // 否则使用第一个
          if (epMatches.isNotEmpty) {
            matchedEpisode = epMatches.first;
          }
        }
        
        // 返回格式化为videoInfo的结构
        return {
          'isMatched': true,
          'animeId': selectedMatch['animeId'],
          'animeTitle': selectedMatch['animeTitle'],
          'episodeId': matchedEpisode.containsKey('episodeId') ? matchedEpisode['episodeId'] : null,
          'episodeTitle': matchedEpisode.containsKey('episodeTitle') ? matchedEpisode['episodeTitle'] : episode.name,
          'matches': [
            {
              'animeId': selectedMatch['animeId'], 
              'animeTitle': selectedMatch['animeTitle'],
              'episodeId': matchedEpisode.containsKey('episodeId') ? matchedEpisode['episodeId'] : null,
              'episodeTitle': matchedEpisode.containsKey('episodeTitle') ? matchedEpisode['episodeTitle'] : episode.name,
            }
          ]
        };
      }
    } catch (e) {
      debugPrint('匹配Jellyfin内容时出错: $e');
    }
    
    return {};
  }
  
  /// 通过DandanPlay搜索动画
  Future<List<Map<String, dynamic>>> _searchAnime(String title) async {
    if (title.isEmpty) {
      debugPrint('搜索动画的标题为空');
      return [];
    }
    
    try {
      debugPrint('搜索动画: "$title"');
      
      // 获取DandanPlay的appSecret
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/search/anime';
      
      final url = 'https://api.dandanplay.net/api/v2/search/anime?keyword=${Uri.encodeComponent(title)}';
      debugPrint('请求URL: $url');
      
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

      debugPrint('搜索结果状态码: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('搜索结果: ${response.body}');
        
        // 处理可能为null的count字段
        final int count = data['count'] ?? 0;
        if (count > 0 && data['animes'] != null) {
          final results = List<Map<String, dynamic>>.from(data['animes']);
          debugPrint('找到 ${results.length} 个匹配动画');
          return results;
        } else {
          debugPrint('没有匹配的动画: count=$count, animes=${data['animes']}');
        }
      }
    } catch (e) {
      debugPrint('搜索动画时出错: $e');
    }
    
    return [];
  }
  
  /// 获取动画的剧集列表
  Future<List<Map<String, dynamic>>> _getAnimeEpisodes(int animeId) async {
    try {
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/anime/$animeId/episodes';
      
      final response = await http.get(
        Uri.parse('https://api.dandanplay.net/api/v2/anime/$animeId/episodes'),
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
        if (data['episodes'] != null) {
          return List<Map<String, dynamic>>.from(data['episodes']);
        }
      }
    } catch (e) {
      debugPrint('获取剧集列表时出错: $e');
    }
    
    return [];
  }

  /// 从Jellyfin流媒体URL中提取元数据
  /// 
  /// [streamUrl]是Jellyfin流媒体URL
  /// 
  /// 返回包含视频元数据的Map
  Future<Map<String, dynamic>> extractMetadataFromStreamUrl(String streamUrl) async {
    try {
      // 尝试从URL中提取itemId
      final RegExp regExp = RegExp(r'/Videos/([^/]+)/stream');
      final match = regExp.firstMatch(streamUrl);
      
      if (match != null && match.groupCount >= 1) {
        final String itemId = match.group(1)!;
        debugPrint('从流媒体URL中提取的itemId: $itemId');
        
        // 从JellyfinService获取更多详细信息
        try {
          // 尝试从服务获取剧集详情
          final episodeDetails = await JellyfinService.instance.getEpisodeDetails(itemId);
          
          if (episodeDetails != null) {
            debugPrint('成功获取剧集详情: ${episodeDetails.seriesName} - ${episodeDetails.name}');
            
            return {
              'seriesName': episodeDetails.seriesName,
              'episodeTitle': episodeDetails.name, 
              'episodeId': itemId,
              'jellyfin': true,
              'success': true
            };
          }
        } catch (detailsError) {
          debugPrint('获取剧集详情时出错: $detailsError');
        }
      }
    } catch (e) {
      debugPrint('从流媒体URL中提取元数据时出错: $e');
    }
    
    return {'success': false};
  }
}

/// 动画匹配对话框
/// 
/// 显示候选的动画匹配列表，让用户选择正确的匹配项
class AnimeMatchDialog extends StatelessWidget {
  final List<Map<String, dynamic>> matches;
  final JellyfinEpisodeInfo episodeInfo;
  
  const AnimeMatchDialog({
    Key? key,
    required this.matches,
    required this.episodeInfo,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择匹配的动画'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('正在播放: ${episodeInfo.seriesName} - ${episodeInfo.name}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('请从以下匹配结果中选择:'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final match = matches[index];
                  return ListTile(
                    title: Text(match['animeTitle']),
                    subtitle: match['typeDescription'] != null
                        ? Text(match['typeDescription'])
                        : null,
                    onTap: () {
                      Navigator.of(context).pop(match);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text('跳过匹配'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
