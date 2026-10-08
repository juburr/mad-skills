# SDK Version Notes

Release history and behavior changes for `github.com/openai/openai-go`, from the alpha through **v3.73.0** (the version this skill is verified against, released 2026-10-06). Use this file to reconcile outdated knowledge: if a pattern you remember appears under "Stale Patterns", it no longer applies.

## Compatibility

| SDK version | Go | Notes |
|---|---|---|
| v3.71.1 – v3.73.0 | 1.25+ | Recommended. Plain-HTTP credential restriction reverted |
| v3.69.0 – v3.71.0 | 1.25+ | **Avoid with `http://` endpoints**: keyed requests to non-loopback HTTP fail |
| v3.45.0 – v3.68.0 | 1.25+ | Go 1.25 minimum introduced in v3.45.0 |
| v3.44.0 | 1.22+ | Last release for Go 1.22–1.24; no security backports |
| v3.0.0 – v3.43.0 | 1.22+ | |
| v2.x | 1.22+ | Import path `github.com/openai/openai-go/v2` |
| v1.x | 1.22+ | Import path `github.com/openai/openai-go` |

The SDK supports the current and previous stable Go releases. Minimum Go bumps ship in minor releases without changing the `/v3` import path. Minor releases may contain small breaking changes in generated types (see "Breaking Changes Within v3").

## Stale Patterns

### If your knowledge predates v3.71

- **`err.Error()` contains the API message** — no. Since v3.71.0, `(*openai.Error).Error()`, `%v`, `%#v`, and slog values are only `OpenAI API error: 400 Bad Request`. Read `apierr.Message`, `Code`, `Type`, `Param`, `StatusCode` via `errors.As`.
- **`ChatModelGPT5`, `ChatModelO3`, `ChatModelO4Mini` are safe defaults** — since v3.71.0 many model constants carry `Deprecated:` shutdown notices; staticcheck SA1019 flags them. `ChatModelGPT5_1Mini` is "not a supported model ID".
- **`client.Videos` (Sora)** — deprecated in v3.51.0; the service shut down on 2026-09-24.

### If your knowledge predates v3.54

- **`CallID: call.CallID` on `ResponseInputItemFunctionCallOutputParam`** — `CallID` is `param.Opt[string]`; write `openai.String(call.CallID)`.
- **`responses.ResponseInputItemParamOfFunctionCallOutput(callID, output)`** — the helper takes only `output`; set `.OfFunctionCallOutput.CallID` afterwards.
- **`item.Arguments` is a string on `ResponseOutputItemUnion`** — it is a union; use `item.AsFunctionCall().Arguments`.
- **`ResponseFunctionCallArgumentsDoneEvent.Name`** — removed (v3.57.0); track the name from `response.output_item.added`.
- **`WithDebugLog` shows request bodies** — since v3.53.0 it logs method, length, status, and credential header names (values masked) only.
- **`client.Get(ctx, "https://other-host/...")`** — since v3.53.0 only relative paths are allowed; host-rewriting middleware and cross-origin redirects fail.
- **`shared.CompoundFilterParam{Filters: []shared.ComparisonFilterParam{...}}`** — `Filters` is `[]shared.CompoundFilterFilterUnionParam` (nested filters).
- **Azure: `option.WithBaseURL(...)` + `azure.WithAPIKey(...)` or `azure.WithTokenCredential(...)`** — fails since v3.53.0 with `azure: authentication requires azure.WithEndpoint`. Use `azure.WithEndpoint` for the deployments API, or `option.WithBaseURL(".../openai/v1/")` + `option.WithAPIKey` for the v1 API.
- **`AddChunk` accepts any chunk** — since v3.53.0 it returns `false` for choice index > 127, tool index < -1, or sparse tool-index jumps of 128+; ignoring the bool drops data.

### If your knowledge predates v3.45

- **Go 1.22 is enough** — v3.45.0+ requires Go 1.25.
- **The default HTTP client is `http.DefaultClient`** — since v3.33.0 the SDK uses a clone of `http.DefaultTransport` with a 10-minute `ResponseHeaderTimeout`. Mutating `http.DefaultClient` has no effect.
- **`Retry-After` is ignored above 60 seconds** — since v3.67.0 it is honored up to 2 minutes; longer delays (or delays above `WithMaxRetryDelay`) stop retrying and return the error.
- **`PromptCacheRetention: "in-memory"`** — the wire value is `"in_memory"` since v3.33.0; use `ResponseNewParamsPromptCacheRetentionInMemory`. The field is deprecated in favor of `PromptCacheOptions.Ttl`.

### If your knowledge predates v3.28

