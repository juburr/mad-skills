# SDK Version Notes

Release history and behavior changes for `github.com/modelcontextprotocol/go-sdk`, v1.0.0 through **v1.8.0** (the version this skill is verified against, released 2026-09-14). Use this file to reconcile outdated knowledge of the SDK: if a pattern you remember is listed under "Stale patterns" below, it no longer applies.

## Compatibility

| SDK Version | Latest MCP Spec | Default Negotiated | All Supported MCP Specs | Go |
|---|---|---|---|---|
| v1.7.0+ | 2026-07-28 | 2026-07-28 | 2026-07-28, 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05 | 1.25+ |
| v1.5.0 – v1.6.1 | 2025-11-25 | 2025-11-25 | 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05 | 1.25+ |
| v1.4.1 | 2025-11-25 | 2025-06-18 | 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05 | 1.25+ |
| v1.4.0 | 2025-11-25 | 2025-06-18 | 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05 | 1.24+ |
| v1.2.0 – v1.3.1 | 2025-11-25 (partial) | 2025-06-18 | 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05 | 1.23+ |
| v1.0.0 – v1.1.0 | 2025-06-18 | 2025-06-18 | 2025-06-18, 2025-03-26, 2024-11-05 | 1.23+ |

The SDK guarantees no breaking API changes within v1 (deprecate-and-add policy); behavior changes ship with temporary `MCPGODEBUG` opt-outs. Prefer v1.3.1+ or v1.4.1+ at minimum — earlier versions have a known security issue with case-insensitive JSON field matching.

## Stale Patterns (if your SDK knowledge predates v1.7)

- **`initialize` is always the first message** — no longer. Clients start with `server/discover` and fall back to `initialize` (capped at 2025-11-25) for older servers.
- **Plain stateful `NewStreamableHTTPHandler` for new servers** — a stateful handler cannot serve 2026-07-28; clients silently fall back to 2025-11-25. Set `StreamableHTTPOptions.Stateless: true`.
- **`ServerSession.Elicit` / `CreateMessage` / `ListRoots` from a tool handler** — these return an error on 2026-07-28 sessions. Return `InputRequests` from the handler (Multi Round-Trip Requests); the SDK shims it for legacy clients.
- **`KeepAlive`, `Ping`, `SetLoggingLevel`, `InitializedHandler`** — removed from the 2026-07-28 protocol; they only operate on legacy sessions.
- **Session IDs and `EventStore` resumption** — absent on 2026-07-28 (stateless HTTP has no session ID; resumability was removed from the spec).
- **`ResourceNotFoundError` code `-32002`** — the code is `-32602` since v1.7.0. `mcp.CodeResourceNotFound` is a deprecated variable.
- **`mcp.CodeHeaderMismatch` is `-32001`** — renumbered to `-32020` in v1.7.0.
- **`ToolAnnotations` omits `false` hints** — `ReadOnlyHint` and `IdempotentHint` are always serialized since v1.7.0.
- **Output schemas must be objects** — since v1.7.0 (SEP-2106) the typed `Out` may be any type with a valid schema, and `StructuredContent` may be any JSON value.
- **Unlimited request bodies** — Streamable HTTP and SSE handlers cap bodies at 4 MiB since v1.7.0 (`MaxRequestBodyBytes`).
- **`go get github.com/modelcontextprotocol/go-sdk`** — get the `mcp` package path instead; the module root has no package.

## Stale Patterns (if your SDK knowledge predates v1.5)

