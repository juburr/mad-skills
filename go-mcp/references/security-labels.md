# Security Labels

Sensitivity labeling, JWT-based row-level security, and mTLS patterns for MCP servers. These patterns apply to any multi-tenant system requiring data-level access control and response-level security labeling — enterprise data governance, regulated industries, or internal sensitivity tiers.

## Sensitivity Labels in `_meta`

MCP's `CallToolResult` has a `Meta` field (JSON `_meta`) for arbitrary metadata. Use `security:`-namespaced keys for sensitivity data to avoid collisions with other metadata consumers.

### Schema

```json
{
  "_meta": {
    "security:level":        "confidential",
    "security:portion_mark": "(C)",
    "security:handling":     ["no-export", "need-to-know"],
    "security:policy":       "data-governance-2024"
  },
  "content": [...]
}
```

| Field | Required | Description |
|---|---|---|
| `security:level` | Yes | Sensitivity level for this tool result |
| `security:portion_mark` | No | Inline marker for the content (e.g., `(C)`, `(I)`) |
| `security:handling` | No | Handling restrictions (e.g., `no-export`, `need-to-know`, `pii`) |
| `security:policy` | No | Reference to the governing data classification policy |

### Server-Side: Returning Labels

```go
func queryHandler(ctx context.Context, req *mcp.CallToolRequest, input QueryInput) (*mcp.CallToolResult, any, error) {
    rows := queryWithRLS(ctx, input)
    maxLevel, handling := deriveSensitivity(rows)

    return &mcp.CallToolResult{
        Meta: mcp.Meta{
            "security:level":    maxLevel,
            "security:handling": handling,
        },
        Content: []mcp.Content{&mcp.TextContent{Text: formatResults(rows)}},
    }, nil, nil
}
```

The sensitivity level should be derived from the data itself (row-level labels in the database), not hardcoded per tool.

## Sensitivity Rollup

When an agent calls multiple tools, the overall response sensitivity is the **high-water mark** across all results. This must be computed deterministically — never by the LLM.

### Sensitivity Ordering

Define levels that match your organization's data classification policy. A common four-tier model:

```go
type Level int

const (
    Public       Level = iota // Freely shareable
    Internal                  // Internal use only
    Confidential              // Limited distribution
    Restricted                // Strict access control
)
```

### Thread-Safe Tracker

```go
type Source struct {
    ToolName    string
    Sensitivity Level
    Handling    []string
}

type Tracker struct {
    mu       sync.Mutex
    highest  Level
    handling map[string]struct{}
    sources  []Source
}

func NewTracker() *Tracker {
    return &Tracker{
        handling: make(map[string]struct{}),
    }
}

func (t *Tracker) Record(toolName string, level Level) {
    t.mu.Lock()
    defer t.mu.Unlock()
    t.sources = append(t.sources, Source{ToolName: toolName, Sensitivity: level})
    if level > t.highest {
        t.highest = level
    }
}

func (t *Tracker) HighWaterMark() Level {
    t.mu.Lock()
    defer t.mu.Unlock()
    return t.highest
}
```

The mutex is critical when tools execute concurrently (e.g., parallel fan-out patterns in an agent framework).

### Extracting Labels from Tool Results

On the client/agent side, intercept every tool result and feed the tracker:

```go
func sensitivityCallback(tracker *Tracker) func(toolName string, result *mcp.CallToolResult) {
    return func(toolName string, result *mcp.CallToolResult) {
        meta := result.Meta
        if meta == nil {
            return
        }
        level, ok := meta["security:level"].(string)
        if !ok {
            return
        }
        tracker.Record(toolName, Parse(level))

        if handling, ok := meta["security:handling"].([]any); ok {
            tracker.RecordHandling(toolName, handling)
        }
    }
}
```

### Response Middleware: Deterministic Banner Enforcement

Sensitivity banners must not depend on the LLM. Stamp them in HTTP middleware after the entire agent pipeline completes.

```go
func SensitivityMiddleware(tracker *Tracker, next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        rec := httptest.NewRecorder()
        next.ServeHTTP(rec, r)

        hwm := tracker.HighWaterMark()
        handling := tracker.Handling()

        // Machine-readable headers
        w.Header().Set("X-Sensitivity", hwm.String())
        if len(handling) > 0 {
            w.Header().Set("X-Sensitivity-Handling", strings.Join(handling, ", "))
        }
        w.Header().Set("X-Sensitivity-Sources", formatSources(tracker.Sources()))

        for k, v := range rec.Header() {
            if k != "X-Sensitivity" {
                w.Header()[k] = v
            }
        }
        w.WriteHeader(rec.Code)

        // Human-readable banner
        banner := hwm.String()
        if len(handling) > 0 {
            banner += " [" + strings.Join(handling, ", ") + "]"
        }
        fmt.Fprintf(w, "// SENSITIVITY: %s //\n\n", banner)
        w.Write(rec.Body.Bytes())
    })
}
```

For JSON APIs, wrap the response in an envelope instead:

```go
type LabeledResponse struct {
    Sensitivity string   `json:"sensitivity"`
    Handling    []string `json:"handling,omitempty"`
    Sources     []Source `json:"sensitivity_sources"`
    Response    any      `json:"response"`
}
```

### Two-Layer Architecture

| Layer | Location | Audience | Survives Transport Change |
|---|---|---|---|
| MCP `_meta` | Per-tool JSON-RPC payload | Partners, third-party consumers, agents | Yes (works over stdio, HTTP, in-memory) |
| HTTP headers | Per-response HTTP headers + body banner | API gateways, SIEM, DLP, audit logs | No (HTTP only) |

