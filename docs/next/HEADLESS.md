# NipaPlay Linux 无界面版

无界面宿主提供媒体目录、下载、Mesh 和可选的本机梨花，不提供播放器窗口。它使用独立数据目录，不与 GUI 共用数据库。发行包、平台和版本以 [GitHub 发行页](https://github.com/AimesSoft/nipaplay-reload/releases) 为准；包内 README 是安装脚本的配套说明。

## 要求与安装

Linux x86_64（amd64）或 aarch64（arm64），glibc 2.35 以上，系统 SQLite 动态库和根证书。使用 `nipa` 客户端需要 Python 3.9 以上；服务安装需要可用的 systemd，否则可以前台运行。本机梨花还需要可用运行环境、模型和网络。

下载对应架构的 `NipaPlay-Headless_<版本>_Linux_<架构>.tar.gz`，解压后：

```sh
tar xzf NipaPlay-Headless_<版本>_Linux_<架构>.tar.gz
cd nipaplay-headless
./install.sh --media-root /srv/media
```

将文件名及媒体目录替换成实际值。默认普通用户安装，程序在 `${XDG_DATA_HOME:-~/.local/share}/nipaplay-headless/app/`，数据在同一目录的 `data/`，命令入口为 `~/.local/bin/nipaplay-headless`；脚本显示实际路径。媒体根目录必须存在且进程可读，`--media-root` 可重复，指定后每次启动以所给列表为准；不指定则沿用保存的列表。`--data` 可指定独立绝对数据路径；安装脚本的路径不能含空白、引号、反斜杠或 `%`。数据目录和媒体根不能互相包含，也不能与 GUI 或另一运行实例共享。

默认在 systemd 可用时创建并启动用户服务；`--no-start` 建立服务但不立即启动，`--no-service` 不创建服务。用户服务能否在退出登录后运行取决于系统设置；需要时管理员可为用户启用 systemd linger。系统级安装使用 `sudo ./install.sh --system --media-root /srv/media`，以专用 `nipaplay` 用户运行；后续数据操作使用 `sudo -u nipaplay nipaplay-headless ...`，并确保该用户能读取媒体目录。

## 日常运行

用户服务：

```sh
systemctl --user status nipaplay-headless
systemctl --user stop nipaplay-headless
systemctl --user start nipaplay-headless
journalctl --user -u nipaplay-headless -f
```

系统服务去掉 `--user`。无 systemd 或使用 `--no-service` 时，运行 `nipaplay-headless` 前台启动，在另一终端用 `nipaplay-headless --stop` 请求停止；同一数据目录不能同时启动服务和前台实例。服务日志在 journal，`data/endpoint.json` 包含本机连接凭据，不要分享。

## 登录与 Mesh

在运行宿主的机器上登录弹弹play，密码从标准输入读取且不回显：

```bash
( read -r -p '弹弹play账号: ' account; read -r -s -p '密码: ' password; echo; printf '%s\n%s\n' "$account" "$password" ) | nipaplay-headless --login-dandanplay
systemctl --user restart nipaplay-headless
```

系统服务使用对应用户运行登录命令并重启系统服务。成功状态以命令输出为准；令牌保存在数据目录的保险库中。设备网使用同账号认证，媒体和调用需要设备间网络可达，并不保证 NAT 穿透或中继。

加入 Mesh 意味着信任同账号认证设备访问本机开放的能力及进程可访问的文件，不只是共享媒体库；仅加入可信设备。默认监听策略和地址可在数据目录的 `mesh.json` 配置，例如 `{"enabled":false}` 关闭组网，`{"loopbackOnly":true}` 限制本机监听，或设置 `{"port":32123}` 固定端口；修改后重启。防火墙需允许实际使用的连接，远程运行程序另受目标宿主授权。

## 本机梨花（可选）

运行需要 Agent 开关、已安装的 DSH 运行环境和配置好的模型。按架构以运行环境状态和发行包说明为准；运行环境不支持时宿主其他能力仍可使用。

```sh
nipaplay-headless --dsh-install
nipaplay-headless --dsh-status
nipaplay-headless --dsh-check
```

模型地址和名称由服务商提供；在 Bash 中可不回显地输入密钥：

```bash
read -r -s -p 'API key: ' model_key; echo
printf %s "$model_key" | nipaplay-headless --model-set \
  --provider PROVIDER --base-url https://models.example/v1 --model MODEL --key-stdin
unset model_key
nipaplay-headless --model-status
nipaplay-headless --model-check
```

替换占位符并按服务商选择接口；`--model-check` 会向模型发送请求，可能产生费用。对话及任务所需内容可能发送给所选服务商。用 `--agent-status` 查看状态，`--agent-disable` / `--agent-enable` 控制本机梨花。主机启动过且梨花可用后，可运行 `nipaplay-headless nipa chat say "检查磁盘空间" --wait 120`；系统安装需以数据所有者执行。

## 备份、升级与恢复

停止服务或前台进程，备份整个实际数据目录及需要保留的外部媒体文件；备份包含数据库、harness、设备身份及保险库秘密，应限制访问。升级时解压新包，使用与原安装相同的模式重新运行 `install.sh`，并重新提供所需的 `--data`、`--media-root` 等选项。脚本替换程序目录并保留数据，数据库可能随版本迁移。

回退前停止服务，保留现状副本，再用升级前的整目录备份在同一机器恢复并安装旧包；不要让旧程序直接打开已迁移的数据库。跨机器不要复制身份到同时在线的设备；迁移边界见[数据与恢复](DATA_AND_RECOVERY.md)。

## 卸载

用户级从安装目录运行 `~/.local/share/nipaplay-headless/app/uninstall.sh`（自定义 XDG 目录以实际路径为准）；系统级使用 `sudo /opt/nipaplay-headless/app/uninstall.sh`。默认保留数据；`--purge` 同时删除数据和秘密，无法恢复。历史开发与实验记录见[归档](development/history/headless-development-notes.md)，不是安装指南。
