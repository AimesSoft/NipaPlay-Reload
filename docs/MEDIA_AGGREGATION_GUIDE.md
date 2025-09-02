# NipaPlay 媒体库大一统聚合方案

## 概述

NipaPlay不仅是独立的媒体服务器，更是一个**媒体库聚合中心**，可以在统一界面中整合和管理来自不同源的媒体库，实现真正的"多源大一统"。

## 聚合架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                      NipaPlay 聚合中心                              │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                    统一 Web 界面                                 │ │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐  │ │
│  │  │本地媒体 │ │朋友的库 │ │ 云存储  │ │ Plex库  │ │Jellyfin │  │ │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘  │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                    聚合服务层                                    │ │
│  │  ┌─────────────────────────────────────────────────────────────┐ │ │
│  │  │              媒体库适配器 (Adapters)                         │ │ │
│  │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───────┐ │ │ │
│  │  │  │本地适配 │ │网络适配 │ │云存储适配│ │ Plex API│ │Emby API│ │ │ │
│  │  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └───────┘ │ │ │
│  │  └─────────────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
          ↓ API调用         ↓ 网络访问        ↓ API调用
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────────────────┐
│   本地 NAS      │ │  朋友家 NAS     │ │     第三方媒体服务           │
│ ┌─────────────┐ │ │ ┌─────────────┐ │ │ ┌─────────┐ ┌─────────────┐ │
│ │ 本地文件    │ │ │ │NipaPlay服务 │ │ │ │  Plex   │ │  Jellyfin   │ │
│ └─────────────┘ │ │ └─────────────┘ │ │ └─────────┘ └─────────────┘ │
└─────────────────┘ └─────────────────┘ └─────────────────────────────┘
```

## 支持的媒体源类型

### 1. 本地媒体源
- **本地文件夹**: 直接扫描本地目录
- **网络共享**: SMB/NFS挂载点
- **外接存储**: USB硬盘、移动硬盘

### 2. 远程NipaPlay实例
- **朋友家的NipaPlay**: 通过API互联
- **多台设备**: 家里多台NAS/服务器
- **分布式存储**: 不同位置的存储设备

### 3. 第三方媒体服务
- **Plex Media Server**: 通过Plex API
- **Jellyfin**: 通过Jellyfin API  
- **Emby**: 通过Emby API
- **Kodi**: 通过JSON-RPC API

### 4. 云存储服务
- **阿里云盘**: 通过官方API
- **百度网盘**: 通过API或WebDAV
- **OneDrive**: 通过Microsoft Graph API
- **Google Drive**: 通过Google Drive API

### 5. 在线媒体源
- **IPTV直播源**: M3U8播放列表
- **网络电台**: 音频流媒体
- **YouTube**: 通过yt-dlp集成
- **Bilibili**: 通过API集成

## 技术实现

### 1. 适配器架构

#### 基础适配器接口
```dart
// lib/adapters/base_media_adapter.dart
abstract class BaseMediaAdapter {
  String get adapterName;
  String get adapterType;
  bool get isOnline;
  
  // 基础功能
  Future<bool> connect();
  Future<void> disconnect();
  Future<bool> testConnection();
  
  // 媒体库操作
  Future<List<MediaLibrary>> getLibraries();
  Future<List<MediaItem>> getLibraryItems(String libraryId);
  Future<MediaItem?> getItemDetails(String itemId);
  
  // 搜索功能
  Future<List<MediaItem>> search(String query);
  
  // 播放功能
  Future<String> getPlayUrl(String itemId);
  Future<List<Subtitle>> getSubtitles(String itemId);
  
  // 元数据
  Future<MediaMetadata> getMetadata(String itemId);
}
```

#### 本地文件适配器
```dart
// lib/adapters/local_file_adapter.dart
class LocalFileAdapter extends BaseMediaAdapter {
  final String basePath;
  
  LocalFileAdapter(this.basePath);
  
  @override
  String get adapterName => "本地文件";
  
  @override
  Future<List<MediaLibrary>> getLibraries() async {
    // 扫描本地目录结构
    return await _scanLocalDirectories();
  }
  
  @override
  Future<String> getPlayUrl(String itemId) async {
    // 返回本地文件路径或HTTP服务URL
    return "file://$basePath/$itemId";
  }
}
```

#### Plex适配器
```dart
// lib/adapters/plex_adapter.dart
class PlexAdapter extends BaseMediaAdapter {
  final String serverUrl;
  final String token;
  
  PlexAdapter(this.serverUrl, this.token);
  
  @override
  String get adapterName => "Plex服务器";
  
