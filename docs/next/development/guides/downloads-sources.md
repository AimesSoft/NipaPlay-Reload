# 媒体来源与下载

先在目标设备用 `nipa list`、`describe` 和 `app.capabilities` 核对能力与前置；来源凭据由宿主管理，登录交互由用户完成。

## 来源：事实与选择

- `media.sources.list`、`browse`、`search` 查询已配置来源及目录；`network.status` / `network.check` 查看路由和连接观察。缓存目录不代表实时可播放。
- 先核对来源类型、地址、授权及目标设备，再按 `media.sources` 实时目录配置或同步。账号登录需要用户操作；不要把密码放进对话、日志或脚本。
- 同步是任务，查看 `task.get` / `task.wait` 和来源状态；网络失败、认证失败及无结果应分别报告，不把旧缓存当新结果。

## 下载：预览与执行

- `download.preview` 可预览磁力、种子或 HTTP 文件；`download.add` 创建任务，`download.read` 查看文件、进度、状态和落盘位置。HTTP 使用对应后端；qBittorrent 需先配置。
- 确认来源、目录、要下载的文件及存储空间后再添加；`download.select_files` 改变选择，不删除已有数据。内置会话限速查 `download.limits`，不适用于所有后端。
- 文件完成并校验后可登记入库，但身份仍需明确判断和绑定，见[媒体身份](media-identity.md)。`task.get` 与下载回执核对实际完成；发起下载后的文件、停滞和终态可作为后续返回对话。
- `download.remove` 保留文件；删除数据有独立的预览/确认契约，按目标设备 `describe` 和用户决定执行。取消任务不等于删除数据；响应丢失先查任务和回执，勿盲目重复。
