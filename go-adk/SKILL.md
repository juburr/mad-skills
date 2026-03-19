---
name: go-adk
description: Guides development of AI agents using Google's Agent Development Kit
  (ADK) for Go. Use when creating agents, defining tools, orchestrating multi-agent
  workflows, integrating MCP servers, connecting remote A2A agents, or building
  agentic applications with ADK Go.
---

# ADK Go

Google's Agent Development Kit for Go (`google.golang.org/adk`) is a code-first toolkit for building AI agents. It is optimized for Gemini and model-agnostic via the `model.LLM` interface. Requires Go 1.24.4+.

```bash
go get google.golang.org/adk
```

## Key Imports

```go
import (
    "google.golang.org/adk/agent"                                  // Core agent interface
    "google.golang.org/adk/agent/llmagent"                         // LLM-powered agents
    "google.golang.org/adk/agent/remoteagent"                      // Remote A2A agents
    "google.golang.org/adk/agent/workflowagents/sequentialagent"   // Sequential orchestration
    "google.golang.org/adk/agent/workflowagents/parallelagent"     // Parallel orchestration
    "google.golang.org/adk/agent/workflowagents/loopagent"         // Loop orchestration
    "google.golang.org/adk/model/gemini"                           // Gemini model provider
    "google.golang.org/adk/runner"                                 // Agent runtime
    "google.golang.org/adk/session"                                // Session and state
    "google.golang.org/adk/tool"                                   // Tool interface
    "google.golang.org/adk/tool/functiontool"                      // Go functions as tools
    "google.golang.org/adk/tool/agenttool"                         // Agent-as-tool wrapper
    "google.golang.org/adk/tool/mcptoolset"                        // MCP server integration
    "google.golang.org/adk/tool/exitlooptool"                      // Break out of loops
    "google.golang.org/adk/tool/geminitool"                        // Gemini native tools
    "google.golang.org/adk/tool/loadartifactstool"                 // LLM-invoked artifact loading
    "google.golang.org/adk/tool/loadmemorytool"                    // LLM-invoked memory search
    "google.golang.org/adk/tool/preloadmemorytool"                 // Auto-injects memory per request
    "google.golang.org/adk/telemetry"                              // OpenTelemetry setup
    "google.golang.org/adk/plugin"                                 // Plugin system
    "google.golang.org/adk/plugin/retryandreflect"                 // Self-healing tool retries
    "google.golang.org/adk/plugin/functioncallmodifier"            // Rewrite tool schemas
    "google.golang.org/adk/plugin/loggingplugin"                   // Console event logger
    "google.golang.org/adk/cmd/launcher"                           // Launcher config
    "google.golang.org/adk/cmd/launcher/full"                      // All launcher modes (dev + prod)
    "google.golang.org/adk/cmd/launcher/prod"                      // Production launcher (no console, no web UI)
    "google.golang.org/genai"                                      // Google GenAI types
)
```

## Creating a Model

```go
// Gemini API (default)
model, err := gemini.NewModel(ctx, "gemini-2.5-flash", &genai.ClientConfig{
    APIKey: os.Getenv("GOOGLE_API_KEY"),
})

// Vertex AI
model, err := gemini.NewModel(ctx, "gemini-2.5-flash", &genai.ClientConfig{
    Project:  "my-project",
    Location: "us-central1",
    Backend:  genai.BackendVertexAI,
})
```

For OpenAI or custom providers, read `references/integrations.md`.

## Creating an Agent

The primary agent type is `llmagent`. It wraps an LLM with instructions, tools, and optional sub-agents.

```go
myAgent, err := llmagent.New(llmagent.Config{
    Name:        "assistant",
    Description: "Helpful coding assistant.",
    Model:       model,
    Instruction: "You are a helpful coding assistant. Help the user write Go code.",
    Tools:       []tool.Tool{myTool},
    GenerateContentConfig: &genai.GenerateContentConfig{
        Temperature: genai.Ptr[float32](0.7),
    },
})
```

### Key llmagent.Config Fields

