# Mesh 跨设备操作

Mesh 使用同账号、经认证的设备。先用 `mesh.devices` 查看设备 ID、连通性、宿主角色、Agent 状态和目录，再对目标执行 `nipa --device NAME list`、`describe ACTION` 与 `app.capabilities`。重名用设备 ID；本机有能力不表示目标有能力，白名单允许也不等于设备在线、已授权或前置满足。

## 查询、调用或委托

1. 查询目标的媒体与目录时，用 `media.library.status` 查看已缓存观察；`media.library.refresh` 会主动刷新。可达性、目录新鲜度和图片状态分别判断：离线保留的旧目录不证明当前可播。
2. 需要目标设备本地完成整项任务时，可考虑 `mesh.delegate`，先确认目标 `agent.runs` 与用户意图。需要单项操作时可用 `nipa --device` 调用；底层按 effect 使用 `mesh.invoke` 或 `mesh.invoke_destructive`。结果、路径和 ID 属于目标设备。
3. 合并目录返回的作品 ID 不一定是写入设备的原始 ID；先用 `media.management.targets` 找拥有者和对应实体，再在拥有者上执行。每台设备本地事务独立，不假设跨设备原子提交。

## 文件与用户授权

跨设备写入、移动、覆盖或删除先确认用户授权。`media.mesh_files.readable` 取得可读路径或临时回环 URL；`begin/chunk/finish` 暂存和发布文件，覆盖返回预览；`delete` 返回删除预览。**`media.mesh_files.confirm` 由调用方在用户同意后执行，宿主不会自动弹出确认。** 预览后文件变化会拒绝确认；取消未使用的暂存传输。传输和决定标识以进程生命周期为限。

下载文件删除使用目标的 `download.delete` 与相应用户在场流程；其他 destructive Action 并非一律弹确认，以目标 `describe` 和实际回执为准。headless 等宿主可能不提供该动作或无法完成用户在场步骤。

## 核验和恢复

- `not_delivered` 表示本次未找到可交付连接，不证明更早的同类请求未执行。`outcome_unknown` 或响应续传不可用表示结果未知，不等于回滚。
- 保留目标设备、来源和原请求键，先查目标 `task.get` / `task.wait`、领域回执和 `diagnostics.operations`。只读数据可重新取；没有持久幂等契约的写操作不要自动重做。
- SQL 写入通过原 previewId 查 `db.receipt`，撤回通过原 requestId 查；`unknown` 仍可能在途或键/来源不符。提交后通知尚未完成也与事务提交分开报告。详见 [过程事实契约](../../OBSERVABILITY_CONTRACT.md)。

实现参考：[Mesh 能力](../../../../lib/next/mesh/capability.dart)、[设备文件](../../../../lib/next/mesh/files.dart)、[目录状态](../../../../lib/next/mesh/library_capability.dart)。
