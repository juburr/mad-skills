# Agents and Middleware

Complete reference for `create_agent`, agent state, structured output strategies, tools that access runtime, and the middleware system. Targets LangChain v1 (`langchain` 1.x, `langgraph` 1.x).

## `create_agent`

Import from `langchain.agents`:

```python
from langchain.agents import create_agent, AgentState
```

`langchain.agents.__all__` is exactly `["AgentState", "create_agent"]`. Full signature:

```python
def create_agent(
    model: str | BaseChatModel,
    tools: Sequence[BaseTool | Callable | dict] | None = None,
    *,
    system_prompt: str | SystemMessage | None = None,
    middleware: Sequence[AgentMiddleware] = (),
    response_format: ResponseFormat | type | dict | None = None,
    state_schema: type[AgentState] | None = None,
    context_schema: type | None = None,
    checkpointer: Checkpointer | None = None,
    store: BaseStore | None = None,
    interrupt_before: list[str] | None = None,
    interrupt_after: list[str] | None = None,
    debug: bool = False,
    name: str | None = None,
    cache: BaseCache | None = None,
    transformers: Sequence[TransformerFactory] | None = None,
) -> CompiledStateGraph: ...
```

It returns a **`CompiledStateGraph`** — a LangGraph graph implementing the model→tools loop. Use the standard runnable/graph API: `invoke`, `stream`, `ainvoke`, `astream`, plus `config=` and `context=`.

| Parameter | Default | Purpose |
|---|---|---|
| `model` | — | `"provider:model"` string or `BaseChatModel`. |
| `tools` | `None` | `@tool` callables, plain functions, `BaseTool`s, or provider tool dicts. |
| `system_prompt` | `None` | System prompt (string or `SystemMessage`). No `prompt=` kwarg. |
| `middleware` | `()` | Sequence of `AgentMiddleware`. |
| `response_format` | `None` | Structured final output (type, `ToolStrategy`, or `ProviderStrategy`). |
| `state_schema` | `None` | Custom mutable state TypedDict (subclass `AgentState`). |
| `context_schema` | `None` | Immutable per-run context dataclass (read via `runtime.context`). |
| `checkpointer` | `None` | Short-term memory (per `thread_id`). |
| `store` | `None` | Long-term, cross-thread memory (`BaseStore`). |
| `interrupt_before` / `interrupt_after` | `None` | Static HITL breakpoints by node name. |
| `debug` | `False` | Verbose execution logging. |
| `name` | `None` | Agent name (useful when nested as a subgraph). |
| `cache` | `None` | `BaseCache` for node-level result caching. |
| `transformers` | `None` | Message transformer factories applied to the model input. |

> **v1.1.0 caveat:** one brief release (1.1.0) failed to export `create_agent` from `langchain.agents`. It is correctly exported on 1.2+. Pin to 1.2 or later.

### `AgentState`

```python
class AgentState(TypedDict):
    messages: Required[Annotated[list[AnyMessage], add_messages]]
    jump_to: NotRequired[Annotated[JumpTo | None, ...]]   # "tools" | "model" | "end"
    structured_response: NotRequired[ResponseT]
```

Input is `{"messages": [...]}`; messages accumulate via the `add_messages` reducer (dedupes by id). Subclass `AgentState` and pass `state_schema=` to add custom keys.

### Context vs. State

- **State** (`state_schema`): mutable, flows through the graph, persisted by the checkpointer.
- **Context** (`context_schema`): immutable per-run data (e.g. `user_id`), passed as `context=` at invocation, read via `runtime.context`.

```python
from dataclasses import dataclass

@dataclass
class Context:
    user_id: str

agent = create_agent("anthropic:claude-sonnet-4-5", tools=[...], context_schema=Context)
agent.invoke({"messages": [...]}, context=Context(user_id="u1"))
```

## Structured Output Strategies

Import from `langchain.agents.structured_output` (also re-exported from `langchain.agents.middleware`):

```python
from langchain.agents.structured_output import (
    ToolStrategy, ProviderStrategy, AutoStrategy, ResponseFormat,
    StructuredOutputValidationError,
)
```

| Strategy | Mechanism | Notes |
|---|---|---|
| `ToolStrategy(schema, handle_errors=..., tool_message_content=...)` | Forces a tool call whose args are the schema. | Works with any tool-calling model; supports **union** schemas; built-in error handling/retry. |
| `ProviderStrategy(schema, strict=...)` | Provider-native structured output (e.g. OpenAI JSON schema). | Single schema only. |
| `AutoStrategy` | Default when you pass a bare type. | Provider-native if supported, else `ToolStrategy`. |

