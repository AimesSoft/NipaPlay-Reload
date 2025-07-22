import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/services/emby_episode_mapping_service.dart';

/// 负责将Emby媒体与DandanPlay的内容匹配，以获取弹幕和元数据
class EmbyDandanplayMatcher {
  static final EmbyDandanplayMatcher instance = EmbyDandanplayMatcher._internal();
  
  EmbyDandanplayMatcher._internal();

  // 预计算哈希值和预匹配弹幕ID的方法
  // 
  // 在视频播放前提前计算哈希值和匹配弹幕ID，避免播放时卡顿
  // 返回一个包含预匹配结果的Map
  Future<Map<String, dynamic>> precomputeVideoInfoAndMatch(
      BuildContext context,
      EmbyEpisodeInfo episode) async {
    try {
      final String seriesName = episode.seriesName ?? '未知剧集';
      final String episodeName = episode.name.isNotEmpty ? episode.name : '未知标题';
      debugPrint('开始预计算Emby视频信息和匹配弹幕ID: $seriesName - $episodeName');
      
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
  /// 将Emby媒体信息转换为可播放的WatchHistoryItem，同时尝试匹配DandanPlay元数据
  /// 
  /// [context] 用于显示匹配对话框
  /// [episode] Emby剧集信息
  /// [showMatchDialog] 是否显示匹配对话框（默认true）
  /// 
  /// 返回一个完整的WatchHistoryItem，包含弹幕信息
  Future<WatchHistoryItem?> createPlayableHistoryItem(
      BuildContext context,
      EmbyEpisodeInfo episode, {
      bool showMatchDialog = true}) async {
    // 1. 先创建基本的WatchHistoryItem
    final historyItem = episode.toWatchHistoryItem();
    
    try {
      // 获取Emby流媒体URL（仅用于日志）
      final streamUrl = getPlayUrl(episode);
      debugPrint('正在为Emby内容创建可播放项: ${episode.seriesName} - ${episode.name}');
      debugPrint('Emby流媒体URL: $streamUrl');
      
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
          filePath: historyItem.filePath, // 保持原始的emby://协议路径，实际播放时再替换
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
        
        // 保存映射关系到数据库
        try {
          await _saveMappingToDatabase(
            episode: episode,
            animeId: animeId,
            animeTitle: dummyVideoInfo['animeTitle'] ?? historyItem.animeName,
            episodeId: episodeId,
            episodeTitle: dummyVideoInfo['episodeTitle'] ?? historyItem.episodeTitle,
          );
        } catch (e) {
          debugPrint('保存映射关系到数据库时出错: $e');
          // 不影响主流程，继续返回匹配结果
        }
        
        return updatedItem;
      } else {
        debugPrint('没有匹配到DandanPlay内容，将使用原始历史记录项');
      }
    } catch (e) {
      debugPrint('Emby媒体匹配失败: $e');
      // 匹配失败仍然返回原始项，不中断播放流程
    }
    
    return historyItem;
  }

  /// 创建一个可播放的历史记录条目（电影版本）
  /// 
  /// 将Emby电影信息转换为可播放的WatchHistoryItem，同时尝试匹配DandanPlay元数据
  /// 复用现有的剧集匹配逻辑，内部进行兼容性转换
  /// 
  /// [context] 用于显示匹配对话框
  /// [movie] Emby电影信息
  /// [showMatchDialog] 是否显示匹配对话框（默认true）
  Future<WatchHistoryItem?> createPlayableHistoryItemFromMovie(
      BuildContext context,
      EmbyMovieInfo movie, {
      bool showMatchDialog = true}) async {
    // 创建虚拟的EmbyEpisodeInfo来复用现有匹配逻辑
    final episodeInfo = _createVirtualEpisodeFromMovie(movie);
    
    // 直接调用现有的剧集匹配方法
    return await createPlayableHistoryItem(context, episodeInfo, showMatchDialog: showMatchDialog);
  }

  /// 创建虚拟的剧集信息从电影，用于复用现有匹配逻辑
  EmbyEpisodeInfo _createVirtualEpisodeFromMovie(EmbyMovieInfo movie) {
    return EmbyEpisodeInfo(
      id: movie.id,
      name: '电影', // 电影设置为通用标题，这样搜索时会是"电影名 电影"
      overview: movie.overview,
      seriesId: movie.id,
      seriesName: movie.name, // 电影名作为系列名，这是主要的搜索关键词
      seasonId: null,
      seasonName: null,
      indexNumber: 1, // 电影默认为第1集
      parentIndexNumber: null,
      imagePrimaryTag: movie.imagePrimaryTag,
      dateAdded: movie.dateAdded,
      premiereDate: movie.premiereDate,
      runTimeTicks: movie.runTimeTicks,
    );
  }

  /// 获取播放URL
  /// 
  /// 根据Emby剧集信息获取媒体流URL
  String getPlayUrl(EmbyEpisodeInfo episode) {
    final url = EmbyService.instance.getStreamUrl(episode.id);
    debugPrint('Emby流媒体URL: $url');
    return url;
  }

  /// 使用DandanPlay API匹配Emby内容
  /// 
  /// 返回格式化为videoInfo的数据
  /// [videoInfo] 包含视频哈希值、文件名和文件大小的Map
  Future<Map<String, dynamic>> _matchWithDandanPlay(
      BuildContext context, 
      EmbyEpisodeInfo episode,
      bool showMatchDialog,
      [Map<String, dynamic>? videoInfo]) async {
    try {
      // 构建匹配的查询参数
      final String seriesName = episode.seriesName ?? '';
      final String episodeName = episode.name;
      
      final String queryTitle = seriesName + (episodeName.isNotEmpty ? ' $episodeName' : '');
      
      debugPrint('开始匹配Emby内容: "$queryTitle"');
      
      // 跳过自动匹配，直接进入手动选择弹窗
      // 因为自动匹配经常失败，用户更倾向于手动选择正确的匹配项
      
      /*
      // 如果有视频信息，尝试使用哈希值、文件名和文件大小进行匹配
      if (videoInfo != null && 
          (videoInfo['hash']?.isNotEmpty == true || 
           videoInfo['fileName']?.isNotEmpty == true || 
           videoInfo['fileSize'] != null && videoInfo['fileSize'] > 0)) {
        
        debugPrint('尝试使用精确信息匹配: ${videoInfo['fileName']}, 文件大小: ${videoInfo['fileSize']} 字节, 哈希值: ${videoInfo['hash']}');
        
        // 尝试使用弹弹play的match API进行精确匹配
        try {
          final matchApiResult = await _matchWithDandanPlayAPI(videoInfo);
          if (matchApiResult.isNotEmpty && matchApiResult['isMatched'] == true) {
            debugPrint('使用match API精确匹配成功');
            return matchApiResult;
          } else {
            debugPrint('match API匹配未成功，尝试fallback搜索');
          }
        } catch (e) {
          debugPrint('使用match API匹配时出错: $e，尝试fallback搜索');
        }
      }
      */
      
      // 为弹窗预搜索一些候选项，但不依赖搜索结果
      debugPrint('为弹窗预搜索候选动画: "$queryTitle"');
      List<Map<String, dynamic>> animeMatches = [];
      
      try {
        animeMatches = await _searchAnime(queryTitle);
        debugPrint('预搜索找到 ${animeMatches.length} 个候选项');
        
        // 如果通过标题搜索没找到匹配，尝试使用季名称搜索
        if (animeMatches.isEmpty) {
          debugPrint('尝试使用季名称搜索');
          final String seriesNameOnly = episode.seriesName ?? '';
          if (seriesNameOnly.isNotEmpty && seriesNameOnly != queryTitle) {
            final seriesMatches = await _searchAnime(seriesNameOnly);
            if (seriesMatches.isNotEmpty) {
              debugPrint('使用季名称"$seriesNameOnly"搜索到 ${seriesMatches.length} 个候选项');
              animeMatches = seriesMatches;
            }
          }
        }
      } catch (e) {
        debugPrint('预搜索过程中出错: $e，将显示空候选列表供手动搜索');
      }
      
      
      Map<String, dynamic>? selectedMatch; // This will hold the chosen anime
      Map<String, dynamic>? matchedEpisode; // This will hold the chosen episode, if selected directly in dialog

      if (showMatchDialog) {
        // 显示匹配对话框，让用户手动选择
        debugPrint('显示选择对话框 (有 ${animeMatches.length} 个预搜索候选项)');
        final dialogResult = await showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false, // Make it modal, like Jellyfin's
          builder: (context) => AnimeMatchDialog(
            matches: animeMatches, // Pass current animeMatches, can be empty
            episodeInfo: episode,
          ),
        );
        
        if (dialogResult != null) {
          selectedMatch = dialogResult;
          if (dialogResult.containsKey('episodeId') && dialogResult['episodeId'] != null) {
            matchedEpisode = dialogResult;
            debugPrint('用户选择了动画和剧集: ${dialogResult['animeTitle']} - ${dialogResult['episodeTitle']}');
          } else {
            debugPrint('用户选择了动画: ${dialogResult['animeTitle']}，但没有选择具体剧集');
          }
        } else {
          debugPrint('用户取消或跳过了匹配对话框');
        }
      } else {
        // 预匹配模式：尝试自动选择最佳匹配项
        debugPrint('预匹配模式：尝试自动选择最佳匹配');
        if (animeMatches.isNotEmpty) {
          selectedMatch = animeMatches.first; // 选择第一个匹配项
          debugPrint('自动选择第一个动画: ${selectedMatch['animeTitle']}');
          
          // 尝试自动匹配剧集
          final episodesList = await _getAnimeEpisodes(selectedMatch['animeId'], selectedMatch['animeTitle']);
          if (episodesList.isNotEmpty && episode.indexNumber != null) {
            // 尝试通过集数匹配
            final targetEpisode = episodesList.firstWhere(
              (ep) {
                final episodeIndex = ep['episodeIndex'];
                int epIndex = 0;
                if (episodeIndex is int) {
                  epIndex = episodeIndex;
                } else if (episodeIndex is String) {
                  epIndex = int.tryParse(episodeIndex) ?? 0;
                }
                return epIndex == episode.indexNumber;
              },
              orElse: () => {},
            );
            
            if (targetEpisode.isNotEmpty) {
              matchedEpisode = targetEpisode;
              debugPrint('自动匹配到剧集: ${matchedEpisode['episodeTitle']}, episodeId=${matchedEpisode['episodeId']}');
            } else {
              debugPrint('无法自动匹配剧集，预匹配失败');
              selectedMatch = null; // 预匹配失败
            }
          } else {
            debugPrint('无法获取剧集列表或没有集数信息，预匹配失败');
            selectedMatch = null; // 预匹配失败
          }
        } else {
          debugPrint('预匹配：没有找到候选动画');
        }
      }

      // If no match was selected (either dialog cancelled/skipped, or no auto-match)
      if (selectedMatch == null) {
        debugPrint('最终没有选择任何匹配项或用户跳过。');
        return {
          'isMatched': false,
          'animeId': null,
          'episodeId': null,
          'animeTitle': episode.seriesName ?? episode.name, // Fallback to original Emby titles
          'episodeTitle': episode.name,
          'matches': [], // Keep structure consistent
        };
      }

      // At this point, selectedMatch is not null.
      // We need to determine matchedEpisode if it wasn't set by the dialog or if it's still null.
      if (matchedEpisode == null) {
        debugPrint('需要为动画 "${selectedMatch['animeTitle']}" 查找或确认剧集');
        final episodesList = await _getAnimeEpisodes(selectedMatch['animeId'], selectedMatch['animeTitle']);
        if (episodesList.isNotEmpty) {
          if (episode.indexNumber != null) {
            // Try to match by episode.indexNumber
            matchedEpisode = episodesList.firstWhere(
              (ep) => ep['episodeNumber'] == episode.indexNumber,
              orElse: () {
                debugPrint('无法通过 indexNumber ${episode.indexNumber} 找到剧集，将尝试选择第一个剧集');
                return episodesList[0]; 
              }
            );
          } else {
            // No indexNumber from Emby episode, default to the first episode of the matched anime
            matchedEpisode = episodesList[0];
            debugPrint('Emby剧集无indexNumber，默认为匹配动画的第一个剧集');
          }
        } else {
          debugPrint('无法获取动画 "${selectedMatch['animeTitle']}" 的剧集列表');
        }
      }
      
      if (matchedEpisode == null) {
        debugPrint('无法找到或确定匹配的剧集 for anime "${selectedMatch['animeTitle']}"');
        // We have an anime match, but no episode match.
        return {
          'isMatched': true, // Matched an anime
          'animeId': selectedMatch['animeId'],
          'animeTitle': selectedMatch['animeTitle'],
          'episodeId': null,
          'episodeTitle': episode.name, // Fallback to original episode name
          'matches': [ 
            {
              'animeId': selectedMatch['animeId'], 
              'animeTitle': selectedMatch['animeTitle'],
              'episodeId': null,
              'episodeTitle': episode.name,
            }
          ]
        };
      }

      // Successfully matched anime and episode
      final dynamic episodeId = matchedEpisode['episodeId'];
      // Ensure episodeTitle is a String, fallback to Emby's episode name if necessary
      final String episodeTitle = (matchedEpisode['episodeTitle'] is String && matchedEpisode['episodeTitle'].isNotEmpty)
                                  ? matchedEpisode['episodeTitle']
                                  : episode.name;

      if (episodeId == null) {
        debugPrint('严重错误: 匹配过程结束但episodeId仍为空，弹幕功能可能无法正常工作');
      } else {
        debugPrint('匹配成功: animeId=${selectedMatch['animeId']}, episodeId=$episodeId, 标题=${selectedMatch['animeTitle']} - $episodeTitle');
        
        // 保存映射关系到数据库
        try {
          await _saveMappingToDatabase(
            episode: episode,
            animeId: selectedMatch['animeId'],
            animeTitle: selectedMatch['animeTitle'],
            episodeId: episodeId,
            episodeTitle: episodeTitle,
          );
        } catch (e) {
          debugPrint('保存映射关系到数据库时出错: $e');
          // 不影响主流程，继续返回匹配结果
        }
      }
      
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
      debugPrint('在 _matchWithDandanPlay 过程中发生错误: $e');
      // Fallback for any unexpected error during the matching process
      return {
        'isMatched': false,
        'animeId': null,
        'episodeId': null,
        'animeTitle': episode.seriesName ?? episode.name,
        'episodeTitle': episode.name,
        'matches': [],
        'error': e.toString(),
      };
    }
  }
  
