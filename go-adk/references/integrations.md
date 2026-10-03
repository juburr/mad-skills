# Integrations

Model providers (Gemini, OpenAI-compatible, Apigee, custom), the model registry, MCP toolsets, outbound auth, A2A clients, Google Cloud Agent Registry, service backends, and pinned dependencies for ADK Go. Verified against `google.golang.org/adk/v2` v2.5.0.

## Gemini

```go
import (
    "google.golang.org/adk/v2/model/gemini"
    "google.golang.org/genai"
)

// Gemini API (AI Studio).
m, err := gemini.NewModel(ctx, "gemini-flash-latest", &genai.ClientConfig{
    APIKey: os.Getenv("GOOGLE_API_KEY"),
})

// Vertex AI. Vertex does not serve the "-latest" aliases; use a concrete model ID.
m, err := gemini.NewModel(ctx, "gemini-3.5-flash", &genai.ClientConfig{
    Project:  "my-gcp-project",
    Location: "us-central1",
    Backend:  genai.BackendVertexAI,
})

// Environment-driven: a nil config resolves backend, key, project, and location from env vars.
m, err := gemini.NewModel(ctx, "gemini-flash-latest", nil)
```

Environment variables: `GOOGLE_API_KEY` or `GEMINI_API_KEY` (Gemini API); `GOOGLE_GENAI_USE_VERTEXAI=true`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION` (Vertex AI). genai v1.71.0 also adds `genai.BackendEnterprise` and `GOOGLE_GENAI_USE_ENTERPRISE`, which takes precedence over the Vertex flag.

```go
type ClientConfig struct { // google.golang.org/genai v1.71.0
    APIKey      string
    Backend     Backend           // BackendGeminiAPI (default), BackendVertexAI, BackendEnterprise
    Project     string
    Location    string
    Credentials *auth.Credentials // cloud.google.com/go/auth
    HTTPClient  *http.Client
    HTTPOptions HTTPOptions       // A value, not a pointer.
}
```

Since v2.0.0 the Gemini model no longer injects a placeholder user turn when the request has no contents.

## OpenAI and OpenAI-Compatible Models (`model/openaimodel`)

Built in since v2.1.0 and marked **experimental**. Uses the Responses API by default; v2.5.0 added the Chat Completions API for providers that only implement `/v1/chat/completions`.

```go
import (
    "github.com/openai/openai-go/v3/option"
    "google.golang.org/adk/v2/model/openaimodel"
)

// OpenAI, Responses API (default).
m, err := openaimodel.NewModel(ctx, "gpt-4o-mini", &openaimodel.ClientConfig{
    APIKey: os.Getenv("OPENAI_API_KEY"),
})

// OpenAI-compatible server that only speaks Chat Completions (vLLM, Ollama, LM Studio, ...).
local, err := openaimodel.NewModel(ctx, "llama3.1", &openaimodel.ClientConfig{
    APIKey:  "unused-but-non-empty", // Keep non-empty so OPENAI_API_KEY is not sent to BaseURL.
    BaseURL: "http://localhost:11434/v1",
    API:     openaimodel.APIChatCompletions,
})

// Extra headers go through openai-go request options.
withOrg, err := openaimodel.NewModel(ctx, "gpt-4o-mini", &openaimodel.ClientConfig{
    APIKey:  os.Getenv("OPENAI_API_KEY"),
    Options: []option.RequestOption{option.WithHeader("OpenAI-Organization", "org-123")},
})
```

```go
type ClientConfig struct {
    APIKey     string                 // Empty: falls back to OPENAI_API_KEY.
    BaseURL    string                 // Empty: falls back to OPENAI_BASE_URL.
    HTTPClient *http.Client
    Options    []option.RequestOption // openai-go escape hatch, applied last.
    API        API                    // APIResponses (zero value) or APIChatCompletions.
}
func NewModel(ctx context.Context, modelName string, cfg *ClientConfig) (model.LLM, error)
```

Limitations and gotchas:

- **Key leakage:** an empty `APIKey` with a custom `BaseURL` sends `OPENAI_API_KEY` to that provider. Always set a key (even a dummy one) for third-party endpoints.
- **Function tools are non-strict**; arguments are best-effort against the declared schema. Not configurable.
- **Structured output is always strict**: every object gets `additionalProperties: false` and **all** properties become required (optional output fields become required; map-typed fields become empty objects).
- **Text only:** images and other inline/file data fail with `openai: unsupported content part`.
- **Function tools only:** `geminitool.GoogleSearch{}` and other model-side tools fail with `openai: non-function tools are not supported`.
- **Reasoning is not replayed** across turns (thought parts from earlier turns are dropped). Have the model state conclusions in its answer.
- **Rejected config fields** (error naming the field): `TopK`, `CandidateCount > 1`, `SafetySettings`, `Labels`, `ResponseModalities`, `SpeechConfig`, `CachedContent`, and similar Gemini-only fields. `StopSequences`, penalties, and `Seed` work only with `APIChatCompletions`. `ThinkingConfig` maps to a reasoning effort.
- A bad finish that still produced an answer is reported in `LLMResponse.CustomMetadata[openaimodel.FinishMessageKey]`.
- `req.Model` set by a `BeforeModelCallback` overrides the constructor's model name.

Azure OpenAI uses openai-go's azure options: `Options: []option.RequestOption{azure.WithEndpoint(endpoint, apiVersion), azure.WithAPIKey(key)}` (import `github.com/openai/openai-go/v3/azure`). Azure key auth uses the `Api-Key` header, so a plain `BaseURL` + `APIKey` does not work.

## Apigee Proxy (`model/apigee`)

Routes Gemini traffic through an Apigee API proxy. **The model name must start with `apigee/`**, otherwise `NewModel` fails with `invalid model string`.

```go
import "google.golang.org/adk/v2/model/apigee"

