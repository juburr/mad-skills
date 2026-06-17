# Models and Messages

Complete reference for chat models, message content blocks, structured output, multimodal input, model resilience, embeddings, and prompt templates. Targets LangChain v1 (`langchain` 1.x, `langchain-core` 1.x).

## `init_chat_model`

```python
from langchain.chat_models import init_chat_model   # also langchain_core import for BaseChatModel

def init_chat_model(
    model: str | None = None,
    *,
    model_provider: str | None = None,
    configurable_fields: Literal["any"] | list[str] | tuple[str, ...] | None = None,
    config_prefix: str | None = None,
    **kwargs,
) -> BaseChatModel | _ConfigurableModel: ...
```

Use `"provider:model"` strings; `**kwargs` (e.g. `temperature`, `max_tokens`, `timeout`, `max_retries`, `base_url`, `rate_limiter`) pass to the provider class.

```python
model = init_chat_model("openai:gpt-5.1", temperature=0, max_tokens=1024)
model = init_chat_model("anthropic:claude-sonnet-4-5")
model = init_chat_model("gpt-5.1", model_provider="openai")   # equivalent
```

### Provider Registry

Each `model_provider` maps to a `langchain-<provider>` package that must be installed:

`openai`, `anthropic`, `azure_openai`, `azure_ai`, `google_vertexai`, `google_genai`, `bedrock`, `bedrock_converse`, `anthropic_bedrock`, `google_anthropic_vertex`, `cohere`, `fireworks`, `together`, `mistralai`, `huggingface`, `groq`, `ollama`, `deepseek`, `ibm`, `nvidia`, `xai`, `openrouter`, `perplexity`, `upstage`, `baseten`, `litellm`.

**Provider inference by bare model prefix** (best-effort, case-insensitive): `gpt-*`/`o1*`/`o3*` → `openai`; `claude*` → `anthropic`; `gemini*` → `google_vertexai` (pass `model_provider` to be explicit); `mistral*`/`mixtral*` → `mistralai`; `deepseek*` → `deepseek`; `grok*` → `xai`; `command*` → `cohere`; `sonar*` → `perplexity`.

### Configurable Models

Omit `model` to build a model selectable at runtime (`configurable_fields` defaults to `("model", "model_provider")`):

```python
configurable = init_chat_model(temperature=0)
configurable.invoke("hi", config={"configurable": {"model": "openai:gpt-5.1"}})

m = init_chat_model("openai:gpt-5.1", configurable_fields="any", config_prefix="foo")
m.invoke("hi", config={"configurable": {"foo_model": "anthropic:claude-sonnet-4-5",
                                        "foo_temperature": 0.7}})
```

**Security:** `configurable_fields="any"` lets runtime config override `api_key`/`base_url`. Enumerate fields explicitly for untrusted config.

### Direct Provider Classes

```python
from langchain_openai import ChatOpenAI
from langchain_anthropic import ChatAnthropic
from langchain_google_genai import ChatGoogleGenerativeAI

llm = ChatOpenAI(model="gpt-5.1", temperature=0, max_tokens=512)
llm = ChatAnthropic(model="claude-sonnet-4-5", max_tokens=1024)
```

### Invocation

`.invoke`, `.stream`, `.batch` plus async `.ainvoke`, `.astream`, `.abatch`. `.stream` yields `AIMessageChunk` objects; add them with `+` to aggregate.

## Messages

Import from `langchain_core.messages` (or the v1 re-export `langchain.messages`):

```python
from langchain_core.messages import (
    HumanMessage, AIMessage, SystemMessage, ToolMessage, AIMessageChunk,
)
```

### `.content` vs `.content_blocks` vs `.text`

| Accessor | Returns | Use |
|---|---|---|
| `.content` | `str \| list[str \| dict]` | Backward-compatible raw content. **Do not assume it's a string.** |
| `.content_blocks` | `list[ContentBlock]` | Standardized, provider-agnostic typed view. Preferred for reading. |
| `.text` | `str` (property) | Concatenation of all `text`-type blocks. `.text()` as a method is deprecated. |

`.content_blocks` (a `langchain-core` 1.0 property) coerces strings to text blocks and routes provider-specific shapes through translators. It works regardless of `output_version`.

### Content Block Types

Discriminated by `type`. Common optional keys: `id`, `index` (streaming), `extras`.

| `type` | Key fields |
|---|---|
| `"text"` | `text: str`, `annotations?` |
| `"reasoning"` | `reasoning?: str` (key is `reasoning`, not `text`/`thinking`) |
| `"tool_call"` | `id`, `name: str`, `args: dict` |
| `"citation"` | `url`, `title`, `start_index`, `end_index`, `cited_text` |
| `"image"` / `"audio"` / `"video"` | `url?`, `base64?`, `file_id?`, `mime_type?` |
| `"file"` | `url?`, `base64?`, `file_id?`, `mime_type?` (PDF/docx/etc.) |
| `"text-plain"` | `mime_type: "text/plain"`, `text`, `title`, `context` |

