# Migration Guide: mark3labs/mcp-go to Official Go SDK

Step-by-step guide for migrating MCP servers and clients from `github.com/mark3labs/mcp-go` to `github.com/modelcontextprotocol/go-sdk`.

> Verified against SDK v1.8.0. "Before" snippets match mark3labs/mcp-go v1.1.1 (they also apply to most v0.x releases).

## Overview of Changes

The official SDK is **not a fork** of mark3labs/mcp-go. It is an independent implementation with a different API design. Key architectural differences:

| Aspect | mark3labs/mcp-go | Official go-sdk |
|---|---|---|
| Package layout | Separate packages: `mcp`, `server`, `client`, `client/transport` | Single `mcp` package |
| Schema definition | Explicit builder functions (`mcp.WithString(...)`) | Reflection from Go struct tags |
| Tool handler args | Manual extraction (`request.RequireString("name")`) | Typed struct parameter, auto-validated |
| Handler return | `(*CallToolResult, error)` | `(*CallToolResult, OutputType, error)` |
| Server options | Variadic functions (`server.WithToolCapabilities()`) | Options structs (`&mcp.ServerOptions{}`) |
| Hooks/middleware | 24+ typed hook functions | `Middleware func(MethodHandler) MethodHandler` chain |
| Session model | Single server, per-session overlays | Distinct `Server`/`ServerSession` types, `getServer` callback |
| Server-to-client requests | `s.RequestElicitation` / `RequestSampling` / `RequestRoots` | Return `InputRequests` from the handler (Multi Round-Trip Requests) |

## Step 1: Update Imports

Replace all mark3labs imports with the single `mcp` package.

**Before:**
```go
import (
    "github.com/mark3labs/mcp-go/mcp"
    "github.com/mark3labs/mcp-go/server"
    "github.com/mark3labs/mcp-go/client"
    "github.com/mark3labs/mcp-go/client/transport"
)
```

**After:**
```go
import (
    "github.com/modelcontextprotocol/go-sdk/mcp"
)
```

Install the `mcp` package (the module root has no package, so `go get` on the bare module path leaves `go.sum` incomplete):
```bash
go get github.com/modelcontextprotocol/go-sdk/mcp@v1.8.0
```

## Step 2: Migrate Server Creation

**Before:**
```go
s := server.NewMCPServer(
    "my-server",
    "1.0.0",
    server.WithResourceCapabilities(true, true),
    server.WithPromptCapabilities(true),
    server.WithToolCapabilities(true),
    server.WithLogging(),
    server.WithInstructions("Server instructions"),
)
```

**After:**
```go
s := mcp.NewServer(
    &mcp.Implementation{Name: "my-server", Version: "1.0.0"},
    &mcp.ServerOptions{
        Instructions: "Server instructions",
    },
)
```

Capabilities are inferred from what you register **before** the server is connected (logging is advertised by default). A server that registers features only after connecting must declare them in `ServerOptions.Capabilities`.

## Step 3: Migrate Tool Definitions

The biggest change. mark3labs uses builder functions; the official SDK uses Go structs with `jsonschema` tags.

### Simple Tool

**Before:**
```go
tool := mcp.NewTool("search",
    mcp.WithDescription("Search the knowledge base"),
    mcp.WithString("query",
        mcp.Required(),
        mcp.Description("Search query"),
    ),
    mcp.WithNumber("limit",
        mcp.Description("Max results"),
    ),
)

s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    query, _ := req.RequireString("query")
    limit := req.GetInt("limit", 10)
    results := doSearch(query, limit)
    return mcp.NewToolResultText(results), nil
})
```

**After:**
```go
type SearchInput struct {
    Query string `json:"query" jsonschema:"search query"`
    Limit int    `json:"limit,omitempty" jsonschema:"max results"`
}

mcp.AddTool(s, &mcp.Tool{
    Name:        "search",
    Description: "Search the knowledge base.",
}, func(ctx context.Context, req *mcp.CallToolRequest, input SearchInput) (*mcp.CallToolResult, any, error) {
    limit := input.Limit
    if limit == 0 {
        limit = 10
    }
    results := doSearch(input.Query, limit)
    return &mcp.CallToolResult{
        Content: []mcp.Content{&mcp.TextContent{Text: results}},
    }, nil, nil
})
```

