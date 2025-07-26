# NipaPlay-Reload: Jellyfin 集成详细说明

本文档详细说明了 NipaPlay-Reload 应用中 Jellyfin 媒体服务器的集成方案，以及如何与 DandanPlay 弹幕系统协同工作。

## 1. 引言

Jellyfin 集成的目标是允许用户连接到他们自己的 Jellyfin 服务器，浏览、管理和播放在 Jellyfin 上托管的媒体内容（当前主要支持电视剧集），并结合应用现有的 DandanPlay 弹幕匹配功能，为用户提供丰富的观看体验。

## 2. 核心架构

集成的核心架构围绕以下组件构建，以实现从用户界面交互到媒体播放的完整流程：

```mermaid
graph TD
    A[UI Layer (Pages/Widgets)] --> B{JellyfinProvider (State)};
    A --> C{JellyfinDandanplayMatcher};
    B --> D[JellyfinService (API)];
    C --> D;
    C --> E[DandanplayService (API)];
    D -- Stream URL --> F[VideoPlayerState];
    C -- WatchHistoryItem (jellyfin://) --> F;
    G[Data Models (Jellyfin/WatchHistory)] <--> D;
    G <--> C;
    B <--> G;

    subgraph 用户界面
        A
    end
    subgraph 状态管理
        B
    end
    subgraph 服务层
        C
        D
        E
    end
    subgraph 数据模型
        G
    end
    subgraph 播放引擎
        F
    end
```

**组件说明:**

-   **UI Layer (用户界面层)**: 包括 `JellyfinDetailPage`、`JellyfinMediaLibraryView`、`JellyfinServerDialog` 以及 `AnimePage` 中集成的 Jellyfin 标签页。负责用户交互和数据显示。
-   **JellyfinProvider (状态管理)**: (`lib/providers/jellyfin_provider.dart`) 负责管理 Jellyfin 相关的全局状态，如连接状态、服务器信息、可用媒体库、已选媒体库、缓存的媒体数据，并通知 UI 更新。
-   **JellyfinDandanplayMatcher (核心匹配服务)**: (`lib/services/jellyfin_dandanplay_matcher.dart`) 核心逻辑处理器，负责创建可播放的 `WatchHistoryItem`，将 Jellyfin 媒体与 DandanPlay 内容进行匹配以获取弹幕，处理用户的手动匹配选择，并预计算视频文件哈希。
-   **JellyfinService (Jellyfin API 服务)**: (`lib/services/jellyfin_service.dart`) 封装了与 Jellyfin 服务器的所有 HTTP API 交互，包括身份验证、获取媒体库、媒体项、剧集详情、生成流媒体 URL 和图片 URL 等。
-   **DandanplayService (弹弹play API 服务)**: (`lib/services/dandanplay_service.dart`) 提供与 DandanPlay API 的交互功能，用于搜索动画、匹配弹幕。
-   **VideoPlayerState (播放引擎)**: (`lib/utils/video_player_state.dart`) 负责实际的视频播放控制。它接收 `WatchHistoryItem` (使用 `jellyfin://` 协议作为 Jellyfin 媒体的唯一标识) 和实际的 HTTP(S) 流 URL 进行播放。
-   **Data Models (数据模型)**: 包括 `lib/models/jellyfin_model.dart` 中定义的 Jellyfin 相关实体，以及 `lib/models/watch_history_model.dart` 中的 `WatchHistoryItem`，后者已适配以支持 Jellyfin 内容。

## 3. 关键组件详解

### 3.1 JellyfinService (`lib/services/jellyfin_service.dart`)

-   **职责**:
    -   连接与认证：处理到 Jellyfin 服务器的连接、用户登录和 `accessToken` 的获取与存储（使用 `shared_preferences`）。
    -   数据获取：从 Jellyfin 服务器拉取媒体库列表、指定库中的媒体项目（如电视剧）、媒体项目的详细信息（元数据、演员、工作室等）、电视剧的季节和剧集列表。
    -   URL 生成：为选定的媒体剧集生成可播放的流媒体 URL，以及为封面、背景图等生成图片 URL。
    -   状态维护：内部维护连接状态和已加载的可用库信息。

### 3.2 JellyfinProvider (`lib/providers/jellyfin_provider.dart`)

-   **职责**:
    -   状态管理：作为 Jellyfin 连接状态、服务器凭据、已选媒体库 ID 列表的单一数据源。
    -   数据缓存与分发：缓存从 `JellyfinService` 获取的媒体库、媒体项目等数据，供 UI 组件消费。
    -   UI 通知：当 Jellyfin 相关状态（如连接成功、媒体库更新）发生变化时，通知监听的 UI 组件进行刷新。
    -   持久化：负责将服务器配置和选定的库 ID 持久化到 `shared_preferences`。

### 3.3 JellyfinDandanplayMatcher (`lib/services/jellyfin_dandanplay_matcher.dart`)

