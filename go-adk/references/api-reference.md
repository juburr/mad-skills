# API Reference

Complete type reference for ADK Go. Verified against `google.golang.org/adk` v1.4.0.

## Core Interfaces

### agent.Agent

```go
type Agent interface {
    Name() string
    Description() string
    Run(InvocationContext) iter.Seq2[*session.Event, error]
    SubAgents() []Agent
    FindAgent(name string) Agent     // Recursive lookup by name (v1.1.0+).
    FindSubAgent(name string) Agent

    // Has an unexported method: user code CANNOT implement this interface.
    // Always construct agents via agent.New, llmagent.New, or workflow constructors.
}
```

### model.LLM

```go
type LLM interface {
    Name() string
    GenerateContent(ctx context.Context, req *LLMRequest, stream bool) iter.Seq2[*LLMResponse, error]
}
```

### tool.Tool

```go
type Tool interface {
    Name() string
    Description() string
    IsLongRunning() bool
}
```

### tool.Toolset

```go
type Toolset interface {
    Name() string
    Tools(ctx agent.ReadonlyContext) ([]Tool, error)
}
```

## agent.Config

Used with `agent.New()` for custom agents.

```go
type Config struct {
    Name                 string
    Description          string
    SubAgents            []Agent
    BeforeAgentCallbacks []BeforeAgentCallback
    AfterAgentCallbacks  []AfterAgentCallback
    Run                  func(InvocationContext) iter.Seq2[*session.Event, error]
}
```

## llmagent.Config

All fields for `llmagent.New()`.

```go
type Config struct {
    // Identity
    Name        string          // Required. Unique in agent tree. Cannot be "user".
    Description string          // Used by parent agents for delegation routing.

    // Model
    Model                   model.LLM
    GenerateContentConfig   *genai.GenerateContentConfig

    // Instructions
    Instruction               string               // Supports {state_key} substitution.
    InstructionProvider       InstructionProvider   // Dynamic instruction generation.
    GlobalInstruction         string               // Prepended to all sub-agent instructions.
    GlobalInstructionProvider InstructionProvider

    // Sub-Agents
    SubAgents                []agent.Agent
    DisallowTransferToParent bool     // Prevent delegating back to parent.
    DisallowTransferToPeers  bool     // Prevent delegating to siblings.

    // Tools
    Tools                []tool.Tool
    Toolsets              []tool.Toolset

    // Schema
    InputSchema  *genai.Schema    // Structured input validation.
    OutputSchema *genai.Schema    // Structured output. Note: disables tool use.

    // Output
    OutputKey       string           // Stores final response in state[OutputKey].
    IncludeContents IncludeContents  // "none" or "default".

    // Agent Callbacks
    BeforeAgentCallbacks []agent.BeforeAgentCallback
    AfterAgentCallbacks  []agent.AfterAgentCallback

    // Model Callbacks
    BeforeModelCallbacks  []BeforeModelCallback
    AfterModelCallbacks   []AfterModelCallback
    OnModelErrorCallbacks []OnModelErrorCallback

    // Tool Callbacks
    BeforeToolCallbacks  []BeforeToolCallback
    AfterToolCallbacks   []AfterToolCallback
    OnToolErrorCallbacks []OnToolErrorCallback
}
```

### InstructionProvider

```go
type InstructionProvider func(ctx agent.ReadonlyContext) (string, error)
```

## Callback Signatures

### Agent Callbacks

```go
// Return non-nil *genai.Content to skip agent execution.
type BeforeAgentCallback func(CallbackContext) (*genai.Content, error)

// Called after agent completes.
type AfterAgentCallback func(CallbackContext) (*genai.Content, error)
```

### Model Callbacks

```go
// Return non-nil *model.LLMResponse to skip the actual model call.
type BeforeModelCallback func(
    ctx agent.CallbackContext,
    llmRequest *model.LLMRequest,
) (*model.LLMResponse, error)

// Called after LLM response. Can modify the response.
type AfterModelCallback func(
    ctx agent.CallbackContext,
    llmResponse *model.LLMResponse,
    llmResponseError error,
) (*model.LLMResponse, error)

// Called when the model returns an error.
type OnModelErrorCallback func(
    ctx agent.CallbackContext,
    llmRequest *model.LLMRequest,
    llmResponseError error,
) (*model.LLMResponse, error)
```

### Tool Callbacks