Note the differences:
- `mcp.AddTool` is a **package-level generic function**, not a method on server
- Input struct replaces builder functions — JSON schema is inferred from struct tags
- Handler receives a typed `input` parameter instead of raw request
- Handler returns **three values**: `(*CallToolResult, OutputType, error)`
- `req` is a pointer (`*mcp.CallToolRequest`) instead of a value

### Required Fields

**Before:** `mcp.Required()` option on each field.

**After:** All exported struct fields are required by default. Make fields optional with the `omitempty` JSON tag:

```go
type Input struct {
    Query string `json:"query" jsonschema:"search query"`         // required
    Limit int    `json:"limit,omitempty" jsonschema:"max results"` // optional
}
```

### Enum Fields

Struct tags do not support enums directly. The preferred approach keeps the typed generic handler and sets `Tool.InputSchema` from `jsonschema.For[T]` with `jsonschema.ForOptions{TypeSchemas: ...}` (see "Schema Customization" in the reference file). Alternatively, define the schema manually with the low-level `AddTool` method:

**Before:**
```go
mcp.WithString("format",
    mcp.Enum("json", "csv", "xml"),
    mcp.Description("Output format"),
)
```

**After (manual schema):**
```go
s.AddTool(&mcp.Tool{
    Name:        "export",
    Description: "Export data.",
    InputSchema: map[string]any{
        "type": "object",
        "properties": map[string]any{
            "format": map[string]any{
                "type":        "string",
                "enum":        []string{"json", "csv", "xml"},
                "description": "Output format",
            },
        },
        "required": []string{"format"},
    },
}, func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    // Manual arg parsing with low-level AddTool
    return &mcp.CallToolResult{
        Content: []mcp.Content{&mcp.TextContent{Text: "done"}},
    }, nil
})
```

### Low-Level Fallback

For complex schemas or incremental migration, use the non-generic `server.AddTool` method directly. This preserves the two-return-value handler signature. Unlike the generic form, `InputSchema` is required — `AddTool` panics if it is nil:

```go
s.AddTool(&mcp.Tool{
    Name:        "ping",
    Description: "Health check.",
    InputSchema: map[string]any{"type": "object"},  // required; use this for no-input tools
}, func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    return &mcp.CallToolResult{
        Content: []mcp.Content{&mcp.TextContent{Text: "pong"}},
    }, nil
})
```

This is useful as an intermediate migration step before converting to typed input structs.

## Step 4: Migrate Tool Results

**Before:**
```go
// Convenience constructors
return mcp.NewToolResultText("hello"), nil
return mcp.NewToolResultError("not found"), nil
return mcp.NewToolResultImage("chart", base64PNG, "image/png"), nil // data is a base64 string
```

**After:**
```go
// Explicit struct construction
return &mcp.CallToolResult{
    Content: []mcp.Content{&mcp.TextContent{Text: "hello"}},
}, nil, nil

// Error result
return &mcp.CallToolResult{
    IsError: true,
    Content: []mcp.Content{&mcp.TextContent{Text: "not found"}},
}, nil, nil

// Image result: Data is raw bytes; the SDK base64-encodes on the wire
return &mcp.CallToolResult{
    Content: []mcp.Content{
        &mcp.TextContent{Text: "chart"},
        &mcp.ImageContent{Data: pngBytes, MIMEType: "image/png"},
    },
}, nil, nil
```

The official SDK does not provide shorthand constructors like `NewToolResultText`. Build `CallToolResult` structs directly.

### Error Handling Changes

**Before:**
```go
// Application error (shown to LLM)
return mcp.NewToolResultError("user not found"), nil

// Infrastructure error (protocol level)
return nil, fmt.Errorf("database down: %w", err)
```

