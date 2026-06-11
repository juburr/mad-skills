# Orchestration Patterns

Complete reference for multi-agent orchestration patterns in ADK Go, with full code examples. Verified against `google.golang.org/adk` v1.4.0.

**Import convention:** Pattern 1 shows the full import block. Subsequent patterns show only the new imports they introduce. All patterns assume the common imports from Pattern 1 (`agent`, `llmagent`, `tool`, `genai`, etc.) plus `SKILL.md`'s Key Imports block.

## Pattern 1: Sequential Pipeline

Agents execute in fixed order. Each agent's output flows to the next via `OutputKey` and `{placeholder}` substitution in instructions.

```go
import (
    "google.golang.org/adk/agent"
    "google.golang.org/adk/agent/llmagent"
    "google.golang.org/adk/agent/workflowagents/sequentialagent"
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

**How it works:** `sequentialagent` runs each sub-agent in order, passing the same `InvocationContext`. When `CodeWriter` finishes, its response is stored in `state["code"]`. `CodeReviewer` sees `{code}` replaced with that value in its instruction.

## Pattern 2: Parallel Fan-Out / Gather

Independent tasks run concurrently. A downstream agent synthesizes results.

```go
import (
    "google.golang.org/adk/agent/workflowagents/parallelagent"
    "google.golang.org/adk/agent/workflowagents/sequentialagent"
)

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
carResearcher, _ := llmagent.New(llmagent.Config{
    Name:        "CarResearcher",
    Model:       m,
    Instruction: "Find car rentals in {destination} for {date}.",
    OutputKey:   "cars",
})

// Fan-out: all three run concurrently
gather, _ := parallelagent.New(parallelagent.Config{
    AgentConfig: agent.Config{
        Name:      "TravelResearch",
        SubAgents: []agent.Agent{flightResearcher, hotelResearcher, carResearcher},
    },
})

// Synthesizer reads all results
tripSynthesizer, _ := llmagent.New(llmagent.Config{
    Name:        "TripSynthesizer",
    Model:       m,
    Instruction: "Create a trip plan combining:\nFlights: {flights}\nHotels: {hotels}\nCars: {cars}",
})

// Sequential wrapper: fan-out first, then synthesize
workflow, _ := sequentialagent.New(sequentialagent.Config{
    AgentConfig: agent.Config{
        Name:      "TravelPlanner",
        SubAgents: []agent.Agent{gather, tripSynthesizer},
    },
})
```

**How it works:** `parallelagent` runs all sub-agents on independent branches concurrently. Each writes to its own `OutputKey`. After all complete, the sequential wrapper continues with the synthesizer, which reads all three state keys.

## Pattern 3: Critic / Refiner Loop

Sub-agents run repeatedly until a quality bar is met. Uses `loopagent` with escalation to exit.

```go
import (
    "google.golang.org/adk/agent/workflowagents/loopagent"
    "google.golang.org/adk/tool/exitlooptool"
)

generator, _ := llmagent.New(llmagent.Config{
    Name:        "DraftWriter",
    Model:       m,
    Instruction: "Write a short article about {topic}. If {criticism} is present, revise accordingly.",
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
    MaxIterations: 5,
    AgentConfig: agent.Config{
        Name:      "RefinementLoop",
        SubAgents: []agent.Agent{generator, critic},
    },
})
```

**Termination conditions (any one exits the loop):**
1. `MaxIterations` is reached
2. A sub-agent calls `exitlooptool` (sets `Escalate = true`)
3. A tool sets `ctx.Actions().Escalate = true` programmatically

**Custom exit tool (alternative to `exitlooptool`):**

```go
type ExitArgs struct{}
type ExitResult struct{ Status string `json:"status"` }

exitTool, _ := functiontool.New(functiontool.Config{
    Name:        "approve_draft",
    Description: "Call when the draft meets quality standards.",
}, func(ctx tool.Context, args ExitArgs) (ExitResult, error) {
    ctx.Actions().Escalate = true
    return ExitResult{Status: "approved"}, nil
})
```

## Pattern 4: Dynamic Delegation

An LLM coordinator routes requests to specialist sub-agents using `transfer_to_agent`. The LLM reads sub-agent `Description` fields to decide where to route.

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
salesAgent, _ := llmagent.New(llmagent.Config{
    Name:        "Sales",
    Model:       m,
    Description: "Handles pricing questions, plan upgrades, and new subscriptions.",
    Instruction: "You are a sales specialist. Help with pricing and subscriptions.",
})

coordinator, _ := llmagent.New(llmagent.Config{
    Name:        "HelpDesk",
    Model:       m,
    Description: "Main help desk coordinator.",
    Instruction: "Route user requests to the appropriate specialist agent.",
    SubAgents:   []agent.Agent{billingAgent, supportAgent, salesAgent},
})
```

