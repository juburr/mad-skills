# Migration Guide: mark3labs/mcp-go to Official Go SDK

Step-by-step guide for migrating MCP servers and clients from `github.com/mark3labs/mcp-go` to `github.com/modelcontextprotocol/go-sdk`.

## Overview of Changes

The official SDK is **not a fork** of mark3labs/mcp-go. It is an independent implementation with a different API design. Key architectural differences:

| Aspect | mark3labs/mcp-go | Official go-sdk |
|---|---|---|
| Package layout | Separate packages: `mcp`, `server`, `client`, `transport` | Single `mcp` package |
| Schema definition | Explicit builder functions (`mcp.WithString(...)`) | Reflection from Go struct tags |
| Tool handler args | Manual extraction (`request.RequireString("name")`) | Typed struct parameter, auto-validated |
| Handler return | `(*CallToolResult, error)` | `(*CallToolResult, OutputType, error)` |
| Server options | Variadic functions (`server.WithToolCapabilities()`) | Options structs (`&mcp.ServerOptions{}`) |
| Hooks/middleware | 24+ typed hook functions | `Middleware func(MethodHandler) MethodHandler` chain |
| Session model | Single server, per-session overlays | Distinct `Server`/`ServerSession` types, `getServer` callback |

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

Install:
```bash
go get github.com/modelcontextprotocol/go-sdk@latest
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

Capability registration (tools, resources, prompts, logging) is now automatic based on what you register. You do not explicitly declare capabilities.

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
    Limit int    `json:"limit" jsonschema:"max results"`
}

mcp.AddTool(s, &mcp.Tool{
    Name:        "search",
    Description: "Search the knowledge base.",
}, func(ctx context.Context, req *mcp.CallToolRequest, input SearchInput) (*mcp.CallToolResult, any, error) {
    results := doSearch(input.Query, input.Limit)
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

Struct tags do not support enums directly. Define the schema manually or modify it after generation:

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

For complex schemas or incremental migration, use the non-generic `server.AddTool` method directly. This preserves the two-return-value handler signature:

```go
s.AddTool(&mcp.Tool{
    Name:        "ping",
    Description: "Health check.",
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
return mcp.NewToolResultImage(data, "image/png"), nil
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

// Image result
return &mcp.CallToolResult{
    Content: []mcp.Content{&mcp.ImageContent{Data: data, MIMEType: "image/png"}},
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

// Infrastructure error (protocol level)
return nil, nil, fmt.Errorf("database down: %w", err)
```

With the generic handler, returning a regular Go error automatically sets `IsError: true` and populates content with the error message. Do not leak secrets in error strings — the LLM will see them:
```go
// This becomes a tool error (IsError: true) visible to the LLM
return nil, nil, fmt.Errorf("user not found")

// For true protocol errors that should NOT reach the LLM, return *jsonrpc.Error
return nil, nil, &jsonrpc.Error{Code: jsonrpc.InternalError, Message: "internal failure"}
```

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
- `ResourceContents` is a single type with `Text` and `Blob` fields, replacing `TextResourceContents` and `BlobResourceContents`
- `req` is a pointer

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

### SSE Server

**Before:**
```go
sseServer := server.NewSSEServer(s, "/mcp",
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

### Streamable HTTP Server

**Before:**
```go
httpServer := server.NewStreamableHTTPServer(s, "/mcp",
    server.WithStreamableHTTPContextFunc(func(ctx context.Context, r *http.Request) context.Context {
        return ctx
    }),
)
http.ListenAndServe(":8080", httpServer)
```

**After:**
```go
handler := mcp.NewStreamableHTTPHandler(
    func(req *http.Request) *mcp.Server { return s },
    &mcp.StreamableHTTPOptions{
        SessionTimeout: 30 * time.Minute,
    },
)
http.Handle("/mcp", handler)
http.ListenAndServe(":8080", nil)
```

The `getServer` callback replaces context functions. It receives the HTTP request and returns a `*Server`, enabling per-request server instances for multi-tenant deployments.

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
if err := c.Initialize(ctx, initRequest); err != nil { log.Fatal(err) }
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

`Connect` handles initialization automatically. No separate `Start` + `Initialize` calls.

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
        return next(ctx, method, req)
    }
})

s.AddSendingMiddleware(func(next mcp.MethodHandler) mcp.MethodHandler {
    return func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error) {
        slog.Info("sending", "method", method)
        return next(ctx, method, req)
    }
})
```

For method-specific logic, switch on the `method` string:
```go
s.AddReceivingMiddleware(func(next mcp.MethodHandler) mcp.MethodHandler {
    return func(ctx context.Context, method string, req mcp.Request) (mcp.Result, error) {
        if method == "tools/call" {
            slog.Info("calling tool")
        }
        return next(ctx, method, req)
    }
})
```

## Step 9: Migrate Notifications

**Before:**
```go
// Notify all clients
s.SendNotificationToAllClients("notifications/tools/list_changed", nil)

