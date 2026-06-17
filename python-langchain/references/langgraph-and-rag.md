# LangGraph and RAG

Reference for raw LangGraph `StateGraph`, persistence, memory, interrupts, streaming internals, retrieval-augmented generation, and deployment. Targets LangGraph 1.x / LangChain 1.x.

Use raw `StateGraph` only when you need control flow beyond the agent loop: conditional branches, cycles, parallel fan-out, or multi-agent orchestration. For a standard tool-calling agent, prefer `create_agent` (see `references/agents-and-middleware.md`).

## StateGraph

```python
from typing import Annotated, TypedDict
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages
from langgraph.checkpoint.memory import InMemorySaver

class State(TypedDict):
    messages: Annotated[list, add_messages]   # reducer: append instead of replace
    count: int                                # no reducer: last write wins

def chatbot(state: State) -> dict:
    return {"messages": [model.invoke(state["messages"])], "count": state["count"] + 1}

def route(state: State) -> str:
    return "tools" if state["messages"][-1].tool_calls else END

builder = StateGraph(State)
builder.add_node("chatbot", chatbot)
builder.add_node("tools", tool_node)
builder.add_edge(START, "chatbot")
builder.add_conditional_edges("chatbot", route, {"tools": "tools", END: END})
builder.add_edge("tools", "chatbot")

graph = builder.compile(checkpointer=InMemorySaver())
graph.invoke({"messages": [...], "count": 0},
             config={"configurable": {"thread_id": "1"}})
```

### Reducers

A reducer is `(old, update) -> merged`, attached via `Annotated[type, reducer]`. Without one, each node write replaces the value. `add_messages` is the message-list reducer (dedupes by id, honors `RemoveMessage`). For plain accumulation use `Annotated[list, operator.add]`.

### Control Flow

- **Conditional edges:** `add_conditional_edges(node, fn, mapping)` where `fn(state)` returns a key in `mapping`.
- **`Command`:** return `Command(goto="node", update={...})` from a node to route and update state in one step.
- **Parallel fan-out:** return `[Send("node", payload), ...]` from a conditional edge.
- **Subgraphs:** add a compiled graph as a node (`builder.add_node("sub", subgraph)`); shared state keys flow automatically.

```python
from langgraph.types import Command, Send
```

## Persistence and Memory

### Checkpointers (short-term, per thread)

```python
from langgraph.checkpoint.memory import InMemorySaver          # dev
from langgraph.checkpoint.sqlite import SqliteSaver            # pip install langgraph-checkpoint-sqlite
from langgraph.checkpoint.sqlite.aio import AsyncSqliteSaver
from langgraph.checkpoint.postgres import PostgresSaver        # pip install langgraph-checkpoint-postgres
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
```

A `thread_id` in `config["configurable"]` is **mandatory** when a checkpointer is set. Imports are namespace-split — never `from langgraph.checkpoint import ...`. It is `InMemorySaver`, not the older `MemorySaver`.

### Store (long-term, cross-thread)

`BaseStore` interface: `put(namespace, key, value)`, `get(namespace, key)`, `search(namespace_prefix, query=..., filter=..., limit=k)`, `delete(...)`.

```python
from langgraph.store.memory import InMemoryStore

store = InMemoryStore(index={"embed": embeddings, "dims": 1536})   # semantic search
store.put(("users", user_id, "memories"), "k1", {"text": "likes tea"})
hits = store.search(("users", user_id, "memories"), query="beverages", limit=3)
```

Pass `store=` to `compile()` / `create_agent`. Inside a node, the store is injected: `def node(state, *, store: BaseStore): ...`. Production: `PostgresStore`, `RedisStore`.

## Interrupts (Human-in-the-Loop)

```python
from langgraph.types import interrupt, Command

def approval(state):
    decision = interrupt({"question": "Approve?", "draft": state["draft"]})  # pauses, persists
    return {"approved": decision}

# Resume on the same thread_id:
graph.invoke(Command(resume="yes"), config={"configurable": {"thread_id": "1"}})
```

Requires a checkpointer. On resume the node **re-runs from its start** — keep pre-interrupt work idempotent. Static breakpoints: `compile(interrupt_before=[...], interrupt_after=[...])`.

## Streaming

| `stream_mode` | Yields |
|---|---|
| `"values"` | Full state after each step. |
| `"updates"` | Per-node deltas. |
| `"messages"` | LLM tokens, as `(chunk, metadata)` tuples. |
| `"custom"` | User data via the stream writer. |
| `"debug"` | Verbose trace events. |

