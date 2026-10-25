# 协调服务正式上线 Runbook

给主控在**真服务器**上照做。每一步都是 `deploy/` 里的一个脚本，逐字在一次性环境里演练过
（演练记录见本文末尾）。命令不写成内联长串：上传整个 `deploy/` 目录后，在服务器上只运行
脚本文件。

## 0. 先读这几条

- **只做增量。** 新建一个系统用户、三个目录、一个 systemd 单元、站点文件里**一个**
  `location ^~ /mesh/`。不碰网关（`nipaplay-dandanplay-gateway`）、`nipaplay-relay`、Plex、Emby、
  xray、frp 和任何别的站点。每个脚本在动手前先检查，不满足就停，不会硬做。
- **磁盘 95% 满，只剩约 2.6 GB。** 本部署占用不到 20 MB（二进制 8 MB，SQLite 数据库初期不到 1 MB），
  日志走 journald、很少。第 1 步会在可用空间小于 300 MB 时拒绝继续。见第 9 节。
- **根的私钥只在生成它的服务器上。** 主根在香港主服务器，备用根在备用服务器（GCP 俄勒冈，
  主控 SSH 别名 `gcp-us-vps`）。
  不下载、不备份到别处、不进仓库、不进日志；只取回公钥证书（`ca.crt.pem`）。
- 所有脚本要 root（`sudo -i` 之后运行，或前面加 `sudo`）。
- 路径里的 `<server>` 是主服务器的 SSH 地址。下面的 `deploy/` 指仓库
  `server/nipaplay-mesh-coordinator/deploy/`。

### 路径与名字一览

| 东西 | 位置 |
|---|---|
| 系统用户 / 组 | `nipaplay-mesh`（`/usr/sbin/nologin`，无家目录创建） |
| 二进制 | `/opt/nipaplay-mesh-coordinator/nipaplay-mesh-coordinator`（root:root 755） |
| 根的公钥证书 | `/opt/nipaplay-mesh-coordinator/ca.crt.pem`（644） |
| 根的私钥 | `/etc/nipaplay-mesh-coordinator/ca.key.pem`（nipaplay-mesh:nipaplay-mesh 600；目录 root:nipaplay-mesh 750） |
| env 文件 | `/etc/nipaplay-mesh-coordinator.env`（root:nipaplay-mesh 640） |
| 数据库 | `/var/lib/nipaplay-mesh-coordinator/mesh.db`（nipaplay-mesh 600） |
| systemd 单元 | `/etc/systemd/system/nipaplay-mesh-coordinator.service` |
| 监听 | `127.0.0.1:18082`（只回环，nginx 反代） |
| 令牌校验 | `http://127.0.0.1:18081`（现有网关，只读 `/api/v2/playhistory`） |
| 脚本与状态 | `/root/mesh-deploy/`，状态快照在 `/root/mesh-deploy/state/` |
| nginx | `/www/server/nginx/sbin/nginx`；站点文件 `/www/server/panel/vhost/nginx/nipaplay.aimes-soft.com.conf` |

对外地址：`https://nipaplay.aimes-soft.com/mesh/...`（应用里内置的默认协调地址就是
`https://nipaplay.aimes-soft.com/mesh`）。

## 1. 上线前，在主控本机准备

```sh
# 二进制与 sha256：~/.nipa-next/coord-deploy/ 里（x86_64，glibc ≤ 2.30，Ubuntu 20.04 容器里构建）
cd ~/.nipa-next/coord-deploy
cat nipaplay-mesh-coordinator.sha256        # 记下这个值，第 3 步要对
```

上传（二进制和脚本放进同一个目录）：

```sh
scp -r <仓库>/server/nipaplay-mesh-coordinator/deploy root@<server>:/root/mesh-deploy
scp ~/.nipa-next/coord-deploy/nipaplay-mesh-coordinator root@<server>:/root/mesh-deploy/
```

备用服务器单独一节（第 8 节），可以和主服务器同时做，也可以先后做；**它们之间没有依赖**。

## 2. 第 1 步：前置检查（只读，加两处备份）

```sh
ssh root@<server> /root/mesh-deploy/01-precheck.sh
```

