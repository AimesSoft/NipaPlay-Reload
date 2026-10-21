# NipaPlay compatibility patch

Vendored from `librqbit-peer-protocol` 9.0.1 on crates.io
(https://github.com/ikatson/rqbit, `crates/peer_binary_protocol`).

The only production source change is in `src/extended/handshake.rs`: the
extended handshake's `m` dictionary gets `#[serde(default)]`. BEP 10 makes every
key optional, and Transmission omits `m` for private torrents (it offers no
extensions there). Without the patch librqbit fails to parse that handshake,
drops the peer and backs off, so private torrents seeded by Transmission never
download. The same fix is upstream as rqbit commit `07cb766` ("fix(peer): accept
extended handshake missing the `m` dictionary", 2026-09-26), not yet released.

Remove the `[patch.crates-io]` entry and this directory when upgrading to an
upstream release containing that commit. The upstream license is in `LICENSE`.

The patch adds one test, `nipaplay_tests::a_handshake_without_m_is_accepted`,
which decodes Transmission 4.1.3's handshake for a private torrent. The crate is
not a workspace member and its own older tests include a file from the rqbit
repository, so run it on a copy outside the workspace with that file stubbed:

```sh
cp -R rust/third_party/librqbit-peer-protocol /tmp/pp && cd /tmp/pp
mkdir -p ../librqbit/resources/test && printf de > ../librqbit/resources/test/extended-handshake.bin
cargo test nipaplay_tests   # fails with "missing field `m`" without the patch
```
