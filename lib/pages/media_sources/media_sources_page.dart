
// lib/pages/media_sources_page.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nipaplay/services/media_source/media_source_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:path/path.dart' as p;


part 'card.dart';
part 'create_source.dart';
part 'files_page.dart';


class MediaSourcesPage extends StatefulWidget {
  const MediaSourcesPage({super.key});

  @override
  State<MediaSourcesPage> createState() => _MediaSourcesPageState();
}

class _MediaSourcesPageState extends State<MediaSourcesPage> {

  // 新建媒体源
  Future<void> _createItem() async {

    final result = await createOrEditMediaSourceDialog(context);

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      MediaSourceService.addMediaSource(result);
    });

    // 保存到配置文件
    await MediaSourceService.saveAllMediaSourcesToConfigFile();
  }

  // 删除媒体源
  Future<void> _deleteItem(int sourceId) async {
    setState(() {
      MediaSourceService.removeMediaSource(sourceId);
    });

    await MediaSourceService.saveAllMediaSourcesToConfigFile();
  }

  // 编辑媒体源
  Future<void> _editItem(MediaSourceInfo info) async {
    final result = await createOrEditMediaSourceDialog(context, info: info);

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      MediaSourceService.updateMediaSource(result);
    });

    await MediaSourceService.saveAllMediaSourcesToConfigFile();
  }

  // 全量更新数据库
  Future<void> _updateDatabase(int sourceId) async {
    await MediaSourceService.registerMediaSourceFilesToDatabase(sourceId);
  }

  // 同步 Path-Asset 表
  Future<void> _synchronizePathAssetRecords(int sourceId) async {
    await MediaSourceService.synchronizeMediaSourceFilesWithDatabase(sourceId);
  }

  /// 1. 获取指定媒体源下所有 asset_pre16mib_md5 字段为 null 的视频资产路径记录
  /// 2. 根据这些记录, 计算该路径文件的前 16MiB 的 MD5 哈希值, 并更新数据库
  Future<void> _updateAssetPathRecordsHash(int sourceId) async {
    await MediaSourceService.updateAssetPathRecordsHash(sourceId);
  }

  @override
  Widget build(BuildContext context) {

    final items = MediaSourceService.getMediaSources().toList();
    items.sort((a, b) => a.id.compareTo(b.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体源'),
        actions: [
          IconButton(
            onPressed: _createItem,
            icon: const Icon(Icons.add),
            tooltip: '新建',
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('暂无媒体源'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final info = items[index];
                return MediaSourceCard(
                  info: info,
                  onDelete: () => _deleteItem(info.id),
                  onEdit: () => _editItem(info),
                  onUpdateDB: () => _updateDatabase(info.id),
                  onSynchronizePathAssetRecords: () => _synchronizePathAssetRecords(info.id),
                  onUpdateAssetPathRecordsHash: () => _updateAssetPathRecordsHash(info.id),
                );
              },
            ),
    );
  }
}

