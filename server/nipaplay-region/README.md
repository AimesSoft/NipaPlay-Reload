# NipaPlay Client Region Resolver

国内备用服务器上的一个小型 HTTP 服务，用来回答「这个客户端是不是中国大陆的 IP」。
NipaPlay 客户端在「自动」模式下会请求它，据此在香港主服务器和国内备用服务器之间选择。

## 接口

### `GET /region`

只监听回环地址，真实客户端 IP 由 nginx 通过 `X-Real-IP` 注入（客户端无法伪造）。

```json
{ "ip": "59.173.225.82", "region": "CN", "country": "CN", "source": "apnic-delegated" }
```

- `region` 为 `CN` 或 `OVERSEAS`；
- 无法解析客户端 IP 时返回 `400`，客户端会退化为「可达性 + 延迟」判定；
- `X-Real-IP` 缺失时依次回退到 `X-Forwarded-For` 首项、socket 对端地址。

### `GET /healthz`

```json
{ "ok": true, "service": "nipaplay-region" }
```

## 数据

`cn_ranges.json` 是从 APNIC 委派文件里筛出的 CN 地址块，合并相邻/包含区间后写成紧凑
JSON（IPv4 约 4100 段、IPv6 约 2000 段）。运行期只做一次二分查找，不需要联网，也不需要
GeoIP 数据库。

重新生成：

```bash
python3 generate_cn_ranges.py                    # 直接从 APNIC 下载
python3 generate_cn_ranges.py delegated-apnic-latest   # 用本地已下载的文件
```

## 运行

```bash
REGION_LISTEN_HOST=127.0.0.1 REGION_LISTEN_PORT=18100 python3 region_service.py
```

生产环境使用 `deploy/nipaplay-region.service`（systemd，`User=www-data`），nginx 站点配置见
`deploy/nginx-site.conf`。

```bash
sudo install -o root -g root -m 644 region_service.py cn_ranges.json /opt/nipaplay-region/
sudo install -o root -g root -m 644 deploy/nipaplay-region.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now nipaplay-region
```

只有 Python 3 标准库依赖。完整部署说明见
[`docs/NIPAPLAY_GATEWAY_DUAL_SERVER.md`](../../docs/NIPAPLAY_GATEWAY_DUAL_SERVER.md)。
