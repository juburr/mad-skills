# Graph Workflows

The graph workflow engine (`google.golang.org/adk/v2/workflow`), added in v2.0.0, plus the `agent/workflowagent` adapter that turns a graph into an `agent.Agent`. Verified against `google.golang.org/adk/v2` v2.5.0. The public `workflow` API has not changed between v2.0.0 and v2.5.0; later releases only fixed bugs, so pin at least v2.4.0 for graph work.

```go
import (
    "github.com/google/jsonschema-go/jsonschema"         // Schema types used by typed nodes
    "google.golang.org/adk/v2/agent"
    "google.golang.org/adk/v2/agent/workflowagent"      // Graph -> agent.Agent
    "google.golang.org/adk/v2/session"
    "google.golang.org/adk/v2/workflow"                 // Nodes, edges, routes, RunNode, HITL
)
```

## Quick Start: Chain of Function Nodes

```go
upper := workflow.NewFunctionNode("upper", func(_ agent.Context, in string) (string, error) {
    return strings.ToUpper(in), nil
}, workflow.NodeConfig{RetryConfig: workflow.DefaultRetryConfig()})

suffix := workflow.NewFunctionNode("suffix", func(_ agent.Context, in string) (string, error) {
    return in + " IS AWESOME!", nil
}, workflow.NodeConfig{})

wf, err := workflowagent.New(workflowagent.Config{
    Name:        "simple_sequence_workflow",
    Description: "Uppercases and appends a suffix.",
    Edges:       workflow.Chain(workflow.Start, upper, suffix), // START passes the user's text
})
// Run wf like any agent: runner.New(runner.Config{Agent: wf, ...}) or
// launcher.Config{AgentLoader: agent.NewSingleLoader(wf)}.
```

A `*workflow.Workflow` is **not** an `agent.Agent`; always wrap edges with `workflowagent.New`. One `workflowagent` instance can serve many sessions because run state is rebuilt from session events.

### workflowagent.Config

```go
type Config struct {
    Name                 string
    Description          string
    SubAgents            []agent.Agent  // Register every agent wrapped in an AgentNode here.
    BeforeAgentCallbacks []agent.BeforeAgentCallback
    AfterAgentCallbacks  []agent.AfterAgentCallback
    Edges                []workflow.Edge
}
func New(cfg Config) (agent.Agent, error)
```

Register AgentNode-wrapped agents in `SubAgents`; otherwise the runner logs "Event from an unknown agent" when they author events. The workflow name doubles as a path namespace, so keep it unique within a session.

## Node Types

