---
name: go-mcp
description: Guides development of MCP servers and clients in Go using the official
  SDK (github.com/modelcontextprotocol/go-sdk). Use when building MCP servers, registering
  tools/resources/prompts, choosing transports, adding authentication, or integrating
  MCP endpoints into existing Go services.
---

# MCP Go

> **Verified against SDK v1.6.1** (released 2026-05-22). Supports MCP spec versions 2025-11-25, 2025-06-18, 2025-03-26, and 2024-11-05. Requires Go 1.25+. If your knowledge of this SDK predates v1.5, read `references/version-notes.md` first — several defaults and patterns changed.

The official Go SDK for the Model Context Protocol (`github.com/modelcontextprotocol/go-sdk/mcp`). Do **not** use the third-party `github.com/mark3labs/mcp-go` package. If migrating from `mark3labs/mcp-go`, read `references/migration-from-mark3labs.md`. Both libraries are wire-compatible: an official SDK client works with a mark3labs server (and vice versa) across all transports, so you can migrate incrementally. The one edge case is legacy SSE transport error handling — mark3labs returns JSON-RPC-formatted errors on the HTTP POST endpoint while the official SDK returns plain text, which may affect clients that parse POST error responses as JSON-RPC. This stems from the 2024-11-05 SSE spec being silent on POST error formatting; neither implementation is wrong.

```bash
go get github.com/modelcontextprotocol/go-sdk@v1.6.1
```

Pin an explicit version rather than `@latest`, especially for air-gapped module mirrors. Newer versions are fine — the SDK guarantees no breaking API changes within v1.

Most MCP protocol types are in the `mcp` package. Auth helpers are in `auth` and `oauthex`. Custom transport authors will also use `jsonrpc`.

```go
import (
    "github.com/modelcontextprotocol/go-sdk/mcp"
    "github.com/modelcontextprotocol/go-sdk/auth"
)
```

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

## Transports

| Transport | Server Side | Client Side | Use When |
|---|---|---|---|
| **Stdio** | `mcp.StdioTransport{}` | `mcp.CommandTransport{Command: exec.Command("server")}` | Local subprocess, IDE integrations |
| **Streamable HTTP** | `mcp.NewStreamableHTTPHandler(getServer, opts)` | `mcp.StreamableClientTransport{Endpoint: url}` | Remote servers, production deployments |
| **SSE** (legacy) | `mcp.NewSSEHandler(getServer, opts)` | `mcp.SSEClientTransport{Endpoint: url}` | Legacy clients only; prefer Streamable HTTP |
| **In-Memory** | `mcp.NewInMemoryTransports()` | Same pair | Testing |

### Stdio Server

```go
if err := server.Run(ctx, &mcp.StdioTransport{}); err != nil {
    log.Fatal(err)
}
```

`Run` blocks until the client disconnects. Use for CLI tools and IDE integrations.

### Streamable HTTP Server

```go
handler := mcp.NewStreamableHTTPHandler(
    func(req *http.Request) *mcp.Server { return server },
    &mcp.StreamableHTTPOptions{
        SessionTimeout: 30 * time.Minute,
        Logger:         slog.Default(),
    },
)
http.Handle("/mcp", handler)
log.Fatal(http.ListenAndServe(":8080", nil))
```

The `getServer` callback receives the HTTP request, enabling per-request server instances (e.g., different tools per tenant). When creating a new `*mcp.Server` per request, share a schema cache across instances to avoid re-deriving tool schemas via reflection on every request:

```go
cache := mcp.NewSchemaCache() // create once, share across all servers
handler := mcp.NewStreamableHTTPHandler(func(req *http.Request) *mcp.Server {
    return mcp.NewServer(impl, &mcp.ServerOptions{SchemaCache: cache})
}, nil)
```

### HTTP Security Defaults

- **DNS rebinding protection is on by default**: requests arriving via localhost with a non-localhost `Host` header are rejected with 403. Opt out with `StreamableHTTPOptions.DisableLocalhostProtection` (also on `SSEOptions`).
- **Cross-origin protection is off by default** (since v1.6.0). To enable it, wrap the handler: `http.NewCrossOriginProtection().Handler(mcpHandler)`. Do not use the deprecated `StreamableHTTPOptions.CrossOriginProtection` field.
- **POST requests must have `Content-Type: application/json`**; the escape hatch is `MCPGODEBUG=disablecontenttypecheck=1` (see `references/version-notes.md` for all `MCPGODEBUG` flags).

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
```

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

If a typed tool handler returns a regular Go error, the SDK wraps it into a tool error result (`IsError: true`). Do not leak secrets in error strings — the LLM will see them.

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

## Middleware

Middleware wraps a `MethodHandler`. Both `Server` and `Client` support `AddReceivingMiddleware` and `AddSendingMiddleware`.

```go
type MethodHandler func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error)
type Middleware func(MethodHandler) MethodHandler
```

### Receiving Middleware (Incoming Requests)

Use for authentication, logging, metrics:

```go
server.AddReceivingMiddleware(func(next mcp.MethodHandler) mcp.MethodHandler {
    return func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error) {
        slog.Info("received", "method", method)
        return next(ctx, method, req)
    }
})
```

### Sending Middleware (Outgoing Requests)

Wraps requests and notifications this side *sends* (e.g., server-to-client `CreateMessage`, list-changed notifications) — not responses to incoming requests. Use for tracing, metrics, adding progress tokens:

```go
server.AddSendingMiddleware(func(next mcp.MethodHandler) mcp.MethodHandler {
    return func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error) {
        start := time.Now()
        result, err := next(ctx, method, req)
        slog.Info("sent", "method", method, "duration", time.Since(start))
        return result, err
    }
})
```

Ordering: `AddReceivingMiddleware(m1, m2, m3)` executes as `m1(m2(m3(handler)))` — m1 runs first.

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
        UserID: claims.Subject,
        Scopes: claims.Scopes,
        Extra:  map[string]any{"tenant_id": claims.TenantID},
    }, nil
}

middleware := auth.RequireBearerToken(verifier, &auth.RequireBearerTokenOptions{
    ResourceMetadataURL: "https://api.example.com/.well-known/oauth-protected-resource",
    Scopes:              []string{"mcp:read"},
})

http.Handle("/mcp", middleware(mcpHandler))
```

