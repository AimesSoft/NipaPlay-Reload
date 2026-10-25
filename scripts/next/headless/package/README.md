# NipaPlay 无界面版

装在 Linux 服务器（seedbox、NAS、工作站 WSL）上的 NipaPlay：没有窗口，开机自启，同一个弹弹play账号下的
其他设备（Mac、iPad、电脑）能在设备网里看到它、读它的媒体库、把下载交给它；装好运行环境、设了模型之后，
这台机器上也能运行自己的 Nipa。

## 要求

- Linux，x86_64（amd64）或 aarch64（arm64），glibc 2.35 以上（Ubuntu 22.04、Debian 12 及更新的发行版）
- systemd（用户服务或系统服务）。没有 systemd 的环境（容器）也能前台运行，见下文
- 系统自带的 SQLite 动态库（Debian/Ubuntu：`libsqlite3-0`；缺了会在启动时报找不到 `libsqlite3.so`）
- 系统根证书（Debian/Ubuntu：`ca-certificates`）
- `python3`（3.9 以上）：只有用 `nipaplay-headless nipa …` 与 Nipa 对话、调用动作时需要
- 运行 Nipa 另需网络下载一次运行环境（见“Nipa”）

## 安装

```sh
tar xzf NipaPlay-Headless_<版本>_Linux_<架构>.tar.gz
cd nipaplay-headless
./install.sh
```

默认是**用户级安装**，不需要 root：

| 位置 | 用途 |
|---|---|
| `~/.local/share/nipaplay-headless/app/` | 程序（升级时整个替换） |
| `~/.local/share/nipaplay-headless/data/` | 数据：设备身份、数据库、模型设置和密钥、Nipa 的记忆、下载（升级和卸载默认都不动） |
| `~/.config/systemd/user/nipaplay-headless.service` | systemd 用户服务，已启用（开机或登录后自启）并已启动 |
| `~/.local/bin/nipaplay-headless` | 命令行入口 |

选项：

- `--media-root DIR`（可重复）：只读媒体库目录，写进服务的启动参数。**写了之后，每次启动都以这里的列表为准**；
  不写则沿用上次保存的（Nipa 也能用 `media.library.roots.add` 登记）。要改，重新运行 `./install.sh --media-root …`
- `--data DIR`：数据目录换个位置（绝对路径，路径里不能有空白、引号、`%`）
- `--no-start`：建好并设为自启，但现在不启动
- `--no-service`：只放文件，不建服务

**让它在没人登录时也运行。** 用户服务默认只在你登录期间运行。要开机即运行、退出 ssh 也不停，需要管理员为你的账号
执行一次（脚本不会替你执行需要 root 的命令）：

```sh
sudo loginctl enable-linger $USER
```

### 系统级安装

想要一个独立的系统服务（不依赖任何人的登录）：

```sh
sudo ./install.sh --system [--data /var/lib/nipaplay-headless] [--media-root /srv/media]
```

程序装到 `/opt/nipaplay-headless/app`，数据在 `/var/lib/nipaplay-headless`，以专门创建的系统用户 `nipaplay`
运行，服务 `nipaplay-headless.service` 开机自启。命令行入口是 `/usr/local/bin/nipaplay-headless`。
数据归 `nipaplay` 所有，所以设置命令都要以它的身份执行：`sudo -u nipaplay nipaplay-headless …`
（下面所有命令照此加前缀）。媒体库目录要让 `nipaplay` 用户读得到。

### 没有 systemd 的环境（容器等）

`install.sh` 检测到没有可用的 systemd 时，会装好文件、说明没有建服务，并给出前台运行方式：

```sh
nipaplay-headless          # 前台运行，Ctrl+C 停止；日志直接输出在终端
nipaplay-headless --stop   # 在另一个终端请求它停止
```

## 日常管理

用户级安装把 `systemctl` 换成 `systemctl --user`、`journalctl` 换成 `journalctl --user`；系统级安装直接用
`systemctl`、`journalctl`。

```sh
systemctl --user status  nipaplay-headless      # 状态
systemctl --user stop    nipaplay-headless      # 停止（正常关闭：先收尾再退出）
systemctl --user start   nipaplay-headless      # 启动
systemctl --user restart nipaplay-headless      # 重启
systemctl --user disable --now nipaplay-headless  # 取消开机自启并停止
journalctl --user -u nipaplay-headless -f       # 看日志（服务的输出都在 journal 里）
```

日志：服务输出进 systemd journal，没有单独的日志文件。Nipa 每个回合的过程在 `data/turn-process/`，
调用记录是 `data/journal.jsonl`。

这台机器本地的连接信息（地址、令牌）在 `data/endpoint.json`，只给本机使用，不要分享。

## 首次设置

下面的命令都是“这台机器上的人”做的事。账号密码和模型 key 都从**标准输入**进去，不放在命令行参数里，
所以不会出现在 shell 历史和进程列表里；Nipa 自己也改不了这些。服务可以一直开着，也可以先不管。

### 1. 登录弹弹play账号

没有账号登录，这台机器进不了设备网，也读不到弹弹play的资料。登录用 bash，密码输入时不回显：

```bash
( read -r -p '弹弹play账号: ' u; read -r -s -p '密码: ' pw; echo; printf '%s\n%s\n' "$u" "$pw" ) \
  | nipaplay-headless --login-dandanplay
```

成功会输出 `{"status":"signed_in",…}`，令牌存进数据目录的 `vault/`（目录 0700、文件 0600）。账号和密码不落盘。
登录之后**重启服务**，让它带着这个账号加入设备网：

