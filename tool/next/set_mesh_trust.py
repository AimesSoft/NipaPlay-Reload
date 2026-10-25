#!/usr/bin/env python3
"""Writes the two public root certificates into lib/next/mesh/trust.dart.

  python3 tool/next/set_mesh_trust.py primary-root.crt.pem standby-root.crt.pem

Only certificates (never keys) are accepted. Each one is checked with openssl
(self-signed CA, Ed25519, not expired) before the file is touched; afterwards run
  dart run tool/next/check_mesh_trust.dart
"""
import pathlib, re, subprocess, sys

if len(sys.argv) != 3:
    sys.exit(__doc__)
target = pathlib.Path(__file__).resolve().parents[2] / "lib/next/mesh/trust.dart"
pems = []
for path in sys.argv[1:]:
    text = pathlib.Path(path).read_text()
    if "PRIVATE KEY" in text:
        sys.exit(f"{path} contains a private key: refuse")
    blocks = re.findall(r"-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\s]+?-----END CERTIFICATE-----", text)
    if len(blocks) != 1:
        sys.exit(f"{path}: expected exactly one certificate, found {len(blocks)}")
    pem = blocks[0].strip() + "\n"
    info = subprocess.run(["openssl", "x509", "-noout", "-text", "-checkend", "0"], input=pem, capture_output=True, text=True)
    if info.returncode != 0:
        sys.exit(f"{path}: openssl rejects it or it has expired:\n{info.stderr}")
    for needle in ("CA:TRUE", "Certificate Sign", "ED25519"):
        if needle not in info.stdout:
            sys.exit(f"{path}: not an Ed25519 CA that may sign certificates ({needle} missing)")
    pems.append(pem)
if pems[0] == pems[1]:
    sys.exit("the primary and the standby root are the same certificate")
literal = "const _builtInIssuerPem = '''" + "".join(pems) + "''';"
source = target.read_text()
new, count = re.subn(r"const _builtInIssuerPem = (?:'''.*?'''|'');", lambda _: literal, source, count=1, flags=re.S)
if count != 1:
    sys.exit("could not find `const _builtInIssuerPem` in trust.dart")
target.write_text(new)
print("wrote", target)
