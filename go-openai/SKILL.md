---
name: go-openai
description: Guides development with the official OpenAI Go SDK (github.com/openai/openai-go/v3).
  Use when calling OpenAI APIs, building chat completions, streaming responses, using
  tool calling, structured outputs, reasoning models, or integrating with OpenAI-compatible
  providers like Azure, vLLM, and Ollama.
---

# OpenAI Go

The official Go SDK for the OpenAI API (`github.com/openai/openai-go/v3`). Do **not** use the community package `sashabaranov/go-openai`.

```bash
go get -u 'github.com/openai/openai-go/v3@v3.24.0'
```

Pin to a specific version in production. Use `@latest` only for prototyping.

Requires Go 1.22+. The import resolves as `openai`:

```go
import (
    "github.com/openai/openai-go/v3"
    "github.com/openai/openai-go/v3/option"
    "github.com/openai/openai-go/v3/responses"
    "github.com/openai/openai-go/v3/shared"
)
```

**Version warning**: LLMs with older training data generate `github.com/openai/openai-go` (v1) or `github.com/openai/openai-go/v2` import paths. These are outdated. Always use the `/v3` suffix.

## Creating a Client

```go
client := openai.NewClient() // reads OPENAI_API_KEY from environment
```

With explicit options:

```go
client := openai.NewClient(
    option.WithAPIKey("sk-..."),
)
```

Options can be set at client level (all requests) or per-request (method call). See `option` package in `references/reference.md` for the full list.

## Two APIs: Responses and Chat Completions

| API | Package | Status | Use When |
|---|---|---|---|
| **Responses** | `responses` | Recommended | New projects, conversation continuity via `PreviousResponseID` |
| **Chat Completions** | root `openai` | Supported indefinitely | Existing code, broader ecosystem compatibility |

Both support streaming, tool calling, structured outputs, and reasoning models.

### Responses API

```go
resp, err := client.Responses.New(ctx, responses.ResponseNewParams{
    Model: openai.ChatModelGPT4o,
    Input: responses.ResponseNewParamsInputUnion{
        OfString: openai.String("Explain Go interfaces"),
    },
})
println(resp.OutputText())
```

### Chat Completions API

```go
chat, err := client.Chat.Completions.New(ctx, openai.ChatCompletionNewParams{
    Model: openai.ChatModelGPT4o,
    Messages: []openai.ChatCompletionMessageParamUnion{
        openai.DeveloperMessage("You are a Go expert."),
        openai.UserMessage("What is a slice?"),
    },
})
println(chat.Choices[0].Message.Content)
```

Message constructors: `openai.UserMessage()`, `openai.DeveloperMessage()`, `openai.AssistantMessage()`.

## Streaming

### Responses API Streaming

```go
stream := client.Responses.NewStreaming(ctx, responses.ResponseNewParams{
    Model: openai.ChatModelGPT4o,
    Input: responses.ResponseNewParamsInputUnion{
        OfString: openai.String("Write a haiku"),
    },
})
for stream.Next() {
    event := stream.Current()
    print(event.Delta)
}
if err := stream.Err(); err != nil {
    log.Fatal(err)
}
```

### Chat Completions Streaming with Accumulator

The `ChatCompletionAccumulator` collects chunks and detects completion events:

```go
stream := client.Chat.Completions.NewStreaming(ctx, openai.ChatCompletionNewParams{
    Model:    openai.ChatModelGPT4o,
    Messages: []openai.ChatCompletionMessageParamUnion{openai.UserMessage("Hello")},
})

acc := openai.ChatCompletionAccumulator{}
for stream.Next() {
    chunk := stream.Current()
    acc.AddChunk(chunk)

    if content, ok := acc.JustFinishedContent(); ok {
        println("Content done:", content)
    }
    if tool, ok := acc.JustFinishedToolCall(); ok {
        println("Tool call done:", tool.Index, tool.Name, tool.Arguments)
    }
    if refusal, ok := acc.JustFinishedRefusal(); ok {
        println("Refusal:", refusal)
    }

    if len(chunk.Choices) > 0 {
        print(chunk.Choices[0].Delta.Content)
    }
}
if err := stream.Err(); err != nil {
    log.Fatal(err)
}
```

