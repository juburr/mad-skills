# Serving and Deployment

Launchers, command-line flags, the REST server's security model, embedding the REST and A2A servers in your own HTTP service, authentication, triggers, Agent Engine, and the `adkgo` deploy CLI. Verified against `google.golang.org/adk/v2` v2.5.0.

## Launcher Packages

| Package | Constructor | Serves |
|---|---|---|
| `cmd/launcher/full` | `full.NewLauncher()` | `console` (default) or `web` with `api`, `webui`, `a2a`, `pubsub`, `eventarc` |
| `cmd/launcher/prod` | `prod.NewLauncher()` | `web` with `api` and `a2a` only (no console, no web UI, no triggers) |
| `cmd/launcher/universal` | `universal.NewLauncher(subs...)` | Router over sublaunchers; the first is the default |
| `cmd/launcher/console` | `console.NewLauncher()` | Terminal chat; prompts for HITL confirmations and request-input pauses |
| `cmd/launcher/web` | `web.NewLauncher(subs...)` | HTTP server hosting web sublaunchers |
| `cmd/launcher/web/{api,webui,a2a}` | `api.NewLauncher()`, `webui.NewLauncher()`, `a2a.NewLauncher()` | REST API, dev web UI at `/ui/`, A2A JSON-RPC |
| `cmd/launcher/web/triggers/{pubsub,eventarc}` | `pubsub.NewLauncher()`, `eventarc.NewLauncher()` | `POST {prefix}/apps/{app_name}/trigger/{pubsub,eventarc}` |
| `cmd/launcher/agentengine` | `agentengine.NewLauncher(agentEngineID)` | Vertex AI Agent Engine endpoints (used by `adkgo deploy agentengine`) |

When composing a custom `web.NewLauncher(...)`, pass `webui` **before** `api`; with `api -path_prefix ""` the API's catch-all would otherwise shadow `/ui/`.

```go
config := &launcher.Config{
    AgentLoader:     agent.NewMultiLoader(rootAgent, otherAgent), // or agent.NewSingleLoader(rootAgent)
    SessionService:  sessionService,
    ArtifactService: artifactService,
    MemoryService:   memoryService,
}
l := prod.NewLauncher()
if err := l.Execute(ctx, config, os.Args[1:]); err != nil {
    log.Fatalf("Run failed: %v\n\n%s", err, l.CommandLineSyntax())
}
```

### launcher.Config

```go
type Config struct {
    SessionService   session.Service
    ArtifactService  artifact.Service
    MemoryService    memory.Service
    AgentLoader      agent.Loader
    A2AOptions       []a2asrv.RequestHandlerOption // a2a-go/v2
    PluginConfig     runner.PluginConfig
    TelemetryOptions []telemetry.Option

    Authenticator  authn.Authenticator // v2.4.0. nil = authn.NewNoop(). REST API routes only.
    Authorizer     authz.Authorizer    // v2.4.0. nil = authz.NewNoop().
    Compaction     *compaction.Config  // v2.3.0. Process-wide; shared by every app.
    BindHost       string              // v2.5.0. Set by the web launcher from -host.
    MaxPayloadSize int64               // v2.5.0. <= 0 = 10 MiB; -max_request_body_size overrides.
}
func (c *Config) Validate() error // v2.3.0. Validates Compaction.
```

The web launcher fills nil session, artifact, and memory services with in-memory ones (logged), so data disappears on restart. `runner.New` and `adkrest.NewServer` do not default them.

## Command-Line Syntax

`full` and `universal` pick a mode from the first argument (`console` when absent). `web` parses its own flags, then each sublauncher keyword consumes the flags that follow it, up to the next keyword. **A flag must follow its own keyword**: `web api -port 8001` fails because `-port` belongs to `web`. Each keyword may appear once.

| Keyword | Flags (default) |
|---|---|
| `console` | `-streaming_mode` (`none` or `sse`), `-shutdown-timeout` (2s), `-otel_to_cloud` |
| `web` | `-host` (`127.0.0.1`, v2.5.0), `-port` (8080), `-read-timeout` (15s), `-write-timeout` (15s), `-idle-timeout` (1m), `-shutdown-timeout` (15s), `-otel_to_cloud`, `-h2c` (cleartext HTTP/2), `-max_request_body_size` (0 = 10 MiB, v2.5.0) |
| `api` | `-webui_address` (`localhost:8080`), `-path_prefix` (`/api`), `-sse-write-timeout` (2m), `-trace_capacity` (10000), `-include_debug_api` (v2.3.0) |
| `webui` | `-api_server_address` (`http://localhost:8080/api`): the REST URL as seen from the browser |
| `a2a` | `-a2a_agent_url` (`http://localhost:8080`): base URL advertised in the agent card |
| `pubsub`, `eventarc` | `-path_prefix` (`/api`), `-trigger_max_retries` (3), `-trigger_base_delay` (1s), `-trigger_max_delay` (10s), `-trigger_max_concurrent_runs` (100) |
| `agentengine` | `-path_prefix` (`/api`), `-max_payload_size` (10485760), `-sse-write-timeout` (2m) |