- **`mcp_go_client_oauth` build tag** — gone. Client-side OAuth has been compiled unconditionally since v1.5.0 (`auth.OAuthHandler`, `StreamableClientTransport.OAuthHandler`).
- **`jsonrpc.InternalError` etc.** — error code constants are named `jsonrpc.CodeInternalError`, `CodeParseError`, `CodeInvalidRequest`, `CodeMethodNotFound`, `CodeInvalidParams`.
- **Stream resumption by default** — since v1.1.0, a nil `StreamableHTTPOptions.EventStore` disables resumption. Set `EventStore: mcp.NewMemoryEventStore(nil)` to enable it (legacy stateful sessions only).
- **`StreamableHTTPOptions.CrossOriginProtection`** — deprecated as of v1.6, and cross-origin protection is no longer applied by default; wrap the handler with `http.NewCrossOriginProtection().Handler(h)` instead.
- **Tool input validation errors as JSON-RPC errors** — since v1.5.0 they are returned as tool results (`IsError: true`), visible to the LLM.
- **`SetError` overwriting `Content`** — since v1.6.0, `CallToolResult.SetError` preserves pre-populated `Content`.
- **`auth.PreregisteredClientConfig`** — removed in v1.5.0; use `AuthorizationCodeHandlerConfig.PreregisteredClient` with `oauthex.ClientCredentials`.
- **`ServerOptions.HasTools/HasPrompts/HasResources`** — deprecated; use `ServerOptions.Capabilities`. `ClientCapabilities.Roots` is deprecated in favor of `RootsV2`.

## Release Highlights

### v1.8.0 (2026-09-14)
No new protocol revision; hardening and fixes over v1.7.0.
- Bounded decoding: JSON nesting deeper than 1000 levels rejected; `StdioTransport.MaxLineLength` / `IOTransport.MaxLineLength` (16 MiB default); `MaxEventSize` on `SSEClientTransport` and `StreamableClientTransport` (16 MiB default); `SSEOptions.MaxRequestBodyBytes` / `SSEServerTransport.MaxRequestBodyBytes`; dynamic client registration responses capped at 1 MB.
- `ServerOptions.SupportedProtocolVersions` and `mcp.SupportedProtocolVersions()` — narrow the versions a server offers.
- `ServerOptions.SetCacheable` — per-request `ttlMs`/`cacheScope` policy.
- `ClientSessionOptions.ProtocolVersion` exported — pin the client's starting version.
- `ServerSession.NotifyElicitationComplete` (legacy URL-mode elicitation).
- `AuthorizationCodeHandlerConfig.ScopeFilter`, `AcceptUnadvertisedIss`.
- OAuth discovery SSRF defaults: rejects HTTPS→HTTP redirects, redirects to private or loopback addresses, and private-IP targets (literal or resolved at dial time). A custom `DialContext` or proxy opts out.
- Behavior: stateful handlers answer 2026-07-28 requests with a JSON-RPC `-32022` error (was plain-text 400); cancelling a call no longer blocks on delivering `notifications/cancelled`.
- Removed `MCPGODEBUG` flags: `seterroroverwrite`, `enableoriginverification`, `disablecontenttypecheck`, `disablelocalhostprotection`.
- Many leak, deadlock, and teardown-hang fixes (stateful sessions, `subscriptions/listen`, `Client.Connect`).

