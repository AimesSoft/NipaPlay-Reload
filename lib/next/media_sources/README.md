# 媒体来源

来源能力复用 Classic 的配置、保险库与客户端，注册在 NextCore。
`media.sources.list` 不联网、不读取凭据；`check` 显式验证一个来源。
`media.sources.search {query,sourceIds?,limit?}` 只读搜索；Jellyfin/Emby 经原客户端
的有界服务器 SearchTerm，SMB/WebDAV 仅查已有文件索引，不枚举或登记新文件。
每个来源独立返回 entries/total 或 error，错误时 total=null；共享保留索引结果，
connected/unverified/failed 表示最近连接观察，未知不是在线。来源默认每组最多 12。
已绑定条目带 Next workId/episodeId；服务器未绑定条目给原样 sourceWorkId/
sourceEpisodeId，共享未绑定文件用 media.sources.play {sourceId,itemId}。
搜索条目另带本机缓存 `poster` 和已绑定作品的 `workTitle`，无缓存为 null，搜索不下载图片。
`media.sources.artwork {sourceId,itemId}` 显式懒加载海报，经 X48 的原认证客户端落到
本机缓存后只返回路径，不返回带认证的地址。宿主未接入图片供应者则返回 unavailable。
能力族契约见 `nipa describe media.sources`，界面接线见 `docs/next/X56_REPORT.md`。
`add/update` 配置地址与用户名，`login` 独立发起登录。

登录默认选择 Jellyfin Quick Connect（启用时），否则打开应用内密码窗口。
`media.sources.login` 支持用户授权后的密码或 API token 登录：传 `password` 和记录实际用户指令的 `userAuthorization`；凭据可由用户提供或从其明确授权的位置取得。应用审计脱敏，任务与回执不保存密码；用 `task.wait` 确认结果。不传密码时仍可使用窗口或 Quick Connect。
Quick Connect 另返回 code，批准等待、同步都使用现有 tasks.wait/cancel。
验证码批准期限十分钟；窗口取消也会取消任务。

`libraries/select` 管理媒体库范围，未选择时默认全部。弹弹play 远程直接展示全部作品，不提供逐作品显示开关。首次进入原生服务器来源会登记后台目录同步，前台按页浏览。
Jellyfin/Emby parentId 为远端库/文件夹/系列/季 ID；recursive=true 返回可播放条目。
SMB/WebDAV parentId 为来源内目录路径。共享来源省略 parentId 列作品，
整数为作品 ID，其他值为远端宿主目录路径（包括 Windows 路径）。
`browse/sync` 发现并登记文件，同时保存 Jellyfin/Emby/弹弹play 的原生作品、季、集和丰富资料快照。原生身份命名空间为 `https://sources.nipaplay.app`，scope 隔离设备、来源连接与实际服务器；ProviderIds 只作为服务器证据保留。返回的 workId/episodeId 可直接用于 Next 的身份、资料、封面与完整度能力。刷新保留人工覆盖和已有文件关联，不删除缺失文件、不调用 Classic 自动识别。原生资料通过 `media.sources.sync` 刷新，修改留在 Next，不回写服务器。
传 `parentIds` 可从指定库或目录开始；`scrape` 则调用 Classic 的 WebDAV/SMB
远程字节识别，保留进度，并迁移已解除匹配记录的进度。

`dandanplay_remote` 是 Classic 的单一弹弹play远程来源，支持配置、用户登录、
刷新、浏览与播放。`play(sourceId,itemId)` 在应用内部解析地址，保留共享续播上下文。
`addresses` 批量管理 Jellyfin/Emby 备用地址、优先级与连通性。
`remote_admin.status/folders/connections` 复用 Classic 共享客户端管理对端目录和连接。
`browse` 支持搜索与排序，`sort` 保存 Jellyfin/Emby 库的 Classic 排序偏好。
来源与对端目录移除只删配置，不删硬盘文件，不需要确认。

`sync.status/configure/login/enable/test/run` 是 WebDAV 多端增量同步原语，
与来源文件发现的 `media.sources.sync` 分开。配置采用 patch，修改地址或用户名
会清除旧凭据。启用、停用、窗口登录、立即同步返回任务回执，设置历史记录调用来源；授权密码登录直接返回验证与保存结果。
`sync.status.hasPassword` 只说明是否有已保存密码，不读回秘密。

文件定位与 Classic 一致；发现不创建观看历史或推断作品身份。
Next 索引按 `sourceId` 隔离远程位置，Jellyfin/Emby 另包括实际 serverId；同类两台服务器即使返回相同 item ID，也得到不同
`fileId`。绑定时使用此 fileId，播放时继续使用原 path。无来源归属的旧记录保留为独立证据。
完整 schema 以实时 Harness 列表为准。实现及实验见 docs/next/X12_REPORT.md。

X48 的片库入口为 `core.libraryData/libraryActions`，能力为 `ui.library.*`，见
`../ui_data/README.md`。原样浏览复用上述客户端，Jellyfin/Emby 使用独立单页
catalogPage，不改变 Classic 的完整 browseCatalog；库排序读取 Classic 保存的偏好。
原样作品和剧集 ID 包含配置及实际服务器身份，图片下载仍由原认证客户端完成。
未绑定条目和条件中的已绑定条目最终都调用同一个 `MediaSourcesService.play`
（现有 `media.sources.play` 的实现），不靠当前激活服务器猜测来源。
