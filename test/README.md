# Test suites

PR validation runs the portable Flutter suite:

```sh
flutter test --no-pub --reporter expanded \
  --exclude-tags 'native_integration || codex_integration || performance'
```

The excluded suites remain runnable explicitly. Missing prerequisites should
fail these explicit runs, rather than silently passing them.

| Tag | Prerequisites | Command |
| --- | --- | --- |
| `native_integration` | Rust toolchain, built Mesh native library/coordinator/issuer, OpenSSL, FFmpeg, and the Flutter JS QuickJS native library on the loader path | `flutter test --no-pub --tags native_integration --concurrency=1` |
| `codex_integration` | A compatible `codex` CLI and Git on `PATH`; these tests use a local fixture provider | `flutter test --no-pub --tags codex_integration --concurrency=1` |
| `performance` | A dedicated machine for the large-profile CPU benchmark | `flutter test --no-pub --tags performance --concurrency=1` |

Build the Mesh prerequisites before running its suites; the delegation and LAN
suites must not race another test's Cargo build. See the setup and evidence in
[`X47_REPORT`](../docs/next/archive/X47_REPORT.md). The plugin/backup experiments
also need a loadable QuickJS library; see
[`X18_REPORT`](../docs/next/archive/X18_REPORT.md) and
[`X21_REPORT`](../docs/next/archive/X21_REPORT.md).

The large-profile benchmark is not a portable PR gate. Its existing Linux
`database is locked` failure still needs investigation in the dedicated run;
excluding the benchmark does not establish that its database behavior is correct.
Functional database, migration, data preservation, Mesh unit and widget tests
remain in the PR suite.

The `Build tvOS` workflow validates the real build. Tests should not require its
shell commands to stay inline when they can live in a helper script, or require
tvOS to share the desktop Erika version when its dependency profile pins a
hosted release separately.
