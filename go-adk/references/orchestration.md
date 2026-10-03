# Orchestration Patterns

Multi-agent orchestration with workflow agents, LLM-driven delegation (including the v2 collaboration modes), and custom agents, with full code examples. Verified against `google.golang.org/adk/v2` v2.5.0. Graph-based workflows (package `workflow`) are covered separately; this file covers everything built from agents.

**Import convention:** Pattern 1 shows the full import block. Later patterns show only the new imports they introduce. All patterns assume `m` is a `model.LLM` and the common imports from Pattern 1 plus `tool`, `functiontool`, and `genai`.

## Choosing an Approach

| Situation | Use |
|---|---|
| Fixed sequence, fan-out, or refinement loop of agents communicating via `OutputKey` + `{key}` | Sequential / parallel / loop agents (Patterns 1-3) |
| LLM decides which specialist handles the conversation; the specialist keeps control until it hands back | Chat sub-agents + `transfer_to_agent` (Pattern 4) |
| LLM coordinator calls specialists that return results automatically (lookup, slot-filling) | `Mode: llmagent.ModeSingleTurn` / `llmagent.ModeTask` sub-agents (Pattern 5) |
| Arbitrary Go control around whole agents, no checkpointing or HITL resume needed | Custom `agent.New` with `Run` (Pattern 6) |
| Deterministic steps mixed with LLM steps, typed hand-offs, per-step retry/timeout, HITL pause/resume, data-dependent loops with checkpointing | Graph workflow (`workflow` + `workflowagent`) |
| Cross-service agents | Remote A2A agents in any of the above (Pattern 8) |

Collaboration modes are for **LLM-decided** delegation; graph workflows are for **code-decided** flow. Sequential/parallel/loop agents are not deprecated in Go and remain the simplest option; `sequentialagent` is the only workflow agent that supports `RunLive` pipelines.

## Pattern 1: Sequential Pipeline

Agents execute in fixed order. Each agent's output flows to the next via `OutputKey` and `{placeholder}` substitution in instructions.

```go
import (
    "google.golang.org/adk/v2/agent"
    "google.golang.org/adk/v2/agent/llmagent"
    "google.golang.org/adk/v2/agent/workflowagents/sequentialagent"
)

codeWriter, _ := llmagent.New(llmagent.Config{
    Name:        "CodeWriter",
    Model:       m,
    Instruction: "Write Go code that implements: {spec}",
    OutputKey:   "code",
})
codeReviewer, _ := llmagent.New(llmagent.Config{
    Name:        "CodeReviewer",
    Model:       m,
    Instruction: "Review this Go code for bugs and style issues:\n{code}",
    OutputKey:   "review",
})
codeRefactorer, _ := llmagent.New(llmagent.Config{
    Name:        "CodeRefactorer",
    Model:       m,
    Instruction: "Refactor the code based on review feedback.\nCode: {code}\nReview: {review}",
    OutputKey:   "final_code",
})

pipeline, _ := sequentialagent.New(sequentialagent.Config{
    AgentConfig: agent.Config{
        Name:      "CodePipeline",
        SubAgents: []agent.Agent{codeWriter, codeReviewer, codeRefactorer},
    },
})
```

**How it works:** `sequentialagent` runs each sub-agent in order with the same invocation. When `CodeWriter` finishes, its final text is stored in `state["code"]`; `CodeReviewer` sees `{code}` replaced with that value. Since v2.4.0, only a final, non-thought text response writes `OutputKey` (tool-call events no longer overwrite it). A missing non-optional `{key}` is an error; use `{key?}` for optional keys.

## Pattern 2: Parallel Fan-Out / Gather

Independent tasks run concurrently. A downstream agent synthesizes results.

