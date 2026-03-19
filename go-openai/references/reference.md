# Reference

Complete type reference, version history, param/respjson utilities, and provider compatibility details for the official OpenAI Go SDK.

## Package Structure

```
github.com/openai/openai-go/v3
├── (root)           Core client, chat completion types, model constants
├── responses/       Responses API types and params
├── conversations/   Conversation management
├── chat/            Chat-specific types
├── audio/           Speech, transcription, translation
├── embeddings/      Embedding models
├── images/          Image generation (DALL-E, gpt-image-1.5)
├── models/          Model listing and management
├── files/           File upload and management
├── vectorstore/     Vector storage
├── realtime/        Real-time API
├── option/          Client and request options
├── shared/          Shared types (ReasoningParam, etc.)
├── param/           Parameter utilities (Opt, Null, Override)
├── respjson/        Response JSON metadata (Field type)
├── azure/           Azure OpenAI helpers
├── pagination/      Auto-paging iterators
└── webhooks/        Webhook payload verification
```

## Client Options (option package)

| Function | Purpose |
|---|---|
| `option.WithAPIKey(key)` | Set API key. Defaults to `OPENAI_API_KEY` env var |
| `option.WithBaseURL(url)` | Override base URL for Azure, vLLM, Ollama, etc. |
| `option.WithHTTPClient(client)` | Replace underlying `*http.Client` |
| `option.WithHeader(key, value)` | Add custom HTTP header to requests |
| `option.WithMiddleware(mw...)` | Add request/response middleware |

All options accept both client-level (applies to all requests) and per-request usage via the variadic `opts ...option.RequestOption` parameter on every API method.

## Model Constants

### Chat Models

| Constant | Model |
|---|---|
| `openai.ChatModelGPT5_2` | gpt-5.2 |
| `openai.ChatModelGPT5_2Pro` | gpt-5.2-pro |
| `openai.ChatModelGPT5_1` | gpt-5.1 |
| `openai.ChatModelGPT5_1Mini` | gpt-5.1-mini |
| `openai.ChatModelGPT5` | gpt-5 |
| `openai.ChatModelGPT5Mini` | gpt-5-mini |
| `openai.ChatModelGPT5Nano` | gpt-5-nano |
| `openai.ChatModelGPT4_1` | gpt-4.1 |
| `openai.ChatModelGPT4_1Mini` | gpt-4.1-mini |
| `openai.ChatModelGPT4_1Nano` | gpt-4.1-nano |
| `openai.ChatModelGPT4o` | gpt-4o |
| `openai.ChatModelGPT4oMini` | gpt-4o-mini |

Date-pinned variants (e.g., `ChatModelGPT5_2_2025_12_11`, `ChatModelGPT4_1_2025_04_14`) are also available. Use date-pinned constants for reproducibility in production.

### Reasoning Models

| Constant | Model |
|---|---|
| `openai.ChatModelO4Mini` | o4-mini |
| `openai.ChatModelO3` | o3 |
| `openai.ChatModelO3Mini` | o3-mini |
| `openai.ChatModelO1` | o1 |
| `openai.ChatModelO1Mini` | o1-mini |
| `openai.ChatModelO1Preview` | o1-preview |