Access token info inside tool handlers:

```go
func myTool(ctx context.Context, req *mcp.CallToolRequest, input MyInput) (*mcp.CallToolResult, any, error) {
    info := auth.TokenInfoFromContext(ctx)
    tenantID := info.Extra["tenant_id"].(string)
    // Use tenantID for RLS, scoping queries, etc.
}
```

### Client-Side OAuth

Clients connecting to OAuth-protected servers set an `OAuthHandler` on the transport (no build tag required since v1.5.0):

```go
handler, err := auth.NewAuthorizationCodeHandler(&auth.AuthorizationCodeHandlerConfig{
    RedirectURL:              "http://localhost:8089/callback",
    AuthorizationCodeFetcher: fetcher, // opens browser, returns code+state
})
session, err := client.Connect(ctx, &mcp.StreamableClientTransport{
    Endpoint:     "https://api.example.com/mcp",
    OAuthHandler: handler,
}, nil)
```

For service-to-service auth, use `extauth.NewClientCredentialsHandler` from `auth/extauth`. See `references/reference.md` for the full client OAuth surface.

### JWT Passthrough to Downstream Services

Forward the caller's JWT on outbound HTTP requests using a custom `RoundTripper`:

```go
type jwtRoundTripper struct {
    base     http.RoundTripper
    getToken func() string
}

func (j *jwtRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
    if token := j.getToken(); token != "" {
        req.Header.Set("Authorization", "Bearer "+token)
    }
    return j.base.RoundTrip(req)
}
```

This pattern composes with mTLS for defense-in-depth (see `references/security-labels.md`).

## The `_meta` Field

Every `CallToolResult` has a `Meta` field (`map[string]any`) that appears as `_meta` in JSON. Use it for out-of-band metadata that the LLM does not need to reason about but consuming systems do.

```go
return &mcp.CallToolResult{
    Meta: mcp.Meta{
        "trace_id":   traceID,
        "latency_ms": elapsed.Milliseconds(),
    },
    Content: []mcp.Content{&mcp.TextContent{Text: result}},
}, nil, nil
```

Consumers read `_meta` from the tool result without affecting the LLM's content window.

## Logging

Integrate with Go's `slog` to forward server logs to the connected client:

```go
logger := slog.New(mcp.NewLoggingHandler(serverSession, &mcp.LoggingHandlerOptions{}))
logger.Info("query executed", "rows", count)
```

Log levels follow RFC 5424: debug, info, notice, warning, error, critical, alert, emergency.

## Design Best Practices

- **Single purpose per server.** Each MCP server should have one well-defined domain.
- **Namespace tool names.** When multiple servers may coexist, prefix tools: `inventory_search`, `orders_search`.
- **Return handles, not payloads.** For large data, return URIs to resources rather than inlining megabytes into tool results.
- **Structured content.** Use JSON schemas for tool outputs the LLM will parse; use `TextContent` for human-readable summaries.
- **Stdout is sacred.** Only JSON-RPC messages go to stdout. All logs and debug output go to stderr or use MCP logging notifications.
- **Validate inputs.** Use Go struct tags and the generic `AddTool` form to get automatic schema validation. Add custom validation for business rules.

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/reference.md` | Complete type reference, all transport options, session management, event stores, structured output, schema customization, client-side OAuth, advanced middleware patterns, testing with in-memory transports | Looking up specific types, writing tests, or implementing advanced patterns |
| `references/migration-from-mark3labs.md` | Step-by-step migration from `mark3labs/mcp-go` to the official SDK, with before/after code for every concept, type mapping table, and known gotchas | Migrating an existing codebase from mark3labs/mcp-go |
| `references/security-labels.md` | Sensitivity metadata in `_meta`, high-water-mark rollup, mTLS configuration, JWT passthrough for RLS, sensitivity middleware | Implementing data sensitivity labeling, JWT-based row-level security, or mTLS for MCP servers |
| `references/version-notes.md` | SDK release history v1.0.0–v1.6.1: behavior changes, new APIs per release, `MCPGODEBUG` compatibility flags, stale patterns to avoid | Working with a different SDK version, debugging version-specific behavior, or your SDK knowledge may be outdated |