| Constructor | Node | Output |
|---|---|---|
| `NewFunctionNode[IN, OUT](name, fn, cfg)` | Go function `func(agent.Context, IN) (OUT, error)` | `OUT` |
| `NewEmittingFunctionNode[IN, OUT](name, fn, cfg)` | Go function that can `emit` events mid-run (routes, HITL prompts, progress) | returned `OUT`; nil suppresses the terminal event |
| `NewFunctionNodeFromState[Params, OUT](name, fn, cfg)` | Params struct loaded from session state (`state:"key"` tags) | `OUT` |
| `NewAgentNode(a, cfg)` / `NewAgentNodeTyped[In, Out](a, cfg)` | Wraps an agent; LLM agents default to `single_turn` | Agent's final text (parsed JSON if `OutputSchema` is set) |
| `NewToolNode(t, cfg)` / `NewToolNodeTyped[In, Out](t, cfg)` | Runs a `tool.Tool` (e.g., a `functiontool`) directly | Tool's `map[string]any` |
| `NewJoinNode(name)` | Fan-in barrier; fires once after **all** predecessors complete | `map[string]any{predecessorName: output}` |
| `NewParallelWorker(name, wrapped, maxConcurrency, cfg)` | Maps `wrapped` over a slice input concurrently | `[]any` in input order |
| `NewWorkflowNode(name, edges)` | Nested sub-graph | The sub-graph's single terminal output |
| `NewDynamicNode[IN, OUT](name, fn, cfg)` | Imperative orchestrator that calls `workflow.RunNode` | Returned `OUT` (or a child's output via `WithUseAsOutput`) |
| `workflow.Start` | Sentinel entry node (`"START"`) | The user message text (or nil) |

`*WithSchema` / `*WithSchemas` variants take `*jsonschema.Schema` for input/output validation. Custom nodes embed `workflow.BaseNode` (from `workflow.NewBaseNode(name, description, cfg)`) and implement `Run(ctx agent.Context, input any) iter.Seq2[*session.Event, error]`.

### Function Node Semantics

- **Input conversion:** a direct type assertion to `IN` is tried first, then a JSON round-trip (a `map[string]any` becomes your struct). A nil input becomes the zero value of `IN`.
- **Output:** a `*genai.Content` goes to `Event.Content`; a returned `*session.Event` is yielded as-is (lets a plain node set `Routes`/`Output`); **anything else goes to `Event.Output` with no `Content`**.
- **No schema inference:** `NewFunctionNode` never infers schemas from `IN`/`OUT`. A conversion failure without a schema is an ordinary error and is retried under `DefaultRetryConfig` (up to ~15s of backoff before it surfaces).
- **From state:** fields load from session state by field name or `state:"key"` tag; a field tagged `state:"node_input"` (or named `NodeInput`) receives the predecessor's output. A missing key is a node error.

### Agent Node Semantics

- The node name is the agent's name.
- An `llmagent` with no declared `Mode` runs as **`single_turn`** at a graph node: it sees only the current turn (unless `IncludeContents: llmagent.IncludeContentsDefault`), is seeded with the node input, and its final text becomes the node output.
- Input becomes user content: a string is used as text; anything else is JSON-marshalled.
- **Task-mode agents cannot be static graph nodes** (`workflow.New` rejects them). Dispatch them with `RunNode` from a dynamic node or put them under a chat coordinator.
- **Chat-mode agents must be wired from `Start`**; a chat agent reached from any other node is rejected.
- **Composite agents produce no node output.** A `sequentialagent`/`parallelagent`/`loopagent` wrapped in an AgentNode hands `nil` to its successor. Pass data through `OutputKey` and session state instead.
- Typed and untyped agent nodes do not mix on one edge: `NewAgentNode(a1)` (schema `{}`) followed by `NewAgentNodeTyped[City, any](a2)` fails with `schema mismatch on edge a1 -> a2`.

## Edges and Routing

```go
type Edge struct{ From, To Node; Route Route }

func Chain(nodes ...Node) []Edge           // Sequential edges.
func Concat(items ...any) []Edge           // Merge Edge and []Edge values.
func NewEdgeBuilder() *EdgeBuilder         // Add, AddRoute, AddRoutes, AddFanOut, AddFanIn, Build.

type StringRoute string                    // Route types match against Event.Routes.
type IntRoute int
type BoolRoute bool
type MultiRoute[T comparable] []T          // Several values to one target.
var Default Route                          // Fires only when no concrete route matched.
```

A node picks a branch by emitting **one** event with `Event.Routes` set:

```go
classify := workflow.NewEmittingFunctionNode("classify",
    func(ctx agent.Context, msg string, emit func(*session.Event) error) (any, error) {
        ev := session.NewEvent(ctx, ctx.InvocationID())
        if strings.HasSuffix(strings.TrimSpace(msg), "?") {
            ev.Routes = []string{"question"}
        } else {
            ev.Routes = []string{"statement"}
        }
        ev.Output = msg      // Becomes the chosen successor's input.
        return nil, emit(ev) // nil return: no second (terminal) output event.
    }, workflow.NodeConfig{})

answer := workflow.NewFunctionNode("answer", func(_ agent.Context, m string) (string, error) {
    return "Q: " + m, nil
}, workflow.NodeConfig{})
comment := workflow.NewFunctionNode("comment", func(_ agent.Context, m string) (string, error) {
    return "S: " + m, nil
}, workflow.NodeConfig{})

edges := workflow.Concat(
    workflow.Chain(workflow.Start, classify),
    workflow.Edge{From: classify, To: answer, Route: workflow.StringRoute("question")},
    workflow.Edge{From: classify, To: comment, Route: workflow.Default},
)
```

Routing rules:

- Edges with no `Route` always fire. Concrete routes fire on a match. `Default` fires only when no concrete route matched.
- **Unmatched routes with no `Default` silently dead-end** the run (not an error). Always add a `Default` edge.
- Several values in `Routes` fan out to every matching edge. More than one routing event per activation is `ErrMultipleRoutingEvents`.
- A `(From, To)` pair may appear only once (`ErrDuplicateEdge`); use `MultiRoute` for several values to one target.
- **Loops** are conditional back-edges, e.g. `AddRoute(fixer, linter, workflow.StringRoute("again"))`. Unconditional cycles are rejected (`ErrUnconditionalCycle`).
- For LLM-driven routing, let an AgentNode classifier reply with one word, then normalize it into `ev.Routes` in an emitting function node. Handlers can read the original message with `ctx.UserContent()`.

## Fan-Out and Fan-In

```go
renewNode, _ := workflow.NewAgentNode(renewableAgent, workflow.NodeConfig{})
evNode, _ := workflow.NewAgentNode(evAgent, workflow.NodeConfig{})
synthNode, _ := workflow.NewAgentNode(synthesisAgent, workflow.NodeConfig{})

gather := workflow.NewJoinNode("gather") // Output keyed by predecessor (agent) name.
format := workflow.NewFunctionNode("format", func(_ agent.Context, got map[string]any) (string, error) {
    return fmt.Sprintf("Renewables: %v\nEVs: %v", got["Renewable"], got["EV"]), nil
}, workflow.NodeConfig{})

edges := workflow.NewEdgeBuilder().
    AddFanOut(workflow.Start, renewNode, evNode). // Run concurrently on sub-branches.
    AddFanIn(gather, renewNode, evNode).          // Fan-in MUST go through a JoinNode.
    Add(gather, format).
    Add(format, synthNode).
    Build()

root, err := workflowagent.New(workflowagent.Config{
    Name:      "research_pipeline",
    Edges:     edges,
    SubAgents: []agent.Agent{renewableAgent, evAgent, synthesisAgent},
})
```

- A non-join node with two or more unconditional incoming edges fails `workflow.New` with `ErrUnsupportedFanIn`.
- **Never route conditionally into a JoinNode**: a predecessor skipped by a route never completes, so the join never fires.
- More than one terminal node producing output fails the run with `ErrMultipleTerminalOutputs`. Converge branches with a JoinNode.

## ParallelWorker

```go
split := workflow.NewFunctionNode("split", func(_ agent.Context, in string) ([]string, error) {
    return strings.Fields(in), nil // ParallelWorker requires a slice input.
}, workflow.NodeConfig{})
upper := workflow.NewFunctionNode("upper", func(_ agent.Context, w string) (string, error) {
    return strings.ToUpper(w), nil
}, workflow.NodeConfig{}) // The wrapped node must NOT have a RetryConfig.

rc := workflow.DefaultRetryConfig()
rc.MaxAttempts = 3
const maxConcurrency = 4 // <= 0 means unlimited.
pw, err := workflow.NewParallelWorker("upper_all", upper, maxConcurrency, workflow.NodeConfig{RetryConfig: rc})

edges := workflow.Chain(workflow.Start, split, pw) // Output: []any{"ONE", "TWO", ...}
```

- A non-slice input fails with `parallel worker X expects a slice input`. Do not wire `Start` (a string) directly into a worker.
- Retries apply per item; the first non-retryable item error cancels in-flight items (fail-fast).
- Intermediate events of the wrapped node are suppressed; only the aggregate output event is yielded.
- `NodeConfig.ParallelWorker` is a no-op flag at v2.5.0; use `NewParallelWorker`.

## NodeConfig, Retries, and Timeouts

```go
type NodeConfig struct {
    RerunOnResume  *bool         // HITL: &true = node re-runs on resume; nil/&false = reply becomes its output.
    WaitForOutput  *bool         // RunNode path: child finishing without output parks the parent.
    RetryConfig    *RetryConfig  // nil = no retries.
    Timeout        time.Duration // > 0: per-activation context.WithTimeout.
    EmitsOwnSpan   bool          // Telemetry; AgentNode forces true.
    ParallelWorker bool          // No-op at v2.5.0.
}

type RetryConfig struct {
    MaxAttempts   int           // Includes the first attempt; 0 or 1 = no retry.
    InitialDelay  time.Duration
    MaxDelay      time.Duration
    BackoffFactor float64       // <= 0 treated as 1.0.
    Jitter        float64       // delay * (1 ± Jitter).
    ShouldRetry   func(error) bool
}
func DefaultRetryConfig() *RetryConfig // 5 attempts, 1s initial, 60s cap, x2 backoff, retries all but ErrInputValidation.
```

- Zero-valued `RetryConfig` fields are **not** defaults. Start from `DefaultRetryConfig()` and override fields.
- Node panics are recovered as node errors (retryable). A timeout (`context.DeadlineExceeded`) is retryable; `context.Canceled` is not.
- The first node error (after retries) cancels all in-flight nodes and is yielded after the drain.

## Data Flow Between Nodes

- **Node to node:** the successor's input is the predecessor's single `Event.Output`. Each activation may emit at most one output (`ErrMultipleOutputs`).
- **Session state:** still available via `ctx.State()`, `OutputKey`, `NewFunctionNodeFromState`, and tool state deltas. Use it for data that must skip nodes.
- **Original user message:** `ctx.UserContent()` in any node.
- **Persisted values:** node inputs, outputs, and HITL payloads must be JSON-encodable to survive pause/resume. Put binary data in artifacts.

## Dynamic Workflows

A dynamic node orchestrates children in Go code. Each child result is checkpointed, so control flow that is awkward as a static graph (loops until a condition, data-dependent fan-out) stays resumable.

```go
drafterNode, _ := workflow.NewAgentNode(drafter, workflow.NodeConfig{})
lintNode := workflow.NewFunctionNode("lint", lintFn, workflow.NodeConfig{})

assistant := workflow.NewDynamicNode[string, string]("assistant",
    func(ctx agent.Context, req string, _ func(*session.Event) error) (string, error) {
        if !strings.Contains(strings.ToLower(req), "email") {
            return "Out of scope. Ask me to draft an email.", nil
        }
        draft, err := workflow.RunNode[string](ctx, drafterNode, req)
        if err != nil {
            return "", err // Return ErrNodeInterrupted unchanged so the workflow pauses.
        }
        for i := 0; i < 3; i++ {
            findings, err := workflow.RunNode[string](ctx, lintNode, draft)
            if err != nil || findings == "" {
                return draft, err
            }
            draft, err = workflow.RunNode[string](ctx, drafterNode, draft+"\nFix: "+findings)
            if err != nil {
                return "", err
            }
        }
        return draft, nil
    }, workflow.NodeConfig{}) // RerunOnResume defaults to &true for dynamic nodes.

wa, err := workflowagent.New(workflowagent.Config{
    Name:      "email_assistant",
    SubAgents: []agent.Agent{drafter},
    Edges:     workflow.Chain(workflow.Start, assistant),
})
```

```go
func RunNode[OUT any](ctx agent.Context, child Node, input any, opts ...RunNodeOption) (OUT, error)

func WithRunID(id string) RunNodeOption        // Stable ID; must contain a non-digit, no '/' or '@'.
func WithUseSubBranch() RunNodeOption          // Isolate the child's LLM history on a sub-branch.
func WithUseAsOutput() RunNodeOption           // Child output becomes the dynamic node's output.
func WithIsolationScope(scope string) RunNodeOption
func WithIsolationScopeFromNodePath() RunNodeOption
func WithOverrideBranch(branch string) RunNodeOption
func WithRaiseOnWait() RunNodeOption           // Unresolved long-running tool => ErrNodeInterrupted.
```

- `ctx` must be the context passed into the enclosing dynamic function, otherwise `ErrInvalidRunNodeContext`. A custom `agent.New` agent cannot call `RunNode`.
- `RunNode[OUT]` is a **strict type assertion** with no JSON coercion. Use `RunNode[string]` for LLM text and `RunNode[any]` when the child returns a map.
- Completed child outputs are cached by path; auto run IDs count per child name, so **call `RunNode` in a deterministic order**. Side effects in the orchestrator body itself re-run on every re-entry.
- Children may run from goroutines; use `WithUseSubBranch()` plus distinct `WithRunID`s. `WithMaxConcurrency` does not cap `RunNode` children.
- Failure: `errors.Is(err, workflow.ErrNodeFailed)`; `errors.As` to `*workflow.NodeRunError` gives `ChildName`, `ChildPath`, `RunID`, `Cause`.

## Human-in-the-Loop (Pause and Resume)

A node pauses by emitting a request-input event and returning `workflow.ErrNodeInterrupted`. The run ends for this turn; the caller resumes by sending a `FunctionResponse` named `adk_request_input`.

### Handoff Mode (the reply becomes the node's output)

```go
ask := workflow.NewEmittingFunctionNode[any, any]("ask_name",
    func(ctx agent.Context, _ any, emit func(*session.Event) error) (any, error) {
        if err := emit(workflow.NewRequestInputEvent(ctx, session.RequestInput{
            InterruptID: "ask_name-" + ctx.InvocationID(), // Unique per run.
            Message:     "What's your name?",
        })); err != nil {
            return nil, err
        }
        return nil, workflow.ErrNodeInterrupted
    }, workflow.NodeConfig{})

greet := workflow.NewFunctionNode("greet", func(_ agent.Context, name string) (string, error) {
    return "Hello, " + name + "!", nil // The human's reply arrives here as input.
}, workflow.NodeConfig{})

wa, err := workflowagent.New(workflowagent.Config{
    Name:  "hitl_simple",
    Edges: workflow.Chain(workflow.Start, ask, greet),
})
```

### Re-entry Mode (the node re-runs and reads the reply)

```go
rerun := true
greet := workflow.NewEmittingFunctionNode[any, any]("greet",
    func(ctx agent.Context, _ any, emit func(*session.Event) error) (any, error) {
        reply, err := workflow.ResumeOrRequestInput(ctx, emit, session.RequestInput{
            InterruptID: "ask_name-" + ctx.InvocationID(),
            Message:     "What's your name?",
        })
        if err != nil {
            return nil, err // First pass: ErrNodeInterrupted pauses the run.
        }
        name, _ := reply.(string)
        return "Hello, " + name + "!", nil
    }, workflow.NodeConfig{RerunOnResume: &rerun})
```

### Resuming Programmatically

```go
// Turn 1: run until the pause and capture the interrupt ID.
var interruptID string
for ev, err := range r.Run(ctx, userID, sessionID, genai.NewContentFromText("hi", genai.RoleUser), agent.RunConfig{}) {
    if err != nil {
        return err
    }
    if ev.RequestedInput != nil {
        interruptID = ev.RequestedInput.InterruptID
    }
}

// Turn 2: answer the adk_request_input function call.
resume := &genai.Content{Role: genai.RoleUser, Parts: []*genai.Part{{
    FunctionResponse: &genai.FunctionResponse{
        ID:       interruptID,
        Name:     workflow.WorkflowInputFunctionCallName, // "adk_request_input"
        Response: map[string]any{"response": "Alice"},    // or {"payload": v}
    },
}}}
for ev, err := range r.Run(ctx, userID, sessionID, resume, agent.RunConfig{}) {
    if err != nil {
        return err
    }
    if ev.Output != nil {
        fmt.Println(ev.Output) // "Hello, Alice!" arrives in Output, not Content.
    }
}
```

`session.RequestInput` fields: `InterruptID` (correlation key; empty = UUID), `Message`, `ResponseSchema *jsonschema.Schema` (a mismatching reply yields `ErrInvalidResumeResponse` and the node keeps waiting), and `Payload any` (JSON-encodable). An answer that matches no waiting node yields `ErrNothingToResume`; a duplicate answer is a no-op.

HITL rules:

- Use a unique `InterruptID` per run (UUID or `name + "-" + ctx.InvocationID()`). The dev web UI skips prompts for IDs it already answered in the session.
- A handoff resume ignores concrete routes from the asker (successors are evaluated with no event). Only unconditional and `Default` edges fire. Route in a node after the asker, or use re-entry mode and emit `Routes` on the re-run.
- **Tool confirmation inside an AgentNode is not resumed by `workflowagent`** at v2.5.0: the confirmed tool never runs. Inside graphs, ask for approval with `RequestInput` instead of `RequireConfirmation`.
- **A dynamic node re-runs children completed before the first pause** once, on the first resume (later resumes hit the cache). Keep pre-pause children idempotent.
- Graph run state is rebuilt from session events. A custom `session.Service` must persist `Output`, `NodeInfo`, `RequestedInput`, `Routes`, `IsolationScope`, and `LongRunningToolIDs`. Changing the graph between pause and resume corrupts the resume.

## Reading Workflow Results

Function-node results are in `event.Output` with **no `Content`**; a loop that only prints `event.Content` text shows nothing for them. Every node's output event is yielded (intermediate nodes included, authored by the workflow's name), so the last one is the terminal result. LLM agent nodes produce `Content` (the runner strips the duplicate `Output` from the yielded copy).

