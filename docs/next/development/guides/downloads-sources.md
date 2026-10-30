# 媒体来源与下载

先在目标设备用 `nipa list`、`describe` 和 `app.capabilities` 核对能力与前置；来源凭据由宿主管理；用户明确授权后，梨花可通过能力配置并登录。

## 来源：事实与选择

- `media.sources.list`、`browse`、`search` 查询已配置来源及目录；`network.status` / `network.check` 查看路由和连接观察。缓存目录不代表实时可播放。
- 先核对来源类型、地址、授权及目标设备，再按 `media.sources` 实时目录配置或同步。`media.sources.login` 可传 `password`（弹弹play 远程用 API token）和 `userAuthorization` 直接登录，用 `task.wait` 检查结果。凭据可由用户提供或从其明确授权的位置取得；不把秘密写入回复、日志或提交到 Git。未提供凭据时仍可使用登录窗口或 Quick Connect。
- 同步是任务，查看 `task.get` / `task.wait` 和来源状态；网络失败、认证失败及无结果应分别报告，不把旧缓存当新结果。

## 下载：预览与执行

- `download.preview` 可预览磁力、种子或 HTTP 文件；`download.add` 创建任务，`download.read` 查看文件、进度、状态和落盘位置。HTTP 使用对应后端；qBittorrent 用 `download.backends.list` 查询，获用户明确授权后用 `download.backends.save` 添加或修改：`name`、`address`、`local`、可选 `id/username/password`、`userAuthorization`。`local` 指 qBittorrent 的文件是否位于目标 NipaPlay 设备。保存后 `list {probe:true}` 检查连接，再把返回的 `backend` 交给 `download.add`。`download.backends.remove` 移除配置及保存的登录，不删除服务器种子或文件。密码不回传，响应丢失先 list 核对是否已保存。
- 确认来源、目录、要下载的文件及存储空间后再添加；`download.select_files` 改变选择，不删除已有数据。内置会话限速查 `download.limits`，不适用于所有后端。
- 文件完成并校验后可登记入库，但身份仍需明确判断和绑定，见[媒体身份](media-identity.md)。`task.get` 与下载回执核对实际完成；发起下载后的文件、停滞和终态可作为后续返回对话。
- `download.remove` 保留文件；删除数据有独立的预览/确认契约，按目标设备 `describe` 和用户决定执行。取消任务不等于删除数据；响应丢失先查任务和回执，勿盲目重复。

### 外部来源的统一管理

Jellyfin、Emby、弹弹play 远程可以直接浏览原始目录。弹弹play 默认全部作品；首次进入来源会登记后台同步任务，界面继续分页加载。`media.sources.browse/sync` 将来源结构和自带资料保存为 Next 的原生作品、季、剧集与元数据快照；`browse` 返回的 `workId/episodeId` 可用于身份绑定、资料覆盖、封面设置和 `media.metadata.ui_facts`。已有文件归属与用户覆盖保留，重新同步不自动重做 Classic 匹配，也不删除源文件。

原生资料的 provider 为 `https://sources.nipaplay.app`，用 `media.sources.sync` 刷新。它保存服务器对该条目的描述；`sourceProviderIds` 和原始 `providerData` 是核实其他平台身份的证据，不代表已经绑定或拉取 TMDB/Bangumi。资料来自服务器时先复用，补缺和跨来源合并仍使用明确的身份操作。Next 的标题、封面与排列调整保存在 Next，不回写外部服务器。
