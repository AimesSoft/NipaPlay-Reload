#!/bin/bash
# Step 1: read-only checks, then a snapshot of what is running and a dated
# backup of the nginx site file. Changes nothing else. Safe to run again.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/00-env.sh"
need_root
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
fail=0
check() { # check <description> <command...>
  local description=$1; shift
  if "$@" >/dev/null 2>&1; then printf 'ok    %s\n' "$description"; else printf 'FAIL  %s\n' "$description"; fail=1; fi
}

say "Host"
uname -srm; { ldd --version | head -1; } || true; free -m | sed -n 1,2p
{ systemctl --version | head -1; } || true
echo "cgroup filesystem: $(stat -fc %T /sys/fs/cgroup) (cgroup2fs = v2; tmpfs = v1/hybrid, where MemoryMax= in the unit may not be enforced; the service is tiny, so this is only an extra guard)"
say "Disk (the mesh needs well under 100 MB; refuse to start with less than 300 MB free)"
df -h / | sed -n 1,2p
free_kb=$(df -Pk / | awk 'NR==2{print $4}')
[ "$free_kb" -ge 307200 ] && echo "ok    free space $((free_kb/1024)) MB" || { echo "FAIL  only $((free_kb/1024)) MB free"; fail=1; }

say "Nothing of ours is installed yet"
check "port $MESH_PORT is free" bash -c "! ss -ltnH 'sport = :$MESH_PORT' | grep -q ."
check "user $MESH_USER does not exist" bash -c "! id $MESH_USER"
for path in "$MESH_OPT" "$MESH_ETC" "$MESH_ENV" "$MESH_VAR" "$MESH_UNIT"; do
  check "$path does not exist" test ! -e "$path"
done

say "What the service needs"
check "the gateway listens on 127.0.0.1:$GATEWAY_PORT" bash -c "ss -ltnH 'sport = :$GATEWAY_PORT' | grep -q ."
check "systemctl exists" command -v systemctl
check "python3 with sqlite3 exists (backup and restore scripts)" python3 "$DEPLOY_DIR/backup-db.py" --check
check "curl exists" command -v curl
check "openssl exists" command -v openssl
check "nginx binary exists ($NGINX_BIN)" test -x "$NGINX_BIN"
check "site file exists ($NGINX_VHOST)" test -f "$NGINX_VHOST"
check "site file has the /dandanplay/ location" grep -q 'location \^~ /dandanplay/' "$NGINX_VHOST"
check "site file has no /mesh/ location yet" bash -c "! grep -q 'location \\^~ /mesh/' '$NGINX_VHOST'"
check "the current nginx configuration is valid" "$NGINX_BIN" -t
{ "$NGINX_BIN" -v 2>&1 | head -1; } || true

say "Snapshot of the running host, for comparison after the change"
ss -ltnp > "$STATE_DIR/listeners.before"
systemctl list-units --type=service --state=running --no-legend --plain > "$STATE_DIR/services.before"
{
  for path in / /dandanplay/healthz; do
    printf '%s %s\n' "$path" "$(curl -s $CURL_EXTRA --resolve "$SITE:$HTTPS_PORT:127.0.0.1" -o /dev/null -w '%{http_code}' "https://$SITE:$HTTPS_PORT$path" || true)"
  done
} > "$STATE_DIR/http.before"
cat "$STATE_DIR/http.before"
wc -l "$STATE_DIR/listeners.before" "$STATE_DIR/services.before"

say "Dated backup of the nginx site file and nginx.conf"
stamp=$(date +%Y%m%d-%H%M%S)
cp -a "$NGINX_VHOST" "$NGINX_VHOST.bak-$stamp"
echo "$NGINX_VHOST.bak-$stamp" | tee "$STATE_DIR/vhost.backup"
nginx_conf=$(dirname "$(dirname "$NGINX_BIN")")/conf/nginx.conf
[ -f "$nginx_conf" ] && cp -a "$nginx_conf" "$nginx_conf.bak-$stamp" && echo "$nginx_conf.bak-$stamp"
echo "(files ending .bak-* are not matched by the panel's *.conf include)"

[ "$fail" -eq 0 ] || die "some checks failed; fix them before step 2"
say "Step 1 done"