There are no CLI flags for authentication, compaction, or extra CORS origins; configure those in code.

```bash
go run .                                          # Console (same as: go run . console)
go run . console -streaming_mode sse
go run . web api webui                            # Dev UI: open http://localhost:8080/ui/ (not 127.0.0.1)
go run . web api -include_debug_api webui         # Enables the UI's Traces and agent-graph panels
go run . web -port 9000 api webui -api_server_address http://localhost:9000/api
go run . web -port 8001 api a2a -a2a_agent_url http://localhost:8001

# Container or VM: listen on all interfaces and advertise the public origin.
/app/server web -host 0.0.0.0 -port 8080 \
    api -webui_address https://agent.example.com \
    a2a -a2a_agent_url https://agent.example.com
```

**A2A URL rule:** `-a2a_agent_url` must share the origin (scheme, host, port) of the URL clients fetch the card from, and must be `https` unless the host is loopback. Otherwise `remoteagent/v2` clients reject the card with `ErrUntrustedCardInterface`. Keep `-port` and `-a2a_agent_url` in sync.

## Security Model (v2.5.0 Defaults)

| Behavior | Since | Notes |
|---|---|---|
| Bind `127.0.0.1` by default | v2.5.0 | v1.x and v2.0-v2.4 bound all interfaces. Containers **must** pass `web -host 0.0.0.0`. |
| Origin check on every REST request and the `/run_live` WebSocket | v2.5.0 | Allowed: no `Origin` (non-browser clients), same origin, or the `-webui_address` origin. Others get `403 origin not allowed`. |
| Host check (DNS-rebinding defense) | v2.5.0 | Armed only for a loopback bind. A `Host` that is neither loopback nor an allowed origin gets `403 host not allowed`. A same-machine reverse proxy needs its origin in `-webui_address`. |
| `-webui_address '*'` | v2.5.0 | Disables both checks. |
| 10 MiB request body limit on every route | v2.5.0 | HTTP 400 when exceeded. Override with `-max_request_body_size` or `MaxPayloadSize`. `/run_live` messages are capped at 16 MiB. |
| Debug trace routes opt-in | v2.3.0 | `api -include_debug_api`. Agent-graph routes joined the gate in v2.5.0. Never enable in production. |
| `GET/HEAD /health` and `/api/health`, `GET /api/version` | v2.3.0-v2.4.0 | Public even with an authenticator; liveness only. |
| REST authentication and authorization | v2.4.0 | Code-only via `Authenticator`/`Authorizer`. |

Origin and Host checks do **not** protect a server reachable over a network. A server bound to a routable interface needs an `Authenticator`. The launcher applies `Authenticator`/`Authorizer` to the **REST API only**: A2A routes, Pub/Sub and Eventarc trigger routes, Agent Engine routes, and web UI assets stay unauthenticated unless you wrap them yourself.

## Embedding the REST API (`server/adkrest`)

```go
import (
    "google.golang.org/adk/v2/server/adkrest"
    "google.golang.org/adk/v2/server/authn"
    "google.golang.org/adk/v2/server/authz"
)

restServer, err := adkrest.NewServer(adkrest.ServerConfig{
    AgentLoader:     agent.NewSingleLoader(rootAgent),
    SessionService:  sessionService,             // Set all three services; adkrest does not default them.
    ArtifactService: artifact.InMemoryService(),
    MemoryService:   memory.InMemoryService(),
    SSEWriteTimeout: 2 * time.Minute,
    Authenticator: authn.NewCustom(func(r *http.Request) (*authn.Caller, error) {
        token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
        if !ok {
            return nil, authn.ErrUnauthenticated // 401
        }
        sub, err := verifyJWT(token)
        if err != nil {
            return nil, fmt.Errorf("%w: %w", authn.ErrUnauthenticated, err)
        }
        return &authn.Caller{UserID: sub}, nil
    }),
    Authorizer:     authz.NewStrict(),                   // Caller.UserID must match {user_id}; else 403.
    AllowedOrigins: []string{"https://app.example.com"}, // Browser origins; "*" disables the guard.
    MaxPayloadSize: 20 << 20,
})
if err != nil {
    log.Fatal(err)
}
mux := http.NewServeMux()
mux.Handle("/api/", http.StripPrefix("/api", restServer))
```

