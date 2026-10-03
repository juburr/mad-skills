# Reference

Complete type reference, transport details, session management, and advanced patterns for the official MCP Go SDK.

> Verified against SDK v1.8.0.

## Core Types

### Server and Client

```go
server := mcp.NewServer(impl *mcp.Implementation, opts *mcp.ServerOptions) *mcp.Server
client := mcp.NewClient(impl *mcp.Implementation, opts *mcp.ClientOptions) *mcp.Client
```

### Implementation

```go
type Implementation struct {
    Name        string
    Title       string   // optional; human-readable display name
    Description string   // optional (since v1.7.0)
    Version     string
    WebsiteURL  string   // optional
    Icons       []Icon   // optional
}
```

### ServerOptions

```go
type ServerOptions struct {
    Instructions                string
    Logger                      *slog.Logger
    InitializedHandler          func(context.Context, *mcp.InitializedRequest)  // legacy sessions only
    PageSize                    int  // default: 1000
    RootsListChangedHandler     func(context.Context, *mcp.RootsListChangedRequest)  // deprecated (roots); legacy only
    ProgressNotificationHandler func(context.Context, *mcp.ProgressNotificationServerRequest)
    CompletionHandler           func(context.Context, *mcp.CompleteRequest) (*mcp.CompleteResult, error)
    KeepAlive                   time.Duration  // ping interval; legacy sessions only
    KeepAliveFailureThreshold   int            // consecutive ping failures before close; 0/1 = first failure
    SubscribeHandler            func(context.Context, *mcp.SubscribeRequest) error
    UnsubscribeHandler          func(context.Context, *mcp.UnsubscribeRequest) error
    Capabilities                *mcp.ServerCapabilities  // overrides inferred capabilities
    SchemaCache                 *mcp.SchemaCache  // share via mcp.NewSchemaCache() across per-request servers
    GetSessionID                func() string     // custom session IDs; ignored when Stateless
    SetCacheable                func(ctx context.Context, req mcp.Request, c *mcp.Cacheable)  // ttlMs/cacheScope policy
    SupportedProtocolVersions   []string          // narrow the versions offered; nil = all
}
```

- `SubscribeHandler` and `UnsubscribeHandler` must be set together or not at all.
- `HasTools`/`HasPrompts`/`HasResources` are deprecated; use `Capabilities`.
- A nil `Capabilities` still advertises `logging`; pass `&mcp.ServerCapabilities{}` to advertise nothing by default.

### ClientOptions

```go
type ClientOptions struct {
    Logger                        *slog.Logger
    CreateMessageHandler          func(context.Context, *mcp.CreateMessageRequest) (*mcp.CreateMessageResult, error)  // deprecated (sampling)
    CreateMessageWithToolsHandler func(context.Context, *mcp.CreateMessageWithToolsRequest) (*mcp.CreateMessageWithToolsResult, error)  // deprecated (sampling)
    ElicitationHandler            func(context.Context, *mcp.ElicitRequest) (*mcp.ElicitResult, error)
    ElicitationCompleteHandler    func(context.Context, *mcp.ElicitationCompleteNotificationRequest)  // legacy URL elicitation
    Capabilities                  *mcp.ClientCapabilities
    ToolListChangedHandler        func(context.Context, *mcp.ToolListChangedRequest)
    PromptListChangedHandler      func(context.Context, *mcp.PromptListChangedRequest)
    ResourceListChangedHandler    func(context.Context, *mcp.ResourceListChangedRequest)
    ResourceUpdatedHandler        func(context.Context, *mcp.ResourceUpdatedNotificationRequest)
    LoggingMessageHandler         func(context.Context, *mcp.LoggingMessageRequest)  // deprecated (logging)
    ProgressNotificationHandler   func(context.Context, *mcp.ProgressNotificationClientRequest)
    MultiRoundTrip                *mcp.MultiRoundTripOptions  // nil = automatic MRTR retries
    KeepAlive                     time.Duration  // ping interval; legacy sessions only
    KeepAliveFailureThreshold     int
}
```