Models are periodically deprecated. Check the [OpenAI deprecations page](https://developers.openai.com/api/docs/deprecations/) before adopting a model for long-lived services.

### Audio Models

| Constant | Model |
|---|---|
| `openai.AudioModelWhisper1` | whisper-1 |
| `openai.AudioModelGPT4oTranscribe` | gpt-4o-transcribe |
| `openai.AudioModelGPT4oMiniTranscribe` | gpt-4o-mini-transcribe |
| `openai.AudioModelGPT4oTranscribeDiarize` | gpt-4o-transcribe-diarize |

### Speech Models

| Constant | Model |
|---|---|
| `openai.SpeechModelTTS1` | tts-1 |
| `openai.SpeechModelTTS1HD` | tts-1-hd |
| `openai.SpeechModelGPT4oMiniTTS` | gpt-4o-mini-tts |

### Reasoning Effort

```go
type ReasoningEffort string

const (
    ReasoningEffortLow    ReasoningEffort = "low"
    ReasoningEffortMedium ReasoningEffort = "medium"
    ReasoningEffortHigh   ReasoningEffort = "high"
)
```

### Reasoning Param

```go
import "github.com/openai/openai-go/v3/shared"

shared.ReasoningParam{
    Effort:  openai.ReasoningEffortHigh,
    Summary: shared.ReasoningSummaryAuto,  // "auto", "concise", "detailed"
}
```

## Chat Completions Types

### ChatCompletionNewParams

```go
type ChatCompletionNewParams struct {
    Model           openai.ChatModel
    Messages        []ChatCompletionMessageParamUnion
    Tools           []ChatCompletionToolUnionParam
    ResponseFormat  ChatCompletionNewParamsResponseFormatUnion
    Reasoning       shared.ReasoningParam
    Temperature     param.Opt[float64]
    TopP            param.Opt[float64]
    MaxTokens       param.Opt[int64]
    N               param.Opt[int64]
    Seed            param.Opt[int64]
    Stop            []string
    // ... additional fields
}
```

### Message Constructors

| Constructor | Creates |
|---|---|
| `openai.UserMessage(parts...)` | User message (text, images, audio, files) |
| `openai.DeveloperMessage(text)` | Developer/system message |
| `openai.AssistantMessage(text)` | Assistant message |
| `openai.SystemMessage(text)` | System message (alias for developer) |

### Content Part Constructors

| Constructor | Creates |
|---|---|
| `openai.TextContentPart(text)` | Text content |
| `openai.ImageContentPart(imageURL)` | Image URL content |
| `openai.FileContentPart(file)` | File content |
| `openai.InputAudioContentPart(audio)` | Audio input |

### ChatCompletion Response

```go
type ChatCompletion struct {
    ID      string
    Object  string
    Created int64
    Model   string
    Choices []ChatCompletionChoice
    Usage   CompletionUsage
    JSON    struct { /* respjson.Field for each + ExtraFields */ }
}

type ChatCompletionChoice struct {
    Index        int64
    Message      ChatCompletionMessage
    FinishReason string  // "stop", "tool_calls", "length", "content_filter"
    JSON         struct { /* respjson.Field for each + ExtraFields */ }
}

type ChatCompletionMessage struct {
    Role       string
    Content    string
    Refusal    string
    ToolCalls  []ChatCompletionMessageToolCall
    JSON       struct { /* respjson.Field for each + ExtraFields */ }
}
```

### CompletionUsage

```go
type CompletionUsage struct {
    PromptTokens            int64
    CompletionTokens        int64
    TotalTokens             int64
    CompletionTokensDetails struct {
        ReasoningTokens      int64
        AcceptedPrediction   int64
        RejectedPrediction   int64
    }
    PromptTokensDetails struct {
        CachedTokens int64
    }
    JSON struct { /* respjson.Field for each + ExtraFields */ }
}
```

### ChatCompletionAccumulator

```go
type ChatCompletionAccumulator struct {
    Choices []ChatCompletionAccumulatorChoice
    Usage   CompletionUsage
}

func (a *ChatCompletionAccumulator) AddChunk(chunk ChatCompletionChunk) error
func (a *ChatCompletionAccumulator) JustFinishedContent() (string, bool)
func (a *ChatCompletionAccumulator) JustFinishedToolCall() (ChatCompletionAccumulatorToolCall, bool)
func (a *ChatCompletionAccumulator) JustFinishedRefusal() (string, bool)
```

The `JustFinished*` methods return `true` exactly once per completed event. Check them before processing delta content.

### Streaming Options

```go
type ChatCompletionStreamOptionsParam struct {
    IncludeUsage       param.Opt[bool]  // include usage in final chunk
    IncludeObfuscation param.Opt[bool]  // enable stream obfuscation (side-channel mitigation)
}
```

When `IncludeUsage` is true, the final streaming chunk contains the full `Usage` struct (including `ReasoningTokens`). The `Choices` array on that final chunk is empty.

## Responses API Types

### ResponseNewParams

```go
type ResponseNewParams struct {
    Model              openai.ChatModel
    Input              ResponseNewParamsInputUnion
    Tools              []ToolUnionParam
    Text               ResponseTextConfigParam
    PreviousResponseID param.Opt[string]
    Instructions       param.Opt[string]
    Temperature        param.Opt[float64]
    MaxOutputTokens    param.Opt[int64]
    // ... additional fields
}
```

### Response

```go
type Response struct {
    ID         string
    Object     string
    Model      string
    Output     []ResponseOutputItemUnion
    Usage      ResponseUsage
    JSON       struct { /* respjson.Field for each + ExtraFields */ }
}

func (r *Response) OutputText() string  // concatenates all text output items
```

### Output Item Types

| Type | Check | Cast Method |
|---|---|---|
| `"message"` | `item.Type == "message"` | `item.AsMessage()` |
| `"function_call"` | `item.Type == "function_call"` | `item.AsFunctionCall()` |
| `"function_call_output"` | `item.Type == "function_call_output"` | — |
| `"reasoning"` | `item.Type == "reasoning"` | `item.AsReasoning()` |

## respjson.Field API

Every response struct has a `.JSON` embedded struct. Each known field maps to a `respjson.Field`, plus an `ExtraFields map[string]respjson.Field` for anything not in the struct definition.

### Methods

| Method | Returns | Description |
|---|---|---|
| `.Raw()` | `string` | Raw JSON value as string |
| `.Valid()` | `bool` | `true` if the field was present and non-null |

### Sentinel Values

| Value | Meaning |
|---|---|
| `respjson.Omitted` | Field was absent from the JSON response |
| `"null"` | Field was explicitly `null` in the JSON |

### Usage Pattern

```go
resp, _ := client.Chat.Completions.New(ctx, params)
msg := resp.Choices[0].Message

// Check if a known field was present
if msg.JSON.Content.Valid() {
    // Content was present and non-null
}

// Check if a known field was omitted
if msg.JSON.Refusal.Raw() == respjson.Omitted {
    // Refusal field was not in the JSON
}

// Access a non-standard field from a provider
if val, ok := msg.JSON.ExtraFields["reasoning_content"]; ok {
    fmt.Println("Reasoning:", val.Raw())
}

// Get the full raw JSON
rawJSON := resp.RawJSON()
```

## param Package Utilities

| Function | Purpose |
|---|---|
| `param.IsOmitted(field)` | Check if an optional field was omitted |
| `param.Null[string]()` | Send explicit JSON `null` for a string field |
| `param.NullStruct[T]()` | Send explicit JSON `null` for a struct field |
| `param.IsNull(field)` | Check if a field is null |
| `param.Override[T](value)` | Send a custom value instead of the expected type |
| `openai.String(s)` | Returns `param.Opt[string]` — wraps a string as an included optional field |
| `openai.Int(n)` | Returns `param.Opt[int64]` — wraps an int64 as an included optional field |
| `openai.Float(f)` | Returns `param.Opt[float64]` — wraps a float64 as an included optional field |
| `openai.Bool(b)` | Returns `param.Opt[bool]` — wraps a bool as an included optional field |

The `param.Opt[T]` type has three states: omitted (zero value), null (`param.Null[T]()`), or included (via constructors above). Do not use raw pointers for optional fields — always use these constructors.

## Error Type

```go
type Error struct {
    StatusCode int
    *http.Request
    *http.Response
}

func (e *Error) DumpRequest(body bool) []byte
func (e *Error) DumpResponse(body bool) []byte
```

Usage with `errors.As`:

```go
var apierr *openai.Error
if errors.As(err, &apierr) {
    fmt.Println("Status:", apierr.StatusCode)
    fmt.Println(string(apierr.DumpResponse(true)))
}
```

## Pagination

List endpoints return paginated results:

```go
// Manual pagination
page, _ := client.Models.List(ctx, openai.ModelListParams{})
for _, model := range page.Data {
    fmt.Println(model.ID)
}

// Auto-pagination
pager := client.Models.ListAutoPaging(ctx, openai.ModelListParams{})
for pager.Next() {
    model := pager.Current()
    fmt.Println(model.ID)
}
if err := pager.Err(); err != nil {
    log.Fatal(err)
}
```

## Version History and Migration

### Version Timeline

| Version | Date | Import Path | Key Changes |
|---|---|---|---|
| v1.0.0 | May 2025 | `github.com/openai/openai-go` | First stable release |
| v2.0.0 | Aug 2025 | `github.com/openai/openai-go/v2` | Tool param union refactoring |
| **v3.0.0** | **Sep 2025** | **`github.com/openai/openai-go/v3`** | **Responses API; current version** |

### v1 to v2 Migration

Tool parameter construction changed:

```go
// v1 (DO NOT USE)
openai.ChatCompletionToolParam{
    Function: openai.FunctionDefinitionParam{Name: "get_weather"},
}

// v2+
openai.ChatCompletionFunctionTool(
    openai.FunctionDefinitionParam{Name: "get_weather"},
)
```

`ChatCompletionToolParam` became the union type `ChatCompletionToolUnionParam`.

### v2 to v3 Migration

- Import path changed to `/v3`
- `responses` subpackage introduced as the primary API
- Breaking changes described as "small and limited"

### Why LLMs Generate Wrong Code

1. The SDK was alpha/beta until May 2025. Most training data predates v1.
2. Three major versions shipped in 5 months (May-Sep 2025). Training data lags behind.
3. `sashabaranov/go-openai` has been popular for much longer. LLMs conflate the two packages.
4. Go's `/v2`, `/v3` import path suffixes are easy to miss.

## Provider Compatibility

### Reasoning Field Names by Provider

| Provider | Non-Streaming Field | Streaming Delta Field | Notes |
|---|---|---|---|
| OpenAI (o1/o3/o4-mini) | Not exposed (internal) | Not exposed | Token count in `Usage.CompletionTokensDetails.ReasoningTokens` |
| DeepSeek API | `reasoning_content` | `reasoning_content` | DeepSeek's native field name |
| vLLM (v0.9+) | `reasoning` | `reasoning` | Changed from `reasoning_content` |
| vLLM (v0.7-v0.8) | `reasoning_content` | `reasoning_content` | Legacy field name |
| OpenRouter | Varies by underlying provider | Varies | May map fields; check both names |

For all non-OpenAI providers, access these via `msg.JSON.ExtraFields["reasoning"]` or `msg.JSON.ExtraFields["reasoning_content"]`. When targeting multiple providers, check both field names.

### Base URL Patterns

| Provider | Base URL | Auth |
|---|---|---|
| OpenAI (default) | `https://api.openai.com/v1` | `OPENAI_API_KEY` |
| Azure OpenAI | `https://RESOURCE.openai.azure.com/openai/v1/` | API key or Entra ID token |
| vLLM | `http://localhost:8000/v1/` | Usually none |
| Ollama | `http://localhost:11434/v1/` | Any non-empty string |
| TGI | `http://localhost:8080/v1/` | Usually none |
| OpenRouter | `https://openrouter.ai/api/v1/` | OpenRouter API key |

### Azure-Specific Configuration

```go
import "github.com/openai/openai-go/v3/azure"

// Token credential with custom scopes
client := openai.NewClient(
    option.WithBaseURL(endpoint + "/openai/v1/"),
    azure.WithTokenCredential(cred, azure.WithTokenCredentialScopes([]string{scope})),
)
```

Azure uses deployment names instead of model IDs. Pass the deployment name in the `Model` field.

## Middleware Details

```go
type MiddlewareNext func(req *http.Request) (*http.Response, error)

func Logger(req *http.Request, next option.MiddlewareNext) (*http.Response, error) {
    start := time.Now()
    resp, err := next(req)
    slog.Info("api call", "status", resp.StatusCode, "duration", time.Since(start))
    return resp, err
}
```

Execution order: client-level middleware runs first, then per-request middleware, then the HTTP client sends the request.

```go
// Client-level (all requests)
client := openai.NewClient(option.WithMiddleware(Logger))

// Per-request (single call)
resp, err := client.Chat.Completions.New(ctx, params, option.WithMiddleware(Retry))
```

## Webhook Verification

```go
import "github.com/openai/openai-go/v3/webhooks"

payload, err := webhooks.Verify(requestBody, headers, webhookSecret)
```