m, err := apigee.NewModel(ctx, "apigee/gemini-2.5-flash",
    apigee.WithProxyURL("https://my-apigee-host/v1/gemini"), // Or env APIGEE_PROXY_URL.
    apigee.WithCustomHeaders(http.Header{"x-api-key": []string{os.Getenv("APIGEE_KEY")}}),
)
```

Accepted name forms: `apigee/<model>`, `apigee/gemini/<model>`, `apigee/vertex_ai/<model>`, and versioned variants such as `apigee/vertex_ai/v1/<model>`. The `apigee/vertex_ai/` prefix (or `GOOGLE_GENAI_USE_VERTEXAI=true`) selects Vertex AI and requires `GOOGLE_CLOUD_PROJECT` and `GOOGLE_CLOUD_LOCATION`. `WithHTTPClient` is documented as testing-only.

## Model Registry (`model.Register` / `model.NewLLM`)

A name-based registry (v2.1.0) for choosing a provider from configuration. **Registration is opt-in**: no provider package registers itself on import.

```go
import (
    "google.golang.org/adk/v2/model"
    "google.golang.org/adk/v2/model/gemini"
    "google.golang.org/adk/v2/model/openaimodel"
)

func init() {
    model.Register(`^(?i)gemini-`, func(ctx context.Context, name string) (model.LLM, error) {
        return gemini.NewModel(ctx, name, nil)
    })
    model.Register(`^(gpt-|o[0-9])`, func(ctx context.Context, name string) (model.LLM, error) {
        return openaimodel.NewModel(ctx, name, &openaimodel.ClientConfig{APIKey: os.Getenv("OPENAI_API_KEY")})
    })
}

// Later:
llm, err := model.NewLLM(ctx, os.Getenv("MODEL")) // e.g. "gemini-flash-latest" or "gpt-4o-mini"
```

- Patterns are Go regexps matched **unanchored**; anchor them with `^`/`$`.
- `NewLLM` requires **exactly one** matching pattern (zero or several matches are errors).
- `Register` panics on an invalid regexp or a duplicate pattern.

## Custom `model.LLM` Providers

For providers without a built-in package (Anthropic, Bedrock, etc.), implement the interface:

```go
package myprovider

import (
    "context"
    "iter"

    "google.golang.org/adk/v2/model"
    "google.golang.org/genai"
)

type MyModel struct {
    name string
}

func NewModel(name string) (model.LLM, error) {
    return &MyModel{name: name}, nil
}

func (m *MyModel) Name() string { return m.name }