`CreateMessageHandler` and `CreateMessageWithToolsHandler` are mutually exclusive (panic if both are set). Setting either one causes the client to advertise the sampling capability; setting `ElicitationHandler` advertises form elicitation (declare `Capabilities.Elicitation.URL` explicitly for URL mode).

### ClientSessionOptions

```go
type ClientSessionOptions struct {
    ProtocolVersion string  // starting version; empty = latest (2026-07-28)
}
```

## Handler Signatures

| Feature | Generic Signature | Non-Generic Signature |
|---|---|---|
| Tool | `func(context.Context, *CallToolRequest, Input) (*CallToolResult, Output, error)` | `func(context.Context, *CallToolRequest) (*CallToolResult, error)` |
| Resource | — | `func(context.Context, *ReadResourceRequest) (*ReadResourceResult, error)` |
| Prompt | — | `func(context.Context, *GetPromptRequest) (*GetPromptResult, error)` |
| Custom method | `func(context.Context, *ServerSession, P) (R, error)` | — |

The generic tool handler's `Input` struct generates the JSON schema automatically from struct field tags. If the handler returns `(nil, output, nil)`, the SDK marshals the output. If it returns `(*CallToolResult{...}, output, nil)`, the explicit result is used as the base, but a non-nil typed output still overwrites its `StructuredContent`, and `Content` is auto-filled only if nil.

Every server request type (`*CallToolRequest`, `*ReadResourceRequest`, ...) is a `*ServerRequest[P]` with fields `Session *ServerSession`, `Params P`, `Extra *RequestExtra` and these methods:

```go
req.ProtocolVersion() string                  // negotiated version for this request
req.ClientInfo() *mcp.Implementation          // from per-request _meta, else initialize
req.ClientCapabilities() *mcp.ClientCapabilities
req.Extra.TokenInfo                           // *auth.TokenInfo from RequireBearerToken, if any
req.Extra.Header                              // http.Header of the HTTP request
```

`req.Extra` is nil on non-HTTP transports (stdio, in-memory); check it before dereferencing. Over HTTP it is populated per request, whereas on a stateful handler the handler's `ctx` carries context values from the request that created the session — read per-request data (token, headers) from `req.Extra`, not from `ctx`.

## Content Types

All implement the `Content` interface:

| Type | Key Fields |
|---|---|
| `TextContent` | `Text string` |
| `ImageContent` | `Data []byte`, `MIMEType string` |
| `AudioContent` | `Data []byte`, `MIMEType string` |
| `EmbeddedResource` | `Resource *ResourceContents` (URI/MIMEType/Text/Blob live on the nested `ResourceContents`) |
| `ResourceLink` | `URI string`, `Name string`, `MIMEType string` |

`Data` and `Blob` are raw bytes; the SDK base64-encodes them on the wire. `ToolUseContent` and `ToolResultContent` are valid only in (deprecated) sampling messages.

## Tool Result

```go
type CallToolResult struct {
    Meta              Meta             // _meta in JSON — arbitrary metadata
    Content           []Content        // content blocks for the LLM
    StructuredContent any              // structured output; any JSON value (SEP-2106)
    IsError           bool             // true = application-level error
    InputRequests     InputRequestMap  // MRTR: requests the client must fulfil (leave Content empty)
    RequestState      string           // MRTR: opaque state echoed on the retry
}
```

Helper methods:

```go
result.SetError(err)     // sets IsError=true; fills Content with the error text only if Content is empty
err := result.GetError() // returns error if IsError is true (always nil on clients)
result.NeedsInput()      // true if the server returned an input-required result
```

`ToolAnnotations.ReadOnlyHint` and `IdempotentHint` are always serialized since v1.7.0, even when `false`.

## Resource Result

