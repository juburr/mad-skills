# Migrating ADK Go v1 to v2, and the v1 Maintenance Line

How to move code from `google.golang.org/adk` (v1.x) to `google.golang.org/adk/v2`, and what changed on the v1 maintenance line after v1.4.0. Verified against v2.5.0 and v1.7.0.

## Which Line to Use

| Line | Module | Go | Status |
|---|---|---|---|
| v2.x (v2.0.0 released 2026-06-30) | `google.golang.org/adk/v2` | 1.26.6+ from v2.3.0 (1.25.0 at v2.0.0; 1.26.5 at v2.1-v2.2) | Active development: graph workflows, collaboration modes, OpenAI provider, compaction, auth |
| v1.x (latest tag v1.7.0) | `google.golang.org/adk` | 1.25.0+ | Maintenance branch `v1`: security and bug-fix backports only |

Use v2 for new code. Stay on v1 only when the Go 1.26.6 requirement or migration cost is blocking; pin with `go get google.golang.org/adk@v1.7.0`.

## Migration Checklist

1. **Module path.** `go get google.golang.org/adk/v2@v2.5.0`, then rewrite every import from `google.golang.org/adk/...` to `google.golang.org/adk/v2/...` (the A2A packages become `google.golang.org/adk/v2/agent/remoteagent/v2` and `google.golang.org/adk/v2/server/adka2a/v2`). Remove the v1 requirement and run `go mod tidy`.
2. **Go toolchain.** Set `go 1.26.6` (or newer) in `go.mod`, or rely on `GOTOOLCHAIN=auto`.
3. **Contexts.** Replace `tool.Context`, `agent.ToolContext`, and `agent.CallbackContext` with `agent.Context` everywhere: function-tool handlers, agent/model/tool callbacks, plugin callbacks, A2A request callbacks, and custom tools' `ProcessRequest`/`Run`. There are no aliases in v2.
4. **Events.** Change `session.NewEvent(invocationID)` (and v1.5-v1.7's `session.NewEventWithContext`) to `session.NewEvent(ctx, ctx.InvocationID())`.
5. **Mocks.** Hand-written context mocks break because the interfaces grew. Embed `agent.StrictContextMock` and override only what the test uses.
6. **Telemetry.** `telemetry.WithGenAICaptureMessageContent` is gone; set `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT` instead.
7. **Artifacts.** `artifact.ArtifactVersion.CreateTime` is `time.Time` (was `float64` Unix seconds). Custom `artifact.Service` implementations must populate every `ArtifactVersion` field and return a non-nil `CustomMetadata` map.
8. **Database sessions.** Call `database.AutoMigrate(svc)` on every startup; v2 adds event columns.
9. **Custom session services.** Persist the new event fields and wrap `session.ErrNotFound` (see Behavior Changes). Run `session/sessiontestsuite` against your implementation.
10. **Deployment.** The web launcher binds `127.0.0.1` from v2.5.0: add `web -host 0.0.0.0` in containers, and review the REST origin checks, 10 MiB body limit, and `-include_debug_api` gate.
11. **Root agent mode.** A root `llmagent` must be chat mode (leave `Mode` unset).
12. **Re-test** OutputKey, artifact, and tool-confirmation flows; several v1 bugs are fixed and behavior moved.

## Before and After

```go
// v1.x
import (
    "google.golang.org/adk/agent"
    "google.golang.org/adk/agent/llmagent"
    "google.golang.org/adk/tool"
    "google.golang.org/adk/tool/functiontool"
)

func lookup(ctx tool.Context, args LookupArgs) (LookupResult, error) { /* ... */ }

before := func(ctx agent.CallbackContext, req *model.LLMRequest) (*model.LLMResponse, error) { /* ... */ }
ev := session.NewEvent(ctx.InvocationID())
```

```go
// v2.x
import (
    "google.golang.org/adk/v2/agent"
    "google.golang.org/adk/v2/agent/llmagent"
    "google.golang.org/adk/v2/tool"
    "google.golang.org/adk/v2/tool/functiontool"
)

func lookup(ctx agent.Context, args LookupArgs) (LookupResult, error) { /* ... */ }

before := func(ctx agent.Context, req *model.LLMRequest) (*model.LLMResponse, error) { /* ... */ }
ev := session.NewEvent(ctx, ctx.InvocationID())
```

Test fake with the v2 context surface:

```go
type fakeCtx struct {
    agent.StrictContextMock // Unimplemented methods panic "not implemented".
}

func (f *fakeCtx) AgentName() string { return "test_agent" }

var _ agent.Context = (*fakeCtx)(nil)

// ctx := &fakeCtx{StrictContextMock: agent.NewStrictContextMock(t.Context())}
```

## Breaking Changes Reference

| Change | Version | Migration |
|---|---|---|
| Module path `google.golang.org/adk` → `google.golang.org/adk/v2` | v2.0.0 | Rewrite imports |
| `tool.Context`, `agent.ToolContext`, `agent.CallbackContext`, `tool.NewToolContext` removed | v2.0.0 | Use `agent.Context`; constructors `agent.NewToolContext` / `agent.NewCallbackContext` return `agent.Context` |
| Callback types take `agent.Context` (`agent.Before/AfterAgentCallback`, `llmagent.*ModelCallback`, `llmagent.*ToolCallback`, `plugin.Config` hooks, `remoteagent` request callbacks) | v2.0.0 | Change the first parameter type |
| `functiontool.Func` / `StreamingFunc` handlers take `agent.Context` | v2.0.0 | `func(ctx agent.Context, args T) (R, error)` |
| `session.NewEvent(ctx, invocationID)`; `NewEventWithContext` removed | v2.0.0 | Pass the context in scope |
| `agent.InvocationContext` gained `IsolationScope()`, `ResumedInput(id)`, `WithICDelta(...)` | v2.0.0 | Embed `agent.StrictContextMock` in fakes |
| `session.Event` gained `IsolationScope`, `Routes`, `RequestedInput`, `Output`, `NodeInfo` | v2.0.0 | Custom stores must persist them |
| `session.Event` / `model.LLMResponse` JSON is consistently camelCase (`invocationId`, `stateDelta`, ...) | v2.2.0 | Update code that stores or parses event JSON |
| `artifact.ArtifactVersion.CreateTime` `float64` → `time.Time` | v2.0.0 | Update readers and custom services |
| `telemetry.WithGenAICaptureMessageContent` removed | v2.0.0 | Use the env var |
| Root `llmagent` must be chat mode; task/single_turn sub-agents become tools, not transfer targets | v2.0.0 | Leave root `Mode` unset |
| `session/database` adds columns (v2.0.0 workflow fields; v2.5.0 transcriptions) | v2.0.0 / v2.5.0 | `database.AutoMigrate` on every startup |
| Web launcher binds `127.0.0.1`; REST refuses cross-origin browsers; 10 MiB body limit; agent-graph routes need `-include_debug_api` | v2.5.0 | `-host 0.0.0.0`, `-webui_address`, `-max_request_body_size` |

## Behavior Changes to Review

- **OutputKey** (#577, fixed v2.4.0 and v1.7.0): only a final response with non-thought text writes the key; tool-call events no longer overwrite it with an empty string.
- **OutputSchema** never disabled tools: with tools present, ADK injects a `set_model_response` tool for Gemini API models (all Gemini models except Vertex AI Gemini 2.0+, which use the native schema). The v1 docs saying otherwise were wrong.
- **load_artifacts without an ArtifactService** (#283) returns an error instead of panicking (v2.3.0, v1.6.1). `ctx.Artifacts()` can be nil when no service is configured; nil-check it in custom tools.
- **Nil RunConfig** (#586) no longer panics when embedding (v2.3.0, v1.6.1).
- **Nil events:** the runner stops with an error when a custom agent yields `(nil, nil)` (v2.3.0).
- **Missing sessions:** bundled services wrap `session.ErrNotFound` (v2.4.0, v1.7.0); custom services must wrap it too.
- **`temp:` state** is stripped from stored event records (in-memory and Vertex AI in v2.5.0). On v2.1.0-v2.4.0 and v1.6.0-v1.7.0, `temp:` keys leaked into stored event `StateDelta`.
- **State prefixes do not compose:** `app:temp:x` is an app-scoped key that persists.
- **agenttool:** `SkipSummarization` results are shown as text (v2.4.0); child agents share the parent's artifacts (v2.5.0).
- **Thought-only turns:** a model that returns only thoughts is re-prompted at most 10 consecutive times (v2.3.0).
- **Orphaned function responses** are pruned instead of failing the turn (v2.4.0, v1.7.0); unanswered function calls are dropped from later requests (v2.5.0).
- **A2A:** a peer's `transfer_to_agent` is ignored unless `AllowTransferToAgent` is set (v2.3.0, v1.6.1); fetched cards must keep the source origin (v2.4.0, v1.7.0).
- **Tool confirmation:** forged or conflicting confirmations are rejected (v2.3.0, v1.6.1); `tool.WithConfirmation` also wraps streaming tools from v2.5.0.
- **MCP results:** empty text and non-text content no longer error (v2.4.0, v1.7.0).
- **Web launcher** defaults nil artifact and memory services to in-memory ones (v2.4.0, v1.7.0).

## What Stays the Same

- `agent.Agent`, `agent.Config` (including `Run func(agent.InvocationContext) iter.Seq2[*session.Event, error]`), loaders, `agent.RunConfig`, `agent.LiveRunConfig`.
- `llmagent.Config` fields (plus the new `Mode`), `runner.New`/`Run`/`RunLive`, `session.Service`, `memory.Service`, `artifact.Service` method sets, `model.LLM`.
- Workflow agents (`sequentialagent`, `parallelagent`, `loopagent`), `agenttool`, `mcptoolset`, `geminitool`, `skilltoolset`, plugins, and launcher usage, apart from import paths and context types.

## The v1 Maintenance Line (v1.5.0 to v1.7.0)

All v1.x releases are additive over v1.4.0 except where noted.

| Release | Notable changes |
|---|---|
| v1.5.0 | `platform` package (time/UUID providers); `session.NewEventWithContext` (and `NewEvent(id)` deprecated); `agent.StrictContextMock`; tool callbacks spelled `agent.ToolContext` (`tool.Context` still an alias); conformance suite moved to `session/sessiontestsuite` (**breaks imports of the old `session/session_test` path**); Agent Engine streaming for Gemini Enterprise |
| v1.5.1 | `parallelagent` waits for sub-agent teardown on early stop |
| v1.6.0 | Web launcher `-h2c`; skilltoolset accepts scalar `allowed-tools`; `gcsartifact.ErrVersionConflict`; tool-confirmation ordering fixes; live-session teardown and race fixes; Vertex AI session ownership check; absolute AgentTool `config_path` rejected (**breaking** for configurable agents) |
| v1.6.1 | `remoteagent/v2.A2AConfig.AllowTransferToAgent` (default false), `ErrUnsupportedCardSource`; tool-confirmation trust fixes; #586 and #283 fixed |
| v1.7.0 | REST `/health` and `/version`, `/dev/apps/...` developer routes; web launcher defaults artifact/memory services; card origin pinning (`ErrUntrustedCardInterface`); #577 fixed; `session.ErrNotFound`; MCP result handling; GCS `CanonicalURI` is `gs://` |

Known v1.7.0 defects (fixed on the `v1` branch after the tag): `/api/run_live` through the `api` sublauncher returns HTTP 500, and `temp:` keys leak into stored in-memory event history. v1.7.0 still binds all interfaces and has no REST authentication, origin checks, or body limit.

v1 does **not** receive: graph workflows, collaboration modes, the unified `agent.Context`, `model/openaimodel`, the model registry, `auth`/`auth/gcp`, `agentregistry`, context compaction, REST authn/authz, or the BigQuery analytics plugin.