| Field | Purpose |
|---|---|
| `Name` | Unique name within the agent tree. Cannot be `"user"`. |
| `Description` | One-line description used by parent agents for delegation decisions. |
| `Model` | `model.LLM` implementation (Gemini, custom, etc.) |
| `Instruction` | System prompt. Supports `{state_key}`, `{artifact.key}`, and `{key?}` (optional) substitution. |
| `GlobalInstruction` | Prepended to all sub-agent instructions. Same substitution syntax. |
| `InstructionProvider` | `func(agent.ReadonlyContext) (string, error)` for dynamic instructions. Note: `{key}` placeholders are **not** auto-injected when using a provider. |
| `Tools` | Slice of `tool.Tool` the agent can invoke. |
| `Toolsets` | Slice of `tool.Toolset` (e.g., `mcptoolset`) for dynamic tool discovery. |
| `SubAgents` | Child agents. Enables LLM-driven delegation via `transfer_to_agent`. |
| `DisallowTransferToParent` | Prevents sub-agent from delegating back to parent. Default `false`. |
| `DisallowTransferToPeers` | Prevents sub-agent from delegating to siblings. Default `false`. |
| `OutputKey` | Stores the agent's final text response in session state under this key. |
| `IncludeContents` | `IncludeContentsDefault` (send history) or `IncludeContentsNone` (current turn only). |
| `InputSchema` / `OutputSchema` | Structured I/O via `*genai.Schema`. Note: `OutputSchema` disables tool use and transfers. |
| `Before/AfterModelCallbacks` | Intercept or replace LLM requests/responses. Return non-nil `*model.LLMResponse` to skip the model call. |
| `Before/AfterToolCallbacks` | Intercept tool execution. `BeforeToolCallback` can return a result map to skip the tool. |
| `OnToolErrorCallbacks` | Handle tool errors. Can return a replacement result or propagate the error. |

For the complete config including all callback fields, read `references/api-reference.md`.

## Defining Tools

### FunctionTool

Wrap any Go function as an agent tool. Argument and result structs are auto-converted to JSON schemas.

```go
type WeatherArgs struct {
    City string `json:"city" jsonschema:"The city to get weather for."`
}
type WeatherResult struct {
    Report string `json:"report"`
}

func getWeather(ctx tool.Context, args WeatherArgs) (WeatherResult, error) {
    return WeatherResult{Report: "Sunny, 72F in " + args.City}, nil
}

weatherTool, err := functiontool.New(functiontool.Config{
    Name:        "get_weather",
    Description: "Gets the current weather for a city.",
}, getWeather)
```

### Tool Context

Inside a tool function, `tool.Context` provides access to state, artifacts, and agent transfer:

```go
func myTool(ctx tool.Context, args MyArgs) (MyResult, error) {
    val, _ := ctx.State().Get("user:preferences")      // Read state
    ctx.State().Set("temp:last_result", "value")        // Write state
    ctx.Actions().TransferToAgent = "support_agent"     // Transfer to another agent
    ctx.Actions().Escalate = true                       // Exit a loop
    return MyResult{}, nil
}
```

### MCP Toolset

Connect to MCP servers using the official Go MCP SDK (`github.com/modelcontextprotocol/go-sdk`):

```go
mcpTools, err := mcptoolset.New(mcptoolset.Config{
    Transport: &mcp.CommandTransport{Command: exec.Command("myserver")},
})

agent, err := llmagent.New(llmagent.Config{
    Name:     "mcp_agent",
    Model:    model,
    Toolsets: []tool.Toolset{mcpTools},
})
```

Supports `CommandTransport` (stdio), `StreamableClientTransport` (HTTPS), and in-memory transports. For HITL confirmation on any toolset (not just MCP), use `tool.WithConfirmation`. For full MCP and confirmation details, read `references/integrations.md`.

### AgentTool

Wrap an agent as a callable tool for explicit invocation (vs. LLM-driven delegation via `SubAgents`):

```go
import "google.golang.org/adk/tool/agenttool"

imageTool := agenttool.New(imageAgent, nil)

parentAgent, err := llmagent.New(llmagent.Config{
    Name:  "artist",
    Model: model,
    Tools: []tool.Tool{imageTool},
})
```

### Built-in Gemini Tools

```go
agent, err := llmagent.New(llmagent.Config{
    Name:  "search_agent",
    Model: model,
    Tools: []tool.Tool{geminitool.GoogleSearch{}},
})
```

### Memory and Artifact Tools

| Tool | Behavior | Constructor |
|---|---|---|
| `loadartifactstool` | LLM-invoked. Lists available artifacts and loads content on request. | `loadartifactstool.New()` |
| `loadmemorytool` | LLM-invoked. Searches memory by query, returns matching entries. | `loadmemorytool.New()` |
| `preloadmemorytool` | **Auto-runs per LLM request.** Searches memory using the user's query and injects relevant past conversations into system instructions. No LLM tool call required. | `preloadmemorytool.New()` |

