# API Reference

Type reference for ADK Go. Verified against `google.golang.org/adk/v2` v2.5.0. All import paths below start with `google.golang.org/adk/v2/`.

## Core Interfaces

### agent.Agent

```go
type Agent interface {
    Name() string
    Description() string
    Run(InvocationContext) iter.Seq2[*session.Event, error]
    SubAgents() []Agent
    FindAgent(name string) Agent    // Recursive lookup by name.
    FindSubAgent(name string) Agent

    // Has an unexported method: user code CANNOT implement this interface.
    // Construct agents via agent.New, llmagent.New, workflowagent.New, or workflow agent constructors.
}
```

### model.LLM

```go
type LLM interface {
    Name() string
    GenerateContent(ctx context.Context, req *LLMRequest, stream bool) iter.Seq2[*LLMResponse, error]
}

// Name-based registry (v2.1.0). Opt-in: providers do not self-register.
type Factory func(ctx context.Context, name string) (LLM, error)
func Register(namePattern string, f Factory)              // Unanchored regexp; panics on invalid/duplicate.
func NewLLM(ctx context.Context, name string) (LLM, error) // Exactly one pattern must match.
```

### tool.Tool and tool.Toolset

```go
type Tool interface {
    Name() string
    Description() string
    IsLongRunning() bool
}

type Toolset interface {
    Name() string
    Tools(ctx agent.ReadonlyContext) ([]Tool, error)
}
```

A hand-written tool (instead of `functiontool`) must also implement these methods, or the flow fails with `tool "X" does not implement RequestProcessor() method`:

```go
ProcessRequest(ctx agent.Context, req *model.LLMRequest) error   // Usually: return toolutils.PackTool(req, t)
Declaration() *genai.FunctionDeclaration
Run(ctx agent.Context, args any) (map[string]any, error)
RunStream(ctx agent.Context, args any) iter.Seq2[string, error]  // Optional: streaming tools.
```

```go
// tool/toolutils (v2.1.0)
type Tool interface {
    Name() string
    Declaration() *genai.FunctionDeclaration
}
func PackTool(req *model.LLMRequest, t Tool) error // Registers t and appends its declaration; errors on duplicate names.
```

## agent.Config

Used with `agent.New()` for custom agents.

```go
type Config struct {
    Name                 string
    Description          string
    SubAgents            []Agent
    BeforeAgentCallbacks []BeforeAgentCallback
    Run                  func(InvocationContext) iter.Seq2[*session.Event, error]
    AfterAgentCallbacks  []AfterAgentCallback
}
func New(cfg Config) (Agent, error) // Errors if a sub-agent appears twice.
```

## llmagent.Config

```go
type Config struct {
    // Identity
    Name        string        // Required. Unique in the agent tree. Do not use "user" (reserved; not validated).
    Description string        // One line; used by parents to decide delegation.
    SubAgents   []agent.Agent

    BeforeAgentCallbacks []agent.BeforeAgentCallback
    AfterAgentCallbacks  []agent.AfterAgentCallback

    // Model
    GenerateContentConfig *genai.GenerateContentConfig // Tools must go in Tools, not here.
    BeforeModelCallbacks  []BeforeModelCallback
    Model                 model.LLM
    AfterModelCallbacks   []AfterModelCallback
    OnModelErrorCallbacks []OnModelErrorCallback

    // Instructions. {key} from state, {key?} optional, {artifact.name} artifact text.
    // Keys must match ^[a-zA-Z_][a-zA-Z0-9_]*$, optionally with an app:, user:, or temp: prefix (others are
    // left literal). A missing non-optional key is an error.
    Instruction               string
    InstructionProvider       InstructionProvider // Replaces Instruction; NO {key} substitution.
    GlobalInstruction         string              // Only the root agent's global instruction takes effect.
    GlobalInstructionProvider InstructionProvider

    // Delegation
    DisallowTransferToParent bool
    DisallowTransferToPeers  bool

    // Unset: history for conversational agents; current turn only for single_turn graph nodes.
    // IncludeContentsDefault keeps history even there; IncludeContentsNone = current turn only.
    IncludeContents IncludeContents

    InputSchema  *genai.Schema // Parameters when used as a tool / single_turn / task sub-agent.
    OutputSchema *genai.Schema // Structured output. Tools and transfers still work (see below).

    // Tools
    BeforeToolCallbacks  []BeforeToolCallback
    Tools                []tool.Tool
    AfterToolCallbacks   []AfterToolCallback
    Toolsets             []tool.Toolset
    OnToolErrorCallbacks []OnToolErrorCallback

    OutputKey string // Final text response saved to state[OutputKey].

    // v2.0.0. ModeChat: reachable via transfer_to_agent. ModeTask: chats with the user, returns via finish_task.
    // ModeSingleTurn: completes without user interaction. Default: chat as root/sub-agent, single_turn as a graph node.
    Mode Mode
}

type Mode = llminternal.Mode // Underlying type is string, so Mode: "task" also compiles.
const (
    ModeUnset      // ""
    ModeChat       // "chat"
    ModeTask       // "task"
    ModeSingleTurn // "single_turn"
)

type IncludeContents string
const (
    IncludeContentsNone    IncludeContents = "none"
    IncludeContentsDefault IncludeContents = "default"
)

type InstructionProvider func(ctx agent.ReadonlyContext) (string, error)
```

