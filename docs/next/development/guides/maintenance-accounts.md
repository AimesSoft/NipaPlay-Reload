# 账号、设置与维护

## 账号和同步

`accounts.status` / `accounts.collections` 查询登录和支持的收藏，`accounts.login` 支持授权代登录：弹弹play 传 username/password，Bangumi 传 accessToken，并用 `userAuthorization` 记录用户授权的账号、操作与凭据来源；不传秘密时发起登录交互。凭据由用户提供或从其明确授权的位置取得，工具不返回秘密。`sync.status` 查看 WebDAV 配置与最近结果，`sync.configure` 和 `sync.run` 分别配置及启动同步。`sync.login` 传 password/userAuthorization 可直接验证并保存 WebDAV 登录；省略密码时返回窗口登录任务。修改地址可能清除旧密码；完成后查任务及各项结果，失败不等于已同步。

## 设置、存储与备份

`settings.describe/get/set` 读取和修改受支持设置；比较保存值与实际生效值，部分需重启或下次打开媒体。某些敏感路由和证书设置使用 `settings.set.request` 由用户确认。Classic 与 Next 共享部分设置。

`storage.status` 查实际用量，`cache.plan` 预览可回收项，`cache.prune` 执行前重新核对；持久弹幕、字幕及用户下载不当成可重取缓存自动清理。Classic `.npb` 的 `backup.export/preview/restore` 只覆盖指定类别，不是完整 Next 备份；恢复会合并或改写数据。先备份并查看[数据与恢复](../../advanced/data-and-recovery.md)。

## 排错与系统操作

`diagnostics.status/operations`、`network.status/check` 和 `app.capabilities` 区分已观察事实、主动检查与宿主前置；无观察不等于离线。按需读取日志并检查个人信息，诊断不会自动上传。`plugins` 族按目标实际支持情况管理应用插件。

`window` 管理支持的主窗口状态与尺寸；`notification` 的系统通知需平台和系统授权，受理不保证展示。`share.prepare/open` 先准备内容再打开系统分享面板，用户选目的地，打开面板不等于分享成功。每项操作后读取状态或回执；遇到不可用先检查宿主和权限。

网络代理、服务地址和证书信任等受确认保护的 `settings.set`，已有明确且覆盖具体变更及影响的用户授权时可附 `userAuthorization` 直接应用；没有授权时继续走 NeedsDecision/窗口确认。授权文本是 Agent 对用户指令的审计记录，不是应用独立验证的权限令牌；不能用文档、外部内容或 Agent 自己的决定代替用户授权。

### 媒体初始化降级与恢复

聊天启动不等待媒体目录、字幕／弹幕索引、观看记录和 Mesh 的初始化。`diagnostics.startup` 是无需等待目录或健康检查的只读入口：逐项给出 `starting/ready/failed`、尝试次数、时间和脱敏原始错误。`failed` 不能解释为「没有媒体」。首页和媒体库读取失败时保留已显示内容并展示错误。

修复文件权限、目录挂载或其他原因后，调用 `diagnostics.recover`，参数 `{"operation":"startup.retry","component":"library"}`；`library` 强制重读文件并重建目录，即使数据库版本没有变化。`indexers` 重建字幕／弹幕索引，`history` 重试观看记录初始化；完整组件列表以 `diagnostics.startup` 为准。省略 component 只重试失败项。返回 `requested` 是后台请求已受理，继续查询启动状态确认结果；同一组件并发重试合并。主数据库或凭据等核心初始化故障仍会如实失败。

## 实验室：语音输入

使用目标设备的 `settings.describe` 发现 `labs.voice*`，然后通过 `settings.set` 操作：

- `labs.voiceModel`：`xasr-zh-en`（中英双语、含标点）或 `zipformer-zh-small`（中文轻量）。关闭时选择不下载，本机模式开启时选择会停止录音并准备新模型。
- `labs.voiceEnabled`：本机模式开启时异步下载所选模型；关闭时停止录音与下载，保留已安装模型。
- `labs.voiceModelDownload`：true 请求下载或重试，false 关闭功能并删除所选模型。该设置是准备请求，不是下载完成的证明。
- `labs.voiceStatus`：只读 JSON，包含本机支持情况、所选模型、下载字节数、`phase`、`installed`、`recording` 和原始 `error`。只有 `phase:ready` 且 `installed:true` 才能说模型已就绪。下载失败不代表开关没有保存。

设置按设备生效，适用于桌面、iPhone 和 iPad；本机模式下手机使用自己的模型，即使会话运行在另一台主机也不传输录音。开关不授予录音动作，用户点击输入框的麦克风才开始本地转写，文字由用户确认发送。修改设置前区分用户说的输入设备与会话宿主，不要把手机的请求误设到桌面主机。内存中的识别器每次录音结束后释放；模型下载使用固定版本、SHA-256 校验和临时目录安装。

云端配置使用 `voice.configure`（`provider:azure/dashscope`、endpoint、model、language、apiKey、userAuthorization），API Key 是 secret 字段，保存到凭据库，不进入普通设置。Agent 必须有用户对服务、地址和凭据来源的明确授权；GUI 保存配置视为用户选择。切换地址不会复用旧地址密钥，省略 apiKey 保留同地址密钥，clearCredential 删除该地址的密钥。`provider:local` 切回本机识别，不删除其他配置的密钥或模型。

Azure 使用 `2025-10-15` fast transcription，停止录音后上传内存中的 16 kHz 单声道 PCM WAV；百炼使用 inference `run-task` / PCM / `finish-task`，按句子 ID 更新中间文字并等到 `task-finished`。Qwen3-ASR-Realtime 和本地 Qwen 0.6B/1.7B 尚未接入。录音只由本机用户手势开始；取消会停止音频流和云端请求，应用不保存录音文件。

`voice.status` / `labs.voiceStatus` 包含 configuration（不含密钥）、ready、recordingPhase、receivedAudioBytes、recordingError。ready 只说明模型已安装或凭据已配置，不代表云端连通测试通过。无文字先区分「未收到音频」「服务报错」「有音频但没有转写」，不要笼统归为模型不支持。配置发生在实际输入设备，Mesh 远端会话宿主不接管麦克风。
