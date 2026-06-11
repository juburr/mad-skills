# Reference

Complete type reference, transport details, session management, and advanced patterns for the official MCP Go SDK.

> Verified against SDK v1.6.1.

## Core Types

### Server and Client

```go
server := mcp.NewServer(impl *mcp.Implementation, opts *mcp.ServerOptions) *mcp.Server
client := mcp.NewClient(impl *mcp.Implementation, opts *mcp.ClientOptions) *mcp.Client
```

### Implementation

```go
type Implementation struct {
    Name       string
    Title      string   // optional; human-readable display name
    Version    string
    WebsiteURL string   // optional
    Icons      []Icon   // optional
}
```

### ServerOptions

```go
type ServerOptions struct {
    Instructions                string
    Logger                      *slog.Logger
    InitializedHandler          func(context.Context, *mcp.InitializedRequest)
    PageSize                    int  // default: 1000
    RootsListChangedHandler     func(context.Context, *mcp.RootsListChangedRequest)
    ProgressNotificationHandler func(context.Context, *mcp.ProgressNotificationServerRequest)
    CompletionHandler           func(context.Context, *mcp.CompleteRequest) (*mcp.CompleteResult, error)
    KeepAlive                   time.Duration  // ping interval; closes session on failure
    SubscribeHandler            func(context.Context, *mcp.SubscribeRequest) error
    UnsubscribeHandler          func(context.Context, *mcp.UnsubscribeRequest) error
    Capabilities                *mcp.ServerCapabilities  // overrides inferred capabilities
    SchemaCache                 *mcp.SchemaCache  // share via mcp.NewSchemaCache() across per-request servers
    GetSessionID                func() string     // custom session IDs (e.g., globally unique for distributed servers)
}
```

`SubscribeHandler` and `UnsubscribeHandler` must be set together or not at all.

### ClientOptions

```go
type ClientOptions struct {
    Logger                      *slog.Logger
    CreateMessageHandler        func(context.Context, *mcp.CreateMessageRequest) (*mcp.CreateMessageResult, error)
    CreateMessageWithToolsHandler func(context.Context, *mcp.CreateMessageWithToolsRequest) (*mcp.CreateMessageWithToolsResult, error)
    ElicitationHandler          func(context.Context, *mcp.ElicitRequest) (*mcp.ElicitResult, error)
    ElicitationCompleteHandler  func(context.Context, *mcp.ElicitationCompleteNotificationRequest)
    Capabilities                *mcp.ClientCapabilities
    ToolListChangedHandler      func(context.Context, *mcp.ToolListChangedRequest)
    PromptListChangedHandler    func(context.Context, *mcp.PromptListChangedRequest)
    ResourceListChangedHandler  func(context.Context, *mcp.ResourceListChangedRequest)
    ResourceUpdatedHandler      func(context.Context, *mcp.ResourceUpdatedNotificationRequest)
    LoggingMessageHandler       func(context.Context, *mcp.LoggingMessageRequest)
    ProgressNotificationHandler func(context.Context, *mcp.ProgressNotificationClientRequest)
    KeepAlive                   time.Duration  // ping interval; closes session on failure
}
```

`CreateMessageHandler` and `CreateMessageWithToolsHandler` are mutually exclusive (panic if both are set). Setting either one causes the client to advertise the sampling capability.

## Handler Signatures

| Feature | Generic Signature | Non-Generic Signature |
|---|---|---|
| Tool | `func(context.Context, *CallToolRequest, Input) (*CallToolResult, Output, error)` | `func(context.Context, *CallToolRequest) (*CallToolResult, error)` |
| Resource | — | `func(context.Context, *ReadResourceRequest) (*ReadResourceResult, error)` |
| Prompt | — | `func(context.Context, *GetPromptRequest) (*GetPromptResult, error)` |

The generic tool handler's `Input` struct generates the JSON schema automatically from struct field tags. If the handler returns `(nil, output, nil)`, the SDK marshals the output. If it returns `(*CallToolResult{...}, output, nil)`, the explicit result is used as the base, but a non-nil typed output still overwrites its `StructuredContent`, and `Content` is auto-filled only if nil.

## Content Types

All implement the `Content` interface:

