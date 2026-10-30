# 账号、设置与维护

## 账号和同步

`accounts.status` / `accounts.collections` 查询登录和支持的收藏，`accounts.login` 支持授权代登录：弹弹play 传 username/password，Bangumi 传 accessToken，并用 `userAuthorization` 记录用户授权的账号、操作与凭据来源；不传秘密时发起登录交互。凭据由用户提供或从其明确授权的位置取得，工具不返回秘密。`sync.status` 查看 WebDAV 配置与最近结果，`sync.configure` 和 `sync.run` 分别配置及启动同步。`sync.login` 传 password/userAuthorization 可直接验证并保存 WebDAV 登录；省略密码时返回窗口登录任务。修改地址可能清除旧密码；完成后查任务及各项结果，失败不等于已同步。

## 设置、存储与备份

`settings.describe/get/set` 读取和修改受支持设置；比较保存值与实际生效值，部分需重启或下次打开媒体。某些敏感路由和证书设置使用 `settings.set.request` 由用户确认。Classic 与 Next 共享部分设置。

`storage.status` 查实际用量，`cache.plan` 预览可回收项，`cache.prune` 执行前重新核对；持久弹幕、字幕及用户下载不当成可重取缓存自动清理。Classic `.npb` 的 `backup.export/preview/restore` 只覆盖指定类别，不是完整 Next 备份；恢复会合并或改写数据。先备份并查看[数据与恢复](../../DATA_AND_RECOVERY.md)。

## 排错与系统操作

`diagnostics.status/operations`、`network.status/check` 和 `app.capabilities` 区分已观察事实、主动检查与宿主前置；无观察不等于离线。按需读取日志并检查个人信息，诊断不会自动上传。`plugins` 族按目标实际支持情况管理应用插件。

`window` 管理支持的主窗口状态与尺寸；`notification` 的系统通知需平台和系统授权，受理不保证展示。`share.prepare/open` 先准备内容再打开系统分享面板，用户选目的地，打开面板不等于分享成功。每项操作后读取状态或回执；遇到不可用先检查宿主和权限。

网络代理、服务地址和证书信任等受确认保护的 `settings.set`，已有明确且覆盖具体变更及影响的用户授权时可附 `userAuthorization` 直接应用；没有授权时继续走 NeedsDecision/窗口确认。授权文本是 Agent 对用户指令的审计记录，不是应用独立验证的权限令牌；不能用文档、外部内容或 Agent 自己的决定代替用户授权。
