# Reference

Type reference, options, model constants, param/respjson utilities, errors, retries, pagination, and file uploads for `github.com/openai/openai-go/v3` (verified against v3.73.0). Snippets assume `ctx context.Context` and `client openai.Client`.

## Package Structure

```
github.com/openai/openai-go/v3          package openai: client, Chat Completions, embeddings, files,
                                        images, audio, moderations, models, batches, uploads, vector
                                        stores, fine-tuning, graders, containers, skills, decisions,
                                        safety, admin, beta (agents, assistants, threads, chatkit)
├── responses/                          Responses API, Responses WebSockets, ResponseAccumulator
├── conversations/                      Conversations and conversation items
├── realtime/                           Realtime client secrets, calls, translation sessions
├── live/                               Live API (WebRTC/SIP control plane)
├── webhooks/                           Webhook verification, event types, endpoint management
├── shared/                             Shared types: ChatModel, ResponsesModel, ReasoningParam, filters
│   └── constant/                       Typed string constants used by unions
├── option/                             Client and request options
├── auth/                               Workload identity and X.509 workload identity
├── azure/                              Azure OpenAI options
├── bedrock/                            Amazon Bedrock client constructor
└── packages/
    ├── param/                          param.Opt, Null, NullStruct, Override, IsOmitted, IsNull
    ├── respjson/                       respjson.Field (Raw, Valid), Omitted, Null
    ├── ssestream/                      ssestream.Stream[T] for SSE streaming
    ├── pagination/                     Page, CursorPage, auto-pagers
    └── websocket/                      Options and DeliveryError for Responses WebSockets
```

Most root types are re-exported from `shared` (`openai.ChatModel`, `openai.ReasoningEffortHigh`, `openai.FunctionDefinitionParam`).

## Client Services

| Accessor | Purpose |
|---|---|
| `client.Responses` | Responses API (`New`, `NewStreaming`, `Get`, `GetStreaming`, `Delete`, `Cancel`, `Compact`, `Connect`, `InputItems`, `InputTokens`) |
| `client.Conversations` | Server-side conversation state and items |
| `client.Chat.Completions` | Chat Completions (`New`, `NewStreaming`, stored completion `Get`/`List`/`Update`/`Delete`) |
| `client.Embeddings`, `client.Moderations`, `client.Images`, `client.Audio` | Embeddings, moderation, image generation and edits, speech, transcription, translation, voices |
| `client.Files`, `client.Uploads`, `client.VectorStores`, `client.Batches` | Files, multipart uploads, vector stores for file search, batch jobs |
| `client.Models`, `client.FineTuning`, `client.Graders`, `client.Containers` | Model listing, fine-tuning, graders, code interpreter containers |
| `client.Decisions` | Ordered classification and scoring questions |
| `client.Beta.Agents` | Hosted agents, sessions, environments, vaults (beta) |
| `client.Beta.Responses` | Beta mirror of Responses with `Betas []string` |
| `client.Realtime`, `client.Live` | Realtime and Live voice control planes |
| `client.Webhooks` | Signature verification and endpoint management |
| `client.Skills`, `client.Safety`, `client.ContentProvenanceChecks` | Skill bundles, safety case/alert lookups, C2PA/SynthID checks |
| `client.Admin.Organization` | Admin API (requires admin key) |
| `client.Videos` | Deprecated: Sora shut down |
| `client.Beta.Assistants`, `client.Beta.Threads` | Deprecated: use Responses |

## Client Options (`option` package)

Every option works at client level (`openai.NewClient(opts...)`) or per request (the variadic `opts ...option.RequestOption` on every method). Per-request options override client options.