```go
type ServerConfig struct {
    SessionService  session.Service
    MemoryService   memory.Service
    AgentLoader     agent.Loader
    ArtifactService artifact.Service
    SSEWriteTimeout time.Duration
    PluginConfig    runner.PluginConfig
    DebugConfig     DebugTelemetryConfig // {TraceCapacity int}
    DebugAPIConfig  DebugAPIConfig       // {IncludeDebugAPI bool}  v2.3.0
    Authenticator   authn.Authenticator  // v2.4.0
    Authorizer      authz.Authorizer     // v2.4.0
    AllowedOrigins  []string             // v2.5.0
    BindHost        string               // v2.5.0: a loopback value arms the Host check.
    Compaction      *compaction.Config   // v2.3.0
    MaxPayloadSize  int64                // v2.5.0
}
```

- `adkrest.Server` does not add CORS headers (the `api` sublauncher does). Embedders serving browsers on another origin must add CORS headers **and** list the origin in `AllowedOrigins`.
- The authenticated caller reaches agents and tools: `authn.CallerFromContext(ctx)` and `agent.IdentityFromContext(ctx)` both work inside an agent run.
- Routes (relative to the mount): `/list-apps`; `/apps/{app}/users/{user}/sessions[/{session}]` (sessions and `.../artifacts`); `POST /run`, `POST /run_sse`; `GET /run_live` (WebSocket); `/health`; `/version`; developer routes under `/dev/apps/{app}/...`.

### Authentication and Authorization (`server/authn`, `server/authz`)

```go
type Caller struct {
    UserID string
    Claims map[string]any
}
type Authenticator interface{ Authenticate(r *http.Request) (*Caller, error) }

var ErrUnauthenticated error // 401
var ErrForbidden error       // 403 (v2.5.0); any other error is 500.

func NewNoop() Authenticator                          // Default: empty Caller for everyone.
func NewHeader(name string) Authenticator             // UserID from one trusted upstream header.
func NewCustom(fn AuthenticatorFunc) Authenticator
func NewIdentityAwareProxy() Authenticator            // Google IAP headers.
func NewGoogleOIDC(cfg GoogleOIDCConfig) (Authenticator, error) // v2.5.0: Google-signed ID tokens.
func Middleware(a Authenticator) func(http.Handler) http.Handler
func CallerFromContext(ctx context.Context) (*Caller, bool)

// package authz
type Authorizer interface{ CanActAsUser(ctx context.Context, userID string) error }
func NewNoop() Authorizer   // Default: anyone may act as any user.
func NewStrict() Authorizer // Caller.UserID must equal the requested user ID.
```

- `NewStrict` without an authenticator denies everything (Noop yields an empty `UserID`).
- `NewGoogleOIDC` requires `Audience` and a non-empty `AllowedServiceAccounts`; it verifies issuer, `email_verified`, and the allow-list. It targets Pub/Sub push and Eventarc OIDC tokens.

Protect trigger routes yourself (the trigger handlers read gorilla/mux route variables):

```go
import (
    "github.com/gorilla/mux"
    "google.golang.org/adk/v2/server/adkrest/controllers/triggers"
)

ctrl, err := triggers.NewPubSubControllerWithConfig(triggers.ControllerConfig{
    SessionService:  sessionService,
    AgentLoader:     loader,
    MemoryService:   memoryService,
    ArtifactService: artifactService,
    TriggerConfig: triggers.TriggerConfig{
        MaxRetries: 3, BaseDelay: time.Second, MaxDelay: 10 * time.Second, MaxConcurrentRuns: 100,
    },
})
oidc, err := authn.NewGoogleOIDC(authn.GoogleOIDCConfig{
    Audience:               "https://my-agent-abc123.a.run.app",
    AllowedServiceAccounts: []string{"pubsub-invoker@my-proj.iam.gserviceaccount.com"},
})
r := mux.NewRouter()
r.Handle("/apps/{app_name}/trigger/pubsub",
    authn.Middleware(oidc)(http.HandlerFunc(ctrl.PubSubTriggerHandler))).Methods(http.MethodPost)
```

Each trigger delivery gets its own session.

## Embedding an A2A Server (`server/adka2a/v2`)

