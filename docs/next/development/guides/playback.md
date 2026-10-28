# 播放、控制与诊断

要让用户观看，先确认目标设备和当前会话；查询状态不会替用户打开视频。使用前查看目标的 `nipa describe playback` 和各 Action schema。

1. 用 `app.instance` 辨认所连接的进程与窗口，`app.capabilities` 查宿主和具体能力；用 `playback.state` 读当前媒体、sessionId、状态和内核。切换设备或重开媒体后重新读取，旧 sessionId 不能代表新会话。
2. 要找片或续播，先查 `media.library.search_merged`、`history.continue_watching` 和 `media.library.readable`。路径与 ID 属于来源设备；远端可读地址可能是接收端临时回环 URL，设备离线时不能当作可播。用户要求播放时才用 `playback.open` 或 `download.play`，并核对目标是否有播放器。
3. 控制当前会话用 `playback.set_paused`、`playback.seek`、`playback.switch_episode`；轨道用 `playback.tracks`、`playback.select_track`。`remember` 等持久化选项以该 Action 的描述为准：临时选轨和记住字幕选择有不同影响。
4. 命令返回只说明请求结果；用同一 sessionId 的 `playback.wait`、`playback.state` 和 `playback.info` 观察 ready、playing、错误与媒体事实。会话已变化则重新取状态，不能把旧会话的结果用在当前播放。

## 内核和设置

`playback.kernel` 报告当前内核、支持的控制、已知属性与覆盖。MDK、Media Kit/mpv、Erika 和 video_player 暴露的属性不同；未报告是 null，不证明不存在。需要调节前先读目标实际支持情况和 `nipa describe playback.set_kernel_properties`。该操作作用于当前播放；`playback.restore_kernel_properties` 恢复可恢复的会话覆盖，`playback.reopen_with_kernel` 会重开媒体。持久默认偏好经 `settings.describe/get/set` 管理，不能把会话覆盖当成永久设置。

`playback.capture` 会写截图或 GIF 文件；先确认用户意图与目标路径，回执中的弹幕包含情况是捕获事实，并不证明画面中此刻有可见弹幕。`ui.capture` 截的是应用窗口，有平台和原生视频层限制，不能当作其他应用或外部播放器的截图。

播放失败时先查 `playback.failures`、`diagnostics.player_log` 和实际内核事实；`playback.retry` 会重建当前内部播放，使用前确认 sessionId 和影响。未知解码或缓冲原因如实保留，不从缺失日志猜测。远程调用遇到 `outcome_unknown` 时先查目标会话、任务和过程事实；没有幂等契约的写入不自动重做。

实现参考：[播放状态与控制](../../../../lib/next/capabilities/playback_capability.dart)、[播放观察](../../../../lib/next/capabilities/playback_inspection.dart)、[内核控制](../../../../lib/next/capabilities/kernel_control.dart)。
