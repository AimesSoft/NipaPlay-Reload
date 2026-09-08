# NipaPlay compatibility patch

Vendored from `librqbit-dualstack-sockets` 0.7.0 on crates.io, upstream commit
`e2f221ca745c25c7790abb593ed260ce5a499fa1`:
https://github.com/ikatson/librqbit-dualstack-sockets

The only production source change is in `src/bind_device.rs`: use the existing
macOS implementation for all Apple targets and exclude those targets from the
`bind_device` fallback. `socket2` 0.6.3 exposes `bind_device_by_index_v4/v6` on
iOS, macOS, tvOS, watchOS, and visionOS; `bind_device` is unavailable there.

This fixes the iOS `aarch64-apple-ios` compilation failure in release run #1018
without downgrading librqbit 9.0.1 or changing Linux, Android, or Windows behavior.
Remove the `[patch.crates-io]` entry and this directory when upgrading to an
upstream release containing the equivalent fix. The upstream license is in
`LICENSE`.

Verify from `rust/`:

```sh
cargo check --locked -p librqbit-dualstack-sockets --target aarch64-apple-ios
cargo check --locked -p librqbit-dualstack-sockets --target aarch64-apple-ios-sim
```