**After:**
```go
// Application error (shown to LLM)
return &mcp.CallToolResult{
    IsError: true,
    Content: []mcp.Content{&mcp.TextContent{Text: "user not found"}},
}, nil, nil

// CAUTION — this is NOT a protocol error in the official SDK. A plain Go
// error from a typed handler is wrapped into a tool result with IsError: true,
// and the message is shown to the LLM:
return nil, nil, fmt.Errorf("database down: %w", err)

// Infrastructure error (protocol level, hidden from the LLM): return *jsonrpc.Error
return nil, nil, &jsonrpc.Error{Code: jsonrpc.CodeInternalError, Message: "internal failure"}
```

This is a behavioral difference from mark3labs, where `return nil, err` produced a protocol-level error. In the official SDK, only `*jsonrpc.Error` is treated as a protocol error; any other Go error becomes a tool error visible to the LLM. Do not leak secrets in error strings.

## Step 5: Migrate Resources

**Before:**
```go
resource := mcp.NewResource(
    "config://app/settings",
    "App Settings",
    mcp.WithResourceDescription("Application config"),
    mcp.WithMIMEType("application/json"),
)

s.AddResource(resource, func(ctx context.Context, req mcp.ReadResourceRequest) ([]mcp.ResourceContents, error) {
    data := loadSettings()
    return []mcp.ResourceContents{
        mcp.TextResourceContents{
            URI:      "config://app/settings",
            MIMEType: "application/json",
            Text:     data,
        },
    }, nil
})
```

**After:**
```go
s.AddResource(&mcp.Resource{
    URI:         "config://app/settings",
    Name:        "App Settings",
    Description: "Application config",
    MIMEType:    "application/json",
}, func(ctx context.Context, req *mcp.ReadResourceRequest) (*mcp.ReadResourceResult, error) {
    data := loadSettings()
    return &mcp.ReadResourceResult{
        Contents: []*mcp.ResourceContents{{
            URI:      req.Params.URI,
            MIMEType: "application/json",
            Text:     data,
        }},
    }, nil
})
```

Key differences:
- Resource struct replaces builder functions
- Handler returns `*ReadResourceResult` (wrapper struct) instead of `[]ResourceContents`
- `ResourceContents` is a single type with `Text` and `Blob` fields, replacing `TextResourceContents` and `BlobResourceContents`; `Blob` is raw bytes, not base64
- `req` is a pointer
- Return `mcp.ResourceNotFoundError(uri)` for unknown URIs (wire code `-32602`)

### Resource Templates

**Before:**
```go
template := mcp.NewResourceTemplate(
    "file:///docs/{path}",
    "Documentation files",
    mcp.WithTemplateDescription("Docs"),
    mcp.WithTemplateMIMEType("text/markdown"),
)
s.AddResourceTemplate(template, handler)
```

**After:**
```go
s.AddResourceTemplate(&mcp.ResourceTemplate{
    URITemplate: "file:///docs/{path}",
    Name:        "Documentation files",
    Description: "Docs",
    MIMEType:    "text/markdown",
}, handler)
```

## Step 6: Migrate Prompts

**Before:**
```go
prompt := mcp.NewPrompt("summarize",
    mcp.WithPromptDescription("Summarize text"),
    mcp.WithArgument("text",
        mcp.ArgumentDescription("text to summarize"),
        mcp.RequiredArgument(),
    ),
)

s.AddPrompt(prompt, func(ctx context.Context, req mcp.GetPromptRequest) (*mcp.GetPromptResult, error) {
    text := req.Params.Arguments["text"]
    return &mcp.GetPromptResult{
        Description: "Summarize the given text",
        Messages: []mcp.PromptMessage{{
            Role: mcp.RoleUser,
            Content: mcp.TextContent{
                Type: "text",
                Text: "Summarize: " + text,
            },
        }},
    }, nil
})
```

