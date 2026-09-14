part of video_player_state;

/// 内联分析的弹幕条数上限。
///
/// 实测 2 万条单趟扫描约 30ms，内联完全可以接受；但热门番单集可能到数万条，
/// 那时转后台 isolate（见 [_detectIntroInBackground]），不去占用 UI isolate
/// 的一帧预算——本功能是锦上添花，绝不参与任何卡顿。
const int _introSkipInlineLimit = 20000;

/// 后台 isolate 的分析入参（跨 isolate 只能传可序列化的值）。
///
/// 元素类型放宽为任意 Map，与内联路径（`raw is! Map` 才跳过）同一口径——
/// DanmakuTextEntry.fromMap 只按键取值，不要求 Map<String, dynamic>。
class _IntroSkipDetectRequest {
  final List<Map<dynamic, dynamic>> comments;
  final double durationSeconds;

  const _IntroSkipDetectRequest(this.comments, this.durationSeconds);
}

/// 日志用的中文标签。
String _kindLabel(SkipSegmentKind kind) =>
    kind == SkipSegmentKind.opening ? '片头' : '片尾';

/// [compute] 的回调，必须是顶层函数。这里把异常吞掉——isolate 侧抛出会让
/// Future 以错误结束，走不到 UI 侧的 try/catch。
SkipSegment? _detectIntroInBackground(_IntroSkipDetectRequest request) {
  final entries = <DanmakuTextEntry>[];
  for (final raw in request.comments) {
    final entry = DanmakuTextEntry.fromMap(raw);
    if (entry.isValid) entries.add(entry);
  }
  if (entries.isEmpty) return null;
  return DanmakuIntroDetector.detect(
    entries,
    durationSeconds:
        request.durationSeconds > 0 ? request.durationSeconds : null,
  );
}

/// VideoPlayerState 的「跳过片头 / 片尾」能力。
///
/// 数据源目前有两路：
/// - 弹幕报点推导（[DanmakuIntroDetector]），只给片头；
/// - AniSkip 社区标注（[AniSkipService]），片头 + 片尾都给。
///
/// 区间按 [SkipSegmentKind] 分槽存放，槽内按 [SkipSegmentSourceRank] 合并——这样
/// 两路信号可以同时生效（弹幕给片头、AniSkip 给片尾），不会互相覆盖。
extension VideoPlayerStateSkipSegments on VideoPlayerState {
  /// 跳过片头功能总开关。
  bool get introSkipEnabled => _introSkipEnabled;

  /// 当前播放位置是否落在某个可跳过区间内，返回那个区间（没有则 null）。
  ///
  /// 用单个 getter 而不是「片头」「片尾」两个：UI 只要问「现在该不该显示跳过
  /// 按钮」，至于是跳片头还是跳片尾由 [skipCurrentSegment] 按位置自行判断。
  SkipSegment? get activeSkipSegment {
    if (!_introSkipEnabled) return null;
    final seconds = position.inMilliseconds / 1000.0;
    for (final segment in _skipSegments.values) {
      if (segment.containsSeconds(seconds)) return segment;
    }
    return null;
  }

  /// 当前是否处于某个可跳过区间内（决定跳过按钮是否出现）。
  ///
  /// 命名不写死「片头」：片头、片尾共用这一个按钮，本 getter 对两者都返回 true，
  /// 具体是哪一种由 [activeSkipSegment] 的 `kind` 决定。
  bool get hasActiveSkipSegment => activeSkipSegment != null;

  /// 跳到当前所在区间的结束点。
  ///
  /// 目标位置会钳制在片长内——越界 seek 会让内核报 EOF 并可能引发错误风暴
  /// （OcPlayer 在 `performSkip` 上踩过同一个坑）。片尾区间天然靠近片长边界，
  /// 这个钳制对 ED 尤其必要。
  Future<void> skipCurrentSegment() async {
    final segment = activeSkipSegment;
    if (segment == null) return;

    var target = segment.end;
    if (duration > Duration.zero) {
      final limit = duration - const Duration(milliseconds: 500);
      if (target > limit) {
        target = limit.isNegative ? Duration.zero : limit;
      }
    }
    debugPrint('[跳过片头] 跳转到 ${target.inMilliseconds / 1000}s（区间 $segment）');
    seekTo(target);
  }