func (m *MyModel) GenerateContent(ctx context.Context, req *model.LLMRequest, stream bool) iter.Seq2[*model.LLMResponse, error] {
    return func(yield func(*model.LLMResponse, error) bool) {
        // 1. Convert req.Contents ([]*genai.Content) to the provider's message format.
        // 2. Map req.Config (temperature, max tokens, response schema, ...).
        // 3. Convert function declarations in req.Config.Tools to the provider's tool format.
        // 4. Call the provider and convert the response back.
        yield(&model.LLMResponse{
            Content: &genai.Content{
                Role:  genai.RoleModel,
                Parts: []*genai.Part{genai.NewPartFromText("Hello!")},
            },
            TurnComplete: true,
        }, nil)
        // Streaming: yield chunks with Partial: true, then a final response with TurnComplete: true.
    }
}
```

| ADK type | Provider mapping |
|---|---|
| `req.Contents` | `[]*genai.Content` with text, `FunctionCall`, and `FunctionResponse` parts |
| `req.Config` | `Temperature`, `MaxOutputTokens`, `ResponseMIMEType`, `ResponseSchema`, `SystemInstruction`, `Tools` |
| Response content | `*genai.Content` (role `model`) with text and `genai.FunctionCall` parts |
| Usage | `UsageMetadata` (`*genai.GenerateContentResponseUsageMetadata`) feeds telemetry and compaction |
| Streaming | `Partial: true` for chunks, `TurnComplete: true` for the final response |

`model.LLMRequest` and `model.LLMResponse` have the same fields as in v1 (camelCase JSON tags since v2.2.0).

## MCP Toolset (`tool/mcptoolset`)

Connects agents to MCP servers using the official Go MCP SDK (`github.com/modelcontextprotocol/go-sdk`, v1.8.0 at ADK v2.5.0). Do **not** use the third-party `mark3labs/mcp-go`.

```go
import (
    "github.com/modelcontextprotocol/go-sdk/mcp"
    "google.golang.org/adk/v2/auth"
    "google.golang.org/adk/v2/tool/mcptoolset"
)

// Local subprocess (stdio).
fsTools, err := mcptoolset.New(mcptoolset.Config{
    Transport: &mcp.CommandTransport{
        Command: exec.Command("npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"),
    },
})

// Remote streamable HTTP server with a static bearer token. Credentialed
// clients must refuse redirects (see refuseRedirects below).
ghTools, err := mcptoolset.New(mcptoolset.Config{
    Transport: &mcp.StreamableClientTransport{
        Endpoint:   "https://api.githubcopilot.com/mcp/",
        HTTPClient: &http.Client{CheckRedirect: refuseRedirects}, // Kept when Auth wraps the client.
    },
    Auth: auth.StaticToken(os.Getenv("GITHUB_PAT")),
})

// Header API key, or Google Application Default Credentials.
keyed, err := mcptoolset.New(mcptoolset.Config{
    Transport: &mcp.StreamableClientTransport{
        Endpoint:   "https://mcp.example.com/mcp",
        HTTPClient: &http.Client{CheckRedirect: refuseRedirects},
    },
    Auth: auth.APIKey("X-Api-Key", os.Getenv("EXAMPLE_KEY")),
})
gcpTools, err := mcptoolset.New(mcptoolset.Config{
    Transport: &mcp.StreamableClientTransport{
        Endpoint:   "https://my-mcp.example.googleapis.com/mcp",
        HTTPClient: &http.Client{CheckRedirect: refuseRedirects},
    },
    Auth: auth.ADC(), // cloud-platform scope by default.
})

// Unauthenticated servers can use the Endpoint shorthand (a default client).
publicTools, err := mcptoolset.New(mcptoolset.Config{Endpoint: "https://mcp.example.com/public/mcp"})