- **`Voice: openai.AudioSpeechNewParamsVoiceAlloy`** — removed. `Voice` is `openai.AudioSpeechNewParamsVoiceUnion{OfString: openai.String("alloy")}` or `{OfAudioSpeechNewsVoiceID: &openai.AudioSpeechNewParamsVoiceID{ID: "voice_..."}}`. Chat audio output changed the same way (`ChatCompletionAudioParamVoiceUnion`).
- **`OfComputerUsePreview: &responses.ComputerToolParam{...}`** — the preview tool is `ComputerUsePreviewToolParam` with `ComputerUsePreviewToolEnvironment*`; `ComputerToolParam` is now the GA tool under `OfComputer` (v3.26.0).

### Patterns that were never valid in v3

- **`Reasoning: shared.ReasoningParam{...}` on `openai.ChatCompletionNewParams`** — Chat Completions uses `ReasoningEffort: openai.ReasoningEffortHigh`. `shared.ReasoningParam` belongs to Responses.
- **`openai.UserMessage(part1, part2)`** — takes one argument: a string or `[]openai.ChatCompletionContentPartUnionParam`.
- **`openai.SystemMessage` is an alias for developer** — it sends `role: system`.
- **`openai.ModelListParams{}`** — `client.Models.List(ctx)` takes no params.
- **`if err := acc.AddChunk(chunk); err != nil`** — `AddChunk` returns `bool`.
- **`webhooks.Verify(body, headers, secret)`** — use `client.Webhooks.Unwrap(body, headers)` or `client.Webhooks.VerifySignature(body, headers)`.
- **`Stop: []string{...}`** — `Stop` is `openai.ChatCompletionNewParamsStopUnion{OfStringArray: []string{...}}`.
- **`option.WithQuerySet`** — does not exist (the SDK README mentions it); use `option.WithQuery`.
- **Subpackages `chat/`, `audio/`, `images/`, `embeddings/`, `files/`, `param/`, `respjson/`** — chat, audio, images, embeddings, files, and vector stores are in the root `openai` package; utilities live under `packages/` (`packages/param`, `packages/respjson`, `packages/ssestream`, `packages/pagination`, `packages/websocket`).

### If your knowledge predates v3.0

- **`github.com/openai/openai-go` or `/v2` import paths** — use `/v3`.
- **`openai.ChatCompletionToolParam{Function: ...}`** — v2.0.0 made tools a union: `openai.ChatCompletionFunctionTool(openai.FunctionDefinitionParam{...})` returns `ChatCompletionToolUnionParam`.
- **Function call output is always a string** — v3.0.0 made `output` a union of string or content list (`OfString`, or images and files).
- **`openai.F(...)` and `param.Field[T]`** — removed before v1. Optional fields are `param.Opt[T]` built with `openai.String`, `openai.Int`, `openai.Float`, `openai.Bool`, or `openai.Opt`.
- **`sashabaranov/go-openai`** — a separate community package with a different API. Do not mix it with this SDK.

## Breaking Changes Within v3

Compile errors an upgrade from v3.24.0 can hit:

| Version | Change |
|---|---|
| v3.25.0 | `ResponseOutputItemUnion.Arguments` became a union (`OfString`, tool-search arguments) |
| v3.26.0 | `ComputerToolParam` became the GA computer tool; preview moved to `ComputerUsePreviewToolParam` |
| v3.28.0 | Speech `Voice` and chat audio `Voice` became unions; `AudioSpeechNewParamsVoice*` constants removed |
| v3.38.0 | Web search action `Query` became `param.Opt[string]` |
| v3.42.0 | `responses.NewApplyPatchToolParam()` removed; use `&responses.ApplyPatchToolParam{}` |
| v3.51.0 | MCP call `Error` and annotation-added event `Annotation` became typed unions |
| v3.53.0 | Compound file-search filters became recursive unions (`[]shared.CompoundFilterFilterUnionParam`) |
| v3.54.0 | Function call output `CallID` became optional (`param.Opt[string]`); `ResponseInputItemParamOfFunctionCallOutput` lost its `callID` argument |
| v3.57.0 | `ResponseFunctionCallArgumentsDoneEvent.Name` removed |
| v3.73.0 | `responses.ToolCodeInterpreterContainerCodeInterpreterToolAutoNetworkPolicyUnionParam` renamed to `ResponseToolSearchOutputItemParamToolCodeInterpreterContainerCodeInterpreterToolAutoNetworkPolicyUnion` (struct literals that omit the type name are unaffected) |

Behavior changes that still compile:

| Version | Change |
|---|---|
| v3.33.0 | Default HTTP client with 10-minute response-header timeout; `OPENAI_CUSTOM_HEADERS`; `"in-memory"` → `"in_memory"` |
| v3.53.0 | Origin enforcement for credentials; Azure provider rules (`option.WithBaseURL` + `azure.WithAPIKey`/`WithTokenCredential` fails at request time); metadata-only debug log; accumulator index validation and linear accumulation; `JustFinishedToolCall` fires when `content:""` accompanies tool calls |
| v3.54.0 | Unset `CallID` silently omits `call_id` |
| v3.67.0 | Retry-After honored up to 2 minutes; longer stops retries |
| v3.69.0 – v3.71.0 | Keyed plain-HTTP requests refused (reverted in v3.71.1) |
| v3.71.0 | Safe `Error()` strings; model `Deprecated:` markers |

