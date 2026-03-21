# 2. 探索项目结构

欢迎来到 NipaPlay-Reload 的代码世界！第一次看到这么多文件和文件夹可能会让你感到有些困惑，但这很正常。本章节会像一张更贴近真实代码的地图，帮你快速抓住项目的几条主线。

当你用 VS Code 打开项目并让 Codex 一起辅助阅读时，请优先关注 `lib` 文件夹。应用绝大部分的产品逻辑、播放器状态、主题 UI 和服务集成，都在这里。

## 先记住这 4 条主线

如果你只想先理解最重要的架构，请先抓住下面这 4 条线：

1.  `lib/main.dart`: 应用启动入口，负责初始化和注册全局 Provider。
2.  `lib/themes/`: 真正的页面和组件 UI，大量界面实现都分主题放在这里。
3.  `lib/utils/video_player_state.dart` 与 `lib/utils/video_player_state/`: 播放器状态中心，几乎所有播放行为都会经过它。
4.  `lib/player_abstraction/` 与 `lib/danmaku_abstraction/`: 可插拔内核层，让我们可以切换播放器与弹幕实现。

你可以把它理解成：

*   `themes/` 是“你看到的界面”
*   `VideoPlayerState` 是“控制播放的一层总调度”
*   `player_abstraction/` 和 `danmaku_abstraction/` 是“真正对接底层内核的一层适配器”

## `lib` 文件夹：项目核心分层

下面是最值得优先认识的目录：

*   `lib/main.dart`
    *   应用启动入口。
    *   这里会注册很多 `ChangeNotifierProvider`，例如 `VideoPlayerState`、`SettingsProvider`、媒体服务器 Provider、主题 Provider 等。
    *   如果你想知道“某个全局状态是从哪里注入到整个应用里的”，通常先看这里。

*   `lib/themes/`
    *   当前项目很多实际 UI 实现都按主题放在这里，最主要的是：
        *   `lib/themes/nipaplay/`
        *   `lib/themes/cupertino/`
    *   同一个功能在不同主题下，可能有不同页面和控件实现。
    *   如果你在 `lib/pages/` 没找到完整页面，就继续到 `themes/` 里找。

*   `lib/pages/`
    *   这里更多是页面入口、共享页面、路由承载页，或者主题之外的通用页面。
    *   比如主页相关页面、播放承载页、媒体服务器详情页等。

*   `lib/utils/video_player_state.dart`
    *   这是整个项目里最值得重点认识的文件之一。
    *   `VideoPlayerState` 是一个巨大的状态协调器，负责把“页面按钮点击”“播放器内核行为”“弹幕”“字幕”“截图”“时间轴预览”“串流”“导航”等多个模块串在一起。
    *   你可以把它看成“播放页的大脑”。

*   `lib/utils/video_player_state/`
    *   因为 `VideoPlayerState` 的职责非常多，项目把它拆成了多个 `part` 文件。
    *   这些文件大致按职责分工：
        *   `video_player_state_initialization.dart`: 初始化和启动流程
        *   `video_player_state_player_setup.dart`: 播放器实例与参数配置
        *   `video_player_state_playback_controls.dart`: 播放/暂停/跳转/速度等控制
        *   `video_player_state_danmaku.dart`: 弹幕加载与交互
        *   `video_player_state_subtitles.dart`: 字幕管理
        *   `video_player_state_timeline_preview.dart`: 时间轴预览
        *   `video_player_state_capture.dart`: 截图与画面捕获
        *   `video_player_state_streaming.dart`: 串流/远程播放相关逻辑
        *   `video_player_state_navigation.dart`: 页面跳转与返回行为
        *   `video_player_state_lifecycle.dart`: 生命周期与资源释放
        *   `video_player_state_preferences.dart`: 用户偏好与播放设置
        *   `video_player_state_metadata.dart`: 媒体信息与元数据处理
    *   当你碰到“播放页某个行为不对”，大概率应该先来这里排查。

*   `lib/player_abstraction/`
    *   这是播放器抽象层。
    *   关键文件包括：
        *   `abstract_player.dart`: 定义统一播放器接口
        *   `player_abstraction.dart`: 暴露给上层使用的统一入口
        *   `player_factory.dart`: 根据设置选择具体内核
        *   `mdk_player_adapter.dart`
        *   `media_kit_player_adapter.dart`
        *   `video_player_adapter.dart`
    *   这层的意义是：UI 和 `VideoPlayerState` 不直接依赖某个具体播放器 SDK，而是通过统一接口工作。这样我们才能支持 FVP(MDK)、Media Kit(libmpv)、Video Player 等不同内核。