| Type | Key Fields |
|---|---|
| `TextContent` | `Text string` |
| `ImageContent` | `Data []byte`, `MIMEType string` |
| `AudioContent` | `Data []byte`, `MIMEType string` |
| `EmbeddedResource` | `Resource *ResourceContents` (URI/MIMEType/Text/Blob live on the nested `ResourceContents`) |
| `ResourceLink` | `URI string`, `Name string`, `MIMEType string` |

## Tool Result

```go
type CallToolResult struct {
    Meta              Meta       // _meta in JSON — arbitrary metadata
    Content           []Content  // content blocks for the LLM
    StructuredContent any        // structured output (when OutputSchema is set)
    IsError           bool       // true = application-level error
}
```

Helper methods:

```go
result.SetError(err)     // sets IsError=true; fills Content with the error text only if Content is empty
err := result.GetError() // returns error if IsError is true
```

## Resource Result

```go
type ReadResourceResult struct {
    Contents []*ResourceContents
}

type ResourceContents struct {
    URI      string
    MIMEType string
    Text     string  // for text content
    Blob     []byte  // for binary content
}
```

Return `mcp.ResourceNotFoundError(uri)` for missing resources.

## Prompt Result

```go
type GetPromptResult struct {
    Description string
    Messages    []*PromptMessage
}

type PromptMessage struct {
    Role    Role     // type Role string; "user" or "assistant" (string literals work)
    Content Content  // TextContent, ImageContent, etc.
}
```

## Transport Details

### Transport and Connection Interfaces

```go
type Transport interface {
    Connect(ctx context.Context) (Connection, error)
}

type Connection interface {
    Read(context.Context) (jsonrpc.Message, error)
    Write(context.Context, jsonrpc.Message) error
    Close() error
    SessionID() string
}
```

### StdioTransport

Reads stdin, writes stdout. Newline-delimited JSON.

```go
&mcp.StdioTransport{}
```

### CommandTransport

Spawns a subprocess and communicates via its stdin/stdout.

```go
&mcp.CommandTransport{
    Command:           exec.Command("./my-server", "--flag"),
    TerminateDuration: 10 * time.Second,  // wait before SIGTERM (default: 5s)
}
```

### StreamableClientTransport

```go
&mcp.StreamableClientTransport{
    Endpoint:             "https://api.example.com/mcp",
    HTTPClient:           customHTTPClient,   // optional: for auth, mTLS
    MaxRetries:           5,                  // default 5; negative to disable
    DisableStandaloneSSE: false,              // true to disable standalone SSE stream
    OAuthHandler:         oauthHandler,       // optional: auth.OAuthHandler for OAuth-protected servers
}
```

### StreamableHTTPHandler and Options

```go
handler := mcp.NewStreamableHTTPHandler(getServer, &mcp.StreamableHTTPOptions{
    Stateless:                  false,             // true = no session tracking
    JSONResponse:               false,             // true = application/json instead of SSE
    Logger:                     slog.Default(),
    EventStore:                 mcp.NewMemoryEventStore(nil),  // enables stream resumption
    SessionTimeout:             30 * time.Minute,
    DisableLocalhostProtection: false,             // DNS rebinding protection
})
```

| Option | Use When |
|---|---|
| `Stateless: true` | Simple deployments without session affinity. No per-session state; each request is independent. |
| `JSONResponse: true` | Environments where SSE is problematic (some proxies, load balancers). Returns `application/json` instead of streaming. |
| `EventStore` | Network instability, long tool runs, or server restarts. Enables stream resumption at the cost of memory. Size with `MemoryEventStore.SetMaxBytes()`. |
| `SessionTimeout` | Controls how long idle sessions survive before cleanup. |
| `DisableLocalhostProtection: true` | Only when testing behind a reverse proxy that obscures the client address. |

Cross-origin protection is **not** applied by default. The `CrossOriginProtection` field on `StreamableHTTPOptions` is deprecated — instead, wrap the handler:

```go
protected := http.NewCrossOriginProtection().Handler(handler)
```

For the client transport, configure retries and SSE behavior:

```go
&mcp.StreamableClientTransport{
    Endpoint:             "https://api.example.com/mcp",
    MaxRetries:           5,      // default 5; negative to disable retries
    DisableStandaloneSSE: false,  // true to skip standalone SSE stream
}
```

The `getServer` callback `func(req *http.Request) *mcp.Server` is called per-request:
- Return the same `*Server` for shared state across sessions
- Return a new `*Server` per-request for tenant isolation or per-user tool sets

