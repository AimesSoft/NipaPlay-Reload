// lib/pages/media_sources/card.dart

part of 'media_sources_page.dart';

class MediaSourceCard extends StatelessWidget {
  const MediaSourceCard({
    super.key,
    required this.info,
    required this.onDelete,
    required this.onEdit,
    required this.onUpdateDB,
    required this.onSynchronizePathAssetRecords,
    required this.onUpdateAssetPathRecordsHash,
  });

  final MediaSourceInfo info;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onUpdateDB;
  final VoidCallback onSynchronizePathAssetRecords;
  final VoidCallback onUpdateAssetPathRecordsHash;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        title: Text(
            info.name == null || info.name!.isEmpty ? '未知媒体源' : info.name!),
        subtitle: Text(info.toString()),

        // 删除按钮
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: onDelete,
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: '打印debug信息',
              onPressed: () {
                debugPrint('MediaSourceCard debug info: ${info.toString()}');
              },
            ),

            // 更新数据库按钮
            IconButton(
              icon: const Icon(Icons.update),
              tooltip: '更新数据库',
              onPressed: onUpdateDB,
            ),

            // 同步 Path-Asset 表按钮
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: '同步 Path-Asset 表',
              onPressed: () {
                onSynchronizePathAssetRecords();
              },
            ),

            // 更新前 16MiB MD5 哈希值按钮
            IconButton(
              icon: const Icon(Icons.lock),
              tooltip: '更新前 16MiB MD5 哈希值',
              onPressed: onUpdateAssetPathRecordsHash,
            ),
          ],
        ),

        // 点击卡片时, 进入媒体源文件浏览页面
        onTap: () {
          if (info is! LocalMediaSourceInfo) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('仅支持本地媒体源的文件浏览'),
              ),
            );
            return;
          }
          final localInfo = info as LocalMediaSourceInfo;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MediaSourceFilesPage(
                folder: localInfo.directory
              ),
            ),
          );
        },
      ),
    );
  }
}