**After:**
```go
s.AddPrompt(&mcp.Prompt{
    Name:        "summarize",
    Description: "Summarize text",
    Arguments: []*mcp.PromptArgument{
        {Name: "text", Description: "text to summarize", Required: true},
    },
}, func(ctx context.Context, req *mcp.GetPromptRequest) (*mcp.GetPromptResult, error) {
    text := req.Params.Arguments["text"]
    return &mcp.GetPromptResult{
        Description: "Summarize the given text",
        Messages: []*mcp.PromptMessage{{
            Role:    "user",
            Content: &mcp.TextContent{Text: "Summarize: " + text},
        }},
    }, nil
})
```

Key differences:
- `Prompt` struct replaces builder functions
- `PromptMessage` uses pointer slices (`[]*mcp.PromptMessage`)
- `Content` is a pointer to an interface (`&mcp.TextContent{...}`)
- Role is a plain string (`"user"`, `"assistant"`), not a constant like `mcp.RoleUser`
- `TextContent` does not need a `Type` field — it is inferred

## Step 7: Migrate Transports

### Stdio Server

**Before:**
```go
stdioServer := server.NewStdioServer(s)
if err := stdioServer.Listen(ctx, os.Stdin, os.Stdout); err != nil {
    log.Fatal(err)
}
// or
if err := server.ServeStdio(s); err != nil {
    log.Fatal(err)
}
```

**After:**
```go
if err := s.Run(ctx, &mcp.StdioTransport{}); err != nil {
    log.Fatal(err)
}
```

### Streamable HTTP Server

**Before:**
```go
httpServer := server.NewStreamableHTTPServer(s,
    server.WithEndpointPath("/mcp"),
    server.WithStateLess(true),
    server.WithHTTPContextFunc(func(ctx context.Context, r *http.Request) context.Context {
        return withTenant(ctx, r.Header.Get("X-Tenant-ID"))
    }),
)
http.ListenAndServe(":8080", httpServer)
```

**After:**
```go
// Replaces WithHTTPContextFunc: rebuild the handler context from each request,
// so existing tool handlers that read the tenant from ctx keep working.
s.AddReceivingMiddleware(func(next mcp.MethodHandler) mcp.MethodHandler {
    return func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error) {
        if extra := req.GetExtra(); extra != nil && extra.Header != nil { // nil on stdio/in-memory
            ctx = withTenant(ctx, extra.Header.Get("X-Tenant-ID"))
        }
        return next(ctx, method, req)
    }
})

handler := mcp.NewStreamableHTTPHandler(
    func(req *http.Request) *mcp.Server { return s },
    &mcp.StreamableHTTPOptions{Stateless: true},
)
http.Handle("/mcp", handler)
http.ListenAndServe(":8080", nil)
```

- Use a receiving middleware, not an HTTP middleware that calls `r.WithContext(...)`, to replace a context function. `req.GetExtra()` (`Header`, `TokenInfo`) is populated for every request, whereas on a *stateful* handler the tool handler's `ctx` carries the values of the request that created the session, so per-request values set by HTTP middleware go stale.
- The example keeps the original header-based tenant to stay behavior-compatible. A client-supplied header is not an identity: in production derive the tenant from the verified token (`extra.TokenInfo`, set by `auth.RequireBearerToken`) and reject requests without one.
- The `getServer` callback also receives the HTTP request, enabling per-request server instances (e.g., a tool set per tenant).
- Set `Stateless: true` for new deployments — it is the only mode that serves protocol 2026-07-28. A stateful handler (the default) still serves 2025-11-25 and older clients; use it only if you depend on session IDs or legacy server-to-client requests.

### SSE Server

**Before:**
```go
sseServer := server.NewSSEServer(s,
    server.WithBasePath("/mcp"),
    server.WithSSEContextFunc(func(ctx context.Context, r *http.Request) context.Context {
        return ctx
    }),
)
http.ListenAndServe(":8080", sseServer)
```

**After:**
```go
handler := mcp.NewSSEHandler(
    func(req *http.Request) *mcp.Server { return s },
    nil,
)
http.ListenAndServe(":8080", handler)
```

The SSE transport is deprecated; migrate SSE servers to Streamable HTTP unless a legacy client requires SSE.

### Client Transports