做什么：检查系统与磁盘余量（≥ 300 MB）、端口 18082 空闲、网关在 18081 监听、用户/目录/单元都还不存在、
`nginx -t` 当前就能通过、站点文件里有 `location ^~ /dandanplay/` 而没有 `/mesh/`、`python3`/`curl`/
`openssl`/`systemctl` 在；把现有监听和运行中的服务、两个现有路由（`/` 与 `/dandanplay/healthz`）的状态码存进
`/root/mesh-deploy/state/`（第 6 步拿它们对比）；把站点文件和 `nginx.conf` 各备份一份带日期的
`.bak-YYYYmmdd-HHMMSS`（放在原目录，面板的 `*.conf` 通配不会把它们当配置读进去）。

期望：以 `Step 1 done` 结束，没有 `FAIL`。任何 `FAIL`：**停下，不要进行第 2 步**，把输出交回。

撤销：删掉两个 `.bak-*` 文件和 `/root/mesh-deploy/state/`。

## 3. 第 2 步：核对 sha256，建用户和目录，装二进制

```sh
ssh root@<server> /root/mesh-deploy/02-install-binary.sh /root/mesh-deploy/nipaplay-mesh-coordinator <第 1 节记下的 sha256>
```

sha256 不符直接 `ABORT`，什么都不建。通过后：建系统用户 `nipaplay-mesh`、`/var/lib/nipaplay-mesh-coordinator`
（750）、`/etc/nipaplay-mesh-coordinator`（root:nipaplay-mesh 750）、`/opt/nipaplay-mesh-coordinator`，装二进制，
并运行一次 `--help` 确认能在这台机器的 glibc 上加载（不会启动服务）。

撤销：`rollback.sh purge --yes-delete-the-root-key`（第 7 节；此时还没有根，等于只清掉这一步）。

## 4. 第 3 步：生成根（私钥只在这台机器上）

```sh
ssh root@<server> /root/mesh-deploy/03-generate-root.sh
```

做什么：在 `/root/mesh-root-stage.XXXXXX`（`umask 077`，仅 root 可进）里调用
`nipaplay-mesh-coordinator --generate-ca`（私钥创建时就是 0600，排他创建），
然后把证书装到 `/opt/.../ca.crt.pem`（644）、私钥装到 `/etc/nipaplay-mesh-coordinator/ca.key.pem`
（属 `nipaplay-mesh`，600），`shred` 掉暂存里的私钥并删除暂存目录。脚本**绝不覆盖**已有的根。
最后打印证书的主题、有效期（10 年）、SHA-256 指纹、`CA:TRUE, pathlen:0`、`Certificate Sign`、Ed25519。

**只取回公钥证书**：

```sh
scp root@<server>:/opt/nipaplay-mesh-coordinator/ca.crt.pem ~/.nipa-next/coord-deploy/primary-root.crt.pem
openssl x509 -in ~/.nipa-next/coord-deploy/primary-root.crt.pem -noout -fingerprint -sha256   # 与脚本打印的指纹一致
```

不要 `scp` 或 `cat` 任何 `*.key.pem`。

撤销：`rollback.sh purge --yes-delete-the-root-key` 会删掉私钥。**根一旦打进发布的应用，就不要再删**
（删了就得发新版应用）。所以：在把证书写进应用之前，这一步可以随便重来。

## 5. 第 4 步：装 env 与 systemd 单元并启动

```sh
ssh root@<server> /root/mesh-deploy/04-install-service.sh
```

做什么：确认网关在 18081 监听、18082 空闲；如果没有 env 文件，就用 `nipaplay-mesh-coordinator.env.example`
装 `/etc/nipaplay-mesh-coordinator.env`（`DANDANPLAY_GATEWAY_BASE=http://127.0.0.1:18081`、
`MESH_ACCOUNT_CLAIM_POINTER=/UserId`、`MESH_LISTEN_ADDR=127.0.0.1:18082`、`RUST_LOG=info`）；装单元、
`daemon-reload`、`enable --now`；等 `http://127.0.0.1:18082/healthz` 答复。