**OutputSchema behavior:** with no tools, ADK sets `ResponseSchema` directly. With tools on Vertex AI Gemini 2.0+, the native schema is used alongside tools. With tools on any other Gemini model (including every Gemini API model), ADK injects a `set_model_response` tool and turns its arguments into the final JSON text. Non-Gemini models get `ResponseSchema` alongside tools. On the chat path, `OutputKey` stores the raw JSON **string**; on the single_turn path the parsed, validated object is stored.

Exported helpers for running an LLM agent as a workflow node: `llmagent.RunLLMAgentAsNode`, `PrepareLLMAgentInput`, `ProcessLLMAgentOutput`.

## Callback Signatures

All callbacks take the unified `agent.Context` (v2.0.0+).

```go
// package agent
type BeforeAgentCallback func(Context) (*genai.Content, error) // Non-nil content skips the agent run.
type AfterAgentCallback func(Context) (*genai.Content, error)  // Non-nil content is emitted as an extra event.

// package llmagent
// Non-nil response or error replaces the model call.
type BeforeModelCallback func(ctx agent.Context, llmRequest *model.LLMRequest) (*model.LLMResponse, error)
// Non-nil response or error replaces the model response.
type AfterModelCallback func(ctx agent.Context, llmResponse *model.LLMResponse, llmResponseError error) (*model.LLMResponse, error)
type OnModelErrorCallback func(ctx agent.Context, llmRequest *model.LLMRequest, llmResponseError error) (*model.LLMResponse, error)

// A non-nil map is used as the tool RESULT and the tool is skipped.
// To modify args and still run the tool, mutate args in place and return (nil, nil).
type BeforeToolCallback func(ctx agent.Context, tool tool.Tool, args map[string]any) (map[string]any, error)
// Non-nil result or error replaces the tool output.
type AfterToolCallback func(ctx agent.Context, tool tool.Tool, args, result map[string]any, err error) (map[string]any, error)
type OnToolErrorCallback func(ctx agent.Context, tool tool.Tool, args map[string]any, err error) (map[string]any, error)
```

In each callback list, the first callback returning a non-nil value (or error) stops the chain. Error handling in `BeforeAgentCallback` depends on placement: for a root `llmagent` run by the runner an error skips the agent, while sub-agents of workflow agents and custom `agent.New` agents yield the error and still run. Return non-nil content to short-circuit reliably.

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

### agent.InvocationContext

Received by custom agents' `Run` and plugin run-level callbacks.

```go
type InvocationContext interface {
    context.Context
    Agent() Agent
    Artifacts() Artifacts
    Memory() Memory
    Session() session.Session
    InvocationID() string
    Branch() string
    IsolationScope() string                       // v2.0.0
    UserContent() *genai.Content
    RunConfig() *RunConfig
    EndInvocation()
    Ended() bool
    ResumedInput(interruptID string) (any, bool)  // v2.0.0: workflow HITL resume.
    WithContext(ctx context.Context) InvocationContext
    WithICDelta(d *InvocationContextDelta) InvocationContext // v2.0.0
}
```

### agent.Context (v2.0.0)

The single context type passed to tools and all callbacks. Replaces v1's `agent.CallbackContext`, `agent.ToolContext`, and `tool.Context`.

