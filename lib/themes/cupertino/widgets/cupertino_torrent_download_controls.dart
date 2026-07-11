part of torrent_download_page;

enum _CupertinoTorrentAction { play, toggle, folder, forget, delete }

extension _CupertinoTorrentDownloadControls on _TorrentDownloadPageState {
  Widget _buildCupertinoTorrentPage() {
    final background = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.systemGroupedBackground,
      context,
    );
    final separator = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.separator,
      context,
    );
    final visibleTasks = _visibleTasks;

    return ColoredBox(
      color: background,
      child: Column(
        children: [
          cupertino.SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 116, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '下载器',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  cupertino.CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(40),
                    onPressed: _toggleViewMode,
                    child: Icon(
                      _viewMode == UnifiedTorrentTaskViewMode.cards
                          ? cupertino.CupertinoIcons.list_bullet
                          : cupertino.CupertinoIcons.square_grid_2x2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildCupertinoTorrentToolbar(),
          ColoredBox(color: separator, child: const SizedBox(height: 0.5)),
          Expanded(
            child: _isLoading
                ? const Center(child: cupertino.CupertinoActivityIndicator())
                : visibleTasks.isEmpty
                    ? _buildCupertinoTorrentEmpty(_tasks.isNotEmpty)
                    : _buildCupertinoTaskList(visibleTasks),
          ),
        ],
      ),
    );
  }

  Widget _buildCupertinoTorrentToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        children: [
          cupertino.CupertinoSearchTextField(
            controller: _searchController,
            placeholder: '搜索下载任务',
            onChanged: _updateSearchQuery,
            onSuffixTap: () {
              _searchController.clear();
              _updateSearchQuery('');
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _cupertinoToolbarButton(
                icon: cupertino.CupertinoIcons.sort_down,
                label: unifiedTorrentTaskSortLabels[_sort] ?? '排序',
                onPressed: _showCupertinoSort,
              ),
              const SizedBox(width: 6),
              _cupertinoToolbarButton(
                icon: cupertino.CupertinoIcons.refresh,
                onPressed: _isBusy ? null : () => _refreshTasks(),
              ),
              const Spacer(),
              _cupertinoToolbarButton(
                icon: cupertino.CupertinoIcons.link,
                label: '添加',
                filled: true,
                onPressed: _isBusy ? null : _showAddMagnetDialog,
              ),
              const SizedBox(width: 6),
              _cupertinoToolbarButton(
                icon: cupertino.CupertinoIcons.doc,
                label: '种子',
                onPressed: _isBusy ? null : _pickTorrentFile,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cupertinoToolbarButton({
    required IconData icon,
    String? label,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    final foreground = filled ? cupertino.CupertinoColors.white : null;
    return cupertino.CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      minimumSize: Size.zero,
      color: filled ? AppAccentColors.current : null,
      borderRadius: BorderRadius.circular(8),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          if (label != null) ...[
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 13, color: foreground)),
          ],
        ],
      ),
    );
  }

  Future<void> _showCupertinoSort() async {
    final selected =
        await showCupertinoModalPopupWithBottomBar<UnifiedTorrentTaskSort>(
      context: context,
      builder: (sheetContext) => cupertino.CupertinoActionSheet(
        title: const Text('排序方式'),
        actions: [
          for (final entry in unifiedTorrentTaskSortLabels.entries)
            cupertino.CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(entry.key),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (entry.key == _sort) ...[
                    const Icon(cupertino.CupertinoIcons.check_mark, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(entry.value),
                ],
              ),
            ),
        ],
        cancelButton: cupertino.CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != null) _applySort(selected);
  }

  Widget _buildCupertinoTaskList(List<TorrentTask> tasks) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 84),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _buildCupertinoTaskCard(
          task,
          compact: _viewMode == UnifiedTorrentTaskViewMode.list,
        );
      },
    );
  }

  Widget _buildCupertinoTaskCard(
    TorrentTask task, {
    required bool compact,
  }) {
    final cardColor = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    final secondary = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );
    final errorColor = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.systemRed,
      context,
    );
    final summary = _scanSummaries[task.autoScanKey];
    final scanning = _autoScanningTaskKeys.contains(task.autoScanKey);
    final scanned = _autoScannedCompletedTaskKeys.contains(task.autoScanKey);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showCupertinoTaskActions(task),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    cupertino.CupertinoIcons.cloud_download,
                    color: AppAccentColors.current,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.name,
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          task.outputFolder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    task.displayState,
                    style: TextStyle(
                      fontSize: 12,
                      color: task.hasError ? errorColor : secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  cupertino.CupertinoButton(
                    padding: const EdgeInsets.only(left: 8),
                    minimumSize: Size.zero,
                    onPressed: () => _showCupertinoTaskActions(task),
                    child: const Icon(
                      cupertino.CupertinoIcons.ellipsis,
                      size: 19,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildCupertinoTaskProgress(task),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _cupertinoMetric(
                    '${(task.progress * 100).toStringAsFixed(1)}%',
                  ),
                  _cupertinoMetric(
                    '${_TorrentTaskCard.formatBytes(task.progressBytes)} / '
                    '${_TorrentTaskCard.formatBytes(task.totalBytes)}',
                  ),
                  if (!compact)
                    _cupertinoMetric(
                      '↓ ${_TorrentTaskCard.formatBytes(task.downloadSpeedBytesPerSecond)}/s',
                    ),
                  if (!compact)
                    _cupertinoMetric(
                      '↑ ${_TorrentTaskCard.formatBytes(task.uploadSpeedBytesPerSecond)}/s',
                    ),
                ],
              ),
              if (scanning || summary != null || scanned) ...[
                const SizedBox(height: 7),
                Text(
                  scanning
                      ? '正在加入媒体库...'
                      : (summary?.displayText.isNotEmpty == true
                          ? summary!.displayText
                          : '已加入媒体库'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              ],
              if (task.error?.isNotEmpty == true) ...[
                const SizedBox(height: 7),
                Text(
                  task.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: errorColor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCupertinoTaskProgress(TorrentTask task) {
    final background = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.systemGrey4,
      context,
    );
    final foreground = task.hasError
        ? cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.systemRed,
            context,
          )
        : AppAccentColors.current;
    return SizedBox(
      height: 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: ColoredBox(
          color: background,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: task.progress,
              child: ColoredBox(color: foreground),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cupertinoMetric(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: cupertino.CupertinoDynamicColor.resolve(
          cupertino.CupertinoColors.secondaryLabel,
          context,
        ),
      ),
    );
  }

  Future<void> _showCupertinoTaskActions(TorrentTask task) async {
    final action =
        await showCupertinoModalPopupWithBottomBar<_CupertinoTorrentAction>(
      context: context,
      builder: (sheetContext) => cupertino.CupertinoActionSheet(
        title: Text(task.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          if (task.finished)
            cupertino.CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.of(sheetContext).pop(_CupertinoTorrentAction.play),
              child: const Text('播放'),
            ),
          if (!task.finished)
            cupertino.CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext)
                  .pop(_CupertinoTorrentAction.toggle),
              child: Text(task.isPaused ? '继续下载' : '暂停下载'),
            ),
          cupertino.CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.of(sheetContext).pop(_CupertinoTorrentAction.folder),
            child: const Text('查看文件夹'),
          ),
          cupertino.CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.of(sheetContext).pop(_CupertinoTorrentAction.forget),
            child: const Text('移除任务'),
          ),
          cupertino.CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () =>
                Navigator.of(sheetContext).pop(_CupertinoTorrentAction.delete),
            child: const Text('删除任务和文件'),
          ),
        ],
        cancelButton: cupertino.CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _CupertinoTorrentAction.play:
        await _playTask(task);
        break;
      case _CupertinoTorrentAction.toggle:
        await _toggleTask(task);
        break;
      case _CupertinoTorrentAction.folder:
        await _openTaskFolder(task);
        break;
      case _CupertinoTorrentAction.forget:
        await _forgetTask(task);
        break;
      case _CupertinoTorrentAction.delete:
        await _deleteTask(task);
        break;
    }
  }

  Future<TorrentTaskFile?> _showCupertinoPlayableFiles(
    List<TorrentTaskFile> files,
  ) {
    return showCupertinoModalPopupWithBottomBar<TorrentTaskFile>(
      context: context,
      builder: (sheetContext) => cupertino.CupertinoActionSheet(
        title: const Text('选择要播放的文件'),
        actions: [
          for (final file in files)
            cupertino.CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(file),
              child: Column(
                children: [
                  Text(
                    file.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _TorrentTaskCard.formatBytes(file.length),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
        cancelButton: cupertino.CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Widget _buildCupertinoTorrentEmpty(bool filtered) {
    final secondary = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            cupertino.CupertinoIcons.cloud_download,
            size: 54,
            color: secondary,
          ),
          const SizedBox(height: 12),
          Text(filtered ? '没有匹配的下载任务' : '暂无下载任务'),
          const SizedBox(height: 5),
          Text(
            filtered ? '换一个关键词或清空搜索后再查看' : '添加 magnet 链接或种子文件开始下载',
            style: TextStyle(fontSize: 13, color: secondary),
          ),
        ],
      ),
    );
  }
}

extension _CupertinoAddMagnetControls on _AddMagnetDialogState {
  Widget _buildCupertinoAddMagnetSheet() {
    final background = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.systemGroupedBackground,
      context,
    );
    final secondary = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );
    final bottom = MediaQuery.viewPaddingOf(context).bottom + 24;

    return CupertinoBottomSheetContentLayout(
      backgroundColor: background,
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, topSpacing + 8, 16, bottom),
          sliver: SliverList.list(
            children: [
              Text('磁力链接', style: TextStyle(fontSize: 13, color: secondary)),
              const SizedBox(height: 6),
              cupertino.CupertinoTextField(
                controller: _magnetController,
                placeholder: 'magnet:?xt=urn:btih:...',
                minLines: 2,
                maxLines: 4,
                onChanged: (_) {
                  if (_preview == null && _error == null) return;
                  _updateCupertinoForm(() {
                    _preview = null;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              Text('下载目录', style: TextStyle(fontSize: 13, color: secondary)),
              const SizedBox(height: 6),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: cupertino.CupertinoDynamicColor.resolve(
                    cupertino.CupertinoColors.secondarySystemGroupedBackground,
                    context,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _downloadDirectory.isEmpty
                              ? '尚未选择目录'
                              : _downloadDirectory,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      cupertino.CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        onPressed: _chooseDirectory,
                        child: const Text('选择'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_recentDirectories.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _recentDirectories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final directory = _recentDirectories[index];
                      return cupertino.CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        color: cupertino.CupertinoDynamicColor.resolve(
                          cupertino.CupertinoColors.systemGrey5,
                          context,
                        ),
                        onPressed: () => _selectDirectory(directory),
                        child: Text(
                          p.basename(directory),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(child: Text('为任务创建独立文件夹')),
                  cupertino.CupertinoSwitch(
                    value: _createFolderForTask,
                    onChanged: (value) {
                      _updateCupertinoForm(() {
                        _createFolderForTask = value;
                        _preview = null;
                      });
                    },
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: cupertino.CupertinoColors.systemRed,
                    fontSize: 13,
                  ),
                ),
              ],
              if (_preview != null) ...[
                const SizedBox(height: 16),
                _buildCupertinoPreview(_preview!),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: cupertino.CupertinoButton(
                      color: cupertino.CupertinoDynamicColor.resolve(
                        cupertino.CupertinoColors.systemGrey5,
                        context,
                      ),
                      onPressed: _isPreviewing ? null : _previewMagnet,
                      child: _isPreviewing
                          ? const cupertino.CupertinoActivityIndicator()
                          : Text(_preview == null ? '预览' : '重新预览'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: cupertino.CupertinoButton.filled(
                      onPressed:
                          _preview == null || _isPreviewing ? null : _confirm,
                      child: const Text('添加任务'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCupertinoPreview(TorrentMagnetPreview preview) {
    final secondary = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );
    final card = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    return DecoratedBox(
      decoration:
          BoxDecoration(color: card, borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preview.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              '${preview.files.length} 个文件 · '
              '${_TorrentTaskCard.formatBytes(preview.totalSize)}',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
            if (preview.files.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final file in preview.files.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      const Icon(cupertino.CupertinoIcons.doc, size: 15),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          file.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _TorrentTaskCard.formatBytes(file.length),
                        style: TextStyle(fontSize: 11, color: secondary),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