单元里的沙箱（演练里在真 systemd 245 上验证过能正常启动）：`NoNewPrivileges`、`PrivateTmp`、`PrivateDevices`、
`ProtectHome`、`ProtectSystem=strict`（只有 `/var/lib/nipaplay-mesh-coordinator` 可写）、`ProtectKernel*`、
`RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`、`CapabilityBoundingSet=`（空）、`MemoryMax=256M`、
`TasksMax=64`。这台机器若是 cgroup v1（Ubuntu 20.04 默认），`MemoryMax` 可能不生效；它只是附加保护。

期望：打印 `{"ok":true,...}` 和 `Active: active (running)`，以 `Step 4 done` 结束。
此时服务只听回环，**外界还访问不到**，现有站点没有任何变化。

撤销：`rollback.sh service`（停止、禁用、删单元与 env；数据库和根不动）。

## 6. 第 5 步：nginx 加 `location ^~ /mesh/`（影响现有站点的一步）

先看改动，不写入：

```sh
ssh root@<server> /root/mesh-deploy/05-nginx-add-location.sh --dry-run
```

要加的**确切文本**（`deploy/nginx-location.conf` 的内容，加上包住它的标记注释，便于精确撤销）：

```nginx
    # >>> nipaplay-mesh (deploy/nginx-location.conf) >>>
    location ^~ /mesh/ {
        proxy_pass http://127.0.0.1:18082;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
        proxy_send_timeout 30s;
    }
    # <<< nipaplay-mesh <<<
```

**位置：紧接在 `location ^~ /dandanplay/ { ... }` 的结束大括号之后**、`location / { ... }` 之前（前面空一行）。
`proxy_pass` **不带** URI，所以 nginx 把 `/mesh/...` 原样交给服务（服务的路由就是 `/mesh/v1/...`，另有 `/mesh/healthz`）。
`^~` 优先于正则 location 和 `/`，不会被宝塔的静态文件正则抢走。

确认 diff 只有这一段后，执行：

```sh
ssh root@<server> /root/mesh-deploy/05-nginx-add-location.sh
```

脚本：用 Python 在站点文件文本里找到**唯一**的 `location ^~ /dandanplay/` 块（找不到或不止一个就中止），
生成新文本，**先写入再 `nginx -t`；`-t` 不通过或 `-s reload` 失败就把原文逐字节放回**，
`reload` 后等 1 秒。它用的是宝塔那个 nginx（`/www/server/nginx/sbin/nginx`）。

注意（宝塔）：以后在面板里改这个站点（SSL、重定向、反代等）可能让面板重写站点文件；
我们的块带标记注释，重写后若丢了，重新运行本步骤即可（脚本会拒绝重复添加）。不要把块放进
面板自己管理的标记区（`#SSL-START … #SSL-END` 之类）。

撤销：`rollback.sh nginx`——只删掉带标记的这一段，`nginx -t` 通过后 reload；演练里验证过
站点文件与加入前**逐字节相同**。

## 7. 第 6 步：自检

```sh
ssh root@<server> /root/mesh-deploy/06-selfcheck.sh
```

检查：服务 active 且以 `nipaplay-mesh` 运行；`127.0.0.1:18082/healthz`；监听只在回环；经 nginx 的
`https://nipaplay.aimes-soft.com/mesh/healthz` 和 `/mesh/v1/server-info`；`server-info` 里的
`serverCertificate` 与 env 文件里配置的根证书**逐字相同**；未带令牌的 `/mesh/v1/devices` 是 401；
**现有路由状态码与第 1 步一致**（`/`、`/dandanplay/healthz`）；监听端口只新增 `127.0.0.1:18082`、
运行中的服务只新增本服务。以 `ALL CHECKS PASSED` 结束。

人工再看一眼（从主控本机，走公网）：

```sh
curl -s https://nipaplay.aimes-soft.com/mesh/healthz
curl -s https://nipaplay.aimes-soft.com/mesh/v1/server-info | head -c 300
curl -sI https://nipaplay.aimes-soft.com/ | head -1
curl -s https://nipaplay.aimes-soft.com/dandanplay/healthz
```

