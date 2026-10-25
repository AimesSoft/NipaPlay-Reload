#!/bin/bash
# Step 6: check the service, the route through nginx, the issuer it advertises,
# and that nothing that was running before has changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/00-env.sh"
need_root
fail=0
ok() { printf 'ok    %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }

say "Service"
systemctl is-active --quiet "$MESH_SERVICE" && ok "active" || bad "not active"
[ "$(systemctl show -p User --value "$MESH_SERVICE")" = "$MESH_USER" ] && ok "runs as $MESH_USER" || bad "wrong user"
curl -fsS "http://127.0.0.1:$MESH_PORT/healthz" | grep -q '"ok":true' && ok "127.0.0.1:$MESH_PORT/healthz" || bad "loopback healthz"
ss -ltnH "sport = :$MESH_PORT" | grep -q "127.0.0.1:$MESH_PORT" && ok "listens on loopback only" || bad "listener"

say "Through nginx ($SITE)"
base="https://$SITE:$HTTPS_PORT"
via() { curl -fsS $CURL_EXTRA --resolve "$SITE:$HTTPS_PORT:127.0.0.1" "$@"; }
via "$base/mesh/healthz" | grep -q '"ok":true' && ok "$base/mesh/healthz" || bad "/mesh/healthz"
info=$(via "$base/mesh/v1/server-info") && ok "$base/mesh/v1/server-info" || { info=; bad "/mesh/v1/server-info"; }
if [ -n "$info" ]; then
  advertised=$(printf '%s' "$info" | python3 "$DEPLOY_DIR/jsonfield.py" serverCertificate)
  root_file=$(sed -n 's/^MESH_CA_CERT_FILE=//p' "$MESH_ENV")   # the root the service is configured to sign with
  [ "$advertised" = "$(cat "$root_file")" ] && ok "server-info advertises the configured root ($root_file)" || bad "server-info certificate differs from $root_file"
  printf '%s' "$info" | python3 "$DEPLOY_DIR/jsonfield.py" heartbeatIntervalSeconds | sed 's/^/      heartbeat seconds: /'
fi
code=$(via -o /dev/null -w "%{http_code}" "$base/mesh/v1/devices" 2>/dev/null || true)
[ "$code" = 401 ] && ok "an unauthenticated /mesh/v1/devices is refused (401)" || bad "/mesh/v1/devices answered $code, expected 401"

say "Nothing else changed"
if [ -f "$STATE_DIR/http.before" ]; then
  {
    for path in / /dandanplay/healthz; do
      printf '%s %s\n' "$path" "$(curl -s $CURL_EXTRA --resolve "$SITE:$HTTPS_PORT:127.0.0.1" -o /dev/null -w '%{http_code}' "$base$path" || true)"
    done
  } > "$STATE_DIR/http.after"
  diff "$STATE_DIR/http.before" "$STATE_DIR/http.after" && ok "existing routes answer as before: $(tr '\n' ' ' < "$STATE_DIR/http.after")" || bad "an existing route answers differently"
  ss -ltnp > "$STATE_DIR/listeners.after"
  systemctl list-units --type=service --state=running --no-legend --plain > "$STATE_DIR/services.after"
  added=$(diff <(awk '{print $4}' "$STATE_DIR/listeners.before" | sort -u) <(awk '{print $4}' "$STATE_DIR/listeners.after" | sort -u) | grep '^[<>]' || true)
  echo "listener changes:"; echo "${added:-  (none)}" | sed 's/^/  /'
  diff <(awk '{print $1}' "$STATE_DIR/services.before") <(awk '{print $1}' "$STATE_DIR/services.after") | grep '^[<>]' | sed 's/^/service change: /' || true
else
  echo "(no snapshot from step 1 found; skipped)"
fi
[ "$fail" -eq 0 ] && say "ALL CHECKS PASSED" || die "some checks failed"