  /// 使用弹弹play的match API进行精确匹配（已禁用）
  /// 
  /// [videoInfo] 包含文件哈希值、文件名和文件大小的Map
  /// 
  /// 注释：由于自动匹配经常不准确，已禁用此功能，直接使用手动选择
  /*
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
      
      debugPrint('弹弹play match API响应状态: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('match API响应数据: ${response.body}');
        
        if (data['success'] == true && data['matches'] != null) {
          final matches = data['matches'] as List;
          if (matches.isNotEmpty) {
            final match = matches[0];
            return {
              'isMatched': true,
              'animeId': match['animeId'],
              'animeTitle': match['animeTitle'],
              'episodeId': match['episodeId'],
              'episodeTitle': match['episodeTitle'],
              'matches': matches,
            };
          }
        }
      }
    } catch (e) {
      debugPrint('使用弹弹play match API时出错: $e');
    }
    
    return {};
  }
  */

  /// 搜索动画
  /// 
  /// [keyword] 搜索关键词
  /// 
  /// 返回匹配的动画列表
  Future<List<Map<String, dynamic>>> _searchAnime(String keyword) async {
    try {
      // 移除常见的无关词汇
      String cleanedKeyword = keyword
          .replaceAll(RegExp(r'\s*\(\d+\)\s*'), '') // 移除年份
          .replaceAll(RegExp(r'\s*第\d+季\s*'), '') // 移除季度信息
          .replaceAll(RegExp(r'\s*S\d+\s*'), '') // 移除S1, S2等
          .trim();
      
      if (cleanedKeyword.isEmpty) {
        cleanedKeyword = keyword; // 如果清理后为空，使用原始关键词
      }
      
      debugPrint('搜索动画关键词: "$cleanedKeyword"');
      
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/search/anime';
      
      final url = 'https://api.dandanplay.net/api/v2/search/anime?keyword=${Uri.encodeComponent(cleanedKeyword)}';
      debugPrint('请求URL: $url');
      
      final uri = Uri.parse(url);
      
      final headers = {
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
      
      debugPrint('发送搜索请求: ${uri.toString()}');
      final response = await http.get(uri, headers: headers);
      
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
            if (anime.containsKey('animeId') && anime.containsKey('animeTitle')) {
              hasValidResults = true;
              break;
            }
          }
          
          if (hasValidResults) {
            return results;
          } else {
            debugPrint('警告: 搜索结果不包含必要字段 (animeId, animeTitle)');
          }
        } else {
          debugPrint('搜索结果为空或格式不正确');
        }
      } else {
        debugPrint('搜索请求失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('搜索动画时出错: $e');
    }
    
    return [];
  }