## 8. 备用服务器（GCP 俄勒冈，`gcp-us-vps`）：只生成备用根

备用服务器**不跑**协调服务、不装用户、不动 nginx。只做一件事：生成并保管备用根的私钥。
那台机器登录的是普通用户、免密 sudo，`/root` 对它不可读，所以证书用 `sudo cat` 取回：

```sh
ssh gcp-us-vps 'mkdir -p ~/mesh-standby-upload && chmod 700 ~/mesh-standby-upload'
scp ~/.nipa-next/coord-deploy/nipaplay-mesh-coordinator <仓库>/server/nipaplay-mesh-coordinator/deploy/standby-generate-root.sh gcp-us-vps:mesh-standby-upload/
ssh gcp-us-vps 'sudo -n bash ~/mesh-standby-upload/standby-generate-root.sh ~/mesh-standby-upload/nipaplay-mesh-coordinator <sha256>; rm -rf ~/mesh-standby-upload'
ssh gcp-us-vps 'sudo -n cat /root/mesh-standby-root/ca.crt.pem' > ~/.nipa-next/coord-deploy/standby-root.crt.pem
```

2026-10-25 上线时生成的两张根（公开指纹，SHA-256）：

| 根 | 保管处 | 指纹 |
|---|---|---|
| 主根 | `nipaplay-prod`：`/etc/nipaplay-mesh-coordinator/ca.key.pem` | `9C:AF:8B:A9:E0:5E:CF:E2:AC:ED:52:A2:1A:2A:DD:5C:DC:95:B4:D3:40:37:87:C3:CC:52:C9:C2:D5:A1:7A:04` |
| 备用根 | `gcp-us-vps`：`/root/mesh-standby-root/ca.key.pem` | `67:8A:B8:66:DF:70:BC:3D:CA:91:00:0E:81:08:C3:5A:8E:21:D6:93:07:B9:EA:92:CB:F2:B8:83:2C:EF:28:0E` |

脚本核对 sha256、在 `/root/mesh-standby-root/`（700）里生成根，私钥 `ca.key.pem` 留在那里（root 0600），
打印指纹。已有就拒绝覆盖。需要 `openssl`（没有就先装；它缺失时脚本在生成之前就停）。
私钥不复制、不另备份。

### 把两张公钥证书写进应用（发布前）

```sh
cd <仓库>
python3 tool/next/set_mesh_trust.py ~/.nipa-next/coord-deploy/primary-root.crt.pem ~/.nipa-next/coord-deploy/standby-root.crt.pem
dart run tool/next/check_mesh_trust.dart          # 必须打印 “Mesh trust roots ok: 2 roots”
```

`set_mesh_trust.py` 拒绝私钥、拒绝不是 Ed25519 CA 的证书、拒绝两张相同；写进 `lib/next/mesh/trust.dart` 的
`_builtInIssuerPem`。`check_mesh_trust.dart` 是**发布门**：信任常量为空、解析失败、有一张不是自签 CA 或已过期、
不足两张不同的根时退出码非 0——**这时不要构建发布**（应用本身遇到这种常量也会拒绝加入：
`issuer_not_configured`）。无界面版同样读这个常量；发布命令带 `--dart-define` 时，检查命令要带同样的定义。

## 9. 数据库备份、升级、回滚、切换备用根

### 备份（建议上线当天先做一次；之后可放进 cron）

```sh
ssh root@<server> /root/mesh-deploy/backup-db.py            # → /var/backups/nipaplay-mesh/mesh-<时间>.db
```

用 SQLite 备份接口，服务不用停，得到的是单个完整文件（0600），默认保留最新 14 份，并做
`integrity_check`。库里只有设备公钥、名称、短期地址，没有令牌也没有私钥。
cron 例（可选，每天 04:17）：`17 4 * * * root /root/mesh-deploy/backup-db.py >/dev/null`。

### 升级二进制（与回滚）