```go
for ev, err := range r.Run(ctx, userID, sessionID, msg, agent.RunConfig{}) {
    if err != nil {
        return err
    }
    switch {
    case ev.Content != nil && ev.IsFinalResponse():
        for _, p := range ev.Content.Parts {
            if p.Text != "" && !p.Thought {
                fmt.Println(p.Text)
            }
        }
    case ev.Output != nil:
        fmt.Printf("%s output: %v\n", ev.Author, ev.Output)
    }
}
```

## Errors

| Error | When |
|---|---|
| `ErrDuplicateNodeName`, `ErrNoStartNode`, `ErrNodePointsToStart`, `ErrDuplicateEdge`, `ErrMultipleDefaultRoutes`, `ErrNodesNotReachable`, `ErrUnconditionalCycle`, `ErrUnsupportedFanIn`, `ErrSubWorkflowNameCollision` | Graph validation at construction |
| `ErrNodeFailed` (+ `*NodeRunError`) | A node failed after retries |
| `ErrNodeInterrupted`, `ErrNodeWaitingForOutput` | A node paused for human input |
| `ErrInputValidation` | Input failed a declared schema (not retried by default) |
| `ErrMultipleOutputs`, `ErrMultipleRoutingEvents`, `ErrMultipleTerminalOutputs` | Output/routing contract violations |
| `ErrInvalidRunNodeContext`, `ErrInvalidRunID`, `ErrOutputAlreadyDelegated` | `RunNode` misuse |
| `ErrInvalidResumeResponse`, `ErrNothingToResume` | Bad resume replies |

## Limitations at v2.5.0

- `workflowagent.New` calls `workflow.New` with no options, so `workflow.WithMaxConcurrency` and `workflow.WithStateSchema` are unreachable through the adapter.
- `NewEmittingFunctionNodeWithSchema` does not infer nil schemas despite its doc comment; pass schemas explicitly.
- The dynamic node output schema is not validated.