```go
type Context interface {
    ReadonlyContext
    InvocationContext

    Artifacts() Artifacts
    State() session.State // Writes become the event's StateDelta.

    // Tool section
    FunctionCallID() string
    Actions() *session.EventActions
    SearchMemory(ctx context.Context, query string) (*memory.SearchResponse, error)
    ToolConfirmation() *toolconfirmation.ToolConfirmation
    RequestConfirmation(hint string, payload any) error

    // Workflow node section
    ResumedInput(interruptID string) (any, bool)
    Path() string
    RunID() string
    SubScheduler() DynamicSubScheduler
    WithAgentContext(ctx context.Context) Context
    WithAgentTimeout(timeout time.Duration) (Context, context.CancelFunc)
    WithAgentCancel() (Context, context.CancelFunc)
    OutputForAncestors() []string
    WithDelta(d *CommonContextDelta) Context
}
```

**Inert methods.** Every method compiles everywhere, but some return nil (and log a warning) depending on where the context comes from:

| Where | Returns nil / no-op | Works |
|---|---|---|
| Agent and model callbacks | `Agent()`, `Session()`, `Memory()`, `RunConfig()`, `Actions()`, `FunctionCallID()`, `EndInvocation()`, `SearchMemory`, `RequestConfirmation` | `State()`, `ReadonlyState()`, `Artifacts()`, identity accessors (`AgentName()`, `UserID()`, `SessionID()`, ...) |
| Tools and tool callbacks | `Agent()`, `Session()`, `Memory()`, `RunConfig()`, `EndInvocation()`, `ResumedInput()` | `State()`, `Actions()`, `Artifacts()`, `SearchMemory`, `FunctionCallID`, `ToolConfirmation`, `RequestConfirmation`, identity accessors |

Use `ctx.AgentName()` (not `ctx.Agent().Name()`), `ctx.State()` (not `ctx.Session().State()`), and `ctx.SearchMemory(...)` (not `ctx.Memory()`). `ctx.Artifacts()` is nil when the runner has no `ArtifactService`.

```go
// Constructors for tests and embedding.
func NewToolContext(ic InvocationContext, functionCallID string, actions *session.EventActions,
    confirmation *toolconfirmation.ToolConfirmation) Context
func NewCallbackContext(ic InvocationContext, actions *session.EventActions) Context

// v2.5.0: recover the acting identity from any context derived from an ADK context
// (e.g. inside an http.RoundTripper under a tool call). Not an authentication boundary.
type Identity struct{ UserID, AppName, SessionID string }
func IdentityFromContext(ctx context.Context) (Identity, bool)

// Test double: embed it and override only what the test uses; other methods panic.
type StrictContextMock struct{ Ctx context.Context }
func NewStrictContextMock(ctx context.Context) StrictContextMock
```

## session.Event

```go
type Event struct {
    model.LLMResponse                           // Embedded: Content, UsageMetadata, Partial, ...
    ID                 string
    Timestamp          time.Time
    InvocationID       string
    Branch             string                   // "agent1.agent2" hierarchy path.
    IsolationScope     string                   // v2.0.0: restricts which agents see this event.
    Author             string                   // "user" or agent name.
    Actions            EventActions
    LongRunningToolIDs []string
    Routes             []string                 // v2.0.0: workflow routing keys.
    RequestedInput     *RequestInput            // v2.0.0: workflow HITL pause.
    Output             any                      // v2.0.0: workflow node output.
    NodeInfo           *NodeInfo                // v2.0.0
}

func NewEvent(ctx context.Context, invocationID string) *Event // v2.0.0: ctx first.
func (e *Event) IsFinalResponse() bool

type RequestInput struct {
    InterruptID    string             // Correlation key; empty = UUID.
    Message        string
    ResponseSchema *jsonschema.Schema // Reply validation.
    Payload        any                // JSON-encodable.
}
```

JSON field names are camelCase (`invocationId`, `isolationScope`, `routes`, `requestedInput`, `output`, `nodeInfo`) since v2.2.0. `IsFinalResponse` is false for compaction events.

### session.EventActions

```go
type EventActions struct {
    StateDelta                 map[string]any
    ArtifactDelta              map[string]int64
    RequestedToolConfirmations map[string]toolconfirmation.ToolConfirmation
    SkipSummarization          bool
    TransferToAgent            string           // Target agent name for delegation.
    Escalate                   bool             // Exit a loop / escalate to the parent.
    Compaction                 *EventCompaction // v2.3.0. Framework-only; cleared if set by user code.
}
```

