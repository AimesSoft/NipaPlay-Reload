# Y14：设置页接上模型端点和 Codex 运行包

2026-10-16，主控自己实现。worktree `y14-model-ui`。

## 做了什么
- **模型**：
  - “在这里设置”排在前面，提供方、地址、模型、API key 都可以自由填写；
  - 上方两个按钮“DeepSeek”“智谱”只把官方地址和模型名填进去，填完照样能改；
  - 另一选项改名为“已有配置”，即电脑上原有的 Codex 配置。
- **Codex 卡片**：
  - 只在会自己下载 Codex 的宿主上出现（`NextHostRuntimeSettings`）。实验配置不下载 Codex，所以真实模式下看不到这张卡片。
  - 行标题直接是状态：未下载、下载中、校验中、已就绪、没能下载。
  - 副标题是大小、进度、版本或失败原因；按钮是下载、取消、重试。
  - “更多”里可以选运行哪个 Codex（自动下载、系统里的、指定路径），填镜像地址，查看开源许可，移除。
- 运行包状态和模型分开读取，互不阻塞。
- 假数据世界的宿主实现了运行包接口，调试扩展加了 `codex=none|downloading|verifying|ready|failed|path`。

## 验证
- 新测试“Codex is fetched from the Nipa section; templates only fill in”：下载、进度、就绪、移除，以及模板只负责填值。设置页测试 11 项全部通过；`flutter analyze --no-pub lib/next/ui` 无问题。
- 截图（`docs/next/evidence/y14/`）：
  - `none` 未下载；
  - `dl` 下载中；
  - `failed` 失败；
  - `ready` 已就绪；
  - `real` 真实模式下的模型卡片。

## 顺带发现
`/tmp/nipa-next` 在 10-16 00:00 前后被清理掉一部分文件：假数据世界的 `meta.json`、部分图片，以及 TMDB 令牌和弹弹play 测试账号。工作目录已经搬到 `~/.nipa-next`，`/tmp/nipa-next` 现在是指向它的链接。`meta.json` 用剩下的图片和自写的简介重建，只供演示，不进仓库。