```go
type ReadResourceResult struct {
    Meta
    Cacheable                          // TTLMs int, CacheScope string ("public" | "private")
    Contents      []*ResourceContents
    InputRequests InputRequestMap      // MRTR
    RequestState  string               // MRTR
}

type ResourceContents struct {
    URI      string
    MIMEType string
    Text     string  // for text content
    Blob     []byte  // for binary content
}
```

Return `mcp.ResourceNotFoundError(uri)` for missing resources (wire code `-32602`).

## Prompt Result

```go
type GetPromptResult struct {
    Description   string
    Messages      []*PromptMessage
    InputRequests InputRequestMap  // MRTR
    RequestState  string           // MRTR
}

type PromptMessage struct {
    Role    Role     // type Role string; "user" or "assistant" (string literals work)
    Content Content  // TextContent, ImageContent, EmbeddedResource, etc.
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

// Optional: implement on a Transport to limit the versions advertised by server/discover.
type ProtocolVersionSupporter interface {
    SupportsProtocolVersion(version string) bool
}
```

### StdioTransport and IOTransport

Newline-delimited JSON over stdin/stdout (`StdioTransport`) or any reader/writer pair (`IOTransport`):

```go
&mcp.StdioTransport{
    MaxLineLength: 0, // 0 = mcp.DefaultMaxLineLength (16 MiB); negative disables the cap
}

&mcp.IOTransport{
    Reader:        myReadCloser,
    Writer:        myWriteCloser,
    MaxLineLength: 0,
}
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
    DisableStandaloneSSE: false,              // legacy sessions: skip the GET notification stream
    OAuthHandler:         oauthHandler,       // optional: auth.OAuthHandler for OAuth-protected servers
    MaxEventSize:         0,                  // 0 = mcp.DefaultMaxEventSize (16 MiB); negative disables
}
```

On 2026-07-28 sessions the client sends `Mcp-Method`, `Mcp-Name`, and `Mcp-Param-*` headers and receives notifications on `subscriptions/listen` streams instead of a GET stream. A non-2xx response carrying a JSON-RPC error is surfaced as that error without tearing down the session.

### StreamableHTTPHandler and Options

```go
handler := mcp.NewStreamableHTTPHandler(getServer, &mcp.StreamableHTTPOptions{
    Stateless:                    true,              // required for 2026-07-28; no session tracking
    JSONResponse:                 false,             // true = application/json instead of SSE
    Logger:                       slog.Default(),
    EventStore:                   nil,               // stateful legacy sessions only: stream resumption
    SessionTimeout:               30 * time.Minute,  // stateful only
    DisableLocalhostProtection:   false,             // DNS rebinding protection
    MaxRequestBodyBytes:          0,                 // 0 = 4 MiB; negative disables (413 when exceeded)
    PropagateRequestCancellation: true,              // 2026-07-28: cancel handler when the client disconnects
})
```

| Option | Use When |
|---|---|
| `Stateless: true` | Default choice for new servers. Required to serve 2026-07-28. No `Mcp-Session-Id`; GET/DELETE return 405; each request gets a temporary session. |
| `JSONResponse: true` | Environments where SSE is problematic (some proxies, load balancers). Returns `application/json` instead of streaming. |
| `EventStore` | Stateful legacy sessions on unstable networks. Size with `MemoryEventStore.SetMaxBytes()`. Ignored on 2026-07-28 (resumability was removed). |
| `SessionTimeout` | Controls how long idle stateful sessions survive before cleanup. |
| `MaxRequestBodyBytes` | Tools that accept large arguments (> 4 MiB). Raise instead of disabling. |
| `PropagateRequestCancellation: true` | Long-running tools; stops work when the client disconnects. |
| `DisableLocalhostProtection: true` | Only when testing behind a reverse proxy that obscures the client address. |

Cross-origin protection is **not** applied by default. The `CrossOriginProtection` field on `StreamableHTTPOptions` is deprecated — wrap the handler instead:

```go
protected := http.NewCrossOriginProtection().Handler(handler)
```

The `getServer` callback `func(req *http.Request) *mcp.Server` is called per request:
- Return the same `*Server` for shared state across sessions
- Return a new `*Server` per request for tenant isolation or per-user tool sets (share a `SchemaCache`)

### SSEHandler (Deprecated)

```go
handler := mcp.NewSSEHandler(
    func(req *http.Request) *mcp.Server { return server },
    &mcp.SSEOptions{
        DisableLocalhostProtection: false,  // DNS rebinding protection, on by default
        MaxRequestBodyBytes:        0,      // 0 = 4 MiB
    },
)
```

SSE is deprecated in favor of Streamable HTTP and never negotiates 2026-07-28. Use only for backward compatibility with older clients. The SSE client transport uses `Endpoint` (not `ServerURL`):

```go
&mcp.SSEClientTransport{
    Endpoint:     "http://localhost:8080/sse",
    HTTPClient:   customHTTPClient,  // optional
    MaxEventSize: 0,                 // 0 = 16 MiB
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

In-memory and stdio connections negotiate 2026-07-28 by default.

## Session Management

### ServerSession

A server's view of a connection to a specific client. Over stateless HTTP, each request gets its own temporary session.

```go
session, err := server.Connect(ctx, transport, &mcp.ServerSessionOptions{})

session.ID() string                           // "" over stateless HTTP
session.InitializeParams() *InitializeParams  // client's init data (synthesized on 2026-07-28)
session.Close() error
session.Wait() error
session.NotifyProgress(ctx, params)  // progress notification (all versions)

// Legacy-only server-to-client calls. They return an error on 2026-07-28
// sessions; return InputRequests from the handler instead.
session.Elicit(ctx, params)                                                 // request user input
session.CreateMessage(ctx, &mcp.CreateMessageParams{...})                   // deprecated: sampling
session.CreateMessageWithTools(ctx, &mcp.CreateMessageWithToolsParams{...}) // deprecated: sampling with tools
session.ListRoots(ctx, params)                                              // deprecated: roots
session.Ping(ctx, params)
session.NotifyElicitationComplete(ctx, &mcp.ElicitationCompleteParams{ElicitationID: id})

// Deprecated: logging. On 2026-07-28, sent only if the request carried a log level.
session.Log(ctx, params)
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
session.InitializeResult() *InitializeResult  // server capabilities and negotiated ProtocolVersion
session.Close() error
session.Wait() error

// Client-to-server calls
session.CallTool(ctx, params)
session.ListTools(ctx, params)          // TTL-cached on 2026-07-28
session.GetPrompt(ctx, params)
session.ListPrompts(ctx, params)        // TTL-cached on 2026-07-28
session.ReadResource(ctx, params)       // TTL-cached on 2026-07-28
session.ListResources(ctx, params)      // TTL-cached on 2026-07-28
session.ListResourceTemplates(ctx, params)
session.Complete(ctx, params)
session.Subscribe(ctx, params)          // opens a subscriptions/listen stream on 2026-07-28
session.Unsubscribe(ctx, params)        // idempotent
session.NotifyProgress(ctx, params)

// Legacy sessions only (removed from 2026-07-28):
session.SetLoggingLevel(ctx, params)    // deprecated: logging
session.Ping(ctx, params)