```go
import "google.golang.org/adk/v2/agent/workflowagents/parallelagent"

flightResearcher, _ := llmagent.New(llmagent.Config{
    Name:        "FlightResearcher",
    Model:       m,
    Instruction: "Find flights from {origin} to {destination} on {date}.",
    OutputKey:   "flights",
})
hotelResearcher, _ := llmagent.New(llmagent.Config{
    Name:        "HotelResearcher",
    Model:       m,
    Instruction: "Find hotels in {destination} for {date}.",
    OutputKey:   "hotels",
})

gather, _ := parallelagent.New(parallelagent.Config{
    AgentConfig: agent.Config{
        Name:      "TravelResearch",
        SubAgents: []agent.Agent{flightResearcher, hotelResearcher},
    },
})

tripSynthesizer, _ := llmagent.New(llmagent.Config{
    Name:        "TripSynthesizer",
    Model:       m,
    Instruction: "Create a trip plan combining:\nFlights: {flights}\nHotels: {hotels}",
})

tripWorkflow, _ := sequentialagent.New(sequentialagent.Config{
    AgentConfig: agent.Config{
        Name:      "TravelPlanner",
        SubAgents: []agent.Agent{gather, tripSynthesizer},
    },
})
```

**How it works:** `parallelagent` runs sub-agents concurrently on separate branches (`<parent>.<sub>`), so their LLM histories are isolated. Each writes its own `OutputKey`. Since v2.1.0, an early stop cancels sub-agents and waits for their teardown before returning. Inject inputs through session state rather than relying on conversation history.

## Pattern 3: Critic / Refiner Loop

Sub-agents run repeatedly until a quality bar is met.

```go
import (
    "google.golang.org/adk/v2/agent/workflowagents/loopagent"
    "google.golang.org/adk/v2/tool/exitlooptool"
)

generator, _ := llmagent.New(llmagent.Config{
    Name:        "DraftWriter",
    Model:       m,
    Instruction: "Write a short article about {topic}. If {criticism?} is present, revise accordingly.",
    OutputKey:   "draft",
})

exitTool, _ := exitlooptool.New()

critic, _ := llmagent.New(llmagent.Config{
    Name:  "Critic",
    Model: m,
    Instruction: `Review the draft: {draft}
Evaluate for accuracy, clarity, and completeness.
If the draft is good enough, call the exit_loop tool.
Otherwise, provide specific criticism for improvement.`,
    OutputKey: "criticism",
    Tools:     []tool.Tool{exitTool},
})

refinementLoop, _ := loopagent.New(loopagent.Config{
    MaxIterations: 5, // Always bound it; 0 is unbounded (see below).
    AgentConfig: agent.Config{
        Name:      "RefinementLoop",
        SubAgents: []agent.Agent{generator, critic},
    },
})
```

**Termination conditions (any one exits the loop):**
1. `MaxIterations` is reached.
2. A sub-agent calls `exit_loop` (sets `Escalate = true` and `SkipSummarization = true`).
3. A tool sets `ctx.Actions().Escalate = true` programmatically.
4. The consumer stops iterating the `Run` stream.

**Errors do not stop a loop.** At v2.5.0 `loopagent` yields a sub-agent's error and starts the next iteration. With `MaxIterations: 0` and a persistent failure (bad model name, quota, auth), it calls the model indefinitely for as long as the consumer keeps reading, and the console and SSE launchers keep reading (upstream issue #1683). Always set a finite `MaxIterations`, and stop iterating `Run` on the first error in your own consumers.

**Custom exit tool:**

```go
type ExitArgs struct{}
type ExitResult struct {
    Status string `json:"status"`
}

approveTool, _ := functiontool.New(functiontool.Config{
    Name:        "approve_draft",
    Description: "Call when the draft meets quality standards.",
}, func(ctx agent.Context, _ ExitArgs) (ExitResult, error) {
    ctx.Actions().Escalate = true
    ctx.Actions().SkipSummarization = true // Avoid an extra summarization model turn.
    return ExitResult{Status: "approved"}, nil
})
```

### Nested Loops (Issue #522, Still Present at v2.5.0)

An inner `loopagent` re-yields the escalating event unchanged, so an **enclosing** loop also sees `Escalate` and exits. Wrap the inner loop to clear the flag on forwarded events:

```go
import (
    "iter"

    "google.golang.org/adk/v2/session"
)

func stopEscalation(name string, inner agent.Agent) (agent.Agent, error) {
    return agent.New(agent.Config{
        Name:      name,
        SubAgents: []agent.Agent{inner},
        Run: func(ctx agent.InvocationContext) iter.Seq2[*session.Event, error] {
            return func(yield func(*session.Event, error) bool) {
                for ev, err := range inner.Run(ctx) {
                    if ev != nil && ev.Actions.Escalate {
                        cp := *ev
                        cp.Actions.Escalate = false // Inner loop already stopped; keep the outer one going.
                        ev = &cp
                    }
                    if !yield(ev, err) {
                        return
                    }
                }
            }
        },
    })
}
```

Alternatively, express nested loops as a graph back-edge or a Go `for` loop in a dynamic workflow node.

## Pattern 4: Dynamic Delegation (Chat Mode)

An LLM coordinator routes the conversation to specialist sub-agents with `transfer_to_agent`, based on their `Description` fields. Sub-agents with no `Mode` (or `llmagent.ModeChat`) behave this way.

```go
billingAgent, _ := llmagent.New(llmagent.Config{
    Name:        "Billing",
    Model:       m,
    Description: "Handles billing inquiries, payment issues, and invoice questions.",
    Instruction: "You are a billing specialist. Help with payment and invoice issues.",
})
supportAgent, _ := llmagent.New(llmagent.Config{
    Name:        "Support",
    Model:       m,
    Description: "Handles technical support, troubleshooting, and bug reports.",
    Instruction: "You are a tech support specialist. Help diagnose and fix issues.",
})

coordinator, _ := llmagent.New(llmagent.Config{
    Name:        "HelpDesk",
    Model:       m,
    Description: "Main help desk coordinator.",
    Instruction: "Route user requests to the appropriate specialist agent.",
    SubAgents:   []agent.Agent{billingAgent, supportAgent},
})
```

**How it works:** ADK adds a `transfer_to_agent` tool to the coordinator. When the LLM calls it with `{"agent_name": "Billing"}`, control moves to Billing, which keeps the conversation until it transfers back (or to a peer).

| Field | Default | Effect |
|---|---|---|
| `DisallowTransferToParent` | `false` | Prevents a sub-agent from delegating back to its parent |
| `DisallowTransferToPeers` | `false` | Prevents a sub-agent from delegating to siblings |

## Pattern 5: Collaboration Modes (single_turn and task)

`llmagent.Config.Mode` changes how a parent reaches a sub-agent. Sub-agents with `ModeSingleTurn` or `ModeTask` are **not** `transfer_to_agent` targets; instead the parent gets a function tool **named after the sub-agent**, and control returns to the parent automatically.

```go
weatherChecker, _ := llmagent.New(llmagent.Config{
    Name:        "weather_checker",
    Model:       m,
    Description: "Looks up current weather for the user or a named place.",
    Mode:        llmagent.ModeSingleTurn, // Autonomous; no user interaction.
    Tools:       []tool.Tool{geocodeTool, getWeatherTool},
    Instruction: "Geocode the location, call get_weather, and answer in one sentence.",
})

flightBooker, _ := llmagent.New(llmagent.Config{
    Name:         "flight_booker",
    Model:        m,
    Description:  "Books a flight given an origin, destination, and date.",
    Mode:         llmagent.ModeTask,  // May ask the user clarifying questions.
    InputSchema:  flightInputSchema,  // *genai.Schema: the delegation tool's parameters.
    OutputSchema: flightResultSchema, // *genai.Schema: finish_task's parameters.
    Tools:        []tool.Tool{searchFlightsTool, bookFlightTool},
    Instruction:  "Search flights, pick the cheapest, book it, then return the FlightResult.",
})

travelPlanner, _ := llmagent.New(llmagent.Config{ // Root: leave Mode unset (chat).
    Name:        "travel_planner",
    Model:       m,
    Description: "Plans trips by delegating to specialists.",
    Instruction: "For weather, delegate to weather_checker. For bookings, gather origin, destination, and date, then delegate to flight_booker.",
    SubAgents:   []agent.Agent{weatherChecker, flightBooker},
})
```

