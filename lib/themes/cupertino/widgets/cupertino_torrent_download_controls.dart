part of torrent_download_page;

class CupertinoTorrentDownloadView extends StatefulWidget {
  const CupertinoTorrentDownloadView({super.key, required this.data});

  final UnifiedTorrentPageViewModel data;

  @override
  State<CupertinoTorrentDownloadView> createState() =>
      _CupertinoTorrentDownloadViewState();
}

class _CupertinoTorrentDownloadViewState
    extends State<CupertinoTorrentDownloadView> {
  CupertinoPageActionsController? _pageActionsController;

  UnifiedTorrentPageViewModel get data => widget.data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPageAction();
  }

  @override
  void didUpdateWidget(covariant CupertinoTorrentDownloadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.viewMode != data.viewMode ||
        oldWidget.data.onToggleViewMode != data.onToggleViewMode) {
      _syncPageAction();
    }
  }

  void _syncPageAction() {
    final controller = CupertinoPageActionsScope.maybeOf(context);
    if (controller != _pageActionsController) {
      _pageActionsController?.clear(this);
      _pageActionsController = controller;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || controller != _pageActionsController) return;
      controller?.setActions(
        this,
        [
          CupertinoPageAction(
            id: 'torrent-view-mode',
            label: data.viewMode == UnifiedTorrentTaskViewMode.cards
                ? '切换到列表视图'
                : '切换到图标视图',
            icon: data.viewMode == UnifiedTorrentTaskViewMode.cards
                ? cupertino.CupertinoIcons.list_bullet
                : cupertino.CupertinoIcons.square_grid_2x2,
            onPressed: data.onToggleViewMode,
          ),
        ],
      );
    });
  }

  @override
  void dispose() {
    _pageActionsController?.clear(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final separator = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.separator,
      context,
    );
    final secondary = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.secondaryLabel,
      context,
    );

    return ColoredBox(
      color: Colors.transparent,
      child: Column(
        children: [
          const CupertinoAppPageHeader(title: '下载器', bottomPadding: 4),
          _buildToolbar(context),
          ColoredBox(color: separator, child: const SizedBox(height: 0.5)),
          Expanded(
            child: data.isLoading
                ? Center(
                    child: cupertino.CupertinoActivityIndicator(
                      color: secondary,
                    ),
                  )
                : data.visibleTasks.isEmpty
                    ? _buildEmpty(context)
                    : _buildTaskList(context),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        children: [
          cupertino.CupertinoSearchTextField(
            controller: data.searchController,
            placeholder: '搜索下载任务',
            onChanged: data.onSearchChanged,
            onSuffixTap: () {
              data.searchController.clear();
              data.onClearSearch();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _cupertinoToolbarButton(
                context,
                icon: cupertino.CupertinoIcons.sort_down,
                label: unifiedTorrentTaskSortLabels[data.sort] ?? '排序',
                onPressed: () => _showSort(context),
              ),
              const SizedBox(width: 6),
              _cupertinoToolbarButton(
                context,
                icon: cupertino.CupertinoIcons.refresh,
                onPressed: data.isBusy ? null : data.onRefresh,
              ),
              const Spacer(),
              _cupertinoToolbarButton(
                context,
                icon: cupertino.CupertinoIcons.link,
                label: '添加',
                filled: true,
                onPressed: data.isBusy ? null : data.onAddMagnet,
              ),
              const SizedBox(width: 6),
              _cupertinoToolbarButton(
                context,
                icon: cupertino.CupertinoIcons.doc,
                label: '种子',
                onPressed: data.isBusy ? null : data.onPickTorrent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cupertinoToolbarButton(
    BuildContext context, {
    required IconData icon,
    String? label,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    final foreground = filled
        ? cupertino.CupertinoColors.white
        : cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.label,
            context,
          );
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

  Future<void> _showSort(BuildContext context) async {
    final selected =
        await CupertinoBottomSheet.showSelection<UnifiedTorrentTaskSort>(
      context: context,
      title: '排序方式',
      options: [
        for (final entry in unifiedTorrentTaskSortLabels.entries)
          CupertinoBottomSheetOption(
            label: entry.value,
            value: entry.key,
            selected: entry.key == data.sort,
          ),
      ],
    );
    if (selected != null) data.onSortChanged(selected);
  }

  Widget _buildTaskList(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 84),
      itemCount: data.visibleTasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = data.visibleTasks[index];
        return _buildTaskCard(
          context,
          item,
          compact: data.viewMode == UnifiedTorrentTaskViewMode.list,
        );
      },
    );
  }

  Widget _buildTaskCard(
    BuildContext context,
    UnifiedTorrentTaskItemViewModel item, {
    required bool compact,
  }) {
    final task = item.task;
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showTaskActions(context, item),
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
                    color: secondary,
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
                    onPressed: () => _showTaskActions(context, item),
                    child: Icon(
                      cupertino.CupertinoIcons.ellipsis,
                      size: 19,
                      color: secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildTaskProgress(context, task),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _metric(
                    context,
                    '${(task.progress * 100).toStringAsFixed(1)}%',
                  ),
                  _metric(
                    context,
                    '${formatTorrentBytes(task.progressBytes)} / '
                    '${formatTorrentBytes(task.totalBytes)}',
                  ),
                  if (!compact)
                    _metric(
                      context,
                      '↓ ${formatTorrentBytes(task.downloadSpeedBytesPerSecond)}/s',
                    ),
                  if (!compact)
                    _metric(
                      context,
                      '↑ ${formatTorrentBytes(task.uploadSpeedBytesPerSecond)}/s',
                    ),
                ],
              ),
              if (item.scanStatusText != null) ...[
                const SizedBox(height: 7),
                Text(
                  item.scanStatusText!,
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

  Widget _buildTaskProgress(BuildContext context, TorrentTask task) {
    final background = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.systemGrey4,
      context,
    );
    final foreground = task.hasError
        ? cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.systemRed,
            context,
          )
        : cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.systemGrey,
            context,
          );
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

  Widget _metric(BuildContext context, String text) {
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

  Future<void> _showTaskActions(
    BuildContext context,
    UnifiedTorrentTaskItemViewModel item,
  ) async {
    final selected =
        await CupertinoBottomSheet.showSelection<UnifiedTorrentTaskAction>(
      context: context,
      title: item.task.name,
      options: [
        for (final action in item.actions)
          CupertinoBottomSheetOption(
            label: action.label,
            value: action.action,
            destructive: action.destructive,
          ),
      ],
    );
    if (selected == null) return;
    item.action(selected)?.onPressed();
  }

  Widget _buildEmpty(BuildContext context) {
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
          Text(data.emptyTitle),
          const SizedBox(height: 5),
          Text(
            data.emptyDescription,
            style: TextStyle(fontSize: 13, color: secondary),
          ),
        ],
      ),
    );
  }
}

class CupertinoAddTorrentView extends StatelessWidget {
  const CupertinoAddTorrentView({super.key, required this.data});

  final AddTorrentDialogViewModel data;

  @override
  Widget build(BuildContext context) {
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
              Text(
                AddTorrentDialogViewModel.magnetLabel,
                style: TextStyle(fontSize: 13, color: secondary),
              ),
              const SizedBox(height: 6),
              cupertino.CupertinoTextField(
                controller: data.magnetController,
                placeholder: AddTorrentDialogViewModel.magnetPlaceholder,
                minLines: 2,
                maxLines: 4,
                onChanged: data.onMagnetChanged,
              ),
              const SizedBox(height: 16),
              Text(
                AddTorrentDialogViewModel.directoryLabel,
                style: TextStyle(fontSize: 13, color: secondary),
              ),
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
                          data.downloadDirectory.isEmpty
                              ? '尚未选择目录'
                              : data.downloadDirectory,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      cupertino.CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        onPressed: data.onChooseDirectory,
                        child: const Text('选择'),
                      ),
                    ],
                  ),
                ),
              ),
              if (data.recentDirectories.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: data.recentDirectories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final directory = data.recentDirectories[index];
                      return cupertino.CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        color: cupertino.CupertinoDynamicColor.resolve(
                          cupertino.CupertinoColors.systemGrey5,
                          context,
                        ),
                        onPressed: () => data.onSelectDirectory(directory),
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
                  const Expanded(
                    child: Text(AddTorrentDialogViewModel.createFolderLabel),
                  ),
                  cupertino.CupertinoSwitch(
                    value: data.createFolderForTask,
                    onChanged: data.onCreateFolderChanged,
                  ),
                ],
              ),
              if (data.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  data.error!,
                  style: const TextStyle(
                    color: cupertino.CupertinoColors.systemRed,
                    fontSize: 13,
                  ),
                ),
              ],
              if (data.preview != null) ...[
                const SizedBox(height: 16),
                _buildPreview(context, data.preview!),
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
                      onPressed: data.isPreviewing ? null : data.onPreview,
                      child: data.isPreviewing
                          ? const cupertino.CupertinoActivityIndicator()
                          : Text(data.previewLabel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: cupertino.CupertinoButton.filled(
                      onPressed: data.canConfirm ? data.onConfirm : null,
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

  Widget _buildPreview(
    BuildContext context,
    TorrentMagnetPreview preview,
  ) {
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
              '${formatTorrentBytes(preview.totalSize)}',
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
                        formatTorrentBytes(file.length),
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
