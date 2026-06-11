# SDK Version Notes

Release history and behavior changes for `github.com/modelcontextprotocol/go-sdk`, v1.0.0 through **v1.6.1** (the version this skill is verified against, released 2026-05-22). Use this file to reconcile outdated knowledge of the SDK: if a pattern you remember is listed under "Stale patterns" below, it no longer applies.

## Compatibility

| SDK Version | Latest MCP Spec | All Supported MCP Specs | Go |
|---|---|---|---|
| v1.4.1+ | 2025-11-25 | 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05 | 1.25+ |
| v1.2.0 – v1.4.0 | 2025-11-25 (partial before v1.4.0) | + 2025-06-18, 2025-03-26, 2024-11-05 | 1.24+ |
| v1.0.0 – v1.1.0 | 2025-06-18 | 2025-06-18, 2025-03-26, 2024-11-05 | — |

Note: v1.4.x still *advertised* 2025-06-18 as the default negotiated version; v1.5.0 switched the negotiated `latestProtocolVersion` to 2025-11-25.

The SDK guarantees no breaking API changes within v1 (deprecate-and-add policy). Prefer v1.3.1+ or v1.4.1+ — earlier versions have a known security issue with case-insensitive JSON field matching.

## Stale Patterns (if your SDK knowledge predates v1.5)

- **`mcp_go_client_oauth` build tag** — gone. Client-side OAuth has been stable and compiled unconditionally since v1.5.0 (`auth.OAuthHandler`, `StreamableClientTransport.OAuthHandler`).
- **`jsonrpc.InternalError` etc.** — error code constants are named `jsonrpc.CodeInternalError`, `CodeParseError`, `CodeInvalidRequest`, `CodeMethodNotFound`, `CodeInvalidParams`.
- **Stream resumption by default** — since v1.1.0, a nil `StreamableHTTPOptions.EventStore` disables resumption. Set `EventStore: mcp.NewMemoryEventStore(nil)` to enable it.
- **`StreamableHTTPOptions.CrossOriginProtection`** — deprecated as of v1.6, and cross-origin protection is no longer applied by default; wrap the handler with `http.NewCrossOriginProtection().Handler(h)` instead.
- **Tool input validation errors as JSON-RPC errors** — since v1.5.0 they are returned as tool results (`IsError: true`), visible to the LLM.
- **`SetError` overwriting `Content`** — since v1.6.0, `CallToolResult.SetError` preserves pre-populated `Content`.
- **`auth.PreregisteredClientConfig`** — removed in v1.5.0; use `AuthorizationCodeHandlerConfig.PreregisteredClient` with `oauthex.ClientCredentials`.
- **`ServerOptions.HasTools/HasPrompts/HasResources`** — deprecated; use `ServerOptions.Capabilities`. `ClientCapabilities.Roots` is deprecated in favor of `RootsV2`.

## Release Highlights

### v1.6.1 (2026-05-22)
- Adds `MCPGODEBUG=disablecontenttypecheck=1` to skip `Content-Type: application/json` validation on POSTs (Streamable HTTP and SSE).

### v1.6.0 (2026-05-08)
- `extauth.NewClientCredentialsHandler` — OAuth 2.0 client credentials grant for service-to-service auth.
- Early 2026-06-30 spec work: `application_type` inference in dynamic client registration (SEP-837); JSON-RPC method/name mirrored into HTTP headers for proxies (partial SEP-2243); new `mcp.CodeHeaderMismatch` (-32001) error code.
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
- `StreamableClientTransport.DisableListening`; `ClientOptions.Logger`; exported `CallToolResult.GetError`/`SetError`.

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
| `disablelocalhostprotection=1` | v1.4.0 | Disable DNS rebinding protection (Streamable HTTP; also SSE since v1.6.0) | planned v1.8.0 |
| `enableoriginverification=1` | v1.6.0 | Re-enable default cross-origin protection | planned v1.8.0 |
| `seterroroverwrite=1` | v1.6.0 | Restore pre-v1.6.0 `SetError` content-overwrite behavior | planned v1.8.0 |
| `disablecontenttypecheck=1` | v1.6.1 | Skip `Content-Type: application/json` check on POSTs | planned v1.8.0 |
| `jsonescaping=1` | v1.4.0 | Restore JSON HTML-escaping | removed v1.6.0 |
| `disablecrossoriginprotection=1` | v1.4.1 | Disable cross-origin protection | removed v1.6.0 |

Prefer the long-term API options (`DisableLocalhostProtection`, handler wrapping) over `MCPGODEBUG` flags.