| Sub-agent `Mode` | Parent reaches it via | Talks to user | Result returns |
|---|---|---|---|
| unset / `ModeChat` | `transfer_to_agent` | Yes | When it transfers back |
| `ModeSingleTurn` | Tool named after the sub-agent | No | Tool result `{"result": <final text or parsed OutputSchema object>}` |
| `ModeTask` | Tool named after the sub-agent | Yes (multi-turn) | When it calls its auto-injected `finish_task` tool |

**Details:**

- The delegation tool's parameters are the sub-agent's `InputSchema`, or `{"request": string}` by default. The sub-agent receives the **whole args map as JSON text** (e.g. `{"request":"weather in Zurich"}`); write instructions that expect that shape.
- `finish_task` parameters mirror the task agent's `OutputSchema` (non-object schemas are wrapped under `result`; default `{"result": string}`). Args are validated; on failure the model is asked to retry.
- Task agents run in an **isolated history** keyed by the delegation call ID (`Event.IsolationScope`). The coordinator never sees the task's internal chatter, and follow-up user messages are routed into the open task until it finishes.
- **The root LLM agent must be chat mode.** A root with `ModeTask` or `ModeSingleTurn` fails with `root agent X must be a chat LlmAgent`.
- An agent with no declared `Mode` is resolved per placement: chat as a root or sub-agent, single_turn as a graph node. Declare `Mode` explicitly when one agent instance is reused in several places.
- `task_completed` is unrelated: it is a tool `sequentialagent` injects only during `RunLive`.

**Single-turn vs. AgentTool:** single_turn sub-agents keep the specialist's tool calls in the parent session's history, and the repo recommends them over the older `agenttool` pattern. Use `agenttool.New(a, &agenttool.Config{SkipSummarization: ...})` when the child should run in a **separate in-memory session** (its events never enter the parent session). The child gets a copy of the parent's state, but its state changes are **not** written back (return data through the tool result), and it runs **without the parent's runner plugins**, so plugin-based logging, metrics, and guardrails do not see its calls. Since v2.5.0, `agenttool` children share the parent's artifact store.

## Pattern 6: Custom Agent with Planning Loop

For control flow beyond workflow agents, implement the `Run` function. `agent.Config.Run` keeps its v1 signature, `func(agent.InvocationContext) iter.Seq2[*session.Event, error]`. Pass `ctx` straight to sub-agents' `Run`; each agent re-binds itself to the context.