  @override
  Future<List<MediaLibrary>> getLibraries() async {
    final response = await http.get(
      Uri.parse('$serverUrl/library/sections'),
      headers: {'X-Plex-Token': token}
    );
    
    return _parsePlexLibraries(response.body);
  }
  
  @override
  Future<String> getPlayUrl(String itemId) async {
    return '$serverUrl/video/:/transcode/universal/start?path=/library/metadata/$itemId';
  }
}
```

#### Jellyfin适配器
```dart
// lib/adapters/jellyfin_adapter.dart
class JellyfinAdapter extends BaseMediaAdapter {
  final String serverUrl;
  final String apiKey;
  
  JellyfinAdapter(this.serverUrl, this.apiKey);
  
  @override
  String get adapterName => "Jellyfin服务器";
  
  @override
  Future<List<MediaLibrary>> getLibraries() async {
    final response = await http.get(
      Uri.parse('$serverUrl/Library/VirtualFolders'),
      headers: {'Authorization': 'MediaBrowser Token="$apiKey"'}
    );
    
    return _parseJellyfinLibraries(response.body);
  }
}
```

#### 云存储适配器
```dart
// lib/adapters/cloud_storage_adapter.dart
class AliyunDriveAdapter extends BaseMediaAdapter {
  final String refreshToken;
  String? accessToken;
  
  @override
  String get adapterName => "阿里云盘";
  
  @override
  Future<List<MediaLibrary>> getLibraries() async {
    await _refreshAccessToken();
    // 获取云盘文件列表
    return await _getCloudFiles();
  }
  
  @override
  Future<String> getPlayUrl(String itemId) async {
    // 获取云盘文件的下载链接
    return await _getDownloadUrl(itemId);
  }
}
```

### 2. 媒体库管理器

```dart
// lib/services/media_aggregation_service.dart
class MediaAggregationService {
  final List<BaseMediaAdapter> _adapters = [];
  final Map<String, List<MediaItem>> _cachedItems = {};
  
  // 注册适配器
  void registerAdapter(BaseMediaAdapter adapter) {
    _adapters.add(adapter);
  }
  
  // 获取所有媒体库
  Future<List<AggregatedLibrary>> getAllLibraries() async {
    final allLibraries = <AggregatedLibrary>[];
    
    for (final adapter in _adapters) {
      try {
        final libraries = await adapter.getLibraries();
        for (final lib in libraries) {
          allLibraries.add(AggregatedLibrary(
            id: '${adapter.adapterName}_${lib.id}',
            name: '${lib.name} (${adapter.adapterName})',
            adapter: adapter,
            originalLibrary: lib,
          ));
        }
      } catch (e) {
        print('获取 ${adapter.adapterName} 媒体库失败: $e');
      }
    }
    
    return allLibraries;
  }
  
  // 聚合搜索
  Future<List<MediaItem>> aggregatedSearch(String query) async {
    final results = <MediaItem>[];
    
    await Future.wait(_adapters.map((adapter) async {
      try {
        final items = await adapter.search(query);
        results.addAll(items.map((item) => item.copyWith(
          sourceAdapter: adapter.adapterName
        )));
      } catch (e) {
        print('在 ${adapter.adapterName} 中搜索失败: $e');
      }
    }));
    
    return results;
  }
  
  // 智能推荐
  Future<List<MediaItem>> getRecommendations() async {
    // 基于观看历史从所有源推荐内容
    return await _generateCrossSourceRecommendations();
  }
}
```

### 3. 统一界面设计

#### 聚合媒体库页面
```dart
// lib/pages/aggregated_library_page.dart
class AggregatedLibraryPage extends StatefulWidget {
  @override
  _AggregatedLibraryPageState createState() => _AggregatedLibraryPageState();
}

class _AggregatedLibraryPageState extends State<AggregatedLibraryPage> {
  final MediaAggregationService _aggregationService = MediaAggregationService();
  List<AggregatedLibrary> _libraries = [];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 媒体源选择器
          _buildSourceSelector(),
          
          // 聚合搜索栏
          _buildAggregatedSearchBar(),
          
