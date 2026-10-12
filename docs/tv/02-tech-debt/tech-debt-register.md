# 技术债登记册（TV 端）

> 维护责任：TV 端技术负责人 ｜ 更新时机：**每个功能开发前评估、完成后核对**
> 规则：未经评估的功能不得进入开发；债务必须带 ID、等级、风险、拆解方案。
> 状态：`Open` 未处理 / `Accepted` 已接受（有理由）/ `Mitigating` 缓解中 / `Resolved` 已解决

## 登记册

| ID | 债务描述 | 等级 | 影响范围 | 风险 | 拆解/缓解方案 | 状态 |
|---|---|---|---|---|---|---|
| TD-001 | watch_history 模型受 `watch_history_model ⇄ watch_history_database` 依赖环阻塞，无法进 core；TV 用轻量本地 `TvRecentPlayStore` 替代 | 中 | 数据层 | 数据模型与手机版不统一，后续云同步需重写 | 先解环（拆纯数据类）再迁 model；TV 侧保持轻量存储直至模型可搬 | Accepted |
| TD-002 | `DandanplayRemoteService` 是单例，只保存一个 baseUrl，多组弹弹端口会互相覆盖 | 中 | 媒体库 | 用户添加多个弹弹远程服务时后一个覆盖前一个 | 已用**独立 HTTP 请求**（`GET /api/v1/library`）绕过单例加载内容；根治需给服务加多实例接口 | Mitigating |
| TD-003 | 本地 TV 镜像构建缺 AVD 硬件加速，仅手机真机实测 | 低 | 测试 | 覆盖机型有限 | 用户装 AEHD 后可跑 `nipaplay_tv_api36` AVD；补 CI | Open |
| TD-004 | 番剧详情评分/简介依赖弹弹网关详情接口；Bangumi 主站 `api.bgm.tv` 从本机不可达 | 低 | 详情页 | 详情加载失败时只能回退榜单自带字段 | 已做 `try/catch` 回退；根治需本地代理或可达镜像 | Mitigating |
| TD-005 | TV 版仅 Erika 单内核，无内核回退 | 中 | 播放 | 遇 Erika 不支持的源无兜底路径 | 用户明确要求（体积优先）；保留 registry 扩展位，需要时加 media_kit 适配器 | Accepted |

## 新增技术债评估模板（开发前必填）

```markdown
### TD-xxx 评估
- 功能：
- 涉及模块：
- 是否引入新的跨层依赖/循环？（是/否，说明）
- 是否影响 TV 焦点可达性？（是/否）
- 是否影响安装包体积？（是/否，估算）
- 缓解/拆解方案：
- 结论：可进入开发 / 需调整后再开发 / 不做
```
