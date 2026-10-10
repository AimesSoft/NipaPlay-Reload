# nipaplay-auth

NipaPlay 服务端二进制共享的认证与上游辅助逻辑。抽出来是为了让
`nipaplay-dandanplay-gateway` 与 `nipaplay-mesh-coordinator` 使用同一份实现，避免缓存与
签名逻辑分叉。

提供：

- `bearer_token` / `token_identity` / `forwarded_ip` / `client_ip`：请求身份提取；
- `app_signature`：上游请求签名；
- `RateLimiter`：固定窗口限流（`check` 为每分钟，`check_window` 可指定窗口）；
- `DandanplayUpstream`：`validate_token`（只读 playhistory 校验，带缓存）与
  `resolve_account`（只读校验通过后，从 JWT 的配置 JSON Pointer 提取稳定用户 ID）；
  `via_gateway` / `via_gateway_with_client` 不持有 AppSecret，携带 Bearer 调用网关，保留路径前缀；
- `load_app_secret` / `decode_legacy_secret`：应用密钥加载与旧接口解密；
- `env_value` / `env_bool` / `env_number` / `unix_timestamp`。

```bash
cargo test --manifest-path server/nipaplay-auth/Cargo.toml
```

直连客户端签名只包含 URI 路径，不包含查询串，网关继续使用原直连构造方式。
协调服务使用网关构造方式，不发送 `x-appid` / `x-timestamp` / `x-signature`。
有效验证缓存 600 秒，无效缓存 30 秒；网络、HTTP 5xx
和 JSON 解析失败不缓存为无效令牌。`with_client` 允许网关复用原连接池及 HTTP 策略，
测试可注入禁用代理的回环客户端。`token_identity` 保留网关原有的 16 位十六进制摘要；
协调服务使用完整 SHA-256 作为内部认证和限流键。

`client_ip` 本身不验证代理是否可信，调用者必须确定信任边界。网关保留原有代理规则；
协调服务仅对回环代理启用转发头。自定义限流窗口的桶清理不会提前丢弃仍有效的小时窗口。
