# 媒体来源

Next 支持 SMB 和 WebDAV，复用其配置与凭据保险库。
`media.sources.list` 读取配置和已有观察，不联网、不读取凭据。
`add/update` 配置地址与用户名，`login` 使用密码窗口；用户明确授权后可用
`password` 与 `userAuthorization` 直接登录，秘密不进入任务输入或回执。

`libraries/select` 管理目录范围，未选择时从根目录开始。
`browse` 的 parentId 是来源内的绝对目录路径；递归发现使用 `sync`。
发现保存文件与来源目录事实，保留已有绑定和字段覆盖，不推断作品身份。
原生目录命名空间 `https://sources.nipaplay.app`、三元组 ID 与缓存键兼容既有数据。
`query` 读取文件事实，不写索引；`search` 只查已有文件名和路径索引。
每个来源独立返回 entries/total 或 error，basis 为 indexed；失败保留索引结果。
poster 是已绑定作品的本机缓存，来源没有独立海报接口。

`play` 使用 sourceId/itemId 打开 Next 播放器，`scrape` 保留文件服务的字节哈希识别。
`check` 显式验证来源；addresses、lastCheck、sync、lastError 和 credential
保留带时间的观察，unknown 不表示离线，密码状态不含秘密。
WebDAV 支持 url/wanUrl，SMB 支持 host/port 和 wanHost/wanPort；至少保留一个地址。
新增地址或切换账号后需要重新登录。

`sync.status/configure/login/enable/test/run` 继续提供 WebDAV 多端同步，
与来源目录发现 `media.sources.sync` 分开。
