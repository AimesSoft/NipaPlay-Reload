#!/bin/bash
# Step 4: install the env file (only if there is none) and the systemd unit,
# start the service and wait for it to answer on loopback.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/00-env.sh"
need_root
[ -x "$MESH_OPT/nipaplay-mesh-coordinator" ] || die "run step 2 first"
[ -f "$MESH_OPT/ca.crt.pem" ] && [ -f "$MESH_ETC/ca.key.pem" ] || die "run step 3 first"
ss -ltnH "sport = :$GATEWAY_PORT" | grep -q . || die "the gateway is not listening on 127.0.0.1:$GATEWAY_PORT"
ss -ltnH "sport = :$MESH_PORT" | grep -q . && die "port $MESH_PORT is taken"

if [ ! -e "$MESH_ENV" ]; then
  install -o root -g "$MESH_USER" -m 640 "$DEPLOY_DIR/nipaplay-mesh-coordinator.env.example" "$MESH_ENV"
  echo "installed $MESH_ENV"
else
  echo "keeping existing $MESH_ENV"
fi
grep -E '^(MESH_LISTEN_ADDR|MESH_DATABASE_PATH|MESH_CA_|DANDANPLAY_GATEWAY_BASE|MESH_ACCOUNT_CLAIM_POINTER|RUST_LOG)' "$MESH_ENV"

install -o root -g root -m 644 "$DEPLOY_DIR/nipaplay-mesh-coordinator.service" "$MESH_UNIT"
systemctl daemon-reload
systemctl enable --now "$MESH_SERVICE"

for _ in $(seq 1 20); do
  curl -fs "http://127.0.0.1:$MESH_PORT/healthz" >/dev/null && break
  sleep 1
done
curl -fsS "http://127.0.0.1:$MESH_PORT/healthz" || { journalctl -u "$MESH_SERVICE" -n 30 --no-pager; die "the service did not come up"; }
echo
systemctl --no-pager --lines=0 status "$MESH_SERVICE" | sed -n 1,6p
journalctl -u "$MESH_SERVICE" -n 5 --no-pager
say "Step 4 done"