  /// 从已加载的弹幕列表推导片头区间。
  ///
  /// 纯本地计算，每集只做一次。小列表内联（万条量级约十余毫秒），
  /// 超过 [_introSkipInlineLimit] 转后台 isolate 并在结果回来时校验播放世代。
  /// 任何异常都静默降级——推导失败只是没有跳过按钮，不该影响播放。
  void detectIntroSkipFromDanmaku(List<dynamic>? danmakuList) {
    if (!_introSkipEnabled) return;
    if (danmakuList == null || danmakuList.isEmpty) return;

    final durationSeconds = duration.inMilliseconds / 1000.0;
    final generation = _playbackGeneration;
    final videoPath = _currentVideoPath;

    if (danmakuList.length <= _introSkipInlineLimit) {
      final entries = <DanmakuTextEntry>[];
      for (final raw in danmakuList) {
        if (raw is! Map) continue;
        final entry = DanmakuTextEntry.fromMap(raw);
        if (entry.isValid) entries.add(entry);
      }
      if (entries.isEmpty) return;
      try {
        _applyDetectedSegment(
          DanmakuIntroDetector.detect(
            entries,
            durationSeconds: durationSeconds > 0 ? durationSeconds : null,
          ),
          generation,
          videoPath,
        );
      } catch (e, stack) {
        debugPrint('[跳过片头] 弹幕分析失败，已降级: $e');
        debugPrint('$stack');
      }
      return;
    }

    // 与内联路径同一口径：任意 Map 都收（见 _IntroSkipDetectRequest 注释），
    // 否则大数据集反而比小数据集丢更多样本。
    final comments = <Map<dynamic, dynamic>>[];
    for (final raw in danmakuList) {
      if (raw is Map) comments.add(raw);
    }
    if (comments.isEmpty) return;
    compute(_detectIntroInBackground,
            _IntroSkipDetectRequest(comments, durationSeconds))
        .then((segment) {
      _applyDetectedSegment(segment, generation, videoPath);
    }).catchError((Object error, StackTrace stack) {
      debugPrint('[跳过片头] 后台弹幕分析失败，已降级: $error');
      debugPrint('$stack');
    });
  }

  /// 落库一份分析结果：播放已经切走（换集 / 换源 / 销毁）则丢弃过期结果。
  void _applyDetectedSegment(
    SkipSegment? segment,
    int generation,
    String? videoPath,
  ) {
    if (segment == null) return;
    if (_isDisposed ||
        _playbackGeneration != generation ||
        _currentVideoPath != videoPath) {
      debugPrint('[跳过片头] 播放已切换，丢弃过期分析结果');
      return;
    }
    applySkipSegment(segment);
  }

  /// 合并一路区间信号。
  ///
  /// ## 优先级（高 → 低，数字见 [SkipSegmentSourceRank]）
  ///
  /// | 顺序 | 来源 | 说明 |
  /// |---|---|---|
  /// | 1 | `manual` (100) | 用户手动标记，永远最准 |
  /// | 2 | `mediaServer` (40) | Jellyfin / Emby 服务端智能识别 |
  /// | 3 | **`aniskip` (30)** | **AniSkip 社区标注，人工校准的精确区间** |
  /// | 4 | **`danmaku` (20)** | **弹幕报点推导，本地估算有误差** |
  /// | 5 | `chapterHeuristic` (10) | 章节名 / 位置启发式 |
  ///
  /// 策略：**AniSkip 有数据就用 AniSkip 的，没有才用弹幕分析的**。
  /// 两路互相独立，谁先到谁先写槽位；后到的若优先级更高就覆盖，更低就忽略。
  ///
  /// 时序上**两种顺序都出现过**（实测）：弹幕是纯本地计算但要等弹幕加载完，
  /// AniSkip 要走网络但不依赖弹幕。谁先到不影响正确性——rank 比较是双向的，
  /// 先到低优先级就后被覆盖，先到高优先级就挡住后来的。
  ///
  /// 只和**同 kind 的槽位**比较：片尾信号不会被片头信号挤掉（反之亦然）。
  /// 因此「AniSkip 只给了 ED、没给 OP」时，OP 仍保留弹幕推导的结果。
  void applySkipSegment(SkipSegment? candidate) {
    if (candidate == null) return;
    // 开关可能在请求发出后、结果回来前被关掉：拒绝在途结果回填，
    // 否则再打开关时会瞬间显示上一轮残留的区间。
    if (!_introSkipEnabled) return;
    final existing = _skipSegments[candidate.kind];
    final merged = mergeSkipSegmentSlot(existing, candidate);
    if (!merged.accepted) {
      debugPrint('[跳过片头] 采纳 ${candidate.source.name}（优先级 '
          '${candidate.source.rank}）失败：槽位 ${existing!.kind.name} 已有更可信的 '
          '${existing.source.name}（优先级 ${existing.source.rank}），保留原值');
      return;
    }

    if (existing != null && existing.source != candidate.source) {
      // 覆盖是预期行为（弹幕先到 → AniSkip 后到改写），打出来方便事后核对
      debugPrint('[跳过片头] ${candidate.source.name}（优先级 '
          '${candidate.source.rank}）覆盖 ${existing.source.name}（优先级 '
          '${existing.source.rank}）的${_kindLabel(candidate.kind)}：'
          '${existing.startSeconds.toStringAsFixed(1)}-'
          '${existing.endSeconds.toStringAsFixed(1)}s → '
          '${candidate.startSeconds.toStringAsFixed(1)}-'
          '${candidate.endSeconds.toStringAsFixed(1)}s');
    } else {
      debugPrint('[跳过片头] 命中区间 $candidate');
    }

    _skipSegments[candidate.kind] = candidate;
    _notifyListeners();
  }