// Session-specific
s.SendNotificationToSession(sessionID, method, params)
```

**After:**

Tool/resource/prompt list change notifications are sent automatically when you call `AddTool`, `RemoveTool`, `AddResource`, etc.

For resource update notifications:
```go
s.ResourceUpdated(ctx, &mcp.ResourceUpdatedNotificationParams{
    URI: "config://app/settings",
})
```

## Step 10: Migrate Client Usage

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
- Notification handlers are set via `ClientOptions`, not callback registration
- Auto-paginating iterators (`session.Tools(ctx, nil)`) replace manual list calls

## Step 11: Migrate Argument Parsing

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

## Step 12: Migrate Session Context

**Before:**
```go
// Get session from context
session := server.ClientSessionFromContext(ctx)
```

**After:**
```go
// ServerSession is passed directly to middleware
// or available via the getServer callback's HTTP request
```

Session access patterns differ significantly. In the official SDK, the `getServer` callback on HTTP handlers receives the `*http.Request`, enabling per-request context injection. Tool handlers receive context enriched by middleware.

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
| `client.NewClient(transport)` | `mcp.NewClient(impl, opts)` then `client.Connect(ctx, transport, nil)` |
| `server.NewStdioServer(s)` | `s.Run(ctx, &mcp.StdioTransport{})` |
| `server.NewSSEServer(s, path, opts...)` | `mcp.NewSSEHandler(getServer, opts)` |
| `server.NewStreamableHTTPServer(s, path, opts...)` | `mcp.NewStreamableHTTPHandler(getServer, opts)` |
| `transport.NewStdio(cmd, env, args...)` | `&mcp.CommandTransport{Command: exec.Command(cmd, args...)}` |
| `transport.NewSSE(url)` | `&mcp.SSEClientTransport{Endpoint: url}` |
| `transport.NewStreamableHTTP(url)` | `&mcp.StreamableClientTransport{Endpoint: url}` |

## Known Gotchas

1. **Three return values.** Generic tool handlers return `(*CallToolResult, OutputType, error)`. Forgetting the middle value causes compile errors. Use `any` as the output type if you do not need structured output.

2. **Pointer receivers on Content.** Content values are pointers in the official SDK (`&mcp.TextContent{...}`), not values. The `Content` field is `[]mcp.Content` (interface slice), and implementations must be passed as pointers.

3. **No convenience constructors.** `NewToolResultText`, `NewToolResultError`, `NewToolResultImage` do not exist. Build `CallToolResult` structs directly.

4. **Enum support.** Struct-tag-based schema generation does not support enums. Use a manual `InputSchema` map or the low-level `AddTool` method for tools requiring enum constraints.

5. **`req` is a pointer.** All request types (`*CallToolRequest`, `*ReadResourceRequest`, etc.) are pointers in handler signatures. mark3labs uses value types.

6. **Auto-initialization.** `client.Connect` handles the initialize handshake. Do not call a separate `Initialize` method.

7. **Automatic capability advertisement.** Capabilities are inferred from registered features. Do not manually declare `WithToolCapabilities()` etc.

8. **`Arguments` is `json.RawMessage`.** In `CallToolRequest.Params`, `Arguments` is `json.RawMessage`, not `map[string]any`. The generic handler auto-unmarshals this, but low-level handlers must unmarshal manually.

9. **`Content` vs `TextContent`.** In mark3labs, `TextContent` has a `Type: "text"` field you must set. In the official SDK, omit the `Type` field — it is set automatically during serialization.

10. **Middleware ordering.** `AddReceivingMiddleware(m1, m2, m3)` executes m1 first (outermost). This is standard middleware wrapping: `m1(m2(m3(handler)))`.

11. **Typed handler errors become tool errors.** When using the generic `AddTool` path, returning a regular Go error wraps it into a `CallToolResult` with `IsError: true`. The error message is visible to the LLM. Only `*jsonrpc.Error` is treated as a protocol-level error.
