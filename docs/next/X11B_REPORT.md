# X11B：实验凭据保险库改用文件

2026-10-11，worktree `~/Desktop/nipaplay-next-wt/lab-vault`，分支 `next/lab-vault`。

## 1. 完成了什么

- macOS Debug 的 `NIPAPLAY_PROFILE` 实例使用 `<实验根目录>/credential-vault.json`，不再调用登录钥匙串。实验根目录为 0700，保险库与暂存文件创建权限为 0600，所有者为当前用户。
- 删除 `LabVaultBroker`、代理启动参数、子进程及管道协议；保留现有 `DesktopCredentialVault` 的 `labVault` MethodChannel 接口，改由同进程的 `LabFileVault` 处理全部 namespace 的读、写、删除。
- 实验进程及继承其限制的子进程不能读取 `~/Library/Keychains`，不能查找 `com.apple.SecurityServer`、`com.apple.securityd.xpc`、`com.apple.securityd` 服务。Rust 的系统保险库读、写、删除入口在实验配置下直接返回 `lab_system_vault_disabled`，不进入 Keychain API。
- `credentials.status` 在实验配置返回 `backend: labFile`；实验凭据失败提示和 `credentials.retry` 说明改为文件后端，不再指导用户授权登录钥匙串。现有 Action 和 GUI 继续使用同一保险库接口，没有新增登录秘密输入能力。
- 未设置 profile 时仍走原 Rust 系统保险库，service、account 编码、授权错误、拒绝后的停止重试与真实实例的“不回落明文”语义保持原实现。Release 继续忽略 profile。

实现位于 `macos/Runner/SandboxMigration.swift`、`macos/Runner/MainFlutterWindow.swift`、`rust/src/vault.rs` 和两个凭据状态/提示 Dart 文件；新增独立原生数据约束检查 `macos/RunnerTests/LabFileVaultTests.swift`。

交付是此 worktree 的源码及 `build/macos/Build/Products/Debug/NipaPlay.app`；没有覆盖 `~/Applications/NipaPlay-Lab.app` 或任何真实实例包。

## 2. 决策

1. 按主控决定，实验保险库使用明文 JSON，仅保存一次性测试凭据。它是实验配置的独立后端，不是系统保险库失败后的回落路径；任何文件操作失败都返回错误。
2. 保留 Dart 接口和凭据引用结构，使用现有原生串行队列处理文件操作。隔离来自每个 profile 自己的根目录，文件内账号继续使用 UTF-8 长度前缀，无需 `lab:<profile>:` 钥匙串 namespace。偏好、插件、服务器、metadata、Mesh 等现有调用均经过该后端。
3. 在实验目录内以 `O_CREAT | O_EXCL | O_NOFOLLOW` 创建随机 0600 暂存文件，写入并同步后 rename 替换。读取仅接受当前用户所有、0600、单链接的普通文件，拒绝符号链接、硬链接、权限不符和损坏数据；失败不覆盖原文件。空文件同样作为损坏数据拒绝。
4. 原生进程限制与 Rust 入口拒绝共同禁止实验实例访问登录钥匙串。限制查询使用 `sandbox_check`，只查询策略，没有尝试读取任何钥匙串条目或打开钥匙串文件。
5. 不迁移、读取或删除此前写进登录钥匙串的实验条目；旧引用在实验文件中不存在时返回缺失。新 profile 从空文件状态开始，不复制真实凭据。真实实例不安装这些实验限制，原生入口仍在启动时清除外部传入的内部 root 标记。

## 3. 实验与真实输出

### 检查与构建

所有构建都在本 worktree；Flutter 为 3.44.6，没有运行 pub get、commit 或 push，没有增加依赖。

