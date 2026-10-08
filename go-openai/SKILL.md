---
name: go-openai
description: Guides development with the official OpenAI Go SDK (github.com/openai/openai-go/v3).
  Use when calling OpenAI APIs from Go, building Responses or Chat Completions requests, streaming,
  tool calling, structured outputs, reasoning models, Responses WebSockets, the beta Agents API,
  integrating Azure OpenAI, Amazon Bedrock, vLLM, Ollama, or other OpenAI-compatible providers,
  or upgrading older openai-go code.
---

# OpenAI Go

> **Verified against SDK v3.73.0** (released 2026-10-06). Requires Go 1.25+; v3.44.0 is the last release that builds with Go 1.22–1.24. If your knowledge of this SDK predates v3.54, read `references/version-notes.md` first: function-call outputs, speech voices, Azure authentication, error strings, and HTTP defaults changed.

The official Go SDK for the OpenAI API (`github.com/openai/openai-go/v3`). Do **not** use the community package `sashabaranov/go-openai`.

```bash
go get 'github.com/openai/openai-go/v3@v3.73.0'
```

Pin an explicit version. Avoid v3.69.0–v3.71.0 when any keyed endpoint uses plain `http://` (those releases refuse it). Minor releases occasionally change generated types, so run the build after every upgrade.

The import resolves as `openai`:

```go
import (
	"github.com/openai/openai-go/v3"
	"github.com/openai/openai-go/v3/option"
	"github.com/openai/openai-go/v3/responses"
	"github.com/openai/openai-go/v3/shared"
)
```

**Version warning**: LLMs with older training data generate `github.com/openai/openai-go` (v1) or `/v2` import paths, `openai.F(...)` wrappers, or `sashabaranov/go-openai` APIs. All are wrong for this SDK. Always use the `/v3` suffix and `param.Opt[T]` constructors (`openai.String`, `openai.Int`, `openai.Float`, `openai.Bool`).

## Creating a Client

```go
client := openai.NewClient() // reads OPENAI_API_KEY, OPENAI_BASE_URL, OPENAI_ORG_ID, OPENAI_PROJECT_ID, ...

client = openai.NewClient(
	option.WithAPIKey(os.Getenv("MY_OPENAI_KEY")),
	option.WithMaxRetries(3),
)
```

- `NewClient` also reads `OPENAI_ADMIN_KEY`, `OPENAI_WEBHOOK_SECRET`, and `OPENAI_CUSTOM_HEADERS` (newline-separated `Name: value` lines). Options apply at client level or per request (every method takes `opts ...option.RequestOption`).
- Ambient credentials follow any base URL you configure: `OPENAI_API_KEY`, an `Authorization` line in `OPENAI_CUSTOM_HEADERS`, and the org/project headers. For third-party servers pass `option.WithAPIKey("")` **and** `option.WithHeaderDel("Authorization")`; `WithAPIKey("")` alone leaves a custom-header `Authorization` in place.
- Create one client at startup and reuse it; `NewClient` returns an `openai.Client` value.

## Choosing an API

| API | Accessor | Use when |
|---|---|---|
| **Responses** | `client.Responses` | Default for new code: tools, hosted tools, reasoning, conversation state via `PreviousResponseID` or Conversations |
| **Chat Completions** | `client.Chat.Completions` | Existing code, OpenAI-compatible servers (vLLM, Ollama), Bedrock; supported indefinitely |
| **Responses WebSockets** | `client.Responses.Connect` | Low-latency loops with many turns on one connection |
| **Agents (beta)** | `client.Beta.Agents` | Hosted multi-turn agents with environments, local tool handlers, subagents, artifacts |
| **Realtime / Live** | `client.Realtime`, `client.Live` | Voice sessions (WebRTC/SIP control plane only) |

For WebSockets, compaction, prompt caching, and the full tool catalog, read `references/responses-advanced.md`. For Agents, Live, Decisions, webhooks, and other new services, read `references/new-apis.md`.

## Choosing a Model