Check `JustFinished*` methods **before** processing the chunk's delta content.

## Tool Calling

### Responses API

```go
params := responses.ResponseNewParams{
    Model: openai.ChatModelGPT4o,
    Input: responses.ResponseNewParamsInputUnion{
        OfString: openai.String("What's the weather in NYC?"),
    },
    Tools: []responses.ToolUnionParam{{
        OfFunction: &responses.FunctionToolParam{
            Name:        "get_weather",
            Description: openai.String("Get weather for a location"),
            Parameters: map[string]any{
                "type":       "object",
                "properties": map[string]any{"location": map[string]string{"type": "string"}},
                "required":   []string{"location"},
            },
        },
    }},
}

resp, _ := client.Responses.New(ctx, params)

for _, item := range resp.Output {
    if item.Type == "function_call" {
        call := item.AsFunctionCall()
        result := callFunction(call.Arguments)

        // Send result back
        resp, _ = client.Responses.New(ctx, responses.ResponseNewParams{
            Model:              openai.ChatModelGPT4o,
            PreviousResponseID: openai.String(resp.ID),
            Input: responses.ResponseNewParamsInputUnion{
                OfInputItemList: []responses.ResponseInputItemUnionParam{{
                    OfFunctionCallOutput: &responses.ResponseInputItemFunctionCallOutputParam{
                        CallID: call.CallID,
                        Output: responses.ResponseInputItemFunctionCallOutputOutputUnionParam{
                            OfString: openai.String(result),
                        },
                    },
                }},
            },
        })
    }
}
```

### Chat Completions API

Tool definitions use the same JSON schema format. Tool calls appear in `chat.Choices[0].Message.ToolCalls` and results are sent back as tool messages.

## Structured Outputs

Use `github.com/invopop/jsonschema` for schema generation:

```go
type Answer struct {
    Summary string   `json:"summary" jsonschema_description:"Brief summary"`
    Points  []string `json:"points" jsonschema_description:"Key points"`
}

func GenerateSchema[T any]() map[string]any {
    r := jsonschema.Reflector{AllowAdditionalProperties: false, DoNotReference: true}
    var v T
    s := r.Reflect(v)
    data, _ := json.Marshal(s)
    var m map[string]any
    _ = json.Unmarshal(data, &m)
    return m
}

schema := GenerateSchema[Answer]()
```

The marshal/unmarshal step converts `*jsonschema.Schema` to `map[string]any`, which is required by the Responses API. The Chat Completions API accepts `any`, so `map[string]any` works for both.

**Do not use `omitempty`** in JSON struct tags. The `jsonschema` library interprets `omitempty` as "optional", which excludes the field from `required`. With `Strict: true`, this causes API rejections.

### Chat Completions

```go
chat, _ := client.Chat.Completions.New(ctx, openai.ChatCompletionNewParams{
    Model:    openai.ChatModelGPT4o,
    Messages: []openai.ChatCompletionMessageParamUnion{openai.UserMessage("Summarize Go")},
    ResponseFormat: openai.ChatCompletionNewParamsResponseFormatUnion{
        OfJSONSchema: &openai.ResponseFormatJSONSchemaParam{
            JSONSchema: openai.ResponseFormatJSONSchemaJSONSchemaParam{
                Name:   "answer",
                Schema: schema,
                Strict: openai.Bool(true),
            },
        },
    },
})

var result Answer
json.Unmarshal([]byte(chat.Choices[0].Message.Content), &result)
```

### Responses API

```go
resp, _ := client.Responses.New(ctx, responses.ResponseNewParams{
    Model: openai.ChatModelGPT4o,
    Input: responses.ResponseNewParamsInputUnion{OfString: openai.String("Summarize Go")},
    Text: responses.ResponseTextConfigParam{
        Format: responses.ResponseFormatTextConfigParamOfJSONSchema("answer", schema),
    },
})

var result Answer
json.Unmarshal([]byte(resp.OutputText()), &result)
```