Both layers are needed. `_meta` is transport-agnostic and gives per-tool granularity. HTTP headers give infrastructure-level rollup without parsing JSON.

### Portion Marks in LLM Instructions

The LLM should preserve existing portion marks but never generate overall sensitivity banners:

```go
Instruction: `You are an analyst.

When source material contains portion markings such as (P), (I),
(C), or (R), preserve them exactly as they appear. Do not add,
remove, or alter any portion markings.
Do not state or infer the overall sensitivity of the response —
sensitivity labels are applied by the system.`
```

## JWT Passthrough for Row-Level Security

The caller's JWT flows through every layer to enforce data-level access control. The token originates at the edge (user login) and must reach every MCP server that touches data.

### Custom RoundTripper

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

### MCP Client with JWT

```go
httpClient := &http.Client{
    Transport: &jwtRoundTripper{
        base:     http.DefaultTransport,
        getToken: func() string { return currentUserJWT },
    },
}

session, _ := client.Connect(ctx, &mcp.StreamableClientTransport{
    Endpoint:   "https://data-service.internal:8443/mcp",
    HTTPClient: httpClient,
}, nil)
```

### Server-Side RLS

On the MCP server, extract the JWT from the request, validate it, and use claims for database queries:

```go
func queryTool(ctx context.Context, req *mcp.CallToolRequest, input QueryInput) (*mcp.CallToolResult, any, error) {
    info := auth.TokenInfoFromContext(ctx)
    tenantID := info.Extra["tenant_id"].(string)

    // Postgres RLS: SET app.tenant_id = tenantID
    rows, _ := db.QueryContext(ctx, "SELECT * FROM records WHERE $1 = $1", tenantID)
    // ... format and return
}
```

### Alternative: JWT in `_meta`

For stdio transports where HTTP headers are unavailable, pass the JWT in the `_meta` field:

```go
result, _ := session.CallTool(ctx, &mcp.CallToolParams{
    Name:      "query",
    Arguments: map[string]any{"q": "search term"},
    Meta:      mcp.Meta{"auth_token": jwt},
})
```

Server-side extraction:

```go
func handler(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    token := req.Params.Meta["auth_token"].(string)
    claims := validateJWT(token)
    // ... use claims for RLS
}
```

## mTLS Configuration

Use mutual TLS when both client and server must present certificates, such as service-to-service communication in zero-trust environments.

### Shared TLS Config

```go
func newMTLSConfig(clientCert, clientKey, caBundlePath string) (*tls.Config, error) {
    cert, err := tls.LoadX509KeyPair(clientCert, clientKey)
    if err != nil {
        return nil, fmt.Errorf("load client cert: %w", err)
    }

    caPEM, err := os.ReadFile(caBundlePath)
    if err != nil {
        return nil, fmt.Errorf("read CA bundle: %w", err)
    }
    caPool := x509.NewCertPool()
    caPool.AppendCertsFromPEM(caPEM)

    return &tls.Config{
        Certificates: []tls.Certificate{cert},
        RootCAs:      caPool,
        MinVersion:   tls.VersionTLS12,
    }, nil
}
```

### Composing mTLS + JWT

```go
tlsCfg, _ := newMTLSConfig(
    "/certs/agent.crt",
    "/certs/agent.key",
    "/certs/ca-bundle.pem",
)

secureClient := &http.Client{
    Transport: &jwtRoundTripper{
        base:     &http.Transport{TLSClientConfig: tlsCfg},
        getToken: getJWTFromSession,
    },
}

// Use for MCP connections
session, _ := client.Connect(ctx, &mcp.StreamableClientTransport{
    Endpoint:   "https://data-service.internal:8443/mcp",
    HTTPClient: secureClient,
}, nil)
```

### Server-Side mTLS

```go
server := &http.Server{
    Addr:    ":8443",
    Handler: sensitivityMiddleware(tracker, mcpHandler),
    TLSConfig: &tls.Config{
        ClientAuth: tls.RequireAndVerifyClientCert,
        ClientCAs:  caPool,
        MinVersion: tls.VersionTLS12,
    },
}
server.ListenAndServeTLS("/certs/server.crt", "/certs/server.key")
```

The same TLS configuration works for both MCP (Streamable HTTP) and A2A connections since both run over standard HTTPS.

## Complete Composition

```
Inbound request                          Outbound response
───────────────                          ─────────────────

Client ──────► mTLS handshake            X-Sensitivity: confidential
               JWT extracted              X-Sensitivity-Sources: [...]
               validated via auth pkg
                    │
                    ▼                    // SENSITIVITY: confidential [need-to-know] //
            ┌───────────────┐
            │  MCP Server   │            { response body with
            │  Tool handlers│              portion marks preserved }
            │  _meta has     │                    ▲
            │  per-tool      │                    │
            │  labels        │           ┌────────┴────────────┐
            │               │           │ Sensitivity          │
            │  callbacks    │           │ Middleware            │
            │  update       │──────────►│                      │
            │  tracker      │  tool     │ reads tracker HWM    │
            └───────────────┘  results  │ stamps HTTP headers  │
                                        │ prepends banner      │
                                        └──────────────────────┘
```

Key principle: the LLM produces content and preserves portion marks. Infrastructure stamps sensitivity labels. These concerns never mix.