Use a current, non-deprecated constant such as `openai.ChatModelGPT5_5`, `openai.ChatModelGPT5_4Mini`, or the GPT-6 family (`ChatModelGPT6Sol`, `ChatModelGPT6_1Sol`). Since v3.71.0 many older constants (`ChatModelGPT5`, `ChatModelO3`, `ChatModelO4Mini`, `ChatModelGPT4_1Nano`) carry `Deprecated:` shutdown notices that staticcheck reports. Pin dated snapshots (`ChatModelGPT5_5_2026_04_23`) for reproducible production behavior. Model fields are string aliases, so any model ID compiles; the server validates it. See `references/reference.md` for the full model table.

## Responses API

```go
resp, err := client.Responses.New(ctx, responses.ResponseNewParams{
	Model:        openai.ChatModelGPT5_5,
	Instructions: openai.String("You are a Go expert."),
	Input:        responses.ResponseNewParamsInputUnion{OfString: openai.String("Explain Go interfaces")},
})
if err != nil {
	return err
}
fmt.Println(resp.OutputText())

// Continue the conversation: send only the new input.
resp, err = client.Responses.New(ctx, responses.ResponseNewParams{
	Model:              openai.ChatModelGPT5_5,
	PreviousResponseID: openai.String(resp.ID),
	Input:              responses.ResponseNewParamsInputUnion{OfString: openai.String("Show an example.")},
})
```

- `Instructions` is not carried over by `PreviousResponseID`; resend it each turn. Check `resp.Status` (`completed`, `incomplete`, `failed`) and `resp.IncompleteDetails.Reason` before trusting `OutputText()`.

## Chat Completions API

```go
chat, err := client.Chat.Completions.New(ctx, openai.ChatCompletionNewParams{
	Model: openai.ChatModelGPT5_5,
	Messages: []openai.ChatCompletionMessageParamUnion{
		openai.DeveloperMessage("You are a Go expert."),
		openai.UserMessage("What is a slice?"),
	},
	MaxCompletionTokens: openai.Int(1024), // MaxTokens is deprecated
})
if err != nil {
	return err
}
fmt.Println(chat.Choices[0].Message.Content)
```

Message constructors (`UserMessage`, `DeveloperMessage`, `SystemMessage`, `AssistantMessage`) each take **one** argument: a string or a slice of content parts. `openai.ToolMessage(content, toolCallID)` returns tool results. `SystemMessage` sends `role: system`; it is not an alias for developer.

## Streaming

### Responses Streaming

```go
stream := client.Responses.NewStreaming(ctx, responses.ResponseNewParams{
	Model: openai.ChatModelGPT5_5,
	Input: responses.ResponseNewParamsInputUnion{OfString: openai.String("Write a haiku")},
})
defer func() { _ = stream.Close() }()

for stream.Next() {
	switch e := stream.Current().AsAny().(type) {
	case responses.ResponseTextDeltaEvent:
		fmt.Print(e.Delta)
	case responses.ResponseCompletedEvent:
		fmt.Println("\ntokens:", e.Response.Usage.TotalTokens) // e.Response is the full final response
	case responses.ResponseIncompleteEvent: // e.g. max_output_tokens; output so far is partial
		return fmt.Errorf("response incomplete: %s", e.Response.IncompleteDetails.Reason)
	case responses.ResponseFailedEvent:
		return fmt.Errorf("response failed: %s", e.Response.Error.Code)
	case responses.ResponseErrorEvent:
		return fmt.Errorf("stream error: %s", e.Code)
	}
}
if err := stream.Err(); err != nil { // transport errors only; protocol failures arrive as events
	return err
}
```

Handle every terminal event: `stream.Err()` stays nil for incomplete, failed, and error events. Do not print `event.Delta` for every event: non-text events (such as shell output deltas) carry JSON in `Delta`.

### Chat Completions Streaming with Accumulator

