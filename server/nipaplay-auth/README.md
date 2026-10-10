# nipaplay-auth

NipaPlay 服务端二进制共享的认证与上游辅助逻辑。抽出来是为了让
`nipaplay-dandanplay-gateway` 与 `nipaplay-mesh-coordinator` 使用同一份实现，避免缓存与
签名逻辑分叉。

提供：

- `bearer_token` / `token_identity` / `forwarded_ip` / `client_ip`：请求身份提取；
- `app_signature`：上游请求签名；
- `RateLimiter`：固定窗口限流（`check` 为每分钟，`check_window` 可指定窗口）；
- `DandanplayUpstream`：`validate_token`（只读 playhistory 校验，带缓存）与
  `resolve_account`（取稳定数字 `userId`）；
- `load_app_secret` / `decode_legacy_secret`：应用密钥加载与旧接口解密；
- `env_value` / `env_bool` / `env_number` / `unix_timestamp`。

```bash
cargo test --manifest-path server/nipaplay-auth/Cargo.toml
```