## model.LLMRequest / LLMResponse

```go
type LLMRequest struct {
    Model    string
    Contents []*genai.Content
    Config   *genai.GenerateContentConfig // Function declarations live in Config.Tools.
    Tools    map[string]any `json:"-"`     // Internal tool registry (filled by PackTool).
}

type LLMResponse struct {
    Content                 *genai.Content
    CitationMetadata        *genai.CitationMetadata
    GroundingMetadata       *genai.GroundingMetadata
    UsageMetadata           *genai.GenerateContentResponseUsageMetadata
    CustomMetadata          map[string]any
    LogprobsResult          *genai.LogprobsResult
    InputTranscription      *genai.Transcription // Live sessions.
    OutputTranscription     *genai.Transcription // Live sessions.
    ModelVersion            string
    Partial                 bool                 // Streaming: incomplete chunk.
    TurnComplete            bool                 // Streaming: response complete.
    Interrupted             bool
    SessionResumptionHandle string               // Live sessions.
    ErrorCode               string
    ErrorMessage            string
    FinishReason            genai.FinishReason
    AvgLogprobs             float64
}
```

## session.State and session.Service

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

const (
    KeyPrefixApp  = "app:"
    KeyPrefixUser = "user:"
    KeyPrefixTemp = "temp:"
)

var ErrNotFound = errors.New("session not found") // v2.4.0: wrapped by Get and AppendEvent.

type Service interface {
    Create(context.Context, *CreateRequest) (*CreateResponse, error)
    Get(context.Context, *GetRequest) (*GetResponse, error)
    List(context.Context, *ListRequest) (*ListResponse, error)
    Delete(context.Context, *DeleteRequest) error
    AppendEvent(context.Context, Session, *Event) error
}
func InMemoryService() Service

type CreateRequest struct {
    AppName, UserID, SessionID string
    State                      map[string]any
}
type GetRequest struct {
    AppName, UserID, SessionID string
    NumRecentEvents int       // Optional: at most N most recent events.
    After           time.Time // Optional: events with timestamp >= After.
}
```

Prefixes do not compose (`app:temp:x` is an app key). Custom services must assign IDs to ID-less events, round-trip `EventActions.Compaction`, persist the v2 event fields, wrap `ErrNotFound`, and treat `Delete` of a missing session as a no-op; `session/sessiontestsuite` checks this contract.

Backends: `session/database` (`NewSessionService(dialector, opts...)`, `NewSessionServiceFromDB(*gorm.DB)`, `AutoMigrate(svc)` on every startup) and `session/vertexai` (`NewSessionService(ctx, VertexAIServiceConfig{ProjectID, Location, ReasoningEngine}, opts...)`).

## runner

```go
type Config struct {
    AppName           string
    Agent             agent.Agent        // Required.
    SessionService    session.Service    // Required.
    ArtifactService   artifact.Service   // Optional; needed by artifact tools.
    MemoryService     memory.Service     // Optional; needed by memory tools.
    PluginConfig      PluginConfig
    AutoCreateSession bool               // Run creates the session on any Get error.
    Compaction        *compaction.Config // v2.3.0. nil = disabled.
}

type PluginConfig struct {
    Plugins      []*plugin.Plugin
    CloseTimeout time.Duration
}

func New(cfg Config) (*Runner, error)
func NewInMemory(appName string, a agent.Agent) (*Runner, error) // v2.1.0: in-memory services + AutoCreateSession.

func (r *Runner) Run(ctx context.Context, userID, sessionID string, msg *genai.Content,
    cfg agent.RunConfig, opts ...RunOption) iter.Seq2[*session.Event, error]
func (r *Runner) RunLive(ctx context.Context, userID, sessionID string,
    cfg agent.LiveRunConfig, opts ...RunOption) (agent.LiveSession, iter.Seq2[*session.Event, error], error)