```go
stream := client.Chat.Completions.NewStreaming(ctx, openai.ChatCompletionNewParams{
	Model:         openai.ChatModelGPT5_5,
	Messages:      []openai.ChatCompletionMessageParamUnion{openai.UserMessage("Hello")},
	StreamOptions: openai.ChatCompletionStreamOptionsParam{IncludeUsage: openai.Bool(true)},
})
defer func() { _ = stream.Close() }()

acc := openai.ChatCompletionAccumulator{}
for stream.Next() {
	chunk := stream.Current()
	if !acc.AddChunk(chunk) {
		return errors.New("accumulator rejected a malformed chunk")
	}
	if content, ok := acc.JustFinishedContent(); ok {
		fmt.Println("\ncontent done:", len(content), "bytes")
	}
	if tool, ok := acc.JustFinishedToolCall(); ok {
		fmt.Println("tool call:", tool.Index, tool.ID, tool.Name, tool.Arguments)
	}
	if refusal, ok := acc.JustFinishedRefusal(); ok {
		fmt.Println("refusal:", refusal)
	}
	if len(chunk.Choices) > 0 {
		fmt.Print(chunk.Choices[0].Delta.Content)
	}
}
if err := stream.Err(); err != nil {
	return err
}
fmt.Println("total tokens:", acc.Usage.TotalTokens) // acc embeds the assembled ChatCompletion
```

- `AddChunk` returns `bool`, not `error`. Ignoring `false` silently drops chunks.
- Check `JustFinished*` before printing the chunk's delta. Use the `...ForChoice(i)` variants when `N > 1`.
- With `IncludeUsage`, the final chunk has usage and an empty `Choices` slice (hence the length check).

## Tool Calling

### Responses API

```go
tools := []responses.ToolUnionParam{{
	OfFunction: &responses.FunctionToolParam{
		Name:        "get_weather",
		Description: openai.String("Get the current weather for a city"),
		Strict:      openai.Bool(true),
		Parameters: map[string]any{
			"type":                 "object",
			"properties":           map[string]any{"city": map[string]any{"type": "string"}},
			"required":             []string{"city"},
			"additionalProperties": false,
		},
	},
}}
resp, err := client.Responses.New(ctx, responses.ResponseNewParams{
	Model: openai.ChatModelGPT5_5,
	Input: responses.ResponseNewParamsInputUnion{OfString: openai.String("Weather in Paris?")},
	Tools: tools,
})
if err != nil {
	return err
}

var outputs []responses.ResponseInputItemUnionParam
for _, item := range resp.Output {
	if item.Type != "function_call" {
		continue
	}
	call := item.AsFunctionCall()
	out := responses.ResponseInputItemParamOfFunctionCallOutput(getWeather(call.Arguments))
	out.OfFunctionCallOutput.CallID = openai.String(call.CallID) // CallID is param.Opt[string]
	outputs = append(outputs, out)
}
if len(outputs) > 0 {
	resp, err = client.Responses.New(ctx, responses.ResponseNewParams{
		Model:              openai.ChatModelGPT5_5,
		PreviousResponseID: openai.String(resp.ID),
		Input:              responses.ResponseNewParamsInputUnion{OfInputItemList: outputs},
		Tools:              tools,
	})
}
```

`CallID: call.CallID` no longer compiles (since v3.54.0), and forgetting `CallID` compiles but omits `call_id` from the request. The SDK's own README tool-calling sample still has the old form.

### Chat Completions API

```go
params := openai.ChatCompletionNewParams{
	Model:    openai.ChatModelGPT5_5,
	Messages: []openai.ChatCompletionMessageParamUnion{openai.UserMessage("Weather in Paris?")},
	Tools: []openai.ChatCompletionToolUnionParam{
		openai.ChatCompletionFunctionTool(openai.FunctionDefinitionParam{
			Name:        "get_weather",
			Description: openai.String("Get the current weather for a city"),
			Strict:      openai.Bool(true),
			Parameters: openai.FunctionParameters{
				"type":                 "object",
				"properties":           map[string]any{"city": map[string]any{"type": "string"}},
				"required":             []string{"city"},
				"additionalProperties": false,
			},
		}),
	},
}
for {
	completion, err := client.Chat.Completions.New(ctx, params)
	if err != nil {
		return err
	}
	msg := completion.Choices[0].Message
	if len(msg.ToolCalls) == 0 {
		fmt.Println(msg.Content)
		break
	}
	params.Messages = append(params.Messages, msg.ToParam()) // assistant turn with tool calls
	for _, call := range msg.ToolCalls {
		params.Messages = append(params.Messages, openai.ToolMessage(getWeather(call.Function.Arguments), call.ID))
	}
}
```

Bound the loop in production (maximum iterations) and validate tool arguments before executing anything; the SDK never runs tools for you.

