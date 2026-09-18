# NipaPlay 网关主/备双服务器部署

## 背景

官方弹弹play 网关原本只部署在香港（`nipaplay.aimes-soft.com`）。中国大陆用户直连香港线路
RTT 高且丢包严重，表现为弹幕/番剧信息加载慢、随机推荐超时、偶尔拉取失败。

为此在国内新增一台备用服务器，客户端按用户出口 IP 自动在两地之间选择，并在链路异常时
自动切换到另一台。

## 拓扑

| 角色 | 地址 | 接入方式 | 说明 |
| --- | --- | --- | --- |
| 主服务器 | `https://nipaplay.aimes-soft.com/dandanplay` | 域名 + HTTPS | 香港，海外与港澳台推荐 |
| 备用服务器 | `http://43.142.85.190/dandanplay` | IP 直连 + HTTP | 国内，中国大陆推荐（免域名免备案） |

两台服务器运行**同一个网关二进制**并共用同一份 `DANDANPLAY_APP_SECRET`，因此对上游
`api.dandanplay.net` 的行为完全一致，可以随时互换。

> 备用服务器使用明文 HTTP，是因为国内域名需要备案。客户端的
> `usesCleartextTraffic`（Android）与 `NSAllowsArbitraryLoads`（iOS）已允许该用法。

## 服务端组成

国内服务器（Ubuntu 26.04，systemd 托管，全部开机自启）：

| systemd 单元 | 监听 | 作用 |
| --- | --- | --- |
| `nipaplay-dandanplay-gateway` | `127.0.0.1:18081` | 弹弹play 上游代理网关（Rust） |
| `nipaplay-next` | `127.0.0.1:3010` | 官方站点、随机推荐、日志分享等 Next.js 接口 |
| `nipaplay-region` | `127.0.0.1:18100` | 归属地判定（内置中国 IP 段库） |
| `nipaplay-relay` | `0.0.0.0:18080` | 远程访问中继 |
| `nginx` | `0.0.0.0:80` | 唯一入口，按路径反代到上面各服务 |

nginx 路由：

- `GET /region` → `nipaplay-region`（归属地接口）
- `/dandanplay/*` → `nipaplay-dandanplay-gateway`
- `/*` → `nipaplay-next`

关键文件：

```
/opt/nipaplay-dandanplay-gateway/nipaplay-dandanplay-gateway   # 网关二进制
/etc/nipaplay-dandanplay-gateway.env                           # 网关配置（含密钥，640 root）
/opt/nipaplay-region/region_service.py                         # 归属地服务
/opt/nipaplay-region/cn_ranges.json                            # 中国 IP 段（APNIC 生成）
/www/wwwroot/nipaplay.aimes-soft.com/                          # 站点与兼容接口
/opt/nipaplay-next-runtime/node_modules                        # 站点运行时依赖（软链到站点目录）
/www/nipaplay-data/                                            # 站点数据根（NIPAPLAY_DATA_ROOT）
/etc/nginx/sites-available/nipaplay.conf                       # nginx 站点配置
```

## 归属地接口

`GET /region` 由 nginx 注入 `X-Real-IP`（客户端无法伪造），服务把该 IP 与内置的中国 IP 段
比对后返回：

```json
{ "ip": "59.173.225.82", "region": "CN", "country": "CN", "source": "apnic-delegated" }
```

- `region` 为 `CN` 或 `OVERSEAS`；
- IP 无法解析时返回 `400`，客户端会退化为「可达性 + 延迟」判定；
- IP 段来自 APNIC 委派文件（`apnic|CN|ipv4`、`apnic|CN|ipv6`），合并为有序区间后固化在
  `cn_ranges.json`，运行期不需要联网，也不需要 GeoIP 数据库。

## 客户端自动选择

实现位于 `lib/services/nipaplay_server_router.dart`，配置读写位于
`lib/utils/network_settings.dart`。

模式（`DandanplayServerMode`）：

- `auto`（默认）：按 IP 归属地 + 可达性自动选择；
- `hongKong`：固定香港域名；
- `china`：固定国内 IP；
- `custom`：用户自填的第三方兼容服务器。

`auto` 的判定流程：

1. 请求国内服务器的 `/region` 获取出口 IP 归属地（超时 4s）；
2. 同时并发探测两地 `/dandanplay/healthz` 的延迟（超时 3s）作为兜底；
3. 归属地为 `CN` 且备用服务器可达 → 国内；归属地为 `OVERSEAS` → 香港；
4. 归属地接口不可用时，若国内服务器可达且延迟 ≤ 1500ms（或明显快于香港）→ 国内；
5. 其余情况一律回落到香港。

判定结果缓存 6 小时（`nipaplay_auto_region`），网络设置里的「网络诊断」会强制重新判定。

HTTPS 页面（Web 版）无法直接请求明文 HTTP 的备用服务器（浏览器混合内容拦截），
因此 **Web 版固定使用香港域名**；原生客户端不受影响。

### 备用服务器接管

`DandanplayHttpClient` 会把官方网关请求的成功/失败上报给路由器。同一台服务器
**连续 3 次失败**（网络异常或 5xx）后，路由器会在 5 分钟内把请求临时切到另一台
（`nipaplay_failover_server`），并重置计数。用户手动切换模式会清空该状态。

### 网络设置

「设置 → 网络 → 弹弹play 服务器」下拉菜单：

- 自动选择（推荐，默认）
- 香港服务器（域名）
- 国内服务器（IP 直连）
- 自定义：… （仅在设置为自定义服务器时出现）

已安装的旧版本若保存过香港/官方地址，会自动迁移为「自动选择」；只有真正自定义的
第三方地址才保留为自定义模式。

## 运维

```bash
# 状态
systemctl status nipaplay-dandanplay-gateway nipaplay-next nipaplay-region nipaplay-relay nginx

# 日志
journalctl -u nipaplay-dandanplay-gateway -f
journalctl -u nipaplay-next -f
journalctl -u nipaplay-region -f

# 自检
curl -s http://43.142.85.190/region
curl -s http://43.142.85.190/dandanplay/healthz
curl -s -o /dev/null -w '%{http_code}\n' http://43.142.85.190/api/random-recommendations
```

更新国内站点代码后需重启 `nipaplay-next`；更新网关二进制后需重启
`nipaplay-dandanplay-gateway`。

### 更新中国 IP 段

```bash
curl -fsSL -o delegated-apnic-latest https://ftp.apnic.net/stats/apnic/delegated-apnic-latest
# 按 region_service.py 顶部注释的规则过滤 apnic|CN|ipv4 / ipv6，合并区间后写入 cn_ranges.json
sudo systemctl restart nipaplay-region
```

## 已知限制

- 国内服务器 `18080`（relay 中继）被腾讯云**安全组**拦截，如需对公网开放需在控制台放行。
  当前客户端并不调用该中继，因此不影响现有功能。
- 国内服务器未部署 1.3G 的 `releases` 安装包仓库与音乐库，`/releases/*`、`/music_library.php`
  等下载/音乐相关接口仍由香港站点提供。
