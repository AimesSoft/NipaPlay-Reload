#!/usr/bin/env bash
# NipaPlay 无界面版安装脚本。
#
#   ./install.sh                     安装到 ~/.local/share/nipaplay-headless，建 systemd 用户服务
#   sudo ./install.sh --system       安装到 /opt/nipaplay-headless，建系统服务（专用系统用户 nipaplay）
#
# 选项：
#   --system             系统级安装（需要 root）
#   --data DIR           数据目录（默认：用户 <安装目录>/data；系统 /var/lib/nipaplay-headless）
#   --media-root DIR     只读媒体库目录，可重复；写进服务的启动参数
#   --no-service         只放文件，不建服务（容器、没有 systemd 的机器）
#   --no-start           建好服务并设为开机自启，但现在不启动
#   --help               显示本说明
#
# 重复执行即升级：只替换程序目录 app/，数据目录不动。
set -euo pipefail

package_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
mode=user
data_dir=
service=yes
start=yes
media_roots=()

say() { printf '%s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --system) mode=system ;;
    --data) [ $# -ge 2 ] || die "--data 需要一个目录"; data_dir=$2; shift ;;
    --media-root) [ $# -ge 2 ] || die "--media-root 需要一个目录"; media_roots+=("$2"); shift ;;
    --no-service) service=no ;;
    --no-start) start=no ;;
    --help|-h) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "不认识的选项：$1（用 --help 查看）" ;;
  esac
  shift
done

[ "$(uname -s)" = Linux ] || die "这个包只能装在 Linux 上。"
[ -x "$package_dir/libexec/nipaplay-headless-host" ] || die "包不完整：缺少 libexec/nipaplay-headless-host。"
case "$(uname -m)" in
  x86_64|amd64) machine=amd64 ;;
  aarch64|arm64) machine=arm64 ;;
  *) machine=$(uname -m) ;;
esac
want=$(cat "$package_dir/ARCH" 2>/dev/null || echo "$machine")
[ "$want" = "$machine" ] || die "这个包是 $want 的，本机是 $machine。"