## Structured Outputs

Generate the schema with `github.com/invopop/jsonschema`, keeping values as `json.RawMessage` so large integer bounds are not rounded through `float64`:

```go
type Answer struct {
	Summary string   `json:"summary" jsonschema_description:"Brief summary"`
	Points  []string `json:"points" jsonschema_description:"Key points"`
}

func SchemaFor[T any]() (map[string]any, error) {
	r := jsonschema.Reflector{AllowAdditionalProperties: false, DoNotReference: true}
	var v T
	data, err := json.Marshal(r.Reflect(v))
	if err != nil {
		return nil, err
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, err
	}
	schema := make(map[string]any, len(raw))
	for k, v := range raw {
		schema[k] = v
	}
	return schema, nil
}
```

**Do not use `omitempty`** in struct tags: the reflector treats it as optional, which breaks `Strict: true` (every property must be required).

```go
schema, err := SchemaFor[Answer]()
if err != nil {
	return err
}

resp, err := client.Responses.New(ctx, responses.ResponseNewParams{
	Model: openai.ChatModelGPT5_5,
	Input: responses.ResponseNewParamsInputUnion{OfString: openai.String("Summarize Go")},
	Text: responses.ResponseTextConfigParam{
		Format: responses.ResponseFormatTextConfigUnionParam{
			OfJSONSchema: &responses.ResponseFormatTextJSONSchemaConfigParam{
				Name: "answer", Schema: schema, Strict: openai.Bool(true),
			},
		},
	},
})
if err != nil {
	return err
}
var answer Answer
if err := json.Unmarshal([]byte(resp.OutputText()), &answer); err != nil {
	return err
}
```

For Chat Completions, set `ResponseFormat: openai.ChatCompletionNewParamsResponseFormatUnion{OfJSONSchema: &openai.ResponseFormatJSONSchemaParam{JSONSchema: openai.ResponseFormatJSONSchemaJSONSchemaParam{Name: "answer", Schema: schema, Strict: openai.Bool(true)}}}` and unmarshal `Choices[0].Message.Content` after checking `Message.Refusal`. `responses.ResponseFormatTextConfigParamOfJSONSchema(name, schema)` is a shortcut that does not set `Strict`.

## Reasoning Models

```go
// Responses: full reasoning controls
resp, err := client.Responses.New(ctx, responses.ResponseNewParams{
	Model: openai.ChatModelGPT5_5,
	Input: responses.ResponseNewParamsInputUnion{OfString: openai.String("Solve step by step...")},
	Reasoning: shared.ReasoningParam{
		Effort:  shared.ReasoningEffortHigh,
		Summary: shared.ReasoningSummaryAuto,
	},
})

// Chat Completions: effort only
chat, err := client.Chat.Completions.New(ctx, openai.ChatCompletionNewParams{
	Model:           openai.ChatModelGPT5_5,
	Messages:        []openai.ChatCompletionMessageParamUnion{openai.UserMessage("Solve step by step...")},
	ReasoningEffort: openai.ReasoningEffortHigh,
})
```

- Effort constants: `ReasoningEffortNone`, `Minimal`, `Low`, `Medium`, `High`, `Xhigh`, `Max`. `ReasoningParam` also has `Context` and `Mode`.
- `ChatCompletionNewParams` has no `Reasoning` field; use `ReasoningEffort`.
- OpenAI models never return chain-of-thought text; counts are in `resp.Usage.OutputTokensDetails.ReasoningTokens` (Responses) or `chat.Usage.CompletionTokensDetails.ReasoningTokens` (Chat), and Responses summaries arrive as `reasoning` output items. vLLM and DeepSeek return reasoning text in `reasoning` / `reasoning_content` extra fields (see `references/providers-auth.md`).

## ExtraFields

Send fields the SDK does not model with `SetExtraFields` on any params struct; read unmodeled response fields from `.JSON.ExtraFields`:

```go
params := openai.ChatCompletionNewParams{
	Model:    "meta-llama/Llama-3.3-70B-Instruct",
	Messages: []openai.ChatCompletionMessageParamUnion{openai.UserMessage("Hi")},
}
params.SetExtraFields(map[string]any{"top_k": 40}) // provider-specific; trusted data only

completion, err := client.Chat.Completions.New(ctx, params)
if err != nil {
	return err
}
if f, ok := completion.Choices[0].Message.JSON.ExtraFields["reasoning"]; ok {
	fmt.Println("raw reasoning JSON:", f.Raw()) // Raw() keeps JSON quoting
}
```