```sh
ssh root@<server> /root/mesh-deploy/backup-db.py
ssh root@<server> systemctl stop nipaplay-mesh-coordinator
ssh root@<server> /root/mesh-deploy/02-install-binary.sh /root/mesh-deploy/<新二进制> <新 sha256>   # 旧的留作 .prev
ssh root@<server> systemctl start nipaplay-mesh-coordinator
ssh root@<server> /root/mesh-deploy/06-selfcheck.sh
# 不对：
ssh root@<server> /root/mesh-deploy/rollback.sh binary      # 换回 .prev 并重启
```

数据库表结构只加不改，所以回到旧二进制不需要动数据库（演练里换到另一构建再换回，数据与设备名单都在）。
注意：回到**不含“凭设备私钥续证”**的旧版本后，令牌已过期的设备暂时无法续证。

### 恢复数据库（备份比现在旧）

客户端会拒绝**倒退的**吊销版本号（`revocation_epoch`），而备份之后新吊销的设备不能复活。
所以不要手工 `cp`，用脚本：

```sh
ssh root@<server> systemctl stop nipaplay-mesh-coordinator
ssh root@<server> /root/mesh-deploy/restore-db.py /var/backups/nipaplay-mesh/mesh-<时间>.db
ssh root@<server> systemctl start nipaplay-mesh-coordinator
```

脚本：检查备份的完整性；把正在用的库改名保留为 `mesh.db.pre-restore-<时间>`（不删）；放回备份；
每个账号的 `revocation_epoch` 设为 `max(备份, 原库) + 1`（所以不倒退，并让所有客户端重新读设备名单）；
把原库里已经吊销的设备**重新吊销**并清掉它们的地址。输出里会打印三组 epoch（备份、恢复前、恢复后）和
“devices kept revoked”。备份之后才注册的设备不在恢复后的库里，它们下次带账号令牌启动时会重新注册。

### 切到备用根签发（根泄露，或计划轮换）

前提：应用已经发布并信任两张根（双根必须从第一版就在）。

```sh
ssh root@<备用> cat /root/mesh-standby-root/ca.key.pem | ssh root@<server> /root/mesh-deploy/switch-root.sh to-standby /root/standby-root.crt.pem
```

（先把 `standby-root.crt.pem` 用 `scp` 放到主服务器 `/root/`。私钥经管道直接从备用服务器送到主服务器，
不落主控本机磁盘。）脚本把私钥装给服务用户（600）、把证书放到 `/opt/.../ca-standby.crt.pem`、改 env 文件的
`MESH_CA_CERT_FILE`/`MESH_CA_KEY_FILE`、重启，并核对 `server-info` 宣告的已经是备用根；
任何一步失败都把 env 放回、删掉刚装的备用私钥、重启回主根。

之后：新注册的设备拿到备用根签发的证书；已有设备在**证书剩不到一天时**续证换根（证书 7 天有效，最多 7 天换完）。
应用同时信任两张根，所以换的过程中新旧证书的设备互通（演练里验证过：持主根证书和持备用根证书的设备互相调用成功）。
撤回：`switch-root.sh back`（主根文件从未被动过）。

**这样做的后果（需要主控知道）：** 备用根的私钥这时已经离开了备用服务器，存在于主服务器上。
它现在是主根，应当另外生成一个新的备用根并随下一次应用发布；旧的主根要不要从应用里去掉，取决于是否怀疑泄露。

### 日常看一眼

```sh
ssh root@<server> systemctl status nipaplay-mesh-coordinator --no-pager | head -8
ssh root@<server> journalctl -u nipaplay-mesh-coordinator -n 20 --no-pager
ssh root@<server> df -h /
```

## 10. 回滚总表（每一步怎么撤）

| 做了什么 | 撤销 | 说明 |
|---|---|---|
| 第 5 步 nginx location | `rollback.sh nginx` | 只删带标记的一段，`nginx -t` 通过才 reload；站点文件恢复为加入前逐字节相同。**这是让外界立刻看不到服务的最快办法** |
| 第 4 步 单元与 env | `rollback.sh service` | 数据库、根、二进制保留 |
| 升级二进制 | `rollback.sh binary` | 换回 `.prev` 并重启 |
| 第 3 步 根 | `rollback.sh purge --yes-delete-the-root-key` | 连同数据库一起删。**根发布进应用之后不要做** |
| 第 2 步 用户与目录 | 同上 `purge` | |
| 第 1 步 备份 | 删 `*.bak-*` 与 `/root/mesh-deploy/state/` | |
| 数据库恢复 | 停服务，把 `mesh.db.pre-restore-<时间>` 改回 `mesh.db`，启动 | 脚本从不删除被替换的库 |