Result appears under `result["structured_response"]`. Pass `response_format=MyModel` (auto), `response_format=ToolStrategy(MyModel)`, or `response_format=ProviderStrategy(MyModel)`.

```python
from pydantic import BaseModel
from langchain.agents.structured_output import ToolStrategy

class Answer(BaseModel):
    summary: str
    confidence: float

agent = create_agent("openai:gpt-5.1", tools=[...], response_format=ToolStrategy(Answer))
out = agent.invoke({"messages": [{"role": "user", "content": "..."}]})
out["structured_response"]   # Answer(...)
```

## Tools That Access Runtime

Tools passed to `create_agent` run in a LangGraph `ToolNode`. To reach agent state, the long-term store, or runtime context from inside a tool, use injected annotations from `langchain.tools` (hidden from the model's schema):

```python
from langchain.tools import tool, InjectedState, InjectedStore, ToolRuntime, InjectedToolCallId
from langgraph.store.base import BaseStore
from typing import Annotated

@tool
def remember(fact: str, store: Annotated[BaseStore, InjectedStore]) -> str:
    """Save a fact to long-term memory."""
    store.put(("memories",), key=fact[:20], value={"fact": fact})
    return "saved"
```

`ToolRuntime` is the v1 unified accessor (state + store + context + tool_call_id). `InjectedToolArg` marks any parameter as framework-filled.

### Returning `Command` from a Tool

A tool may return a `Command` (from `langgraph.types`) to update agent state or steer control flow instead of returning a plain value:

```python
from langgraph.types import Command
from langchain_core.messages import ToolMessage

@tool
def escalate(reason: str, tool_call_id: Annotated[str, InjectedToolCallId]) -> Command:
    """Hand off to a human."""
    return Command(update={
        "messages": [ToolMessage("escalated", tool_call_id=tool_call_id)],
        "needs_human": True,
    })
```

### Tool Error Handling

`from langchain_core.tools import ToolException`. The tool's `handle_tool_error` attribute (`bool | str | Callable | None`, default `False`) controls behavior: `True` returns the exception message to the model; a string returns that string; a callable's return value is used. Handled errors become a `ToolMessage(status="error")`. For loop-level retries, use `ToolRetryMiddleware`; to intercept/replace tool results, use `wrap_tool_call` middleware.

## Middleware

Middleware objects hook into the agent loop. Import from `langchain.agents.middleware`.

### Built-in Middleware

| Class | Purpose |
|---|---|
| `SummarizationMiddleware` | Summarize history when it grows past a token threshold. |
| `HumanInTheLoopMiddleware` | Interrupt for approval/edit/reject of tool calls. |
| `PIIMiddleware` | Detect/redact PII (raises `PIIDetectionError`). |
| `ModelCallLimitMiddleware` | Cap number of model calls. |
| `ToolCallLimitMiddleware` | Cap number of tool calls. |
| `ModelFallbackMiddleware` | Fall back to alternate model(s) on error. |
| `ModelRetryMiddleware` / `ToolRetryMiddleware` | Retry model / tool calls. |
| `ContextEditingMiddleware` (+ `ClearToolUsesEdit`) | Trim/clear old tool outputs from context. |
| `TodoListMiddleware` | Maintain a todo list in state. |
| `LLMToolSelectorMiddleware` | LLM pre-filters which tools to expose. |
| `LLMToolEmulator` | Emulate tools with an LLM (testing). |
| `ShellToolMiddleware` (+ `HostExecutionPolicy`, `DockerExecutionPolicy`, `CodexSandboxExecutionPolicy`) | Shell execution with sandbox policies. |
| `FilesystemFileSearchMiddleware` | File search tool. |
| `ProviderToolSearchMiddleware` | Provider-native tool search. |

### Hooks

Subclass `AgentMiddleware` and override hooks. Each has an `a`-prefixed async twin.

| Hook | Signature | Use |
|---|---|---|
| `before_agent` / `after_agent` | `(self, state, runtime) -> dict \| None` | Run once at agent start/end. |
| `before_model` / `after_model` | `(self, state, runtime) -> dict \| None` | Run around each model call. Return a state-update dict, or `None`. |
| `wrap_model_call` | `(self, request: ModelRequest, handler) -> ModelCallResult` | Wrap the model call; call `handler(request)` to run it (zero or more times). |
| `wrap_tool_call` | `(self, request: ToolCallRequest, handler) -> ToolMessage \| Command` | Wrap a tool call; can retry or replace results. |

Lifecycle hooks return a dict to update state; returning `{"jump_to": "end"}` (when `can_jump_to` permits) short-circuits the loop.

`ModelRequest` fields: `model`, `messages`, `system_message`, `tool_choice`, `tools`, `response_format`, `state`, `runtime`, `model_settings`; plus `.override(**overrides)` for a modified copy. `ModelResponse` fields: `result: list[BaseMessage]`, `structured_response`.

### Decorators

Generate single-hook middleware without subclassing. From `langchain.agents.middleware`:

```python
from langchain.agents.middleware import (
    before_model, after_model, before_agent, after_agent,
    wrap_model_call, wrap_tool_call, dynamic_prompt, hook_config, ModelRequest,
)

@dynamic_prompt
def personalized(request: ModelRequest) -> str:
    user = request.runtime.context.user_id
    return f"You are assisting user {user}."

@wrap_model_call
def retry_on_error(request, handler):
    for attempt in range(3):
        try:
            return handler(request)
        except Exception:
            if attempt == 2:
                raise

@before_model
def log_state(state, runtime) -> dict | None:
    print("turns:", len(state["messages"]))
    return None
```

Decorator params: `@before_model`/`@after_model`/`@before_agent`/`@after_agent` accept `state_schema`, `tools`, `can_jump_to`, `name`; `@wrap_model_call` accepts `state_schema`, `tools`, `name`; `@wrap_tool_call` accepts `tools`, `name`; `@dynamic_prompt` takes none; `@hook_config` accepts `can_jump_to`.

### Class Form

```python
from langchain.agents.middleware import AgentMiddleware

class GuardMiddleware(AgentMiddleware):
    def before_model(self, state, runtime):
        if len(state["messages"]) > 50:
            return {"jump_to": "end"}
        return None

    def wrap_tool_call(self, request, handler):
        return handler(request)
```

## Human-in-the-Loop

`HumanInTheLoopMiddleware` pauses the agent before configured tools and waits for a human decision. Requires a `checkpointer`.

```python
from langchain.agents.middleware import HumanInTheLoopMiddleware, InterruptOnConfig
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.types import Command

agent = create_agent(
    "anthropic:claude-sonnet-4-5",
    tools=[send_email],
    middleware=[HumanInTheLoopMiddleware(interrupt_on={
        "send_email": InterruptOnConfig(
            allowed_decisions=["approve", "edit", "reject"],
            description="Approve sending this email?",
        ),
    })],
    checkpointer=InMemorySaver(),
)

cfg = {"configurable": {"thread_id": "1"}}
result = agent.invoke({"messages": [{"role": "user", "content": "Email the team"}]}, config=cfg)
# Agent pauses at send_email. Inspect result["__interrupt__"] for the pending action(s), then resume:
result = agent.invoke(Command(resume={"decisions": [{"type": "approve"}]}), config=cfg)
```

`interrupt_on` maps a tool name to `True` (require approval, all decision types allowed), `False` (auto-approve), or an `InterruptOnConfig`. Resume with a `{"decisions": [...]}` payload containing **one decision per interrupted tool call**, in order. Decision shapes:

| Decision | Shape |
|---|---|
| Approve | `{"type": "approve"}` |
| Edit | `{"type": "edit", "edited_action": {"name": str, "args": dict}}` |
| Reject | `{"type": "reject", "message": str}` (message optional) |
| Respond | `{"type": "respond", "message": str}` (synthetic tool result) |

`InterruptOnConfig` fields: `allowed_decisions`, `description`, `args_schema`. You can also set static breakpoints via `interrupt_before=` / `interrupt_after=` on `create_agent`.

## Deprecated Agent APIs

| v0 | v1 |
|---|---|
| `AgentExecutor(agent=..., tools=...)` | `create_agent(...)` (returns a runnable graph; no separate executor) |
| `initialize_agent(...)` | `create_agent(...)` (legacy in `langchain_classic.agents`) |
| `from langgraph.prebuilt import create_react_agent` | `from langchain.agents import create_agent` (the prebuilt is `@deprecated`) |
| `AgentType.*`, `create_openai_tools_agent`, `ConversationalAgent` | `create_agent` + middleware |
| `prompt=` / `state_modifier` / `messages_modifier` | `system_prompt=` or `@dynamic_prompt` middleware |
