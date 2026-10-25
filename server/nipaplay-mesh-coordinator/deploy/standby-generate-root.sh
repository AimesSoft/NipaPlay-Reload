#!/bin/bash
# Standby server only: generate the standby root and keep its private key here.
# Installs no service, no user, no nginx change; nothing runs afterwards.
# usage: standby-generate-root.sh <binary> <expected-sha256>
set -euo pipefail
binary=${1:?usage: standby-generate-root.sh <binary> <expected-sha256>}
expected=${2:?usage: standby-generate-root.sh <binary> <expected-sha256>}
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
command -v openssl >/dev/null || { echo "openssl is needed to show the fingerprint" >&2; exit 1; }
actual=$(sha256sum "$binary" | awk '{print $1}')
[ "$actual" = "$expected" ] || { echo "sha256 mismatch: $actual" >&2; exit 1; }

home=${STANDBY_DIR:-/root/mesh-standby-root}
[ ! -e "$home" ] || { echo "$home exists; this script never replaces a root" >&2; exit 1; }
umask 077
mkdir -p "$home"
cp "$binary" "$home/nipaplay-mesh-coordinator"; chmod 700 "$home/nipaplay-mesh-coordinator"
"$home/nipaplay-mesh-coordinator" --generate-ca "$home/ca.crt.pem" "$home/ca.key.pem"
chmod 644 "$home/ca.crt.pem"
[ "$(stat -c %a "$home/ca.key.pem")" = 600 ] || { echo "key is not 0600" >&2; exit 1; }
echo
openssl x509 -in "$home/ca.crt.pem" -noout -subject -dates -fingerprint -sha256 -ext basicConstraints,keyUsage
ls -l "$home"
echo
echo "Fetch ONLY the certificate:  scp <server>:$home/ca.crt.pem ./standby-root.crt.pem"
echo "The key stays in $home/ca.key.pem (root only, 0600): no copy, no backup elsewhere."