## Reasoning Models

The SDK natively supports reasoning models (o1, o3, o3-mini, o4-mini) via `shared.ReasoningParam`:

```go
chat, _ := client.Chat.Completions.New(ctx, openai.ChatCompletionNewParams{
    Model:    openai.ChatModelO3,
    Messages: []openai.ChatCompletionMessageParamUnion{openai.UserMessage("Solve step by step...")},
    Reasoning: shared.ReasoningParam{
        Effort:  openai.ReasoningEffortHigh,
        Summary: shared.ReasoningSummaryAuto,
    },
})
```

Reasoning effort constants: `ReasoningEffortLow`, `ReasoningEffortMedium`, `ReasoningEffortHigh`.

For OpenAI models, reasoning tokens are internal — counted in `Usage.CompletionTokensDetails.ReasoningTokens` but the chain-of-thought text is not returned.

### Non-OpenAI Reasoning Providers

vLLM, DeepSeek, and other providers return reasoning text in non-standard response fields. Use `ExtraFields` to access them:

```go
resp, _ := client.Chat.Completions.New(ctx, params)
msg := resp.Choices[0].Message

// vLLM (newer): "reasoning" field
if r, ok := msg.JSON.ExtraFields["reasoning"]; ok {
    fmt.Println("Thinking:", r.Raw())
}
// DeepSeek / vLLM (older): "reasoning_content" field
if r, ok := msg.JSON.ExtraFields["reasoning_content"]; ok {
    fmt.Println("Thinking:", r.Raw())
}
```

Streaming with non-standard reasoning fields:

```go
for stream.Next() {
    chunk := stream.Current()
    if len(chunk.Choices) > 0 {
        delta := chunk.Choices[0].Delta
        if r, ok := delta.JSON.ExtraFields["reasoning"]; ok {
            print(r.Raw()) // reasoning stream
        }
        print(delta.Content) // content stream
    }
}
```

## ExtraFields

The SDK provides a two-way mechanism for handling non-standard fields that the SDK structs do not define. This is critical for provider compatibility and forward compatibility with new API features.

### Sending Extra Fields in Requests

Every request param struct has `SetExtraFields(map[string]any)`. Nested param structs have `WithExtraFields(map[string]any)`:

```go
params := openai.ChatCompletionNewParams{/* ... */}
params.SetExtraFields(map[string]any{
    "custom_provider_field": "value",
})
```

Extra fields overwrite struct fields with matching keys. Only use with trusted data.

### Reading Extra Fields from Responses

Every response struct has a `.JSON` companion with `respjson.Field` metadata for each known field plus `ExtraFields` for unknown fields:

```go
// Access a non-standard field
raw := resp.JSON.ExtraFields["some_field"].Raw()

// Check if a known field was actually present in the JSON
if resp.JSON.Model.Valid() {
    // field was present and non-null
}

// Get the complete raw JSON
rawJSON := resp.RawJSON()
```

See `references/reference.md` for the full `respjson.Field` API and `param` package utilities.

## Error Handling

```go
resp, err := client.Chat.Completions.New(ctx, params)
if err != nil {
    var apierr *openai.Error
    if errors.As(err, &apierr) {
        fmt.Println("Status:", apierr.StatusCode)
        fmt.Println("Request:", string(apierr.DumpRequest(true)))
        fmt.Println("Response:", string(apierr.DumpResponse(true)))
    }
    log.Fatal(err)
}
```

The `*openai.Error` type exposes `StatusCode`, the original `*http.Request`, the `*http.Response`, and `DumpRequest`/`DumpResponse` helpers.

## Vision / Multimodal

```go
openai.ChatCompletionNewParams{
    Model: openai.ChatModelGPT4o,
    Messages: []openai.ChatCompletionMessageParamUnion{
        openai.UserMessage(
            openai.TextContentPart("What's in this image?"),
            openai.ImageContentPart(openai.ChatCompletionContentPartImageImageURLParam{
                URL:    "https://example.com/photo.png",
                Detail: "high",
            }),
        ),
    },
}
```

