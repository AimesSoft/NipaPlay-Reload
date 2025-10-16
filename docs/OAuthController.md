# 弹弹play开放平台 OAuth 2.0 API 文档

本文档介绍如何通过 OAuth 2.0 授权码模式接入弹弹play开放平台服务。

## 基础信息

**Base URL**: `https://api.dandanplay.net`

**授权流程**: OAuth 2.0 Authorization Code Flow（支持 PKCE）

**Token 类型**: Bearer Token

---

## 1. 授权流程概览

标准的 OAuth 2.0 授权码流程分为以下步骤：

1. 引导用户访问登录页面（`GET /api/v2/oauth/login`）
2. 用户完成登录和授权
3. 服务端重定向回你的应用，携带授权码 `code`
4. 使用授权码交换访问令牌（`POST /api/v2/oauth/token`）
5. 使用访问令牌调用受保护的 API
6. 令牌过期后使用刷新令牌获取新令牌（`POST /api/v2/oauth/refresh`）

---

## 2. 发起授权请求

### 2.1 引导用户登录

将用户浏览器重定向到以下 URL：

```
GET /api/v2/oauth/login
```

**Query 参数**:

```
https://api.dandanplay.net/api/v2/oauth/login?
  client_id={your_client_id}&
  redirect_uri={your_redirect_uri}&
  response_type=code&
  scope={requested_scopes}&
  state={random_state}&
  code_challenge={challenge}&           // PKCE (可选)
  code_challenge_method=S256             // PKCE (可选)
```

| 参数 | 必填 | 说明 |
|------|------|------|
| `client_id` | 是 | 你的应用 ID |
| `redirect_uri` | 是 | 授权完成后的回调地址，必须与注册时一致 |
| `response_type` | 是 | 固定值 `code` |
| `scope` | 是 | 请求的权限范围，多个用空格分隔 |
| `state` | 推荐 | 随机字符串，用于防止 CSRF 攻击 |
| `code_challenge` | 可选 | PKCE 质询码（推荐公有客户端使用） |
| `code_challenge_method` | 可选 | 质询方法，固定值 `S256` |

**PKCE 说明**（推荐移动端和前端应用使用）：

生成随机字符串 `code_verifier`（43-128 字符），然后计算 `code_challenge = BASE64URL(SHA256(code_verifier))`。

### 2.2 用户授权

用户在登录页面输入用户名和密码，系统会：

- 验证用户身份
- 显示授权确认页面（如需要）
- 用户同意后重定向回你的应用

**注意**：登录失败超过 5 次（10分钟内）将被锁定 15 分钟。

### 2.3 接收授权码

授权成功后，用户浏览器会重定向到 `redirect_uri`，携带授权码：

```
https://your-app.com/callback?code={authorization_code}&state={state}
```

**参数说明**:

- `code`: 授权码，有效期较短（通常 10 分钟），仅可使用一次
- `state`: 你发起请求时传入的 state 值，请验证是否一致

---

## 3. 交换访问令牌

使用授权码换取访问令牌和刷新令牌。

```
POST /api/v2/oauth/token
```

**Content-Type**: `application/x-www-form-urlencoded` 或 `application/json`

**请求参数** (form-urlencoded):

```
client_id={your_client_id}
client_secret={your_client_secret}
code={authorization_code}
redirect_uri={your_redirect_uri}
grant_type=authorization_code
code_verifier={verifier}              // 使用 PKCE 时必填
```

**请求示例** (JSON):

```json
{
  "client_id": "your_client_id",
  "client_secret": "your_client_secret",    // 公有客户端可不提供，需配合 PKCE
  "code": "authorization_code_from_callback",
  "redirect_uri": "https://your-app.com/callback",
  "grant_type": "authorization_code",
  "code_verifier": "random_verifier_string"  // 使用 PKCE 时必填
}
```

**成功响应** (200):

```json
{
  "access_token": "eyJhbGc...",           // 访问令牌，用于调用 API
  "token_type": "Bearer",                 // 令牌类型
  "expires_in": 3600,                     // 访问令牌过期时间（秒）
  "refresh_token": "def50200...",         // 刷新令牌，用于获取新的访问令牌
  "scope": "basic profile"                // 实际授予的权限范围
}
```

**错误响应** (400/401):

```json
{
  "error": "invalid_grant",               // 错误类型
  "error_description": "Authorization code is invalid or expired"
}
```

常见错误码：

