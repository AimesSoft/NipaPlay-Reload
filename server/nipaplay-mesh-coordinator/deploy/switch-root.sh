#!/bin/bash
# Make the coordinator sign with the standby root instead of the primary one.
#
#   switch-root.sh to-standby <standby-ca.crt.pem> < standby-ca.key.pem
#   switch-root.sh back
#
# to-standby reads the standby PRIVATE key from stdin (pipe it from the standby
# server; do not save it anywhere else), installs both files for the service
# only, points the env file at them, restarts, and checks that /mesh/v1/server-info
# now advertises the standby certificate. Any failure puts the previous env back.
# After this the standby key lives on this server: plan a new standby root.
# `back` points the service at the primary root again (its files were never touched).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/00-env.sh"
need_root
mode=${1:-}
[ -f "$MESH_ENV" ] || die "no $MESH_ENV"
swap_env() { # swap_env <cert> <key>
  sed -i -E "s#^MESH_CA_CERT_FILE=.*#MESH_CA_CERT_FILE=$1#; s#^MESH_CA_KEY_FILE=.*#MESH_CA_KEY_FILE=$2#" "$MESH_ENV"
}
advertised_ok() { # advertised_ok <cert file>
  local info
  info=$(curl -fsS "http://127.0.0.1:$MESH_PORT/mesh/v1/server-info") || return 1
  [ "$(printf '%s' "$info" | python3 "$DEPLOY_DIR/jsonfield.py" serverCertificate)" = "$(cat "$1")" ]
}
restart_and_wait() {
  systemctl restart "$MESH_SERVICE"
  for _ in $(seq 1 20); do curl -fs "http://127.0.0.1:$MESH_PORT/healthz" >/dev/null && return 0; sleep 1; done
  return 1
}
case "$mode" in
  to-standby)
    crt=${2:?usage: switch-root.sh to-standby <standby-ca.crt.pem> < key}
    [ -f "$crt" ] || die "$crt not found"
    [ ! -e "$MESH_ETC/ca-standby.key.pem" ] || die "a standby key is already installed"
    umask 077
    key_tmp=$(mktemp "$MESH_ETC/.standby-key.XXXXXX")
    cat > "$key_tmp"
    [ -s "$key_tmp" ] || { rm -f "$key_tmp"; die "no key on stdin"; }
    install -o "$MESH_USER" -g "$MESH_USER" -m 600 "$key_tmp" "$MESH_ETC/ca-standby.key.pem"; shred -u "$key_tmp" 2>/dev/null || rm -f "$key_tmp"
    install -o root -g root -m 644 "$crt" "$MESH_OPT/ca-standby.crt.pem"
    cp -a "$MESH_ENV" "$STATE_DIR/env.before-switch"
    swap_env "$MESH_OPT/ca-standby.crt.pem" "$MESH_ETC/ca-standby.key.pem"
    if restart_and_wait && advertised_ok "$MESH_OPT/ca-standby.crt.pem"; then
      echo "now signing with the standby root:"; openssl x509 -in "$MESH_OPT/ca-standby.crt.pem" -noout -fingerprint -sha256
      echo "Devices change over as they renew (within one day before their certificate runs out, at most 7 days)."
    else
      cp -a "$STATE_DIR/env.before-switch" "$MESH_ENV"; rm -f "$MESH_ETC/ca-standby.key.pem" "$MESH_OPT/ca-standby.crt.pem"
      restart_and_wait || true
      die "the service would not sign with the standby root; the primary root is back and the standby key is removed again"
    fi
    ;;
  back)
    swap_env "$MESH_OPT/ca.crt.pem" "$MESH_ETC/ca.key.pem"
    restart_and_wait && advertised_ok "$MESH_OPT/ca.crt.pem" && echo "signing with the primary root again" || die "primary root did not come back; check journalctl -u $MESH_SERVICE"
    ;;
  *) sed -n 2,16p "$0"; exit 2 ;;
esac
