#!/bin/bash
# Step 3: generate the root on this server. The private key is created here
# (0600), moved into place, and never leaves this machine; only the public
# certificate is for the application. Refuses to replace an existing root.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/00-env.sh"
need_root
bin=$MESH_OPT/nipaplay-mesh-coordinator
[ -x "$bin" ] || die "run step 2 first"
[ ! -e "$MESH_OPT/ca.crt.pem" ] && [ ! -e "$MESH_ETC/ca.key.pem" ] || die "a root already exists; this script never replaces one"

umask 077
stage=$(mktemp -d /root/mesh-root-stage.XXXXXX)
trap 'rm -rf "$stage"' EXIT
"$bin" --generate-ca "$stage/ca.crt.pem" "$stage/ca.key.pem"
[ "$(stat -c %a "$stage/ca.key.pem")" = 600 ] || die "key is not 0600"
install -o root -g root -m 644 "$stage/ca.crt.pem" "$MESH_OPT/ca.crt.pem"
install -o "$MESH_USER" -g "$MESH_USER" -m 600 "$stage/ca.key.pem" "$MESH_ETC/ca.key.pem"
shred -u "$stage/ca.key.pem" 2>/dev/null || rm -f "$stage/ca.key.pem"
rm -rf "$stage"; trap - EXIT

say "The public root certificate (this is what goes into the application)"
openssl x509 -in "$MESH_OPT/ca.crt.pem" -noout -subject -issuer -dates -fingerprint -sha256 -ext basicConstraints,keyUsage
openssl x509 -in "$MESH_OPT/ca.crt.pem" -noout -text | grep -E "Signature Algorithm|Public Key Algorithm" | sort -u
ls -l "$MESH_OPT/ca.crt.pem" "$MESH_ETC/ca.key.pem"
echo
echo "Fetch ONLY the certificate:  scp <server>:$MESH_OPT/ca.crt.pem ./primary-root.crt.pem"
say "Step 3 done"
