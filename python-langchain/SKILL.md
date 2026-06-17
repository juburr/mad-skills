---
name: python-langchain
description: Guides development with the Python LangChain v1 framework (langchain,
  langchain-core, langgraph). Use when building LLM applications, creating agents
  with create_agent, writing agent middleware, calling tools, generating structured
  output, building RAG pipelines, composing LangGraph state machines, streaming,
  managing memory and persistence, or migrating LangChain v0 code to v1.
---

# LangChain (Python)

LangChain v1 is a framework for building LLM applications and agents. The core abstraction is `create_agent`, a tool-calling agent built on the LangGraph runtime. Requires Python 3.10+.

> **Version warning — read first.** This skill targets **LangChain v1** (the `langchain` 1.x / `langchain-core` 1.x / `langgraph` 1.x line, GA October 2025). LLMs trained on v0.x emit outdated code: `LLMChain`, `AgentExecutor`, `initialize_agent`, `RetrievalQA`, `ConversationBufferMemory`, `from langchain.chat_models import ChatOpenAI`, and string-only `message.content`. **None of these are correct in v1.** When recalled APIs conflict with this document, trust this document. Legacy symbols moved to the separate `langchain-classic` package. See `references/migration-from-v0.md`.

## Packages and Installation

The v1 `langchain` namespace was deliberately slimmed to agents, models, messages, and tools. Integrations live in dedicated provider packages.

| Package | Role | Install |
|---|---|---|
| `langchain-core` | Base abstractions: messages, `BaseChatModel`, tools, Runnables/LCEL, output parsers. Stable, minimal deps. | (pulled in transitively) |
| `langchain` | Meta package: `create_agent`, `init_chat_model`, agent middleware, re-exports. **Depends on `langgraph`.** | `pip install langchain` |
| `langgraph` | Stateful graph runtime that powers agents (persistence, streaming, HITL). | (dep of `langchain`) |
| `langchain-<provider>` | One per provider; owns that provider's chat model + embeddings. | `pip install langchain-openai langchain-anthropic` |
| `langchain-community` | Community integrations without a dedicated package (e.g. `FAISS`, many loaders). | `pip install langchain-community` |
| `langchain-classic` | Home for v0 code pruned from `langchain`: legacy chains, `AgentExecutor`, indexing API, `hub`. Migration only. | `pip install langchain-classic` |

```bash
pip install langchain langchain-openai langchain-anthropic
# or:  uv add langchain langchain-anthropic
```

Provider packages must match the model you use. Pin versions in production.

## Chat Models

Use `init_chat_model` with a `"provider:model"` string. It resolves to the right provider class (which must be installed).

```python
from langchain.chat_models import init_chat_model

model = init_chat_model("anthropic:claude-sonnet-4-5", temperature=0)
# Equivalent:  init_chat_model("claude-sonnet-4-5", model_provider="anthropic")

resp = model.invoke("Explain Python generators in one sentence.")
print(resp.text)            # property, NOT resp.text()
```

Provider strings include `openai`, `anthropic`, `azure_openai`, `google_genai`, `google_vertexai`, `bedrock`, `groq`, `ollama`, `mistralai`, `deepseek`, `xai`, and more. Common kwargs (`temperature`, `max_tokens`, `timeout`, `max_retries`, `base_url`, `rate_limiter`) pass through to the provider class. Direct classes also work: `from langchain_openai import ChatOpenAI`. For the full provider registry, configurable models, and direct-class usage, read `references/models-and-messages.md`.

Every model supports `.invoke`, `.stream`, `.batch`, and async `.ainvoke` / `.astream` / `.abatch`. Input is a string, a list of messages, or a prompt value.

## Messages and Content Blocks

The biggest v1 change: **`message.content` is `str | list[str | dict]`, not always a string.** Read responses through the standardized accessors instead of indexing `.content`.

```python
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage, ToolMessage

ai = model.invoke([SystemMessage("Be terse."), HumanMessage("Hi")])

ai.text             # concatenated text of all text blocks (property)
ai.content_blocks   # list[ContentBlock]: provider-agnostic typed view
ai.tool_calls       # list[ToolCall] dicts: {"name","args","id","type"}
ai.usage_metadata   # {"input_tokens","output_tokens","total_tokens", ...} | None
```

`.content_blocks` (a `langchain-core` 1.0 property) normalizes provider-specific shapes into typed dicts discriminated by `type`: `text`, `reasoning`, `tool_call`, `citation`, `image`, `audio`, `video`, `file`. It works regardless of the model's `output_version` setting.

