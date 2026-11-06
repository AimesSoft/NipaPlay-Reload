# 已知问题

本页跟随 `next` 分支更新，每条注明出现的版本。反馈时写明版本和构建号（「设置」→「关于」）。

## 当前限制

### 播放器

| 项目 | 版本 | 说明 |
|---|---|---|
| 快捷键 | Alpha 2 | Next 播放器使用固定快捷键，不读取「设置」→「快捷键」 |
| 跳过时间 | Alpha 2 | Classic 的「跳过时间」未接入 Next 播放器 |
| 字体库导入、播放器内匹配弹幕 | Alpha 2 | 界面未完成；弹幕可在剧集菜单「弹幕…」中搜索和添加 |
| 字幕样式 | Alpha 2 | Erika 不支持调整字幕高度；MDK 只应用字幕颜色与粗细 |

### 数据

| 项目 | 版本 | 说明 |
|---|---|---|
| 备份与恢复 | Alpha 1 | 没有完整的产品内备份恢复，按[数据与恢复](../advanced/data-and-recovery.md)备份 |

### 组网

| 项目 | 版本 | 说明 |
|---|---|---|
| 连接方式 | Alpha 1 | 仅支持设备直连，不提供 NAT 穿透和中继；切换网络、睡眠唤醒、长时间播放的表现取决于设备和网络环境 |
| 移动设备 | Alpha 1 | iPhone、iPad 本机不运行梨花，使用其他设备上的梨花，见[多台设备](../use/devices.md#在-ipadiphone-上使用梨花) |

### 梨花

| 项目 | 版本 | 说明 |
|---|---|---|
| DSH 插件参数 | Alpha 1 | 原生插件的参数在运行器重启时校验，见 [DSH 高级配置](../advanced/dsh-config.md) |
| 模型差异 | — | 各模型的工具调用能力和安全策略不同，部分模型会拒绝 BT 资源相关的请求，见[常见问题](faq.md#梨花拒绝帮我下载) |

### 平台

- macOS 和 Windows 为主要验证平台，Linux 构建为实验性质。
- iPhone、iPad：TestFlight 以[发行页](https://github.com/AimesSoft/NipaPlay-Reload/releases)说明为准；GitHub 上的 IPA 未签名，需自行签名侧载。
- 不分发 Android、tvOS 和 HarmonyOS 版本。

## 已修复

### Alpha 4

- 设备地址查询失败不再阻塞本机上报或长期锁住旧地址；设备页可手动「刷新组网」，梨花可调用 `mesh.refresh`。正常离线仍保留低频退避，限流等待不会被刷新绕过。

- Windows 的 Erika 视频画面不再遮住播放控件和菜单。
- 处理外挂字幕开头重复的 UTF-8 BOM；字幕加载失败不再让已打开的视频进入致命错误状态。
- Erika 超分加速使用系统 Vulkan 加载器，减少旧加载器对扩展识别的干扰。

### Alpha 2

- 点击播放后立即进入播放画面，地址解析和组网请求在后台进行。
- 右方向键与 Classic 一致：单击快进，长按按设定倍速播放。
- Erika 成为常规内核选项，无须实验室开关。
- 图片直接随请求发送给模型，服务商不支持时返回错误。
- 收起提醒在本机立即生效。

完整列表见[更新说明](../release-notes.md)。

---

提交 [Bug 报告](https://github.com/AimesSoft/NipaPlay-Reload/issues/new?template=bug_report.yml) 前，按[故障排查](troubleshooting.md)收集诊断信息。

上一篇：[故障排查](troubleshooting.md) · 回到[文档首页](../README.md)