**There is no `source_type` key in v1** (that was v0). Blocks carry `url`/`base64`/`file_id` directly. `mime_type` is required when `base64` is set.

```python
for b in ai.content_blocks:
    if b["type"] == "reasoning":
        print(b.get("reasoning"))
    elif b["type"] == "text":
        print(b["text"])
    elif b["type"] == "tool_call":
        print(b["name"], b["args"])
```

### Multimodal Input

Use the `content_blocks=` constructor kwarg with the same block types:

```python
from langchain_core.messages import HumanMessage

HumanMessage(content_blocks=[
    {"type": "text", "text": "Describe this image."},
    {"type": "image", "url": "https://example.com/cat.png", "mime_type": "image/png"},
])

HumanMessage(content_blocks=[
    {"type": "text", "text": "Summarize this PDF."},
    {"type": "file", "base64": pdf_b64, "mime_type": "application/pdf"},
])
# Provider Files API:  {"type": "file", "file_id": "file-abc123"}
```

Factory helpers exist: `from langchain_core.messages.content import create_image_block, create_file_block, create_text_block`.

### `output_version`

`BaseChatModel.output_version` (default `None`, env var `LC_OUTPUT_VERSION`). Set to `"v1"` to store standardized content-block dicts directly in `.content` (useful when non-LangChain code reads `.content`). `.content_blocks` parsing works either way.

## Structured Output

```python
model.with_structured_output(schema, *, method=..., include_raw=False, **kwargs)
```

| Schema type | Result |
|---|---|
| Pydantic v2 `BaseModel` | validated instance |
| `TypedDict` or JSON-schema `dict` | plain `dict` |

`method` options vary by provider:
- **OpenAI:** `"function_calling"` (default), `"json_schema"`, `"json_mode"`.
- **Anthropic:** `"function_calling"` (default), `"json_schema"`.

`json_mode` does **not** send the schema to the model — describe the desired JSON in the prompt yourself.

```python
from pydantic import BaseModel, Field

class Joke(BaseModel):
    setup: str = Field(description="The setup")
    punchline: str
    rating: int | None = None

joke = model.with_structured_output(Joke).invoke("Tell me a cat joke")   # Joke instance

out = model.with_structured_output(Joke, include_raw=True).invoke("...")
out["raw"]            # AIMessage
out["parsed"]         # Joke | None
out["parsing_error"]  # exception | None  (surfaced, not raised)
```

## Usage Metadata

```python
resp = model.invoke("hi")
um = resp.usage_metadata            # UsageMetadata | None
um["input_tokens"]; um["output_tokens"]; um["total_tokens"]
um.get("input_token_details", {}).get("cache_read")
um.get("output_token_details", {}).get("reasoning")
resp.response_metadata              # dict: model name, finish_reason, headers, raw token_usage
```

## Resilience: Caching, Rate Limiting, Retries, Fallbacks

**Caching** (global):

```python
from langchain_core.globals import set_llm_cache
from langchain_core.caches import InMemoryCache
set_llm_cache(InMemoryCache())
# Persistent (community):  from langchain_community.cache import SQLiteCache
```

The global LLM cache may not apply inside LangGraph prebuilt agents.

**Rate limiting** (requests/sec only, not tokens):

```python
from langchain_core.rate_limiters import InMemoryRateLimiter
model = ChatAnthropic(
    model="claude-sonnet-4-5",
    rate_limiter=InMemoryRateLimiter(requests_per_second=0.5, max_bucket_size=10),
)
```

**Retries and fallbacks** (any runnable):

```python
robust = model.with_retry(stop_after_attempt=3, wait_exponential_jitter=True)
chain = ChatOpenAI(model="gpt-5.1").with_fallbacks([ChatAnthropic(model="claude-sonnet-4-5")])
```

**Configurable fields:**

```python
from langchain_core.runnables import ConfigurableField
m = ChatOpenAI(temperature=0).configurable_fields(
    temperature=ConfigurableField(id="temperature"))
m.invoke("...", config={"configurable": {"temperature": 0.9}})
```

## Embeddings

Interface: `embed_documents(list[str]) -> list[list[float]]`, `embed_query(str) -> list[float]`, plus async `aembed_*`.

```python
from langchain_openai import OpenAIEmbeddings
emb = OpenAIEmbeddings(model="text-embedding-3-large", dimensions=1024)
emb.embed_query("hello")
emb.embed_documents(["a", "b"])

# Unified factory (v1):
from langchain.embeddings import init_embeddings
emb = init_embeddings("openai:text-embedding-3-small")
```

## Prompt Templates

Supported but de-emphasized in v1 (which favors plain message lists and agents). Not deprecated.

```python
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder

prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    MessagesPlaceholder("history"),
    ("human", "{input}"),
])
chain = prompt | init_chat_model("openai:gpt-5.1")
chain.invoke({"history": [("human", "Hi"), ("ai", "Hello!")], "input": "Capital of France?"})
```

Role strings: `human`/`user`, `ai`/`assistant`, `system`, `placeholder`. **Security:** do not interpolate untrusted input into template strings (template-injection risk).