  /// 获取动画的剧集列表
  /// 
  /// [animeId] 动画ID
  /// [animeTitle] 动画标题（用于日志）
  /// 
  /// 返回剧集列表
  Future<List<Map<String, dynamic>>> _getAnimeEpisodes(int animeId, String animeTitle) async {
    try {
      debugPrint('获取动画剧集列表: animeId=$animeId, title="$animeTitle"');
      
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/bangumi/$animeId';
      
      final uri = Uri.parse('https://api.dandanplay.net$apiPath');
      
      final headers = {
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
      
      final response = await http.get(uri, headers: headers);
      
      debugPrint('剧集列表请求状态码: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['bangumi'] != null && data['bangumi']['episodes'] != null) {
          final episodes = data['bangumi']['episodes'] as List;
          debugPrint('获取到 ${episodes.length} 个剧集');
          
          return episodes.map((episode) => {
            'episodeId': episode['episodeId'],
            'episodeTitle': episode['episodeTitle'],
            'episodeIndex': episode['episodeNumber'] is int 
                ? episode['episodeNumber'] 
                : int.tryParse(episode['episodeNumber']?.toString() ?? '0') ?? 0, // 确保episodeIndex是数字
          }).toList();
        } else {
          debugPrint('剧集数据格式不正确');
        }
      } else {
        debugPrint('获取剧集列表失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('获取剧集列表时出错: $e');
    }
    
    return [];
  }

  /// 从Emby流媒体URL中提取元数据
  /// 
  /// [streamUrl]是Emby流媒体URL
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
        
        // 从EmbyService获取更多详细信息
        try {
          // 尝试从服务获取剧集详情
          final episodeDetails = await EmbyService.instance.getEpisodeDetails(itemId);
          
          if (episodeDetails != null) {
            debugPrint('成功获取剧集详情: ${episodeDetails.seriesName} - ${episodeDetails.name}');
            
            return {
              'seriesName': episodeDetails.seriesName,
              'episodeTitle': episodeDetails.name, 
              'episodeId': itemId,
              'emby': true,
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

  /// 计算Emby流媒体视频的哈希值（使用前16MB数据）
  /// 获取原始文件名和文件大小信息
  /// 
  /// [episode] Emby剧集信息
  /// 
  /// 返回包含哈希值、原始文件名和文件大小的Map
  /// 
  /// 注意：此功能暂时被禁用，通过弹窗和关键词搜索匹配弹幕库已经足够使用
  Future<Map<String, dynamic>> calculateVideoHash(EmbyEpisodeInfo episode) async {
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
      final String seriesName = episode.seriesName ?? '';
      final String episodeName = episode.name.isNotEmpty ? episode.name : '';
      
      debugPrint('开始计算Emby视频哈希值: $seriesName - $episodeName');
      
      // 获取流媒体URL
      final String streamUrl = EmbyService.instance.getStreamUrl(episode.id);
      
      if (streamUrl.isEmpty) {
        debugPrint('无法获取流媒体URL');
        throw Exception('无法获取流媒体URL');
      }
      
      debugPrint('使用流媒体URL计算哈希值: $streamUrl');
      
      // 首先尝试HEAD请求获取文件大小
      final headResponse = await http.head(Uri.parse(streamUrl));
      final int? contentLength = headResponse.contentLength;
      
      if (contentLength != null) {
        debugPrint('获取到文件大小: $contentLength 字节');
      } else {
        debugPrint('无法从HEAD请求获取文件大小');
      }
      
      // 使用范围请求获取前16MB数据
      const int chunkSize = 16 * 1024 * 1024; // 16MB
      final headers = {'Range': 'bytes=0-${chunkSize - 1}'};
      
      final response = await http.get(Uri.parse(streamUrl), headers: headers);
      
      if (response.statusCode == 206 || response.statusCode == 200) {
        // 计算哈希值
        final hash = md5.convert(response.bodyBytes).toString();
        debugPrint('成功计算哈希值: $hash (使用 ${response.bodyBytes.length} 字节数据)');
        
        // 尝试从EmbyService获取文件信息
        String? fileName;
        int? fileSize;
        
        try {
          final fileInfo = await EmbyService.instance.getMediaFileInfo(episode.id);
          if (fileInfo != null) {
            fileName = fileInfo['fileName'];
            fileSize = fileInfo['fileSize'];
            debugPrint('获取到媒体文件信息: 文件名=$fileName, 大小=$fileSize');
          } else {
            debugPrint('未能获取到媒体文件信息，使用默认值');
            fileName = '$seriesName - $episodeName.mp4'; // 默认文件名
            fileSize = response.contentLength ?? 0;      // 使用响应大小作为文件大小的估计
          }
        } catch (e) {
          debugPrint('获取媒体文件信息时出错: $e，使用默认值');
          fileName = '$seriesName - $episodeName.mp4'; // 默认文件名
          fileSize = response.contentLength ?? 0;      // 使用响应大小作为文件大小的估计
        }
        
        // 确保文件大小是有效的数字
        if ((fileSize == null || fileSize <= 0) && response.contentLength != null) {
          debugPrint('文件大小无效，使用响应大小作为替代');
          fileSize = response.contentLength!;
        }
        
        return {
          'hash': hash,
          'fileName': fileName,
          'fileSize': fileSize
        };
      } else {
        debugPrint('范围请求失败: HTTP ${response.statusCode}');
        throw Exception('范围请求失败: HTTP ${response.statusCode}');
      }
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
  Future<void> _saveMappingToDatabase({
    required EmbyEpisodeInfo episode,
    required int animeId,
    required String animeTitle,
    required dynamic episodeId,
    required String episodeTitle,
  }) async {
    try {
      debugPrint('[Emby映射] 开始保存映射关系到数据库');
      
      // 获取Emby系列和季节信息
      final seriesId = episode.seriesId ?? '';
      final seasonId = episode.seasonId;
      final indexNumber = episode.indexNumber ?? 0;
      
      if (seriesId.isEmpty) {
        debugPrint('[Emby映射] 警告: 无法获取系列ID，跳过映射保存');
        return;
      }
      
      // 创建或更新动画级映射
      final mappingId = await EmbyEpisodeMappingService.instance.createOrUpdateAnimeMapping(
        embySeriesId: seriesId,
        embySeriesName: episode.seriesName ?? '未知系列',
        embySeasonId: seasonId,
        dandanplayAnimeId: animeId,
        dandanplayAnimeTitle: animeTitle,
      );
      
      debugPrint('[Emby映射] 动画映射已保存，映射ID: $mappingId');
      
      // 记录剧集级映射
      await EmbyEpisodeMappingService.instance.recordEpisodeMapping(
        embyEpisodeId: episode.id,
        embyIndexNumber: indexNumber,
        dandanplayEpisodeId: int.tryParse(episodeId.toString()) ?? 0,
        mappingId: mappingId,
        confirmed: true, // 用户手动匹配的，标记为已确认
      );
      
      debugPrint('[Emby映射] 剧集映射已保存: Emby集$indexNumber -> DandanPlay集$episodeId');
      
    } catch (e) {
      debugPrint('[Emby映射] 保存映射关系到数据库时出错: $e');
      rethrow;
    }
  }
}

/// 动画匹配对话框
/// 
/// 显示候选的动画匹配列表，让用户选择正确的匹配项，并提供手动搜索功能
class AnimeMatchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> matches;
  final EmbyEpisodeInfo episodeInfo;
  
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
      final results = await EmbyDandanplayMatcher.instance._searchAnime(searchText);
      
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
      final episodes = await EmbyDandanplayMatcher.instance._getAnimeEpisodes(animeId, animeTitle);
      
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
        (ep) {
          final episodeIndex = ep['episodeIndex'];
          int epIndex = 0;
          if (episodeIndex is int) {
            epIndex = episodeIndex;
          } else if (episodeIndex is String) {
            epIndex = int.tryParse(episodeIndex) ?? 0;
          }
          return epIndex == currentEpisodeIndex;
        },
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
        final aIndexRaw = a['episodeIndex'] ?? 0;
        final bIndexRaw = b['episodeIndex'] ?? 0;
        
        int aIndex = 0;
        int bIndex = 0;
        
        if (aIndexRaw is int) {
          aIndex = aIndexRaw;
        } else if (aIndexRaw is String) {
          aIndex = int.tryParse(aIndexRaw) ?? 0;
        }
        
        if (bIndexRaw is int) {
          bIndex = bIndexRaw;
        } else if (bIndexRaw is String) {
          bIndex = int.tryParse(bIndexRaw) ?? 0;
        }
        
        return (aIndex - currentEpisodeIndex).abs().compareTo((bIndex - currentEpisodeIndex).abs());
      });
      
      if (sortedEpisodes.isNotEmpty) {
        final closestMatch = sortedEpisodes.first;
        setState(() {
          _selectedEpisode = closestMatch;
          final episodeIndexRaw = closestMatch['episodeIndex'];
          final episodeIndex = episodeIndexRaw is int ? episodeIndexRaw : (int.tryParse(episodeIndexRaw?.toString() ?? '0') ?? 0);
          debugPrint('找到最接近的剧集匹配: ${closestMatch['episodeTitle']}, 集数: $episodeIndex (目标集数: $currentEpisodeIndex)');
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

