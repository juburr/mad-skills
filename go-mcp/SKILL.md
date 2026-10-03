---
name: go-mcp
description: Guides development of MCP servers and clients in Go using the official
  SDK (github.com/modelcontextprotocol/go-sdk). Use when building MCP servers, registering
  tools/resources/prompts, choosing transports, adding authentication, adopting the
  stateless 2026-07-28 protocol (multi round-trip requests, stateless HTTP), or integrating
  MCP endpoints into existing Go services.
---

# MCP Go

> **Verified against SDK v1.8.0** (released 2026-09-14). Supports MCP spec versions 2026-07-28 (default), 2025-11-25, 2025-06-18, 2025-03-26, and 2024-11-05. Requires Go 1.25+. If your knowledge of this SDK predates v1.7, read `references/version-notes.md` first — the default protocol is now stateless, and several APIs and defaults changed.

The official Go SDK for the Model Context Protocol (`github.com/modelcontextprotocol/go-sdk/mcp`). Do **not** use the third-party `github.com/mark3labs/mcp-go` package. If migrating from `mark3labs/mcp-go`, read `references/migration-from-mark3labs.md`. The two libraries interoperate on the wire, so you can migrate incrementally — with one exception: a default mark3labs client fails against an official server behind a *stateful* HTTP handler; serve with `Stateless: true` (see below) to avoid it.

```bash
go get github.com/modelcontextprotocol/go-sdk/mcp@v1.8.0
```

Get the `mcp` package path, not the bare module path: the module root contains no package, so `go get github.com/modelcontextprotocol/go-sdk` records an `// indirect` requirement without the `go.sum` entries the build needs. Pin an explicit version rather than `@latest`, especially for air-gapped module mirrors. Newer versions are fine — the SDK guarantees no breaking API changes within v1.

Most MCP protocol types are in the `mcp` package. Auth helpers are in `auth`, `auth/extauth`, and `oauthex`. Custom transport authors will also use `jsonrpc`.

```go
import (
    "github.com/modelcontextprotocol/go-sdk/mcp"
    "github.com/modelcontextprotocol/go-sdk/auth"
)
```

## Protocol 2026-07-28 in Brief

`Client.Connect` negotiates the version automatically: it probes `server/discover` and falls back to the legacy `initialize` handshake (capped at 2025-11-25) when the server does not offer 2026-07-28. Handler code mostly stays the same. These are the differences that matter:

| Concern | 2026-07-28 session | 2025-11-25 and older |
|---|---|---|
| Streamable HTTP | Served only by a handler with `Stateless: true` | Stateful or stateless handler |
| Asking the client for input | Return `InputRequests` from the handler (see [below](#asking-the-client-for-input)) | Same code works; the SDK shims it |
| `ServerSession.Elicit` / `CreateMessage` / `ListRoots` | Return an error | Work |
| `Ping`, `KeepAlive`, `SetLoggingLevel`, `InitializedHandler` | Removed from the protocol; do not rely on them | Work |
| Session ID | None over stateless HTTP (`ServerSession.ID()` is `""`) | Assigned by stateful HTTP |
| Client info / capabilities | Sent on every request: `req.ClientInfo()`, `req.ClientCapabilities()`, `req.ProtocolVersion()` | Same accessors (read from the handshake) |
| Stream resumption (`EventStore`) | Removed; a broken stream loses the request | Opt-in |

Roots, sampling, and logging are **deprecated** as of 2026-07-28 (functional for at least twelve more months). In new servers, take paths as tool arguments, call LLM provider APIs directly, and log to stderr or OpenTelemetry. Read `references/protocol-2026-07-28.md` for discovery, subscriptions, caching, HTTP header mirroring, and the compatibility matrix.

## Creating a Server

```go
server := mcp.NewServer(
    &mcp.Implementation{Name: "my-server", Version: "v1.0.0"},
    &mcp.ServerOptions{},
)
```

### Registering Tools

Prefer the generic form. Go struct tags drive JSON schema generation automatically.

```go
type SearchInput struct {
    Query string `json:"query" jsonschema:"the search query"`
    Limit int    `json:"limit" jsonschema:"max results to return"`
}

func search(ctx context.Context, req *mcp.CallToolRequest, input SearchInput) (*mcp.CallToolResult, any, error) {
    results := doSearch(input.Query, input.Limit)
    return &mcp.CallToolResult{
        Content: []mcp.Content{&mcp.TextContent{Text: results}},
    }, nil, nil
}

mcp.AddTool(server, &mcp.Tool{
    Name:        "search",
    Description: "Search the knowledge base.",
}, search)
```

The output type may be any Go type with a valid JSON Schema (struct, map, slice, or primitive) — not only objects.

Non-generic form (manual argument parsing). `InputSchema` is **required** here — `server.AddTool` panics if it is nil. For a tool with no input, use `{"type": "object"}`:

```go
server.AddTool(&mcp.Tool{
    Name:        "ping",
    Description: "Health check.",
    InputSchema: map[string]any{"type": "object"},
}, func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    return &mcp.CallToolResult{
        Content: []mcp.Content{&mcp.TextContent{Text: "pong"}},
    }, nil
})
```

### Registering Resources

```go
server.AddResource(&mcp.Resource{
    URI:      "config://app/settings",
    Name:     "App Settings",
    MIMEType: "application/json",
}, func(ctx context.Context, req *mcp.ReadResourceRequest) (*mcp.ReadResourceResult, error) {
    data := loadSettings()
    return &mcp.ReadResourceResult{
        Contents: []*mcp.ResourceContents{{URI: req.Params.URI, Text: data}},
    }, nil
})
```

Dynamic URIs use resource templates:

```go
server.AddResourceTemplate(&mcp.ResourceTemplate{
    URITemplate: "file:///docs/{path}",
    Name:        "Documentation files",
}, handler)
```

### Registering Prompts

```go
server.AddPrompt(&mcp.Prompt{
    Name: "summarize",
    Arguments: []*mcp.PromptArgument{
        {Name: "text", Description: "text to summarize", Required: true},
    },
}, func(ctx context.Context, req *mcp.GetPromptRequest) (*mcp.GetPromptResult, error) {
    return &mcp.GetPromptResult{
        Description: "Summarize the given text",
        Messages: []*mcp.PromptMessage{{
            Role:    "user",
            Content: &mcp.TextContent{Text: "Summarize: " + req.Params.Arguments["text"]},
        }},
    }, nil
})
```

### Removing Features at Runtime

```go
server.RemoveTools("old-tool")
server.RemoveResources("config://app/deprecated")
server.RemovePrompts("old-prompt")
server.RemoveResourceTemplates("file:///old/{path}")
```

## Asking the Client for Input

Use **Multi Round-Trip Requests** (MRTR) to ask for user confirmation (elicitation), an LLM completion (sampling), or the client's roots. Return a result with `InputRequests` set and `Content` empty; the client's built-in middleware fulfils each request with its configured handler and retries the same call with `InputResponses`. The handler therefore runs once per round:

```go
import "github.com/google/jsonschema-go/jsonschema"

func deleteRepo(ctx context.Context, req *mcp.CallToolRequest, in DeleteInput) (*mcp.CallToolResult, any, error) {
    answer, answered := req.Params.InputResponses["confirm"].(*mcp.ElicitResult)
    if !answered {
        caps := req.ClientCapabilities() // URL-only clients cannot render forms
        if caps == nil || caps.Elicitation == nil || (caps.Elicitation.Form == nil && caps.Elicitation.URL != nil) {
            return nil, nil, fmt.Errorf("client cannot confirm deletion; refusing")
        }
        return &mcp.CallToolResult{
            InputRequests: mcp.InputRequestMap{
                "confirm": &mcp.ElicitParams{
                    Message: "Delete " + in.Repo + "?",
                    RequestedSchema: &jsonschema.Schema{
                        Type:       "object",
                        Properties: map[string]*jsonschema.Schema{"confirm": {Type: "boolean"}},
                    },
                },
            },
        }, nil, nil
    }
    if answer.Action != "accept" || answer.Content["confirm"] != true {
        return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: "Cancelled."}}}, nil, nil
    }
    // ... delete ...
}
```

| Input request value | Retry carries |
|---|---|
| `*mcp.ElicitParams` | `*mcp.ElicitResult` |
| `*mcp.CreateMessageParams` or `*mcp.CreateMessageWithToolsParams` | `*mcp.CreateMessageWithToolsResult` (always this type) |
| `*mcp.ListRootsParams` | `*mcp.ListRootsResult` |

- MRTR works on `tools/call`, `prompts/get`, and `resources/read`; `GetPromptResult` and `ReadResourceResult` carry the same `InputRequests`/`RequestState` fields.
- While requesting input, leave every content field empty — `Content`, `StructuredContent`, prompt `Messages`, resource `Contents` — or the SDK rejects it as a server bug (`-32603`). (`AddTool` discards a typed handler's output on that round.)
- Only request what the client declared (check `req.ClientCapabilities()`). Older clients send `elicitation: {}` (nil `Form` and `URL`) to mean form support.
- The retry is a new, independent request; over stateless HTTP another instance may serve it. Carry progress in `RequestState`, not in memory, and treat it as attacker-controlled: integrity-protect it (HMAC or AEAD) and bind it to the caller and a short expiry.
- Legacy (≤ 2025-11-25) clients still work: the SDK fulfils the requests itself with server-to-client calls and re-invokes the handler once, so collect all input in one round for them. That needs a bidirectional session (stdio, in-memory, stateful HTTP) — it fails for legacy clients over stateless HTTP.

Do **not** call `req.Session.Elicit` / `CreateMessage` / `ListRoots` in new code: they return an error on 2026-07-28 sessions. See `references/protocol-2026-07-28.md` for manual retry handling, load shedding, and a `RequestState` signing example.

## Transports

| Transport | Server Side | Client Side | Use When |
|---|---|---|---|
| **Stdio** | `mcp.StdioTransport{}` | `mcp.CommandTransport{Command: exec.Command("server")}` | Local subprocess, IDE integrations |
| **Streamable HTTP** | `mcp.NewStreamableHTTPHandler(getServer, opts)` | `mcp.StreamableClientTransport{Endpoint: url}` | Remote servers, production deployments |
| **SSE** (deprecated) | `mcp.NewSSEHandler(getServer, opts)` | `mcp.SSEClientTransport{Endpoint: url}` | Legacy clients only; never negotiates 2026-07-28 |
| **In-Memory** | `mcp.NewInMemoryTransports()` | Same pair | Testing |

### Stdio Server

```go
if err := server.Run(ctx, &mcp.StdioTransport{}); err != nil {
    log.Fatal(err)
}
```

`Run` blocks until the client disconnects. Use for CLI tools and IDE integrations. Stdio supports every protocol version.

### Streamable HTTP Server

```go
handler := mcp.NewStreamableHTTPHandler(
    func(req *http.Request) *mcp.Server { return server },
    &mcp.StreamableHTTPOptions{
        Stateless:                    true, // required to serve 2026-07-28
        PropagateRequestCancellation: true, // cancel handler ctx when the client disconnects
        Logger:                       slog.Default(),
    },
)
http.Handle("/mcp", handler)
log.Fatal(http.ListenAndServe(":8080", nil))
```

Choose the mode deliberately:

| Mode | Serves | Behavior |
|---|---|---|
| `Stateless: true` (recommended for new servers) | 2026-07-28 and legacy clients | No `Mcp-Session-Id`; GET/DELETE return 405; a fresh `ServerSession` per request, so any replica can serve any request. Legacy clients get no server-to-client requests or list-changed notifications. |
| Stateful (default) | 2025-11-25 and older only; newer clients fall back automatically | Session IDs, `SessionTimeout`, optional `EventStore` resumption, server-to-client requests for legacy clients. Needs sticky routing across replicas. |

The `getServer` callback receives the HTTP request, enabling per-request server instances (e.g., different tools per tenant). When creating a new `*mcp.Server` per request, share a schema cache across instances to avoid re-deriving tool schemas via reflection on every request:

```go
cache := mcp.NewSchemaCache() // create once, share across all servers
handler := mcp.NewStreamableHTTPHandler(func(req *http.Request) *mcp.Server {
    return mcp.NewServer(impl, &mcp.ServerOptions{SchemaCache: cache})
}, &mcp.StreamableHTTPOptions{Stateless: true})
```

### HTTP Security Defaults

- **DNS rebinding protection is on by default**: requests arriving via localhost with a non-localhost `Host` header are rejected with 403. Opt out only with `StreamableHTTPOptions.DisableLocalhostProtection` (also on `SSEOptions`); the `MCPGODEBUG` escape hatch was removed in v1.8.0.
- **Cross-origin protection is off by default.** The spec requires servers to validate `Origin`; wrap any browser-reachable handler: `http.NewCrossOriginProtection().Handler(mcpHandler)`. Do not use the deprecated `StreamableHTTPOptions.CrossOriginProtection` field.
- **POST requests must have `Content-Type: application/json`**; this can no longer be disabled.
- **Request bodies are capped at 4 MiB** (`mcp.DefaultMaxRequestBodyBytes`; larger requests get 413). Raise it with `MaxRequestBodyBytes` on `StreamableHTTPOptions` or `SSEOptions`; a negative value removes the cap — never do that on untrusted networks.
- **Decoders are bounded**: JSON nesting deeper than 1000 levels is rejected, stdio/IO frames are capped by `MaxLineLength` (16 MiB default), and client SSE events by `MaxEventSize` (16 MiB default).

### Adding MCP to an Existing HTTP Service

Mount the handler on a subpath alongside existing routes:

```go
mux := http.NewServeMux()
mux.Handle("/api/", apiHandler)                   // existing REST API
mux.Handle("/mcp", mcpHandler)                    // MCP endpoint
mux.Handle("/.well-known/oauth-protected-resource", authMetadataHandler)
log.Fatal(http.ListenAndServe(":8080", mux))
```

This avoids deploying a separate service. Use `getServer` to inject per-request context (auth, tenant ID) from HTTP headers into tool handlers.

## Creating a Client

```go
client := mcp.NewClient(
    &mcp.Implementation{Name: "my-client", Version: "v1.0.0"},
    nil,
)

session, err := client.Connect(ctx, &mcp.StreamableClientTransport{
    Endpoint: "http://localhost:8080/mcp",
}, nil)
if err != nil {
    log.Fatal(err)
}
defer session.Close()

log.Println("negotiated", session.InitializeResult().ProtocolVersion)
```

To request an older protocol (e.g., to test legacy behavior), pass `&mcp.ClientSessionOptions{ProtocolVersion: "2025-11-25"}` to `Connect`. The server may still negotiate a different supported version, so assert `session.InitializeResult().ProtocolVersion` when a test needs an exact revision.

### Calling Tools

```go
result, err := session.CallTool(ctx, &mcp.CallToolParams{
    Name:      "search",
    Arguments: map[string]any{"query": "MCP protocol", "limit": 10},
})
if err != nil {
    log.Fatal("protocol error:", err)
}
if result.IsError {
    log.Fatal("tool reported an error")
}
for _, c := range result.Content {
    if tc, ok := c.(*mcp.TextContent); ok {
        fmt.Println(tc.Text)
    }
}
```

Set `ElicitationHandler` (and, for legacy features, `CreateMessageHandler`) in `ClientOptions` so the client can answer input requests; MRTR retries are automatic.

### Iterating Over Available Features

Auto-paginating iterators:

```go
for tool, err := range session.Tools(ctx, nil) {
    if err != nil { log.Fatal(err) }
    fmt.Println(tool.Name, "-", tool.Description)
}
for resource, err := range session.Resources(ctx, nil) { /* ... */ }
for prompt, err := range session.Prompts(ctx, nil) { /* ... */ }
```

On 2026-07-28 sessions the client caches list and `resources/read` results for the server-provided `ttlMs`; list-changed and resource-updated notifications invalidate the cache. The cache belongs to the session, not the caller, so never share one session across users.

## Error Handling

### Tool-Level Errors (Application Errors)

Return an error result that the LLM can reason about:

```go
return &mcp.CallToolResult{
    IsError: true,
    Content: []mcp.Content{
        &mcp.TextContent{Text: "User not found with ID: " + input.UserID},
    },
}, nil, nil
```

### Go Errors from Typed Handlers

If a typed tool handler returns a regular Go error, the SDK wraps it into a tool error result (`IsError: true`). Input-schema validation failures are reported the same way. Do not leak secrets in error strings — the LLM will see them.

```go
// This becomes a tool error visible to the LLM:
return nil, nil, fmt.Errorf("user not found: %s", input.UserID)
```

For true protocol-level errors (that should not reach the LLM), return a `*jsonrpc.Error`:

```go
import "github.com/modelcontextprotocol/go-sdk/jsonrpc"

return nil, nil, &jsonrpc.Error{Code: jsonrpc.CodeInternalError, Message: "internal failure"}
```

### Resource Not Found

```go
return nil, mcp.ResourceNotFoundError(uri)
```

The wire code is `-32602` (Invalid Params) since v1.7.0; it was `-32002` before. Update any client that matches on `-32002`.

## Middleware

Middleware wraps a `MethodHandler`. Both `Server` and `Client` support `AddReceivingMiddleware` and `AddSendingMiddleware`.

```go
type MethodHandler func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error)
type Middleware func(MethodHandler) MethodHandler
```

Receiving middleware wraps incoming requests — use it for authentication, logging, and metrics:

```go
server.AddReceivingMiddleware(func(next mcp.MethodHandler) mcp.MethodHandler {
    return func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error) {
        slog.Info("received", "method", method)
        return next(ctx, method, req)
    }
})
```

Sending middleware wraps requests and notifications this side *sends* (e.g., list-changed notifications, legacy server-to-client calls) — not responses to incoming requests. Use it for tracing and outbound metrics.

- Ordering: `AddReceivingMiddleware(m1, m2, m3)` executes as `m1(m2(m3(handler)))` — m1 runs first.
- On 2026-07-28 sessions, server middleware also sees `server/discover` and `subscriptions/listen`, and sees each MRTR round as a separate `tools/call`.

## Authentication

The SDK provides OAuth bearer token middleware via the `auth` package.

```go
import "github.com/modelcontextprotocol/go-sdk/auth"

verifier := func(ctx context.Context, token string, req *http.Request) (*auth.TokenInfo, error) {
    claims, err := validateJWT(token)
    if err != nil {
        return nil, auth.ErrInvalidToken
    }
    return &auth.TokenInfo{
        UserID:     claims.Subject, // binds stateful sessions to this user
        Scopes:     claims.Scopes,
        Expiration: claims.ExpiresAt, // required unless AllowMissingExpiration is set
        Extra:      map[string]any{"tenant_id": claims.TenantID},
    }, nil
}

middleware := auth.RequireBearerToken(verifier, &auth.RequireBearerTokenOptions{
    ResourceMetadataURL: "https://api.example.com/.well-known/oauth-protected-resource",
    Scopes:              []string{"mcp:read"},
    ClockSkew:           30 * time.Second, // tolerate IdP clock drift
})

http.Handle("/mcp", middleware(mcpHandler))
```

Read token info inside tool handlers from `req.Extra`, which is set per request. Avoid `auth.TokenInfoFromContext(ctx)` there: on a stateful handler, `ctx` carries the values of the request that created the session, so the token can be stale.

```go
func myTool(ctx context.Context, req *mcp.CallToolRequest, input MyInput) (*mcp.CallToolResult, any, error) {
    if req.Extra == nil || req.Extra.TokenInfo == nil { // Extra is nil on stdio/in-memory
        return nil, nil, &jsonrpc.Error{Code: jsonrpc.CodeInvalidRequest, Message: "unauthenticated"}
    }
    tenantID, ok := req.Extra.TokenInfo.Extra["tenant_id"].(string)
    if !ok || tenantID == "" { // fail closed: never run unscoped
        return nil, nil, &jsonrpc.Error{Code: jsonrpc.CodeInvalidRequest, Message: "token missing tenant"}
    }
    // Use tenantID for RLS, scoping queries, etc.
}
```

### Client-Side OAuth

Clients connecting to OAuth-protected servers set an `OAuthHandler` on the transport:

```go
handler, err := auth.NewAuthorizationCodeHandler(&auth.AuthorizationCodeHandlerConfig{
    // At least one registration method is required. Prefer a Client ID Metadata
    // Document; the spec deprecates Dynamic Client Registration as of 2026-07-28.
    ClientIDMetadataDocumentConfig: &auth.ClientIDMetadataDocumentConfig{
        URL: "https://client.example.com/oauth/metadata.json",
    },
    RedirectURL:              "http://localhost:8089/callback",
    AuthorizationCodeFetcher: fetcher, // opens browser; returns code, state, and iss
})
session, err := client.Connect(ctx, &mcp.StreamableClientTransport{
    Endpoint:     "https://api.example.com/mcp",
    OAuthHandler: handler,
}, nil)
```

The fetcher must return the redirect's `iss` query parameter in `AuthorizationResult.Iss` (RFC 9207 mix-up defense). OAuth discovery rejects private-IP targets by default. For service-to-service auth, use `extauth.NewClientCredentialsHandler` from `auth/extauth`. See `references/reference.md` for the full client OAuth surface, token persistence, and SSRF opt-outs.

To forward a caller's JWT to downstream MCP servers (row-level security, mTLS composition), see `references/security-labels.md`.

## The `_meta` Field

Every result and params type has a `Meta` field (`mcp.Meta`, a `map[string]any`) that appears as `_meta` in JSON. Use it for out-of-band metadata that consuming systems need but the LLM does not:

```go
return &mcp.CallToolResult{
    Meta: mcp.Meta{
        "trace_id":   traceID,
        "latency_ms": elapsed.Milliseconds(),
    },
    Content: []mcp.Content{&mcp.TextContent{Text: result}},
}, nil, nil
```

Prefixes whose second label is `modelcontextprotocol` or `mcp` (such as `io.modelcontextprotocol/`) are reserved: on 2026-07-28 sessions the SDK writes the protocol version, client info, and capabilities into request `_meta` and `io.modelcontextprotocol/serverInfo` into result `_meta`. Use your own reverse-DNS prefix ending in `/` (e.g., `com.example.security/level`); the name after the prefix may contain only alphanumerics, `-`, `_`, and `.`. For distributed tracing, propagate W3C `traceparent`/`tracestate`/`baggage` keys in `_meta`.

## Logging

Logging to the client is deprecated as of 2026-07-28 — prefer stderr (stdio servers) or OpenTelemetry. For legacy clients, or clients that still opt in, forward `slog` records with the request context:

```go
logger := slog.New(mcp.NewLoggingHandler(req.Session, nil))
logger.InfoContext(ctx, "query executed", "rows", count) // pass ctx: the level comes from the request
```

On 2026-07-28 sessions a message is sent only if the request carried a level (`mcp.MetaKeyLogLevel` in `_meta`); `SetLoggingLevel` no longer applies.

## Design Best Practices

- **Single purpose per server.** Each MCP server should have one well-defined domain.
- **Namespace tool names.** When multiple servers may coexist, prefix tools: `inventory_search`, `orders_search`.
- **Design for statelessness.** Return server-minted handles (IDs, cursors) as tool results and accept them as tool arguments instead of keeping per-session state.
- **Return handles, not payloads.** For large data, return URIs to resources rather than inlining megabytes into tool results.
- **Structured content.** Use JSON schemas for tool outputs the LLM will parse; use `TextContent` for human-readable summaries.
- **Stdout is sacred.** Only JSON-RPC messages go to stdout. All logs and debug output go to stderr.
- **Validate inputs.** Use Go struct tags and the generic `AddTool` form to get automatic schema validation. Add custom validation for business rules.

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/protocol-2026-07-28.md` | Stateless lifecycle and discovery, per-request metadata, MRTR in depth (manual retries, load shedding, signed `RequestState`), `subscriptions/listen`, result caching, HTTP header mirroring and `x-mcp-header`, error codes, deprecations, compatibility matrix | Building for or migrating to protocol 2026-07-28, deploying stateless HTTP, or debugging version negotiation |
| `references/reference.md` | Complete type reference, all transport options, session management, event stores, structured output, schema customization, custom JSON-RPC methods, client-side OAuth, testing with in-memory transports | Looking up specific types, writing tests, or implementing advanced patterns |
| `references/migration-from-mark3labs.md` | Step-by-step migration from `mark3labs/mcp-go` to the official SDK, with before/after code for every concept, type mapping table, interop notes, and known gotchas | Migrating an existing codebase from mark3labs/mcp-go |
| `references/security-labels.md` | Sensitivity metadata in `_meta`, high-water-mark rollup, mTLS configuration, JWT passthrough for RLS, sensitivity middleware | Implementing data sensitivity labeling, JWT-based row-level security, or mTLS for MCP servers |
| `references/version-notes.md` | SDK release history v1.0.0–v1.8.0: behavior changes, new APIs per release, `MCPGODEBUG` compatibility flags, stale patterns to avoid | Working with a different SDK version, debugging version-specific behavior, or your SDK knowledge may be outdated |