for path in "${data_dir:-}" "${media_roots[@]+"${media_roots[@]}"}"; do
  [ -z "$path" ] && continue
  case "$path" in /*) ;; *) die "路径必须是绝对路径：$path" ;; esac
  case "$path" in *[[:space:]%\"\'\\]*) die "路径里不能有空白、引号、反斜杠或百分号：$path" ;; esac
done
for root in "${media_roots[@]+"${media_roots[@]}"}"; do
  [ -d "$root" ] || die "媒体库目录不存在：$root"
done

if [ "$mode" = system ]; then
  [ "$(id -u)" -eq 0 ] || die "--system 需要 root：请用 sudo ./install.sh --system"
  base=/opt/nipaplay-headless
  [ -n "$data_dir" ] || data_dir=/var/lib/nipaplay-headless
  unit_dir=/etc/systemd/system
  bin_dir=/usr/local/bin
  run_user=nipaplay
  systemctl_cmd=(systemctl)
else
  [ "$(id -u)" -ne 0 ] || die "以 root 身份请加 --system；用户级安装请用普通用户运行。"
  base=${XDG_DATA_HOME:-$HOME/.local/share}/nipaplay-headless
  [ -n "$data_dir" ] || data_dir=$base/data
  unit_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
  bin_dir=$HOME/.local/bin
  run_user=$(id -un)
  systemctl_cmd=(systemctl --user)
  if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$(id -u)" ]; then
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
  fi
fi
app=$base/app
unit_name=nipaplay-headless.service
version=$(cat "$package_dir/VERSION" 2>/dev/null || echo unknown)

# 能不能管理服务：systemd 正在运行，且（用户级）用户管理器可用。
have_systemd=no
if [ "$service" = yes ]; then
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 &&
     "${systemctl_cmd[@]}" show --property=Version >/dev/null 2>&1; then
    have_systemd=yes
  fi
fi

# ---- 数据目录的归属检查：已有数据目录不能是别的用户的 ----
if [ "$mode" = system ]; then
  if ! id -u "$run_user" >/dev/null 2>&1; then
    command -v useradd >/dev/null 2>&1 || die "找不到 useradd，无法创建系统用户 $run_user。"
    useradd --system --home-dir "$data_dir" --no-create-home --shell /usr/sbin/nologin "$run_user"
    say "已创建系统用户 $run_user。"
  fi
fi

# ---- 停掉旧服务（升级），替换程序目录 ----
was_active=no
if [ "$have_systemd" = yes ] && "${systemctl_cmd[@]}" is-active --quiet "$unit_name" 2>/dev/null; then
  was_active=yes
  say "停止正在运行的服务以替换程序……"
  "${systemctl_cmd[@]}" stop "$unit_name"
fi

mkdir -p "$base"
rm -rf "$app.new"
mkdir -p "$app.new"
cp -a "$package_dir/libexec" "$package_dir/bin" "$package_dir/assets" "$app.new/"
for file in VERSION ARCH README.md uninstall.sh; do
  [ -e "$package_dir/$file" ] && cp -a "$package_dir/$file" "$app.new/"
done
[ -e "$package_dir/LICENSE" ] && cp -a "$package_dir/LICENSE" "$app.new/"
cp -a "$package_dir/install.sh" "$app.new/install.sh"
printf '%s\n' "$data_dir" > "$app.new/data-dir"
{
  printf 'MODE=%s\n' "$mode"
  printf 'BASE=%s\n' "$base"
  printf 'DATA=%s\n' "$data_dir"
  printf 'UNIT_DIR=%s\n' "$unit_dir"
  printf 'BIN_DIR=%s\n' "$bin_dir"
  printf 'RUN_USER=%s\n' "$run_user"
  printf 'SERVICE=%s\n' "$service"
} > "$app.new/install.env"
rm -rf "$app.old"
[ -e "$app" ] && mv "$app" "$app.old"
mv "$app.new" "$app"
rm -rf "$app.old"
if [ "$mode" = system ]; then
  chmod -R go+rX "$base"
fi

mkdir -p "$data_dir"
if [ "$mode" = system ]; then
  chown "$run_user":"$(id -gn "$run_user")" "$data_dir"
  chmod 750 "$data_dir"
else
  chmod 700 "$data_dir"
fi

# ---- 初始化数据目录（写入格式标记，之后才可以放 mesh.json 之类的配置文件）----
as_run_user=()
if [ "$mode" = system ]; then
  if command -v runuser >/dev/null 2>&1; then as_run_user=(runuser -u "$run_user" --); else as_run_user=(none); fi
fi
if [ "${as_run_user[0]:-}" != none ]; then
  if ! "${as_run_user[@]+"${as_run_user[@]}"}" "$app/libexec/nipaplay-headless-host" --data "$data_dir" --agent-status >/dev/null 2>&1; then
    say "注意：数据目录没能初始化（$data_dir）。检查缺少的系统库（libsqlite3 等，见 README 的“要求”）。"
  fi
fi

# ---- 命令行入口 ----
mkdir -p "$bin_dir"
ln -sfn "$app/bin/nipaplay-headless" "$bin_dir/nipaplay-headless"

say "已安装 NipaPlay 无界面版 $version"
say "  程序目录  $app"
say "  数据目录  $data_dir"
say "  命令      $bin_dir/nipaplay-headless"
case ":$PATH:" in *":$bin_dir:"*) ;; *) say "  提示：$bin_dir 不在 PATH 里，请加入 PATH，或用完整路径运行。" ;; esac

# ---- 服务 ----
exec_start="$app/libexec/nipaplay-headless-host --data $data_dir"
for root in "${media_roots[@]+"${media_roots[@]}"}"; do
  exec_start="$exec_start --media-root $root"
done

write_unit() {
  mkdir -p "$unit_dir"
  {
    echo '[Unit]'
    echo 'Description=NipaPlay headless host'
    if [ "$mode" = system ]; then
      echo 'After=network-online.target'
      echo 'Wants=network-online.target'
    fi
    echo
    echo '[Service]'
    echo 'Type=simple'
    echo "ExecStart=$exec_start"
    echo "WorkingDirectory=$app"
    echo 'Restart=on-failure'
    echo 'RestartSec=5'
    echo 'TimeoutStopSec=30'
    echo 'Environment=PATH=/usr/local/bin:/usr/bin:/bin'
    if [ "$mode" = system ]; then
      echo "User=$run_user"
      echo 'NoNewPrivileges=yes'
    fi
    echo
    echo '[Install]'
    if [ "$mode" = system ]; then echo 'WantedBy=multi-user.target'; else echo 'WantedBy=default.target'; fi
  } > "$unit_dir/$unit_name"
}

if [ "$service" = no ]; then
  say
  say "按要求没有建服务。前台运行："
  say "  $bin_dir/nipaplay-headless"
elif [ "$have_systemd" = no ]; then
  say
  say "注意：这台机器没有可用的 systemd${mode:+（$mode 级）}，没有建开机自启服务。"
  say "程序已装好，可以前台运行（Ctrl+C 停止）："
  say "  $bin_dir/nipaplay-headless"
  if [ "$mode" = user ] && [ -d /run/systemd/system ]; then
    say "systemd 在运行，但用户管理器不可用；通常是用 su 或 sudo 切换用户所致，请直接以该用户登录（ssh）后重新运行 install.sh。"
  fi
else
  write_unit
  "${systemctl_cmd[@]}" daemon-reload
  if [ "$start" = yes ]; then
    "${systemctl_cmd[@]}" enable --now "$unit_name"
    sleep 2
    if "${systemctl_cmd[@]}" is-active --quiet "$unit_name"; then
      say "服务已启动，并设为开机自启。"
    else
      say "服务没有保持运行，查看原因："
      if [ "$mode" = system ]; then say "  journalctl -u nipaplay-headless -n 50"; else say "  journalctl --user -u nipaplay-headless -n 50"; fi
    fi
  else
    "${systemctl_cmd[@]}" enable "$unit_name"
    say "服务已建好，并设为开机自启；现在没有启动（--no-start）。"
  fi
  if [ "$mode" = user ]; then
    linger=$(loginctl show-user "$(id -un)" --property=Linger --value 2>/dev/null || echo unknown)
    if [ "$linger" != yes ]; then
      say
      say "注意：用户服务默认只在你登录期间运行。要让它在开机后、没人登录时也运行，需要管理员执行一次："
      say "  sudo loginctl enable-linger $(id -un)"
    fi
  fi
fi

say
say "下一步（详见 $app/README.md）："
say "  1. 登录弹弹play、设置模型：见 README 的“首次设置”"
if [ "$mode" = system ]; then
  say "  2. 系统级安装的数据归 $run_user 所有，设置命令请用 sudo -u $run_user nipaplay-headless …"
fi
