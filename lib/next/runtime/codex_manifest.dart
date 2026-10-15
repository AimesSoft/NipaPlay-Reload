// Pinned GitHub Release metadata; no latest-version lookup at runtime.
const codexVersion = '0.144.1';
const codexRelease =
    'https://github.com/openai/codex/releases/download/rust-v0.144.1';

final class CodexAsset {
  const CodexAsset(this.name, this.sha256, this.bytes, this.executable);
  final String name, sha256, executable;
  final int bytes;
  String get url => '$codexRelease/$name';
}

const codexAssets = <String, CodexAsset>{
  'macos-arm64': CodexAsset(
      'codex-npm-darwin-arm64-0.144.1.tgz',
      '365a5685170f66bad58dd1dabb0462dfb824f82a870bcc8d9af2eb0a41cf2e18',
      120299266,
      'package/vendor/aarch64-apple-darwin/bin/codex'),
  'macos-x64': CodexAsset(
      'codex-npm-darwin-x64-0.144.1.tgz',
      '03e708c91834be795559a377b81cc12881e6d852ffa428693726f2a47e6132e0',
      128728164,
      'package/vendor/x86_64-apple-darwin/bin/codex'),
  'linux-arm64': CodexAsset(
      'codex-npm-linux-arm64-0.144.1.tgz',
      '25c66d4451c4f57df6b427173ed7d3d7e29c129d61dc58498dbdb946787b7655',
      123597069,
      'package/vendor/aarch64-unknown-linux-musl/bin/codex'),
  'linux-x64': CodexAsset(
      'codex-npm-linux-x64-0.144.1.tgz',
      'e2a64d421c10aaf0b7e3c0e8bd71b71e497d75823003318b674a278d71add0c7',
      131162436,
      'package/vendor/x86_64-unknown-linux-musl/bin/codex'),
  'windows-arm64': CodexAsset(
      'codex-npm-win32-arm64-0.144.1.tgz',
      '2846540881fa8fccdfbeb9a0a4270d771f5d15b8618766043132280c0d915afe',
      136014571,
      'package/vendor/aarch64-pc-windows-msvc/bin/codex.exe'),
  'windows-x64': CodexAsset(
      'codex-npm-win32-x64-0.144.1.tgz',
      'd6d1c36f4c5c921724c28500ba89e1e840fd791ec5cc8aca2de256695e1c1c17',
      145088030,
      'package/vendor/x86_64-pc-windows-msvc/bin/codex.exe'),
};