## Release Highlights

### v3.60.0 – v3.73.0 (September – October 2026)
- **v3.73.0**: standalone Decisions API (`client.Decisions`).
- **v3.72.0**: Agents `OnToolError` for local tool failures; turn items listing.
- **v3.71.0 – v3.71.2**: custom voices (`client.Audio.Voices`), agent session webhooks, safe API error strings, HTTP restriction reverted, bounded sparse tool-call growth in the chat accumulator.
- **v3.69.0 – v3.70.0**: Agents typed output (`NewBetaAgentOutput`) and final-result collection, file preparation and artifact downloads, Realtime translation client secrets and session traces, `"original"` image detail, Azure origin validation.
- **v3.67.0 – v3.68.0**: Agents credentials and computer use, Cyber access programs, `gpt-6.1-sol`, WebSocket `ResponseAccumulator` snapshots, Python-aligned Retry-After.
- **v3.65.0 – v3.66.0**: `gpt-6-sol`, `gpt-6-luna`, `gpt-rosalind-research`, GCP external storage.
- **v3.62.0 – v3.64.0**: managed Responses WebSockets (`client.Responses.Connect`), prompt-cache prewarming, compaction progress events, webhook endpoint management, safety cases and webhooks, MCP `ConnectorID` deprecated.
- **v3.60.0 – v3.61.0**: Live API (`client.Live`) and beta Agents API (`client.Beta.Agents`).

### v3.50.0 – v3.59.0 (August – September 2026)
- **v3.58.0**: GPT Image 2.5 (Sunburst, Flare) and `xhigh`/`max` image quality.
- **v3.57.0**: prompt cache diagnostics.
- **v3.56.0**: `gpt-6-astra`.
- **v3.55.0**: provider dependencies (AWS, Azure) isolated from root-package consumers.
- **v3.54.0**: function call output `CallID` optional.
- **v3.53.0**: X.509 workload identity, data residency (`option.WithDataResidency`), `ChatCompletionChunk.Obfuscation`, Realtime call creation, and broad hardening (origins, retries, multipart, webhooks, accumulator).
- **v3.52.0**: Amazon Bedrock (`bedrock` package).
- **v3.51.0**: `gpt-5.5-pro`, Daybreak and `gpt-5.6-cyber` models, WebSocket stream IDs, Ultrafast tier, typed MCP and annotation unions, Sora deprecated.
- **v3.50.0**: `gpt-5.5`.

### v3.39.0 – v3.49.0 (June – July 2026)
- **v3.49.0**: content provenance checks.
- **v3.48.0**: Fast service tier.
- **v3.47.0**: `gpt-transcribe` with `Keywords` and `Languages`.
- **v3.45.0**: Go 1.25 required.
- **v3.46.0**: admin spend limits (spend alerts arrived in v3.40.0).
- **v3.42.0**: `gpt-5.6-sol`/`terra`/`luna` and `ReasoningEffortMax`.
- **v3.39.0**: `Moderation` on Responses and Chat Completions.

### v3.25.0 – v3.38.0 (March – June 2026)
- **v3.38.0**: `additional_tools` item; web search `Query` optional.
- **v3.35.0**: Realtime 2, Realtime translate, GPT Image 2.
- **v3.34.0**: admin API keys (`option.WithAdminAPIKey`).
- **v3.33.0**: default HTTP client with timeout, `OPENAI_CUSTOM_HEADERS`.
- **v3.31.0**: workload identity (`option.WithWorkloadIdentity`, `auth` package); `phase` on conversation messages.
- **v3.29.0**: `gpt-5.4-mini`, `gpt-5.4-nano`; `in`/`nin` filters.
- **v3.28.0**: function tool `DeferLoading`, custom voices, voice union (breaking).
- **v3.26.0**: GA computer tool.
- **v3.25.0**: `gpt-5.4`, tool search tool.

### Earlier Milestones
- **v3.0.0** (2025-09-30): function call output became string-or-content union; import path `/v3`.
- **v2.0.0** (2025-08-07): GPT-5; chat tools became `ChatCompletionToolUnionParam` with `ChatCompletionFunctionTool`.
- **v1.0.0** (2025-05-19): first stable release.

## Why Generated Code Is Often Wrong

1. The SDK was alpha/beta until May 2025; much training data uses `openai.F(...)`.
2. Three major versions shipped in five months (May – September 2025), and v3 has had 70+ minor releases with generated-type changes.
3. `sashabaranov/go-openai` predates the official SDK and has a different API.
4. Go's `/v2`, `/v3` import suffixes are easy to miss.
5. The SDK's own README contains snippets that do not compile against current releases (the Responses tool-calling `CallID`, `option.WithQuerySet`).