These tools require backing services in `runner.Config`. Memory tools fail with `"memory service is not set"` if `MemoryService` is nil; artifact tools panic without `ArtifactService`.

```go
agent, err := llmagent.New(llmagent.Config{
    Name:  "memory_agent",
    Model: model,
    Tools: []tool.Tool{
        preloadmemorytool.New(),   // Auto-injects memory context
        loadmemorytool.New(),      // LLM can search for more
        loadartifactstool.New(),   // LLM can load artifacts
    },
})

// Runner must have backing services configured:
r, _ := runner.New(runner.Config{
    Agent:           agent,
    SessionService:  session.InMemoryService(),
    MemoryService:   memory.InMemoryService(),    // Required for memory tools
    ArtifactService: artifact.InMemoryService(),  // Required for artifact tools
})
```

## Orchestration Patterns

ADK provides three workflow agent types plus custom agents for arbitrary control flow.

| Pattern | Agent Type | Use When |
|---|---|---|
| **Sequential Pipeline** | `sequentialagent.New()` | Steps run in fixed order. Data flows via `OutputKey` + `{placeholder}`. |
| **Parallel Fan-Out** | `parallelagent.New()` | Independent tasks run concurrently. Gather results with a downstream synthesizer. |
| **Iterative Loop** | `loopagent.New()` | Repeat until `MaxIterations` or `Escalate = true`. Critic/refiner pattern. |
| **Dynamic Delegation** | `llmagent` with `SubAgents` | LLM routes to sub-agents via `transfer_to_agent` based on descriptions. |
| **Agent-as-Tool** | `agenttool.New()` | Parent explicitly invokes child agents as tools. |
| **Custom Agent** | `agent.New()` with `Run` func | Arbitrary Go control flow: conditional branching, dynamic planning loops. |

### Quick Example: Sequential Pipeline

```go
step1, _ := llmagent.New(llmagent.Config{
    Name: "Fetch", Model: m, OutputKey: "data",
    Instruction: "Fetch the requested information.",
})
step2, _ := llmagent.New(llmagent.Config{
    Name: "Process", Model: m,
    Instruction: "Process: {data}",
})

pipeline, _ := sequentialagent.New(sequentialagent.Config{
    AgentConfig: agent.Config{
        Name:      "Pipeline",
        SubAgents: []agent.Agent{step1, step2},
    },
})
```

### Quick Example: Parallel Fan-Out / Gather

```go
api1, _ := llmagent.New(llmagent.Config{Name: "API1", Model: m, OutputKey: "api1_data"})
api2, _ := llmagent.New(llmagent.Config{Name: "API2", Model: m, OutputKey: "api2_data"})

gather, _ := parallelagent.New(parallelagent.Config{
    AgentConfig: agent.Config{Name: "Gather", SubAgents: []agent.Agent{api1, api2}},
})

synth, _ := llmagent.New(llmagent.Config{
    Name: "Synth", Model: m,
    Instruction: "Combine {api1_data} and {api2_data}.",
})

workflow, _ := sequentialagent.New(sequentialagent.Config{
    AgentConfig: agent.Config{Name: "FanOutGather", SubAgents: []agent.Agent{gather, synth}},
})
```

For all patterns with complete code examples (including loop/critic-refiner, dynamic delegation, custom planning loops, and composite workflows), read `references/orchestration.md`.

## State Management

State is scoped by key prefix:

| Prefix | Scope | Persistence |
|---|---|---|
| `app:` | All users, all sessions | Permanent |
| `user:` | Current user, all sessions | Permanent |
| `temp:` | Current invocation only | Discarded after invocation |
| *(none)* | Current session | Session lifetime |

### OutputKey and Instruction Substitution

`OutputKey` stores an agent's final text response in session state. `{key}` placeholders in `Instruction` are auto-replaced with state values:

```go
step1, _ := llmagent.New(llmagent.Config{
    Name: "Researcher", Model: m, OutputKey: "research",
    Instruction: "Research the topic: {topic}",
})
step2, _ := llmagent.New(llmagent.Config{
    Name: "Writer", Model: m,
    Instruction: "Write a summary based on: {research}",
})
```

Create sessions with initial state:

```go
resp, _ := sessionService.Create(ctx, &session.CreateRequest{
    AppName: "my_app",
    UserID:  "user1",
    State:   map[string]any{"topic": "quantum computing"},
})
```

## Running Agents

### Runner Pattern