```sh
systemctl --user restart nipaplay-headless
```

也可以在别的设备上已登录后，把令牌从标准输入交给这台机器：`printf %s "$TOKEN" | nipaplay-headless --enroll-token-stdin`。

设备网默认开启，协调服务是官方的 `https://nipaplay.aimes-soft.com/mesh`。不想加入设备网，在数据目录写
`mesh.json`：`{"enabled": false}`。要固定监听端口（建议，方便放行防火墙）：`{"port": 32123}`（改完重启）。
默认监听所有网卡，所有连接都要先通过同账号设备证书的双向 TLS，没有证书的连接在握手时就被拒绝；只想限制在本机，
写 `{"loopbackOnly": true}`。

### 2. 让 Nipa 在这台机器上运行（可选）

要同时满足：agent 开关开着（默认开）、模型已设置并有 key、运行环境已装。

**运行环境**（Node.js 加精简的 DeepSeek Harness，装在数据目录里，不动系统；官方源连不上会换 npmmirror）：

```sh
nipaplay-headless --dsh-install     # 下载并解压，约 60 MB
nipaplay-headless --dsh-status      # 将要启动的是哪一份
nipaplay-headless --dsh-check       # 启动一次并开一个线程，不调用模型
```

**模型**。key 从标准输入读（下面的 `read -s` 不回显、不进历史）：

```bash
read -r -s -p 'API key: ' KEY; echo
printf %s "$KEY" | nipaplay-headless --model-set \
  --provider NAME --base-url https://models.example/v1 --model MODEL_NAME \
  [--api responses|chat] [--reasoning low|medium|high] --key-stdin
unset KEY

nipaplay-headless --model-status    # 提供方、地址、模型、有没有 key（不含 key）
nipaplay-headless --model-check     # 向模型发一次很小的请求，看地址和 key 能不能用
nipaplay-headless --model-clear     # 删掉设置和 key
```

key 与提供方、地址绑定：改了地址而没有重新录入，旧 key 不会被发到新地址。

**agent 开关**（这台机器上能不能运行 Nipa）：

```sh
nipaplay-headless --agent-status
nipaplay-headless --agent-disable   # 关：停掉对话进程，所有对话入口都说明原因
nipaplay-headless --agent-enable    # 开
```

模型、开关、运行环境的变化由正在运行的服务自己发现，立即生效，不用重启（已在跑的回合下一回合起采用新设置）。
`nipaplay-headless nipa app.runtime` 里的 `conversationHost` 说明 Nipa 现在是 `running`、`disabled`、
`missing`（并列出缺什么）还是 `failed`。

### 3. 和 Nipa 对话

`nipaplay-headless nipa …` 就是这台机器 `data/harness/nipa` 客户端，自动连到本机正在运行的服务：

```sh
nipaplay-headless nipa chat say "这台机器的磁盘还剩多少" --wait 120   # 发话，等回合结束，打印回复和她执行的命令
nipaplay-headless nipa chat say "…"            # 只发起，回合在后台跑
nipaplay-headless nipa chat status --wait 55   # 回合状态
nipaplay-headless nipa chat read --turns 3     # 最近几个回合
nipaplay-headless nipa chat stop               # 中止正在跑的回合
nipaplay-headless nipa status                  # 服务状态
nipaplay-headless nipa list                    # 全部动作
```

同账号的其他设备上的 Nipa 也可以把事情交给这台机器上的 Nipa（需要它处于运行状态）。

## 升级

下载新版本的包，解压后在里面再运行一次 `./install.sh`（用户级或 `sudo ./install.sh --system`，与第一次相同；
`--media-root` 之类的选项要重新带上）。它会停掉服务、**只替换程序目录 `app/`**、重新建好服务并启动。数据目录不动，
数据库按版本自动迁移。

回退到旧版本：停止服务，用升级前备份的整个数据目录替换，再装旧包。不要用旧程序直接打开已被新版迁移过的数据库。
升级前想保险，先停服务再 `cp -a` 备份整个数据目录。

## 卸载

```sh
~/.local/share/nipaplay-headless/app/uninstall.sh            # 用户级
sudo /opt/nipaplay-headless/app/uninstall.sh                 # 系统级
```

默认删除程序、服务和命令入口，**数据目录原样保留**（重装后设备身份、模型设置都还在）。连数据一起删（设备身份、
数据库、模型 key、Nipa 的记忆，不可恢复；系统级还会删除用户 `nipaplay`）：

```sh
~/.local/share/nipaplay-headless/app/uninstall.sh --purge
```

## 数据目录里有什么

| 路径 | 含义 |
|---|---|
| `headless.json` | 格式标记，保存媒体库目录、端口 |
| `device.json`、`next.db` | 设备身份、任务、片库、绑定、元数据、设置 |
| `vault/` | 弹弹play令牌、模型 key 等秘密（0600） |
| `model.json`、`agent.json` | 模型设置（不含 key）、agent 开关 |
| `mesh.json`、`download.json`、`network.json` | 设备网、下载、网关路由的主机配置，按需创建 |
| `harness/` | Nipa 的工作目录：记忆、钩子、脚本、`nipa` 客户端 |
| `dsh-runtime/`、`dsh-home/` | Nipa 的运行环境和它的数据 |
| `downloads/`、`torrent-session/` | 下载目录和 BT 会话 |
| `endpoint.json`、`running.json`、`instance.lock` | 运行时文件；一个数据目录同时只能有一个实例 |

更多说明见源码仓库的 `docs/next/HEADLESS.md`。
