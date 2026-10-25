#!/bin/bash
# rollback.sh nginx | service | binary | purge --yes-delete-the-root-key
#   nginx    take the /mesh/ location out of the site (marked block only), test, reload
#   service  stop and disable the service, remove unit and env file (data and root stay)
#   binary   put the previous binary back and restart
#   purge    remove everything this deployment created, including the root key
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/00-env.sh"
need_root
case "${1:-}" in
  nginx)
    new=$(mktemp "$NGINX_VHOST.new.XXXXXX"); trap 'rm -f "$new"' EXIT
    python3 "$DEPLOY_DIR/nginx_location.py" remove "$NGINX_VHOST" > "$new"
    diff -u "$NGINX_VHOST" "$new" || true
    cp -a "$NGINX_VHOST" "$STATE_DIR/vhost.before-rollback"
    cat "$new" > "$NGINX_VHOST"
    if ! "$NGINX_BIN" -t; then cat "$STATE_DIR/vhost.before-rollback" > "$NGINX_VHOST"; die "nginx -t failed; site file restored"; fi
    "$NGINX_BIN" -s reload && sleep 1 && echo "nginx reloaded without /mesh/"
    ;;
  service)
    systemctl disable --now "$MESH_SERVICE" || true
    rm -f "$MESH_UNIT" "$MESH_ENV"; systemctl daemon-reload
    echo "service removed; $MESH_VAR and the root are untouched"
    ;;
  binary)
    target=$MESH_OPT/nipaplay-mesh-coordinator
    [ -f "$target.prev" ] || die "no previous binary ($target.prev)"
    systemctl stop "$MESH_SERVICE" || true
    mv "$target" "$target.rolled-back"; mv "$target.prev" "$target"
    systemctl start "$MESH_SERVICE"; sleep 1
    curl -fsS "http://127.0.0.1:$MESH_PORT/healthz"; echo
    echo "now running $(sha256sum "$target" | awk '{print $1}'); the replaced build is $target.rolled-back"
    ;;
  purge)
    [ "${2:-}" = "--yes-delete-the-root-key" ] || die "this deletes the root private key for good; pass --yes-delete-the-root-key"
    systemctl disable --now "$MESH_SERVICE" 2>/dev/null || true
    rm -f "$MESH_UNIT" "$MESH_ENV"; systemctl daemon-reload
    rm -rf "$MESH_OPT" "$MESH_ETC" "$MESH_VAR"
    id "$MESH_USER" >/dev/null 2>&1 && userdel "$MESH_USER" || true
    echo "purged"
    ;;
  *) sed -n 2,7p "$0"; exit 2 ;;
esac
