import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/themes/web/services/web_remote_api_client.dart';
import 'package:url_launcher/url_launcher.dart';

class WebManagementPage extends StatefulWidget {
  const WebManagementPage({
    super.key,
    required this.api,
  });

  final WebRemoteApiClient api;

  @override
  State<WebManagementPage> createState() => _WebManagementPageState();
}

class _WebManagementPageState extends State<WebManagementPage> {
  late Future<WebManagementData> _future;
  final TextEditingController _folderController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchManagement();
  }

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = widget.api.fetchManagement();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<WebManagementData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(
              title: '加载失败',
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final data = snapshot.data ?? const WebManagementData();
          final status = data.scanStatus;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '库管理',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      await widget.api.rescanAll();
                      _refresh();
                    },
                    icon: const Icon(Icons.manage_search),
                    label: const Text('重新扫描'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (status != null) _ScanStatusCard(status: status),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _FoldersCard(
                        folders: data.folders,
                        onRemove: (path) async {
                          await widget.api.removeFolder(path);
                          _refresh();
                        },
                        onBrowse: (path) async {
                          await showDialog<void>(
                            context: context,
                            builder: (_) => Dialog(
                              insetPadding: const EdgeInsets.all(16),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 980,
                                  maxHeight: 720,
                                ),
                                child: _RemoteBrowser(
                                  api: widget.api,
                                  initialPath: path,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: _AddFolderCard(
                        controller: _folderController,
                        onAdd: (path) async {
                          await widget.api.addFolder(path, scan: true);
                          _folderController.clear();
                          _refresh();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScanStatusCard extends StatelessWidget {
  const _ScanStatusCard({required this.status});

  final SharedRemoteScanStatus status;

  @override
  Widget build(BuildContext context) {
    final bool scanning = status.isScanning;
    final double progress = status.progress.clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(scanning ? Icons.autorenew : Icons.check_circle_outline),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scanning ? '扫描中' : '空闲',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: scanning ? progress : null),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (status.message.isNotEmpty) status.message,
                      '已发现文件：${status.totalFilesFound}',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoldersCard extends StatelessWidget {
  const _FoldersCard({
    required this.folders,
    required this.onRemove,
    required this.onBrowse,
  });

  final List<SharedRemoteScannedFolder> folders;
  final Future<void> Function(String path) onRemove;
  final Future<void> Function(String path) onBrowse;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '扫描文件夹',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: folders.isEmpty
                  ? const Center(child: Text('暂无扫描文件夹'))
                  : ListView.separated(
                      itemCount: folders.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        return ListTile(
                          leading: Icon(
                            folder.exists ? Icons.folder : Icons.folder_off,
                          ),
                          title: Text(folder.name),
                          subtitle: Text(folder.path),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '浏览',
                                onPressed: () => onBrowse(folder.path),
                                icon: const Icon(Icons.travel_explore),
                              ),
                              IconButton(
                                tooltip: '移除',
                                onPressed: () => onRemove(folder.path),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddFolderCard extends StatelessWidget {
  const _AddFolderCard({
    required this.controller,
    required this.onAdd,
  });

  final TextEditingController controller;
  final Future<void> Function(String path) onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '添加文件夹（服务端路径）',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '/Volumes/Media/Anime',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final path = controller.text.trim();
                  if (path.isEmpty) return;
                  await onAdd(path);
                },
                icon: const Icon(Icons.add),
                label: const Text('添加并扫描'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '提示：此处填写的是运行 NipaPlay 的机器上的绝对路径。',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteBrowser extends StatefulWidget {
  const _RemoteBrowser({
    required this.api,
    required this.initialPath,
  });

  final WebRemoteApiClient api;
  final String initialPath;

  @override
  State<_RemoteBrowser> createState() => _RemoteBrowserState();
}

class _RemoteBrowserState extends State<_RemoteBrowser> {
  late String _path;
  late Future<List<SharedRemoteFileEntry>> _future;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _future = widget.api.browseDirectory(_path);
  }

  void _open(String path) {
    setState(() {
      _path = path;
      _future = widget.api.browseDirectory(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '远程浏览',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<SharedRemoteFileEntry>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorView(
                    title: '读取目录失败',
                    message: snapshot.error.toString(),
                    onRetry: () => _open(_path),
                  );
                }
                final entries = snapshot.data ?? const <SharedRemoteFileEntry>[];
                if (entries.isEmpty) {
                  return const Center(child: Text('空目录'));
                }

                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final subtitle = <String>[
                      if (entry.modifiedTime != null)
                        DateFormat('yyyy-MM-dd HH:mm')
                            .format(entry.modifiedTime!.toLocal()),
                      if (!entry.isDirectory && entry.size != null)
                        '${(entry.size! / (1024 * 1024)).toStringAsFixed(1)} MB',
                      if (entry.animeName?.isNotEmpty == true)
                        entry.animeName!,
                      if (entry.episodeTitle?.isNotEmpty == true)
                        entry.episodeTitle!,
                    ].join(' · ');

                    return ListTile(
                      leading: Icon(
                        entry.isDirectory ? Icons.folder : Icons.movie_outlined,
                      ),
                      title: Text(entry.name),
                      subtitle: subtitle.isEmpty ? null : Text(subtitle),
                      onTap: entry.isDirectory ? () => _open(entry.path) : null,
                      trailing: entry.isDirectory
                          ? const Icon(Icons.chevron_right)
                          : TextButton(
                              onPressed: () async {
                                final uri =
                                    widget.api.resolveManageStream(entry.path);
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                              child: const Text('打开'),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