**Before:**
```go
// Stdio
t := transport.NewStdio("./my-server", nil)

// SSE
t, _ := transport.NewSSE("http://localhost:8080/mcp")

// Streamable HTTP
t, _ := transport.NewStreamableHTTP("http://localhost:8080/mcp")

c := client.NewClient(t)
if err := c.Start(ctx); err != nil { log.Fatal(err) }
if _, err := c.Initialize(ctx, initRequest); err != nil { log.Fatal(err) }
```

**After:**
```go
c := mcp.NewClient(
    &mcp.Implementation{Name: "my-client", Version: "1.0.0"},
    nil,
)

// Stdio
session, err := c.Connect(ctx, &mcp.CommandTransport{
    Command: exec.Command("./my-server"),
}, nil)

// SSE
session, err := c.Connect(ctx, &mcp.SSEClientTransport{
    Endpoint: "http://localhost:8080/mcp",
}, nil)

// Streamable HTTP
session, err := c.Connect(ctx, &mcp.StreamableClientTransport{
    Endpoint: "http://localhost:8080/mcp",
}, nil)
```

`Connect` handles discovery and initialization automatically. No separate `Start` + `Initialize` calls.

## Step 8: Migrate Hooks to Middleware

mark3labs uses 24+ typed hook functions. The official SDK uses a unified middleware pattern.

**Before:**
```go
hooks := &server.Hooks{}
hooks.AddBeforeCallTool(func(ctx context.Context, id any, req *mcp.CallToolRequest) {
    log.Printf("calling tool: %s", req.Params.Name)
})
hooks.AddAfterCallTool(func(ctx context.Context, id any, req *mcp.CallToolRequest, result any) {
    log.Printf("tool done: %s", req.Params.Name)
})
hooks.AddOnError(func(ctx context.Context, id any, method mcp.MCPMethod, msg any, err error) {
    log.Printf("error: %v", err)
})

s := server.NewMCPServer("name", "1.0.0", server.WithHooks(hooks))
```

**After:**
```go
s := mcp.NewServer(
    &mcp.Implementation{Name: "name", Version: "1.0.0"},
    nil,
)

s.AddReceivingMiddleware(func(next mcp.MethodHandler) mcp.MethodHandler {
    return func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error) {
        slog.Info("received", "method", method)
        res, err := next(ctx, method, req)
        if err != nil {
            slog.Error("failed", "method", method, "err", err)
        }
        return res, err
    }
})
```

For method-specific logic, switch on the `method` string and type-assert the request:
```go
s.AddReceivingMiddleware(func(next mcp.MethodHandler) mcp.MethodHandler {
    return func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error) {
        if call, ok := req.(*mcp.CallToolRequest); ok {
            slog.Info("calling tool", "name", call.Params.Name)
        }
        return next(ctx, method, req)
    }
})
```

`AddSendingMiddleware` wraps messages the server sends (notifications, legacy server-to-client requests).

## Step 9: Migrate Notifications

**Before:**
```go
// Notify all clients
s.SendNotificationToAllClients("notifications/tools/list_changed", nil)

// Session-specific
s.SendNotificationToSpecificClient(sessionID, method, params)
```

**After:**

Tool/resource/prompt list change notifications are sent automatically when you call `AddTool`, `RemoveTools`, `AddResource`, etc.

For resource update notifications:
```go
s.ResourceUpdated(ctx, &mcp.ResourceUpdatedNotificationParams{
    URI: "config://app/settings",
})
```

For progress on a specific request, use `req.Session.NotifyProgress` inside the handler. There is no API for arbitrary notifications to a session ID.

## Step 10: Migrate Server-to-Client Requests

mark3labs servers call the client mid-handler. The official SDK uses Multi Round-Trip Requests: return the request, and the handler runs again with the answer. This works for every client over stdio, in-memory, and stateful HTTP. Over `Stateless: true` HTTP it works only for 2026-07-28 clients: the SDK serves older clients through a shim that needs server-to-client calls, so their call fails.