**How it works:** ADK's AutoFlow adds a virtual `transfer_to_agent` tool to the coordinator's LLM. When the LLM decides a request should go to Billing, it generates:
```json
{"name": "transfer_to_agent", "args": {"agent_name": "Billing"}}
```
ADK intercepts this, finds the target agent, and transfers execution.

**Transfer scope controls:**

| Field | Default | Effect |
|---|---|---|
| `DisallowTransferToParent` | `false` | Prevents sub-agent from delegating back to parent |
| `DisallowTransferToPeers` | `false` | Prevents sub-agent from delegating to siblings |

**AgentTool vs SubAgents:**

| Mechanism | Use When |
|---|---|
| `SubAgents` + `transfer_to_agent` | LLM decides routing dynamically based on descriptions |
| `agenttool.New()` | Parent explicitly invokes child as a tool call (more control) |

## Pattern 5: Custom Agent with Planning Loop

For control flow beyond workflow agents, implement the `Run` function. This example implements a plan-execute-reflect loop.

```go
import (
    "encoding/json"
    "fmt"
    "iter"

    "google.golang.org/adk/agent"
    "google.golang.org/adk/agent/llmagent"
    "google.golang.org/adk/model"
    "google.golang.org/adk/session"
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
        for cycle := 0; cycle < a.maxCycles; cycle++ {
            // 1. Plan
            for event, err := range a.planner.Run(ctx) {
                if err != nil {
                    yield(nil, fmt.Errorf("planner failed: %w", err))
                    return
                }
                if !yield(event, nil) { return }
            }

            // 2. Parse plan from state
            rawPlan, _ := ctx.Session().State().Get("plan")
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
                ctx.Session().State().Set("step_input", step.Input)

                for event, err := range executor.Run(ctx) {
                    if err != nil {
                        yield(nil, fmt.Errorf("executor %s failed: %w", step.Agent, err))
                        return
                    }
                    if !yield(event, nil) { return }
                }

                result, _ := ctx.Session().State().Get("step_result")
                if r, ok := result.(string); ok {
                    results = append(results, r)
                }
            }

            // 4. Store results for reflector
            resultsJSON, _ := json.Marshal(results)
            ctx.Session().State().Set("results", string(resultsJSON))

            // 5. Reflect
            for event, err := range a.reflector.Run(ctx) {
                if err != nil {
                    yield(nil, fmt.Errorf("reflector failed: %w", err))
                    return
                }
                if !yield(event, nil) { return }
            }

            // 6. Check if done; wire guidance for next planner cycle
            verdict, _ := ctx.Session().State().Get("verdict")
            if v, ok := verdict.(string); ok && v == "done" {
                return
            }
            // Reflector wrote guidance to "verdict"; copy to "guidance" for planner
            if v, ok := verdict.(string); ok {
                ctx.Session().State().Set("guidance", v)
            }
        }
    }
}

func NewPlanExecuteReflect(m model.LLM, executors map[string]agent.Agent) (agent.Agent, error) {
    planner, _ := llmagent.New(llmagent.Config{
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

    reflector, _ := llmagent.New(llmagent.Config{
        Name:  "Reflector",
        Model: m,
        Instruction: `Task: {task}
Results: {results?}
Are the results complete and correct?
If yes, output exactly: done
If no, output guidance for the planner to improve.`,
        OutputKey: "verdict",
    })

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

agent, _ := NewPlanExecuteReflect(m, map[string]agent.Agent{
    "researcher": researcher,
    "coder":      coder,
})
```

## Pattern 6: Composite Workflows

Real systems combine patterns. Nest workflow agents freely.

