import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/services/jellyfin_episode_mapping_service.dart';

/// 负责将Jellyfin媒体与DandanPlay的内容匹配，以获取弹幕和元数据
class JellyfinDandanplayMatcher {
  static final JellyfinDandanplayMatcher instance = JellyfinDandanplayMatcher._internal();
  
  JellyfinDandanplayMatcher._internal();

  // 预计算哈希值和预匹配弹幕ID的方法
  // 
  // 在视频播放前提前计算哈希值和匹配弹幕ID，避免播放时卡顿
  // 返回一个包含预匹配结果的Map
  Future<Map<String, dynamic>> precomputeVideoInfoAndMatch(
      BuildContext context,
      JellyfinEpisodeInfo episode) async {
    try {
      final String seriesName = episode.seriesName ?? '未知剧集';
      final String episodeName = episode.name.isNotEmpty ? episode.name : '未知标题';
      debugPrint('开始预计算Jellyfin视频信息和匹配弹幕ID: $seriesName - $episodeName');
      
      // 启动哈希值计算，但用超时控制，避免阻塞太长时间
      Map<String, dynamic> videoInfoMap = {};
      try {
        videoInfoMap = await calculateVideoHash(episode)
            .timeout(const Duration(seconds: 5), onTimeout: () {
          debugPrint('哈希值计算超时，将在后台继续计算');
          // 在后台继续计算哈希值
          calculateVideoHash(episode).then((hashResult) {
            debugPrint('后台哈希值计算完成: hash=${hashResult["hash"]}, fileName=${hashResult["fileName"]}, fileSize=${hashResult["fileSize"]}');
          }).catchError((e) {
            debugPrint('后台哈希值计算出错: $e');
          });
          
          // 创建一个基于剧集信息的临时哈希值
          final String seriesName = episode.seriesName ?? '';
          final String episodeName = episode.name.isNotEmpty ? episode.name : '';
          final String tempHash = md5.convert(utf8.encode('$seriesName$episodeName${DateTime.now()}')).toString();
          debugPrint('生成临时哈希值: $tempHash (超时)');
          
          // 返回临时结果
          return {
            'hash': tempHash,
            'fileName': '$seriesName - $episodeName.mp4',
            'fileSize': 0
          };
        });

        debugPrint('成功计算视频信息: hash=${videoInfoMap["hash"]}, fileName=${videoInfoMap["fileName"]}, fileSize=${videoInfoMap["fileSize"]}');
      } catch (hashError) {
        debugPrint('哈希值计算发生错误: $hashError');
        // 哈希计算失败不影响主流程，继续匹配
        // 使用默认值
        videoInfoMap = {
          'hash': '',
          'fileName': '$seriesName - $episodeName.mp4',
          'fileSize': 0
        };
      }
      
      // 获取预匹配结果
      final matchResult = await _matchWithDandanPlay(context, episode, false, videoInfoMap);
      
      if (matchResult.isNotEmpty && 
          matchResult['matches'] != null && 
          matchResult['matches'].isNotEmpty) {
        
        final match = matchResult['matches'][0];
        final animeId = match['animeId'];
        final episodeId = match['episodeId'];
        
        if (episodeId != null && animeId != null) {
          debugPrint('预匹配成功! 已获取ID: animeId=$animeId, episodeId=$episodeId');
          
          // 预先获取弹幕数据并缓存，但不等待结果
          _preloadDanmaku(episodeId.toString(), animeId);
          
          return {
            'success': true,
            'animeId': animeId,
            'episodeId': episodeId,
            'animeTitle': match['animeTitle'],
            'episodeTitle': match['episodeTitle'],
            'videoHash': videoInfoMap['hash'], // 如果计算成功，则包含哈希值
            'fileName': videoInfoMap['fileName'],
            'fileSize': videoInfoMap['fileSize']
          };
        }
      }
      
      debugPrint('预匹配未能找到完全匹配的结果');
      return {
        'success': false, 
        'message': '未能找到完全匹配的结果',
        'videoHash': videoInfoMap['hash'], // 即使匹配失败，也可以返回已计算的哈希值
        'fileName': videoInfoMap['fileName'],
        'fileSize': videoInfoMap['fileSize']
      };
    } catch (e) {
      debugPrint('预计算和匹配过程中出错: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  // 预加载弹幕数据（异步执行，不等待结果）
  Future<void> _preloadDanmaku(String episodeId, int animeId) async {
    try {
      debugPrint('开始预加载弹幕: episodeId=$episodeId, animeId=$animeId');
      
      // 检查是否已经缓存了弹幕数据
      final cachedDanmaku = await DanmakuCacheManager.getDanmakuFromCache(episodeId);
      if (cachedDanmaku != null) {
        debugPrint('弹幕已存在于缓存中，无需预加载: episodeId=$episodeId');
        return;
      }
      
      // 异步预加载弹幕，不等待结果
      DandanplayService.getDanmaku(episodeId, animeId).then((danmakuData) {
        final count = danmakuData['count'];
        if (count != null) {
          debugPrint('弹幕预加载成功: 加载了$count条弹幕');
        } else {
          debugPrint('弹幕预加载成功，但无法确定数量');
        }
        
        // 确保弹幕数据被正确缓存
        if (danmakuData['comments'] != null && danmakuData['comments'] is List) {
          final List<dynamic> comments = danmakuData['comments'];
          if (comments.isNotEmpty) {
            debugPrint('已成功缓存 ${comments.length} 条弹幕');
          }
        }
      }).catchError((e) {
        debugPrint('弹幕预加载失败: $e');
      });
    } catch (e) {
      debugPrint('预加载弹幕出错: $e');
    }
  }

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
      
      // 获取视频信息（不阻塞主流程）
      Map<String, dynamic> videoInfo = {};
      try {
        videoInfo = await calculateVideoHash(episode).timeout(
          const Duration(seconds: 2),
          onTimeout: () => {'hash': '', 'fileName': '', 'fileSize': 0}
        );
      } catch (e) {
        debugPrint('获取视频信息失败: $e');
      }
      
      // 2. 通过DandanPlay API匹配内容
      final Map<String, dynamic> dummyVideoInfo = await _matchWithDandanPlay(context, episode, showMatchDialog, videoInfo);
      
      // 3. 如果匹配成功，更新历史条目的元数据
      if (dummyVideoInfo.isNotEmpty && dummyVideoInfo['animeId'] != null) {
        final animeId = dummyVideoInfo['animeId'];
        final episodeId = dummyVideoInfo['episodeId'];
        
        debugPrint('匹配成功! animeId=$animeId, episodeId=$episodeId');
        
        // 使用转换后的数据更新WatchHistoryItem
        final updatedItem = WatchHistoryItem(
          filePath: historyItem.filePath, // 保持原始的jellyfin://或emby://协议路径，实际播放时再替换
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
          videoHash: videoInfo['hash'], // 保存视频哈希值，用于后续匹配弹幕
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
  /// [videoInfo] 包含视频哈希值、文件名和文件大小的Map
  Future<Map<String, dynamic>> _matchWithDandanPlay(
      BuildContext context, 
      JellyfinEpisodeInfo episode,
      bool showMatchDialog,
      [Map<String, dynamic>? videoInfo]) async {
    try {
      // 构建匹配的查询参数
      final String seriesName = episode.seriesName ?? '';
      final String episodeName = episode.name;
      
      final String queryTitle = seriesName + (episodeName.isNotEmpty ? ' $episodeName' : '');
      
      debugPrint('开始匹配Jellyfin内容: "$queryTitle"');
      
      // 如果有视频信息，尝试使用哈希值、文件名和文件大小进行匹配
      if (videoInfo != null && 
          (videoInfo['hash']?.isNotEmpty == true || 
           videoInfo['fileName']?.isNotEmpty == true || 
           videoInfo['fileSize'] != null && videoInfo['fileSize'] > 0)) {
        
        debugPrint('尝试使用精确信息匹配: ${videoInfo['fileName']}, 文件大小: ${videoInfo['fileSize']} 字节, 哈希值: ${videoInfo['hash']}');
        
        // 尝试使用弹弹play的match API进行精确匹配
        try {
          final matchResult = await _matchWithDandanPlayAPI(videoInfo);
          if (matchResult.isNotEmpty && matchResult['isMatched'] == true) {
            debugPrint('通过精确匹配成功! 匹配结果: ${matchResult['animeTitle']} - ${matchResult['episodeTitle']}');
            return matchResult;
          } else {
            debugPrint('精确匹配未成功，回退到搜索匹配');
          }
        } catch (e) {
          debugPrint('精确匹配过程中出错: $e，回退到搜索匹配');
        }
      } else {
        debugPrint('没有可用的精确匹配信息，使用标题搜索匹配');
      }
      
      // 使用DandanPlay的API搜索动画
      List<Map<String, dynamic>> animeMatches = await _searchAnime(queryTitle);
      
      // 如果通过标题搜索没找到匹配，尝试使用季名称搜索
      if (animeMatches.isEmpty) {
        debugPrint('未找到匹配的动画，将尝试使用季名称搜索');
        // 尝试使用系列名称（季名称）进行搜索
        final String seriesNameOnly = episode.seriesName ?? '';
        if (seriesNameOnly.isNotEmpty && seriesNameOnly != queryTitle) {
          final seriesMatches = await _searchAnime(seriesNameOnly);
          if (seriesMatches.isNotEmpty) {
            debugPrint('使用季名称"$seriesNameOnly"搜索成功，找到 ${seriesMatches.length} 个匹配');
            animeMatches = seriesMatches; // 使用季名称搜索的结果
          } else {
            debugPrint('使用季名称"$seriesNameOnly"搜索也没有找到匹配结果');
          }
        }
      }
      
      // 无论是否找到匹配结果，声明变量用于存储用户选择
      Map<String, dynamic>? selectedMatch;
      
      if (showMatchDialog) {
        // 总是显示对话框让用户选择或跳过，使其成为阻塞操作
        // 即使没有找到匹配，也要显示对话框，让用户能手动搜索
        selectedMatch = await showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false, // 设置为 false 使对话框成为模态对话框，阻止背景交互
          builder: (context) => AnimeMatchDialog(
            matches: animeMatches, // 可以为空列表，对话框会适当处理
            episodeInfo: episode,
          ),
        );
        
        // 如果用户通过对话框选择了匹配项，记录日志
        if (selectedMatch != null) {
          debugPrint('用户选择了匹配项: ${selectedMatch['animeTitle']}');
        } else {
          debugPrint('用户跳过了匹配');
        }
      } else {
        // 非对话框模式下（例如预计算），如果匹配项不为空，则自动选择第一个
        if (animeMatches.isNotEmpty) {
          selectedMatch = animeMatches.first;
          debugPrint('自动选择了第一个匹配项: ${selectedMatch['animeTitle']}');
        } else {
          debugPrint('没有找到匹配项，且不显示对话框，无法自动选择');
        }
      }
      
      // 如果用户从对话框中选择了“跳过匹配”(selectedMatch 为 null)
      // 或者在非对话框模式下没有自动匹配到任何结果
      if (selectedMatch == null) {
        debugPrint('用户跳过匹配或未找到/选择匹配项。');
        // 返回一个表示未匹配成功的结构
        // 确保返回的结构与成功匹配时的结构在关键字段上保持一致（例如 isMatched, animeId, episodeId）
        // 以便调用方可以统一处理。
        // 这里的 animeTitle 和 episodeTitle 可以使用 Jellyfin 的原始信息作为后备。
        return {
          'isMatched': false,
          'animeId': null,
          'episodeId': null,
          'animeTitle': episode.seriesName ?? episode.name, // 使用原始标题作为后备
          'episodeTitle': episode.name,                   // 使用原始剧集名作为后备
          'matches': [], // 保持 matches 字段存在且为空列表
        };
      }
      
      // 如果选择了匹配项，返回包含匹配信息的videoInfo格式Map
      
      // 如果用户已经在对话框中选择了剧集，直接使用选择的信息
      if (selectedMatch.containsKey('episodeId') && selectedMatch['episodeId'] != null) {
        debugPrint('用户已经在对话框中选择了剧集: episodeId=${selectedMatch['episodeId']}');
        // 用户已经在对话框中完成了剧集选择，不需要再进行自动匹配
        return {
          'isMatched': true,
          'animeId': selectedMatch['animeId'],
          'animeTitle': selectedMatch['animeTitle'],
          'episodeId': selectedMatch['episodeId'],
          'episodeTitle': selectedMatch['episodeTitle'] ?? episode.name,
          'matches': [
            {
              'animeId': selectedMatch['animeId'], 
              'animeTitle': selectedMatch['animeTitle'],
              'episodeId': selectedMatch['episodeId'],
              'episodeTitle': selectedMatch['episodeTitle'] ?? episode.name,
            }
          ]
        };
      } else {
        debugPrint('警告: 用户选择了动画但没有选择剧集，episodeId可能为空: ${selectedMatch['animeTitle']}');
      }
      
      // 如果用户只选择了动画但没有选择剧集，则需要获取剧集列表并进行匹配
      debugPrint('用户选择了动画但未选择剧集，进行自动匹配');
      // 确保 selectedMatch 包含 animeId 和 animeTitle
      if (selectedMatch['animeId'] == null || selectedMatch['animeTitle'] == null) {
        debugPrint('错误: selectedMatch 中缺少 animeId 或 animeTitle。无法获取剧集。');
        // 返回表示未匹配或信息不足的结构
        return {
          'isMatched': false,
          'animeId': selectedMatch['animeId'], // 可能为 null
          'animeTitle': selectedMatch['animeTitle'] ?? episode.seriesName ?? episode.name,
          'episodeId': null,
          'episodeTitle': episode.name,
          'matches': [],
        };
      }
      final epMatches = await _getAnimeEpisodes(selectedMatch['animeId'], selectedMatch['animeTitle']);
      
      // 尝试根据集数匹配到具体剧集
      Map<String, dynamic> matchedEpisode = {};
      if (epMatches.isNotEmpty) {
        if (episode.indexNumber != null) {
          // 如果有确切的集数信息，尝试精确匹配
          try {
            debugPrint('尝试根据集数 ${episode.indexNumber} 精确匹配剧集');
            
            // 先尝试精确匹配episodeIndex
            var exactMatches = epMatches.where(
              (ep) => ep['episodeIndex'] == episode.indexNumber
            ).toList();
            
            if (exactMatches.isNotEmpty) {
              matchedEpisode = exactMatches.first;
              debugPrint('成功匹配到第 ${episode.indexNumber} 集: ${matchedEpisode['episodeTitle']}, ID: ${matchedEpisode['episodeId']}');
            } else {
              // 然后尝试从标题中查找集数
              exactMatches = epMatches.where((ep) {
                final title = ep['episodeTitle'] as String? ?? '';
                return title.contains('第${episode.indexNumber}') || 
                       title.contains('EP${episode.indexNumber}') ||
                       title.contains('#${episode.indexNumber}');
              }).toList();
              
              if (exactMatches.isNotEmpty) {
                matchedEpisode = exactMatches.first;
                debugPrint('通过标题匹配到第 ${episode.indexNumber} 集: ${matchedEpisode['episodeTitle']}, ID: ${matchedEpisode['episodeId']}');
              } else {
                // 如果集数超出范围但在合理范围内，选择最后一集
                if (episode.indexNumber! > epMatches.length && 
                    episode.indexNumber! <= epMatches.length + 5) {
                  matchedEpisode = epMatches.last;
                  debugPrint('集数超出范围但在合理范围内，使用最后一集: ${matchedEpisode['episodeTitle']}, ID: ${matchedEpisode['episodeId']}');
                } else if (episode.indexNumber! <= epMatches.length) {
                  // 使用索引号匹配
                  matchedEpisode = epMatches[episode.indexNumber! - 1];
                  debugPrint('使用索引号匹配第 ${episode.indexNumber} 集: ${matchedEpisode['episodeTitle']}, ID: ${matchedEpisode['episodeId']}');
                } else {
                  // 无法匹配，使用第一集
                  matchedEpisode = epMatches.first;
                  debugPrint('无法匹配到第 ${episode.indexNumber} 集，使用第一集作为备选: ${matchedEpisode['episodeTitle']}, ID: ${matchedEpisode['episodeId']}');
                }
              }
            }
          } catch (e) {
            debugPrint('精确匹配剧集失败: $e');
            if (epMatches.isNotEmpty) {
              matchedEpisode = epMatches.first;
              debugPrint('出错时使用第一个剧集作为备选: ${matchedEpisode['episodeTitle']}, ID: ${matchedEpisode['episodeId']}');
            }
          }
        } else {
          // 没有集数信息，使用第一个
          matchedEpisode = epMatches.first;
          debugPrint('没有集数信息，使用第一个剧集: ${matchedEpisode['episodeTitle']}, ID: ${matchedEpisode['episodeId']}');
        }
      } else {
        debugPrint('警告: 未找到任何剧集信息');
        
        // 尝试根据季号的不同方式获取剧集信息
        final animeTitle = selectedMatch['animeTitle'];
        if (animeTitle != null && animeTitle.isNotEmpty) {
          // 检查是否包含季号信息，如"第二季"、"S2"等
          final seasonMatch = RegExp(r'第(\d+)季|S(\d+)').firstMatch(animeTitle);
          if (seasonMatch != null) {
            final seasonNumber = int.parse(seasonMatch.group(1) ?? seasonMatch.group(2) ?? '1');
            debugPrint('检测到季号信息: 第$seasonNumber季');
            
            // 尝试查找不含季号的基本动画名称
            String baseAnimeName = animeTitle.replaceAll(RegExp(r'第\d+季|S\d+'), '').trim();
            if (baseAnimeName.isNotEmpty) {
              debugPrint('尝试使用基础动画名称搜索: "$baseAnimeName"');
              
              // 创建一个表示第一集的虚拟剧集
              matchedEpisode = {
                'episodeId': selectedMatch['animeId'] * 10000 + (episode.indexNumber ?? 1),  // 创建一个可能的剧集ID
                'episodeTitle': '第${episode.indexNumber ?? 1}集',
                'episodeIndex': episode.indexNumber ?? 1
              };
              debugPrint('创建虚拟剧集匹配: ${matchedEpisode['episodeTitle']}, ID: ${matchedEpisode['episodeId']}');
            }
          }
        }
      }
        
        // 确保成功提取episodeId
        int? episodeId;
        if (matchedEpisode.containsKey('episodeId')) {
          episodeId = matchedEpisode['episodeId'];
          debugPrint('成功获取episodeId: $episodeId');
        } else {
          debugPrint('警告: 匹配的剧集中没有episodeId字段');
          // 如果没有找到episodeId，但有其他剧集可用，尝试获取第一个剧集的ID
          if (epMatches.isNotEmpty && epMatches.first.containsKey('episodeId')) {
            episodeId = epMatches.first['episodeId'];
            debugPrint('使用第一个剧集的ID作为后备: $episodeId');
          }
        }
        
        // 如果仍然没有获得有效的episodeId，这是一个严重问题，显示警告
        if (episodeId == null) {
          debugPrint('严重警告: 无法获取有效的episodeId，这将导致无法正确加载弹幕');
          // 在非对话框模式下，尝试根据动画ID查询更多信息
          if (!showMatchDialog && selectedMatch['animeId'] != null) {
            debugPrint('尝试再次获取动画 ${selectedMatch['animeId']} 的所有剧集以找到有效的episodeId');
            // 再次尝试获取剧集列表
            // 确保 selectedMatch 包含 animeId 和 animeTitle
            if (selectedMatch['animeId'] == null || selectedMatch['animeTitle'] == null) {
              debugPrint('错误: 第二次尝试获取剧集时，selectedMatch 中仍缺少 animeId 或 animeTitle。');
            } else {
              final List<Map<String, dynamic>> allEpisodes = await _getAnimeEpisodes(selectedMatch['animeId'], selectedMatch['animeTitle']);
              if (allEpisodes.isNotEmpty && allEpisodes.first.containsKey('episodeId')) {
                episodeId = allEpisodes.first['episodeId'];
                debugPrint('第二次尝试成功，获取到episodeId: $episodeId');
                // 同时更新matchedEpisode以获取正确的剧集标题
                matchedEpisode = allEpisodes.first;
              }
            }
          }
        }
        
        // 检查最终的匹配结果
        final String episodeTitle = matchedEpisode.containsKey('episodeTitle') ? matchedEpisode['episodeTitle'] : episode.name;
        
        if (episodeId == null) {
          debugPrint('严重错误: 匹配过程结束但episodeId仍为空，弹幕功能可能无法正常工作');
        } else {
          debugPrint('匹配成功: animeId=${selectedMatch['animeId']}, episodeId=$episodeId, 标题=${selectedMatch['animeTitle']} - $episodeTitle');
          
          // 自动保存映射关系到智能映射系统
          try {
            await _saveMappingToDatabase(episode, selectedMatch, episodeId);
          } catch (e) {
            debugPrint('保存映射关系失败: $e');
          }
        }
        
        // 返回格式化为videoInfo的结构
        return {
          'isMatched': true,
          'animeId': selectedMatch['animeId'],
          'animeTitle': selectedMatch['animeTitle'],
          'episodeId': episodeId,
          'episodeTitle': episodeTitle,
          'matches': [
            {
              'animeId': selectedMatch['animeId'], 
              'animeTitle': selectedMatch['animeTitle'],
              'episodeId': episodeId,
              'episodeTitle': episodeTitle,
            }
          ]
        };
    } catch (e) {
      debugPrint('匹配Jellyfin内容时出错: $e');
    }
    
    return {};
  }
  
  /// 使用弹弹play的match API进行精确匹配
  /// 
  /// [videoInfo] 包含文件哈希值、文件名和文件大小的Map
  Future<Map<String, dynamic>> _matchWithDandanPlayAPI(Map<String, dynamic> videoInfo) async {
    try {
      final String? hash = videoInfo['hash'] as String?;
      final String? fileName = videoInfo['fileName'] as String?;
      final int fileSize = (videoInfo['fileSize'] ?? 0) as int;
      
      if ((hash == null || hash.isEmpty) && (fileName == null || fileName.isEmpty)) {
        return {};
      }
      
      debugPrint('使用弹弹play的match API进行精确匹配: hash=$hash, fileName=$fileName, fileSize=$fileSize');
      
      // 获取appSecret
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/match';
      
      // 构建请求头和请求体
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-AppId': DandanplayService.appId,
        'X-Signature': DandanplayService.generateSignature(
          DandanplayService.appId, 
          timestamp, 
          apiPath, 
          appSecret
        ),
        'X-Timestamp': '$timestamp',
      };
      
      final body = json.encode({
        'fileName': fileName,
        'fileHash': hash,
        'fileSize': fileSize,
        'matchMode': 'hashAndFileName',
      });
      
      debugPrint('发送匹配请求到弹弹play API');
      final response = await http.post(
        Uri.parse('https://api.dandanplay.net/api/v2/match'),
        headers: headers,
        body: body,
      );
      
      debugPrint('匹配API响应状态码: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // 检查是否成功匹配
        if (data['isMatched'] == true) {
          debugPrint('精确匹配成功: ${data['matches']?.length ?? 0} 个结果');
          return data;
        } else {
          debugPrint('弹弹play API未能精确匹配');
          return {};
        }
      } else {
        debugPrint('弹弹play匹配API请求失败: ${response.statusCode}');
        return {};
      }
    } catch (e) {
      debugPrint('调用弹弹play匹配API时出错: $e');
      return {};
    }
  }
  
  /// 通过DandanPlay搜索动画
  Future<List<Map<String, dynamic>>> _searchAnime(String title) async {
    if (title.isEmpty) {
      debugPrint('搜索动画的标题为空');
      return [];
    }
    
    try {
      debugPrint('开始搜索动画: "$title"');
      
      // 获取DandanPlay的appSecret
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/search/anime';
      
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
        
        // 打印前100个字符，避免日志过长
        final previewText = response.body.length > 100 ? 
            '${response.body.substring(0, 100)}...(总长度: ${response.body.length})' : 
            response.body;
        debugPrint('搜索结果预览: $previewText');
        
        // 检查是否有'animes'字段且不为空
        if (data['animes'] != null && data['animes'] is List && data['animes'].isNotEmpty) {
          final results = List<Map<String, dynamic>>.from(data['animes']);
          debugPrint('找到 ${results.length} 个匹配动画');
          
          // 检查返回的结果是否包含所需字段
          bool hasValidResults = false;
          for (var anime in results) {
            if (anime['animeId'] != null && anime['animeTitle'] != null) {
              hasValidResults = true;
              break;
            }
          }
          
          if (!hasValidResults) {
            debugPrint('警告: 所有结果都不包含必要的animeId或animeTitle字段');
          } else {
            // 打印第一个结果的基本信息
            if (results.isNotEmpty) {
              final first = results.first;
              debugPrint('第一个结果: ID=${first['animeId']}, 标题=${first['animeTitle']}, 类型=${first['typeDescription']}');
            }
          }
          
          return results;
        } else {
          debugPrint('没有匹配的动画: animes=${data['animes'] ?? "null"}');
          
          // 检查是否有错误信息
          if (data.containsKey('errorMessage') && data['errorMessage'] != null) {
            debugPrint('API返回错误: ${data['errorMessage']}');
          }
          
          if (data.containsKey('success') && data['success'] == false) {
            debugPrint('API调用失败: success=false');
          }
        }
      } else {
        debugPrint('API调用失败，状态码: ${response.statusCode}, 响应内容: ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('搜索动画时出错: $e');
      debugPrint('错误堆栈: $stackTrace');
    }
    
    debugPrint('搜索"$title"未返回任何结果');
    return [];
  }
  
  /// 获取动画的剧集列表
  Future<List<Map<String, dynamic>>> _getAnimeEpisodes(int animeId, String animeTitle) async {
    debugPrint('开始获取动画ID: $animeId (标题: "$animeTitle") 的剧集列表');
    // 直接使用传入的 animeTitle，不再调用 _getAnimeTitle

    if (animeTitle.isEmpty) {
      debugPrint('动画标题为空 (ID: $animeId)，无法继续搜索剧集。');
      return [];
    }

    try {
      // 使用获取到的动画标题搜索剧集
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/search/episodes';
      
      final url = 'https://api.dandanplay.net/api/v2/search/episodes?anime=${Uri.encodeComponent(animeTitle)}';
      debugPrint('请求URL (使用标题搜索剧集): $url');
      
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

      debugPrint('获取剧集列表状态码 (使用标题搜索): ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final previewText = response.body.length > 200 ? 
            '${response.body.substring(0, 200)}...(总长度: ${response.body.length})' : 
            response.body;
        debugPrint('剧集列表响应预览 (使用标题 "$animeTitle" 搜索): $previewText');
        
        if (data['animes'] != null && data['animes'] is List && (data['animes'] as List).isNotEmpty) {
          Map<String, dynamic>? matchedAnimeByTitleAndId;
          List<dynamic> animesList = data['animes'];

          // 首先尝试通过 animeId 精确匹配
          for (var animeData in animesList) {
            if (animeData is Map<String, dynamic> && animeData['animeId'] == animeId) {
              matchedAnimeByTitleAndId = animeData;
              // 在此上下文中，matchedAnimeByTitleAndId 已被赋值且不为null，因此不需要 '?'
              debugPrint('在标题搜索结果中通过 animeId ($animeId) 精确匹配到动画: ${matchedAnimeByTitleAndId['animeTitle']}');
              break;
            }
          }

          // 如果没有通过 animeId 精确匹配到，但列表不为空，可以考虑使用第一个结果作为备选
          if (matchedAnimeByTitleAndId == null && animesList.isNotEmpty) {
            // animesList.first 可能不是 Map<String, dynamic>，所以需要 as Map<String, dynamic>?
            // 并且 matchedAnimeByTitleAndId 在此赋值后可能为 null，所以后续访问需要 '?'
            matchedAnimeByTitleAndId = animesList.first as Map<String, dynamic>?; 
            debugPrint('警告: 在标题搜索结果中未通过 animeId ($animeId) 精确匹配。使用第一个结果: ${matchedAnimeByTitleAndId?['animeTitle']} (ID: ${matchedAnimeByTitleAndId?['animeId']})');
          }
          
          if (matchedAnimeByTitleAndId != null && 
              matchedAnimeByTitleAndId['episodes'] != null && 
              matchedAnimeByTitleAndId['episodes'] is List) {
            final episodes = List<Map<String, dynamic>>.from(matchedAnimeByTitleAndId['episodes']);
            debugPrint('成功获取 ${episodes.length} 个剧集，动画标题: ${matchedAnimeByTitleAndId['animeTitle']} (原始请求ID: $animeId)');
            
            if (episodes.isNotEmpty) {
              int validEpisodes = 0;
              for (var ep in episodes) {
                if (ep['episodeId'] != null) {
                  validEpisodes++;
                }
              }
              if (validEpisodes < episodes.length) {
                debugPrint('警告: 只有 $validEpisodes/${episodes.length} 个剧集有有效的episodeId');
              } else {
                debugPrint('所有剧集都有有效的episodeId');
              }
              
              final firstEp = episodes.first;
              debugPrint('第一个剧集: ID=${firstEp['episodeId']}, 标题=${firstEp['episodeTitle']}');
              
              for (var i = 0; i < episodes.length; i++) {
                var ep = episodes[i];
                final episodeTitle = ep['episodeTitle'] as String? ?? '';
                // 更新正则表达式以更好地匹配集数，例如 " 01 ", "EP01", "(01)"
                final indexMatch = RegExp(r'第\s*(\d+)\s*[集话期]|\s(\d+)(?:\s|$)|EP\s*(\d+)|\((\d+)\)|\【(\d+)\】|\s(\d+)$').firstMatch(episodeTitle);

                if (indexMatch != null) {
                  // 尝试所有可能的捕获组
                  String? numStr;
                  for (int j = 1; j <= indexMatch.groupCount; j++) {
                    if (indexMatch.group(j) != null) {
                      numStr = indexMatch.group(j);
                      break;
                    }
                  }
                  if (numStr != null) {
                    ep['episodeIndex'] = int.parse(numStr);
                  } else {
                     ep['episodeIndex'] = i + 1; // Fallback
                  }
                } else {
                  ep['episodeIndex'] = i + 1;
                }
              }
            }
            return episodes;
          } else {
            debugPrint('警告: 匹配的动画 (${matchedAnimeByTitleAndId?['animeTitle']}) 中没有episodes字段或不是列表格式。');
          }
        } else {
          debugPrint('警告: 使用标题 "$animeTitle" 搜索剧集时，响应中没有animes字段或为空。');
          if (data.containsKey('errorMessage') && data['errorMessage'] != null) {
            debugPrint('API返回错误: ${data['errorMessage']}');
          }
        }
      } else {
        debugPrint('使用标题 "$animeTitle" 获取剧集列表失败，状态码: ${response.statusCode}, 响应: ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('使用标题 "$animeTitle" 获取剧集列表时出错: $e');
      debugPrint('错误堆栈: $stackTrace');
    }
    
    debugPrint('未能获取动画ID: $animeId (标题: "$animeTitle") 的剧集列表');
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

  /// 计算Jellyfin流媒体视频的哈希值（使用前16MB数据）
  /// 获取原始文件名和文件大小信息
  /// 
  /// [episode] Jellyfin剧集信息
  /// 
  /// 返回包含哈希值、原始文件名和文件大小的Map
  /// 
  /// 注意：此功能暂时被禁用，通过弹窗和关键词搜索匹配弹幕库已经足够使用
  Future<Map<String, dynamic>> calculateVideoHash(JellyfinEpisodeInfo episode) async {
    // 返回一个基于剧集信息的临时哈希值，而不是实际计算
    final String seriesName = episode.seriesName ?? '未知剧集';
    final String episodeName = episode.name.isNotEmpty ? episode.name : '未知标题';
    debugPrint('哈希值计算已禁用，返回基于剧集信息的模拟哈希值');
    
    final String fallbackString = '$seriesName$episodeName${episode.id}${DateTime.now()}';
    final String tempHash = md5.convert(utf8.encode(fallbackString)).toString();
    
    return {
      'hash': tempHash,
      'fileName': '$seriesName - $episodeName.mp4',
      'fileSize': 0
    };
    
    /* 原始哈希值计算代码（已禁用）
    try {
      final String seriesName = episode.seriesName ?? '未知剧集';
      final String episodeName = episode.name.isNotEmpty ? episode.name : '未知标题';
      debugPrint('开始计算Jellyfin视频哈希值: $seriesName - $episodeName');
      
      const int maxBytes = 16 * 1024 * 1024; // 16MB
      String? hash;
      String fileName = ''; 
      int fileSize = 0;

      // 获取媒体文件信息（并行操作）
      final mediaInfoFuture = JellyfinService.instance.getMediaInfo(episode.id);
      
      // 同时获取流媒体URL并开始计算哈希值
      final String streamUrl = getPlayUrl(episode);
      debugPrint('获取流媒体URL: $streamUrl');

      // 使用HTTP Range头只获取前16MB数据
      final response = await http.get(
        Uri.parse(streamUrl),
        headers: {
          'Range': 'bytes=0-${maxBytes - 1}', // 指定只获取前16MB数据
        },
      );

      if (response.statusCode == 200 || response.statusCode == 206) { // 200 OK或206 Partial Content
        debugPrint('成功获取视频前16MB数据: ${response.contentLength} bytes');
        
        // 计算MD5哈希值
        hash = md5.convert(response.bodyBytes).toString();
        debugPrint('哈希值计算完成: $hash');
      } else {
        debugPrint('请求视频数据失败: HTTP ${response.statusCode}');
        throw Exception('请求视频数据失败: HTTP ${response.statusCode}');
      }
      
      // 获取媒体文件信息
      final mediaInfo = await mediaInfoFuture;
      if (mediaInfo.isNotEmpty) {
        fileName = mediaInfo['fileName'] ?? '';
        fileSize = mediaInfo['size'] != null ? int.parse(mediaInfo['size'].toString()) : 0;
        debugPrint('获取到媒体文件信息: 文件名=$fileName, 大小=$fileSize');
      } else {
        debugPrint('未能获取到媒体文件信息，使用默认值');
        fileName = '$seriesName - $episodeName.mp4'; // 默认文件名
        fileSize = response.contentLength ?? 0;      // 使用响应大小作为文件大小的估计
      }
      
      // 确保文件大小是有效的数字
      if (fileSize <= 0 && response.contentLength != null) {
        debugPrint('文件大小无效，使用响应大小作为替代');
        fileSize = response.contentLength!;
      }
      
      return {
        'hash': hash,
        'fileName': fileName,
        'fileSize': fileSize
      };
    } catch (e) {
      debugPrint('计算视频哈希值时出错: $e');
      // 返回一个基于剧集名称的备用哈希值
      final String seriesName = episode.seriesName ?? '';
      final String episodeName = episode.name.isNotEmpty ? episode.name : '';
      final String episodeId = episode.id;
      final fallbackString = '$seriesName$episodeName$episodeId';
      final fallbackHash = md5.convert(utf8.encode(fallbackString)).toString();
      
      return {
        'hash': fallbackHash,
        'fileName': '$seriesName - $episodeName.mp4', // 默认文件名
        'fileSize': 0                                // 默认文件大小
      };
    }
    */
  }
  
  /// 保存映射关系到数据库
  /// 
  /// 在成功匹配后自动保存 Jellyfin 剧集与 DandanPlay 的映射关系
  Future<void> _saveMappingToDatabase(
    JellyfinEpisodeInfo episode, 
    Map<String, dynamic> selectedMatch, 
    dynamic episodeId
  ) async {
    try {
      final mappingService = JellyfinEpisodeMappingService();
      
      // 保存动画级别的映射
      final mappingId = await mappingService.createOrUpdateAnimeMapping(
        jellyfinSeriesId: episode.seriesId ?? '',
        jellyfinSeriesName: episode.seriesName ?? '',
        jellyfinSeasonId: episode.seasonId,
        dandanplayAnimeId: selectedMatch['animeId'],
        dandanplayAnimeTitle: selectedMatch['animeTitle'] ?? '',
      );
      
      // 保存剧集级别的映射
      if (episode.indexNumber != null && episodeId != null && mappingId > 0) {
        await mappingService.recordEpisodeMapping(
          jellyfinEpisodeId: episode.id,
          jellyfinIndexNumber: episode.indexNumber!,
          dandanplayEpisodeId: episodeId,
          mappingId: mappingId,
          confirmed: true,
        );
        
        debugPrint('成功保存映射关系: 剧集 ${episode.indexNumber} -> DandanPlay episodeId: $episodeId');
      }
    } catch (e) {
      debugPrint('保存映射关系时出错: $e');
    }
  }
}

/// 动画匹配对话框
/// 
/// 显示候选的动画匹配列表，让用户选择正确的匹配项，并提供手动搜索功能
class AnimeMatchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> matches;
  final JellyfinEpisodeInfo episodeInfo;
  
  const AnimeMatchDialog({
    super.key,
    required this.matches,
    required this.episodeInfo,
  });
  
  @override
  State<AnimeMatchDialog> createState() => _AnimeMatchDialogState();
}

class _AnimeMatchDialogState extends State<AnimeMatchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _currentMatches = [];
  List<Map<String, dynamic>> _currentEpisodes = [];
  bool _isSearching = false;
  bool _isLoadingEpisodes = false;
  String _searchMessage = '';
  String _episodesMessage = '';
  
  // 匹配的动画和剧集状态
  Map<String, dynamic>? _selectedAnime;
  Map<String, dynamic>? _selectedEpisode;
  
  // 视图状态
  bool _showEpisodesView = false;
  
  @override
  void initState() {
    super.initState();
    _currentMatches = widget.matches;
    
    // 如果初始没有匹配结果，设置提示信息
    if (_currentMatches.isEmpty) {
      _searchMessage = '未找到匹配结果，请尝试手动搜索';
    }
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  // 执行手动搜索动画
  Future<void> _performSearch() async {
    final searchText = _searchController.text.trim();
    if (searchText.isEmpty) return;
    
    setState(() {
      _isSearching = true;
      _searchMessage = '正在搜索...';
      _showEpisodesView = false; // 返回到动画列表视图
      _selectedAnime = null;
      _selectedEpisode = null;
      _currentEpisodes = [];
    });
    
    try {
      // 使用已有的搜索动画功能
      final results = await JellyfinDandanplayMatcher.instance._searchAnime(searchText);
      
      setState(() {
        _isSearching = false;
        _currentMatches = results;
        
        if (results.isEmpty) {
          _searchMessage = '没有找到匹配"$searchText"的结果';
        } else {
          _searchMessage = '';
        }
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchMessage = '搜索出错: $e';
      });
    }
  }
  
  // 加载动画的剧集列表
  Future<void> _loadAnimeEpisodes(Map<String, dynamic> anime) async {
    if (anime['animeId'] == null) {
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '错误：动画ID为空。';
        _currentEpisodes = [];
      });
      return;
    }
    if (anime['animeTitle'] == null || (anime['animeTitle'] as String).isEmpty) {
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '错误：动画标题为空。';
        _currentEpisodes = [];
      });
      return;
    }
    
    final int animeId = anime['animeId'];
    final String animeTitle = anime['animeTitle'] as String;
    debugPrint('开始加载动画ID $animeId (标题: "$animeTitle") 的剧集列表');
    
    setState(() {
      _isLoadingEpisodes = true;
      _episodesMessage = '正在加载剧集...';
      _currentEpisodes = []; // 清空旧列表
      _selectedAnime = anime; // 存储选中的动画
      _showEpisodesView = true;
    });
    
    try {
      // final episodes = await JellyfinDandanplayMatcher.instance._getAnimeEpisodes(animeId);
      // 修正：传递 animeTitle
      final episodes = await JellyfinDandanplayMatcher.instance._getAnimeEpisodes(animeId, animeTitle);
      
      if (!mounted) return; // 检查widget是否还在树中
      
      debugPrint('加载到 ${episodes.length} 个剧集');
      
      // 检查剧集是否有效
      if (episodes.isNotEmpty) {
        bool hasValidEpisodes = false;
        for (var ep in episodes) {
          if (ep.containsKey('episodeId') && ep['episodeId'] != null) {
            hasValidEpisodes = true;
            break;
          }
        }
        
        if (!hasValidEpisodes) {
          debugPrint('警告: 所有剧集都没有有效的episodeId');
        }
      }
      
      if (mounted) {
        setState(() {
          _isLoadingEpisodes = false;
          _currentEpisodes = episodes;
          
          if (episodes.isEmpty) {
            _episodesMessage = '没有找到该动画的剧集信息';
            debugPrint('动画 $animeId 没有剧集信息');
          } else {
            _episodesMessage = '';
            debugPrint('成功加载剧集: ${episodes.length} 集');
            
            // 尝试自动匹配当前集数
            if (widget.episodeInfo.indexNumber != null) {
              final int targetEpisode = widget.episodeInfo.indexNumber!;
              debugPrint('尝试自动匹配第 $targetEpisode 集');
              _tryAutoMatchEpisode(targetEpisode);
            } else {
              debugPrint('无法自动匹配剧集: 没有集数信息');
              // 没有集数信息时，默认选择第一集
              if (episodes.isNotEmpty) {
                setState(() {
                  _selectedEpisode = episodes.first;
                  debugPrint('默认选择第一集: ${episodes.first['episodeTitle']}');
                });
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint('加载剧集列表出错: $e');
      if (mounted) {
        setState(() {
          _isLoadingEpisodes = false;
          _episodesMessage = '加载剧集出错: $e';
        });
      }
    }
  }
  
  // 尝试自动匹配剧集
  void _tryAutoMatchEpisode(int currentEpisodeIndex) {
    try {
      // 首先尝试精确匹配集数
      final exactMatch = _currentEpisodes.firstWhere(
        (ep) => ep['episodeIndex'] == currentEpisodeIndex,
        orElse: () => {},
      );
      
      if (exactMatch.isNotEmpty) {
        setState(() {
          _selectedEpisode = exactMatch;
          debugPrint('自动匹配到剧集: ${exactMatch['episodeTitle']}, episodeId=${exactMatch['episodeId']}');
        });
        return;
      }
      
      // 如果没有精确匹配，尝试查找接近的集数
      final List<Map<String, dynamic>> sortedEpisodes = List.from(_currentEpisodes);
      sortedEpisodes.sort((a, b) {
        final aIndex = a['episodeIndex'] ?? 0;
        final bIndex = b['episodeIndex'] ?? 0;
        return (aIndex - currentEpisodeIndex).abs().compareTo((bIndex - currentEpisodeIndex).abs());
      });
      
      if (sortedEpisodes.isNotEmpty) {
        final closestMatch = sortedEpisodes.first;
        setState(() {
          _selectedEpisode = closestMatch;
          debugPrint('找到最接近的剧集匹配: ${closestMatch['episodeTitle']}, 集数: ${closestMatch['episodeIndex']} (目标集数: $currentEpisodeIndex)');
        });
      }
    } catch (e) {
      debugPrint('自动匹配剧集失败: $e');
      // 失败时尝试选择第一集作为默认
      if (_currentEpisodes.isNotEmpty) {
        setState(() {
          _selectedEpisode = _currentEpisodes.first;
          debugPrint('无法精确匹配剧集，默认选择第一集: ${_currentEpisodes.first['episodeTitle']}');
        });
      }
    }
  }
  
  // 返回动画选择列表
  void _backToAnimeSelection() {
    setState(() {
      _showEpisodesView = false;
      _selectedEpisode = null;
    });
  }
  
  // 完成选择并返回结果
  void _completeSelection() {
    if (_selectedAnime == null) return;
    
    // 创建最终结果对象
    final result = Map<String, dynamic>.from(_selectedAnime!);
    
    // 如果用户选择了剧集，添加剧集信息
    if (_selectedEpisode != null && _selectedEpisode!.isNotEmpty) {
      result['episodeId'] = _selectedEpisode!['episodeId'];
      result['episodeTitle'] = _selectedEpisode!['episodeTitle'];
      debugPrint('用户选择了剧集: ${_selectedEpisode!['episodeTitle']}, episodeId=${_selectedEpisode!['episodeId']}');
    } else {
      // 如果在剧集选择界面用户没有选择具体剧集，但有可用剧集，默认使用第一个
      if (_showEpisodesView && _currentEpisodes.isNotEmpty) {
        final firstEpisode = _currentEpisodes.first;
        result['episodeId'] = firstEpisode['episodeId'];
        result['episodeTitle'] = firstEpisode['episodeTitle'];
        debugPrint('用户没有选择具体剧集，默认使用第一个: ${firstEpisode['episodeTitle']}, episodeId=${firstEpisode['episodeId']}');
      } else {
        debugPrint('警告: 没有匹配到任何剧集信息，episodeId可能为空');
      }
    }
    
    Navigator.of(context).pop(result);
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_showEpisodesView ? '选择匹配的剧集' : '选择匹配的动画'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6, // 适当增大对话框高度
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 视频信息
            Text('正在播放: ${widget.episodeInfo.seriesName} - ${widget.episodeInfo.name}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (widget.episodeInfo.indexNumber != null)
              Text('第 ${widget.episodeInfo.indexNumber} 集',
                  style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            
            // 显示当前选择的动画（在剧集选择视图中）
            if (_showEpisodesView && _selectedAnime != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('已选动画:',
                              style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(_selectedAnime!['animeTitle'] ?? '未知动画',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('返回', style: TextStyle(fontSize: 12)),
                      onPressed: _backToAnimeSelection,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  ],
                ),
              ),
            
            // 手动搜索区域（只在动画选择视图中显示）
            if (!_showEpisodesView)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: '手动搜索动画名称',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _performSearch(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSearching ? null : _performSearch,
                    child: const Text('搜索'),
                  ),
                ],
              ),
            
            const SizedBox(height: 16),
            
            // 动画选择视图
            if (!_showEpisodesView) ...[
              const Text('请从以下匹配结果中选择动画:'),
              const SizedBox(height: 8),
              
              if (_searchMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_searchMessage, 
                    style: TextStyle(
                      color: _searchMessage.contains('出错') ? Colors.red : Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              
              Expanded(
                child: _isSearching 
                  ? const Center(child: CircularProgressIndicator())
                  : _currentMatches.isEmpty
                    ? const Center(
                        child: Text('没有匹配结果', style: TextStyle(color: Colors.grey))
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _currentMatches.length,
                        itemBuilder: (context, index) {
                          final match = _currentMatches[index];
                          return ListTile(
                            title: Text(match['animeTitle'] ?? '未知动画'),
                            subtitle: match['typeDescription'] != null
                                ? Text(match['typeDescription'])
                                : null,
                            onTap: () => _loadAnimeEpisodes(match),
                          );
                        },
                      ),
              ),
            ],
            
            // 剧集选择视图
            if (_showEpisodesView) ...[
              const Text('请选择匹配的剧集:'),
              const SizedBox(height: 8),
              
              if (_episodesMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_episodesMessage, 
                    style: TextStyle(
                      color: _episodesMessage.contains('出错') ? Colors.red : Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              
              Expanded(
                child: _isLoadingEpisodes 
                  ? const Center(child: CircularProgressIndicator())
                  : _currentEpisodes.isEmpty
                    ? const Center(
                        child: Text('没有找到剧集', style: TextStyle(color: Colors.grey))
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _currentEpisodes.length,
                        itemBuilder: (context, index) {
                          final episode = _currentEpisodes[index];
                          final bool isSelected = _selectedEpisode != null &&
                              _selectedEpisode!['episodeId'] == episode['episodeId'];
                          
                          return ListTile(
                            title: Text('第${episode['episodeIndex'] ?? '?'}集: ${episode['episodeTitle'] ?? '未知剧集'}'),
                            trailing: isSelected 
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : null,
                            selected: isSelected,
                            onTap: () {
                              setState(() {
                                _selectedEpisode = episode;
                              });
                            },
                          );
                        },
                      ),
              ),
              
              if (_currentEpisodes.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  child: _selectedEpisode == null 
                    ? const Text(
                      '请选择一个剧集来获取正确的弹幕',
                      style: TextStyle(fontStyle: FontStyle.italic, color: Colors.red),
                    )
                    : const Text(
                      '已选择剧集，点击"确认选择"继续',
                      style: TextStyle(fontStyle: FontStyle.italic, color: Colors.green),
                    ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_showEpisodesView)
          TextButton(
            child: const Text('跳过匹配'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        if (_showEpisodesView) ...[
          TextButton(
            onPressed: _backToAnimeSelection,
            style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
            child: const Text('返回动画选择'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
            child: const Text('跳过匹配'),
          ),
          if (_currentEpisodes.isNotEmpty) 
            ElevatedButton(
              onPressed: _completeSelection,
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedEpisode != null ? Colors.green : Colors.amber,
              ),
              child: _selectedEpisode != null 
                ? const Text('确认选择剧集') 
                : const Text('使用第一集'),
            ),
        ],
      ],
    );
  }
}