### SSEHandler (Deprecated)

```go
handler := mcp.NewSSEHandler(
    func(req *http.Request) *mcp.Server { return server },
    &mcp.SSEOptions{
        DisableLocalhostProtection: false,  // DNS rebinding protection, on by default
    },
)
```

SSE is deprecated in favor of Streamable HTTP. Use only for backward compatibility with older clients. The SSE client transport uses `Endpoint` (not `ServerURL`):

```go
&mcp.SSEClientTransport{
    Endpoint:   "http://localhost:8080/sse",
    HTTPClient: customHTTPClient,  // optional
}
```

### IOTransport

Generic reader/writer transport:

```go
&mcp.IOTransport{
    Reader: myReadCloser,
    Writer: myWriteCloser,
}
```

### LoggingTransport

Wraps any transport to log all JSON-RPC messages:

```go
&mcp.LoggingTransport{
    Transport: &mcp.StdioTransport{},
    Writer:    os.Stderr,
}
```

### In-Memory Transport (Testing)

```go
serverTransport, clientTransport := mcp.NewInMemoryTransports()

// Connect server first, then client
session, _ := server.Connect(ctx, serverTransport, nil)
clientSession, _ := client.Connect(ctx, clientTransport, nil)
```

## Session Management

### ServerSession

A server's view of a connection to a specific client.

```go
session, err := server.Connect(ctx, transport, &mcp.ServerSessionOptions{})

session.ID() string
session.InitializeParams() *InitializeParams  // client's init data
session.Close() error
session.Wait() error

// Server-to-client calls
session.CreateMessage(ctx, &mcp.CreateMessageParams{...})                   // request sampling
session.CreateMessageWithTools(ctx, &mcp.CreateMessageWithToolsParams{...}) // sampling with tool use
session.Elicit(ctx, params)          // request user input
session.ListRoots(ctx, params)       // list client roots
session.Log(ctx, params)             // send log message
session.NotifyProgress(ctx, params)  // progress notification
session.Ping(ctx, params)
```

Iterate all active sessions:

```go
for ss := range server.Sessions() {
    fmt.Println(ss.ID())
}
```

### ClientSession

A client's view of a connection to a server.

```go
session.ID() string
session.InitializeResult() *InitializeResult  // server's capabilities
session.Close() error
session.Wait() error

// Client-to-server calls
session.CallTool(ctx, params)
session.ListTools(ctx, params)
session.GetPrompt(ctx, params)
session.ListPrompts(ctx, params)
session.ReadResource(ctx, params)
session.ListResources(ctx, params)
session.ListResourceTemplates(ctx, params)
session.Complete(ctx, params)
session.Subscribe(ctx, params)
session.Unsubscribe(ctx, params)
session.SetLoggingLevel(ctx, params)
session.Ping(ctx, params)
session.NotifyProgress(ctx, params)

// Auto-paginating iterators
session.Tools(ctx, nil)               // iter.Seq2[*Tool, error]
session.Prompts(ctx, nil)             // iter.Seq2[*Prompt, error]
session.Resources(ctx, nil)           // iter.Seq2[*Resource, error]
session.ResourceTemplates(ctx, nil)   // iter.Seq2[*ResourceTemplate, error]
```

### Resource Update Notifications

Notify clients when a resource changes:

```go
server.ResourceUpdated(ctx, &mcp.ResourceUpdatedNotificationParams{URI: "config://app/settings"})
```

### Client Roots

```go
client.AddRoots(&mcp.Root{URI: "file:///workspace", Name: "Project Root"})
client.RemoveRoots("file:///workspace")
```

### Client Sampling

Implement `CreateMessageHandler` to let the server request LLM completions from the client (e.g., agent hosts, gateways):

```go
client := mcp.NewClient(impl, &mcp.ClientOptions{
    CreateMessageHandler: func(ctx context.Context, req *mcp.CreateMessageRequest) (*mcp.CreateMessageResult, error) {
        // Forward to your LLM provider
        return &mcp.CreateMessageResult{
            Content: &mcp.TextContent{Text: llmResponse},
            Model:   "my-model",
            Role:    "assistant",
        }, nil
    },
})
```

For parallel tool calls, use `CreateMessageWithToolsHandler` instead (mutually exclusive — setting both panics):

