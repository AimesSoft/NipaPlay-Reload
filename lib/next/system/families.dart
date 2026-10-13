/// Family context belongs to live describe, not to the harness seed.
const systemFamilyDescriptions = <String, String>{
  'download.limits': 'get 读取原生内置下载会话限速，set 调整上传/下载字节每秒预算并返回引擎读回值。0 为无限制，正值至少 16384；省略方向保留现值。不自动初始化会话；applied=false 不能宣称已限速。只影响本机内置会话，重建后恢复默认无限制，不改变服务端限流。',
  'task':
      '后台任务共用持久快照、来源和回执。control 批量暂停/恢复/取消，逐项给支持与受理事实；paused 可能仍在排空当前文件。get/wait 核对完成。resources 读取实际容量；tasks.*Concurrency 设置只改变新工作派发。不能安全重放的执行器拒绝暂停。终态回执不改写，取消不删除文件。',
  'events':
      '身体变化共用 hook 与 followup 的持久事实日志。describe 列出事件；wait(afterCursor) 有界等待和分页，游标跨重启；只重读事实，不重跑脚本。followup.register 订阅下一次事件；hook 名称就是事件名。播放位置不逐帧发事件；seek_requested 是受理意图，settlement 必须另核对。',
  'network':
      'status 给路由、代理、故障转移、媒体服务器连接 UA 及来源最近错误/上次成功。check 显式检查已登记来源或官方网关 healthz，不更换路由或登录。观测历史只覆盖当前进程，未观察值不宣称可达。第三方凭据去向仍由用户设置；秘密不进输出。',
  'storage':
      'status 给目录真实用量和卷可用空间。父目录包含子目录，不相加。watch 显式订阅空间阈值、unwatch 取消；仅当前进程有效，转换发 storage.space_changed。可重取缓存用 cache.plan/prune；字幕、导入弹幕、用户下载与无法证明可重取的图片保留。磁盘用户文件删除/覆盖沿用 media.mesh_files 的 NeedsDecision。',
  'cache':
      'plan(kinds,maxBytes) 返回实际回收对象、估计字节和保留原因，prune(planId) 重新核对引用与变化并返回逐项结果。仅可重取缓存回收无 NeedsDecision。Next 弹幕池复用引用感知回收；正在获取时推迟。计划是当前进程的预览，不允许夹带任意路径。',
  'diagnostics':
      'status 给健康、版本、资源、日志和迁移观察；file_logs 用受限 fileId 与行游标读取脱敏摘录。recover 只执行显式的日志重启、投影核对、索引器检查，不自动修改用户数据或登录。日志公开发布必须有明确目标与内容；本族不上传。',
  'app':
      'update.check 立即复用 Classic 发布检查；失败时 hasUpdate/latestVersion 为 null，错误与检查时间保留。update.status 读取上次检查；update.open 打开已核对公开发布页。没有应用内更新安装、自动重启或下载能力。instance 读取当前进程事实。',
  'notification':
      '当前 macOS 宿主有原生 OS 通知：status 读取系统设置，send 受系统授权、声音及系统展示策略管理，list 区分 pending/delivered，cancel 请求移除。未授权默认 blocked，requestPermission 明确请求系统询问用户。accepted 不等于用户看到了横幅；其他平台如实返回 unavailable。',
  'share':
      'prepare 预览文字、公开 URL 或授权本地文件；open 打开该计划的系统面板，由用户选目的地。会核对预览后文件变化。不以打开面板冒充已分享，也不自动上传日志。',
  'window':
      'bounds.get 读取、bounds.set 设置本进程主窗准确位置与尺寸，读写 effect 分开；不激活窗口，变化发 window.bounds_changed；已有 window.control 管 fullscreen/PiP/托盘。坐标为 window_manager 逻辑像素。目标不会按应用名查找。',
  'media.indexers':
      'status 返回自动附件索引器的启用值、正在执行、排队、上次运行与错误。library.*Enabled 是独立策略开关；关闭排空当前文件、保留队列，显式检查保持可用。自动匹配、弹幕加载和下载完成导入沿用各领域已有设置。',
};