          // 媒体库网格
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _getGridCrossAxisCount(),
                childAspectRatio: 0.7,
              ),
              itemCount: _libraries.length,
              itemBuilder: (context, index) {
                return _buildLibraryCard(_libraries[index]);
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSourceSelector() {
    return Container(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _aggregationService.adapters.length,
        itemBuilder: (context, index) {
          final adapter = _aggregationService.adapters[index];
          return _buildSourceChip(adapter);
        },
      ),
    );
  }
  
  Widget _buildLibraryCard(AggregatedLibrary library) {
    return Card(
      child: Column(
        children: [
          // 库封面
          Expanded(
            child: _buildLibraryCover(library),
          ),
          
          // 库信息
          Padding(
            padding: EdgeInsets.all(8),
            child: Column(
              children: [
                Text(library.name, locale:Locale("zh","CN"),
style: TextStyle(fontWeight: FontWeight.bold)),
                Text(library.adapter.adapterName, 
                     locale:Locale("zh","CN"),
style: TextStyle(color: Colors.grey, fontSize: 12)),
                // 连接状态指示器
                _buildConnectionStatus(library.adapter),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

### 4. 配置管理

#### 媒体源配置
```dart
// lib/models/media_source_config.dart
class MediaSourceConfig {
  final String id;
  final String name;
  final MediaSourceType type;
  final Map<String, dynamic> config;
  final bool enabled;
  
  const MediaSourceConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.config,
    this.enabled = true,
  });
}

enum MediaSourceType {
  local,
  plex,
  jellyfin,
  emby,
  nipaplay,
  aliyunDrive,
  baiduPan,
  iptv,
}
```

#### 设置页面
```dart
// lib/pages/settings/media_sources_page.dart
class MediaSourcesPage extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // 添加媒体源按钮
        ListTile(
          title: Text("添加媒体源"),
          leading: Icon(Icons.add),
          onTap: _showAddSourceDialog,
        ),
        
        Divider(),
        
        // 已配置的媒体源列表
        ..._buildSourcesList(),
        
        Divider(),
        
        // 聚合设置
        SwitchListTile(
          title: Text("启用跨源搜索"),
          subtitle: Text("在所有媒体源中同时搜索"),
          value: _crossSourceSearchEnabled,
          onChanged: _toggleCrossSourceSearch,
        ),
        
        SwitchListTile(
          title: Text("智能推荐"),
          subtitle: Text("基于所有源的观看历史推荐内容"),
          value: _smartRecommendationEnabled,
          onChanged: _toggleSmartRecommendation,
        ),
      ],
    );
  }
}
```

## 高级功能

### 1. 跨源播放列表
```dart
// 用户可以创建包含不同源内容的播放列表
class CrossSourcePlaylist {
  final String id;
  final String name;
  final List<PlaylistItem> items;
  
  // 播放列表项可能来自不同的适配器
  class PlaylistItem {
    final String itemId;
    final BaseMediaAdapter adapter;
    final MediaItem metadata;
  }
}
```

### 2. 统一观看历史
```dart
// 不管从哪个源观看，都记录在统一的历史中
class UnifiedWatchHistory {
  final String itemId;
  final String sourceAdapter;
  final DateTime watchTime;
  final Duration position;
  final MediaItem metadata;
}
```

### 3. 智能去重
```dart
// 识别不同源中的相同内容
class ContentDeduplicator {
  Future<List<MediaItem>> deduplicateItems(List<MediaItem> items) async {
    // 基于文件名、时长、大小等特征识别重复内容
    return await _performDeduplication(items);
  }
}
```

### 4. 负载均衡
```dart
// 自动选择最佳的播放源
class PlaybackSourceSelector {
  Future<String> selectBestPlayUrl(List<String> availableUrls) async {
    // 基于网络延迟、带宽、服务器负载选择最佳源
    return await _selectOptimalSource(availableUrls);
  }
}
```

## 使用场景

### 家庭场景
```
客厅电视: "我想看电影"
├── 本地NAS: 家庭收藏的高清电影
├── 朋友分享: 朋友家NAS的最新电影
├── Plex服务器: 朋友推荐的Plex内容
└── 云盘: 临时下载的电影资源
```

### 社交分享
```
朋友圈媒体分享:
用户A: 分享自己NAS上的动漫收藏
用户B: 添加A的媒体库到自己的聚合列表
用户C: 通过B发现A的收藏，也申请添加
→ 形成媒体内容社交网络
```

### 多设备同步
```
家里: 主NAS + 客厅盒子 + 卧室电视
公司: 办公室NAS
云端: 备份和临时存储
→ 在任何地方都能访问完整的媒体库
```

## 优势总结

### 1. 用户体验
- **一站式访问**: 一个界面管理所有媒体
- **无缝切换**: 自动选择最佳播放源
- **智能推荐**: 跨源内容发现

### 2. 技术优势
- **高可用性**: 单源故障不影响整体使用
- **负载分散**: 自动负载均衡
- **插件化**: 易于扩展新的媒体源

### 3. 社交价值
- **内容分享**: 朋友间媒体库互通
- **发现机制**: 通过社交网络发现新内容
- **协作管理**: 多人共同维护媒体库

这样，NipaPlay就成为了真正的**媒体宇宙中心**，连接一切媒体资源！🌌 