Extra fields override struct fields with the same key. `Valid()` reports whether a known field was present and non-null; it is always false for extra fields, so inspect `Raw()`. `completion.RawJSON()` returns the whole body. See `references/reference.md` for the `respjson` and `param` APIs.

## Error Handling

```go
resp, err := client.Responses.New(ctx, params)
if err != nil {
	var apierr *openai.Error
	if errors.As(err, &apierr) {
		slog.Error("openai api error", "status", apierr.StatusCode, "code", apierr.Code,
			"type", apierr.Type, "param", apierr.Param, "request_id", apierr.Response.Header.Get("x-request-id"))
	}
	return err
}
```

- Since v3.71.0, `err.Error()` (and `%v`, slog) prints only `OpenAI API error: 400 Bad Request`. Never parse the error string; read the fields.
- `apierr.Message` and `RawJSON()` are raw provider diagnostics that can echo request content. Keep them out of routine logs; surface them only in gated debug paths.
- `apierr.DumpRequest(true)` / `DumpResponse(true)` include the `Authorization` header and bodies verbatim. Use them only in local debugging, never in logs.
- Non-API failures (network, timeouts) are returned as-is: `*url.Error`, `context.DeadlineExceeded`.

## Vision and Files

`openai.UserMessage` takes one slice of parts: `openai.UserMessage([]openai.ChatCompletionContentPartUnionParam{openai.TextContentPart("What's in this image?"), openai.ImageContentPart(openai.ChatCompletionContentPartImageImageURLParam{URL: url, Detail: "high"})})`. Passing parts as separate arguments does not compile. `FileContentPart` and `InputAudioContentPart` cover files and audio; see `references/reference.md`.

## Provider Configuration

```go
// vLLM / Ollama / other OpenAI-compatible servers
local := openai.NewClient(
	option.WithBaseURL("http://localhost:8000/v1/"), // Ollama: http://localhost:11434/v1/
	option.WithAPIKey("not-needed"),                // placeholder; replaces any ambient Authorization
)

// Azure OpenAI v1 API with an API key
az := openai.NewClient(
	option.WithBaseURL("https://my-resource.openai.azure.com/openai/v1/"),
	option.WithAPIKey(os.Getenv("AZURE_OPENAI_API_KEY")),
)

// Azure deployments API with Entra ID (or azure.WithAPIKey)
azDeploy := openai.NewClient(
	azure.WithEndpoint("https://my-resource.openai.azure.com", "2024-10-21"),
	azure.WithTokenCredential(cred),
)

// Amazon Bedrock (returns an error; resolves AWS credentials eagerly)
bed, err := bedrock.NewClient(ctx, bedrock.Config{Endpoint: bedrock.EndpointRuntime, AWSRegion: "us-east-1"})
```

- `option.WithBaseURL` + `azure.WithAPIKey`/`azure.WithTokenCredential` fails since v3.53.0 (`requires azure.WithEndpoint`). For Entra ID on the v1 API, add the token in middleware (see `references/providers-auth.md`).
- Put the Azure deployment name in `Model`. Bedrock models are inference-profile IDs such as `us.openai.gpt-5.6-sol`.
- Keyed plain-HTTP requests work on every release except v3.69.0–v3.71.0. `option.WithUnsafeAllowHTTP()` is a no-op today; the restriction is planned to return in the next major version.

For OpenRouter, reasoning-field mapping, data residency, mutual TLS, workload identity, and X.509 authentication, read `references/providers-auth.md`.

## Production Configuration

```go
ctx, cancel := context.WithTimeout(ctx, 2*time.Minute) // bounds the whole call, retries included
defer cancel()
resp, err := client.Responses.New(ctx, params,
	option.WithRequestTimeout(45*time.Second), // per attempt, including the body; a timeout is not retried
)
```