```go
sessionService := session.InMemoryService()
resp, _ := sessionService.Create(ctx, &session.CreateRequest{
    AppName: "my_app", UserID: "user1",
})

r, _ := runner.New(runner.Config{
    AppName:        "my_app",
    Agent:          myAgent,
    SessionService: sessionService,
})

input := genai.NewContentFromText("Hello!", genai.RoleUser)
for event, err := range r.Run(ctx, "user1", resp.Session.ID(), input, agent.RunConfig{}) {
    if err != nil {
        log.Fatal(err)
    }
    if event.IsFinalResponse() && event.Content != nil {
        for _, part := range event.Content.Parts {
            if part.Text != "" {
                fmt.Println(part.Text)
            }
        }
    }
}
```

### Launcher Pattern (Dev/Prod Servers)

```go
config := &launcher.Config{AgentLoader: agent.NewSingleLoader(myAgent)}
// For multiple agents: agent.NewMultiLoader(rootAgent, agentB, agentC)
l := full.NewLauncher()       // Dev: includes console + web UI + API + A2A
// l := prod.NewLauncher()    // Prod: REST API + A2A only (no console, no web UI)
if err := l.Execute(ctx, config, os.Args[1:]); err != nil {
    log.Fatalf("Run failed: %v\n\n%s", err, l.CommandLineSyntax())
}
```

Run modes via CLI args:

```bash
go run main.go                       # Console mode
go run main.go web api webui         # Web UI at localhost:8080 (dev only)
go run main.go web api a2a           # REST API + A2A server
```

## Plugins

Plugins provide cross-cutting lifecycle hooks that apply to all agents in a runner. Attach via `runner.PluginConfig`.

```go
retryPlugin := retryandreflect.MustNew(
    retryandreflect.WithMaxRetries(3),
    retryandreflect.WithTrackingScope(retryandreflect.Invocation),
)

r, _ := runner.New(runner.Config{
    AppName:        "my_app",
    Agent:          myAgent,
    SessionService: sessionService,
    PluginConfig: runner.PluginConfig{
        Plugins: []*plugin.Plugin{retryPlugin},
    },
})
```

### Built-in Plugins

| Plugin | Purpose | Constructor |
|---|---|---|
| `retryandreflect` | Self-healing tool error recovery. Intercepts tool failures, provides reflection guidance to the LLM, and retries. | `retryandreflect.New(opts...)` |
| `functioncallmodifier` | Rewrites tool schemas and descriptions before model calls. Use when models hallucinate arguments or you need per-environment policy. | `functioncallmodifier.NewPlugin(cfg)` |
| `loggingplugin` | Prints all critical events to console for terminal-based debugging. | `loggingplugin.New(name)` |

### Plugin Lifecycle Hooks

Plugins can intercept at every phase: user message, before/after run, before/after agent, before/after model, before/after tool, and on model/tool errors. For the full `plugin.Config` type with all callback signatures, read `references/api-reference.md`.

## Telemetry (OpenTelemetry)

ADK supports OpenTelemetry tracing and logging. Initialize providers, set them as globals, and shut down on exit:

```go
import "google.golang.org/adk/telemetry"

providers, err := telemetry.New(ctx,
    telemetry.WithOtelToCloud(true),                // Export to GCP
    telemetry.WithResource(otelResource),            // Custom OTel resource
)
if err != nil { log.Fatal(err) }
defer providers.Shutdown(context.Background())
providers.SetGlobalOtelProviders()
```

The launcher's web mode auto-initializes telemetry when `--otel_to_cloud` is set. For standalone runner usage, initialize manually as shown above. For the full list of telemetry options, read `references/api-reference.md`.

## A2A Remote Agents

### Consuming a Remote Agent (Client)

```go
remoteAgent, err := remoteagent.NewA2A(remoteagent.A2AConfig{
    Name:            "prime_agent",
    Description:     "Checks if numbers are prime.",
    AgentCardSource: "http://localhost:8001",
})

rootAgent, _ := llmagent.New(llmagent.Config{
    Name:      "root",
    Model:     model,
    SubAgents: []agent.Agent{localAgent, remoteAgent},
})
```

### Exposing an Agent (Server)

Use the full launcher with `web api a2a` CLI args:

```go
config := &launcher.Config{
    AgentLoader:    agent.NewSingleLoader(myAgent),
    SessionService: session.InMemoryService(),
}
l := full.NewLauncher()
if err := l.Execute(ctx, config, []string{"web", "--port", "8001", "api", "a2a", "--a2a_agent_url", "http://localhost:8001"}); err != nil {
    log.Fatal(err)
}
```