```go
// Return modified args or error. Non-nil result map skips tool execution.
type BeforeToolCallback func(
    ctx tool.Context,
    tool tool.Tool,
    args map[string]any,
) (map[string]any, error)

// Can modify or replace the tool result.
type AfterToolCallback func(
    ctx tool.Context,
    tool tool.Tool,
    args map[string]any,
    result map[string]any,
    err error,
) (map[string]any, error)

// Called when tool execution errors.
type OnToolErrorCallback func(
    ctx tool.Context,
    tool tool.Tool,
    args map[string]any,
    err error,
) (map[string]any, error)
```

## Context Interfaces

### agent.ReadonlyContext

```go
type ReadonlyContext interface {
    context.Context
    UserContent() *genai.Content
    InvocationID() string
    AgentName() string
    ReadonlyState() session.ReadonlyState
    UserID() string
    AppName() string
    SessionID() string
    Branch() string
}
```

### agent.CallbackContext

```go
type CallbackContext interface {
    ReadonlyContext
    Artifacts() Artifacts
    State() session.State
}
```

### agent.InvocationContext

```go
type InvocationContext interface {
    context.Context
    Agent() Agent
    Artifacts() Artifacts
    Memory() Memory
    Session() session.Session
    InvocationID() string
    Branch() string
    UserContent() *genai.Content
    RunConfig() *RunConfig
    EndInvocation()
    Ended() bool
    WithContext(context.Context) InvocationContext
}
```

### agent.ToolContext (alias: tool.Context)

```go
type ToolContext interface {
    CallbackContext
    FunctionCallID() string
    Actions() *session.EventActions
    SearchMemory(ctx context.Context, query string) (*memory.SearchResponse, error)
    ToolConfirmation() *toolconfirmation.ToolConfirmation
    RequestConfirmation(hint string, payload any) error
}
```

Since v1.4.0, `tool.Context` is a deprecated type alias (`type Context = agent.ToolContext`); existing code compiles unchanged, but `agent.ToolContext` is the canonical name. Constructors for tests/embedding: `agent.NewToolContext`, `agent.NewCallbackContext`.

## session.Event

```go
type Event struct {
    model.LLMResponse                     // Embedded: Content, metadata, etc.
    ID               string
    Timestamp        time.Time
    InvocationID     string
    Branch           string               // "agent1.agent2.agent3" hierarchy path
    Author           string               // "user" or agent name
    Actions          EventActions
    LongRunningToolIDs []string
}

func NewEvent(invocationID string) *Event
func (e *Event) IsFinalResponse() bool
```

### session.Events

```go
type Events interface {
    All() iter.Seq[*Event]
    Len() int
    At(i int) *Event
}
```

### session.EventActions

```go
type EventActions struct {
    StateDelta                 map[string]any
    ArtifactDelta              map[string]int64
    RequestedToolConfirmations map[string]toolconfirmation.ToolConfirmation
    SkipSummarization          bool
    TransferToAgent            string    // Target agent name for delegation.
    Escalate                   bool      // Exit loop / escalate to parent.
}
```

## model.LLMRequest / LLMResponse

```go
type LLMRequest struct {
    Model    string
    Contents []*genai.Content
    Config   *genai.GenerateContentConfig
    Tools    map[string]any `json:"-"`
}

type LLMResponse struct {
    Content             *genai.Content
    CitationMetadata    *genai.CitationMetadata
    GroundingMetadata   *genai.GroundingMetadata
    UsageMetadata       *genai.GenerateContentResponseUsageMetadata
    CustomMetadata      map[string]any
    LogprobsResult      *genai.LogprobsResult
    InputTranscription  *genai.Transcription   // Live sessions (v1.3.0+).
    OutputTranscription *genai.Transcription   // Live sessions (v1.3.0+).
    ModelVersion        string
    Partial             bool             // Streaming: incomplete chunk.
    TurnComplete        bool             // Streaming: response fully complete.
    Interrupted         bool
    SessionResumptionHandle string       // Live sessions (v1.3.0+).
    ErrorCode           string
    ErrorMessage        string
    FinishReason        genai.FinishReason
    AvgLogprobs         float64
}
```

## session.State

```go
type State interface {
    Get(string) (any, error)
    Set(string, any) error
    All() iter.Seq2[string, any]
}

type ReadonlyState interface {
    Get(string) (any, error)
    All() iter.Seq2[string, any]
}
```

## session.Service