```python
for chunk, meta in graph.stream(inputs, stream_mode="messages"):
    if chunk.content:
        print(chunk.content, end="")   # meta["langgraph_node"] = source node
```

A list of modes yields `(mode, payload)` tuples. Emit custom data from inside a node:

```python
from langgraph.config import get_stream_writer

def node(state):
    writer = get_stream_writer()
    writer({"progress": "fetching..."})   # surfaces under stream_mode="custom"
```

The lower-level `astream_events` defaults to `version="v2"` (dict events). `"v1"` is deprecated; `"v3"` (typed, content-block-centric) is beta.

## Async

Every runnable/graph has async twins: `ainvoke`, `abatch`, `astream`, `astream_events`. Use `AsyncSqliteSaver` / `AsyncPostgresSaver` (their `.from_conn_string(...)` returns async context managers). Do not mix a sync checkpointer/store into async paths; prefer native async tool/node functions to avoid blocking the event loop.

## RAG

The v1-preferred pattern is **retrieval-as-a-tool on an agent** (agentic RAG). The deprecated `RetrievalQA` / `ConversationalRetrievalChain` / `create_retrieval_chain` live in `langchain-classic`.

### Building Blocks (exact imports)

```python
from langchain_text_splitters import RecursiveCharacterTextSplitter   # dedicated package
from langchain_core.vectorstores import InMemoryVectorStore           # built into core
from langchain_chroma import Chroma                                   # dedicated package
from langchain_community.vectorstores import FAISS                    # community
from langchain_postgres import PGVector                               # pgvector (psycopg3)
from langchain_openai import OpenAIEmbeddings
from langchain_community.document_loaders import WebBaseLoader, PyPDFLoader
from langchain_core.documents import Document
```

Splitters also include `CharacterTextSplitter`, `MarkdownHeaderTextSplitter`, `TokenTextSplitter`, and `RecursiveCharacterTextSplitter.from_language(...)`.

### Retriever from a Vector Store

```python
retriever = vector_store.as_retriever(
    search_type="mmr",                                       # or "similarity", "similarity_score_threshold"
    search_kwargs={"k": 4, "fetch_k": 20, "lambda_mult": 0.5},
)
docs = retriever.invoke("query")   # not get_relevant_documents()
```

### Agentic RAG

```python
from langchain.agents import create_agent
from langchain_core.tools import tool

splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200, add_start_index=True)
chunks = splitter.split_documents([Document(page_content=big_text)])

store = InMemoryVectorStore(OpenAIEmbeddings(model="text-embedding-3-small"))
store.add_documents(chunks)

@tool
def retrieve(query: str) -> str:
    """Search the knowledge base for relevant context."""
    return "\n\n".join(d.page_content for d in store.similarity_search(query, k=4))

agent = create_agent("openai:gpt-5.1", tools=[retrieve],
                     system_prompt="Answer using the retrieve tool. Cite sources.")
result = agent.invoke({"messages": [{"role": "user", "content": "..."}]})
```

### Deterministic RAG (LCEL)

For non-agentic, single-shot retrieval, an LCEL chain is still valid:

```python
from langchain_core.runnables import RunnablePassthrough
from langchain_core.output_parsers import StrOutputParser

chain = ({"context": retriever | format_docs, "question": RunnablePassthrough()}
         | prompt | model | StrOutputParser())
```

## Deployment (LangGraph Platform)

Install `pip install "langgraph-cli[inmem]"`. Add `langgraph.json` at the project root:

```json
{
  "dependencies": ["."],
  "graphs": { "agent": "./src/agent.py:graph" },
  "env": ".env",
  "python_version": "3.12"
}
```

`graphs` maps a name to `path:variable` (a compiled graph, a `create_agent` result, or a factory function). Commands:

- `langgraph dev` — local dev server with hot reload and Studio UI.
- `langgraph build` / `langgraph up` — build/run the Docker image (Postgres-backed).
- `langgraph deploy` — build, push, and deploy to managed LangSmith Deployments.

The server exposes a REST API: threads, runs (incl. streaming), assistants, the store, and HITL resume — so checkpointing/interrupts/memory are first-class over HTTP.

## Evaluation

- **`agentevals`** (`pip install agentevals`): trajectory evaluators — `create_trajectory_match_evaluator` and LLM-as-judge trajectory evaluators that score tool-call/step sequences.
- **LangSmith eval** (`from langsmith import evaluate`): run datasets against your app with custom or off-the-shelf evaluators, including full trajectory scoring.