```go
import (
    "encoding/json"
    "fmt"
    "iter"

    "google.golang.org/adk/v2/agent"
    "google.golang.org/adk/v2/agent/llmagent"
    "google.golang.org/adk/v2/model"
    "google.golang.org/adk/v2/session"
    "google.golang.org/genai"
)

type PlanStep struct {
    Agent string `json:"agent"`
    Input string `json:"input"`
}

type PlanExecuteReflectAgent struct {
    planner   agent.Agent
    reflector agent.Agent
    executors map[string]agent.Agent
    maxCycles int
}

func (a *PlanExecuteReflectAgent) Run(ctx agent.InvocationContext) iter.Seq2[*session.Event, error] {
    return func(yield func(*session.Event, error) bool) {
        state := ctx.Session().State()
        for cycle := 0; cycle < a.maxCycles; cycle++ {
            // 1. Plan
            for event, err := range a.planner.Run(ctx) {
                if err != nil {
                    yield(nil, fmt.Errorf("planner failed: %w", err))
                    return
                }
                if !yield(event, nil) {
                    return
                }
            }

            // 2. Parse plan from state
            rawPlan, _ := state.Get("plan")
            planStr, ok := rawPlan.(string)
            if !ok {
                yield(nil, fmt.Errorf("plan not found in state"))
                return
            }
            var steps []PlanStep
            if err := json.Unmarshal([]byte(planStr), &steps); err != nil {
                yield(nil, fmt.Errorf("invalid plan JSON: %w", err))
                return
            }

            // 3. Execute each step
            var results []string
            for _, step := range steps {
                executor, exists := a.executors[step.Agent]
                if !exists {
                    yield(nil, fmt.Errorf("unknown executor: %s", step.Agent))
                    return
                }
                if err := state.Set("step_input", step.Input); err != nil {
                    yield(nil, err)
                    return
                }
                for event, err := range executor.Run(ctx) {
                    if err != nil {
                        yield(nil, fmt.Errorf("executor %s failed: %w", step.Agent, err))
                        return
                    }
                    if !yield(event, nil) {
                        return
                    }
                }
                if r, ok := mustGet(state, "step_result").(string); ok {
                    results = append(results, r)
                }
            }

            // 4. Store results for the reflector
            resultsJSON, _ := json.Marshal(results)
            if err := state.Set("results", string(resultsJSON)); err != nil {
                yield(nil, err)
                return
            }

            // 5. Reflect
            for event, err := range a.reflector.Run(ctx) {
                if err != nil {
                    yield(nil, fmt.Errorf("reflector failed: %w", err))
                    return
                }
                if !yield(event, nil) {
                    return
                }
            }

            // 6. Stop, or feed guidance to the next planning cycle
            verdict, _ := mustGet(state, "verdict").(string)
            if verdict == "done" {
                return
            }
            if err := state.Set("guidance", verdict); err != nil {
                yield(nil, err)
                return
            }
        }
    }
}

func mustGet(s session.State, key string) any {
    v, _ := s.Get(key)
    return v
}

func NewPlanExecuteReflect(m model.LLM, executors map[string]agent.Agent) (agent.Agent, error) {
    planner, err := llmagent.New(llmagent.Config{
        Name:  "Planner",
        Model: m,
        Instruction: `Given the task: {task}
Previous results (if any): {results?}
Reflector guidance (if any): {guidance?}
Output a JSON array of steps: [{"agent": "name", "input": "description"}]`,
        OutputKey: "plan",
        GenerateContentConfig: &genai.GenerateContentConfig{
            ResponseMIMEType: "application/json",
        },
    })
    if err != nil {
        return nil, err
    }
    reflector, err := llmagent.New(llmagent.Config{
        Name:  "Reflector",
        Model: m,
        Instruction: `Task: {task}
Results: {results?}
Are the results complete and correct?
If yes, output exactly: done
If no, output guidance for the planner to improve.`,
        OutputKey: "verdict",
    })
    if err != nil {
        return nil, err
    }

    subAgents := []agent.Agent{planner, reflector}
    for _, e := range executors {
        subAgents = append(subAgents, e)
    }
    orchestrator := &PlanExecuteReflectAgent{
        planner:   planner,
        reflector: reflector,
        executors: executors,
        maxCycles: 3,
    }
    return agent.New(agent.Config{
        Name:      "PlanExecuteReflect",
        SubAgents: subAgents,
        Run:       orchestrator.Run,
    })
}
```

**Usage:**

```go
researcher, _ := llmagent.New(llmagent.Config{
    Name: "researcher", Model: m,
    Instruction: "Research: {step_input}", OutputKey: "step_result",
})
coder, _ := llmagent.New(llmagent.Config{
    Name: "coder", Model: m,
    Instruction: "Write code for: {step_input}", OutputKey: "step_result",
})

planAgent, _ := NewPlanExecuteReflect(m, map[string]agent.Agent{
    "researcher": researcher,
    "coder":      coder,
})
```

**Custom agent rules:**