- The default HTTP client clones `http.DefaultTransport` with a 10-minute `ResponseHeaderTimeout` and no overall timeout. Changing `http.DefaultClient` has no effect.
- Do not use `&http.Client{Timeout: ...}` for streaming or long reasoning calls: it cuts the body. To customize the transport, clone `http.DefaultTransport` and keep `ResponseHeaderTimeout`.
- Retries: 2 by default for connection errors, 408, 409, 429, and 5xx. `Retry-After` is honored up to 2 minutes; longer delays return the error immediately. `option.WithMaxRetryDelay` changes the caps.
- Log the `x-request-id` response header (from `apierr.Response` or `option.WithResponseInto`) for support tickets.
- `option.WithDebugLog` logs only method, size, status, and masked credential header names. Write middleware for richer logs:

```go
func Logger(req *http.Request, next option.MiddlewareNext) (*http.Response, error) {
	start := time.Now()
	resp, err := next(req)
	attrs := []any{"method", req.Method, "path", req.URL.Path, "duration", time.Since(start)}
	if resp != nil {
		attrs = append(attrs, "status", resp.StatusCode, "request_id", resp.Header.Get("x-request-id"))
	}
	slog.Info("openai request", attrs...)
	return resp, err
}

client := openai.NewClient(option.WithMiddleware(Logger))
```

Middleware runs client-level first, then per-request, and must not change the request's scheme, host, or port.

## Audio

```go
file, err := os.Open("recording.mp3")
if err != nil {
	return err
}
defer file.Close()
transcription, err := client.Audio.Transcriptions.New(ctx, openai.AudioTranscriptionNewParams{
	Model: openai.AudioModelGPT4oTranscribe,
	File:  file,
})
if err != nil {
	return err
}
fmt.Println(transcription.Text)

speech, err := client.Audio.Speech.New(ctx, openai.AudioSpeechNewParams{
	Model: openai.SpeechModelGPT4oMiniTTS,
	Input: "Hello from the OpenAI Go SDK.",
	Voice: openai.AudioSpeechNewParamsVoiceUnion{OfString: openai.String("marin")},
})
if err != nil {
	return err
}
defer speech.Body.Close()
_, err = io.Copy(out, speech.Body) // audio stream (mp3 by default)
```

- `Voice` is a union since v3.28.0: built-in names via `OfString`, custom voices via `OfAudioSpeechNewsVoiceID: &openai.AudioSpeechNewParamsVoiceID{ID: "voice_..."}`. The old `AudioSpeechNewParamsVoiceAlloy` constants are gone.
- For `text`, `srt`, or `vtt` transcription output, call `client.Post(ctx, "audio/transcriptions", params, &str)`; the typed method only decodes JSON.

## Deprecated Surfaces

- Assistants and Threads: use Responses (`Instructions`, `PreviousResponseID` or Conversations, `file_search`) or beta Agents.
- Sora (`client.Videos`): shut down on 2026-09-24; the SDK has no replacement.
- MCP `ConnectorID`: use `ServerURL` or `TunnelID`. DALL-E and `Images.NewVariation`: use GPT Image models and edits.
- Chat `MaxTokens`, `Functions`, `FunctionCall`: use `MaxCompletionTokens`, `Tools`, `ToolChoice`.

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/version-notes.md` | Go compatibility, stale patterns by version, breaking changes within v3, release highlights | Upgrading, fixing compile errors in older code, or unsure whether a remembered API is current |
| `references/reference.md` | Package and service map, all options, model constants and deprecations, Chat/Responses types, accumulator, respjson/param, errors, retries, pagination, files, images, embeddings, audio | Looking up a type, option, constant, or utility |
| `references/responses-advanced.md` | Function-call outputs, streaming events, tool catalog, file search filters, compaction, prompt caching, moderation, service tiers, Conversations, Responses WebSockets | Building agent loops or using advanced Responses features |
| `references/new-apis.md` | Beta Agents API, Live, Decisions, Realtime additions, webhooks, Safety, provenance checks, Skills, Admin, deprecated surfaces | Using any API added after early 2026 or handling webhooks |
| `references/providers-auth.md` | Credential sources, vLLM/Ollama/OpenRouter, plain-HTTP policy, Azure, Bedrock, data residency, mTLS, workload identity, X.509, admin keys | Configuring non-default endpoints or authentication |