```text
$ ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache \
    ~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub
✓ Built build/macos/Build/Products/Debug/NipaPlay.app

$ ~/development/flutter-3.44.6/bin/flutter analyze --no-pub \
    lib/security/credential_capability.dart lib/security/credential_store.dart \
    lib/security/desktop_credential_vault.dart
Analyzing 3 items...
No issues found! (ran in 2.3s)

$ ~/development/flutter-3.44.6/bin/flutter test --no-pub \
    test/lab_profile_test.dart test/security/credential_store_test.dart \
    test/security/credential_access_experiment_test.dart
00:10 +19: All tests passed!

$ ~/development/flutter-3.44.6/bin/flutter test --no-pub \
    test/security/credential_store_test.dart \
    test/security/credential_access_experiment_test.dart
00:00 +16: All tests passed!

$ swiftc macos/Runner/SandboxMigration.swift \
    macos/RunnerTests/LabFileVaultTests.swift -o /tmp/nipa-next/x11b-vault-tests
$ /tmp/nipa-next/x11b-vault-tests
PASS: reference boundaries, Unicode/empty secrets, update/delete preservation, 0600
PASS: invalid input/permissions, symlinks, hardlinks and corrupt data rejected without data loss
PASS: no staging file remains

$ CARGO_TARGET_DIR="$PWD/build/macos/Build/Intermediates.noindex/Pods.build/Debug/rust_lib_nipaplay.build" \
    cargo test --offline --locked --manifest-path rust/Cargo.toml \
    --target aarch64-apple-darwin --lib vault::tests
running 4 tests
test vault::tests::missing_and_deleted_entries_are_idempotent ... ok
test vault::tests::authorization_status_codes_are_distinct ... ok
test vault::tests::reference_boundaries ... ok
test vault::tests::lab_calls_are_rejected_before_reference_or_keychain_access ... ok
test result: ok. 4 passed; 0 failed; 0 ignored; 0 measured; 123 filtered out; finished in 0.00s
```

Rust 拒绝检查使用空 namespace/key：即使拒绝逻辑失效，也会在引用校验处失败，测试不会访问用户钥匙串。其他保险库检查用 mock。独立 Swift 检查仅使用自己的临时文件目录并清理。

不带 `DEBUG` 编译相同原生源码的探针，设置 profile 和伪造内部 root 标记后：

```text
$ NIPAPLAY_PROFILE=x11b-release-probe NIPAPLAY_LAB_ROOT=/unused \
    /tmp/nipa-next/x11b-release-probe
release profile ignored: active=false, root=nil, marker=nil
release probe profile absent= True
```

### 实际应用写入与读回

先在唯一临时 profile 的 `preferences.json` 预置 Next 开关和一个合成测试 token；直接执行本 worktree 的可执行文件，不按 bundle id 启动。应用启动时现有 `CredentialStore.verifiedWrite` 将它写入文件保险库并读回比对，再把实验偏好改成 `credentialRef`。随后通过本实例的回环端点执行现有 `credentials.status` 和 `credentials.retry`；请求显式禁用代理，没有调用真实实例端点。

以下是补齐空文件数据约束后重建的实验输出。实验结束后仅补回 schema 构造函数的 `const` 来消除 analyzer 提示，并再次构建；保险库、隔离策略和 Action 运行逻辑未再修改。

```text
experiment start=2026-10-11T13:17:28.081507
direct executable=~/Desktop/nipaplay-next-wt/lab-vault/build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay
profile=x11b-131728 PID=16673
credentials.status: {"status": "completed", "result": {"backend": "labFile", "notices": [], "failures": []}}
credentials.retry: {"status": "completed", "result": {"reference": {"namespace": "preferences", "key": "dandanplay_token"}, "available": true}}
startup CredentialStore.verifiedWrite + readback succeeded; file test value matches=True
vault=~/Library/Application Support/NipaPlay/LabProfiles/x11b-131728/credential-vault.json mode=0o600 owner_uid=501; root_mode=0o700
preferences contain credentialRef=True; test plaintext removed from preferences=True
credentials.retry: {"status": "completed", "result": {"reference": {"namespace": "agent", "key": "token"}, "available": false}}
real account reference agent/token resolves only lab file: available=False
sandbox_check PID=16673: login-file-read=1 lab-file-write=0 outside-write=1 SecurityServer-lookup=1 securityd.xpc-lookup=1 (0=allowed, 1=denied)
direct children=<none>; lab vault broker process count=0
```

登录钥匙串中既有 `5:agenttoken`，实验文件中没有该引用；上述请求只经过文件后端，返回缺失，不读取登录钥匙串。`sandbox_check` 从外部检查实际应用 PID 的策略，确认登录钥匙串文件读取和旧式/现代服务查找均被拒绝，同时实验内写入仍允许。

### 钥匙串名称、数量与授权观察

启动前、运行中、按 PID 退出并清理后均只执行：

