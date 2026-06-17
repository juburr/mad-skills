# Migrating from LangChain v0 to v1

Reference for porting LangChain v0.x code to v1 and for recognizing outdated patterns an LLM may emit from stale training data. LangChain/LangGraph reached v1.0 GA in October 2025.

## What Changed

The `langchain` package namespace was deliberately slimmed to **agents, models, messages, and tools**. Everything legacy still works but **moved to the `langchain-classic` package** — it was not deleted. v1 commits to no breaking changes until 2.0.

```bash
pip install langchain-classic   # only if you must keep using legacy chains/agents/memory
```

## Symbol Mapping

| v0 (stale) | v1 |
|---|---|
| `from langchain.chains import LLMChain` | LCEL: `prompt \| model \| parser` (or `langchain_classic.chains.LLMChain`) |
| `LLMChain`, `ConversationChain`, `SimpleSequentialChain` | Rebuild with LCEL; legacy in `langchain_classic.chains` |
| `RetrievalQA`, `ConversationalRetrievalChain` | Agentic RAG (retrieval-as-tool) or LCEL; legacy in `langchain_classic.chains` |
| `from langchain.agents import initialize_agent, AgentExecutor` | `from langchain.agents import create_agent` |
| `AgentType.*`, `create_openai_tools_agent`, `ConversationalAgent` | `create_agent` + middleware |
| `from langgraph.prebuilt import create_react_agent` | `from langchain.agents import create_agent` (prebuilt is `@deprecated`) |
| `from langchain.chat_models import ChatOpenAI` | `from langchain_openai import ChatOpenAI` (or `init_chat_model`) |
| `from langchain.embeddings import HuggingFaceEmbeddings` | `from langchain_community.embeddings import HuggingFaceEmbeddings` |
| `from langchain.vectorstores import FAISS` | `from langchain_community.vectorstores import FAISS` |
| `from langchain.retrievers import MultiQueryRetriever` | `from langchain_classic.retrievers import MultiQueryRetriever` |
| `from langchain.indexes import ...` | `from langchain_classic.indexes import ...` |
| `from langchain import hub` | `from langchain_classic import hub` |
| `ConversationBufferMemory`, `RunnableWithMessageHistory` | LangGraph checkpointers + `thread_id` (and `Store` for long-term) |

## Method-Call Changes

| v0 | v1 |
|---|---|
| `chain.run(...)`, `chain(...)` | `chain.invoke(...)` |
| `llm.predict(...)`, `llm.predict_messages(...)` | `model.invoke(...)` |
| `llm(...)` (`__call__`), `llm.generate(...)` | `model.invoke(...)` / `.batch(...)` |
| `retriever.get_relevant_documents(...)` | `retriever.invoke(...)` |
| `message.text()` (method) | `message.text` (property) |

The whole framework standardizes on the Runnable interface: `invoke` / `stream` / `batch` plus async `ainvoke` / `astream` / `abatch`.

## Message Content

In v0, `message.content` was treated as a string and multimodal used `{"type": "image_url", "image_url": {"url": ...}}` with a `source_type` key. In v1:

- `message.content` is `str | list[str | dict]` — read via `.text` (property) or `.content_blocks`.
- Multimodal blocks carry `url` / `base64` / `file_id` directly. **No `source_type`.** `mime_type` is required with `base64`.
- Reasoning content is a `{"type": "reasoning", "reasoning": ...}` block (key is `reasoning`).

```python
# v0 (wrong in v1):
content = response.content              # assumed str
# v1:
text = response.text                    # property
blocks = response.content_blocks        # standardized list
```

## Agents

```python
# v0 (wrong in v1):
from langchain.agents import initialize_agent, AgentExecutor, AgentType
agent = initialize_agent(tools, llm, agent=AgentType.OPENAI_FUNCTIONS)
agent.run("...")

# v1:
from langchain.agents import create_agent
agent = create_agent("openai:gpt-5.1", tools=tools, system_prompt="...")
result = agent.invoke({"messages": [{"role": "user", "content": "..."}]})
result["messages"][-1].content
```

Key differences:
- `create_agent` returns a ready-to-run compiled graph — there is no separate `AgentExecutor` wrapper.
- Input is `{"messages": [...]}`, not `{"input": "..."}`. Output is `result["messages"][-1]`.
- The kwarg is `system_prompt`, not `prompt` / `state_modifier` / `messages_modifier`. Dynamic prompts use `@dynamic_prompt` middleware.
- Cross-cutting concerns (summarization, retries, HITL, limits, guardrails) are **middleware**, not hand-rolled callbacks.

## Memory

```python
# v0 (wrong in v1):
from langchain.memory import ConversationBufferMemory
memory = ConversationBufferMemory()

# v1: persistence is a checkpointer + thread_id
from langgraph.checkpoint.memory import InMemorySaver
agent = create_agent(model, tools, checkpointer=InMemorySaver())
agent.invoke({"messages": [...]}, config={"configurable": {"thread_id": "abc"}})
```

## Observability

`LANGCHAIN_TRACING_V2` / `LANGCHAIN_API_KEY` / `LANGCHAIN_PROJECT` still work, but the current names are `LANGSMITH_TRACING` / `LANGSMITH_API_KEY` / `LANGSMITH_PROJECT`.

## Gotcha Checklist

- `message.content` is not always a string — use `.text` / `.content_blocks`.
- `.text` is a property; `.text()` is deprecated.
- No `AgentExecutor` / `initialize_agent` — use `create_agent`.
- `create_react_agent` (both `langchain.agents` and `langgraph.prebuilt`) is deprecated.
- Checkpointer imports are namespace-split (`langgraph.checkpoint.memory`, etc.); it is `InMemorySaver`.
- Integrations are not bundled — `ChatOpenAI` is in `langchain-openai`; vector stores/loaders in provider or community packages.
- `with_structured_output` default method is `function_calling` (not `json_schema`, despite older blog posts).
- `InMemoryRateLimiter` limits requests/sec, not tokens.
- `output_version` defaults to `None`; standardized `.content` storage is opt-in (but `.content_blocks` always works).
- `astream_events(version="v1")` is deprecated; v2 is the default.