func WithStateDelta(delta map[string]any) RunOption // Inject state before the run.
func WithYieldUserMessage() RunOption               // v2.0.0: also yield the appended user event (LLM-agent roots).
```

- A root `llmagent` runs through the workflow node runtime and must be chat mode.
- An error does not end the stream; `Run` yields `(nil, err)` and may continue.
- Live runs never compact. Compaction failures wrap `compaction.ErrCompaction` and arrive after the turn's events are persisted.

## agent.RunConfig and Live Sessions

```go
type RunConfig struct {
    StreamingMode             StreamingMode // StreamingModeNone ("none") or StreamingModeSSE ("sse").
    SaveInputBlobsAsArtifacts bool
}

type LiveSession interface {
    Send(req LiveRequest) error
    Close() error // Tears down the flow (v2.3.0); always call it.
}

type LiveRequest struct {
    RealtimeInput any            // *genai.Blob, *genai.ActivityStart, or *genai.ActivityEnd.
    Content       *genai.Content // Text/multimodal content or a FunctionResponse reply.
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
    SaveLiveBlob             bool
    MaxLLMCalls              int
}
```

## session/compaction (v2.3.0)

```go
type Config struct {
    CompactionInterval int        // Sliding window: summarize every N completed invocations (0 = off).
    OverlapSize        int        // Re-include N already-compacted invocations (needs CompactionInterval).
    TokenThreshold     int        // Tail retention: compact mid-invocation when prompt tokens >= this (0 = off).
    EventRetentionSize int        // Tail retention: raw recent events to keep (required with TokenThreshold).
    Summarizer         Summarizer // nil = LLMSummarizer over the root agent's model (root must be an LLM agent).
}
func (c *Config) Validate() error
var ErrCompaction error

type Summarizer interface {
    SummarizeEvents(ctx context.Context, events []*session.Event) (SummarizeResult, error)
}

type LLMSummarizerConfig struct {
    Model                 model.LLM     // Required.
    PromptTemplate        string        // Must contain "{conversation_history}"; "" = built-in.
    MaxToolContentChars   int           // Per-part cap (default 2000; negative disables).
    MaxTranscriptChars    int           // Whole-transcript cap (default 200000; exceeding is an error).
    Timeout               time.Duration
    GenerateContentConfig *genai.GenerateContentConfig
}
func NewLLMSummarizer(cfg LLMSummarizerConfig) (*LLMSummarizer, error)
```

Covered events stay in the session; prompt assembly replaces them with the summary. Summaries are not yielded to `Run` consumers (find them via `ev.Actions.Compaction != nil`). Keep durable facts in state referenced by `{key}` rather than relying on summaries.

## functiontool

```go
type Config struct {
    Name                        string
    Description                 string
    InputSchema                 *jsonschema.Schema // nil = inferred from TArgs.
    OutputSchema                *jsonschema.Schema // nil = inferred from TResults.
    IsLongRunning               bool
    RequireConfirmation         bool               // Static HITL flag.
    RequireConfirmationProvider any                // Must be func(TArgs) bool.
}

type Func[TArgs, TResults any] func(agent.Context, TArgs) (TResults, error)
func New[TArgs, TResults any](cfg Config, handler Func[TArgs, TResults]) (tool.Tool, error)

type StreamingFunc[TArgs any] func(agent.Context, TArgs) iter.Seq2[string, error]
func NewStreaming[TArgs any](cfg Config, handler StreamingFunc[TArgs]) (tool.Tool, error)

var ErrInvalidArgument error
```

`TArgs` must be a struct or map (or a pointer to one). Handler panics are recovered into errors. Non-map results are wrapped as `{"result": X}`.

## agenttool

```go
func New(agent agent.Agent, cfg *Config) tool.Tool

type Config struct {
    SkipSummarization bool // End the parent's turn on the tool result (shown as text since v2.4.0).
}
```

Each call runs the child through a new runner with a fresh in-memory session seeded with a copy of the parent's state, and a fresh in-memory memory service. **State changes made by the child are not written back to the parent**; return data through the tool result. **The parent's runner plugins are not propagated**: plugin callbacks (logging, metrics, guardrails) never see the child's model and tool calls. Use a `ModeSingleTurn` or `ModeTask` sub-agent when plugins must cover delegated work. Since v2.5.0 the child shares the parent's artifact store. Output is validated against the child's `OutputSchema` if set, else returned as `{"result": text}`.

## Tool Helpers

```go
var ErrConfirmationRequired error
var ErrConfirmationRejected error