**Before:**
```go
s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    res, err := s.RequestElicitation(ctx, mcp.ElicitationRequest{
        Params: mcp.ElicitationParams{
            Message:         "Proceed?",
            RequestedSchema: confirmSchema,
        },
    })
    if err != nil {
        return nil, err
    }
    if res.Action != mcp.ElicitationResponseActionAccept {
        return mcp.NewToolResultText("cancelled"), nil
    }
    return mcp.NewToolResultText(doWork()), nil
})
```

**After:**
```go
mcp.AddTool(s, &mcp.Tool{Name: "work"}, func(ctx context.Context, req *mcp.CallToolRequest, _ struct{}) (*mcp.CallToolResult, any, error) {
    res, answered := req.Params.InputResponses["proceed"].(*mcp.ElicitResult)
    if !answered {
        // Form elicitation needs a client that declared it; URL-only clients cannot render forms.
        caps := req.ClientCapabilities()
        if caps == nil || caps.Elicitation == nil || (caps.Elicitation.Form == nil && caps.Elicitation.URL != nil) {
            return nil, nil, fmt.Errorf("client cannot confirm; refusing to proceed")
        }
        return &mcp.CallToolResult{
            InputRequests: mcp.InputRequestMap{
                "proceed": &mcp.ElicitParams{Message: "Proceed?", RequestedSchema: confirmSchema},
            },
        }, nil, nil
    }
    if res.Action != "accept" {
        return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: "cancelled"}}}, nil, nil
    }
    return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: doWork()}}}, nil, nil
})
```

This tool takes no arguments. When the confirmed action depends on arguments or on the caller, also bind the answer to them with a signed `RequestState` (the `deleteRepo` example in SKILL.md): the client sends both rounds, so otherwise a retry can carry an answer onto different arguments.

`RequestSampling` maps to `&mcp.CreateMessageParams{...}` (answered with `*mcp.CreateMessageWithToolsResult`) and `RequestRoots` to `&mcp.ListRootsParams{}` (answered with `*mcp.ListRootsResult`); both features are deprecated in the 2026-07-28 spec. Calling `req.Session.Elicit` directly also compiles but fails on 2026-07-28 sessions.

## Step 11: Migrate Client Usage

**Before:**
```go
c := client.NewClient(t)
c.Start(ctx)
c.Initialize(ctx, mcp.InitializeRequest{...})

// Call tool
result, err := c.CallTool(ctx, mcp.CallToolRequest{
    Params: mcp.CallToolParams{
        Name:      "search",
        Arguments: map[string]any{"query": "test"},
    },
})

// List tools
tools, err := c.ListTools(ctx, mcp.ListToolsRequest{})

// Handle notifications
c.OnNotification(func(notif mcp.JSONRPCNotification) {
    // ...
})
```

**After:**
```go
c := mcp.NewClient(
    &mcp.Implementation{Name: "my-client", Version: "1.0.0"},
    &mcp.ClientOptions{
        ToolListChangedHandler: func(ctx context.Context, req *mcp.ToolListChangedRequest) {
            // tool list changed
        },
        ElicitationHandler: func(ctx context.Context, req *mcp.ElicitRequest) (*mcp.ElicitResult, error) {
            return askUser(req.Params) // answers server input requests
        },
    },
)
session, err := c.Connect(ctx, transport, nil)

// Call tool
result, err := session.CallTool(ctx, &mcp.CallToolParams{
    Name:      "search",
    Arguments: map[string]any{"query": "test"},
})

// List tools (auto-paginating iterator)
for tool, err := range session.Tools(ctx, nil) {
    if err != nil { log.Fatal(err) }
    fmt.Println(tool.Name)
}
```

Key differences:
- `Connect` replaces `Start` + `Initialize`
- Methods are on `*ClientSession`, not `*Client`
- Notification and request handlers are set via `ClientOptions`, not callback registration
- Auto-paginating iterators (`session.Tools(ctx, nil)`) replace manual list calls

## Step 12: Migrate Argument Parsing

If migrating incrementally and not yet using typed input structs, translate manual argument parsing:

**Before (mark3labs helpers):**
```go
func handler(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    name, err := req.RequireString("name")
    age := req.GetInt("age", 0)
    tags := req.GetStringSlice("tags", nil)

    var input MyStruct
    if err := req.BindArguments(&input); err != nil { ... }
}
```

**After (manual JSON parsing with low-level handler):**
```go
func handler(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    var args map[string]any
    if err := json.Unmarshal(req.Params.Arguments, &args); err != nil {
        return nil, err
    }
    name, _ := args["name"].(string)

    // Or unmarshal directly into a struct:
    var input MyStruct
    if err := json.Unmarshal(req.Params.Arguments, &input); err != nil {
        return nil, err
    }
}
```

**After (preferred — typed generic handler):**
```go
type Input struct {
    Name string   `json:"name" jsonschema:"user name"`
    Age  int      `json:"age,omitempty" jsonschema:"user age"`
    Tags []string `json:"tags,omitempty" jsonschema:"tag list"`
}

func handler(ctx context.Context, req *mcp.CallToolRequest, input Input) (*mcp.CallToolResult, any, error) {
    // input is already validated and populated
}
```

## Step 13: Migrate Session Context

**Before:**
```go
// Get session from context
session := server.ClientSessionFromContext(ctx)
```

**After:**
```go
func handler(ctx context.Context, req *mcp.CallToolRequest, in Input) (*mcp.CallToolResult, any, error) {
    ss := req.Session          // *mcp.ServerSession
    caller := req.ClientInfo() // client name/version
    if req.Extra != nil {      // nil on stdio and in-memory transports
        token := req.Extra.TokenInfo // from auth.RequireBearerToken; may be nil
        tenant := req.Extra.Header.Get("X-Tenant-ID")
        // ...
    }
    // ...
}
```

Over stateless HTTP each request has its own temporary `ServerSession` (`ss.ID()` is `""`), so do not key long-lived state on the session; pass server-minted handles as tool arguments instead.

## Quick Reference: Type Mapping

| mark3labs Type | Official SDK Type |
|---|---|
| `server.NewMCPServer(name, version, opts...)` | `mcp.NewServer(impl, opts)` |
| `mcp.NewTool(name, opts...)` | `&mcp.Tool{Name: ..., Description: ...}` |
| `mcp.NewResource(uri, name, opts...)` | `&mcp.Resource{URI: ..., Name: ...}` |
| `mcp.NewResourceTemplate(uri, name, opts...)` | `&mcp.ResourceTemplate{URITemplate: ..., Name: ...}` |
| `mcp.NewPrompt(name, opts...)` | `&mcp.Prompt{Name: ..., Description: ...}` |
| `mcp.TextContent{Type: "text", Text: s}` | `&mcp.TextContent{Text: s}` |
| `mcp.TextResourceContents{...}` | `&mcp.ResourceContents{Text: s}` |
| `mcp.BlobResourceContents{...}` | `&mcp.ResourceContents{Blob: data}` |
| `mcp.NewToolResultText(s)` | `&mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: s}}}` |
| `mcp.NewToolResultError(s)` | `&mcp.CallToolResult{IsError: true, Content: []mcp.Content{&mcp.TextContent{Text: s}}}` |
| `server.Hooks{}` | `s.AddReceivingMiddleware(...)` / `s.AddSendingMiddleware(...)` |
| `s.RequestElicitation(ctx, req)` | Return `InputRequests: mcp.InputRequestMap{"id": &mcp.ElicitParams{...}}` |
| `server.ClientSessionFromContext(ctx)` | `req.Session` |
| `client.NewClient(transport)` | `mcp.NewClient(impl, opts)` then `client.Connect(ctx, transport, nil)` |
| `server.NewStdioServer(s)` / `server.ServeStdio(s)` | `s.Run(ctx, &mcp.StdioTransport{})` |
| `server.NewSSEServer(s, opts...)` | `mcp.NewSSEHandler(getServer, opts)` |
| `server.NewStreamableHTTPServer(s, opts...)` | `mcp.NewStreamableHTTPHandler(getServer, &mcp.StreamableHTTPOptions{Stateless: true})` |
| `transport.NewStdio(cmd, env, args...)` | `&mcp.CommandTransport{Command: exec.Command(cmd, args...)}` |
| `transport.NewSSE(url)` | `&mcp.SSEClientTransport{Endpoint: url}` |
| `transport.NewStreamableHTTP(url)` | `&mcp.StreamableClientTransport{Endpoint: url}` |