```python
for block in ai.content_blocks:
    if block["type"] == "reasoning":
        print("THINKING:", block.get("reasoning"))   # key is "reasoning"
    elif block["type"] == "text":
        print(block["text"])
```

Multimodal input uses the same block types via the `content_blocks=` kwarg. Note: v1 blocks carry `url` / `base64` / `file_id` directly — there is **no** v0 `source_type` key, and `mime_type` is required with `base64`.

```python
msg = HumanMessage(content_blocks=[
    {"type": "text", "text": "What's in this image?"},
    {"type": "image", "url": "https://example.com/cat.png", "mime_type": "image/png"},
])
```

Message classes also re-export from `langchain.messages`. For the full content-block TypedDict reference and `output_version`, read `references/models-and-messages.md`.

## Tools

Define tools with the `@tool` decorator. The schema is inferred from type hints and the docstring.

```python
from langchain_core.tools import tool

@tool
def get_weather(city: str) -> str:
    """Get the current weather for a city."""
    return f"It's sunny in {city}."
```

Use `parse_docstring=True` for per-argument descriptions, or pass an explicit Pydantic `args_schema`. With `response_format="content_and_artifact"`, return `(content, artifact)` to attach data not shown to the model. For error handling (`ToolException`, `handle_tool_error`), injected runtime/state (`ToolRuntime`, `InjectedState`, `InjectedStore`), and returning `Command`, read `references/agents-and-middleware.md`.

Bind tools to a model directly (without an agent) to read raw tool calls:

```python
model_with_tools = model.bind_tools([get_weather])   # optional tool_choice="any"
resp = model_with_tools.invoke("weather in Paris?")
for tc in resp.tool_calls:
    print(tc["name"], tc["args"], tc["id"])
```

## Structured Output (without an agent)

`model.with_structured_output(schema)` returns a runnable that produces typed output. A Pydantic model yields a validated instance; a `TypedDict` or JSON-schema dict yields a dict.

```python
from pydantic import BaseModel, Field

class Joke(BaseModel):
    setup: str
    punchline: str
    rating: int | None = Field(default=None, description="1-10")

structured = model.with_structured_output(Joke)
joke = structured.invoke("Tell me a cat joke")   # -> Joke instance
```

`method` options vary by provider (`function_calling` default, plus `json_schema` / `json_mode`). Use `include_raw=True` to get `{"raw", "parsed", "parsing_error"}` instead of raising. See `references/models-and-messages.md`.

## Agents: `create_agent`

`create_agent` is the canonical v1 agent. It returns a compiled LangGraph that runs the tool-calling loop (model → tools → model, until the model stops calling tools).

```python
from langchain.agents import create_agent

agent = create_agent(
    model="anthropic:claude-sonnet-4-5",   # string or a BaseChatModel
    tools=[get_weather],
    system_prompt="You are a helpful assistant.",
)

result = agent.invoke({"messages": [{"role": "user", "content": "weather in SF?"}]})
print(result["messages"][-1].content)
```

State is keyed on `messages` (an `add_messages`-reduced list). Input is `{"messages": [...]}`, **not** `{"input": "..."}`. The final answer is `result["messages"][-1]`.

### Key `create_agent` Parameters

| Parameter | Purpose |
|---|---|
| `model` | `"provider:model"` string or `BaseChatModel` instance. |
| `tools` | List of `@tool` callables, plain functions, `BaseTool`s, or provider tool dicts. |
| `system_prompt` | System prompt (string or `SystemMessage`). For dynamic prompts use `@dynamic_prompt` middleware — there is no `prompt=` kwarg. |
| `middleware` | Sequence of `AgentMiddleware` — the v1 extensibility mechanism (see below). |
| `response_format` | Structured final output: a Pydantic type, or `ToolStrategy` / `ProviderStrategy`. |
| `checkpointer` | Short-term memory (per `thread_id`). |
| `store` | Long-term, cross-thread memory (`BaseStore`). |
| `state_schema` / `context_schema` | Custom mutable state vs. immutable runtime context. |
| `interrupt_before` / `interrupt_after` | Static human-in-the-loop breakpoints by node name. |

For the full signature, read `references/agents-and-middleware.md`.

### Structured Output from an Agent

Pass `response_format`; the typed result appears under `result["structured_response"]`.