```go
CreateMessageWithToolsHandler: func(ctx context.Context, req *mcp.CreateMessageWithToolsRequest) (*mcp.CreateMessageWithToolsResult, error) {
    return &mcp.CreateMessageWithToolsResult{
        Content: []mcp.Content{&mcp.TextContent{Text: response}},
        Model:   "my-model",
        Role:    "assistant",
    }, nil
},
```

Server-side, request sampling from a connected client:

```go
result, err := serverSession.CreateMessage(ctx, &mcp.CreateMessageParams{...})
```

### Client Elicitation

Implement `ElicitationHandler` to let the server request additional user input:

```go
client := mcp.NewClient(impl, &mcp.ClientOptions{
    ElicitationHandler: func(ctx context.Context, req *mcp.ElicitRequest) (*mcp.ElicitResult, error) {
        // Prompt the user for input
        return &mcp.ElicitResult{Action: "accept", Content: userResponse}, nil
    },
})
```

Server-side:

```go
result, err := serverSession.Elicit(ctx, &mcp.ElicitParams{
    Message:   "Please confirm the operation",
    RequestedSchema: schema,
})
```

### Completion

Server-side completion handler for argument autocompletion in UIs:

```go
server := mcp.NewServer(impl, &mcp.ServerOptions{
    CompletionHandler: func(ctx context.Context, req *mcp.CompleteRequest) (*mcp.CompleteResult, error) {
        // Return completion suggestions
        return &mcp.CompleteResult{
            Completion: mcp.CompletionResultDetails{
                Values:  []string{"option-a", "option-b"},
                HasMore: false,  // true if more than 100 matches exist
                Total:   2,      // optional: total number of matches
            },
        }, nil
    },
})
```

Client-side:

```go
result, err := session.Complete(ctx, &mcp.CompleteParams{...})
```

### Resource Subscriptions

Clients subscribe to resource changes:

```go
err := session.Subscribe(ctx, &mcp.SubscribeParams{URI: "config://app/settings"})
// later...
err = session.Unsubscribe(ctx, &mcp.UnsubscribeParams{URI: "config://app/settings"})
```

Server declares subscription support via `SubscribeHandler` and `UnsubscribeHandler` in `ServerOptions` (must set both or neither). Notify subscribers with:

```go
server.ResourceUpdated(ctx, &mcp.ResourceUpdatedNotificationParams{URI: "config://app/settings"})
```

### KeepAlive

Set `KeepAlive` on `ServerOptions` or `ClientOptions` to send periodic pings. If the peer fails to respond, the session is automatically closed:

```go
server := mcp.NewServer(impl, &mcp.ServerOptions{
    KeepAlive: 30 * time.Second,
})
```

## EventStore (Stream Resumption)

Enables clients to resume interrupted streams.

```go
type EventStore interface {
    Open(ctx context.Context, sessionID, streamID string) error
    Append(ctx context.Context, sessionID, streamID string, data []byte) error
    After(ctx context.Context, sessionID, streamID string, index int) iter.Seq2[[]byte, error]
    SessionClosed(ctx context.Context, sessionID string) error
}
```

Built-in implementation:

```go
store := mcp.NewMemoryEventStore(&mcp.MemoryEventStoreOptions{})
```

Wire into StreamableHTTPHandler:

```go
handler := mcp.NewStreamableHTTPHandler(getServer, &mcp.StreamableHTTPOptions{
    EventStore: store,
})
```

## Structured Output

Use typed `In` and `Out` structs with `mcp.AddTool` for structured input and output:

```go
type MetricsInput struct {
    Host string `json:"host" jsonschema:"target hostname"`
}

type MetricsOutput struct {
    CPU    float64 `json:"cpu"`
    Memory int64   `json:"memory_mb"`
}

mcp.AddTool(server, &mcp.Tool{
    Name:        "get_metrics",
    Description: "Returns system metrics.",
}, func(ctx context.Context, req *mcp.CallToolRequest, input MetricsInput) (*mcp.CallToolResult, MetricsOutput, error) {
    metrics := collectMetrics(input.Host)
    return nil, MetricsOutput{CPU: metrics.CPU, Memory: metrics.MemoryMB}, nil
})
```

The SDK infers both input and output JSON schemas from struct tags. When the handler returns `(nil, output, nil)`:
- `StructuredContent` is populated with the marshaled output
- If `Content` is unset, the SDK populates it with a `TextContent` containing the JSON

