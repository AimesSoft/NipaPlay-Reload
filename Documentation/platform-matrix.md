# 平台能力矩阵

本文区分“可以构建”“有可分发包”和“已完成真机验收”。平台列表中的“支持”不代表所有硬解、HDR、字幕、弹幕或远程功能都具备完全一致的行为。Erika 已覆盖所有当前原生客户端平台，**仅 Linux 不支持 Erika**；电视设备（包括 tvOS）则由工厂强制使用 Erika。

| 平台 | 获取方式 | 默认/推荐内核 | Erika 状态 | HDR/高阶渲染 | 说明 |
|---|---|---|---|---|---|
| Windows x64 | GitHub Release / Microsoft Store | Media Kit（libmpv）、Erika 或 MDK | 支持 | D3D11 路径，设备相关 | Release 会准备完整 libmpv；遇到格式问题可切换内核 |
| Windows ARM64 | GitHub Release（若该版本提供） | Erika、Media Kit（libmpv）或 MDK | 支持 | D3D11/WGPU 路径，设备相关 | 不要把 x64 DLL 复制到 ARM64 安装中 |
| macOS Intel/Apple Silicon | GitHub Release / Homebrew | Erika 或 Media Kit（libmpv） | 支持 | Metal、HDR/EDR、ArtCNN 路径 | Erika 是 macOS 的主要高阶路径 |
| Linux amd64/arm64 | GitHub Release | Media Kit（libmpv）或 MDK | **不支持** | 取决于发行版、驱动和渲染器 | Linux 是当前唯一不支持 Erika 的原生客户端平台 |
| Android | GitHub Release APK | Erika、Media Kit（libmpv）或 MDK | 支持 | Vulkan/TextureView/SurfaceView；HDR 需真机验证 | API、GPU、厂商解码器差异较大 |
| iOS | App Store / TestFlight / 自签名 | Erika | 可用 | Metal、HDR/EDR、原生 surface | 侧载包的签名有效期由 Apple 账号决定 |
| tvOS | 开发者预览、源码构建、侧载 | **Erika（强制，唯一选项）** | 支持 | Metal；真机能力需逐版本验收 | 需要 Xcode、tvOS 签名和项目指定 Flutter fork |
| HarmonyOS | 源码构建 HAP | Erika、Media Kit（libmpv）或 MDK | 支持 | Vulkan/OHOS surface；缺能力时回退 | 需要 DevEco Studio、Native SDK 和开发者签名 |

## 验收维度

提交平台相关改动时，至少记录以下结果：

- 本地文件播放、HTTP/HTTPS 播放和媒体服务器播放；
- 硬件解码是否启用，以及软件回退是否可用；
- ASS/SRT/WebVTT 字幕、多音轨和外挂字幕；
- 弹幕数量较大时的帧率、遮挡和字体回退；
- 截图、画中画、媒体控制、后台音频和外部播放器；
- HDR/EDR（若平台有显示设备）和窗口/旋转/尺寸变化；
- 远程控制、Web server 和网络断开后的错误提示。

测试报告应标明设备型号、系统版本、Flutter 版本、NipaPlay commit、Erika commit 或 prebuilt tag。没有真机验证时，应写“可构建”或“待验收”，不要写“完全支持”。

## Erika 集成版本边界

NipaPlay 使用固定的 Erika release pin，而桌面上的 Erika 仓库可能领先于该版本。更新内核时必须同时更新依赖 pin、平台产物和变更记录；不能只在本地 Erika 仓库构建成功后就假设 NipaPlay 已完成集成。