```python
from langchain.agents.structured_output import ToolStrategy
from pydantic import BaseModel

class Contact(BaseModel):
    name: str
    email: str

agent = create_agent("openai:gpt-5.1", tools=[], response_format=ToolStrategy(Contact))
out = agent.invoke({"messages": [{"role": "user", "content": "John Doe, john@x.com"}]})
out["structured_response"]   # Contact(name="John Doe", email="john@x.com")
```

`ToolStrategy` works with any tool-calling model and supports union schemas; `ProviderStrategy` uses the provider's native structured-output API.

## Agent Middleware

Middleware hooks into the agent loop to add summarization, human approval, retries, guardrails, and limits — instead of hand-rolling these. Import from `langchain.agents.middleware`.

```python
from langchain.agents.middleware import SummarizationMiddleware, HumanInTheLoopMiddleware

agent = create_agent(
    "anthropic:claude-sonnet-4-5",
    tools=[get_weather],
    middleware=[
        SummarizationMiddleware(model="anthropic:claude-haiku-4-5", max_tokens_before_summary=4000),
        HumanInTheLoopMiddleware(interrupt_on={"get_weather": True}),
    ],
    checkpointer=InMemorySaver(),   # required for HITL
)
```

Built-in middleware includes `SummarizationMiddleware`, `HumanInTheLoopMiddleware`, `PIIMiddleware`, `ModelCallLimitMiddleware`, `ToolCallLimitMiddleware`, `ModelFallbackMiddleware`, `ToolRetryMiddleware`, and more. Write custom middleware via decorators (`@before_model`, `@after_model`, `@wrap_model_call`, `@wrap_tool_call`, `@dynamic_prompt`) or by subclassing `AgentMiddleware`:

```python
from langchain.agents.middleware import before_model

@before_model
def log_turns(state, runtime) -> dict | None:
    print("messages so far:", len(state["messages"]))
    return None
```

For the full middleware catalog, all hooks (`ModelRequest`/`ModelResponse`, `wrap_model_call`/`wrap_tool_call`), HITL resume payloads, and structured-output strategies, read `references/agents-and-middleware.md`.

## Memory and Persistence

Agents are stateless between calls unless you attach a checkpointer.

- **Short-term (within a conversation):** pass a `checkpointer` and invoke with a `thread_id`.
- **Long-term (across conversations):** pass a `store` (`BaseStore`); access it inside tools via `InjectedStore` / `ToolRuntime`.

```python
from langgraph.checkpoint.memory import InMemorySaver

agent = create_agent("anthropic:claude-sonnet-4-5", tools=[get_weather],
                     checkpointer=InMemorySaver())
cfg = {"configurable": {"thread_id": "user-123"}}

agent.invoke({"messages": [{"role": "user", "content": "I'm Bob"}]}, config=cfg)
agent.invoke({"messages": [{"role": "user", "content": "What's my name?"}]}, config=cfg)  # remembers
```

A `thread_id` is **mandatory** once a checkpointer is set. Production backends: `langgraph-checkpoint-postgres`, `langgraph-checkpoint-sqlite`. This replaces v0 `ConversationBufferMemory` and `RunnableWithMessageHistory`.

## Streaming

Stream from any agent or graph with `stream` / `astream` and a `stream_mode`:

| Mode | Yields |
|---|---|
| `"values"` | Full state after each step. |
| `"updates"` | Per-node deltas (keyed by `"model"` / `"tools"`). |
| `"messages"` | LLM tokens, as `(chunk, metadata)` tuples. |
| `"custom"` | Arbitrary data from `get_stream_writer()`. |

```python
for token, meta in agent.stream(
    {"messages": [{"role": "user", "content": "Tell me a story"}]},
    stream_mode="messages",
):
    if token.content:
        print(token.content, end="", flush=True)
```

Pass a list (e.g. `stream_mode=["updates", "messages"]`) to combine modes; output becomes `(mode, payload)` tuples. The lower-level `astream_events` defaults to `version="v2"` (`"v1"` is deprecated).

## RAG and Custom Graphs

The v1-preferred RAG pattern is **retrieval-as-a-tool on an agent** (agentic RAG), not the deprecated `RetrievalQA`/`ConversationalRetrievalChain`.

```python
from langchain_core.vectorstores import InMemoryVectorStore
from langchain_openai import OpenAIEmbeddings

store = InMemoryVectorStore(OpenAIEmbeddings(model="text-embedding-3-small"))
store.add_documents(chunks)

@tool
def retrieve(query: str) -> str:
    """Search the knowledge base."""
    return "\n\n".join(d.page_content for d in store.similarity_search(query, k=4))

agent = create_agent("openai:gpt-5.1", tools=[retrieve],
                     system_prompt="Answer using the retrieve tool. Cite sources.")
```

