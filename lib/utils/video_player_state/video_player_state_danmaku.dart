part of video_player_state;

class _LocalDanmakuCandidate {
  final String filePath;
  final String fileName;
  final int score;

  const _LocalDanmakuCandidate({
    required this.filePath,
    required this.fileName,
    required this.score,
  });
}

class _SpoilerAiRequestConfig {
  final SpoilerAiApiFormat apiFormat;
  final String apiUrl;
  final String apiKey;
  final String model;
  final double temperature;

  const _SpoilerAiRequestConfig({
    required this.apiFormat,
    required this.apiUrl,
    required this.apiKey,
    required this.model,
    required this.temperature,
  });
}

extension VideoPlayerStateDanmaku on VideoPlayerState {
  Future<void> _autoDetectAndLoadLocalDanmakuFromVideoDirectory(
      String videoPath) async {
    if (_isDisposed || kIsWeb) return;

    if (videoPath.startsWith('http://') ||
        videoPath.startsWith('https://') ||
        videoPath.startsWith('jellyfin://') ||
        videoPath.startsWith('emby://') ||
        SharedRemoteHistoryHelper.isSharedRemoteStreamPath(videoPath)) {
      return;
    }

    final targetVideoPath = _currentVideoPath;
    bool canContinue() =>
        !_isDisposed && _currentVideoPath == targetVideoPath;

    try {
      final dirPath = p.dirname(videoPath);
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;

      final videoBaseName =
          p.basenameWithoutExtension(videoPath).toLowerCase();

      final candidates = <_LocalDanmakuCandidate>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (!canContinue()) return;
        if (entity is! File) continue;

        final filePath = entity.path;
        final fileName = p.basename(filePath);
        final lowerName = fileName.toLowerCase();
        final ext = p.extension(lowerName);
        if (ext != '.json' && ext != '.xml') continue;

        // 很多目录会带有配置/元数据 JSON/XML，做个简单打分再尝试解析。
        final nameNoExt = p.basenameWithoutExtension(lowerName);
        int score = 0;
        if (nameNoExt == videoBaseName) {
          score += 100;
        } else if (nameNoExt.startsWith(videoBaseName)) {
          score += 80;
        } else if (nameNoExt.contains(videoBaseName)) {
          score += 60;
        }

        if (lowerName.contains('danmaku') ||
            lowerName.contains('barrage') ||
            lowerName.contains('comment') ||
            lowerName.contains('弹幕')) {
          score += 20;
        }

        // 轻微偏好 XML（更常见的B站格式）
        if (ext == '.xml') score += 3;

        candidates.add(_LocalDanmakuCandidate(
          filePath: filePath,
          fileName: fileName,
          score: score,
        ));
      }

      if (!canContinue()) return;
      if (candidates.isEmpty) return;

      candidates.sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) return scoreCompare;
        return a.fileName.compareTo(b.fileName);
      });

      const maxTryCount = 8;
      for (final candidate in candidates.take(maxTryCount)) {
        if (!canContinue()) return;
        final filePath = candidate.filePath;

        // 避免同一文件在一次初始化里被重复加载
        final alreadyLoaded = _danmakuTracks.values.any((track) =>
            track['source'] == 'local' && track['filePath'] == filePath);
        if (alreadyLoaded) continue;

        Map<String, dynamic> jsonData;
        try {
          jsonData = await _readLocalDanmakuFileAsJsonData(filePath);
        } catch (e) {
          debugPrint('自动识别本地弹幕：解析失败，跳过 $filePath: $e');
          continue;
        }

        final commentCount = _countLocalDanmakuComments(jsonData);
        if (commentCount <= 0) continue;

        final baseTrackName = p.basenameWithoutExtension(filePath);
        final trackName = _dedupeLocalTrackName(baseTrackName);

        try {
          await loadDanmakuFromLocal(
            jsonData,
            trackName: trackName,
            sourceFilePath: filePath,
            setStatusMessage: false,
          );
          debugPrint('自动识别本地弹幕：已加载 $filePath -> $trackName');
          return; // 只自动加载最匹配的一份，避免重复弹幕
        } catch (e) {
          debugPrint('自动识别本地弹幕：加载失败，跳过 $filePath: $e');
          continue;
        }
      }
    } catch (e) {
      // 自动加载不应影响正常播放
      debugPrint('自动识别本地弹幕出错: $e');
    }
  }

  Future<Map<String, dynamic>> _readLocalDanmakuFileAsJsonData(
      String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final content = utf8.decode(bytes, allowMalformed: true);
    final lowerPath = filePath.toLowerCase();

    if (lowerPath.endsWith('.xml')) {
      return _convertBilibiliXmlDanmakuToJson(content);
    }

    if (lowerPath.endsWith('.json')) {
      final decoded = json.decode(content);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      }
      if (decoded is List) {
        return <String, dynamic>{'comments': decoded};
      }
      throw Exception('JSON根节点必须是对象或数组');
    }

    throw Exception('不支持的文件格式: $filePath');
  }

  Map<String, dynamic> _convertBilibiliXmlDanmakuToJson(String xmlContent) {
    final List<Map<String, dynamic>> comments = [];

    final RegExp danmakuRegex = RegExp(r'<d p="([^"]+)">([^<]+)</d>');
    final Iterable<RegExpMatch> matches = danmakuRegex.allMatches(xmlContent);

    for (final match in matches) {
      try {
        final String pAttr = match.group(1) ?? '';
        final String textContent = match.group(2) ?? '';

        if (textContent.isEmpty) continue;

        final List<String> pParams = pAttr.split(',');
        if (pParams.length < 4) continue;

        // XML弹幕格式参数：时间,类型,字号,颜色,时间戳,池,用户id,弹幕id
        final double time = double.tryParse(pParams[0]) ?? 0.0;
        final int typeCode = int.tryParse(pParams[1]) ?? 1;
        final int fontSize = int.tryParse(pParams[2]) ?? 25;
        final int colorCode = int.tryParse(pParams[3]) ?? 16777215;

        String danmakuType;
        switch (typeCode) {
          case 4:
            danmakuType = 'bottom';
            break;
          case 5:
            danmakuType = 'top';
            break;
          case 1:
          case 6:
          default:
            danmakuType = 'scroll';
            break;
        }

        final int r = (colorCode >> 16) & 0xFF;
        final int g = (colorCode >> 8) & 0xFF;
        final int b = colorCode & 0xFF;
        final String color = 'rgb($r,$g,$b)';

        comments.add({
          't': time,
          'c': textContent,
          'y': danmakuType,
          'r': color,
          'fontSize': fontSize,
          'originalType': typeCode,
        });
      } catch (_) {
        continue;
      }
    }

    return {
      'count': comments.length,
      'comments': comments,
    };
  }

  int _countLocalDanmakuComments(Map<String, dynamic> jsonData) {
    final comments = jsonData['comments'];
    if (comments is List) return comments.length;

    final data = jsonData['data'];
    if (data is List) return data.length;
    if (data is String) {
      try {
        final parsed = json.decode(data);
        if (parsed is List) return parsed.length;
      } catch (_) {
        return 0;
      }
    }

    return 0;
  }

  String _dedupeLocalTrackName(String baseName) {
    final reservedIds = {'dandanplay', 'timeline'};
    String candidate = baseName.trim().isEmpty ? '本地弹幕' : baseName.trim();
    if (reservedIds.contains(candidate)) {
      candidate = '本地_$candidate';
    }

    if (!_danmakuTracks.containsKey(candidate)) return candidate;

    var index = 2;
    while (_danmakuTracks.containsKey('$candidate ($index)')) {
      index++;
    }
    return '$candidate ($index)';
  }

  Future<void> loadDanmaku(String episodeId, String animeIdStr) async {
    if (_isDisposed) return;
    final targetVideoPath = _currentVideoPath;
    bool canContinue() =>
        !_isDisposed && _currentVideoPath == targetVideoPath;

    try {
      debugPrint('尝试为episodeId=$episodeId, animeId=$animeIdStr加载弹幕');
      _setStatus(PlayerStatus.recognizing, message: '正在加载弹幕...');

      if (episodeId.isEmpty) {
        debugPrint('无效的episodeId，无法加载弹幕');
        _setStatus(PlayerStatus.recognizing, message: '无效的弹幕ID，跳过加载');
        return;
      }

      // 清除之前的弹幕数据
      debugPrint('清除之前的弹幕数据');
      _danmakuList.clear();
      danmakuController?.clearDanmaku();
      if (canContinue()) {
        notifyListeners();
      } else {
        return;
      }

      // 更新内部状态变量，确保新的弹幕ID被保存
      final parsedAnimeId = int.tryParse(animeIdStr) ?? 0;
      final episodeIdInt = int.tryParse(episodeId) ?? 0;

      if (episodeIdInt > 0 && parsedAnimeId > 0) {
        _episodeId = episodeIdInt;
        _animeId = parsedAnimeId;
        debugPrint('更新内部弹幕ID状态: episodeId=$_episodeId, animeId=$_animeId');
      }

      // 从缓存加载弹幕
      final cachedDanmaku =
          await DanmakuCacheManager.getDanmakuFromCache(episodeId);
      if (!canContinue()) return;
      if (cachedDanmaku != null) {
        debugPrint('从缓存中找到弹幕数据，共${cachedDanmaku.length}条');
        _setStatus(PlayerStatus.recognizing, message: '正在从缓存加载弹幕...');

        // 设置最终加载阶段标志，减少动画性能消耗
        _isInFinalLoadingPhase = true;
        if (canContinue()) {
          notifyListeners();
        } else {
          return;
        }

        // 加载弹幕到控制器
        danmakuController?.loadDanmaku(cachedDanmaku);
        _setStatus(PlayerStatus.playing,
            message: '从缓存加载弹幕完成 (${cachedDanmaku.length}条)');

        // 解析弹幕数据并添加到弹弹play轨道
        final parsedDanmaku = await compute(
            parseDanmakuListInBackground, cachedDanmaku as List<dynamic>?);
        if (!canContinue()) return;

        _danmakuTracks['dandanplay'] = {
          'name': '弹弹play',
          'source': 'dandanplay',
          'episodeId': episodeId,
          'animeId': animeIdStr,
          'danmakuList': parsedDanmaku,
          'count': parsedDanmaku.length,
        };
        _danmakuTrackEnabled['dandanplay'] = true;

        // 重新计算合并后的弹幕列表
        if (!canContinue()) return;
        _updateMergedDanmakuList();

        // 移除GPU弹幕字符集预构建调用
        // await _prebuildGPUDanmakuCharsetIfNeeded();

        if (canContinue()) {
          notifyListeners();
        }
        return;
      }

      debugPrint('缓存中没有找到弹幕，从网络加载中...');
      // 从网络加载弹幕
      final animeId = int.tryParse(animeIdStr) ?? 0;

      // 设置最终加载阶段标志，减少动画性能消耗
      _isInFinalLoadingPhase = true;
      if (canContinue()) {
        notifyListeners();
      } else {
        return;
      }

      final danmakuData = await DandanplayService.getDanmaku(episodeId, animeId)
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw TimeoutException('加载弹幕超时');
      });
      if (!canContinue()) return;

      if (danmakuData['comments'] != null && danmakuData['comments'] is List) {
        debugPrint('成功从网络加载弹幕，共${danmakuData['count']}条');

        // 加载弹幕到控制器
        final filteredDanmaku = danmakuData['comments']
            .where((d) => !shouldBlockDanmaku(d))
            .toList();
        danmakuController?.loadDanmaku(filteredDanmaku);

        // 解析弹幕数据并添加到弹弹play轨道
        final parsedDanmaku = await compute(parseDanmakuListInBackground,
            danmakuData['comments'] as List<dynamic>?);
        if (!canContinue()) return;

        _danmakuTracks['dandanplay'] = {
          'name': '弹弹play',
          'source': 'dandanplay',
          'episodeId': episodeId,
          'animeId': animeId.toString(),
          'danmakuList': parsedDanmaku,
          'count': parsedDanmaku.length,
        };
        _danmakuTrackEnabled['dandanplay'] = true;

        // 重新计算合并后的弹幕列表
        if (!canContinue()) return;
        _updateMergedDanmakuList();

        // 移除GPU弹幕字符集预构建调用
        if (canContinue()) {
          await _prebuildGPUDanmakuCharsetIfNeeded();
        } else {
          return;
        }

        _setStatus(PlayerStatus.playing,
            message: '弹幕加载完成 (${danmakuData['count']}条)');
        if (canContinue()) {
          notifyListeners();
        }
      } else {
        debugPrint('网络返回的弹幕数据无效');
        if (canContinue()) {
          _setStatus(PlayerStatus.playing, message: '弹幕数据无效，跳过加载');
        }
      }
    } catch (e, st) {
      debugPrint('加载弹幕失败: $e');
      debugPrintStack(stackTrace: st);
      if (canContinue()) {
        _setStatus(PlayerStatus.playing, message: '弹幕加载失败');
      }
    }
  }

  // 从本地JSON数据加载弹幕（多轨道模式）
  Future<void> loadDanmakuFromLocal(Map<String, dynamic> jsonData,
      {String? trackName,
      String? sourceFilePath,
      bool setStatusMessage = true}) async {
    if (_isDisposed) return;
    final targetVideoPath = _currentVideoPath;
    bool canContinue() =>
        !_isDisposed && _currentVideoPath == targetVideoPath;

    try {
      debugPrint('开始从本地JSON加载弹幕...');

      // 解析弹幕数据，支持多种格式
      List<dynamic> comments = [];

      if (jsonData.containsKey('comments') && jsonData['comments'] is List) {
        // 标准格式：comments字段包含数组
        comments = jsonData['comments'];
      } else if (jsonData.containsKey('data')) {
        // 兼容格式：data字段
        final data = jsonData['data'];
        if (data is List) {
          // data是数组
          comments = data;
        } else if (data is String) {
          // data是字符串，需要解析
          try {
            final parsedData = json.decode(data);
            if (parsedData is List) {
              comments = parsedData;
            } else {
              throw Exception('data字段的JSON字符串不是数组格式');
            }
          } catch (e) {
            throw Exception('data字段的JSON字符串解析失败: $e');
          }
        } else {
          throw Exception('data字段格式不正确，应为数组或JSON字符串');
        }
      } else {
        throw Exception('JSON文件格式不正确，必须包含comments数组或data字段');
      }

      if (comments.isEmpty) {
        throw Exception('弹幕文件中没有弹幕数据');
      }

      // 解析弹幕数据
      final parsedDanmaku =
          await compute(parseDanmakuListInBackground, comments);
      if (!canContinue()) return;

      // 生成轨道名称
      final String finalTrackName =
          trackName ?? 'local_${DateTime.now().millisecondsSinceEpoch}';

      // 添加到本地轨道
      if (!canContinue()) return;
      _danmakuTracks[finalTrackName] = {
        'name': trackName ?? '本地轨道${_danmakuTracks.length}',
        'source': 'local',
        if (sourceFilePath != null) 'filePath': sourceFilePath,
        'danmakuList': parsedDanmaku,
        'count': parsedDanmaku.length,
        'loadTime': DateTime.now(),
      };
      _danmakuTrackEnabled[finalTrackName] = true;

      // 重新计算合并后的弹幕列表
      if (!canContinue()) return;
      _updateMergedDanmakuList();

      debugPrint('本地弹幕轨道添加完成: $finalTrackName，共${comments.length}条');
      if (canContinue()) {
        if (setStatusMessage) {
          _setStatus(PlayerStatus.playing,
              message: '本地弹幕轨道添加完成 (${comments.length}条)');
        } else {
          _addStatusMessage('已自动加载本地弹幕 (${comments.length}条)');
        }
        notifyListeners();
      }
    } catch (e, st) {
      if (!canContinue()) return;
      debugPrint('加载本地弹幕失败: $e');
      debugPrintStack(stackTrace: st);
      if (setStatusMessage) {
        _setStatus(PlayerStatus.playing, message: '本地弹幕加载失败');
      } else {
        _addStatusMessage('本地弹幕自动加载失败');
      }
      rethrow;
    }
  }

  // 更新合并后的弹幕列表
  void _updateMergedDanmakuList() {
    final List<Map<String, dynamic>> mergedList = [];

    // 合并所有启用的轨道
    for (final trackId in _danmakuTracks.keys) {
      if (_danmakuTrackEnabled[trackId] == true) {
        final trackData = _danmakuTracks[trackId]!;
        final trackDanmaku =
            trackData['danmakuList'] as List<Map<String, dynamic>>;
        mergedList.addAll(trackDanmaku);
      }
    }

    // 重新排序
    mergedList.sort((a, b) {
      final timeA = (a['time'] as double?) ?? 0.0;
      final timeB = (b['time'] as double?) ?? 0.0;
      return timeA.compareTo(timeB);
    });

    _totalDanmakuCount = mergedList.length;
    _maybeStartSpoilerDanmakuAnalysis(mergedList);
    final filteredList =
        mergedList.where((d) => !shouldBlockDanmaku(d)).toList();
    _danmakuList = filteredList;

    danmakuController?.clearDanmaku();
    danmakuController?.loadDanmaku(filteredList);

    // 通过更新key来强制刷新DanmakuOverlay
    _danmakuOverlayKey = 'danmaku_${DateTime.now().millisecondsSinceEpoch}';

    debugPrint('弹幕轨道合并及过滤完成，显示${_danmakuList.length}条，总计${mergedList.length}条');
    notifyListeners(); // 确保通知UI更新
  }

  void _maybeStartSpoilerDanmakuAnalysis(List<Map<String, dynamic>> mergedList) {
    if (!_spoilerPreventionEnabled) {
      return;
    }

    final requestConfig = _resolveSpoilerAiRequestConfig();
    if (requestConfig == null) {
      return;
    }

    if (mergedList.isEmpty) {
      _isSpoilerDanmakuAnalyzing = false;
      _spoilerDanmakuAnalysisHash = null;
      _spoilerDanmakuRunningAnalysisHash = null;
      _spoilerDanmakuTexts = <String>{};
      _clearPendingSpoilerDanmakuAnalysis();
      return;
    }

    final danmakuTexts = _collectSpoilerAnalysisDanmakuTexts(mergedList);
    if (danmakuTexts.isEmpty) {
      _isSpoilerDanmakuAnalyzing = false;
      _spoilerDanmakuAnalysisHash = null;
      _spoilerDanmakuRunningAnalysisHash = null;
      _spoilerDanmakuTexts = <String>{};
      _clearPendingSpoilerDanmakuAnalysis();
      return;
    }

    final analysisHash =
        _computeSpoilerDanmakuAnalysisHash(danmakuTexts, requestConfig);
    if (_spoilerDanmakuAnalysisHash == analysisHash) {
      return;
    }

    _spoilerDanmakuAnalysisHash = analysisHash;
    _spoilerDanmakuPendingAnalysisHash = analysisHash;
    _spoilerDanmakuPendingRequestConfig = requestConfig;
    _spoilerDanmakuPendingTexts = danmakuTexts;
    _spoilerDanmakuPendingTargetVideoPath = _currentVideoPath;

    if (_isSpoilerDanmakuAnalyzing) {
      return;
    }

    _scheduleSpoilerDanmakuAnalysisDebounced();
  }

  void _scheduleSpoilerDanmakuAnalysisDebounced() {
    _spoilerDanmakuAnalysisDebounceTimer?.cancel();
    _spoilerDanmakuAnalysisDebounceTimer =
        Timer(const Duration(milliseconds: 650), () {
      if (_isDisposed) return;
      _tryStartPendingSpoilerDanmakuAnalysis();
    });
  }

  void _clearPendingSpoilerDanmakuAnalysis() {
    _spoilerDanmakuAnalysisDebounceTimer?.cancel();
    _spoilerDanmakuAnalysisDebounceTimer = null;
    _spoilerDanmakuPendingAnalysisHash = null;
    _spoilerDanmakuPendingRequestConfig = null;
    _spoilerDanmakuPendingTexts = null;
    _spoilerDanmakuPendingTargetVideoPath = null;
  }

  void _tryStartPendingSpoilerDanmakuAnalysis() {
    if (_isDisposed) return;
    if (!_spoilerPreventionEnabled) {
      _clearPendingSpoilerDanmakuAnalysis();
      return;
    }
    if (_isSpoilerDanmakuAnalyzing) return;

    final analysisHash = _spoilerDanmakuPendingAnalysisHash;
    final requestConfig = _spoilerDanmakuPendingRequestConfig;
    final danmakuTexts = _spoilerDanmakuPendingTexts;
    final targetVideoPath = _spoilerDanmakuPendingTargetVideoPath;

    if (analysisHash == null ||
        requestConfig == null ||
        danmakuTexts == null ||
        danmakuTexts.isEmpty) {
      return;
    }

    if (_currentVideoPath != targetVideoPath) {
      _clearPendingSpoilerDanmakuAnalysis();
      return;
    }

    _spoilerDanmakuAnalysisDebounceTimer?.cancel();
    _spoilerDanmakuAnalysisDebounceTimer = null;
    _spoilerDanmakuPendingAnalysisHash = null;
    _spoilerDanmakuPendingRequestConfig = null;
    _spoilerDanmakuPendingTexts = null;
    _spoilerDanmakuPendingTargetVideoPath = null;

    _isSpoilerDanmakuAnalyzing = true;
    _spoilerDanmakuRunningAnalysisHash = analysisHash;

    unawaited(_runSpoilerDanmakuAnalysis(
      analysisHash: analysisHash,
      targetVideoPath: targetVideoPath,
      requestConfig: requestConfig,
      danmakuTexts: danmakuTexts,
    ));
  }

  List<String> _collectSpoilerAnalysisDanmakuTexts(
      List<Map<String, dynamic>> mergedList) {
    const int maxUniqueTexts = 1200;
    final results = <String>[];
    final seen = <String>{};

    for (final danmaku in mergedList) {
      final content = danmaku['content']?.toString() ?? '';
      final normalized = _normalizeSpoilerMatchText(content);
      if (normalized.isEmpty) continue;

      if (!seen.add(normalized)) continue;
      results.add(normalized);
      if (results.length >= maxUniqueTexts) {
        break;
      }
    }

    return results;
  }

  _SpoilerAiRequestConfig? _resolveSpoilerAiRequestConfig() {
    if (!_spoilerAiUseCustomKey) {
      return const _SpoilerAiRequestConfig(
        apiFormat: SpoilerAiApiFormat.openai,
        apiUrl: DanmakuSpoilerFilterService.defaultEndpoint,
        apiKey: '',
        model: 'gpt-5',
        temperature: 0.5,
      );
    }

    final resolvedModel = _spoilerAiModel.trim();
    final resolvedTemperature = _spoilerAiTemperature.clamp(0.0, 2.0).toDouble();
    final apiUrl = _spoilerAiApiUrl.trim();
    final apiKey = _spoilerAiApiKey.trim();
    if (apiUrl.isEmpty || apiKey.isEmpty || resolvedModel.isEmpty) {
      return null;
    }

    return _SpoilerAiRequestConfig(
      apiFormat: _spoilerAiApiFormat,
      apiUrl: apiUrl,
      apiKey: apiKey,
      model: resolvedModel,
      temperature: resolvedTemperature,
    );
  }

  String _computeSpoilerDanmakuAnalysisHash(
    List<String> danmakuTexts,
    _SpoilerAiRequestConfig requestConfig,
  ) {
    final buffer = StringBuffer();
    buffer.write(_currentVideoPath ?? '');
    buffer.write('|');
    buffer.write(_animeId?.toString() ?? '');
    buffer.write('|');
    buffer.write(_episodeId?.toString() ?? '');
    buffer.write('|');
    buffer.write(_spoilerAiUseCustomKey ? 'custom' : 'builtin');
    buffer.write('|');
    buffer.write(requestConfig.apiFormat.name);
    buffer.write('|');
    buffer.write(requestConfig.apiUrl);
    buffer.write('|');
    buffer.write(requestConfig.model);
    buffer.write('|');
    buffer.write(requestConfig.temperature.toStringAsFixed(3));
    buffer.write('\n');
    for (final text in danmakuTexts) {
      buffer.write(text);
      buffer.write('\u0000');
    }
    return sha1.convert(utf8.encode(buffer.toString())).toString();
  }

  Future<void> _runSpoilerDanmakuAnalysis({
    required String analysisHash,
    required String? targetVideoPath,
    required _SpoilerAiRequestConfig requestConfig,
    required List<String> danmakuTexts,
  }) async {
    try {
      debugPrint('[防剧透] 开始AI分析弹幕，样本=${danmakuTexts.length}');
      final spoilerTexts =
          await DanmakuSpoilerFilterService.detectSpoilerDanmakuTexts(
        danmakuTexts: danmakuTexts,
        apiFormat: requestConfig.apiFormat,
        apiUrl: requestConfig.apiUrl,
        apiKey: requestConfig.apiKey,
        model: requestConfig.model,
        temperature: requestConfig.temperature,
        debugPrintResponse: _spoilerAiDebugPrintResponse,
      );

      if (_isDisposed) return;
      if (!_spoilerPreventionEnabled) return;
      if (_spoilerDanmakuRunningAnalysisHash != analysisHash) return;
      if (_currentVideoPath != targetVideoPath) return;

      final normalizedSet = <String>{};
      for (final text in spoilerTexts) {
        final normalized = _normalizeSpoilerMatchText(text);
        if (normalized.isNotEmpty) {
          normalizedSet.add(normalized);
        }
      }
      _spoilerDanmakuTexts = normalizedSet;
      debugPrint('[防剧透] AI分析完成，返回=${spoilerTexts.length} 命中=${normalizedSet.length}');
      if (_spoilerAiDebugPrintResponse && normalizedSet.isNotEmpty) {
        final previewList = normalizedSet.take(200).toList();
        debugPrint(
          '[防剧透] 命中文本预览(${previewList.length}/${normalizedSet.length}): ${previewList.join('||')}',
        );
      }
    } catch (e, st) {
      debugPrint('[防剧透] AI分析失败: $e');
      debugPrintStack(stackTrace: st);
      // 失败时保留现有命中集合，避免反复清空导致过滤闪烁/失效
      if (_isDisposed) return;
      if (!_spoilerPreventionEnabled) return;
      if (_spoilerDanmakuRunningAnalysisHash != analysisHash) return;
      if (_currentVideoPath != targetVideoPath) return;
    } finally {
      if (_isDisposed) return;

      final isCurrentRun = _spoilerDanmakuRunningAnalysisHash == analysisHash;
      if (isCurrentRun) {
        _spoilerDanmakuRunningAnalysisHash = null;
        _isSpoilerDanmakuAnalyzing = false;
      }

      if (isCurrentRun && _spoilerPreventionEnabled && _currentVideoPath == targetVideoPath) {
        _updateMergedDanmakuList();
        unawaited(_prebuildGPUDanmakuCharsetIfNeeded());
      }

      if (isCurrentRun) {
        _tryStartPendingSpoilerDanmakuAnalysis();
      }
    }
  }

  // GPU弹幕字符集预构建（如果需要）
  Future<void> _prebuildGPUDanmakuCharsetIfNeeded() async {
    try {
      // 检查当前是否使用GPU弹幕内核
      final currentKernel = await PlayerKernelManager.getCurrentDanmakuKernel();
      if (currentKernel != 'GPU渲染') {
        return; // 不是GPU内核，跳过
      }

      if (_danmakuList.isEmpty) {
        return; // 没有弹幕数据，跳过
      }

      debugPrint('VideoPlayerState: 检测到GPU弹幕内核，开始预构建字符集');
      _setStatus(PlayerStatus.recognizing, message: '正在优化GPU弹幕字符集...');

      // 使用过滤后的弹幕列表来预构建字符集，避免屏蔽词字符被包含
      final filteredDanmakuList = getFilteredDanmakuList();

      // 调用GPU弹幕覆盖层的预构建方法
      await GPUDanmakuOverlay.prebuildDanmakuCharset(filteredDanmakuList);

      debugPrint('VideoPlayerState: GPU弹幕字符集预构建完成');
    } catch (e) {
      debugPrint('VideoPlayerState: GPU弹幕字符集预构建失败: $e');
      // 不抛出异常，避免影响正常播放
    }
  }

  // 切换轨道启用状态
  void toggleDanmakuTrack(String trackId, bool enabled) {
    if (_danmakuTracks.containsKey(trackId)) {
      _danmakuTrackEnabled[trackId] = enabled;
      _updateMergedDanmakuList();
      notifyListeners();
      debugPrint('弹幕轨道 $trackId ${enabled ? "启用" : "禁用"}');
    }
  }

  // 删除弹幕轨道
  void removeDanmakuTrack(String trackId) {
    if (trackId == 'dandanplay') {
      debugPrint('不能删除弹弹play轨道');
      return;
    }

    if (_danmakuTracks.containsKey(trackId)) {
      _danmakuTracks.remove(trackId);
      _danmakuTrackEnabled.remove(trackId);
      _updateMergedDanmakuList();
      notifyListeners();
      debugPrint('删除弹幕轨道: $trackId');
    }
  }

  // 在设置视频时长时更新状态
  void setVideoDuration(Duration duration) {
    _videoDuration = duration;
    notifyListeners();
  }

  // 更新观看记录
  Future<void> _updateWatchHistory({bool forceRemoteSync = false}) async {
    if (_currentVideoPath == null) {
      return;
    }

    // 防止在播放器重置过程中更新历史记录
    if (_isResetting && !forceRemoteSync) {
      return;
    }

    if (_status == PlayerStatus.idle || _status == PlayerStatus.error) {
      return;
    }

    final bool isSharedRemoteStream =
        SharedRemoteHistoryHelper.isSharedRemoteStreamPath(_currentVideoPath!);

    try {
      // 使用 Provider 获取播放记录
      WatchHistoryItem? existingHistory;

      final watchHistoryProvider = _resolveWatchHistoryProvider();
      if (watchHistoryProvider != null) {
        existingHistory =
            await watchHistoryProvider.getHistoryItem(_currentVideoPath!);
      } else {
        // 不使用 Provider 更新状态，避免不必要的 UI 刷新
        existingHistory = await WatchHistoryDatabase.instance
            .getHistoryByFilePath(_currentVideoPath!);
      }

      if (existingHistory != null) {
        // 使用当前缩略图路径，如果没有则尝试捕获一个
        String? thumbnailPath = _currentThumbnailPath;
        if (thumbnailPath == null || thumbnailPath.isEmpty) {
          thumbnailPath = existingHistory.thumbnailPath;
          if ((thumbnailPath == null || thumbnailPath.isEmpty) &&
              player.state == PlaybackState.playing) {
            // 仅在播放时尝试捕获
            // 仅在没有缩略图时才尝试捕获
            try {
              thumbnailPath = await _captureVideoFrameWithoutPausing();
              if (thumbnailPath != null) {
                _currentThumbnailPath = thumbnailPath;
              }
            } catch (e) {
              //debugPrint('自动捕获缩略图失败: $e');
            }
          }
        }

        // 更新现有记录
        // 对于Jellyfin流媒体，优先使用当前实例变量中的友好名称（如果有的话）
        String finalAnimeName = existingHistory.animeName;
        String? finalEpisodeTitle = existingHistory.episodeTitle;

        // 检查是否是流媒体并且当前有更好的名称
        final bool isJellyfinStream =
            _currentVideoPath!.startsWith('jellyfin://');
        final bool isEmbyStream = _currentVideoPath!.startsWith('emby://');
        if (isJellyfinStream || isEmbyStream || isSharedRemoteStream) {
          final animeNameCandidate =
              SharedRemoteHistoryHelper.firstNonEmptyString([
            SharedRemoteHistoryHelper.normalizeHistoryName(_animeTitle),
            SharedRemoteHistoryHelper.normalizeHistoryName(
                _initialHistoryItem?.animeName),
            SharedRemoteHistoryHelper.normalizeHistoryName(finalAnimeName),
          ]);
          if (animeNameCandidate != null) {
            finalAnimeName = animeNameCandidate;
          }

          final episodeTitleCandidate =
              SharedRemoteHistoryHelper.firstNonEmptyString([
            _episodeTitle,
            _initialHistoryItem?.episodeTitle,
            finalEpisodeTitle,
          ]);
          if (episodeTitleCandidate != null) {
            finalEpisodeTitle = episodeTitleCandidate;
          }
          debugPrint(
              'VideoPlayerState: 使用流媒体/共享媒体友好名称更新记录: $finalAnimeName - $finalEpisodeTitle');
        }

        final updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: finalAnimeName,
          episodeTitle: finalEpisodeTitle,
          episodeId: _episodeId ??
              existingHistory.episodeId ??
              _initialHistoryItem?.episodeId, // 优先使用存储的 episodeId
          animeId: _animeId ??
              existingHistory.animeId ??
              _initialHistoryItem?.animeId, // 优先使用存储的 animeId
          watchProgress: _progress,
          lastPosition: _position.inMilliseconds,
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: thumbnailPath ?? _initialHistoryItem?.thumbnailPath,
          isFromScan: existingHistory.isFromScan,
        );

        // Jellyfin同步：如果是Jellyfin流媒体，同步播放进度（每秒同步一次）
        if (isJellyfinStream) {
          try {
            // 每秒同步一次，提供更及时的进度更新
            if (_position.inMilliseconds % 1000 < 100) {
              final itemId = _currentVideoPath!.replaceFirst('jellyfin://', '');
              final syncService = JellyfinPlaybackSyncService();
              await syncService.syncCurrentProgress(_position.inMilliseconds);
            }
          } catch (e) {
            debugPrint('Jellyfin播放进度同步失败: $e');
          }
        }

        // Emby同步：如果是Emby流媒体，同步播放进度（每秒同步一次）
        if (isEmbyStream) {
          try {
            // 每秒同步一次，提供更及时的进度更新
            if (_position.inMilliseconds % 1000 < 100) {
              final itemId = _currentVideoPath!.replaceFirst('emby://', '');
              final syncService = EmbyPlaybackSyncService();
              await syncService.syncCurrentProgress(_position.inMilliseconds);
            }
          } catch (e) {
            debugPrint('Emby播放进度同步失败: $e');
          }
        }

        // 通过 Provider 更新记录
        if (watchHistoryProvider != null) {
          await watchHistoryProvider.addOrUpdateHistory(updatedHistory);
        } else {
          // 直接使用数据库更新
          await WatchHistoryDatabase.instance
              .insertOrUpdateWatchHistory(updatedHistory);
        }
      } else {
        // 如果记录不存在，创建新记录
        final fileName = _currentVideoPath!.split('/').last;

        // 尝试从文件名中提取初始动画名称
        String initialAnimeName = fileName.replaceAll(
            RegExp(r'\.(mp4|mkv|avi|mov|flv|wmv)$', caseSensitive: false), '');
        initialAnimeName =
            initialAnimeName.replaceAll(RegExp(r'[_\.-]'), ' ').trim();

        if (initialAnimeName.isEmpty) {
          initialAnimeName = "未知动画"; // 确保非空
        }

        // 尝试获取缩略图
        String? thumbnailPath = _currentThumbnailPath;
        if (thumbnailPath == null && player.state == PlaybackState.playing) {
          // 仅在播放时尝试捕获
          try {
            thumbnailPath = await _captureVideoFrameWithoutPausing();
            if (thumbnailPath != null) {
              _currentThumbnailPath = thumbnailPath;
            }
          } catch (e) {
            //debugPrint('首次创建记录时捕获缩略图失败: $e');
          }
        }

        final newHistory = WatchHistoryItem(
          filePath: _currentVideoPath!,
          animeName: initialAnimeName,
          episodeId: _episodeId, // 使用从 historyItem 传入的 episodeId
          animeId: _animeId, // 使用从 historyItem 传入的 animeId
          watchProgress: _progress,
          lastPosition: _position.inMilliseconds,
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: thumbnailPath,
          isFromScan: false,
        );

        // 通过 Provider 添加记录
        if (watchHistoryProvider != null) {
          await watchHistoryProvider.addOrUpdateHistory(newHistory);
        } else {
          // 直接使用数据库添加
          await WatchHistoryDatabase.instance
              .insertOrUpdateWatchHistory(newHistory);
        }
      }

      if (isSharedRemoteStream) {
        try {
          await SharedRemotePlaybackSyncService.instance.syncProgress(
            videoUrl: _currentVideoPath!,
            positionMs: _position.inMilliseconds,
            durationMs: _duration.inMilliseconds,
            progress: _progress,
            force: forceRemoteSync,
          );
        } catch (e) {
          debugPrint('共享媒体播放进度同步失败: $e');
        }
      }
    } catch (e) {
      debugPrint('更新观看记录时出错: $e');
    }
  }

  // 添加一条新弹幕到当前列表
  void addDanmaku(Map<String, dynamic> danmaku) {
    if (danmaku.containsKey('time') && danmaku.containsKey('content')) {
      _danmakuList.add(danmaku);
      // 按时间重新排序
      _danmakuList.sort((a, b) {
        final timeA = (a['time'] as double?) ?? 0.0;
        final timeB = (b['time'] as double?) ?? 0.0;
        return timeA.compareTo(timeB);
      });
      notifyListeners();
      debugPrint('已添加新弹幕到列表: ${danmaku['content']}');
    }
  }

  // 将一条新弹幕添加到指定的轨道，如果轨道不存在则创建
  void addDanmakuToNewTrack(Map<String, dynamic> danmaku,
      {String trackName = '我的弹幕'}) {
    if (danmaku.containsKey('time') && danmaku.containsKey('content')) {
      final trackId = 'local_$trackName';

      // 检查轨道是否存在
      if (!_danmakuTracks.containsKey(trackId)) {
        // 如果轨道不存在，创建新轨道
        _danmakuTracks[trackId] = {
          'name': trackName,
          'source': 'local',
          'danmakuList': <Map<String, dynamic>>[],
          'count': 0,
          'loadTime': DateTime.now(),
        };
        _danmakuTrackEnabled[trackId] = true; // 默认启用新轨道
      }

      // 添加弹幕到轨道
      final trackDanmaku =
          _danmakuTracks[trackId]!['danmakuList'] as List<Map<String, dynamic>>;
      trackDanmaku.add(danmaku);
      _danmakuTracks[trackId]!['count'] = trackDanmaku.length;

      // 重新计算合并后的弹幕列表
      _updateMergedDanmakuList();

      debugPrint('已将新弹幕添加到轨道 "$trackName": ${danmaku['content']}');
    }
  }

  // 确保视频信息中包含格式化后的动画标题和集数标题
  static void _ensureVideoInfoTitles(Map<String, dynamic> videoInfo) {
    if (videoInfo['matches'] != null && videoInfo['matches'].isNotEmpty) {
      final match = videoInfo['matches'][0];
      // ... existing code ...
    }
  }

  // 显示发送弹幕对话框
  Future<void> showSendDanmakuDialog() async {
    debugPrint('[VideoPlayerState] 快捷键触发发送弹幕');

    if (_context == null) {
      debugPrint('[VideoPlayerState] Context为空，无法显示发送弹幕对话框');
      return;
    }

    // 先检查是否已经有弹幕对话框在显示
    final dialogManager = DanmakuDialogManager();

    // 如果已经在显示弹幕对话框，则关闭它，否则显示新对话框
    if (!dialogManager.handleSendDanmakuHotkey()) {
      final wasPlaying = player.state == PlaybackState.playing;

      // 对话框未显示，显示新对话框
      // 检查是否能发送弹幕
      if (episodeId == null) {
        // 使用BlurSnackBar显示提示
        BlurSnackBar.show(_context!, '无法获取剧集信息，无法发送弹幕');
        return;
      }

      if (wasPlaying) {
        try {
          await player.pauseDirectly();
        } catch (e) {
          debugPrint('[VideoPlayerState] 暂停失败: $e');
          try {
            player.state = PlaybackState.paused;
          } catch (fallbackError) {
            debugPrint('[VideoPlayerState] 暂停回退失败: $fallbackError');
          }
        }
        _setStatus(PlayerStatus.paused, message: '已暂停');
        _uiUpdateTicker?.stop();
      }

      try {
        await DanmakuDialogManager().showSendDanmakuDialog(
          context: _context!,
          episodeId: episodeId!,
          currentTime: position.inSeconds.toDouble(),
          onDanmakuSent: (danmaku) {
            addDanmakuToNewTrack(danmaku);
          },
          onDialogClosed: () {},
          wasPlaying: wasPlaying,
        );
      } finally {
        if (wasPlaying) {
          try {
            await player.playDirectly();
          } catch (e) {
            debugPrint('[VideoPlayerState] 恢复播放失败: $e');
            try {
              player.state = PlaybackState.playing;
            } catch (fallbackError) {
              debugPrint('[VideoPlayerState] 恢复播放回退失败: $fallbackError');
            }
          }
          _setStatus(PlayerStatus.playing, message: '开始播放');
          if (_uiUpdateTicker == null) {
            _startUiUpdateTimer();
          }
          if (!(_uiUpdateTicker?.isActive ?? false)) {
            _uiUpdateTicker!.start();
          }
        }
      }
    }
  }

  void _applyTimelineDanmakuTrackForCurrentVideo() {
    if (!_isTimelineDanmakuEnabled || _duration <= Duration.zero) {
      _danmakuTracks.remove('timeline');
      _danmakuTrackEnabled.remove('timeline');
      return;
    }

    final timelineDanmaku =
        TimelineDanmakuService.generateTimelineDanmaku(_duration);
    _danmakuTracks['timeline'] = {
      'name': timelineDanmaku['name'],
      'source': timelineDanmaku['source'],
      'danmakuList': timelineDanmaku['comments'],
      'count': timelineDanmaku['count'],
    };
    _danmakuTrackEnabled['timeline'] = true;
  }

  // 切换时间轴告知弹幕轨道
  Future<void> toggleTimelineDanmaku(bool enabled) async {
    _isTimelineDanmakuEnabled = enabled;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_timelineDanmakuEnabledKey, enabled);
    } catch (e) {
      debugPrint('保存时间轴告知开关失败: $e');
    }

    _applyTimelineDanmakuTrackForCurrentVideo();
    _updateMergedDanmakuList();
    notifyListeners();
  }
}