agent, err := llmagent.New(llmagent.Config{
    Name:     "fs_agent",
    Model:    m,
    Toolsets: []tool.Toolset{fsTools},
})
```

**Never let a credentialed client follow redirects.** `auth.Transport` resolves and applies the credential on every request, including a redirect hop after `net/http` has stripped `Authorization`, so a redirecting endpoint would receive the token. `Config.Endpoint` builds a default `http.Client` that follows redirects; with `Auth`, pass a `StreamableClientTransport` whose `HTTPClient` refuses them:

```go
// refuseRedirects returns redirect responses to the caller instead of following them.
func refuseRedirects(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
```

In-memory transports (`mcp.NewInMemoryTransports()`) work for tests: connect an `mcp.NewServer` to the server end and pass the client end as `Transport`. The older `HTTPClient: oauth2.NewClient(ctx, ts)` pattern on `mcp.StreamableClientTransport` still works.

```go
type Config struct {
    Client                      *mcp.Client                // Optional custom MCP client.
    Transport                   mcp.Transport              // Stdio, streamable HTTP, in-memory, ...
    Endpoint                    string                     // v2.1.0+: used when Transport is nil.
    Auth                        auth.CredentialProvider    // v2.1.0+: per-request credentials; needs a streamable HTTP transport.
    ToolFilter                  tool.Predicate             // Deprecated: use tool.FilterToolset.
    RequireConfirmation         bool                       // HITL for every tool.
    RequireConfirmationProvider tool.ConfirmationProvider  // Dynamic HITL; takes precedence.
}
```

Behavior notes:

- At v2.5.0, a config with neither `Transport` nor `Endpoint` is **not** rejected by `New`; it fails later during tool discovery with a nil-pointer panic (under the runner, a run error such as `node "root" panicked: ...`). Validate your config.
- `Auth` with a non-HTTP transport fails at construction. Do not combine `Auth` with the transport's own `OAuthHandler`.
- Sessions are created lazily on the first LLM request and reconnect automatically on closed connections or missing sessions. Tool discovery paginates `ListTools`.
- **Tool calls are at-least-once.** When `CallTool` fails with a closed connection, missing session, or EOF, ADK reconnects and **resends the same call once**. If the server had already executed it before the connection dropped, a mutating tool (create record, send message, charge payment) runs twice while ADK reports one result (upstream issue #1689). Make mutating MCP tools idempotent (e.g. idempotency keys), or gate them behind confirmation.
- Results: `StructuredContent` is returned as `{"output": ...}`; otherwise text is returned as `{"output": "<text>"}`. Since v2.4.0, empty text is valid, and non-text content (images, audio, resource links) is rendered as bracketed labels instead of being dropped (binary payloads are not forwarded to the model).
- `IsError: true` results become a tool error: `Tool execution failed. Details: ...`.
- For HTTP servers with idle timeouts, the cached session can go stale; tune server timeouts or recreate the toolset on persistent connection errors.

### Filtering and Confirmation

```go
filtered := tool.FilterToolset(fsTools, tool.AllowedToolsPredicate([]string{"read_file", "list_directory"}))

confirmed, err := mcptoolset.New(mcptoolset.Config{
    Transport: transport,
    RequireConfirmationProvider: func(toolName string, args any) bool {
        return toolName == "delete_file" // Only confirm destructive tools.
    },
})

// Any toolset (experimental API): wrap with confirmation logic.
safe := tool.WithConfirmation(myToolset, false, func(toolName string, toolInput any) bool {
    return toolName == "delete_record"
})
```

`tool.StringPredicate` is deprecated in favor of `tool.AllowedToolsPredicate`. `tool.WithConfirmation` is still experimental; since v2.5.0 it also wraps streaming tools. When a tool needs confirmation, the agent emits a function call named `toolconfirmation.FunctionCallName` (`"adk_request_confirmation"`); `toolconfirmation.OriginalCallFrom(fc)` extracts the call awaiting approval. The caller replies in the next `Run` with a user-role `FunctionResponse` that has the **same ID** and name, and `Response: map[string]any{"confirmed": true, "payload": optionalPayload}`. Inside a tool, `ctx.ToolConfirmation()` reads the decision and `ctx.RequestConfirmation(hint, payload)` triggers the flow.

## Outbound Auth (`auth`, `auth/gcp`)

Credentials for outbound calls (MCP servers, A2A peers, any HTTP client). Core package since v2.1.0; `auth/gcp` REST client since v2.3.0; credential caching (`CredentialStore`) and the per-user `gcp.NewProvider` since v2.5.0.

```go
type Credential interface{ Apply(h http.Header) error }
type CredentialProvider interface{ Credential(ctx context.Context) (Credential, error) }

func StaticToken(token string) CredentialProvider             // Authorization: Bearer <token>
func APIKey(name, value string) CredentialProvider            // <name>: <value>
func TokenSourceProvider(ts oauth2.TokenSource) CredentialProvider
func ADC(scopes ...string) CredentialProvider                  // Default scope: cloud-platform.
func ServiceAccount(cfg ServiceAccountConfig) CredentialProvider // JSONKey + Scopes, or Audience for ID tokens.

type Transport struct {              // Applies a provider's credential per request.
    Provider CredentialProvider
    Base     http.RoundTripper       // nil = http.DefaultTransport
}

type ConsentRequiredError struct{ AuthURI, Nonce, Key string }
func NewInMemoryCredentialStore() *InMemoryCredentialStore
```

Wrap any HTTP client, and always refuse redirects on clients that carry credentials (`auth.Transport` re-applies the credential on every hop, including to another host):

```go
authed := &http.Client{
    Transport:     &auth.Transport{Provider: auth.ADC()},
    CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
}
```

**Per-user credentials (`auth/gcp`):** resolves end-user credentials from Google Cloud Agent Identity or IAM Connector credential services, keyed by the acting user from `agent.IdentityFromContext(ctx)`.

```go
import "google.golang.org/adk/v2/auth/gcp"

client, err := gcp.NewClient(ctx, nil) // Build ONE long-lived client; per-request clients defeat the cache.
perUser, err := gcp.NewProvider(ctx, gcp.ProviderConfig{
    Scheme: gcp.ProviderScheme{
        Name:   "projects/my-proj/locations/global/connectors/github",
        Scopes: []string{"repo"},
    },
    Client: client,
    Store:  auth.NewInMemoryCredentialStore(),
})
userTools, err := mcptoolset.New(mcptoolset.Config{
    Transport: &mcp.StreamableClientTransport{
        Endpoint:   "https://mcp.example.com/mcp",
        HTTPClient: &http.Client{CheckRedirect: refuseRedirects}, // Required by gcp.NewProvider.
    },
    Auth: perUser,
})
```

- The provider fails with `gcp.ErrNoActingUser` when the context carries no ADK identity. ADK does **not** authenticate `session.UserID`; trust comes from your server's authentication.
- Interactive consent is not wired into the tool layer at v2.5.0: a `*auth.ConsentRequiredError` surfaces as an ordinary tool error.
- An MCP session is bound to the user that opened it, so `mcptoolset` does not isolate per-user credentials across a shared connection.

## A2A Remote Agents (`agent/remoteagent/v2`)

```go
import remoteagent "google.golang.org/adk/v2/agent/remoteagent/v2"

remote, err := remoteagent.NewA2A(remoteagent.A2AConfig{
    Name:              "prime_agent",
    Description:       "Checks if numbers are prime.",
    AgentCardProvider: remoteagent.NewAgentCardProvider("https://prime.example.com"), // URL or file path.
})
```

- **Card origin pinning (v2.4.0+):** every interface URL in a fetched card must use `https` (or `http` on a loopback host) and share the origin (scheme, host, port) of the configured source URL; otherwise `ErrUntrustedCardInterface`. Static `AgentCard` values and file sources are not checked.
- `NewAgentCardProvider` accepts only `http(s)://` URLs or plain paths; other schemes return `ErrUnsupportedCardSource`.
- `AllowTransferToAgent` (default `false`) redacts a peer's `transfer_to_agent` request. Enable it only for trusted peers.
- `BeforeRequestCallbacks` / `AfterRequestCallbacks` take `agent.Context`. When the remote agent runs inside a graph node with an isolation scope, history is filtered to that scope.
- The v1 package `agent/remoteagent` (a2a-go v0) is deprecated; use `/v2`.

**Per-request auth at v2.5.0:** there is no `Auth` field on `A2AConfig` yet. Supply an authenticated client factory:

```go
import "github.com/a2aproject/a2a-go/v2/a2aclient"

hc := &http.Client{
    Transport:     &auth.Transport{Provider: auth.StaticToken(os.Getenv("REMOTE_TOKEN"))},
    CheckRedirect: refuseRedirects, // Never forward the token to a redirect target.
}
factory := a2aclient.NewFactory(a2aclient.WithJSONRPCTransport(hc), a2aclient.WithRESTTransport(hc))
remote, err := remoteagent.NewA2A(remoteagent.A2AConfig{
    Name:              "prime_agent",
    Description:       "Checks if numbers are prime.",
    AgentCardProvider: remoteagent.NewAgentCardProvider("https://prime.example.com"),
    ClientProvider:    remoteagent.NewA2AClientProvider(factory),
})
```

## Google Cloud Agent Registry (`agentregistry`)

A client for discovering A2A agents, MCP servers, and endpoints registered in Agent Registry (v2.1.0+), with factories that turn entries into ADK agents and toolsets. Needs `roles/agentregistry.viewer`.

```go
import "google.golang.org/adk/v2/agentregistry"

reg, err := agentregistry.New(ctx, agentregistry.Config{
    ProjectID: os.Getenv("GOOGLE_CLOUD_PROJECT"),
    Location:  "global",
}) // nil HTTPClient = ADC with mTLS endpoint selection.

for srv, err := range reg.AllMCPServers(ctx, agentregistry.WithPageSize(50)) {
    if err != nil {
        return err
    }
    if slices.ContainsFunc(srv.Tools, func(t agentregistry.Tool) bool { return t.Name == "list_log_names" }) {
        tools, err := reg.MCPToolset(ctx, srv.Name)
        // ...
    }
}

remote, err := reg.RemoteAgent(ctx, "projects/p/locations/global/agents/my-agent",
    agentregistry.WithA2AHTTPClient(&http.Client{
        Transport:     &auth.Transport{Provider: auth.ADC()},
        CheckRedirect: refuseRedirects,
    }))
```

- Discovery: `ListAgents`/`GetAgent`/`AllAgents`, `ListMCPServers`/`GetMCPServer`/`AllMCPServers`, `ListEndpoints`/`GetEndpoint`/`AllEndpoints`; options `WithFilter`, `WithPageSize`, `WithPageToken`. Non-2xx responses are `*agentregistry.APIError`.
- The registry is a catalog, not a proxy. `MCPToolset` reuses the registry's ADC client only for `*.googleapis.com` endpoints; `RemoteAgent` never authenticates unless you pass `WithA2AHTTPClient` or `WithA2AHeaders`.

## Service Backends

| Service | In-memory | Production |
|---|---|---|
| Sessions | `session.InMemoryService()` | `session/database.NewSessionService(dialector, opts...)` or `NewSessionServiceFromDB(*gorm.DB)` (v2.4.0+); `session/vertexai.NewSessionService(ctx, VertexAIServiceConfig{ProjectID, Location, ReasoningEngine})` |
| Memory | `memory.InMemoryService()` | `memory/vertexai.NewService(ctx, &ServiceConfig{...})` (Vertex AI Memory Bank) |
| Artifacts | `artifact.InMemoryService()` | `artifact/gcsartifact.NewService(ctx, bucketName, opts...)` |

```go
import (
    "github.com/glebarez/sqlite"
    "gorm.io/gorm"
    "google.golang.org/adk/v2/session/database"
)

db, err := gorm.Open(sqlite.Open("sessions.db"), &gorm.Config{})
sessions, err := database.NewSessionServiceFromDB(db)
if err := database.AutoMigrate(sessions); err != nil { // Run on EVERY startup.
    log.Fatal(err)
}
```

- **`database.AutoMigrate` must run on every startup.** The service never creates or alters tables; v2.0.0 added workflow columns and v2.5.0 added transcription columns, and `AppendEvent` fails until they exist.
- `Get` and `AppendEvent` of every bundled session service wrap `session.ErrNotFound` (v2.4.0); match with `errors.Is`. Custom services must wrap it too (the REST server maps it to 404).
- Custom session services must persist the v2 event fields (`IsolationScope`, `Routes`, `RequestedInput`, `Output`, `NodeInfo`, `Actions.Compaction`); `session/sessiontestsuite` checks the contract.
- `artifact.ArtifactVersion.CreateTime` is `time.Time` (was `float64` in v1). `CanonicalURI` is a stable identity (`gs://bucket/object` for GCS since v2.4.0), not a download URL. `gcsartifact.Save` can return `gcsartifact.ErrVersionConflict` under concurrent writers; retry it.

### BigQuery Agent Analytics Plugin

A separate Go module, `google.golang.org/adk/plugin/agentanalytics` (no `/v2`, no release tags; `go get` resolves a pseudo-version). It logs every lifecycle event to BigQuery through the Storage Write API.

```go
import (
    "google.golang.org/adk/plugin/agentanalytics"
    "google.golang.org/adk/v2/plugin"
)

cfg := agentanalytics.DefaultConfig() // Dataset "agent_analytics", table "events", batched writes.
cfg.ProjectID = "my-project"
p, err := agentanalytics.NewBigQueryAgentAnalyticsPluginWithConfig(ctx, cfg)
// runner.Config{PluginConfig: runner.PluginConfig{Plugins: []*plugin.Plugin{p}}}
```

A table the plugin creates is day-partitioned on `timestamp` (v2.5.0); existing tables are not altered.

## Key Dependencies

Versions pinned by ADK Go v2.5.0 (`go 1.26.6`):

```
google.golang.org/adk/v2                      v2.5.0
google.golang.org/genai                       v1.71.0
github.com/modelcontextprotocol/go-sdk        v1.8.0   (NOT mark3labs/mcp-go)
github.com/a2aproject/a2a-go/v2               v2.5.0   (remoteagent/v2, server/adka2a/v2)
github.com/a2aproject/a2a-go                  v0.3.15  (deprecated v1 A2A packages only)
github.com/openai/openai-go/v3                v3.64.0  (model/openaimodel)
github.com/google/jsonschema-go               v0.4.3   (functiontool and workflow schemas)
go.opentelemetry.io/otel                      v1.46.0  (otel/log v0.22.0)
```