### v1.7.0 (2026-07-28)
Full support for protocol 2026-07-28, now the default.
- Stateless protocol (SEP-2575/2567): `server/discover` (served automatically), per-request `_meta` (`MetaKeyProtocolVersion`, `MetaKeyClientInfo`, `MetaKeyClientCapabilities`, `MetaKeyServerInfo`, `MetaKeyLogLevel`, `MetaKeySubscriptionID`), `ServerRequest.ProtocolVersion()/ClientInfo()/ClientCapabilities()`, automatic fallback to `initialize`.
- Streamable HTTP serves 2026-07-28 only when `Stateless: true`; stateless mode no longer reads or sets `Mcp-Session-Id` and rejects GET/DELETE with 405.
- Multi Round-Trip Requests (SEP-2322): `InputRequests`/`RequestState` on `CallToolResult`, `GetPromptResult`, `ReadResourceResult`; `InputResponses`/`RequestState` on their params; `NeedsInput()`; `ClientOptions.MultiRoundTrip`; automatic client retries and a server shim for legacy clients. Legacy server-to-client calls error on new sessions.
- `subscriptions/listen` (`SubscriptionsListenParams`, `NotificationSubscriptions`) replaces the GET stream and `resources/subscribe` on new sessions; existing client/server APIs use it transparently.
- Cacheable results (SEP-2549): `Cacheable`/`CacheableResult` embedded in list results, `ReadResourceResult`, `DiscoverResult`; client-side TTL cache.
- HTTP header standardization (SEP-2243): `Mcp-Method`, `Mcp-Name`, `Mcp-Param-*` via `x-mcp-header`.
- Error codes: `CodeHeaderMismatch` → `-32020`; new `CodeMissingRequiredClientCapabilities` (`-32021`), `CodeUnsupportedProtocolVersion` (`-32022`) with `MissingRequiredClientCapabilityData` / `UnsupportedProtocolVersionData`; resource not found → `-32602`.
- Roots, sampling, and logging APIs marked deprecated (SEP-2577).
- Custom JSON-RPC methods: `AddReceivingCustomMethod`, `AddSendingCustomMethod`, `CallCustomMethod`, `ParamsBase`, `ResultBase`.
- `StreamableHTTPOptions.MaxRequestBodyBytes` (4 MiB default) and `PropagateRequestCancellation`; `KeepAliveFailureThreshold` on client and server options; `Implementation.Description`; `ProtocolVersionSupporter` interface.
- Auth: `AuthorizationResult.Iss` and RFC 9207 issuer validation; `oauthex.ClientCredentials.Issuer` (SEP-2352); `RequestRefreshToken` (SEP-2207); `InitialTokenSource`/`NewTokenSource` for token persistence; `RequireBearerTokenOptions.ClockSkew` and `AllowMissingExpiration`; `oauthex.MatchesResource`.
- Behavior: `ToolAnnotations` hints always serialized; completion requests validated; params-decoding failures reported as `-32602`.

### v1.6.1 (2026-05-22)
- Adds `MCPGODEBUG=disablecontenttypecheck=1` to skip `Content-Type: application/json` validation on POSTs (removed again in v1.8.0).

### v1.6.0 (2026-05-08)
- `extauth.NewClientCredentialsHandler` — OAuth 2.0 client credentials grant for service-to-service auth.
- Early 2026 spec work: `application_type` inference in dynamic client registration (SEP-837); JSON-RPC method/name mirrored into HTTP headers for proxies (partial SEP-2243); `mcp.CodeHeaderMismatch` (then `-32001`, renumbered to `-32020` in v1.7.0).
- Behavior: `CallToolResult.SetError` preserves existing `Content`; cross-origin protection no longer on by default.
- DNS rebinding and cross-origin protections extended to the SSE transport (`SSEOptions.DisableLocalhostProtection`).

### v1.5.0 (2026-04-07)
- Client-side OAuth stabilized — build tag removed; `auth.AuthorizationCodeFetcher` named type; `PreregisteredClient` replaces `PreregisteredClientConfig`.
- New `auth/extauth` package: Enterprise Managed Authorization (SEP-990, RFC 8693 token exchange via `NewEnterpriseHandler`), `PerformOIDCLogin`.
- Negotiated protocol version is now 2025-11-25.
- Tool input validation errors returned as tool results, not JSON-RPC errors; scope included in `WWW-Authenticate`.

### v1.4.1 (2026-03-13) — security patch
- Fixed vulnerability in the case-sensitive JSON decoder dependency.
- Added Content-Type verification and (then-default) cross-origin protection on POSTs. Go requirement raised to 1.25.

### v1.4.0 (2026-02-27)
- Completes the 2025-11-25 spec: Sampling with Tools (`ServerSession.CreateMessageWithTools`, `ClientOptions.CreateMessageWithToolsHandler`).
- DNS rebinding protection enabled by default (`DisableLocalhostProtection` to opt out).
- `Extensions` field on client/server capabilities (SEP-2133, enables MCP Apps).
- JSON HTML-escaping removed when marshaling. `MCPGODEBUG` mechanism introduced. Go requirement raised to 1.24.