```go
// Stage 1: Sequential code pipeline
spec, _ := llmagent.New(llmagent.Config{
    Name: "SpecWriter", Model: m, OutputKey: "spec",
    Instruction: "Write a spec for: {task}",
})
coder, _ := llmagent.New(llmagent.Config{
    Name: "Coder", Model: m, OutputKey: "code",
    Instruction: "Implement: {spec}",
})
linter, _ := llmagent.New(llmagent.Config{
    Name: "Linter", Model: m, OutputKey: "lint_result",
    Instruction: "Lint this code:\n{code}",
})

codePipeline, _ := sequentialagent.New(sequentialagent.Config{
    AgentConfig: agent.Config{
        Name:      "CodePipeline",
        SubAgents: []agent.Agent{spec, coder, linter},
    },
})

// Stage 2: Parallel research
security, _ := llmagent.New(llmagent.Config{
    Name: "SecurityReview", Model: m, OutputKey: "security",
    Instruction: "Security review:\n{code}",
})
perf, _ := llmagent.New(llmagent.Config{
    Name: "PerfReview", Model: m, OutputKey: "perf",
    Instruction: "Performance review:\n{code}",
})

reviews, _ := parallelagent.New(parallelagent.Config{
    AgentConfig: agent.Config{
        Name:      "ParallelReviews",
        SubAgents: []agent.Agent{security, perf},
    },
})

// Stage 3: Revision loop
reviser, _ := llmagent.New(llmagent.Config{
    Name: "Reviser", Model: m, OutputKey: "code",
    Instruction: "Revise code based on:\nSecurity: {security}\nPerf: {perf}\nCode: {code}",
})
exitTool, _ := exitlooptool.New()
checker, _ := llmagent.New(llmagent.Config{
    Name: "Checker", Model: m, OutputKey: "check",
    Instruction: "Check if revisions address all concerns. Call exit_loop if satisfactory.",
    Tools: []tool.Tool{exitTool},
})
revisionLoop, _ := loopagent.New(loopagent.Config{
    MaxIterations: 3,
    AgentConfig: agent.Config{
        Name:      "RevisionLoop",
        SubAgents: []agent.Agent{reviser, checker},
    },
})

// Compose: pipeline → parallel reviews → revision loop
fullWorkflow, _ := sequentialagent.New(sequentialagent.Config{
    AgentConfig: agent.Config{
        Name:      "FullCodeWorkflow",
        SubAgents: []agent.Agent{codePipeline, reviews, revisionLoop},
    },
})
```

## Pattern 7: Remote Agents in Orchestration

Mix local and remote agents. Remote agents (via A2A) are used like any other agent.

```go
import remoteagent "google.golang.org/adk/agent/remoteagent/v2"

// Remote agent running on another service. The v1 agent/remoteagent package
// (AgentCardSource field) is deprecated; v2 uses an AgentCardProvider.
testRunner, _ := remoteagent.NewA2A(remoteagent.A2AConfig{
    Name:              "TestRunner",
    Description:       "Runs test suites and reports results.",
    AgentCardProvider: remoteagent.NewAgentCardProvider("http://test-service:8001"),
})

// Local agent
coder, _ := llmagent.New(llmagent.Config{
    Name: "Coder", Model: m, OutputKey: "code",
    Instruction: "Write code for: {task}",
})

// Mix in a sequential pipeline
pipeline, _ := sequentialagent.New(sequentialagent.Config{
    AgentConfig: agent.Config{
        Name:      "CodeAndTest",
        SubAgents: []agent.Agent{coder, testRunner},
    },
})
```

Remote agents participate in the same state and event system. The A2A protocol handles serialization across the network boundary.

## Choosing a Pattern

| Situation | Pattern |
|---|---|
| Fixed sequence of processing steps | Sequential Pipeline |
| Independent tasks that can run concurrently | Parallel Fan-Out / Gather |
| Iterative quality improvement | Critic / Refiner Loop |
| Request routing based on content | Dynamic Delegation |
| Complex conditional logic, re-planning | Custom Agent |
| Combining multiple patterns | Composite (nest workflow agents) |
| Cross-service agent communication | Remote Agents (A2A) |

## State Flow Cheat Sheet

```
OutputKey="data"     →  state["data"] = agent's final text response
{data} in Instruction →  replaced with state["data"] at runtime
temp:key             →  cleared after invocation ends
app:key              →  persists across all users and sessions
user:key             →  persists across sessions for one user
```