| Function | Purpose |
|---|---|
| `WithAPIKey(key)` | Bearer key. `WithAPIKey("")` sends no `Authorization` header |
| `WithAdminAPIKey(key)` | Admin key, used only by `client.Admin.Organization.*` |
| `WithBaseURL(url)` | Endpoint override (vLLM, Ollama, Azure v1, proxies) |
| `WithDataResidency(option.DataResidencyEU)` | Regional endpoint: `Global`, `US`, `EU`, `AE`. Exclusive with `WithBaseURL` in the same call |
| `WithOrganization(id)` / `WithProject(id)` | `OpenAI-Organization` / `OpenAI-Project` headers |
| `WithHTTPClient(c)` | Replace the HTTP client (also replaces the SDK's 10-minute header timeout) |
| `WithMiddleware(mw...)` | Request/response middleware |
| `WithMaxRetries(n)` | Default 2 |
| `WithMaxRetryDelay(d)` | Cap backoff and server-directed delays (default caps: 8s backoff, 2m `Retry-After`) |
| `WithRequestTimeout(d)` | Per-attempt deadline, including body reads and streams. A timed-out attempt is not retried |
| `WithHeader` / `WithHeaderAdd` / `WithHeaderDel` | Header edits |
| `WithQuery` / `WithQueryAdd` / `WithQueryDel` | Query parameter edits (there is no `WithQuerySet`) |
| `WithJSONSet(path, value)` / `WithJSONDel(path)` | Edit the JSON body with sjson paths |
| `WithRequestBody(contentType, body)` | Raw request body |
| `WithResponseInto(&httpResp)` / `WithResponseBodyInto(&v)` | Capture the raw `*http.Response` or decode the body into your own type |
| `WithDebugLog(logger)` | Metadata-only request/response logging (credential values masked, no URLs or bodies) |
| `WithWebhookSecret(secret)` | Webhook signing secret |
| `WithWorkloadIdentity(auth.WorkloadIdentity{...})` | Cloud identity token exchange instead of an API key |
| `WithX509WorkloadIdentity(auth.X509WorkloadIdentity{...})` | Certificate-based token exchange over mTLS |
| `WithUnsafeAllowHTTP()` | No-op since v3.71.1 (enforced only in v3.69.0–v3.71.0) |
| `WithEnvironmentProduction()` | Default `https://api.openai.com/v1/` |

## Model Constants

All model types (`shared.ChatModel`, `shared.ResponsesModel`, `openai.ImageModel`, ...) are `string` aliases; any string compiles and the server decides validity. Root aliases exist for each (`openai.ChatModelGPT5_5`).

### Current Chat Models (not deprecated)

| Constant | Model |
|---|---|
| `ChatModelGPT6_1Sol` | gpt-6.1-sol |
| `ChatModelGPT6Astra` | gpt-6-astra |
| `ChatModelGPT6Sol` / `ChatModelGPT6Luna` | gpt-6-sol / gpt-6-luna |
| `ChatModelGPT5_6Sol` / `ChatModelGPT5_6Terra` / `ChatModelGPT5_6Luna` | gpt-5.6-sol / -terra / -luna |
| `ChatModelGPT5_5` / `ChatModelGPT5_5_2026_04_23` | gpt-5.5 |
| `ChatModelGPT5_4` / `ChatModelGPT5_4Mini` / `ChatModelGPT5_4Nano` | gpt-5.4 family (dated `..._2026_03_17` for mini and nano) |
| `ChatModelGPT5_2` / `ChatModelGPT5_2Pro` / `ChatModelGPT5_1` | gpt-5.2, gpt-5.2-pro, gpt-5.1 (dated variants available) |
| `ChatModelGPT4_1` / `ChatModelGPT4_1Mini` | gpt-4.1 / gpt-4.1-mini |
| `ChatModelGPT4o` / `ChatModelGPT4oMini` | gpt-4o / gpt-4o-mini |

### Responses-Only Models

| Constant | Model |
|---|---|
| `ResponsesModelGPT5_5Pro` / `..._2026_04_23` | gpt-5.5-pro |
| `ResponsesModelGPT5_6Cyber` | gpt-5.6-cyber |
| `ResponsesModelGPTDaybreakBlueLatest` / `...RedLatest` | gpt-daybreak-blue/red-latest (use with `AccessPrograms.Cyber`) |
| `ResponsesModelGPTRosalindResearch` | gpt-rosalind-research |

### Deprecated Model Constants

Since v3.71.0 these carry Go `Deprecated:` notices (staticcheck SA1019):

| Constants | Announced shutdown |
|---|---|
| `ChatModelO1Preview`, `ChatModelO1Mini` | Already shut down (2025) |
| `ChatModelGPT5_1Codex`, `ChatModelGPT5_1ChatLatest`, `ChatModelGPT5ChatLatest`, `*SearchPreview*` | 2026-07-23 |
| `ChatModelGPT5_2ChatLatest`, `ChatModelGPT5_3ChatLatest` | 2026-08-10 |
| `ChatModelO4Mini`, `ChatModelO3Mini`, `ChatModelO1`, `ChatModelGPT4_1Nano`, `ChatModelGPT4Turbo`, `ChatModelGPT4`, `ChatModelGPT3_5Turbo` | 2026-10-23 |
| `ChatModelGPT5`, `ChatModelGPT5Mini`, `ChatModelGPT5Nano`, `ChatModelO3` (and dated variants) | 2026-12-11 |
| `ChatModelGPTAudioMini` | 2027-01-20 |
| `ChatModelGPT5_1Mini` | Not a supported model ID |
| `ResponsesModelO1Pro`, `O3Pro`, `O3DeepResearch`, `O4MiniDeepResearch`, `ComputerUsePreview`, `GPT5Codex`, `GPT5Pro` | Deprecated |

Pin dated snapshots (for example `ChatModelGPT5_5_2026_04_23`) for reproducible production behavior, and check the [deprecations page](https://developers.openai.com/api/docs/deprecations/) before adopting a model.

### Other Model Constants

| Area | Constants |
|---|---|
| Transcription (`AudioModel`) | `AudioModelGPTTranscribe` (supports `Keywords`, `Languages`), `AudioModelGPT4oTranscribe`, `AudioModelGPT4oMiniTranscribe`, `AudioModelGPT4oTranscribeDiarize`, `AudioModelWhisper1` |
| Speech (`SpeechModel`) | `SpeechModelGPT4oMiniTTS`, `SpeechModelTTS1`, `SpeechModelTTS1HD` |
| Images (`ImageModel`) | `ImageModelGPTImage2_5Sunburst`, `ImageModelGPTImage2_5Flare`, `ImageModelGPTImage2`, `ImageModelGPTImage1_5`, `ImageModelGPTImage1`, `ImageModelGPTImage1Mini`, `ImageModelChatgptImageLatest`; DALL-E 2/3 are retired |
| Embeddings | `EmbeddingModelTextEmbedding3Small`, `EmbeddingModelTextEmbedding3Large`, `EmbeddingModelTextEmbeddingAda002` |
| Realtime | `realtime.RealtimeSessionCreateRequestModelGPTRealtime2` and newer |
| Live | `live.MediaSessionConfigModelGPTLive1` |

## Reasoning Types

| Type | Values |
|---|---|
| `shared.ReasoningEffort` | `ReasoningEffortNone`, `Minimal`, `Low`, `Medium`, `High`, `Xhigh`, `Max` |
| `shared.ReasoningSummary` | `ReasoningSummaryAuto`, `Concise`, `Detailed` |
| `shared.ReasoningContext` | `ReasoningContextAuto`, `CurrentTurn`, `AllTurns` |
| `shared.ReasoningMode` | `ReasoningModeStandard`, `ReasoningModePro` |

- Responses: `ResponseNewParams.Reasoning` is `shared.ReasoningParam{Effort, Summary, Context, Mode}`.
- Chat Completions: `ChatCompletionNewParams.ReasoningEffort` only; no summaries.
- Reasoning token counts: Responses `Usage.OutputTokensDetails.ReasoningTokens`; Chat `Usage.CompletionTokensDetails.ReasoningTokens`.

## Chat Completions Types

### Key `ChatCompletionNewParams` Fields

| Field | Type / constructor |
|---|---|
| `Model` | `shared.ChatModel` |
| `Messages` | `[]ChatCompletionMessageParamUnion` |
| `Tools` | `[]ChatCompletionToolUnionParam` via `openai.ChatCompletionFunctionTool(...)` or `ChatCompletionCustomTool(...)` |
| `ToolChoice` | `ChatCompletionToolChoiceOptionUnionParam{OfAuto: openai.String("required")}` or `openai.ToolChoiceOptionFunctionToolChoice(...)` |
| `ResponseFormat` | `ChatCompletionNewParamsResponseFormatUnion{OfJSONSchema: &openai.ResponseFormatJSONSchemaParam{...}}` |
| `ReasoningEffort` | `openai.ReasoningEffortHigh` and friends |
| `MaxCompletionTokens` | `param.Opt[int64]`; `MaxTokens` is deprecated and unsupported by reasoning models |
| `Temperature`, `TopP`, `Seed`, `N` | `param.Opt[...]` |
| `Stop` | `ChatCompletionNewParamsStopUnion{OfString: ...}` or `{OfStringArray: []string{...}}` |
| `StreamOptions` | `ChatCompletionStreamOptionsParam{IncludeUsage, IncludeObfuscation}` |
| `ServiceTier` | `ChatCompletionNewParamsServiceTierAuto`, `Default`, `Flex`, `Scale`, `Priority`, `Fast` (no ultrafast) |
| `PromptCacheKey`, `PromptCacheOptions` | Cache routing and explicit caching (`Mode`, `Ttl`) |
| `SafetyIdentifier` | Stable hashed end-user ID |
| `Moderation` | `ChatCompletionNewParamsModeration{Model, Policy{Input{Mode}, Output{Mode}}}` |
| `Verbosity` | `ChatCompletionNewParamsVerbosityLow`, `Medium`, `High` |
| `Audio`, `Modalities` | Audio output; `Audio.Voice` is `ChatCompletionAudioParamVoiceUnion{OfString: openai.String("alloy")}` |
| `Functions`, `FunctionCall` | Deprecated; use `Tools` and `ToolChoice` |

### Message and Content Constructors

| Constructor | Argument |
|---|---|
| `openai.UserMessage(content)` | `string` or `[]openai.ChatCompletionContentPartUnionParam` (one argument, not variadic) |
| `openai.DeveloperMessage(content)` | `string` or `[]openai.ChatCompletionContentPartTextParam` |
| `openai.SystemMessage(content)` | Same; sends `role: system` (separate from developer) |
| `openai.AssistantMessage(content)` | `string` or assistant content parts |
| `openai.ToolMessage(content, toolCallID)` | Tool result for a tool call |
| `msg.ToParam()` | Converts a response `ChatCompletionMessage` (including tool calls) to a request message |
| `openai.TextContentPart(text)` | Text part |
| `openai.ImageContentPart(openai.ChatCompletionContentPartImageImageURLParam{URL, Detail})` | `Detail` is a string: `"auto"`, `"low"`, `"high"`, `"original"` |
| `openai.FileContentPart(openai.ChatCompletionContentPartFileFileParam{FileID / FileData / Filename})` | File part |
| `openai.InputAudioContentPart(openai.ChatCompletionContentPartInputAudioInputAudioParam{Data, Format})` | Audio input (`"wav"`, `"mp3"`) |

### Vision and Structured Output Examples

```go
// Image input: UserMessage takes ONE argument (a slice of parts)
vision, err := client.Chat.Completions.New(ctx, openai.ChatCompletionNewParams{
	Model: openai.ChatModelGPT5_5,
	Messages: []openai.ChatCompletionMessageParamUnion{
		openai.UserMessage([]openai.ChatCompletionContentPartUnionParam{
			openai.TextContentPart("What's in this image?"),
			openai.ImageContentPart(openai.ChatCompletionContentPartImageImageURLParam{
				URL:    "https://example.com/photo.png",
				Detail: "high",
			}),
		}),
	},
})
if err != nil {
	return err
}
fmt.Println(vision.Choices[0].Message.Content)

// Structured output with a JSON schema (map[string]any, see SKILL.md for generation)
structured, err := client.Chat.Completions.New(ctx, openai.ChatCompletionNewParams{
	Model:    openai.ChatModelGPT5_5,
	Messages: []openai.ChatCompletionMessageParamUnion{openai.UserMessage("Summarize Go")},
	ResponseFormat: openai.ChatCompletionNewParamsResponseFormatUnion{
		OfJSONSchema: &openai.ResponseFormatJSONSchemaParam{
			JSONSchema: openai.ResponseFormatJSONSchemaJSONSchemaParam{
				Name: "answer", Schema: schema, Strict: openai.Bool(true),
			},
		},
	},
})
if err != nil {
	return err
}
if msg := structured.Choices[0].Message; msg.Refusal == "" {
	err = json.Unmarshal([]byte(msg.Content), &answer)
}
```

### Response Types

| Field | Notes |
|---|---|
| `ChatCompletion.Choices[i].Message` | `Content`, `Refusal`, `ToolCalls`, `Audio`, `Annotations` |
| `Choices[i].FinishReason` | `"stop"`, `"length"`, `"tool_calls"`, `"content_filter"` |
| `Message.ToolCalls[j]` | `ID`, `Type` (`"function"` / `"custom"`), `Function.Name`, `Function.Arguments` (JSON string) |
| `Usage.PromptTokens`, `CompletionTokens`, `TotalTokens` | Token counts |
| `Usage.PromptTokensDetails` | `CachedTokens`, `CacheWriteTokens`, `AudioTokens`, `ImageTokens`, `TextTokens` |
| `Usage.CompletionTokensDetails` | `ReasoningTokens`, `AcceptedPredictionTokens`, `RejectedPredictionTokens`, `AudioTokens` |
| `ChatCompletionChunk.Obfuscation` | Side-channel padding; disable with `StreamOptions.IncludeObfuscation: openai.Bool(false)` |

### ChatCompletionAccumulator

`ChatCompletionAccumulator` embeds `ChatCompletion`; after the stream ends, `acc.ChatCompletion` (or `acc.Choices`) holds the assembled completion.

| Method | Returns |
|---|---|
| `AddChunk(chunk)` | `bool`; `false` means the chunk was rejected (ID mismatch, choice index outside 0–127, tool index below -1, sparse tool-index jump of 128+) |
| `JustFinishedContent()` | `(string, bool)` |
| `JustFinishedRefusal()` | `(string, bool)` |
| `JustFinishedToolCall()` | `(openai.FinishedChatCompletionToolCall, bool)`; fields `Index`, `ID`, `Name`, `Arguments` |
| `JustFinishedContentForChoice(i)` etc. | Per-choice variants for `N > 1`; the plain methods report only the first choice in the latest chunk |

- Each `JustFinished*` event is reported once, by the `AddChunk` call whose chunk ends that content or tool call (the last one ends on the `finish_reason` chunk); check them before printing that chunk's delta.
- The accumulated `Usage` omits `CacheWriteTokens`, `ImageTokens`, and `TextTokens`; read those from the final usage chunk.
- Copying an accumulator by value shares the `Choices` slice; `slices.Clone` it before the copies diverge.
- Accumulation is linear in stream length (it was quadratic before v3.53.0).

## Responses Types

### Key `ResponseNewParams` Fields

| Field | Type |
|---|---|
| `Model` | `shared.ResponsesModel` (accepts `openai.ChatModel*` constants) |
| `Input` | `ResponseNewParamsInputUnion{OfString}` or `{OfInputItemList: responses.ResponseInputParam{...}}` |
| `Instructions` | `param.Opt[string]`; not carried over by `PreviousResponseID` |
| `PreviousResponseID` / `Conversation` | Conversation state (use one) |
| `Tools`, `ToolChoice`, `ParallelToolCalls`, `MaxToolCalls` | Tool configuration |
| `Text` | `ResponseTextConfigParam{Format, Verbosity}` |
| `Reasoning` | `shared.ReasoningParam` |
| `MaxOutputTokens`, `Temperature`, `TopP`, `TopLogprobs` | Sampling |
| `Store`, `Background`, `Include`, `Metadata`, `Truncation` | Storage, background mode, extra output, truncation strategy |
| `ContextManagement` | Server-side compaction |
| `PromptCacheKey`, `PromptCacheOptions` | Prompt caching (`PromptCacheRetention` is deprecated) |
| `SafetyIdentifier`, `Moderation`, `ServiceTier`, `AccessPrograms` | Safety, moderation, latency tier, cyber programs |

### Input Item Helpers

| Helper | Creates |
|---|---|
| `responses.ResponseInputItemParamOfMessage(content, role)` | Message (`responses.EasyInputMessageRoleUser`, `...Assistant`, `...System`, `...Developer`) |
| `responses.ResponseInputItemParamOfFunctionCallOutput(output)` | Function result; then set `.OfFunctionCallOutput.CallID = openai.String(id)` |
| `responses.ResponseInputItemParamOfCustomToolCallOutput(callID, output)` | Custom tool result |
| `responses.ResponseInputItemParamOfComputerCallOutput(callID, screenshot)` | Computer tool result |
| `param.Override[responses.ResponseInputItemUnionParam](json.RawMessage(item.RawJSON()))` | Resend an output item verbatim |

### Output Items

| `item.Type` | Accessor |
|---|---|
| `"message"` | `item.AsMessage()` |
| `"function_call"` | `item.AsFunctionCall()` (`Name`, `Arguments`, `CallID`, `Namespace`) |
| `"reasoning"` | `item.AsReasoning()` |
| `"web_search_call"`, `"file_search_call"` | `item.AsWebSearchCall()`, `item.AsFileSearchCall()` |
| `"mcp_call"`, `"mcp_list_tools"`, `"mcp_approval_request"` | `item.AsMcpCall()` (typed `Error` union), ... |
| `"computer_call"`, `"shell_call"`, `"custom_tool_call"`, `"tool_search_call"`, `"program"` | Matching `As*` methods |

`resp.OutputText()` concatenates every `output_text` part. `resp.Status` is `completed`, `incomplete`, `failed`, `in_progress`, `queued`, or `cancelled`; check `resp.IncompleteDetails.Reason` for `max_output_tokens` truncation.

## respjson.Field API

Every response struct has a `.JSON` field with one `respjson.Field` per known property plus `ExtraFields map[string]respjson.Field`.

| Expression | Meaning |
|---|---|
| `f.Valid()` | Present, non-null, and decoded successfully |
| `f.Raw()` | Raw JSON literal (strings keep their quotes) |
| `f.Raw() == respjson.Omitted` | Absent from the JSON (`""`) |
| `f.Raw() == respjson.Null` | Explicit `null` |
| `resp.RawJSON()` | The whole raw JSON object |
| `resp.JSON.ExtraFields["name"]` | Field the SDK does not model; `Valid()` is false for extra fields, so check `Raw()` |

```go
completion, err := client.Chat.Completions.New(ctx, params)
if err != nil {
	return err
}
msg := completion.Choices[0].Message
if msg.JSON.Refusal.Valid() {
	fmt.Println("refused:", msg.Refusal)
}
if f, ok := completion.Usage.JSON.ExtraFields["compute_units"]; ok {
	fmt.Println("compute units:", f.Raw()) // no typed field exists
}
```

## param Package and Optional Fields

| Function | Purpose |
|---|---|
| `openai.String(s)`, `openai.Int(n)`, `openai.Float(f)`, `openai.Bool(b)` | Set a `param.Opt[T]` field |
| `openai.Opt(v)` | Generic `param.Opt[T]` constructor (typed enums) |
| `param.Null[T]()` | Send explicit `null` for a `param.Opt[T]` |
| `param.NullStruct[T]()` | Send explicit `null` for a struct |
| `param.IsOmitted(v)` / `param.IsNull(v)` | Inspect a field |
| `param.Override[T](value)` | Send an arbitrary JSON value where a struct is expected |
| `params.SetExtraFields(map[string]any{...})` | Add or override body fields (keys are emitted in sorted order since v3.64.1) |

- Zero values of `param.Opt[T]`, slices, maps, structs, and enums are omitted (`omitzero`).
- Required primitive fields (tagged `api:"required"`) always serialize, even as zero.
- Union params have one `Of*` field per variant; set exactly one. `Get*` methods return pointers to shared sub-fields.
- Enum-like string fields are not validated client-side.
- Extra fields override struct fields with the same key; only pass trusted data.

## Errors

`*openai.Error` (alias of the internal `apierror.Error`):

| Member | Content |
|---|---|
| `StatusCode` | HTTP status |
| `Code`, `Type`, `Param`, `Message` | API error body fields |
| `Request`, `Response` | Raw `*http.Request` / `*http.Response` |
| `RawJSON()` | Raw error JSON |
| `DumpRequest(body)` / `DumpResponse(body)` | `httputil` dumps; **include `Authorization` headers verbatim** |
| `Error()`, `%v`, slog value | `OpenAI API error: <status> <text>` only (since v3.71.0) |

```go
var apierr *openai.Error
switch {
case errors.As(err, &apierr):
	slog.Error("openai api error",
		"status", apierr.StatusCode, "type", apierr.Type, "code", apierr.Code,
		"param", apierr.Param, "message", apierr.Message,
		"request_id", apierr.Response.Header.Get("x-request-id"))
case errors.Is(err, context.DeadlineExceeded):
	slog.Error("openai request timed out") // not retried
default:
	slog.Error("openai transport error", "err", err) // *url.Error may contain URLs
}
```

## Retries and Timeouts

| Behavior | Detail |
|---|---|
| Default retries | 2 (3 attempts) with exponential backoff (0.5s doubling, capped at 8s, up to 25% jitter) |
| Retried | Connection errors, 408, 409, 429, ≥500; `x-should-retry: true/false` overrides |
| `Retry-After` / `Retry-After-Ms` | Honored up to 2 minutes; a longer delay stops retrying and returns the error |
| Non-replayable bodies | Never retried |
| Default HTTP client | Cloned `http.DefaultTransport`, `ResponseHeaderTimeout` 10 minutes, no overall timeout |
| `WithRequestTimeout(d)` | Per attempt, covers the body; a timed-out attempt ends the call |
| `context.WithTimeout` | Bounds the whole call including retries and streaming |
| `&http.Client{Timeout: d}` | Cuts streams and long reasoning responses at `d`; avoid for streaming |

```go
// Custom transport that keeps the SDK's header timeout and streams safely
base, ok := http.DefaultTransport.(*http.Transport)
if !ok {
	return errors.New("http.DefaultTransport is wrapped; configure your own *http.Transport")
}
tr := base.Clone()
tr.ResponseHeaderTimeout = 10 * time.Minute
tr.MaxIdleConnsPerHost = 32
client := openai.NewClient(
	option.WithHTTPClient(&http.Client{Transport: tr}),
	option.WithMaxRetries(3),
)
```

## Raw Requests and Undocumented Fields

```go
// Undocumented endpoint (path is relative to the base URL; absolute URLs are rejected)
var out map[string]any
err := client.Post(ctx, "some/new/endpoint", map[string]any{"x": 1}, &out)

// Undocumented body field or query parameter on a typed call
resp, err := client.Responses.New(ctx, params,
	option.WithJSONSet("experimental.flag", true),
	option.WithQuery("trace", "1"),
)

// Raw HTTP response (headers, request ID)
var httpResp *http.Response
resp, err = client.Responses.New(ctx, params, option.WithResponseInto(&httpResp))
if err == nil {
	fmt.Println(httpResp.Header.Get("x-request-id"))
}
```

`client.Get`, `Post`, `Put`, `Patch`, `Delete`, and `Execute` respect client options (auth, retries, middleware). Text transcription formats (`text`, `srt`, `vtt`) must use `client.Post(ctx, "audio/transcriptions", params, &str)` because the typed method only decodes JSON.

## Pagination

```go
// Auto-pagination
iter := client.FineTuning.Jobs.ListAutoPaging(ctx, openai.FineTuningJobListParams{Limit: openai.Int(20)})
for iter.Next() {
	job := iter.Current()
	fmt.Println(job.ID, job.Status)
}
if err := iter.Err(); err != nil {
	return err
}

// Manual pages
page, err := client.FineTuning.Jobs.List(ctx, openai.FineTuningJobListParams{Limit: openai.Int(20)})
for page != nil && err == nil {
	for _, job := range page.Data {
		fmt.Println(job.ID)
	}
	page, err = page.GetNextPage()
}
if err != nil {
	return err
}

// Models take no params
models := client.Models.ListAutoPaging(ctx)
for models.Next() {
	fmt.Println(models.Current().ID)
}
```

Request options (headers, base URL) carry over to subsequent pages since v3.53.0.

## File Uploads and Vector Stores

Multipart file fields are `io.Reader`. `*os.File` sends its file name; wrap other readers with `openai.File(reader, name, contentType)`.

```go
f, err := os.Open("handbook.pdf")
if err != nil {
	return err
}
defer f.Close()

vs, err := client.VectorStores.New(ctx, openai.VectorStoreNewParams{Name: openai.String("handbook")})
if err != nil {
	return err
}
// Uploads the file, attaches it, and polls until processing finishes (0 = default 1s interval).
vsFile, err := client.VectorStores.Files.UploadAndPoll(ctx, vs.ID, openai.FileNewParams{
	File:    f,
	Purpose: openai.FilePurposeAssistants,
}, 0)
if err != nil {
	return err
}
fmt.Println(vsFile.Status) // use vs.ID with the file_search tool
```

File purposes: `FilePurposeAssistants`, `FilePurposeBatch`, `FilePurposeFineTune`, `FilePurposeVision`, `FilePurposeUserData`, `FilePurposeEvals`.

## Images and Embeddings

```go
img, err := client.Images.Generate(ctx, openai.ImageGenerateParams{
	Model:        openai.ImageModelGPTImage2_5Flare,
	Prompt:       "A watercolor gopher reading a book",
	Size:         openai.ImageGenerateParamsSize("1536x864"), // GPT image 2+ accept custom WxH (multiples of 16)
	Quality:      openai.ImageGenerateParamsQualityHigh,
	OutputFormat: openai.ImageGenerateParamsOutputFormatPNG,
})
if err != nil {
	return err
}
png, err := base64.StdEncoding.DecodeString(img.Data[0].B64JSON) // GPT image models return base64, not URLs
if err != nil {
	return err
}

emb, err := client.Embeddings.New(ctx, openai.EmbeddingNewParams{
	Model:      openai.EmbeddingModelTextEmbedding3Small,
	Input:      openai.EmbeddingNewParamsInputUnion{OfArrayOfStrings: []string{"hello", "world"}},
	Dimensions: openai.Int(256),
})
```

- `ImageGenerateParamsQualityXhigh` and `...Max` apply to GPT Image 2.5 only. `QualityStandard`/`HD`, `Style`, and `ResponseFormat` are DALL-E-era and unsupported for GPT image models.
- `client.Images.GenerateStreaming` / `EditStreaming` stream partial images (`PartialImages` 0–3).
- `emb.Data[i].Embedding` is `[]float64`.

## Audio Details

| Task | API |
|---|---|
| Built-in voice | `Voice: openai.AudioSpeechNewParamsVoiceUnion{OfString: openai.String("marin")}` (alloy, ash, ballad, coral, echo, fable, nova, onyx, sage, shimmer, verse, marin, cedar) |
| Custom voice | `Voice: openai.AudioSpeechNewParamsVoiceUnion{OfAudioSpeechNewsVoiceID: &openai.AudioSpeechNewParamsVoiceID{ID: "voice_..."}}` |
| Create a voice | `client.Audio.Voices.New(ctx, openai.AudioVoiceNewParams{OfAudioSample: ...})` (audio sample + consent ID) or `{OfPrompt: ...}` (Live only) |
| Transcribe with hints | `openai.AudioTranscriptionNewParams{Model: openai.AudioModelGPTTranscribe, Keywords: []string{...}, Languages: []string{"en"}}` |
| Translate to English | `client.Audio.Translations.New` |

## Middleware

```go
type MiddlewareNext = func(*http.Request) (*http.Response, error)
type Middleware = func(*http.Request, MiddlewareNext) (*http.Response, error)
```

- Client middleware runs first, then per-request middleware, then provider authentication (Azure, Bedrock, workload identity), then the HTTP client.
- Middleware sees requests without provider credentials and must not change scheme, host, or port.
- `resp` is nil when `next` returns an error; guard before reading `resp.StatusCode`.
