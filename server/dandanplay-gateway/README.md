# NipaPlay Dandanplay Gateway

Small Rust reverse proxy used by official NipaPlay builds. It keeps the
Dandanplay AppSecret on the server, signs upstream requests, and preserves the
existing `/api/v2/*` response format expected by the Flutter client.

The gateway requires a valid Dandanplay bearer token for every upstream API,
including comments, search, trending, metadata, and unknown compatibility routes.
Only `POST /api/v2/login` and `POST /api/v2/register` accept anonymous requests
(with the usual IP/global limits). Token renewal requires an existing bearer
token and is validated by the upstream renewal endpoint. The two browser account
management pages accept their upstream-validated short-lived `webToken`; this
credential cannot be used for other APIs. `/healthz` makes no upstream request.
Before accepting a previously unseen token, it checks the token with the
read-only play-history endpoint and caches the result (10 minutes for valid
tokens, 30 seconds for invalid tokens). Merely sending a fake `Bearer` header
does not unlock any API. Authenticated responses are marked private/no-store.
Known client routes are explicitly classified. Unknown `/api/v2/*` routes are
logged and forwarded while `ALLOW_UNKNOWN_API_V2=true`, which is the initial
compatibility mode used to discover missed client features without breaking
production.

Run locally:

```bash
DANDANPLAY_APP_SECRET=... cargo run --manifest-path server/dandanplay-gateway/Cargo.toml
```

Health check:

```bash
curl http://127.0.0.1:18081/healthz
```

Production templates are in `deploy/`. After key rotation, set the new key as
`DANDANPLAY_APP_SECRET` in `/etc/nipaplay-dandanplay-gateway.env` and remove the
legacy secret URL setting.

## Release boundary

- Publish the gateway-aware client before retiring compatibility with old clients.
- Rotate the old application secret as a separate, coordinated release operation;
  anyone who already has that secret can still bypass this gateway until rotation.
- Keep the new secret only in server configuration, never in the legacy public
  secret endpoint or the app. Coordinate the website's daily-recommendation
  generator, which currently also signs upstream requests, before rotation.
- The configured account limit is per bearer token, not per upstream user ID.
  IP and global limits apply across tokens; these are bounded abuse controls,
  not a guarantee against a distributed attack or an upstream daily quota.
- Cached data, independent static images, local danmaku, and third-party providers
  do not consume this application's upstream key and stay available anonymously.