Content part constructors: `TextContentPart()`, `ImageContentPart()`, `FileContentPart()`, `InputAudioContentPart()`.

## Provider Configuration

### Azure OpenAI

```go
import "github.com/openai/openai-go/v3/azure"

// API key auth
client := openai.NewClient(
    option.WithBaseURL("https://YOUR-RESOURCE.openai.azure.com/openai/v1/"),
    option.WithAPIKey(os.Getenv("AZURE_OPENAI_API_KEY")),
)

// Entra ID token credential auth
client := openai.NewClient(
    option.WithBaseURL("https://YOUR-RESOURCE.openai.azure.com/openai/v1/"),
    azure.WithTokenCredential(tokenCredential),
)
```

Use Azure deployment names in the `Model` field instead of standard model IDs.

### vLLM / Ollama / Other OpenAI-Compatible Providers

Override the base URL:

```go
// vLLM
client := openai.NewClient(
    option.WithBaseURL("http://localhost:8000/v1/"),
    option.WithAPIKey("not-needed"),
)

// Ollama
client := openai.NewClient(
    option.WithBaseURL("http://localhost:11434/v1/"),
    option.WithAPIKey("ollama"),
)
```

Use `ExtraFields` to send provider-specific request parameters and read provider-specific response fields (see ExtraFields section above).

## Middleware

```go
func Logger(req *http.Request, next option.MiddlewareNext) (*http.Response, error) {
    start := time.Now()
    resp, err := next(req)
    slog.Info("openai request", "method", req.Method, "url", req.URL, "duration", time.Since(start))
    return resp, err
}

client := openai.NewClient(option.WithMiddleware(Logger))
```

Client-level middleware runs first, then per-request middleware. The HTTP client receives the request after all middleware has run.

## Production Client Configuration

Always pass a context with a deadline for API calls:

```go
ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
defer cancel()
resp, err := client.Chat.Completions.New(ctx, params)
```

Set a global timeout on the HTTP client as a safety net:

```go
client := openai.NewClient(
    option.WithHTTPClient(&http.Client{Timeout: 60 * time.Second}),
)
```

**Body dumping warning**: `DumpRequest(true)` and `DumpResponse(true)` include full request/response bodies, which may contain prompts, user content, or API keys. Only dump bodies in controlled debug environments. In production logging, use `DumpRequest(false)` / `DumpResponse(false)` for headers only.

## Audio

### Transcription

```go
file, _ := os.Open("recording.mp3")
transcription, _ := client.Audio.Transcriptions.New(ctx, openai.AudioTranscriptionNewParams{
    Model: openai.AudioModelWhisper1,
    File:  file,
})
println(transcription.Text)
```

Models: `AudioModelWhisper1`, `AudioModelGPT4oTranscribe`, `AudioModelGPT4oMiniTranscribe`. Formats: flac, mp3, mp4, mpeg, mpga, m4a, ogg, wav, webm.

### Text-to-Speech

```go
res, _ := client.Audio.Speech.New(ctx, openai.AudioSpeechNewParams{
    Model: openai.SpeechModelTTS1,
    Input: "Hello from the OpenAI Go SDK.",
    Voice: openai.AudioSpeechNewParamsVoiceAlloy,
})
defer res.Body.Close()
io.Copy(outputFile, res.Body) // res.Body is an audio stream
```

Models: `SpeechModelTTS1`, `SpeechModelTTS1HD`, `SpeechModelGPT4oMiniTTS`.

## Assistants API (Deprecated)

The Assistants API (`client.Beta.Assistants`, `client.Beta.Threads`) is deprecated in the SDK. Do not use it for new projects. Use the Responses API instead.

Key migration concepts:
- Assistant instructions → `Instructions` field on `ResponseNewParams`
- Threads / conversation history → `PreviousResponseID` for conversation continuity
- Runs → `client.Responses.New()` calls
- File search / retrieval → `file_search` tool in Responses

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/reference.md` | Complete type reference, model constants, option package, param utilities, respjson.Field API, version history, migration guide, provider compatibility details | Looking up specific types, debugging ExtraFields, migrating between SDK versions, or working with non-OpenAI providers |