```bash
go run main.go web --port 8001 api a2a --a2a_agent_url http://localhost:8001
```

The agent card is auto-served at `http://localhost:8001/.well-known/agent-card.json`.

## Custom Agents

For control flow beyond what workflow agents provide (conditional branching, dynamic planning, reflection loops), implement the `Run` function directly:

```go
customAgent, _ := agent.New(agent.Config{
    Name:      "Orchestrator",
    SubAgents: []agent.Agent{planner, executor, reflector},
    Run: func(ctx agent.InvocationContext) iter.Seq2[*session.Event, error] {
        return func(yield func(*session.Event, error) bool) {
            // Run planner
            for event, err := range planner.Run(ctx) {
                if err != nil { yield(nil, err); return }
                if !yield(event, nil) { return }
            }

            // Read state, branch conditionally
            plan, _ := ctx.Session().State().Get("plan")
            // ... dispatch to executor, reflect, re-plan ...
        }
    },
})
```

For the complete custom agent pattern (plan-execute-reflect loop), read `references/orchestration.md`.

## Known Gotchas

- **Nested loop escalation propagation ([#522](https://github.com/google/adk-go/issues/522)).** `Escalate = true` inside a nested `loopagent` can propagate upward and stop the entire parent pipeline, not just the inner loop. As of v0.6.0, `sequentialagent` no longer depends on `loopagent` internally (PR #611), which mitigates the most common trigger. However, test nested loop exit behavior explicitly when composing multiple `loopagent` layers.
- **OutputSchema disables tools.** Setting `OutputSchema` on an `llmagent` disables tool use and agent transfers. Use it only on leaf agents that produce structured final output.
- **FunctionTool input must be a struct.** `functiontool.New` validates that the args type is a struct. Primitive types or maps will be rejected.
- **Pre-v1 API instability.** ADK Go is pre-v1 (verified against v0.6.0). Pin your module version in `go.mod` and prefer the pkg.go.dev reference for the exact version you target.
- **Parallel agent input.** In fan-out patterns, verify sub-agents receive required context. Prefer injecting data via session state (`OutputKey` + `{placeholder}`) rather than relying on conversation history propagation.
- **OutputKey overwrite during tool calls ([#577](https://github.com/google/adk-go/issues/577)).** Use a unique `OutputKey` for each agent in a pipeline. When an agent uses tools, intermediate function-call/response events can overwrite a shared `OutputKey` with an empty string because the guard condition triggers on non-partial events that have no text content. A fix switching to `event.IsFinalResponse()` gating is in progress (PR #578).
- **Artifact tool panic when misconfigured ([#283](https://github.com/google/adk-go/issues/283)).** `loadartifactstool` can panic with a nil pointer dereference if added to an agent without configuring `ArtifactService` in the runner. Always set `ArtifactService` in `runner.Config` when using artifact tools, and validate required services are non-nil at startup.
- **Nil RunConfig panic when embedding ADK ([#586](https://github.com/google/adk-go/issues/586)).** `runconfig.FromContext(ctx)` returns nil if `RunConfig` is never inserted into the context chain, causing a nil pointer dereference in `base_flow.go`. This affects teams that embed ADK into existing Go services with custom runners or invocation contexts. Guard against nil returns or ensure `RunConfig` is injected into the context before invoking agent flows.
- **Agent identity auto-injection (v0.6.0+).** Agent `Name` and `Description` are now automatically injected into LLM system prompts. If your `Instruction` already includes identity text (e.g., "You are AgentX"), you may get duplication. Remove manual identity from instructions to avoid redundancy.

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/orchestration.md` | All orchestration patterns with complete code: pipeline, fan-out/gather, critic/refiner loop, dynamic delegation, custom planning loops, composite workflows | Designing multi-agent workflows or implementing a specific pattern |
| `references/api-reference.md` | Complete types: `llmagent.Config`, all callback signatures, `session.Event`, `EventActions`, `tool.Context`, `genai.GenerateContentConfig`, `runner.Config`, `plugin.Config`, built-in plugin configs, telemetry options | Looking up specific field names, types, or callback signatures |
| `references/integrations.md` | MCP toolset (all transports, filtering, HITL), OpenAI integration status, custom `model.LLM` providers, Vertex AI config | Connecting to MCP servers, using non-Gemini models, or writing a custom provider |