-   **职责**:
    -   创建可播放项：将 `JellyfinEpisodeInfo` 转换为包含播放所需全部信息的 `WatchHistoryItem`。
    -   弹幕匹配：获取 Jellyfin 剧集的元数据（如标题、文件名、文件大小、预计算的视频哈希），调用 `DandanplayService` 进行弹幕匹配。
    -   用户交互：当自动匹配结果不唯一或不确定时，弹出 `AnimeMatchDialog` 供用户手动选择正确的动画和剧集。
    -   哈希计算：能够预先计算 Jellyfin 视频文件的哈希值，用于精确匹配弹幕。
    -   播放 URL 获取：通过 `JellyfinService` 获取最终的流媒体 URL。

### 3.4 UI 组件

-   **`JellyfinServerDialog` (`lib/widgets/jellyfin_server_dialog.dart`)**:
    -   允许用户输入 Jellyfin 服务器地址、用户名、密码进行连接。
    -   连接成功后，展示可用的媒体库供用户选择，并将选择持久化。
-   **`JellyfinMediaLibraryView` (`lib/widgets/jellyfin_media_library_view.dart`)**:
    -   在 `AnimePage` 的 "Jellyfin" 标签页中显示。
    -   通过 `JellyfinProvider` 获取已连接 Jellyfin 服务器上选定媒体库中的电视剧集，并以卡片形式展示。
    -   支持点击媒体卡片导航到详情页。
-   **`JellyfinDetailPage` (`lib/pages/jellyfin_detail_page.dart`)**:
    -   展示特定 Jellyfin 电视剧的详细信息（海报、简介、演员、季节列表、剧集列表等）。
    -   用户可在此页面选择特定剧集进行播放。

### 3.5 VideoPlayerState (`lib/utils/video_player_state.dart`)

-   **Jellyfin 流处理**:
    -   `VideoPlayerState` 通过其播放逻辑接收一个 `WatchHistoryItem`。对于 Jellyfin 内容，该 `WatchHistoryItem` 的 `filePath` 字段会使用 `jellyfin://<itemId>` 格式的伪协议作为唯一标识。
    -   实际播放时，`VideoPlayerState` 会使用由 `JellyfinDandanplayMatcher` 或调用方提供的、通过 `JellyfinService.getStreamUrl()` 获取的真实 HTTP(S) 流 URL。
    -   弹幕加载依赖于 `WatchHistoryItem` 中由 `JellyfinDandanplayMatcher` 填充的弹幕 ID 和视频哈希。

## 4. 数据模型与转换

### 4.1 Jellyfin 模型 (`lib/models/jellyfin_model.dart`)

定义了与 Jellyfin API 交互所需的各种数据结构：
-   `JellyfinLibrary`: Jellyfin 媒体库信息。
-   `JellyfinMediaItem`: Jellyfin 媒体项目（如电视剧系列、电影）。
-   `JellyfinMediaItemDetail`: 媒体项目的详细信息。
-   `JellyfinSeasonInfo`: 电视剧的季节信息。
-   `JellyfinEpisodeInfo`: 电视剧的单集信息。
-   `JellyfinPerson`: 演职员信息。

### 4.2 WatchHistoryItem 适配 (`lib/models/watch_history_model.dart`)

为了将 Jellyfin 媒体集成到现有的观看历史和播放流程中，`WatchHistoryItem` 进行了适配：
-   `filePath`: 对于 Jellyfin 内容，存储格式为 `jellyfin://<JellyfinEpisodeId>`，作为其在应用内的唯一标识。
-   `videoHash`: 新增字段，存储视频文件的哈希值，用于更精确的弹幕匹配。
-   其他字段（如 `animeName`, `episodeTitle`, `duration`）会从 Jellyfin 数据中填充。

### 4.3 关键转换逻辑

-   **`JellyfinEpisodeInfo.toWatchHistoryItem()`**:
    -   此方法（或类似逻辑存在于 `JellyfinDandanplayMatcher` 中）负责将从 Jellyfin API 获取的 `JellyfinEpisodeInfo` 对象转换为一个基础的 `WatchHistoryItem` 对象。
    -   它会填充标题、剧集号、Jellyfin ID (作为 `filePath` 的一部分)、时长（runTimeTicks 转换）等信息。
-   **`JellyfinDandanplayMatcher.createPlayableHistoryItem()`**:
    -   这是核心的转换和组装方法。它接收一个 `JellyfinEpisodeInfo`。
    -   调用 `JellyfinService` 获取更详细的媒体信息和文件哈希（如果需要）。
    -   调用 `DandanplayService` 进行弹幕匹配。
    -   最终构建一个完整的 `WatchHistoryItem`，包含所有播放和历史记录所需的信息：`jellyfin://` 路径、弹幕 ID、视频哈希、媒体元数据等。

## 5. 核心流程

### 5.1 Jellyfin 服务器连接与配置流程