```go
type Service interface {
    Create(context.Context, *CreateRequest) (*CreateResponse, error)
    Get(context.Context, *GetRequest) (*GetResponse, error)
    List(context.Context, *ListRequest) (*ListResponse, error)
    Delete(context.Context, *DeleteRequest) error
    AppendEvent(context.Context, Session, *Event) error
}

func InMemoryService() Service

type GetRequest struct {
    AppName   string
    UserID    string
    SessionID string
    NumRecentEvents int        // Optional: at most N most recent events.
    After           time.Time  // Optional: events with timestamp >= After.
}
```

Database-backed: `google.golang.org/adk/session/database`
Vertex AI-backed: `google.golang.org/adk/session/vertexai`

## runner.Config and Runner

```go
type Config struct {
    AppName           string
    Agent             agent.Agent
    SessionService    session.Service
    ArtifactService   artifact.Service    // Optional.
    MemoryService     memory.Service      // Optional.
    PluginConfig      PluginConfig
    AutoCreateSession bool                // v1.0.0+: Run creates the session if ID not found.
}

type PluginConfig struct {
    Plugins      []*plugin.Plugin
    CloseTimeout time.Duration
}

func New(cfg Config) (*Runner, error)

// Run executes one turn. opts is v1.0.0+; existing call sites compile unchanged.
func (r *Runner) Run(ctx context.Context, userID, sessionID string, msg *genai.Content,
    cfg agent.RunConfig, opts ...RunOption) iter.Seq2[*session.Event, error]

// RunLive opens a bidirectional (live) session. v1.3.0+.
func (r *Runner) RunLive(ctx context.Context, userID, sessionID string,
    cfg agent.LiveRunConfig, opts ...RunOption) (agent.LiveSession, iter.Seq2[*session.Event, error], error)

type RunOption func(*runOptions)
func WithStateDelta(delta map[string]any) RunOption  // Inject state before the run.
```

## agent.RunConfig

```go
type RunConfig struct {
    StreamingMode             StreamingMode
    SaveInputBlobsAsArtifacts bool
}

type StreamingMode string
const (
    StreamingModeNone StreamingMode = "none"
    StreamingModeSSE  StreamingMode = "sse"
)
```

## Live Sessions (v1.3.0+)

Used with `Runner.RunLive` and live-capable Gemini models.

```go
type LiveSession interface {     // agent.LiveSession
    Send(req LiveRequest) error
    Close() error
}

type LiveRequest struct {
    // RealtimeInput can be *genai.Blob, *genai.ActivityStart, or *genai.ActivityEnd.
    RealtimeInput any
    // Content is standard text/multimodal user content, or a FunctionResponse reply.
    Content *genai.Content
}

type LiveRunConfig struct {
    ResponseModalities       []genai.Modality
    SpeechConfig             *genai.SpeechConfig
    InputAudioTranscription  *genai.AudioTranscriptionConfig
    OutputAudioTranscription *genai.AudioTranscriptionConfig
    RealtimeInputConfig      *genai.RealtimeInputConfig
    EnableAffectiveDialog    bool
    Proactivity              *genai.ProactivityConfig
    SessionResumption        *genai.SessionResumptionConfig
    SaveLiveBlob             bool    // Save audio blobs as artifacts.
    MaxLLMCalls              int
}
```

## functiontool

```go
type Config struct {
    Name                        string
    Description                 string
    InputSchema                 *jsonschema.Schema  // Auto-inferred if nil.
    OutputSchema                *jsonschema.Schema  // Auto-inferred if nil.
    IsLongRunning               bool
    RequireConfirmation         bool                // Static HITL flag.
    RequireConfirmationProvider any                 // func(toolInput T) bool
}

type Func[TArgs, TResults any] func(tool.Context, TArgs) (TResults, error)
func New[TArgs, TResults any](cfg Config, handler Func[TArgs, TResults]) (tool.Tool, error)

// Streaming tools (live sessions, v1.3.0+): each yielded string is streamed
// to the model as an intermediate function result.
type StreamingFunc[TArgs any] func(tool.Context, TArgs) iter.Seq2[string, error]
func NewStreaming[TArgs any](cfg Config, handler StreamingFunc[TArgs]) (tool.Tool, error)
```

`TArgs` must be a struct or map (or pointer to one); primitives are rejected.

## agenttool.Config

```go
func New(agent agent.Agent, cfg *Config) tool.Tool

type Config struct {
    SkipSummarization bool    // Skip summarization after sub-agent finishes.
}
```

Pass `nil` for `cfg` to use defaults (`SkipSummarization: false`).

## tool.WithConfirmation (experimental)