## Interoperability During Migration

Both libraries speak protocol 2026-07-28 and fall back to older versions, so mixed fleets work — with one exception. Observed with SDK v1.8.0 and mark3labs/mcp-go v1.1.1:

| Client → Server | Result |
|---|---|
| Official client → mark3labs server (stdio or Streamable HTTP) | Works (2026-07-28) |
| mark3labs client → official server (stdio) | Works (2026-07-28) |
| mark3labs client → official Streamable HTTP, `Stateless: true` | Works (2026-07-28) |
| mark3labs client → official Streamable HTTP, stateful | **Fails on the first call**: the mark3labs client ignores the server's `supportedVersions` and keeps using 2026-07-28. Fix server-side with `Stateless: true`, or client-side with `client.WithLegacyProtocolOnly()` |

Legacy SSE transport edge case: mark3labs returns JSON-RPC-formatted errors on the HTTP POST endpoint while the official SDK returns plain text. The 2024-11-05 SSE spec does not specify POST error formatting, so neither is wrong, but clients that parse POST error bodies as JSON-RPC may misreport errors.

## Known Gotchas

1. **Three return values.** Generic tool handlers return `(*CallToolResult, OutputType, error)`. Forgetting the middle value causes compile errors. Use `any` as the output type if you do not need structured output.

2. **Pointer receivers on Content.** Content values are pointers in the official SDK (`&mcp.TextContent{...}`), not values. The `Content` field is `[]mcp.Content` (interface slice), and implementations must be passed as pointers.

3. **No convenience constructors.** `NewToolResultText`, `NewToolResultError`, `NewToolResultImage` do not exist. Build `CallToolResult` structs directly.

4. **Binary data is raw bytes.** mark3labs carries base64 strings in image, audio, and blob fields; the official SDK uses `[]byte` and encodes on the wire. Decode existing base64 before assigning it, or clients receive double-encoded data.

5. **Enum support.** Struct-tag-based schema generation does not support enums. Set `Tool.InputSchema` explicitly — either via `jsonschema.For[T]` with `ForOptions{TypeSchemas: ...}` (keeps the typed handler) or a manual schema with the low-level `AddTool` method.

6. **`req` is a pointer.** All request types (`*CallToolRequest`, `*ReadResourceRequest`, etc.) are pointers in handler signatures. mark3labs uses value types.

7. **Auto-initialization.** `client.Connect` handles discovery and the initialize handshake. Do not call a separate `Initialize` method.

8. **Automatic capability advertisement.** Capabilities are inferred from features registered before connecting. Do not manually declare `WithToolCapabilities()` etc.

9. **`Arguments` is `json.RawMessage`.** In `CallToolRequest.Params`, `Arguments` is `json.RawMessage`, not `map[string]any`. The generic handler auto-unmarshals this, but low-level handlers must unmarshal manually.

10. **`Content` vs `TextContent`.** In mark3labs, `TextContent` has a `Type: "text"` field you must set. In the official SDK, omit the `Type` field — it is set automatically during serialization.

11. **Middleware ordering.** `AddReceivingMiddleware(m1, m2, m3)` executes m1 first (outermost). This is standard middleware wrapping: `m1(m2(m3(handler)))`.

12. **Typed handler errors become tool errors.** When using the generic `AddTool` path, returning a regular Go error wraps it into a `CallToolResult` with `IsError: true`. The error message is visible to the LLM. Only `*jsonrpc.Error` is treated as a protocol-level error.

13. **No mid-handler client calls.** Replace `RequestElicitation`/`RequestSampling`/`RequestRoots` with `InputRequests`; the handler must be safe to run more than once per logical call.