1.  用户通过设置界面或媒体库的提示，打开 `JellyfinServerDialog`。
2.  用户输入服务器 URL、用户名和密码，点击连接。
3.  `JellyfinServerDialog` 调用 `JellyfinProvider` (或直接 `JellyfinService`) 的连接方法。
4.  `JellyfinService` 向 Jellyfin 服务器发送认证请求。
5.  成功后，`JellyfinService` 获取可用的媒体库列表。
6.  `JellyfinProvider` 更新其状态（连接成功、服务器信息、可用库列表），并通知 `JellyfinServerDialog` 更新 UI。
7.  用户在对话框中选择要使用的媒体库。
8.  `JellyfinProvider` 保存用户选择的库 ID，并持久化服务器配置。

### 5.2 媒体浏览与详情查看流程

1.  用户切换到 `AnimePage` 内的 "Jellyfin" 标签页，显示 `JellyfinMediaLibraryView`。
2.  `JellyfinMediaLibraryView` 检查 `JellyfinProvider` 的连接状态。
3.  如果已连接且已选择库，它会请求 `JellyfinProvider` (其内部调用 `JellyfinService`) 加载所选库中的媒体项目。
4.  获取到的 `JellyfinMediaItem` 列表在 `JellyfinMediaLibraryView` 中以卡片形式展示。
5.  用户点击某个媒体卡片。
6.  应用导航到 `JellyfinDetailPage`，并传递所选媒体的 Jellyfin ID。
7.  `JellyfinDetailPage` 使用此 ID，通过 `JellyfinService` 获取该媒体的完整详情（包括季节和剧集列表）并展示。

### 5.3 Jellyfin 媒体播放流程

1.  用户在 `JellyfinDetailPage` 中选择一个剧集进行播放。
2.  调用 `JellyfinDandanplayMatcher.createPlayableHistoryItem()`，传入选定的 `JellyfinEpisodeInfo`。
3.  **Matcher 内部**:
    a.  (可选) 调用 `JellyfinService` 获取该剧集的最新详细信息或特定元数据（如文件路径用于哈希计算）。
    b.  计算视频文件哈希值（如果尚未缓存）。这可能需要 `JellyfinService` 提供媒体源信息。
    c.  使用剧集标题、文件名、哈希等信息，调用 `DandanplayService` 的匹配 API。
    d.  如果匹配不唯一或失败，显示 `AnimeMatchDialog` 供用户手动选择。
    e.  构建 `WatchHistoryItem`：
        -   `filePath`: `jellyfin://<JellyfinEpisodeId>`
        -   `videoHash`: 计算得到的哈希值
        -   `episodeId` (弹幕库中的剧集 ID), `animeId` (弹幕库中的动画 ID)
        -   其他元数据如 `animeName`, `episodeTitle`, `duration`。
4.  `JellyfinDandanplayMatcher` 返回构建好的 `WatchHistoryItem`。
5.  播放启动逻辑 (通常在 `JellyfinDetailPage` 或 `AnimePage` 的回调中) 获取实际的流媒体 URL：调用 `JellyfinService.getStreamUrl(episode.id)`。
6.  使用 `VideoPlayerState.play()` 方法启动播放，传入 `WatchHistoryItem` (用于历史记录、状态跟踪和弹幕加载) 和上一步获取的实际流媒体 URL。
7.  `VideoPlayerState` 初始化播放器，加载视频流，并根据 `WatchHistoryItem` 中的弹幕信息加载弹幕。

## 6. 错误处理

-   **连接错误**: 在 `JellyfinServerDialog` 和 `JellyfinService` 中处理网络请求失败、认证失败等情况，并向用户显示合适的错误提示。
-   **数据加载错误**: 在 `JellyfinProvider` 或各 UI 组件中，处理从 Jellyfin 获取数据（如媒体列表、详情）失败的情况，显示加载失败或空状态提示。
-   **弹幕匹配失败**: 如果 `JellyfinDandanplayMatcher` 无法成功匹配到弹幕（无论是自动还是手动），视频仍然可以播放，但不会加载弹幕。用户会收到相应提示。
-   **流媒体错误**: `VideoPlayerState` 处理播放过程中可能出现的流媒体加载失败、解码错误等，并显示错误信息。

## 7. 后续优化方向

1.  **增强弹幕缓存机制**: 为 Jellyfin 匹配到的弹幕信息实现更持久和智能的缓存，减少重复的 API 请求。
2.  **优化匹配算法**: 持续优化 `JellyfinDandanplayMatcher` 中的匹配逻辑，提高自动匹配的准确度和召回率。
3.  **用户反馈与学习**: 考虑记录用户的手动弹幕匹配选择，用于未来改进自动匹配算法或提供个性化推荐。
4.  **离线播放支持**: 探索对 Jellyfin 媒体的下载和离线播放支持（需要 Jellyfin 服务器支持及客户端实现）。
5.  **更广泛的媒体类型支持**: 目前主要集中在电视剧，未来可以扩展到电影、音乐等其他 Jellyfin 支持的媒体类型。
6.  **实时同步**: 实现与 Jellyfin 服务器的播放状态（如播放进度、已观看标记）的双向同步。
7.  **性能优化**: 针对大量媒体库项目的情况，优化数据加载、处理和显示的性能。

---
*文档更新于: 2025年5月27日*
