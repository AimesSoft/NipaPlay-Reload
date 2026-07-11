part of webdav_browser_page;

extension _CupertinoWebDavBrowserControls on _WebDAVBrowserPageState {
  Widget _buildCupertinoWebDavPage() {
    final background = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.systemGroupedBackground,
      context,
    );
    final secondary = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );

    if (_isInitializing) {
      return ColoredBox(
        color: background,
        child: const Center(child: AdaptiveMediaActivityIndicator()),
      );
    }

    if (_currentConnection == null) {
      return ColoredBox(
        color: background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(cupertino.CupertinoIcons.cloud,
                    size: 52, color: secondary),
                const SizedBox(height: 14),
                const Text(
                  '没有配置 WebDAV 服务器',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  '添加服务器后即可浏览、搜索和播放远程视频',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondary, fontSize: 13),
                ),
                const SizedBox(height: 18),
                cupertino.CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(8),
                  onPressed: _showAddServerDialog,
                  child: const Text('添加服务器'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_canNavigateBack,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _canNavigateBack) _navigateBack();
      },
      child: ColoredBox(
        color: background,
        child: Column(
          children: [
            _buildCupertinoWebDavHeader(),
            if (context.watch<WebDAVQuickAccessProvider>().showPathBreadcrumb)
              _buildCupertinoWebDavBreadcrumb(),
            Expanded(
              child: _isSearchMode
                  ? _buildCupertinoWebDavSearchResults()
                  : _buildCupertinoWebDavDirectory(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCupertinoWebDavHeader() {
    final secondary = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );
    final searchEnabled =
        context.watch<WebDAVQuickAccessProvider>().enableSearch;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 112, 6),
        child: Column(
          children: [
            Row(
              children: [
                if (_canNavigateBack)
                  cupertino.CupertinoButton(
                    padding: const EdgeInsets.all(7),
                    minimumSize: const Size.square(36),
                    onPressed: _navigateBack,
                    child: const Icon(cupertino.CupertinoIcons.back, size: 20),
                  ),
                Expanded(
                  child: cupertino.CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    alignment: Alignment.centerLeft,
                    onPressed: _showServerSelector,
                    child: Row(
                      children: [
                        const Icon(cupertino.CupertinoIcons.cloud, size: 20),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _currentConnection!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          cupertino.CupertinoIcons.chevron_down,
                          size: 15,
                          color: secondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (searchEnabled)
                  cupertino.CupertinoButton(
                    padding: const EdgeInsets.all(7),
                    minimumSize: const Size.square(36),
                    onPressed: _toggleCupertinoWebDavSearch,
                    child: Icon(
                      _isSearchMode
                          ? cupertino.CupertinoIcons.clear
                          : cupertino.CupertinoIcons.search,
                      size: 20,
                    ),
                  ),
                cupertino.CupertinoButton(
                  padding: const EdgeInsets.all(7),
                  minimumSize: const Size.square(36),
                  onPressed: _showCupertinoServerActions,
                  child: const Icon(
                    cupertino.CupertinoIcons.ellipsis_circle,
                    size: 21,
                  ),
                ),
              ],
            ),
            if (_isSearchMode) ...[
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: cupertino.CupertinoSearchTextField(
                      controller: _searchController,
                      placeholder: '搜索文件…',
                      onChanged: (value) => setState(() {
                        _searchKeyword = value;
                      }),
                      onSubmitted: (_) {
                        if (_searchController.text.trim().isNotEmpty) {
                          _startSearch();
                        }
                      },
                      onSuffixTap: () => setState(() {
                        _searchController.clear();
                        _searchKeyword = '';
                        _searchResults = [];
                      }),
                    ),
                  ),
                  const SizedBox(width: 7),
                  cupertino.CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    onPressed:
                        _isSearching || _searchController.text.trim().isEmpty
                            ? null
                            : _startSearch,
                    child: Text(_isSearching ? '搜索中' : '搜索'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _toggleCupertinoWebDavSearch() {
    setState(() {
      _isSearchMode = !_isSearchMode;
      if (!_isSearchMode) {
        _stopSearchRequested = true;
        _searchResults = [];
        _searchController.clear();
        _searchKeyword = '';
      }
    });
  }

  Widget _buildCupertinoWebDavBreadcrumb() {
    final segments =
        _currentPath.split('/').where((segment) => segment.isNotEmpty).toList();
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _buildCupertinoPathButton(
            label: '根目录',
            selected: segments.isEmpty,
            onPressed: () => _navigateToPath('/'),
          ),
          for (var index = 0; index < segments.length; index++) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Icon(cupertino.CupertinoIcons.chevron_right, size: 13),
            ),
            _buildCupertinoPathButton(
              label: segments[index],
              selected: index == segments.length - 1,
              onPressed: index == segments.length - 1
                  ? null
                  : () => _navigateToPath(
                        '/${segments.sublist(0, index + 1).join('/')}',
                      ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCupertinoPathButton({
    required String label,
    required bool selected,
    required VoidCallback? onPressed,
  }) {
    final secondary = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );
    return cupertino.CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected
              ? cupertino.CupertinoTheme.of(context).primaryColor
              : secondary,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildCupertinoWebDavDirectory() {
    if (_isLoading) {
      return const Center(child: AdaptiveMediaActivityIndicator());
    }
    if (_currentFiles.isEmpty) {
      return const Center(child: Text('当前目录为空'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
      itemCount: _currentFiles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) =>
          _buildCupertinoWebDavFile(_currentFiles[index]),
    );
  }

  Widget _buildCupertinoWebDavFile(WebDAVFile file) {
    final label = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.label,
      context,
    );
    final secondary = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );
    final card = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    final videoUrl = file.isDirectory
        ? null
        : WebDAVService.instance.getFileUrl(_currentConnection!, file.path);
    WatchHistoryItem? historyItem;
    if (videoUrl != null) {
      for (final item in context.read<WatchHistoryProvider>().history) {
        if (item.filePath == videoUrl) {
          historyItem = item;
          break;
        }
      }
    }
    final progress = historyItem?.watchProgress ?? 0;
    final hasProgress = progress > 0.01 && progress < 0.95;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: cupertino.CupertinoButton(
        padding: const EdgeInsets.all(11),
        borderRadius: BorderRadius.circular(8),
        onPressed: file.isDirectory
            ? () => _navigateToDirectory(file.path)
            : () => _playVideo(file),
        child: Row(
          children: [
            Icon(
              file.isDirectory
                  ? cupertino.CupertinoIcons.folder
                  : cupertino.CupertinoIcons.play_rectangle,
              color: file.isDirectory
                  ? cupertino.CupertinoColors.systemYellow
                  : cupertino.CupertinoTheme.of(context).primaryColor,
              size: 25,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: label,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file.isDirectory
                        ? '文件夹'
                        : file.size == null
                            ? '视频'
                            : _formatFileSize(file.size!),
                    style: TextStyle(color: secondary, fontSize: 12),
                  ),
                  if (hasProgress) ...[
                    const SizedBox(height: 7),
                    AdaptiveMediaProgressBar(value: progress, height: 2),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              file.isDirectory
                  ? cupertino.CupertinoIcons.chevron_right
                  : cupertino.CupertinoIcons.play_circle,
              color: secondary,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCupertinoWebDavSearchResults() {
    final secondary = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );
    if (_isSearching) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '已扫描 $_searchedCount 个目录，找到 $_foundCount 个结果',
                        style: TextStyle(color: secondary, fontSize: 13),
                      ),
                    ),
                    cupertino.CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(44, 32),
                      onPressed: () => setState(() {
                        _stopSearchRequested = true;
                      }),
                      child: const Text(
                        '停止',
                        style: TextStyle(
                          color: cupertino.CupertinoColors.systemRed,
                        ),
                      ),
                    ),
                  ],
                ),
                const AdaptiveMediaProgressBar(value: null, height: 2),
              ],
            ),
          ),
          Expanded(child: _buildCupertinoWebDavSearchList(secondary)),
        ],
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          _searchKeyword.isEmpty ? '输入关键词搜索文件' : '未找到匹配的文件',
          style: TextStyle(color: secondary),
        ),
      );
    }
    return _buildCupertinoWebDavSearchList(secondary);
  }

  Widget _buildCupertinoWebDavSearchList(Color secondary) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cupertino.CupertinoDynamicColor.resolve(
              cupertino.CupertinoColors.secondarySystemGroupedBackground,
              context,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: cupertino.CupertinoButton(
            padding: const EdgeInsets.all(11),
            borderRadius: BorderRadius.circular(8),
            onPressed: result.file.isDirectory
                ? () => _navigateToPathFromSearch(result.file.path)
                : () => _playSearchResult(result),
            child: Row(
              children: [
                Icon(
                  result.file.isDirectory
                      ? cupertino.CupertinoIcons.folder
                      : cupertino.CupertinoIcons.play_rectangle,
                  size: 24,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.relativePath.isEmpty ? '/' : result.relativePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(
                  result.file.isDirectory
                      ? cupertino.CupertinoIcons.arrow_turn_up_right
                      : cupertino.CupertinoIcons.play_circle,
                  size: 19,
                  color: secondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCupertinoServerActions() async {
    final current = _currentConnection;
    final action =
        await cupertino.showCupertinoModalPopup<_CupertinoWebDavAction>(
      context: context,
      builder: (sheetContext) => cupertino.CupertinoActionSheet(
        title: const Text('WebDAV 服务器'),
        actions: [
          for (final connection in WebDAVService.instance.connections)
            cupertino.CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(
                _CupertinoWebDavAction.select(connection),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (connection.name == current?.name) ...[
                    const Icon(cupertino.CupertinoIcons.check_mark, size: 16),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      connection.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          cupertino.CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(
              const _CupertinoWebDavAction.add(),
            ),
            child: const Text('添加服务器'),
          ),
          if (current != null)
            cupertino.CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(
                const _CupertinoWebDavAction.edit(),
              ),
              child: const Text('编辑当前服务器'),
            ),
          if (current != null)
            cupertino.CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(
                const _CupertinoWebDavAction.test(),
              ),
              child: const Text('测试当前连接'),
            ),
          if (current != null)
            cupertino.CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(sheetContext).pop(
                const _CupertinoWebDavAction.remove(),
              ),
              child: const Text('删除当前服务器'),
            ),
        ],
        cancelButton: cupertino.CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action.kind) {
      case _CupertinoWebDavActionKind.select:
        setState(() {
          _currentConnection = action.connection;
          _currentPath = '/';
          _pathHistory.clear();
        });
        await _loadDirectory();
        break;
      case _CupertinoWebDavActionKind.add:
        await _showAddServerDialog();
        break;
      case _CupertinoWebDavActionKind.edit:
        await _editCupertinoWebDavServer(current!);
        break;
      case _CupertinoWebDavActionKind.test:
        await WebDAVService.instance.updateConnectionStatus(current!.name);
        if (!mounted) return;
        final updated = WebDAVService.instance.getConnection(current.name);
        setState(() => _currentConnection = updated ?? current);
        BlurSnackBar.show(
          context,
          updated?.isConnected == true ? 'WebDAV 连接正常' : 'WebDAV 连接失败',
        );
        break;
      case _CupertinoWebDavActionKind.remove:
        await _removeCupertinoWebDavServer(current!);
        break;
    }
  }

  Future<void> _editCupertinoWebDavServer(WebDAVConnection connection) async {
    final saved = await CupertinoWebDAVConnectionDialog.show(
      context,
      editConnection: connection,
    );
    if (!mounted || saved != true) return;
    final connections = WebDAVService.instance.connections;
    setState(() {
      _currentConnection = connections.firstWhere(
        (item) => item.name == connection.name,
        orElse: () => connections.first,
      );
      _currentPath = '/';
      _pathHistory.clear();
    });
    await _loadDirectory();
  }

  Future<void> _removeCupertinoWebDavServer(
    WebDAVConnection connection,
  ) async {
    final confirmed = await cupertino.showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => cupertino.CupertinoAlertDialog(
        title: const Text('删除 WebDAV 服务器'),
        content: Text('确定删除“${connection.name}”吗？'),
        actions: [
          cupertino.CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          cupertino.CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await WebDAVService.instance.removeConnection(connection.name);
    if (!mounted) return;
    final connections = WebDAVService.instance.connections;
    setState(() {
      _currentConnection = connections.isEmpty ? null : connections.first;
      _currentPath = '/';
      _pathHistory.clear();
      _currentFiles = [];
    });
    if (_currentConnection != null) await _loadDirectory();
  }
}

enum _CupertinoWebDavActionKind { select, add, edit, test, remove }

class _CupertinoWebDavAction {
  const _CupertinoWebDavAction.select(this.connection)
      : kind = _CupertinoWebDavActionKind.select;
  const _CupertinoWebDavAction.add()
      : kind = _CupertinoWebDavActionKind.add,
        connection = null;
  const _CupertinoWebDavAction.edit()
      : kind = _CupertinoWebDavActionKind.edit,
        connection = null;
  const _CupertinoWebDavAction.test()
      : kind = _CupertinoWebDavActionKind.test,
        connection = null;
  const _CupertinoWebDavAction.remove()
      : kind = _CupertinoWebDavActionKind.remove,
        connection = null;

  final _CupertinoWebDavActionKind kind;
  final WebDAVConnection? connection;
}