// Auto-paginating iterators
session.Tools(ctx, nil)               // iter.Seq2[*Tool, error]
session.Prompts(ctx, nil)             // iter.Seq2[*Prompt, error]
session.Resources(ctx, nil)           // iter.Seq2[*Resource, error]
session.ResourceTemplates(ctx, nil)   // iter.Seq2[*ResourceTemplate, error]
```

### Resource Subscriptions and Updates

Clients subscribe to resource changes:

```go
err := session.Subscribe(ctx, &mcp.SubscribeParams{URI: "config://app/settings"})
// later...
err = session.Unsubscribe(ctx, &mcp.UnsubscribeParams{URI: "config://app/settings"})
```

Server declares subscription support via `SubscribeHandler` and `UnsubscribeHandler` in `ServerOptions` (must set both or neither; both fire on every protocol version). Notify subscribers with:

```go
server.ResourceUpdated(ctx, &mcp.ResourceUpdatedNotificationParams{URI: "config://app/settings"})
```

The notification carries only the URI; clients re-read the resource.

### Elicitation

Implement `ElicitationHandler` so servers can request user input:

```go
client := mcp.NewClient(impl, &mcp.ClientOptions{
    ElicitationHandler: func(ctx context.Context, req *mcp.ElicitRequest) (*mcp.ElicitResult, error) {
        // Prompt the user for input
        return &mcp.ElicitResult{Action: "accept", Content: userResponse}, nil
    },
})
```

Server-side, return an input request from the handler (see SKILL.md). This works for every client over stdio, in-memory, and stateful HTTP. Over `Stateless: true` HTTP it works only for 2026-07-28 clients: the SDK serves legacy (≤ 2025-11-25) clients through a shim that needs server-to-client calls, so their call fails. Check first that the client can render a form — URL-only clients cannot, and older clients send `elicitation: {}` (nil `Form` and `URL`) to mean form support:

```go
caps := req.ClientCapabilities()
if caps == nil || caps.Elicitation == nil || (caps.Elicitation.Form == nil && caps.Elicitation.URL != nil) {
    return nil, nil, fmt.Errorf("client cannot confirm the operation")
}
return &mcp.CallToolResult{
    InputRequests: mcp.InputRequestMap{
        "confirm": &mcp.ElicitParams{Message: "Please confirm the operation", RequestedSchema: schema},
    },
}, nil, nil
```

`RequestedSchema` is a flat object (no nested objects). Each property is one of: a `"string"` (optional `format` `email`/`uri`/`date`/`date-time`, or a single-select enum via `Enum` or titled `OneOf` entries of `{Const, Title}`), a `"number"`/`"integer"`, a `"boolean"`, or a multi-select `"array"` whose `Items` is a string `Enum` or titled `AnyOf` entries. `Default` values are applied when the user accepts without supplying a field (unless the field is also `Required`); `Enum` is allowed only on string fields.

### Sampling (Deprecated)

Sampling is deprecated as of 2026-07-28; servers should call LLM provider APIs directly. To support existing servers, implement `CreateMessageHandler` (or `CreateMessageWithToolsHandler` for tool use — mutually exclusive):

```go
client := mcp.NewClient(impl, &mcp.ClientOptions{
    CreateMessageHandler: func(ctx context.Context, req *mcp.CreateMessageRequest) (*mcp.CreateMessageResult, error) {
        return &mcp.CreateMessageResult{
            Content: &mcp.TextContent{Text: llmResponse},
            Model:   "my-model",
            Role:    "assistant",
        }, nil
    },
})
```

A server may request sampling via `InputRequests` (`*mcp.CreateMessageParams`) only if `req.ClientCapabilities().Sampling` is non-nil; tool-enabled sampling (`*mcp.CreateMessageWithToolsParams` with `Tools`) also requires `Sampling.Tools`, because a client with only a basic `CreateMessageHandler` receives a down-converted request without `Tools` or `ToolChoice`. The retry always carries a `*mcp.CreateMessageWithToolsResult` (array `Content`).

### Roots (Deprecated)

```go
client.AddRoots(&mcp.Root{URI: "file:///workspace", Name: "Project Root"})
client.RemoveRoots("file:///workspace")
```

Servers request roots with `&mcp.ListRootsParams{}` in `InputRequests` (only if the client declared roots) and receive `*mcp.ListRootsResult`. Prefer taking paths as tool arguments.

### Completion

Server-side completion handler for argument autocompletion in UIs:

```go
server := mcp.NewServer(impl, &mcp.ServerOptions{
    CompletionHandler: func(ctx context.Context, req *mcp.CompleteRequest) (*mcp.CompleteResult, error) {
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

Since v1.7.0 the server rejects `completion/complete` requests missing `ref` or `argument.name` with `-32602`. Client-side:

```go
result, err := session.Complete(ctx, &mcp.CompleteParams{...})
```

### KeepAlive (Legacy Sessions)

Set `KeepAlive` on `ServerOptions` or `ClientOptions` to send periodic pings on legacy sessions; `KeepAliveFailureThreshold` tolerates transient misses. `ping` does not exist in 2026-07-28, so the client never starts keepalive on those sessions.

```go
server := mcp.NewServer(impl, &mcp.ServerOptions{
    KeepAlive:                 30 * time.Second,
    KeepAliveFailureThreshold: 3,
})
```

## EventStore (Legacy Stream Resumption)

Enables legacy (≤ 2025-11-25) clients of a *stateful* handler to resume interrupted streams. 2026-07-28 removed resumability.

```go
type EventStore interface {
    Open(ctx context.Context, sessionID, streamID string) error  // may be a no-op
    Append(ctx context.Context, sessionID, streamID string, data []byte) error
    After(ctx context.Context, sessionID, streamID string, index int) iter.Seq2[[]byte, error]
    SessionClosed(ctx context.Context, sessionID string) error
}
```

Built-in implementation (testing or simple deployments):

```go
store := mcp.NewMemoryEventStore(&mcp.MemoryEventStoreOptions{})
handler := mcp.NewStreamableHTTPHandler(getServer, &mcp.StreamableHTTPOptions{
    EventStore: store,
})
```

## Structured Output

Use typed `In` and `Out` types with `mcp.AddTool` for structured input and output:

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

The SDK infers both input and output JSON schemas from struct tags. `In` must be a struct or map; `Out` may be any type with a valid schema (struct, map, slice, primitive). When the handler returns `(nil, output, nil)`:
- `StructuredContent` is populated with the marshaled output
- If `Content` is unset, the SDK populates it with a `TextContent` containing the JSON

Client-side, read structured output:

```go
result, err := session.CallTool(ctx, params)
if result.StructuredContent != nil {
    // Parse structured content (any JSON value)
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

Non-standard keywords (e.g., `x-mcp-header`) go in a property's `Extra` map.

## Custom JSON-RPC Methods

Register non-standard methods (e.g., for an extension) without forking the SDK. Params and results embed `mcp.ParamsBase` / `mcp.ResultBase`:

```go
type SearchParams struct {
    mcp.ParamsBase
    Query string `json:"query"`
}

type SearchResult struct {
    mcp.ResultBase
    Hits []string `json:"hits"`
}

// Server
err := mcp.AddReceivingCustomMethod(server, "acme/search",
    func(ctx context.Context, ss *mcp.ServerSession, p *SearchParams) (*SearchResult, error) {
        return &SearchResult{Hits: search(p.Query)}, nil
    })

// Client: register once, then call on any session
err = mcp.AddSendingCustomMethod[*SearchParams, *SearchResult](client, "acme/search")
res, err := mcp.CallCustomMethod[*SearchParams, *SearchResult](ctx, session, "acme/search", &SearchParams{Query: "q"})
```

Custom methods pass through middleware. Registering a standard MCP method name returns an error. Namespace method names with a vendor prefix.

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

### Server-Side Token Verification

`auth.RequireBearerToken(verifier, opts)` rejects requests without a valid bearer token and checks expiry and `opts.Scopes`.

| `RequireBearerTokenOptions` field | Purpose |
|---|---|
| `ResourceMetadataURL` | Advertised in `WWW-Authenticate` on 401 |
| `Scopes` | Required scopes (403 `insufficient_scope` otherwise) |
| `ClockSkew` | Tolerance when comparing `TokenInfo.Expiration` (default 0 = strict) |
| `AllowMissingExpiration` | Accept tokens with a zero `Expiration` (default rejects them) |

The verifier must enforce audience binding (token passthrough defense). `oauthex.MatchesResource(audClaims, resourceURI)` compares `aud` values with trailing-slash tolerance; use byte equality when you need RFC 9728's strict comparison.

### Client-Side OAuth

Client-side OAuth is compiled unconditionally (the old `mcp_go_client_oauth` build tag no longer exists). Set an `auth.OAuthHandler` on the client transport:

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
    ClientIDMetadataDocumentConfig: &auth.ClientIDMetadataDocumentConfig{URL: cimdURL}, // non-root HTTPS URL; preferred
    PreregisteredClient: &oauthex.ClientCredentials{
        ClientID: id,
        Issuer:   "https://auth.example.com", // optional: refuse other authorization servers (SEP-2352)
    },
    DynamicClientRegistrationConfig: &auth.DynamicClientRegistrationConfig{ // RFC 7591; deprecated by the spec
        Metadata: &oauthex.ClientRegistrationMetadata{
            ClientName:   "my-client",
            RedirectURIs: []string{"http://localhost:8089/callback"}, // required for DCR
            // RequestRefreshToken only adds offline_access; DCR clients must also
            // register the refresh_token grant (listing replaces the default).
            GrantTypes: []string{"authorization_code", "refresh_token"},
        },
    },
    // Required unless inferred from DCR RedirectURIs; with DCR set, must be in that list.
    RedirectURL: "http://localhost:8089/callback",
    // Called with the authorization URL; returns code, state, and iss after user consent.
    AuthorizationCodeFetcher: func(ctx context.Context, args *auth.AuthorizationArgs) (*auth.AuthorizationResult, error) {
        openBrowser(args.URL)
        q := waitForCallbackQuery() // url.Values from the redirect
        return &auth.AuthorizationResult{Code: q.Get("code"), State: q.Get("state"), Iss: q.Get("iss")}, nil
    },
    RequestRefreshToken: true,  // add offline_access when the AS supports it
    ScopeFilter: func(discovered []string) []string { return discovered }, // narrow/extend requested scopes
    Client:      customHTTPClient, // optional; defaults to http.DefaultClient
})

session, err := client.Connect(ctx, &mcp.StreamableClientTransport{
    Endpoint:     "https://api.example.com/mcp",
    OAuthHandler: handler,
}, nil)
```

| Field | Purpose |
|---|---|
| `AuthorizationResult.Iss` | RFC 9207 issuer from the redirect; a mismatch fails. If the AS advertises `authorization_response_iss_parameter_supported`, a missing `iss` fails. |
| `AcceptUnadvertisedIss` | Accept a matching `iss` even when the AS metadata does not advertise support (default rejects) |
| `InitialTokenSource` | Resume with a persisted token (skips the browser flow until it fails) |
| `NewTokenSource` | Wrap the token source after the code exchange (e.g., persist refreshed tokens) |
| `RequestRefreshToken` | Request `offline_access`; with DCR, also add `refresh_token` to `Metadata.GrantTypes` |
| `ScopeFilter` | Adjust scopes discovered from resource metadata before authorization |

**SSRF defaults (v1.8.0).** OAuth discovery rejects `http://` URLs (except loopback), redirects that downgrade to HTTP, URLs with literal private/link-local/CGNAT IPs, and hostnames that resolve to such addresses. For an authorization server on a private network, use a DNS name and pass a `Client` whose `*http.Transport` has a custom `DialContext` (or a configured proxy) — that opts out of the dial-time check, making network filtering your responsibility.

**Service-to-service** (client credentials grant) and **Enterprise Managed Authorization** (SEP-990 token exchange) live in `auth/extauth`:

```go
import "github.com/modelcontextprotocol/go-sdk/auth/extauth"

handler, err := extauth.NewClientCredentialsHandler(...)  // OAuth 2.0 client credentials
handler, err := extauth.NewEnterpriseHandler(...)         // ID token → ID-JAG exchange (RFC 8693)
```

Lower-level `oauthex` helpers: `GetAuthServerMeta` (RFC 8414 metadata), `GetProtectedResourceMetadata`, `RegisterClient` (dynamic client registration), `ParseWWWAuthenticate`, `ExchangeToken` (RFC 8693), `MatchesResource`.

## Logging Integration (Deprecated)

Forward server logs to the client using `slog`. Pass the request context so the per-request level applies on 2026-07-28 sessions:

```go
logger := slog.New(mcp.NewLoggingHandler(req.Session, &mcp.LoggingHandlerOptions{
    LoggerName:  "my-server",
    MinInterval: 100 * time.Millisecond,  // rate-limit log messages; excess are dropped
}))
logger.InfoContext(ctx, "processing request", "tool", toolName)
```

On 2026-07-28 sessions, clients opt in per request with `Meta: mcp.Meta{mcp.MetaKeyLogLevel: "info"}`; on legacy sessions, with `SetLoggingLevel`. Log messages must not contain credentials, PII, or internal system details. Prefer stderr or OpenTelemetry for new servers.

## Testing Patterns

### In-Memory Server/Client Test

```go
func TestMyTool(t *testing.T) {
    ctx := context.Background()
    server := mcp.NewServer(&mcp.Implementation{Name: "test", Version: "v0.0.1"}, nil)
    mcp.AddTool(server, &mcp.Tool{Name: "greet", Description: "say hi"}, greetHandler)

    serverT, clientT := mcp.NewInMemoryTransports()
    if _, err := server.Connect(ctx, serverT, nil); err != nil {
        t.Fatal(err)
    }

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

### Testing Both Protocol Eras

The test above runs on 2026-07-28. Run legacy-sensitive tests (MRTR shim, list-changed, subscriptions) a second time requesting an older version. The option only sets the version the client asks for first, so assert what was negotiated:

```go
for _, want := range []string{"2026-07-28", "2025-11-25"} {
    serverT, clientT := mcp.NewInMemoryTransports()
    if _, err := server.Connect(ctx, serverT, nil); err != nil {
        t.Fatal(err)
    }
    session, err := client.Connect(ctx, clientT, &mcp.ClientSessionOptions{ProtocolVersion: want})
    if err != nil {
        t.Fatal(err)
    }
    if got := session.InitializeResult().ProtocolVersion; got != want {
        t.Fatalf("negotiated %s, want %s", got, want)
    }
    // ... same assertions ...
    session.Close()
}
```

### Testing with HTTP Transport

```go
func TestHTTPServer(t *testing.T) {
    ctx := context.Background()
    server := mcp.NewServer(&mcp.Implementation{Name: "test", Version: "v0.0.1"}, nil)
    // ... register tools ...

    handler := mcp.NewStreamableHTTPHandler(
        func(r *http.Request) *mcp.Server { return server },
        &mcp.StreamableHTTPOptions{Stateless: true}, // stateful handlers negotiate 2025-11-25
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
cache := mcp.NewSchemaCache()
handler := mcp.NewStreamableHTTPHandler(func(req *http.Request) *mcp.Server {
    tenantID := req.Header.Get("X-Tenant-ID")

    server := mcp.NewServer(
        &mcp.Implementation{Name: "multi-tenant", Version: "v1.0.0"},
        &mcp.ServerOptions{SchemaCache: cache},
    )

    // Register only tools this tenant has access to
    for _, tool := range getToolsForTenant(tenantID) {
        mcp.AddTool(server, tool.Definition, tool.Handler)
    }

    return server
}, &mcp.StreamableHTTPOptions{Stateless: true})
```

Derive the tenant from verified token claims, not a client-supplied header, in production.

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

Implement `SupportsProtocolVersion(string) bool` on the transport if it cannot carry every protocol version (as the SSE transport does for 2026-07-28).