**停服退路：** 去掉 `/mesh/` location（`rollback.sh nginx`）或 `systemctl stop`。设备用缓存的证书与名单在局域网里
继续工作（证书最多再撑 7 天；这期间新设备加不进来、吊销只能靠设备之间的通知传播）。

## 11. 磁盘紧张时的注意

- 本服务**不写日志文件**：日志进 journald。env 里 `RUST_LOG=info` 只记注册、吊销和所有警告，不要调高。
  先看一下 `journalctl --disk-usage`；如果 journald 本身没有上限，建议
  `journalctl --vacuum-size=100M`（现有服务共用 journald，这是系统级设置，由主控决定是否做）。
- nginx 的访问日志按宝塔站点原有设置写 `/www/wwwlogs/`：心跳每台设备每小时 4 次，量很小；
  如果想让 `/mesh/` 不进访问日志，可在我们的 location 块里加一行 `access_log off;`（默认没加）。
- SQLite 体积：`devices` 一台一行，`addresses` 短期并每小时清理，`possession_proofs` 每次请求清理 10 分钟前的；
  只有 `certificates`（每次签发一行，约 30 字节）会缓慢增长：一百台设备每 6 天各一行，一年约 600 KB。
  数据库有 WAL 文件（`mesh.db-wal`/`-shm`），服务停止时合并。预计库不会超过几 MB。
- 备份目录 `/var/backups/nipaplay-mesh` 默认保留 14 份，每份约等于库大小；磁盘更紧就 `--keep 3`。
- 随时可查：`du -sh /var/lib/nipaplay-mesh-coordinator /var/backups/nipaplay-mesh /opt/nipaplay-mesh-coordinator`。
- 磁盘剩余低于 300 MB 时不要做第 1 步之外的任何事，先腾空间。

## 12. 正式部署之后（主控与实验）

- 三个实验实例用测试账号经正式地址注册、吊销、轮换（设计 §10 阶段 1）；屏蔽协调服务 30 分钟看局域网；三台设备同时开着时
  不出现 429。
- 无界面主机用**固定端口**（默认 47812，不要设 `"port": 0`）：令牌过期后设备无法向协调服务查询对端的新地址，
  固定端口让已记住的地址一直有效。
- 无界面主机令牌过期后：证书照常续（凭设备私钥），局域网照常工作；读不到新的设备名单（新加入的设备、新吊销的设备要等令牌更新）。

## 附：与真机的差异（演练做不到的）

| 演练 | 真机 | 影响 |
|---|---|---|
| arm64 的 `ubuntu:20.04` 容器 + 真 systemd 245 | x86_64，Ubuntu 20.04.6 | 单元与沙箱同一版本验证过；真正的 x86_64 二进制另在 amd64 仿真容器里验证过能加载并回答 `/healthz`、`/mesh/healthz`、`server-info` |
| 演练用 arm64 构建 | 上线用 `~/.nipa-next/coord-deploy/` 里的 x86_64 构建 | 同一份 Rust 源码（逐文件核对过） |
| nginx 1.18（apt），目录模仿宝塔 | 宝塔 nginx 1.30.6 | `location ^~`、`proxy_pass`、`-t`、`-s reload` 行为一致；宝塔面板本身未模拟 |
| 自签 HTTPS + 一个同时监听 80 的站点 | 真证书 | 演练里应用经回环 HTTP 连接（客户端允许回环 HTTP） |
| 假网关（校验演练令牌）| 真网关 | 令牌声明名 `UserId` 已由 X45 用测试账号确认；正式部署后用测试账号再验一次 |
| 证书有效期在演练中临时改成 900 秒（为了立刻触发续证） | 604800 秒（env 模板默认） | 仅演练；模板与上线值未改 |