type Predicate func(ctx agent.ReadonlyContext, tool Tool) bool
func AllowedToolsPredicate(allowedTools []string) Predicate
func StringPredicate(allowedTools []string) Predicate // Deprecated.
func FilterToolset(toolset Toolset, predicate Predicate) Toolset

// Experimental.
type ConfirmationProvider func(toolName string, toolInput any) bool
func WithConfirmation(toolset Toolset, requireConfirmation bool, provider ConfirmationProvider) Toolset

// tool/toolconfirmation
const FunctionCallName = "adk_request_confirmation"
type ToolConfirmation struct {
    Hint      string `json:"hint"`
    Confirmed bool   `json:"confirmed"`
    Payload   any    `json:"payload"`
}
func OriginalCallFrom(fc *genai.FunctionCall) (*genai.FunctionCall, error)
```

Framework-injected tools to recognize in traces: `transfer_to_agent`, `set_model_response`, `finish_task` (task mode), one tool per single_turn/task sub-agent (named after it), `task_completed` (`sequentialagent` live runs only), `adk_request_confirmation`, and `adk_request_input` (workflow HITL).

## genai.GenerateContentConfig (Key Fields)

```go
type GenerateContentConfig struct {
    SystemInstruction *Content
    Temperature       *float32
    TopP              *float32
    TopK              *float32
    MaxOutputTokens   int32
    StopSequences     []string
    ResponseMIMEType  string   // "text/plain" or "application/json".
    ResponseSchema    *Schema
    SafetySettings    []*SafetySetting
    ThinkingConfig    *ThinkingConfig
    Seed              *int32
    CandidateCount    int32
    PresencePenalty   *float32
    FrequencyPenalty  *float32
}
```

Use `genai.Ptr[float32](0.7)` for pointer fields. Prefer `llmagent.Config.Instruction` over `SystemInstruction`.

## Workflow Agent Configs

```go
// sequentialagent, parallelagent
type Config struct {
    AgentConfig agent.Config // Name + SubAgents required; a custom Run is rejected.
}

// loopagent
type Config struct {
    AgentConfig   agent.Config
    MaxIterations uint // 0 = run until a sub-agent escalates.
}

// agent/workflowagent (graph workflows)
type Config struct {
    Name                 string
    Description          string
    SubAgents            []agent.Agent // Agents wrapped in AgentNodes.
    BeforeAgentCallbacks []agent.BeforeAgentCallback
    AfterAgentCallbacks  []agent.AfterAgentCallback
    Edges                []workflow.Edge
}
```

## remoteagent/v2 A2AConfig

```go
// import remoteagent "google.golang.org/adk/v2/agent/remoteagent/v2"

func NewA2A(cfg A2AConfig) (agent.Agent, error)
func NewAgentCardProvider(source string, opts ...agentcard.ResolveOption) AgentCardProvider // http(s) URL or file path.
type AgentCardProvider func(ctx context.Context) (*a2a.AgentCard, error)
func NewA2AClientProvider(factory *a2aclient.Factory) A2AClientProvider

type A2AConfig struct {
    Name        string
    Description string

    AgentCard         *a2a.AgentCard    // Static card, OR:
    AgentCardProvider AgentCardProvider // Resolved per invocation.

    BeforeAgentCallbacks   []agent.BeforeAgentCallback
    BeforeRequestCallbacks []BeforeA2ARequestCallback // func(agent.Context, *a2a.SendMessageRequest) (*session.Event, error)
    Converter              A2AEventConverter
    AfterRequestCallbacks  []AfterA2ARequestCallback
    AfterAgentCallbacks    []agent.AfterAgentCallback

    AllowTransferToAgent bool // v2.3.0. Default false: a peer's transfer request is redacted.

    A2APartConverter   adka2a.A2APartConverter
    GenAIPartConverter adka2a.GenAIPartConverter

    ClientProvider    A2AClientProvider       // Custom client (e.g. authenticated HTTP).
    MessageSendConfig *a2a.SendMessageConfig

    RemoteTaskCleanupCallback A2ARemoteTaskCleanupCallback // Default: cancel with a 5s timeout.
}