### v1.3.1 (2026-02-18) — security patch
- JSON decoding made case-sensitive (struct field/tag matching); previously exploitable.

### v1.3.0 (2026-02-09)
- `mcp.NewSchemaCache()` / `ServerOptions.SchemaCache` — avoids repeated schema reflection; important for per-request server deployments.
- `StreamableClientTransport.DisableStandaloneSSE`; `ClientOptions.Logger`; exported `CallToolResult.GetError`/`SetError`.

### v1.2.0 (2025-12-22)
- Partial 2025-11-25 spec support: icons and metadata (SEP-973), tool name validation (SEP-986), elicitation defaults/URL mode/enum improvements (SEP-1024/1036/1330), SSE polling (SEP-1699).
- `auth.TokenInfo.UserID` added (bind sessions to users to prevent session hijacking); `ServerOptions.Capabilities`/`ClientOptions.Capabilities`; `ClientCapabilities.RootsV2`; OAuth 2.0 Protected Resource Metadata.

### v1.1.0 (2025-10-30)
- Stream resumption made opt-in via `StreamableHTTPOptions.EventStore` (nil disables it).
- `IOTransport`, `ServerOptions.Logger`, `StreamableHTTPOptions.Logger`, `StreamableHTTPOptions.SessionTimeout`.

### v1.0.0 (2025-09-30)
- First stable release; full 2025-06-18 spec except client-side OAuth.

## MCPGODEBUG Flags

Comma-separated `name=value` pairs in the `MCPGODEBUG` environment variable. Temporary escape hatches for behavior changes, typically removed after two minor releases.

| Flag | Added | Effect | Removal |
|---|---|---|---|
| `customresnotfounderrcode=1` | v1.7.0 | `ResourceNotFoundError` uses `-32002` instead of `-32602` | planned v1.9.0 |
| `hintomitempty=1` | v1.7.0 | Omit `false` `ReadOnlyHint`/`IdempotentHint` | planned v1.9.0 |
| `allowsessionsinstateless=1` | v1.7.0 | Stateless HTTP honors `Mcp-Session-Id`, `GetSessionID`, and DELETE | planned v1.9.0 |
| `nomethodnotfoundcodeinerror=1` | v1.7.0 | Omit `-32601` from stdio method-not-found responses | planned v1.9.0 |
| `noprotocolerrorbody=1` | v1.7.0 | HTTP client ignores JSON-RPC bodies on non-2xx and fails the connection | planned v1.9.0 |
| `nowrapinvalidparams=1` | v1.7.0 | Params-decoding failures use code `0` instead of `-32602` | planned v1.9.0 |
| `disablecompleteparamsvalidation=1` | v1.7.0 | Skip `ref`/`argument.name` validation on `completion/complete` | planned v1.9.0 |
| `plaintextstatefulrejection=1` | v1.8.0 | Stateful handler rejects 2026-07-28 requests with plain-text 400 | planned v1.9.0 |
| `blockingcancelnotify=1` | v1.8.0 | Cancelled calls wait (up to 5s) for `notifications/cancelled` delivery | planned v1.9.0 |
| `disablelocalhostprotection=1` | v1.4.0 | Disable DNS rebinding protection | removed v1.8.0 |
| `enableoriginverification=1` | v1.6.0 | Re-enable default cross-origin protection | removed v1.8.0 |
| `seterroroverwrite=1` | v1.6.0 | Restore pre-v1.6.0 `SetError` content-overwrite behavior | removed v1.8.0 |
| `disablecontenttypecheck=1` | v1.6.1 | Skip `Content-Type: application/json` check on POSTs | removed v1.8.0 |
| `jsonescaping=1` | v1.4.0 | Restore JSON HTML-escaping | removed v1.6.0 |
| `disablecrossoriginprotection=1` | v1.4.1 | Disable cross-origin protection | removed v1.6.0 |

Prefer the long-term API options (`DisableLocalhostProtection`, handler wrapping, `MaxRequestBodyBytes`) over `MCPGODEBUG` flags.
