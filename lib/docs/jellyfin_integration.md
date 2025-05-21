# Jellyfin 与 DandanPlay 集成实现说明

本文档详细说明了 NipaPlay-Reload 应用中 Jellyfin 媒体与 DandanPlay 弹幕系统的集成实现。

## 1. 架构概述

该集成方案采用了以下架构：

```
JellyfinDetailPage -> JellyfinDandanplayMatcher -> VideoPlayerState
       |                       |                         |
       v                       v                         v
JellyfinService         DandanplayService      VideoPlayerStateExtension
```

- **JellyfinDetailPage**: 用户界面，展示 Jellyfin 媒体详情和剧集列表，用户可以选择剧集进行播放
- **JellyfinDandanplayMatcher**: 核心服务，负责将 Jellyfin 媒体匹配到 DandanPlay 的内容，获取弹幕和元数据
- **JellyfinService**: 提供与 Jellyfin 服务器交互的功能
- **DandanplayService**: 提供与 DandanPlay API 交互的功能
- **VideoPlayerState**: 视频播放状态管理
- **VideoPlayerStateExtension**: 扩展 VideoPlayerState，提供对流媒体 URL 的特殊处理

## 2. 关键类与功能

### 2.1 JellyfinDandanplayMatcher

该服务负责：
- 创建可播放的历史记录项
- 获取 Jellyfin 媒体的流媒体 URL
- 使用 DandanPlay API 匹配内容，获取弹幕 ID
- 处理用户的匹配选择

### 2.2 JellyfinService

该服务负责：
- 连接、认证 Jellyfin 服务器
- 获取媒体库列表
- 获取媒体项目详情、季节、剧集信息
- 生成流媒体 URL
- 处理图片 URL

### 2.3 VideoPlayerStateExtension

扩展功能：
- 提供专门用于播放流媒体 URL 的方法
- 添加对 Jellyfin 流媒体的特殊处理
- 增强错误处理，添加网络检查

## 3. 数据模型

### 3.1 Jellyfin 模型
- **JellyfinLibrary**: Jellyfin 媒体库
- **JellyfinMediaItem**: Jellyfin 媒体项目（电视剧、电影）
- **JellyfinMediaItemDetail**: 媒体详情，包含更多元数据
- **JellyfinSeasonInfo**: 季节信息
- **JellyfinEpisodeInfo**: 剧集信息
- **JellyfinPerson**: 人员信息（演员、导演）

### 3.2 数据转换
- `JellyfinEpisodeInfo.toWatchHistoryItem()`: 将 Jellyfin 剧集转换为观看历史记录项
- `createPlayableHistoryItem()`: 创建带有 DandanPlay 元数据的可播放历史记录项

## 4. 播放流程

1. 用户在 JellyfinDetailPage 选择剧集
2. 调用 JellyfinDandanplayMatcher.createPlayableHistoryItem() 创建历史记录项
   - 尝试使用 DandanPlay API 匹配内容，获取弹幕 ID
   - 如果有多个匹配结果，显示选择对话框
3. 获取流媒体 URL
4. 使用 VideoPlayerState 初始化播放器
5. 开始播放

## 5. 错误处理

- 如果 DandanPlay 匹配失败，仍然可以播放视频，但没有弹幕
- 如果网络连接失败，提供适当的错误消息
- 如果流媒体 URL 无效，提供详细的错误信息

## 6. 测试工具

提供了用于测试集成功能的工具：
- **JellyfinIntegrationTester**: 提供测试 Jellyfin 连接、DandanPlay 匹配和完整工作流的方法
- **JellyfinTestPanel**: 提供用户界面，执行各种测试

## 后续优化方向

1. 增强弹幕缓存机制，减少重复请求
2. 优化匹配算法，提高匹配准确度
3. 添加用户反馈机制，当自动匹配失败时记录用户的手动选择
4. 添加离线播放支持，缓存 Jellyfin 媒体