```sh
security dump-keychain -a "$HOME/Library/Keychains/login.keychain-db"
```

原始输出只在观察脚本内存中解析，保留条目 class 和 account/service/label 等名称字段，排序计算摘要，并直接比较三份完整名称列表。没有使用 `-d`、`-w`、find/read/delete 等命令，没有获取秘密。除 NipaPlay 账号名外，不把其他应用条目名写入报告。

```text
before: login entries=172 names_sha256=56d94e26be0225f4eec45550a8db5604b8918d0ca4f65da9fb6c033e1f734014 nipa_vault_entries=10
running: login entries=172 names_sha256=56d94e26be0225f4eec45550a8db5604b8918d0ca4f65da9fb6c033e1f734014 nipa_vault_entries=10
after cleanup: login entries=172 names_sha256=56d94e26be0225f4eec45550a8db5604b8918d0ca4f65da9fb6c033e1f734014 nipa_vault_entries=10
all login entry names/count unchanged=True
```

原有 NipaPlay 保险库账号名三次完全相同：

```text
11:preferencesdandanplay_remote_api_token
11:preferencesdandanplay_token
15:server_profiles1771498139998
15:server_profiles1776489862978
15:server_profiles1776489944190
15:server_profiles1782631706009
4:meshb4288e91723e6216e06fab532a14c951e43f39bb18f6cd9cda4a4f5400e85a78
4:mesheea59da682350d20669521616b62a82036b71721c44d65e06ea4510ac98bed92
5:agenttoken
8:metadatatmdb
```

从第一次名称检查之前到清理后的检查结束，持续每约 100ms 用 `pgrep -x SecurityAgent` 采样，同时运行：

```sh
/usr/bin/log stream --style compact --level debug \
  --predicate 'process == "securityd" OR process == "SecurityAgent"'
```

```text
SecurityAgent process samples=506; observed PIDs=[]
security stream rows=26603; SecurityAgent rows=0; NipaPlay/profile rows=0
experiment end=2026-10-11T13:18:28.986607
```

最后一项按实验 PID 的完整数字、worktree 应用包路径或本次 profile 名匹配。日志中存在既有钥匙串 ACL 的其他应用路径及签名检查记录，不能把系统日志整体称为“没有钥匙串活动”；实验实例没有对应请求记录，SecurityAgent 没有进程或日志活动。结合文件读回、无 broker 和实际进程的服务查找拒绝，本次全过程未触发钥匙串授权弹窗。

首次实验也成功：`x11b-131424`、PID 5633，三次仍为相同的 172/10 条，504 次 SecurityAgent 采样均无 PID；该实例同样按 PID 退出，目录已删除。

### 清理、意外与验证范围

```text
terminated only experiment PID=16673 exit=-15
removed only ~/Library/Application Support/NipaPlay/LabProfiles/x11b-131728; absent=True
```

没有启动或退出 `/Applications/NipaPlay.app`，没有使用 `open -b` 或按应用标识退出，也没有构建主仓库。观察脚本和真实日志保存在 `/tmp/nipa-next/x11b-experiment.py`、`x11b-experiment.log`、`x11b-app.log`、`x11b-security-stream.log`；首次日志另存 `x11b-first-*`。

- Flutter 构建自动执行 pod install，将锁文件中的 Erika 记录从仓库值 0.1.3 改成已解析依赖的 0.2.1。每次构建后恢复仓库原值，没有手动升级依赖，交付不包含锁文件修改。
- 独立 Release 探针首次因字符串插值中的引号转义写错而编译失败；修正探针后得到上述输出。应用构建没有此问题。
- 实验专用的 Action 描述改成条件表达式后，analyzer 提示 8 项可使用 const；补回两个 schema 的 const 后零问题，回归检查通过并重建。
- 收尾检查补齐了空保险库文件的处理：作为损坏 JSON 返回错误，保留原文件，不执行空值解包。补充原生数据约束检查并重建、复跑真机实验。
- 应用仍输出 X11 已记录的 universal_gamepad/audioplayers MissingPluginException。合成 token 也触发既有续期路径的 `DandanplayLoginRequired`；它不是网站登录凭据。本任务没有验证真实登录、播放或 Mesh 业务功能，没有改变这些插件或客户端。

## 4. 需要主控决定的问题

没有。