- Never yield `(nil, nil)`: since v2.3.0 the runner stops with `adk: agent "X" yielded a nil event`.
- Build your own events with `session.NewEvent(ctx, ctx.InvocationID())` (the v2 signature takes a context first) and yield them; never append to the session directly.
- A custom agent cannot call `workflow.RunNode`; use a dynamic graph node when you need checkpointed children or HITL resume.

## Pattern 7: Composite Workflows

Workflow agents nest freely.

```go
spec, _ := llmagent.New(llmagent.Config{
    Name: "SpecWriter", Model: m, OutputKey: "spec",
    Instruction: "Write a spec for: {task}",
})
coder, _ := llmagent.New(llmagent.Config{
    Name: "Coder", Model: m, OutputKey: "code",
    Instruction: "Implement: {spec}",
})
codePipeline, _ := sequentialagent.New(sequentialagent.Config{
    AgentConfig: agent.Config{Name: "CodePipeline", SubAgents: []agent.Agent{spec, coder}},
})

security, _ := llmagent.New(llmagent.Config{
    Name: "SecurityReview", Model: m, OutputKey: "security",
    Instruction: "Security review:\n{code}",
})
perf, _ := llmagent.New(llmagent.Config{
    Name: "PerfReview", Model: m, OutputKey: "perf",
    Instruction: "Performance review:\n{code}",
})
reviews, _ := parallelagent.New(parallelagent.Config{
    AgentConfig: agent.Config{Name: "ParallelReviews", SubAgents: []agent.Agent{security, perf}},
})

reviser, _ := llmagent.New(llmagent.Config{
    Name: "Reviser", Model: m, OutputKey: "code",
    Instruction: "Revise code based on:\nSecurity: {security}\nPerf: {perf}\nCode: {code}",
})
checkerExit, _ := exitlooptool.New()
checker, _ := llmagent.New(llmagent.Config{
    Name: "Checker", Model: m, OutputKey: "check",
    Instruction: "Check if revisions address all concerns. Call exit_loop if satisfactory.",
    Tools: []tool.Tool{checkerExit},
})
revisionLoop, _ := loopagent.New(loopagent.Config{
    MaxIterations: 3,
    AgentConfig:   agent.Config{Name: "RevisionLoop", SubAgents: []agent.Agent{reviser, checker}},
})

fullWorkflow, _ := sequentialagent.New(sequentialagent.Config{
    AgentConfig: agent.Config{
        Name:      "FullCodeWorkflow",
        SubAgents: []agent.Agent{codePipeline, reviews, revisionLoop},
    },
})
```

A composite agent wrapped as a node in a **graph** workflow produces no node output (its successor receives `nil`); read its results from state instead.

## Pattern 8: Remote Agents in Orchestration

Remote A2A agents are used like any other agent.

```go
import remoteagent "google.golang.org/adk/v2/agent/remoteagent/v2"

testRunner, _ := remoteagent.NewA2A(remoteagent.A2AConfig{
    Name:              "TestRunner",
    Description:       "Runs test suites and reports results.",
    AgentCardProvider: remoteagent.NewAgentCardProvider("http://localhost:8001"),
})

pipeline, _ := sequentialagent.New(sequentialagent.Config{
    AgentConfig: agent.Config{
        Name:      "CodeAndTest",
        SubAgents: []agent.Agent{coder, testRunner},
    },
})
```

A fetched agent card must advertise interface URLs with the same origin as the URL it was fetched from, using `https` (or `http` on loopback); otherwise `ErrUntrustedCardInterface`. A remote peer's `transfer_to_agent` request is ignored unless `AllowTransferToAgent: true`.

## State Flow Cheat Sheet

```
OutputKey="data"       ->  state["data"] = agent's final text response
{data} in Instruction  ->  replaced with state["data"] (error if missing)
{data?}                ->  optional; empty string if missing
{artifact.name}        ->  replaced with the artifact's text
temp:key               ->  invocation-only; stripped from stored events
app:key                ->  shared across all users and sessions
user:key               ->  shared across one user's sessions
app:temp:key           ->  an app key (prefixes do not compose); persists
```