var ErrUnsupportedCardSource error  // v2.3.0: source is neither http(s) nor a path.
var ErrUntrustedCardInterface error // v2.4.0: fetched card advertises another origin, or non-loopback http.
```

## plugin

```go
type Config struct {
    Name                  string
    OnUserMessageCallback OnUserMessageCallback
    OnEventCallback       OnEventCallback
    BeforeRunCallback     BeforeRunCallback
    AfterRunCallback      AfterRunCallback
    BeforeAgentCallback   agent.BeforeAgentCallback
    AfterAgentCallback    agent.AfterAgentCallback
    BeforeModelCallback   llmagent.BeforeModelCallback
    AfterModelCallback    llmagent.AfterModelCallback
    OnModelErrorCallback  llmagent.OnModelErrorCallback
    BeforeToolCallback    llmagent.BeforeToolCallback
    AfterToolCallback     llmagent.AfterToolCallback
    OnToolErrorCallback   llmagent.OnToolErrorCallback
    CloseFunc             func() error
}
func New(cfg Config) (*Plugin, error)

type OnUserMessageCallback func(agent.InvocationContext, *genai.Content) (*genai.Content, error)
type BeforeRunCallback func(agent.InvocationContext) (*genai.Content, error)
type AfterRunCallback func(agent.InvocationContext)
type OnEventCallback func(agent.InvocationContext, *session.Event) (*session.Event, error)
```

Plugin callbacks run before the agent's own callbacks of the same kind. Plugins cannot plant or alter `Actions.Compaction`.

### Built-in Plugins

```go
// plugin/retryandreflect
func New(opts ...PluginOption) (*plugin.Plugin, error)
func MustNew(opts ...PluginOption) *plugin.Plugin
func WithMaxRetries(maxRetries int) PluginOption         // Default 3.
func WithErrorIfRetryExceeded(b bool) PluginOption       // Default false: inject "stop using this tool" guidance.
func WithTrackingScope(scope TrackingScope) PluginOption // Invocation (default) or Global.

// plugin/functioncallmodifier
func NewPlugin(cfg FunctionCallModifierConfig) (*plugin.Plugin, error)
func MustNewPlugin(cfg FunctionCallModifierConfig) *plugin.Plugin
type FunctionCallModifierConfig struct {
    Predicate           func(toolName string) bool
    Args                map[string]*genai.Schema         // Extra args injected into tool schemas.
    OverrideDescription func(original string) string
}
// Injected args are stripped from the call and stored in state under "{functionCallID}/{argName}".

// plugin/loggingplugin
func New(name string) (*plugin.Plugin, error) // "" = "logging_plugin".
func MustNew(name string) *plugin.Plugin
```

The BigQuery agent analytics plugin lives in the separate module `google.golang.org/adk/plugin/agentanalytics`.

## artifact.Service

```go
type Service interface {
    Save(ctx context.Context, req *SaveRequest) (*SaveResponse, error)
    Load(ctx context.Context, req *LoadRequest) (*LoadResponse, error)
    Delete(ctx context.Context, req *DeleteRequest) error
    List(ctx context.Context, req *ListRequest) (*ListResponse, error)
    Versions(ctx context.Context, req *VersionsRequest) (*VersionsResponse, error)
    GetArtifactVersion(ctx context.Context, req *GetArtifactVersionRequest) (*GetArtifactVersionResponse, error)
}
func InMemoryService() Service

type SaveRequest struct {
    AppName, UserID, SessionID, FileName string
    Part           *genai.Part
    CustomMetadata map[string]any // v2.5.0: values persisted as strings.
    Version        int64
}

type ArtifactVersion struct {
    Version        int64
    CanonicalURI   string         // Stable identity (gs://bucket/object for GCS); not a download URL.
    CustomMetadata map[string]any // Always non-nil.
    CreateTime     time.Time      // Was float64 in v1.
    MimeType       string
}
```

Filenames prefixed `user:` are user-scoped. GCS backend: `artifact/gcsartifact.NewService(ctx, bucketName, opts...)`.

## memory.Service

```go
type Service interface {
    AddSessionToMemory(ctx context.Context, s session.Session) error
    SearchMemory(ctx context.Context, req *SearchRequest) (*SearchResponse, error)
}
func InMemoryService() Service