```go
type ConfirmationProvider func(toolName string, toolInput any) bool

func WithConfirmation(toolset Toolset, requireConfirmation bool, provider ConfirmationProvider) Toolset
```

Wraps a `Toolset` so every tool checks HITL confirmation before executing. If `provider` is non-nil, it takes precedence over the static `requireConfirmation` flag. Still marked experimental at v1.4.0 (excluded from the v1.0 API stability guarantee). See `integrations.md` for usage examples.

## tool.Predicate and FilterToolset

```go
type Predicate func(ctx agent.ReadonlyContext, tool Tool) bool

// Create a predicate from a string slice of allowed tool names.
func StringPredicate(allowedTools []string) Predicate

// Wrap a Toolset to only expose tools matching the predicate.
func FilterToolset(toolset Toolset, predicate Predicate) Toolset
```

## genai.GenerateContentConfig (Key Fields)

```go
type GenerateContentConfig struct {
    SystemInstruction  *Content          // System-level instructions.
    Temperature        *float32          // 0.0 = deterministic.
    TopP               *float32          // Nucleus sampling.
    TopK               *float32          // Top-K sampling.
    MaxOutputTokens    int32
    StopSequences      []string
    ResponseMIMEType   string            // "text/plain" or "application/json".
    ResponseSchema     *Schema           // Structured output schema.
    SafetySettings     []*SafetySetting
    ThinkingConfig     *ThinkingConfig
    Seed               *int32            // Reproducibility.
    CandidateCount     int32
    PresencePenalty    *float32
    FrequencyPenalty   *float32
}
```

Use `genai.Ptr[float32](0.7)` to set pointer fields like `Temperature`.

When using ADK, prefer `llmagent.Config.Instruction` over `GenerateContentConfig.SystemInstruction` — ADK manages system instructions through the `Instruction` field.

## Workflow Agent Configs

### sequentialagent.Config

```go
type Config struct {
    AgentConfig agent.Config    // Name + SubAgents required.
}
```

### parallelagent.Config

```go
type Config struct {
    AgentConfig agent.Config    // Name + SubAgents required.
}
```

### loopagent.Config

```go
type Config struct {
    MaxIterations uint          // 0 = indefinite (until Escalate).
    AgentConfig   agent.Config  // Name + SubAgents required.
}
```

## remoteagent/v2 A2AConfig

The canonical remote-agent package is `agent/remoteagent/v2` (a2a-go v2 types). The v1 `agent/remoteagent` package (with `AgentCardSource`/`CardResolveOptions`/`ClientFactory` fields) is deprecated.

```go
// import remoteagent "google.golang.org/adk/agent/remoteagent/v2"

func NewA2A(cfg A2AConfig) (agent.Agent, error)

// Resolves a card from an http(s) URL or a local file path.
func NewAgentCardProvider(source string, opts ...agentcard.ResolveOption) AgentCardProvider
type AgentCardProvider func(ctx context.Context) (*a2a.AgentCard, error)

type A2AConfig struct {
    Name        string
    Description string

    AgentCard         *a2a.AgentCard     // Static card. Either this OR:
    AgentCardProvider AgentCardProvider  // Resolved on each invocation.

    BeforeAgentCallbacks   []agent.BeforeAgentCallback
    BeforeRequestCallbacks []BeforeA2ARequestCallback
    Converter              A2AEventConverter         // Default: adka2a.ToSessionEvent.
    AfterRequestCallbacks  []AfterA2ARequestCallback
    AfterAgentCallbacks    []agent.AfterAgentCallback

    A2APartConverter   adka2a.A2APartConverter    // Custom A2A→GenAI part conversion.
    GenAIPartConverter adka2a.GenAIPartConverter  // Custom GenAI→A2A part conversion.

    ClientProvider    A2AClientProvider          // Custom message-sending implementation.
    MessageSendConfig *a2a.SendMessageConfig

    // Called if Run exits before a terminal event from the remote server.
    // Default behavior: cancel RPC with a 5s timeout.
    RemoteTaskCleanupCallback A2ARemoteTaskCleanupCallback
}
```

