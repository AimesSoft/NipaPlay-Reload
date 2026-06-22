part of video_player_state;

/// VideoPlayerState 章节能力 mixin。
///
/// 数据来源：libmpv `chapter-list` 属性（MKV 容器自带章节），由
/// [MediaKitPlayerAdapter._refreshChapters] 解析并写入 `player.mediaInfo.chapters`。
/// 参考 REFERENCE/mpv/player/playloop.c:607 get_current_chapter 计算当前章节。
extension VideoPlayerStateChapters on VideoPlayerState {
  /// 当前媒体的章节列表（按 startMs 升序）。无章节或非 libmpv 内核时为空列表。
  List<PlayerChapter> get chapters => player.mediaInfo.chapters ?? const [];

  /// 当前播放所在的章节索引。
  /// -1 表示无章节或位于首个章节之前；-2 保留语义（参考 mpv get_current_chapter 返回 -2）。
  /// 当前实现：-1=无章节/首章前，>=0=章节索引。
  int get currentChapter => _currentChapterIndex;

  /// 跳转到指定索引的章节（使用 mpv 原生 `chapter` 属性，keyframe 对齐）。
  /// 参考 REFERENCE/mpv/player/command.c:996 (queue_seek MPSEEK_CHAPTER)。
  Future<void> seekToChapter(int index) async {
    final list = chapters;
    debugPrint('[CHAPTER-DIAG] seekToChapter($index) 调用，章节数=${list.length}');
    if (list.isEmpty || index < 0 || index >= list.length) {
      debugPrint('[CHAPTER-DIAG] seekToChapter: 跳过（空列表或越界 index=$index, len=${list.length}）');
      return;
    }
    final chapter = list[index];
    debugPrint('[CHAPTER-DIAG] seekToChapter: 跳转到章节 #$index "${chapter.title}" @ ${chapter.startMs}ms');
    // 两段式 seek 设计（PR review 注意点2 优化）：
    // 1. seekTo(章节起点) 同步走 player.seek（精确 seek，毫秒级）+ 立即更新 UI 状态
    //    （_position/_progress/_playbackTimeMs/_isSeeking/平滑时钟锚点），保证"进度条立即动"。
    // 2. setChapter(index) 走 mpv setProperty("chapter") → MPSEEK_CHAPTER（keyframe 对齐，
    //    参考 command.c:996）。mpv chapter seek 会定位到最近 keyframe（可能与精确 seek
    //    位置差 <1 个 keyframe 间隔，通常 <500ms）。
    // 顺序：seekTo 先同步 UI（同步执行），setChapter 用 scheduleMicrotask 延后到下一微任务，
    // 确保 UI 状态先于 mpv chapter seek 生效，避免两段式 seek 视觉闪烁（进度条先到精确位置，
    // mpv keyframe 校正差异在视觉不可察觉范围内）。
    seekTo(Duration(milliseconds: chapter.startMs));
    // 立即更新本地索引，UI 即时反馈（实际 position 由导航循环校正）
    _currentChapterIndex = index;
    // 延后 setChapter：让 seekTo 的 UI 同步先渲染，再触发 mpv keyframe 对齐 seek
    scheduleMicrotask(() async {
      await player.setChapter(index);
    });
  }

  /// 根据 position（毫秒）计算并更新当前章节索引。
  /// 算法参考 REFERENCE/mpv/player/playloop.c:607 get_current_chapter：
  /// 遍历 chapters 找到首个 startMs > position 的，取其前一个索引；
  /// 全部 <= position 则取最后一个；空列表返回 -1。
  void _updateCurrentChapterFromPosition(int positionMs) {
    final list = chapters;
    if (list.isEmpty) {
      if (_currentChapterIndex != -1) {
        _currentChapterIndex = -1;
      }
      return;
    }
    int newIndex = -1;
    for (int i = 0; i < list.length; i++) {
      if (list[i].startMs > positionMs) {
        break;
      }
      newIndex = i;
    }
    // 首章节起始 > 0 且 position < 首章节起点 → newIndex 保持 -1（位于首章前）
    if (newIndex != _currentChapterIndex) {
      _currentChapterIndex = newIndex;
    }
  }

  /// 当前章节标题（用于 UI 显示）。无章节时返回 null。
  String? get currentChapterTitle {
    final idx = _currentChapterIndex;
    final list = chapters;
    if (idx < 0 || idx >= list.length) return null;
    final title = list[idx].title;
    return title.isEmpty ? null : title;
  }
}