*   `lib/danmaku_abstraction/`、`lib/danmaku_gpu/`、`lib/danmaku_next/`
    *   这是弹幕系统的核心区域。
    *   `danmaku_abstraction/` 负责定义统一的数据结构和渲染抽象。
    *   `danmaku_gpu/` 负责 GPU 渲染相关实现。
    *   `danmaku_next/` 是当前项目很重要的一套弹幕逻辑实现。

*   `lib/services/`
    *   处理外部交互和“脏活累活”，例如网络请求、弹弹play、Jellyfin/Emby/WebDAV、日志、文件选择、播放同步等。
    *   如果你要改的是“和外部服务打交道”的逻辑，优先看这里。

*   `lib/providers/`
    *   放全局可观察状态，例如设置、主题、媒体服务器账号、转码参数等。
    *   一般负责“页面设置项”和“全局数据”之间的连接。

*   `lib/models/`
    *   数据模型定义，例如媒体信息、观看历史、转码设置等。

*   `lib/widgets/`
    *   共享组件、覆盖层、弹幕容器、上下文菜单等通用部件。

## 从“点击播放”到“真正开始播放”的大致调用链

理解项目最有效的方式，不是死记目录，而是跟着一条真实调用链走一遍。下面是一个简化版思路：

1.  页面层 (`pages/` 或 `themes/.../pages/`) 响应用户操作，比如点击视频卡片或播放按钮。
2.  页面把请求交给 `VideoPlayerState`。
3.  `VideoPlayerState` 根据当前设置决定要用哪个播放器内核、是否加载字幕/弹幕、是否应用预缓存和偏好设置。
4.  `PlayerFactory` 在 `player_abstraction/` 中创建具体播放器适配器，例如 MDK、Media Kit 或 Video Player。
5.  播放过程中，UI 组件继续订阅 `VideoPlayerState` 的变化来刷新按钮、时间轴、弹幕和字幕。

这也是为什么很多“看起来像 UI Bug”的问题，最后会落到 `VideoPlayerState` 或 `player_abstraction/`。

## 遇到不同需求时，优先去哪里找

如果你接到一个任务，不妨按下面这个思路找入口：

*   **改页面布局、文案、交互样式**:
    *   优先看 `lib/themes/nipaplay/` 或 `lib/themes/cupertino/`

*   **改播放逻辑、播放状态、时间轴、截图、弹幕开关**:
    *   优先看 `lib/utils/video_player_state.dart`
    *   再看 `lib/utils/video_player_state/`

*   **改播放器内核选择、解码、底层播放能力**:
    *   优先看 `lib/player_abstraction/`

*   **改弹幕加载、渲染、轨道或引擎切换**:
    *   优先看 `lib/danmaku_abstraction/`
    *   再看 `lib/danmaku_gpu/` 与 `lib/danmaku_next/`

*   **改设置项持久化、主题、账号、媒体服务器逻辑**:
    *   优先看 `lib/providers/` 和 `lib/services/`

## 一个简单的例子

假设我们想修改主页上视频卡片的显示样式。根据上面的介绍，你应该能猜到修改流程：

1.  先打开 `lib/pages/dashboard_home_page.dart`，看看主页入口是怎么组织的。
2.  继续顺着引用找到具体卡片组件，例如 `lib/themes/nipaplay/widgets/anime_card.dart`。
3.  如果你想支持另一套主题，再去看 `lib/themes/cupertino/widgets/cupertino_anime_card.dart`。
4.  如果卡片展示的数据本身不对，再继续追到 `models/`、`providers/` 或 `services/`。

## 如何用 Codex 帮你快速建立全局认知？

当你对某一段代码感到困惑时，不要只问“这段代码做了什么”，更推荐你让 Codex 帮你建立结构化理解。你可以这样提问：

1.  **先问架构**:
    *   “请阅读 `lib/main.dart`、`lib/utils/video_player_state.dart` 和 `lib/player_abstraction/player_factory.dart`，用中文总结播放器架构。”
2.  **再问调用链**:
    *   “如果用户在播放页切换播放器内核，调用链通常会经过哪些文件？”
3.  **最后问落点**:
    *   “我想改字幕开关的行为，最可能需要修改哪几个文件？请按优先级列出来。”

这种问法通常比“帮我解释整个仓库”有效得多，也更容易得到靠谱答案。

## 总结

现在你应该已经对 NipaPlay-Reload 的项目结构有了更贴近实战的认识。请优先记住这句话：

**UI 在 `themes/`，播放核心在 `VideoPlayerState`，底层能力在 `player_abstraction/` 和弹幕相关抽象层。**

只要先抓住这条线，大多数需求都能快速找到切入点。

在下一章节，我们将正式开始讲解如何进行一次完整的代码贡献流程。

---

**⬅️ 上一篇: [1. 准备你的开发环境](01-Environment-Setup.md)** | **➡️ 下一篇: [3. 贡献代码的标准流程](03-How-To-Contribute.md)**