type SearchRequest struct{ Query, UserID, AppName string }
```

Vertex AI Memory Bank: `memory/vertexai.NewService(ctx, *ServiceConfig)`. `ServiceConfig` embeds `util/vertexai.AgentEngineData{ProjectID, Location, ReasoningEngine}` and adds `StateKeySessionLastUpdateTime string` and `WaitForCompletion bool`.

## agent.Loader

```go
type Loader interface {
    ListAgents() []string
    LoadAgent(name string) (Agent, error)
    RootAgent() Agent
}
func NewSingleLoader(a Agent) Loader
func NewMultiLoader(root Agent, agents ...Agent) (Loader, error) // Error on duplicate names.
```

## launcher.Config

```go
type Config struct {
    SessionService   session.Service
    ArtifactService  artifact.Service
    MemoryService    memory.Service
    AgentLoader      agent.Loader
    A2AOptions       []a2asrv.RequestHandlerOption
    PluginConfig     runner.PluginConfig
    TelemetryOptions []telemetry.Option
    Authenticator    authn.Authenticator // v2.4.0, REST API only.
    Authorizer       authz.Authorizer    // v2.4.0
    Compaction       *compaction.Config  // v2.3.0
    BindHost         string              // v2.5.0, set by the web launcher.
    MaxPayloadSize   int64               // v2.5.0, <= 0 = 10 MiB.
}
func (c *Config) Validate() error
```

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

| Option | Purpose |
|---|---|
| `WithOtelToCloud(bool)` | Export to Google Cloud (`telemetry.googleapis.com`). |
| `WithResource(*resource.Resource)` | Custom OTel resource (merged with defaults). |
| `WithGoogleCredentials(*google.Credentials)` | Override application default credentials. |
| `WithGcpResourceProject(string)` | Set the `gcp.project_id` resource attribute. |
| `WithGcpQuotaProject(string)` | Quota project for export. |
| `WithSpanProcessors(...sdktrace.SpanProcessor)` | Additional span processors. |
| `WithLogRecordProcessors(...sdklog.Processor)` | Additional log processors. |
| `WithTracerProvider(*sdktrace.TracerProvider)` | Override the TracerProvider. |
| `WithLoggerProvider(*sdklog.LoggerProvider)` | Override the LoggerProvider. |

Message content capture is controlled only by `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT`:

| Value | Log records | `generate_content` span attributes (`gen_ai.input.messages`, ...) |
|---|---|---|
| unset | no | no |
| `true` / `1` | yes | no |
| `EVENT_ONLY` | yes | no |
| `SPAN_ONLY` | no | yes |
| `SPAN_AND_EVENT` | yes | yes |

Span attributes over 60 KiB are omitted entirely. OTLP exporters read the standard `OTEL_EXPORTER_OTLP_*` endpoint variables. Code passing `sdklog` types must use `go.opentelemetry.io/otel/sdk/log` v0.22.x.

## Other Packages

```go
// tool/exampletool: few-shot examples injected as system-instruction text (not an LLM-invoked tool).
type Example struct {
    Input  *genai.Content   `json:"input"`
    Output []*genai.Content `json:"output"`
}
type ExampleToolConfig struct{ Examples []*Example }
func New(config ExampleToolConfig) (*exampleTool, error) // Use as tool.Tool.

// tool/skilltoolset: Agent Skills with progressive disclosure (load_skill takes a "name" param).
type Config struct {
    Source            skill.Source // e.g. a filesystem source from the skill subpackage.
    Name              string
    SystemInstruction string
}
func New(ctx context.Context, cfg Config) (*SkillToolset, error) // Implements tool.Toolset.

// model/apigee: the model name must start with "apigee/".
func NewModel(ctx context.Context, modelName string, opts ...Option) (*apigeeModel, error) // Use as model.LLM.
// Options: WithProxyURL(string), WithCustomHeaders(http.Header), WithHTTPClient(*http.Client) (testing only).

// util/instructionutil: {key} / {artifact.key} / {key?} substitution inside an InstructionProvider.
func InjectSessionState(ctx agent.ReadonlyContext, template string) (string, error)

// platform: context-carried seams for deterministic tests and custom executors.
func WithTimeProvider(ctx context.Context, provider TimeProvider) context.Context
func WithUUIDProvider(ctx context.Context, provider UUIDProvider) context.Context
func WithTaskRunner(ctx context.Context, runner TaskRunner) context.Context // v2.1.0: parallel tool-call fan-out.
type TaskRunner func(ctx context.Context, tasks []func(context.Context)) // Must block until all tasks finish.
```