For complete RAG (loaders, `langchain-text-splitters`, vector stores, retrievers with MMR), and raw LangGraph `StateGraph` (nodes, reducers, conditional edges, checkpointers, the `Store`, interrupts, subgraphs), read `references/langgraph-and-rag.md`.

## When to Use What

| Need | Use |
|---|---|
| Straight-line pipeline (prompt → model → parse), batch transforms | **LCEL** (`prompt \| model \| parser`) |
| Tool-calling agent loop with memory, middleware, HITL | **`create_agent`** |
| Custom control flow: branches, cycles, fan-out, multi-agent | **Raw LangGraph `StateGraph`** |

LCEL is **not** deprecated; it remains the right tool for deterministic flows. Use `RunnableLambda`, `RunnablePassthrough`, `RunnableParallel` from `langchain_core.runnables`.

## Observability (LangSmith)

Tracing is automatic for LangChain/LangGraph once environment variables are set:

```bash
export LANGSMITH_TRACING=true
export LANGSMITH_API_KEY=ls__...
export LANGSMITH_PROJECT=my-project        # optional
```

`LANGSMITH_*` is current; legacy `LANGCHAIN_TRACING_V2` / `LANGCHAIN_API_KEY` still work. Decorate arbitrary functions with `@traceable` from `langsmith`.

## Known Gotchas

- **`message.content` is not always a string.** Use `.text` (property) or `.content_blocks`. `.text()` as a method is deprecated.
- **No `AgentExecutor` / `initialize_agent`.** `create_agent` returns a ready-to-run compiled graph; there is no separate executor.
- **`create_react_agent` is deprecated** — both the old `langchain.agents` one and `langgraph.prebuilt.create_react_agent`. Use `create_agent`.
- **Agent input is `{"messages": [...]}`** and output is `result["messages"][-1]` (structured output under `result["structured_response"]`).
- **`system_prompt`, not `prompt`.** No `messages_modifier` / `state_modifier`. Dynamic prompts use `@dynamic_prompt` middleware.
- **Persistence is `checkpointer` + `thread_id`**, not v0 `Memory` classes.
- **Checkpointer imports are namespace-split**: `from langgraph.checkpoint.memory import InMemorySaver` — never `from langgraph.checkpoint import ...`. It is `InMemorySaver`, not `MemorySaver`.
- **Integrations are not bundled.** `ChatOpenAI` is in `langchain-openai`, not `langchain.chat_models`. Embeddings/vector stores live in provider or community packages.
- **Multimodal uses v1 blocks** (`url`/`base64`/`file_id` + `mime_type`), not v0 `source_type` or `image_url`.
- **`.run()` / `.predict()` / `__call__` / `get_relevant_documents()` are gone.** Everything is `.invoke` / `.stream` / `.batch`.

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/agents-and-middleware.md` | Full `create_agent` signature and `AgentState`; complete built-in middleware catalog; all middleware hooks and decorators (`ModelRequest`/`ModelResponse`, `wrap_model_call`/`wrap_tool_call`); structured-output strategies; tools accessing state/store/runtime; `Command`; HITL interrupt/resume payloads | Building agents, writing custom middleware, configuring HITL, or controlling tool execution |
| `references/models-and-messages.md` | `init_chat_model` provider registry and configurable models; direct provider classes; full content-block TypedDict reference; multimodal; `output_version`; `with_structured_output` methods; usage metadata; caching, rate limiting, retries, fallbacks, configurable fields; embeddings; prompt templates | Looking up provider strings, reading/constructing message content, structured output details, or model resilience config |
| `references/langgraph-and-rag.md` | LangGraph `StateGraph` (nodes, edges, conditional edges, reducers); checkpointers and the `Store`; interrupts and `Command`; subgraphs and fan-out; stream modes and `get_stream_writer`; complete RAG (loaders, text splitters, vector stores, retrievers); deployment with `langgraph.json` | Designing custom graphs, building RAG, long-term memory, or deploying agents |
| `references/migration-from-v0.md` | Complete v0→v1 symbol mapping; `langchain-classic` contents; deprecated chains/agents/memory; import-path changes; per-area gotchas | Migrating v0.x code or debugging outdated imports |