Server side: `server/adka2a/v2` exposes agents over A2A (the launcher's `a2a` mode uses it); `server/adkrest` embeds the REST API in existing services.

## plugin.Config

```go
type Config struct {
    Name                    string
    OnUserMessageCallback   OnUserMessageCallback
    OnEventCallback         OnEventCallback
    BeforeRunCallback       BeforeRunCallback
    AfterRunCallback        AfterRunCallback
    BeforeAgentCallback     agent.BeforeAgentCallback
    AfterAgentCallback      agent.AfterAgentCallback
    BeforeModelCallback     llmagent.BeforeModelCallback
    AfterModelCallback      llmagent.AfterModelCallback
    OnModelErrorCallback    llmagent.OnModelErrorCallback
    BeforeToolCallback      llmagent.BeforeToolCallback
    AfterToolCallback       llmagent.AfterToolCallback
    OnToolErrorCallback     llmagent.OnToolErrorCallback
    CloseFunc               func() error
}
```

## artifact.Service

```go
type Service interface {
    Save(ctx context.Context, req *SaveRequest) (*SaveResponse, error)
    Load(ctx context.Context, req *LoadRequest) (*LoadResponse, error)
    Delete(ctx context.Context, req *DeleteRequest) error
    List(ctx context.Context, req *ListRequest) (*ListResponse, error)
    Versions(ctx context.Context, req *VersionsRequest) (*VersionsResponse, error)
    GetArtifactVersion(ctx context.Context, req *GetArtifactVersionRequest) (*GetArtifactVersionResponse, error)  // v1.1.0+
}

func InMemoryService() Service
```

GCS-backed: `google.golang.org/adk/artifact/gcsartifact`

## memory.Service

Method names changed at v1.0.0 (`AddSession` → `AddSessionToMemory`, `Search` → `SearchMemory`); request/response type names did not change.

```go
type Service interface {
    AddSessionToMemory(ctx context.Context, s session.Session) error
    SearchMemory(ctx context.Context, req *SearchRequest) (*SearchResponse, error)
}

func InMemoryService() Service
```

Vertex AI Memory Bank backend (v1.3.0+): `google.golang.org/adk/memory/vertexai`

```go
// import memvertexai "google.golang.org/adk/memory/vertexai"
func NewService(ctx context.Context, config *ServiceConfig) (memory.Service, error)

type ServiceConfig struct {
    vertexaiutil.AgentEngineData             // Embedded: identifies the Agent Engine instance.
    StateKeySessionLastUpdateTime string     // "" = use whole session for memory generation.
    WaitForCompletion             bool
}
```

## agent.Loader

```go
type Loader interface {
    ListAgents() []string
    LoadAgent(name string) (Agent, error)
    RootAgent() Agent
}

func NewSingleLoader(a Agent) Loader
func NewMultiLoader(root Agent, agents ...Agent) (Loader, error)
```

`NewSingleLoader` provides one root agent. `NewMultiLoader` registers multiple agents with one designated as root; returns error on duplicate names. Used with `launcher.Config.AgentLoader`.

## launcher.Config

```go
type Config struct {
    SessionService   session.Service
    ArtifactService  artifact.Service
    MemoryService    memory.Service
    AgentLoader      agent.Loader
    A2AOptions       []a2asrv.RequestHandlerOption
    PluginConfig     runner.PluginConfig    // Plugins in launcher mode.
    TelemetryOptions []telemetry.Option     // Telemetry in launcher mode.
}
```

Launchers: `full.NewLauncher()` (console + web UI + API + A2A, dev), `prod.NewLauncher()` (REST API + A2A only), plus `cmd/launcher/console`, `cmd/launcher/web`, `cmd/launcher/universal` (compose custom sets via `launcher.SubLauncher`), and `cmd/launcher/agentengine` for Vertex AI Agent Engine. Pub/Sub and Eventarc trigger sublaunchers: `cmd/launcher/web/triggers/{pubsub,eventarc}`.

## telemetry

```go
func New(ctx context.Context, opts ...Option) (*Providers, error)

type Providers struct {
    TracerProvider *sdktrace.TracerProvider
    LoggerProvider *sdklog.LoggerProvider
}

func (t *Providers) SetGlobalOtelProviders()
func (t *Providers) Shutdown(ctx context.Context) error
```

### Telemetry Options

| Option | Purpose |
|---|---|
| `WithOtelToCloud(bool)` | Enable/disable export to GCP `telemetry.googleapis.com`. |
| `WithResource(*resource.Resource)` | Custom OTel resource (merged with defaults). |
| `WithGoogleCredentials(*google.Credentials)` | Override application default credentials. |
| `WithGcpResourceProject(string)` | Set `gcp.project_id` resource attribute. |
| `WithGcpQuotaProject(string)` | Set quota project for telemetry export. |
| `WithSpanProcessors(...sdktrace.SpanProcessor)` | Register additional span processors. |
| `WithLogRecordProcessors(...sdklog.Processor)` | Register additional log processors. |
| `WithTracerProvider(*sdktrace.TracerProvider)` | Override the default TracerProvider. |
| `WithLoggerProvider(*sdklog.LoggerProvider)` | Override the default LoggerProvider. |
| `WithGenAICaptureMessageContent(bool)` | Log message content (default from `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT` env). |

## Plugin Callback Types

```go
type OnUserMessageCallback func(agent.InvocationContext, *genai.Content) (*genai.Content, error)
type BeforeRunCallback func(agent.InvocationContext) (*genai.Content, error)
type AfterRunCallback func(agent.InvocationContext)
type OnEventCallback func(agent.InvocationContext, *session.Event) (*session.Event, error)
```

These are plugin-specific callbacks defined in `google.golang.org/adk/plugin`. Model/tool/agent callbacks in `plugin.Config` reuse the types from `llmagent` and `agent` packages.

## Built-in Plugin Configs

### retryandreflect

```go
func New(opts ...PluginOption) (*plugin.Plugin, error)
func MustNew(opts ...PluginOption) *plugin.Plugin

type TrackingScope string
const (
    Invocation TrackingScope = "invocation"    // Per-invocation failure tracking (default).
    Global     TrackingScope = "global"        // Cross-invocation failure tracking.
)

func WithMaxRetries(maxRetries int) PluginOption         // Default: 3.
func WithErrorIfRetryExceeded(b bool) PluginOption       // Default: false (injects guidance instead).
func WithTrackingScope(scope TrackingScope) PluginOption  // Default: Invocation.
```

When `ErrorIfRetryExceeded` is `false` (default), exceeded retries inject an instruction telling the LLM to stop using the failing tool rather than returning the raw error.

### functioncallmodifier

```go
func NewPlugin(cfg FunctionCallModifierConfig) (*plugin.Plugin, error)
func MustNewPlugin(cfg FunctionCallModifierConfig) *plugin.Plugin

type FunctionCallModifierConfig struct {
    Predicate           func(toolName string) bool       // Which tools to modify.
    Args                map[string]*genai.Schema          // Extra args to inject into tool schema.
    OverrideDescription func(original string) string      // Rewrite tool description.
}
```

Injected args are stripped from the LLM's function call and stored in session state under `"{functionCallID}/{argName}"`.

### loggingplugin

```go
func New(name string) (*plugin.Plugin, error)
func MustNew(name string) *plugin.Plugin
```

Pass `""` for name to default to `"logging_plugin"`. Logs to console with ANSI grey coloring.

## tool/exampletool (v1.0.0+)

Injects few-shot examples into the LLM request as system-instruction text (a request processor, not an LLM-invoked tool).

```go
type Example struct {
    Input  *genai.Content   `json:"input"`
    Output []*genai.Content `json:"output"`
}

type ExampleToolConfig struct {
    Examples []*Example
}

func New(config ExampleToolConfig) (tool.Tool, error)  // Concrete unexported type; use as tool.Tool.
```

## tool/skilltoolset (v1.2.0+)

Agent Skills with progressive disclosure: the toolset injects skill frontmatter into the system instruction and exposes `load_skill` / resource-loading tools so the LLM pulls full skill content on demand.

```go
// import "google.golang.org/adk/tool/skilltoolset"
//        "google.golang.org/adk/tool/skilltoolset/skill"

type Config struct {
    Source            skill.Source  // Where skills come from (e.g., filesystem source).
    Name              string
    SystemInstruction string
}

func New(ctx context.Context, cfg Config) (*SkillToolset, error)  // Implements tool.Toolset.
```

The `skill` subpackage provides `Frontmatter`, `Parse`, `ParseBytes`, `Validate`, `Build`, the `Source` interface, a filesystem source, and preload/merge source proxies.

## model/apigee (v1.0.0+)

Routes Gemini calls through an Apigee proxy:

```go
func NewModel(ctx context.Context, modelName string, opts ...Option) (model.LLM, error)  // Concrete unexported type; use as model.LLM.
// Options: WithProxyURL(string), WithCustomHeaders(http.Header), WithHTTPClient(*http.Client)
```

## util/instructionutil

```go
// Performs {key} / {artifact.key} / {key?} substitution against session state.
// Use inside an InstructionProvider (providers do not auto-substitute).
func InjectSessionState(ctx agent.ReadonlyContext, template string) (string, error)
```
