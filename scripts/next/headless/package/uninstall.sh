#!/usr/bin/env bash
# NipaPlay 无界面版卸载脚本。
#
#   ~/.local/share/nipaplay-headless/app/uninstall.sh            卸载用户级安装
#   sudo /opt/nipaplay-headless/app/uninstall.sh                 卸载系统级安装
#
# 默认只删程序、服务和命令入口，数据目录原样保留；--purge 连数据一起删（含设备身份、
# 数据库、模型 key、Nipa 的记忆），不可恢复。
#   --system   从解压出来的安装包目录运行时，指明要卸载系统级安装
#   --purge    同时删除数据目录（系统级安装还会删除系统用户 nipaplay）
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
mode=
purge=no
say() { printf '%s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --system) mode=system ;;
    --purge) purge=yes ;;
    --help|-h) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "不认识的选项：$1" ;;
  esac
  shift
done

# 从安装目录运行时，安装记录就在旁边；从安装包目录运行时，按默认位置去找。
if [ -f "$here/install.env" ]; then
  env_file=$here/install.env
else
  if [ "$mode" = system ]; then
    env_file=/opt/nipaplay-headless/app/install.env
  else
    env_file=${XDG_DATA_HOME:-$HOME/.local/share}/nipaplay-headless/app/install.env
  fi
fi
[ -f "$env_file" ] || die "没有找到安装记录 $env_file；没有装过，或位置不是默认的。"
# shellcheck disable=SC1090
MODE= BASE= DATA= UNIT_DIR= BIN_DIR= RUN_USER=
while IFS='=' read -r key value; do
  case "$key" in
    MODE) MODE=$value ;; BASE) BASE=$value ;; DATA) DATA=$value ;;
    UNIT_DIR) UNIT_DIR=$value ;; BIN_DIR) BIN_DIR=$value ;; RUN_USER) RUN_USER=$value ;;
  esac
done < "$env_file"
[ -n "$BASE" ] && [ -n "$DATA" ] || die "安装记录不完整：$env_file"

if [ "$MODE" = system ]; then
  [ "$(id -u)" -eq 0 ] || die "卸载系统级安装需要 root：请用 sudo。"
  systemctl_cmd=(systemctl)
else
  [ "$(id -u)" -ne 0 ] || die "这是用户级安装，请用安装它的普通用户运行。"
  systemctl_cmd=(systemctl --user)
  if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$(id -u)" ]; then
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
  fi
fi
unit=nipaplay-headless.service

if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 &&
   "${systemctl_cmd[@]}" show --property=Version >/dev/null 2>&1; then
  "${systemctl_cmd[@]}" disable --now "$unit" >/dev/null 2>&1 || true
  rm -f "$UNIT_DIR/$unit"
  "${systemctl_cmd[@]}" daemon-reload || true
  "${systemctl_cmd[@]}" reset-failed "$unit" >/dev/null 2>&1 || true
else
  # 没有 systemd：只可能是前台运行过。有在运行的实例就请它自己停。
  if [ -f "$DATA/running.json" ]; then
    "$BASE/app/libexec/nipaplay-headless-host" --stop --data "$DATA" >/dev/null 2>&1 || true
  fi
  rm -f "$UNIT_DIR/$unit"
fi

link=$BIN_DIR/nipaplay-headless
if [ -L "$link" ] && [ "$(readlink "$link")" = "$BASE/app/bin/nipaplay-headless" ]; then
  rm -f "$link"
fi

# 程序目录里的 uninstall.sh 正在运行；bash 读脚本是按需读的，先整个读进内存再删更稳妥，
# 所以删除放在最后一步，且这一步之后不再有命令。
if [ "$purge" = yes ]; then
  say "按 --purge 删除数据目录 $DATA"
  rm -rf "$DATA"
  if [ "$MODE" = system ] && id -u "$RUN_USER" >/dev/null 2>&1; then
    userdel "$RUN_USER" 2>/dev/null || say "没能删除系统用户 $RUN_USER，请手动处理。"
  fi
  rm -rf "$BASE/app"
  rmdir "$BASE" 2>/dev/null || rm -rf "$BASE"
  say "已卸载 NipaPlay 无界面版，数据已删除。"
else
  rm -rf "$BASE/app"
  say "已卸载 NipaPlay 无界面版的程序和服务。"
  say "数据目录原样保留：$DATA"
  say "不要数据了，请再运行带 --purge 的卸载，或手动删除该目录。"
fi
exit 0