- `invalid_client`: client_id 或 client_secret 错误
- `invalid_grant`: 授权码无效、已使用或过期
- `invalid_request`: 缺少必要参数
- `unauthorized_client`: redirect_uri 不匹配

---

## 4. 使用访问令牌

获取访问令牌后，在请求头中携带令牌调用受保护的 API：

```
GET /api/v2/user/profile
Authorization: Bearer eyJhbGc...
```

**访问令牌过期时间**通常为 1 小时，过期后需要使用刷新令牌获取新的访问令牌。

---

## 5. 刷新访问令牌

当访问令牌过期时，使用刷新令牌获取新的令牌对。

```
POST /api/v2/oauth/refresh
```

**Content-Type**: `application/x-www-form-urlencoded` 或 `application/json`

**请求参数** (form-urlencoded):

```
client_id={your_client_id}
client_secret={your_client_secret}
refresh_token={your_refresh_token}
grant_type=refresh_token
```

**请求示例** (JSON):

```json
{
  "client_id": "your_client_id",
  "client_secret": "your_client_secret",
  "refresh_token": "def50200...",
  "grant_type": "refresh_token"
}
```

**成功响应** (200):

```json
{
  "access_token": "eyJhbGc...",           // 新的访问令牌
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "def50200...",         // 新的刷新令牌（刷新令牌轮换）
  "scope": "basic profile"
}
```

**重要说明**：

- 刷新令牌采用**轮换机制**，每次刷新后旧的 refresh_token 将失效
- 请妥善保存新的 refresh_token
- 刷新令牌通常有效期较长（30天或更久）

**错误响应** (400/401):

```json
{
  "error": "invalid_grant",
  "error_description": "Refresh token is invalid or expired"
}
```

---

## 6. 获取 WebToken（特殊场景）

WebToken 用于某些需要在浏览器环境中执行的业务操作。

```
GET /api/v2/oauth/webToken?business={business_type}
```

**请求头**:

```
Authorization: Bearer {your_access_token}
```

**Query 参数**:

| 参数 | 必填 | 说明 |
|------|------|------|
| `business` | 是 | 业务标识，如 `deleteAccount` |

**成功响应** (200):

```json
{
  "webToken": "temporary_web_token",      // 临时网页令牌
  "business": "deleteAccount",            // 业务标识
  "expiresAt": "2025-10-15T12:00:00Z"    // 过期时间（UTC）
}
```

**错误响应**:

```json
{
  "errorCode": 401                        // 错误码
}
```

**使用场景**：

生成 WebToken 后，可以将用户重定向到特定业务页面：

```
https://api.dandanplay.net/api/v2/oauth/deleteAccount?webToken={web_token}
```

---

## 7. 最佳实践

### 7.1 安全建议

1. **使用 HTTPS**：所有请求必须通过 HTTPS
2. **验证 state 参数**：防止 CSRF 攻击
3. **使用 PKCE**：公有客户端（前端/移动端）强烈推荐使用 PKCE
4. **安全存储令牌**：
   - 移动端：使用 Keychain/Keystore
   - 前端：使用 HttpOnly Cookie 或 SessionStorage（不推荐 LocalStorage）
   - 后端：使用环境变量或密钥管理服务
5. **不要在 URL 中传递令牌**：仅在请求头中传递 access_token
6. **及时刷新令牌**：在访问令牌过期前主动刷新

### 7.2 错误处理

- `401 Unauthorized`：令牌无效或过期，尝试刷新令牌
- `403 Forbidden`：权限不足，检查 scope
- `429 Too Many Requests`：请求频率过高，实施指数退避

### 7.3 刷新令牌策略

推荐在访问令牌过期前 5 分钟主动刷新：

```javascript
// 伪代码
if (token.expiresAt - now() < 300) {  // 5分钟
  await refreshToken();
}
```

### 7.4 PKCE 实现示例（JavaScript）

```javascript
// 生成 code_verifier
function generateCodeVerifier() {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return base64UrlEncode(array);
}

// 生成 code_challenge
async function generateCodeChallenge(verifier) {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return base64UrlEncode(new Uint8Array(hash));
}

function base64UrlEncode(buffer) {
  return btoa(String.fromCharCode(...buffer))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

// 使用
const verifier = generateCodeVerifier();
const challenge = await generateCodeChallenge(verifier);
// 保存 verifier，在 /token 请求时使用
// 在授权 URL 中使用 challenge
```