If the handler returns `(*CallToolResult{...}, _, nil)`, the explicit result takes precedence.

Client-side, read structured output:

```go
result, err := session.CallTool(ctx, params)
if result.StructuredContent != nil {
    // Parse structured content
}
```

## Schema Customization (Enums, Ranges)

Struct tags cannot express enums or numeric ranges. Keep the typed generic handler and customize the inferred schema with `jsonschema.For` (from `github.com/google/jsonschema-go/jsonschema`):

```go
type WeatherType string
const (
    Sunny  WeatherType = "sunny"
    Cloudy WeatherType = "cloudy"
)

type WeatherInput struct {
    Type WeatherType `json:"type"`
    Days int         `json:"days"`
}

customSchemas := map[reflect.Type]*jsonschema.Schema{
    reflect.TypeFor[WeatherType](): {Type: "string", Enum: []any{Sunny, Cloudy}},
}
in, err := jsonschema.For[WeatherInput](&jsonschema.ForOptions{TypeSchemas: customSchemas})
if err != nil {
    log.Fatal(err)
}

// Tweak inferred fields directly:
in.Properties["days"].Minimum = jsonschema.Ptr(0.0)
in.Properties["days"].Maximum = jsonschema.Ptr(10.0)

mcp.AddTool(server, &mcp.Tool{
    Name:        "weather",
    InputSchema: in,  // overrides default inference; OutputSchema works the same way
}, weatherHandler)
```

## Protected Resource Metadata (RFC 9728)

Publish OAuth metadata at the well-known endpoint:

```go
import "github.com/modelcontextprotocol/go-sdk/oauthex"

metadataHandler := auth.ProtectedResourceMetadataHandler(&oauthex.ProtectedResourceMetadata{
    Resource:               "https://api.example.com",
    AuthorizationServers:   []string{"https://auth.example.com"},
    ScopesSupported:        []string{"mcp:read", "mcp:write"},
    BearerMethodsSupported: []string{"header"},
})

http.Handle("/.well-known/oauth-protected-resource", metadataHandler)
```

### Client-Side OAuth

Since v1.5.0, no build tag is required and these APIs are covered by the SDK's backward-compatibility guarantee. (Older docs mention a `mcp_go_client_oauth` build tag; it no longer exists. The README's "experimental" footnote predates v1.5.0.) Set an `auth.OAuthHandler` on the client transport:

```go
type OAuthHandler interface {
    TokenSource(ctx context.Context) (oauth2.TokenSource, error)
    Authorize(ctx context.Context, req *http.Request, resp *http.Response) error
}
```

**Authorization code flow** (interactive clients):

```go
handler, err := auth.NewAuthorizationCodeHandler(&auth.AuthorizationCodeHandlerConfig{
    // Client registration: at least ONE of these three must be set.
    // When multiple are set, they are attempted in this order:
    ClientIDMetadataDocumentConfig: &auth.ClientIDMetadataDocumentConfig{URL: cimdURL}, // non-root HTTPS URL
    PreregisteredClient:            &oauthex.ClientCredentials{ClientID: id},
    DynamicClientRegistrationConfig: &auth.DynamicClientRegistrationConfig{ // RFC 7591
        Metadata: &oauthex.ClientRegistrationMetadata{
            ClientName:   "my-client",
            RedirectURIs: []string{"http://localhost:8089/callback"}, // required for DCR
        },
    },
    // Required unless inferred from DCR RedirectURIs; with DCR set, must be in that list.
    RedirectURL: "http://localhost:8089/callback",
    // Called with the authorization URL; returns the code and state after user consent
    AuthorizationCodeFetcher: func(ctx context.Context, args *auth.AuthorizationArgs) (*auth.AuthorizationResult, error) {
        openBrowser(args.URL)
        code, state := waitForCallback()
        return &auth.AuthorizationResult{Code: code, State: state}, nil
    },
    Client: customHTTPClient, // optional; defaults to http.DefaultClient
})

session, err := client.Connect(ctx, &mcp.StreamableClientTransport{
    Endpoint:     "https://api.example.com/mcp",
    OAuthHandler: handler,
}, nil)
```

**Service-to-service** (client credentials grant) and **Enterprise Managed Authorization** (SEP-990 token exchange) live in `auth/extauth`:

```go
import "github.com/modelcontextprotocol/go-sdk/auth/extauth"

handler, err := extauth.NewClientCredentialsHandler(...)  // OAuth 2.0 client credentials
handler, err := extauth.NewEnterpriseHandler(...)         // ID token → ID-JAG exchange (RFC 8693)
```

Lower-level `oauthex` helpers: `GetAuthServerMeta` (RFC 8414 metadata), `GetProtectedResourceMetadata`, `RegisterClient` (dynamic client registration), `ParseWWWAuthenticate`, `ExchangeToken` (RFC 8693).

## Logging Integration

Forward MCP server logs to the connected client using `slog`:

```go
logger := slog.New(mcp.NewLoggingHandler(serverSession, &mcp.LoggingHandlerOptions{
    LoggerName:  "my-server",
    MinInterval: 100 * time.Millisecond,  // rate-limit log messages; excess are dropped
}))
logger.Info("processing request", "tool", toolName, "user", userID)
```

Log messages must not contain credentials, PII, or internal system details. Use `MinInterval` for noisy tools to avoid flooding clients.

## Testing Patterns

### In-Memory Server/Client Test

```go
func TestMyTool(t *testing.T) {
    server := mcp.NewServer(&mcp.Implementation{Name: "test", Version: "v0.0.1"}, nil)
    mcp.AddTool(server, &mcp.Tool{Name: "greet", Description: "say hi"}, greetHandler)

    serverT, clientT := mcp.NewInMemoryTransports()
    server.Connect(ctx, serverT, nil)

    client := mcp.NewClient(&mcp.Implementation{Name: "test-client", Version: "v0.0.1"}, nil)
    session, err := client.Connect(ctx, clientT, nil)
    if err != nil {
        t.Fatal(err)
    }
    defer session.Close()

    result, err := session.CallTool(ctx, &mcp.CallToolParams{
        Name:      "greet",
        Arguments: map[string]any{"name": "World"},
    })
    if err != nil {
        t.Fatal(err)
    }
    if result.IsError {
        t.Fatal("tool returned error")
    }

    text := result.Content[0].(*mcp.TextContent).Text
    if text != "Hello, World!" {
        t.Errorf("got %q, want %q", text, "Hello, World!")
    }
}
```

### Testing with HTTP Transport

```go
func TestHTTPServer(t *testing.T) {
    server := mcp.NewServer(&mcp.Implementation{Name: "test", Version: "v0.0.1"}, nil)
    // ... register tools ...

    handler := mcp.NewStreamableHTTPHandler(
        func(r *http.Request) *mcp.Server { return server },
        nil,
    )
    ts := httptest.NewServer(handler)
    defer ts.Close()

    client := mcp.NewClient(&mcp.Implementation{Name: "test-client", Version: "v0.0.1"}, nil)
    session, err := client.Connect(ctx, &mcp.StreamableClientTransport{
        Endpoint: ts.URL,
    }, nil)
    if err != nil {
        t.Fatal(err)
    }
    defer session.Close()

    // ... call tools and assert ...
}
```

## Per-Request Server Pattern

Create per-request servers for tenant isolation or user-specific tool sets:

```go
handler := mcp.NewStreamableHTTPHandler(func(req *http.Request) *mcp.Server {
    tenantID := req.Header.Get("X-Tenant-ID")

    server := mcp.NewServer(
        &mcp.Implementation{Name: "multi-tenant", Version: "v1.0.0"},
        nil,
    )

    // Register only tools this tenant has access to
    for _, tool := range getToolsForTenant(tenantID) {
        mcp.AddTool(server, tool.Definition, tool.Handler)
    }

    return server
}, nil)
```

## Custom Transport

Implement `Transport` and `Connection` for custom protocols:

```go
type MyTransport struct { /* ... */ }

func (t *MyTransport) Connect(ctx context.Context) (mcp.Connection, error) {
    return &myConn{/* ... */}, nil
}

type myConn struct { /* ... */ }

func (c *myConn) Read(ctx context.Context) (jsonrpc.Message, error)  { /* ... */ }
func (c *myConn) Write(ctx context.Context, msg jsonrpc.Message) error { /* ... */ }
func (c *myConn) Close() error                                         { /* ... */ }
func (c *myConn) SessionID() string                                    { /* ... */ }
```