```go
import (
    "github.com/a2aproject/a2a-go/v2/a2a"
    "github.com/a2aproject/a2a-go/v2/a2asrv"
    "google.golang.org/adk/v2/server/adka2a/v2"
)

executor := adka2a.NewExecutor(adka2a.ExecutorConfig{
    RunnerConfig: runner.Config{
        AppName:        rootAgent.Name(),
        Agent:          rootAgent,
        SessionService: session.InMemoryService(),
    },
})
card := &a2a.AgentCard{
    Name:        rootAgent.Name(),
    Description: rootAgent.Description(),
    SupportedInterfaces: []*a2a.AgentInterface{
        a2a.NewAgentInterface("https://agent.example.com/invoke", a2a.TransportProtocolJSONRPC),
    },
    Version:            "1.0.0",
    DefaultInputModes:  []string{"text/plain"},
    DefaultOutputModes: []string{"text/plain"},
    Skills:             adka2a.BuildAgentSkills(rootAgent),
    Capabilities:       a2a.AgentCapabilities{Streaming: true},
}
mux := http.NewServeMux()
mux.Handle(a2asrv.WellKnownAgentCardPath, a2asrv.NewStaticAgentCardHandler(card)) // /.well-known/agent-card.json
mux.Handle("/invoke", a2asrv.NewJSONRPCHandler(a2asrv.NewHandler(executor)))
```

- The executor marks emitted tasks with the ADK A2A extension (`adka2a.ADKExtensionURI`) so ADK clients in other languages read long-running calls correctly.
- `adka2a.TransferToAgentFromMeta(meta)` recovers a peer's transfer request when you opt into it.
- The plain `server/adka2a` package (a2a-go v0) is deprecated.

## Agent Engine

- Entry point: `cmd/launcher/agentengine.NewLauncher(agentEngineID)`, or include the `agentengine` web sublauncher. The `examples/agentengine` program reads `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_AGENT_ENGINE_LOCATION`, and `GOOGLE_CLOUD_AGENT_ENGINE_ID` and uses `session/vertexai` plus `memory/vertexai`.
- Embedding: `server/agentengine.NewHandler(config *launcher.Config, sseWriteTimeout time.Duration, maxPayloadSize int64, agentEngineID string) (http.Handler, error)`.

## `adkgo` Deploy CLI

```bash
go install google.golang.org/adk/v2/cmd/adkgo@v2.5.0

adkgo deploy cloudrun -p my-project -r us-central1 -s my-agent -e ./main.go
adkgo deploy agentengine -p my-project -r us-central1 -s "My Agent" -e ./main.go
```

| Command | Key flags |
|---|---|
| `deploy cloudrun` | `-p/--project_name`, `-r/--region`, `-s/--service_name`, `-e/--entry_point_path`, `--server_port` (8080), `--proxy_port` (8081), `--api`, `--debug_api` (v2.3.0+), `--webui`, `--a2a`, `-a/--a2a_agent_url`, `--pubsub*`, `--eventarc*` |
| `deploy agentengine` | `-p/--project_name`, `-r/--region`, `-s/--name`, `-e/--entry_point_path`, `-d/--source_dir`, `--agent_engine_id` (update an existing instance), `--mem_deploy`, `--mem_model`, `--mem_ttl` |

- `cloudrun` builds a static linux/amd64 binary into a distroless image whose command runs `web -host 0.0.0.0 ...`, deploys with `--no-allow-unauthenticated`, injects a Secret Manager secret named `GOOGLE_API_KEY`, and starts `gcloud run services proxy` so the UI is at `http://127.0.0.1:8081/ui/`.
- `agentengine` builds from source with `FROM golang:<go.mod version>` and `GOTOOLCHAIN=auto`; the entry point must serve the `agentengine` sublauncher.

## Context Compaction on Serving Surfaces

Set `launcher.Config.Compaction` (process-wide) or the `Compaction` field on `adkrest.ServerConfig`, `runner.Config`, or `triggers.ControllerConfig`. Configs are validated at startup against the root agent: a config without a `Summarizer` requires an LLM root agent (its model becomes the default summarizer). On trigger surfaces each delivery is a new session, so only tail retention (`TokenThreshold` + `EventRetentionSize`) helps.

## Telemetry in Launchers

`console` and `web` **always** initialize OpenTelemetry providers (from `launcher.Config.TelemetryOptions`) and replace the global providers; `-otel_to_cloud` only adds export to Google Cloud. Pass custom exporters through `TelemetryOptions` rather than setting globals before `Execute`. Since v2.4.0, telemetry is initialized before the HTTP server starts.