  /// 清空全部可跳过区间（切集 / 换源 / 关闭播放器时调用）。
  ///
  /// 清的是**所有**槽位（片头 + 片尾），所以叫复数。
  void clearSkipSegments() {
    if (_skipSegments.isEmpty) return;
    _skipSegments.clear();
    _notifyListeners();
  }

  /// 设置跳过片头总开关（持久化）。
  Future<void> setIntroSkipEnabled(bool enabled) async {
    if (_introSkipEnabled == enabled) return;
    _introSkipEnabled = enabled;
    if (!enabled) {
      clearSkipSegments();
    }
    _notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_introSkipEnabledKey, enabled);
    } catch (e) {
      debugPrint('[跳过片头] 开关持久化失败: $e');
    }
  }

  /// 加载跳过片头总开关。
  Future<void> loadIntroSkipEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_introSkipEnabledKey) ?? true;
      if (_introSkipEnabled != enabled) {
        _introSkipEnabled = enabled;
        _notifyListeners();
      }
    } catch (e) {
      debugPrint('[跳过片头] 开关读取失败，使用默认值: $e');
      _introSkipEnabled = true;
    }
  }

  // ---------------------------------------------------------------------------
  // AniSkip（社区标注库）数据源
  //
  // 与弹幕报点相比，AniSkip 是人工标注的精确区间，可信度更高（rank 30 > 20），
  // 因此结果是「喂给 applySkipSegment 参与合并」而不是直接覆盖——如果用户
  // 手动标过（rank 100）或媒体服务器给了 MediaSegments（rank 40），仍然以后者为准。
  //
  // 链路（每一跳都可能断，断了静默返回，只留弹幕那一路）：
  //   animeId →(弹弹play 详情) bangumiId
  //           →(Bangumi /v0/subjects) 日文原名 + 放送年份
  //           →(AniList GraphQL 搜索) idMal = MAL ID
  //           →(AniSkip) 片头 / 片尾区间
  //
  // 为什么不直接用 Bangumi 的 infobox 拿 MAL：实测动画条目的 infobox 里没有
  // 这个字段（详见 SkipIdResolver 的类注释）。必须借 AniList 转一道。
  // ---------------------------------------------------------------------------

  /// 本次播放解析到的 MAL ID（null 表示尚未解析或解析失败）。
  ///
  /// 注意：字段本体声明在 `video_player_state.dart`（extension 不能声明实例字段）。

  /// 从弹弹play 剧集详情补齐 bangumiId。
  ///
  /// 这条链路已有先例（首页缩略图取高清封面走的就是同一招），所以直接复用
  /// [DandanplayService.getBangumiDetails]（内部有内存缓存 + 并发合并）。
  Future<void> ensureBangumiId() async {
    if (_bangumiId != null && _bangumiId! > 0) return;
    final animeId = _animeId;
    if (animeId == null || animeId <= 0) return;

    try {
      final details = await DandanplayService.getBangumiDetails(animeId);
      final bangumiId = SkipIdResolver.extractBangumiIdFromDetails(details);
      if (bangumiId == null) {
        debugPrint('[跳过片头] 弹弹play 详情里没有 Bangumi 外链（animeId=$animeId）');
        return;
      }
      _bangumiId = bangumiId;
      debugPrint('[跳过片头] 解析到 Bangumi 条目 $bangumiId（animeId=$animeId）');
    } catch (e) {
      debugPrint('[跳过片头] 获取弹弹play 详情失败，跳过 AniSkip: $e');
    }
  }

  /// 尝试从 AniSkip 拉取本集的跳过区间并合并进状态。
  ///
  /// 调用时机：弹幕加载完成之后（此时 [duration] 通常已就绪，能传 `episodeLength`
  /// 让服务端过滤掉片长不符的标注）。整个过程异步、失败静默。
  Future<void> fetchAniSkipSegments() async {
    debugPrint('[跳过片头] AniSkip 开始（开关=$_introSkipEnabled，'
        'animeId=$_animeId，episodeId=$_episodeId）');
    if (!_introSkipEnabled) return;

    // 记录调用时的播放世代，结果回来时校验，防止切集后把旧集的区间安到新集上。
    final generation = _playbackGeneration;
    final videoPath = _currentVideoPath;

    try {
      final malId = await _resolveMalId();
      if (malId == null || malId <= 0) return;

      final episodeNumber = await _resolveEpisodeNumber();
      if (episodeNumber == null || episodeNumber <= 0) {
        debugPrint('[跳过片头] 无法确定集数，跳过 AniSkip');
        return;
      }

      // 网络往返可能在用户切集期间完成，先校验一次再发 AniSkip 请求。
      if (!_stillOnSamePlayback(generation, videoPath)) return;

      // 没拿到时长时不传 episodeLength：AniSkip 要求该参数必须是有效数字，
      // 传 0 会被拒（400）。缺了它服务端仍会返回，只是可能给出别的片长版本的
      // 区间——所以这里优先等 duration 就绪（本方法在弹幕加载完成后调用，
      // 通常已经就绪）。
      final durationSeconds = duration.inMilliseconds / 1000.0;
      final segments = await AniSkipService.instance.fetchSkipTimes(
        malId: malId,
        episodeNumber: episodeNumber,
        episodeLengthSeconds: durationSeconds > 0 ? durationSeconds : null,
      );
      if (segments.isEmpty) {
        // 注解：这是策略的后半段——AniSkip 没数据就保持弹幕推导的结果，
        // 不做任何覆盖（冷门番、剧场版、AniSkip 未收录都会走到这里）。
        final kept = _skipSegments[SkipSegmentKind.opening];
        debugPrint(kept == null
            ? '[跳过片头] AniSkip 无数据，且无弹幕推导结果 → 本集不显示跳过按钮'
            : '[跳过片头] AniSkip 无数据，保留 ${kept.source.name} 的片头区间 '
                '${kept.startSeconds.toStringAsFixed(1)}-'
                '${kept.endSeconds.toStringAsFixed(1)}s');
        return;
      }

      // 二次校验：网络往返期间用户可能已经切集 / 换源 / 关播放器。
      if (!_stillOnSamePlayback(generation, videoPath)) {
        debugPrint('[跳过片头] 播放已切换，丢弃过期的 AniSkip 结果');
        return;
      }

      for (final segment in segments) {
        applySkipSegment(segment);
      }
    } catch (e, stack) {
      debugPrint('[跳过片头] AniSkip 流程失败，已降级: $e');
      debugPrint('$stack');
    }
  }

  /// 解析本番的 MAL ID，一集只尝试一次。
  ///
  /// 先取 Bangumi 条目拿到**日文原名 + 放送年份**（这是 AniList 能认的输入，
  /// 中文译名它不认识），交给 [SkipIdResolver] 搜 AniList 换 `idMal`。
  /// Bangumi 这一跳失败时退化为直接用本地标题搜——命中率低些，但聊胜于无。
  Future<int?> _resolveMalId() async {
    final cached = _animeMalId;
    if (cached != null && cached > 0) return cached;
    if (_malIdResolved) return null;

    try {
      await ensureBangumiId();

      String? bangumiOriginalTitle;
      String? bangumiCnTitle;
      int? premiereYear;

      final bangumiId = _bangumiId;
      if (bangumiId != null && bangumiId > 0) {
        final subject = await _fetchBangumiSubject(bangumiId);
        if (subject != null) {
          bangumiOriginalTitle = subject['name']?.toString();
          bangumiCnTitle = subject['name_cn']?.toString();
          premiereYear = _yearFromDate(subject['date']?.toString());
        }
      }

      // 候选顺序：Bangumi 原名（AniList 最认）> 本地番剧名 > Bangumi 中文名。
      final malId = await SkipIdResolver.resolveMalIdFromTitles(
        [
          bangumiOriginalTitle,
          _animeTitle,
          bangumiCnTitle,
        ],
        premiereYear: premiereYear,
      );

      _malIdResolved = true;
      if (malId != null && malId > 0) {
        _animeMalId = malId;
        debugPrint('[跳过片头] 本番 MAL ID = $malId');
        return malId;
      }
      debugPrint('[跳过片头] 未能解析 MAL ID，AniSkip 这一路放弃');
      return null;
    } catch (e) {
      _malIdResolved = true;
      debugPrint('[跳过片头] 解析 MAL ID 异常，已降级: $e');
      return null;
    }
  }

  /// 取 Bangumi 条目详情（公开接口，无需令牌）。
  Future<Map<String, dynamic>?> _fetchBangumiSubject(int subjectId) async {
    try {
      final baseUrl = await NetworkSettings.getBangumiServer();
      final uri = WebRemoteAccessService.proxyUri(
        Uri.parse('$baseUrl/v0/subjects/$subjectId'),
      );
      final response = await ddp_http.get(uri, headers: {
        'User-Agent': 'NipaPlay/1.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) {
        debugPrint('[跳过片头] Bangumi 条目 $subjectId HTTP ${response.statusCode}');
        return null;
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('[跳过片头] 取 Bangumi 条目 $subjectId 失败: $e');
      return null;
    }
  }

  /// 从 `2026-07-06` 这样的日期串里取年份。
  static int? _yearFromDate(String? date) {
    if (date == null || date.isEmpty) return null;
    final match = RegExp(r'^(\d{4})').firstMatch(date);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// 结果回填前的世代守卫。
  bool _stillOnSamePlayback(int generation, String? videoPath) {
    if (_isDisposed) return false;
    if (_playbackGeneration != generation) return false;
    if (_currentVideoPath != videoPath) return false;
    return true;
  }

  /// 确定当前集数。
  ///
  /// 优先级：弹弹play 详情里按 `episodeId` 匹配到的 `episodeNumber`（最准，
  /// 是服务端给的）> 已缓存字段 > 从剧集标题 / 视频文件名里解析。
  Future<int?> _resolveEpisodeNumber() async {
    final known = _episodeNumber;
    if (known != null && known > 0) return known;

    final fromService = await _episodeNumberFromDandanplay();
    if (fromService != null && fromService > 0) {
      _episodeNumber = fromService;
      debugPrint('[跳过片头] 从弹弹play 详情解析到集数 $fromService');
      return fromService;
    }

    final fromName = EpisodeNumberExtractor.extractFromAny([
      _episodeTitle,
      _currentVideoPath,
      _animeTitle,
    ]);
    if (fromName != null && fromName > 0) {
      _episodeNumber = fromName;
      debugPrint('[跳过片头] 从标题/文件名解析到集数 $fromName');
      return fromName;
    }

    // 走到这里说明三路都没解析出集数。把候选原样打出来——排查时最常遇到的
    // 就是「文件名里其实有集数，但格式没被任何一条正则覆盖」，看到原文才好判断。
    debugPrint('[跳过片头] 无法确定集数，已尝试的候选: '
        'episodeTitle=$_episodeTitle, videoPath=$_currentVideoPath, '
        'animeTitle=$_animeTitle');
    return null;
  }

  /// 在弹弹play 的剧集列表里按 `episodeId` 反查 `episodeNumber`。
  ///
  /// 详情接口在有缓存时是同步返回的（DandanplayService 内部做了内存缓存），
  /// 所以这一跳通常不产生额外网络开销。
  Future<int?> _episodeNumberFromDandanplay() async {
    final animeId = _animeId;
    final episodeId = _episodeId;
    if (animeId == null || animeId <= 0) return null;

    try {
      final details = await DandanplayService.getBangumiDetails(animeId);
      if (details['success'] != true) return null;
      final bangumi = details['bangumi'];
      if (bangumi is! Map) return null;
      final episodes = bangumi['episodes'];
      if (episodes is! List) return null;

      // 有 episodeId 就精确匹配；没有则退化为「列表里只有一个」时直接取。
      if (episodeId != null && episodeId > 0) {
        for (final raw in episodes) {
          if (raw is! Map) continue;
          if (raw['episodeId']?.toString() != episodeId.toString()) continue;
          final parsed = int.tryParse(raw['episodeNumber']?.toString() ?? '');
          if (parsed != null && parsed > 0) return parsed;
        }
        return null;
      }

      if (episodes.length == 1) {
        final only = episodes.first;
        if (only is Map) {
          return int.tryParse(only['episodeNumber']?.toString() ?? '');
        }
      }
      return null;
    } catch (e) {
      debugPrint('[跳过片头] 从弹弹play 反查集数失败: $e');
      return null;
    }
  }
}
