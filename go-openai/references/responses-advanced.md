# Responses API: Advanced Usage

Tool results, streaming events, the full tool catalog, compaction, prompt caching, moderation, service tiers, Conversations, and Responses WebSockets for `github.com/openai/openai-go/v3` (verified against v3.73.0). All snippets assume `ctx context.Context` and `client openai.Client`.

## Returning Function Call Results

Since v3.54.0, `ResponseInputItemFunctionCallOutputParam.CallID` is `param.Opt[string]`, and the helper `responses.ResponseInputItemParamOfFunctionCallOutput` no longer takes a call ID. The SDK's own README tool-calling sample still uses the old form and does not compile.

```go
var outputs []responses.ResponseInputItemUnionParam
for _, item := range resp.Output {
	if item.Type != "function_call" {
		continue
	}
	fc := item.AsFunctionCall()
	result := runTool(fc.Name, fc.Arguments) // fc.Arguments is a JSON string

	out := responses.ResponseInputItemParamOfFunctionCallOutput(result)
	out.OfFunctionCallOutput.CallID = openai.String(fc.CallID) // required in practice
	outputs = append(outputs, out)
}
resp, err = client.Responses.New(ctx, responses.ResponseNewParams{
	Model:              openai.ChatModelGPT5_5,
	PreviousResponseID: openai.String(resp.ID),
	Input:              responses.ResponseNewParamsInputUnion{OfInputItemList: outputs},
	Tools:              tools, // resend tools on every turn
})
```

| Pitfall | Effect |
|---|---|
| `CallID: call.CallID` | Compile error: `string` is not `param.Opt[string]` |
| `ResponseInputItemParamOfFunctionCallOutput(callID, out)` | Compile error: too many arguments |
| Forgetting to set `CallID` | Compiles, but the request silently omits `call_id` and the API rejects it |
| `item.Arguments` as a string | Compile error: it is now a union (`item.Arguments.OfString`); use `item.AsFunctionCall().Arguments` |

Only function-call output changed. These helpers still take `callID string` as the first argument: `ResponseInputItemParamOfCustomToolCallOutput`, `ResponseInputItemParamOfComputerCallOutput`, `ResponseInputItemParamOfShellCallOutput`, `ResponseInputItemParamOfApplyPatchCallOutput`.

## Streaming Events

`client.Responses.NewStreaming` returns `*ssestream.Stream[responses.ResponseStreamEventUnion]`. Switch on `AsAny()` and keep the full response from the terminal event. `Close` is idempotent; defer it so early exits release the connection.

```go
stream := client.Responses.NewStreaming(ctx, params)
defer func() { _ = stream.Close() }()

var final *responses.Response
for stream.Next() {
	switch e := stream.Current().AsAny().(type) {
	case responses.ResponseTextDeltaEvent:
		fmt.Print(e.Delta)
	case responses.ResponseCompletedEvent:
		final = &e.Response
	case responses.ResponseIncompleteEvent:
		final = &e.Response // check final.IncompleteDetails.Reason
	case responses.ResponseFailedEvent:
		return fmt.Errorf("response failed: %s", e.Response.Error.Message)
	case responses.ResponseErrorEvent:
		return fmt.Errorf("stream error %s: %s", e.Code, e.Message)
	}
}
if err := stream.Err(); err != nil {
	return err
}
if final == nil {
	return errors.New("stream ended without a terminal event")
}
```

- Do not `print(event.Delta)` for every event. Shell-output delta events carry JSON (`{"stdout":"..."}`) in `Delta`. Filter on `response.output_text.delta`.
- `ResponseFunctionCallArgumentsDoneEvent.Name` was removed (v3.57.0). Track the tool name from the `response.output_item.added` event.
- `ResponseOutputTextAnnotationAddedEvent.Annotation` is a typed union, not `any`.
- New event types: `response.compaction.compacting`, `response.shell_call_command.added|delta|done`, `response.shell_call_output_content.delta|done`.
- `responses.ResponseAccumulator` accepts `responses.ResponsesServerEventUnion` (WebSocket events) only. Over SSE, use the `Response` carried by the terminal event.

## Tool Catalog

`responses.ToolUnionParam` variants:

| Field | Param type | Notes |
|---|---|---|
| `OfFunction` | `FunctionToolParam` | `DeferLoading` (load via tool search), `Strict`, `AllowedCallers` (`"direct"`, `"programmatic"`), `OutputSchema` |
| `OfCustom` | `CustomToolParam` | Freeform text or grammar input via `shared.CustomToolInputFormatUnionParam` |
| `OfToolSearch` | `ToolSearchToolParam` | Searches deferred tools. `Execution`: `ToolSearchToolExecutionServer` or `...Client` |
| `OfNamespace` | `NamespaceToolParam` | Groups function/custom tools; build with `ToolParamOfNamespace(desc, name, tools)` |
| `OfComputer` | `ComputerToolParam` | GA computer tool, `{"type":"computer"}`; build with `NewComputerToolParam()`. Calls carry batched `Actions` |
| `OfComputerUsePreview` | `ComputerUsePreviewToolParam` | Legacy preview tool; `ToolParamOfComputerUsePreview(h, w, ComputerUsePreviewToolEnvironmentBrowser)` |
| `OfWebSearch` | `WebSearchToolParam` | `ExternalWebAccess: openai.Bool(false)` restricts to cached results |
| `OfWebSearchPreview` | `WebSearchPreviewToolParam` | Unchanged legacy variant |
| `OfFileSearch` | `FileSearchToolParam` | Filters are recursive (see below); `ToolParamOfFileSearch(vectorStoreIDs)` |
| `OfMcp` | `ToolMcpParam` | Use `ServerURL` or `TunnelID`; `ConnectorID` is deprecated |
| `OfCodeInterpreter` | `ToolCodeInterpreterParam` | Auto container with optional egress allowlist |
| `OfImageGeneration` | `ToolImageGenerationParam` | `Model: "gpt-image-2"` and newer |
| `OfShell` | `FunctionShellToolParam` | Hosted shell; `Environment.OfContainerAuto` / `OfLocal` / `OfContainerReference` |
| `OfLocalShell` | `ToolLocalShellParam` | `NewToolLocalShellParam()` |
| `OfApplyPatch` | `ApplyPatchToolParam` | Use `&responses.ApplyPatchToolParam{}`; `NewApplyPatchToolParam()` was removed |
| `OfProgrammaticToolCalling` | `ToolProgrammaticToolCallingParam` | Model calls opted-in tools from code it writes; `NewToolProgrammaticToolCallingParam()` |

### Deferred Tools with Tool Search

Mark large or rarely used tools `DeferLoading` and add the tool search tool. The model loads deferred definitions on demand, which keeps the prompt small.

```go
tools := []responses.ToolUnionParam{
	{OfToolSearch: &responses.ToolSearchToolParam{Execution: responses.ToolSearchToolExecutionServer}},
	{OfFunction: &responses.FunctionToolParam{
		Name:         "lookup_order",
		Description:  openai.String("Look up an order by ID."),
		Strict:       openai.Bool(true),
		DeferLoading: openai.Bool(true),
		Parameters: map[string]any{
			"type":                 "object",
			"properties":           map[string]any{"order_id": map[string]any{"type": "string"}},
			"required":             []string{"order_id"},
			"additionalProperties": false,
		},
	}},
}
```

### Computer, MCP, Code Interpreter, Shell

```go
computer := responses.NewComputerToolParam() // GA tool
tools := []responses.ToolUnionParam{
	{OfComputer: &computer},
	{OfMcp: &responses.ToolMcpParam{
		ServerLabel:     "docs",
		ServerURL:       openai.String("https://mcp.example.com/mcp"),
		AllowedTools:    responses.ToolMcpAllowedToolsUnionParam{OfMcpAllowedTools: []string{"search"}},
		RequireApproval: responses.ToolMcpRequireApprovalUnionParam{OfMcpToolApprovalSetting: openai.String("never")},
	}},
	{OfCodeInterpreter: &responses.ToolCodeInterpreterParam{
		Container: responses.ToolCodeInterpreterContainerUnionParam{
			OfCodeInterpreterToolAuto: &responses.ToolCodeInterpreterContainerCodeInterpreterContainerAutoParam{
				MemoryLimit: "4g",
				NetworkPolicy: responses.ResponseToolSearchOutputItemParamToolCodeInterpreterContainerCodeInterpreterToolAutoNetworkPolicyUnion{
					OfAllowlist: &responses.ContainerNetworkPolicyAllowlistParam{AllowedDomains: []string{"pypi.org"}},
				},
			},
		},
	}},
	{OfShell: &responses.FunctionShellToolParam{
		Environment: responses.FunctionShellToolEnvironmentUnionParam{OfContainerAuto: &responses.ContainerAutoParam{}},
	}},
}
```

- The preview computer tool moved: `OfComputerUsePreview` now takes `*ComputerUsePreviewToolParam` with `ComputerUsePreviewToolEnvironment*` constants. The old `ComputerToolEnvironment*` constants are gone.
- `AsMcpCall().Error` is a union (`McpToolCallErrorUnion`), not a string.
- The SDK never executes tool calls. Your code decides whether and when to act on returned arguments.

### File Search Filters

`shared.CompoundFilterParam.Filters` holds `[]shared.CompoundFilterFilterUnionParam`, so filters nest. This also applies to vector store search.

```go
tool := responses.ToolUnionParam{OfFileSearch: &responses.FileSearchToolParam{
	VectorStoreIDs: []string{"vs_123"},
	Filters: responses.FileSearchToolFiltersUnionParam{
		OfCompoundFilter: &shared.CompoundFilterParam{
			Type: shared.CompoundFilterTypeAnd,
			Filters: []shared.CompoundFilterFilterUnionParam{
				{OfComparison: &shared.ComparisonFilterParam{
					Key: "lang", Type: shared.ComparisonFilterTypeEq,
					Value: shared.ComparisonFilterValueUnionParam{OfString: openai.String("go")},
				}},
				{OfFilter: &shared.CompoundFilterParam{
					Type: shared.CompoundFilterTypeOr,
					Filters: []shared.CompoundFilterFilterUnionParam{
						{OfComparison: &shared.ComparisonFilterParam{
							Key: "year", Type: shared.ComparisonFilterTypeGte,
							Value: shared.ComparisonFilterValueUnionParam{OfFloat: openai.Float(2026)},
						}},
					},
				}},
			},
		},
	},
}}
```

Comparison types include `in` and `nin` (since v3.29.0) in addition to `eq`, `ne`, `gt`, `gte`, `lt`, `lte`.

## Reasoning Options

`ResponseNewParams.Reasoning` is `shared.ReasoningParam` (alias `openai.ReasoningParam`):

| Field | Constants |
|---|---|
| `Effort` | `ReasoningEffortNone`, `Minimal`, `Low`, `Medium`, `High`, `Xhigh`, `Max` |
| `Summary` | `ReasoningSummaryAuto`, `Concise`, `Detailed` |
| `Context` | `ReasoningContextAuto`, `CurrentTurn`, `AllTurns` (gpt-5.6 family defaults to all turns) |
| `Mode` | `ReasoningModeStandard`, `ReasoningModePro` |

`GenerateSummary` is deprecated; use `Summary`. Not every model accepts every effort level; the API rejects unsupported combinations.

## Context Management and Compaction

Server-side compaction trims long `PreviousResponseID` chains automatically:

```go
resp, err := client.Responses.New(ctx, responses.ResponseNewParams{
	Model: openai.ChatModelGPT5_5,
	Input: responses.ResponseNewParamsInputUnion{OfString: openai.String("Continue the analysis.")},
	ContextManagement: []responses.ResponseNewParamsContextManagement{{
		Type:             "compaction",
		CompactThreshold: openai.Int(200000), // tokens
	}},
})
```

Continue normally with `PreviousResponseID: openai.String(resp.ID)` and only new input. Streams emit `responses.ResponseCompactionCompactingEvent` while compacting.

Standalone compaction returns a compacted input window. Preserve every output item verbatim (they include encrypted items and fields the SDK may not model) and start a new chain:

```go
compacted, err := client.Responses.Compact(ctx, responses.ResponseCompactParams{
	Model:              responses.ResponseCompactParamsModelGPT5_5,
	PreviousResponseID: openai.String(previousID),
})
if err != nil {
	return err
}
input := make(responses.ResponseInputParam, 0, len(compacted.Output)+1)
for _, item := range compacted.Output {
	input = append(input, param.Override[responses.ResponseInputItemUnionParam](json.RawMessage(item.RawJSON())))
}
input = append(input, responses.ResponseInputItemParamOfMessage("Continue.", responses.EasyInputMessageRoleUser))
resp, err := client.Responses.New(ctx, responses.ResponseNewParams{
	Model: openai.ChatModelGPT5_5,
	Input: responses.ResponseNewParamsInputUnion{OfInputItemList: input}, // no PreviousResponseID
})
```

`compacted.ID` (`cmp_...`) is not a response ID; never pass it as `PreviousResponseID`.

## Prompt Caching

| Field | Purpose |
|---|---|
| `PromptCacheKey` | Routes requests that share a prefix to the same cache |
| `PromptCacheOptions.Mode` | `"implicit"` or `"explicit"` |
| `PromptCacheOptions.Ttl` | `"30m"` |
| `PromptCacheOptions.Prewarm` | `openai.Bool(true)` warms the cache without generating output |
| `PromptCacheOptions.ComparisonResponseID` | Explains cache misses relative to an earlier response |
| `PromptCacheRetention` | Deprecated; use `PromptCacheOptions.Ttl` |

```go
_, err := client.Responses.New(ctx, responses.ResponseNewParams{
	Model:              openai.ChatModelGPT5_5,
	Instructions:       openai.String(longSystemPrompt),
	Input:              responses.ResponseNewParamsInputUnion{OfString: openai.String("warmup")},
	PromptCacheKey:     openai.String("tenant-42"),
	PromptCacheOptions: responses.ResponseNewParamsPromptCacheOptions{Prewarm: openai.Bool(true)},
})
```

Read `resp.PromptCacheDiagnostics.Type` (`cache_hit`, `cache_miss`, `comparison_response_not_found`, `unavailable`); `AsCacheMiss()` gives the miss reason and token counts. Cache writes appear in `resp.Usage.InputTokensDetails.CacheWriteTokens`.

The wire value of `PromptCacheRetentionInMemory` changed from `"in-memory"` to `"in_memory"` (v3.33.0). Hard-coded `"in-memory"` literals still compile and send the old value; use the constant.

## Moderation, Service Tiers, Access Programs

```go
params := responses.ResponseNewParams{
	Model:            openai.ChatModelGPT5_5,
	Input:            responses.ResponseNewParamsInputUnion{OfString: openai.String("...")},
	SafetyIdentifier: openai.String(hashedUserID), // stable per end user; never raw PII
	ServiceTier:      responses.ResponseNewParamsServiceTierFlex,
	Moderation: responses.ResponseNewParamsModeration{
		Model: "omni-moderation-latest",
		Policy: responses.ResponseNewParamsModerationPolicy{
			Input:  responses.ResponseNewParamsModerationPolicyInput{Mode: "block"},
			Output: responses.ResponseNewParamsModerationPolicyOutput{Mode: "score"},
		},
	},
}
```

- Service tiers: `Auto`, `Default`, `Flex`, `Scale`, `Priority`, `Fast`, `Ultrafast`. A `fast` request reports `service_tier=priority` in the response. Chat Completions has `fast` but not `ultrafast`.
- Moderation results come back in `resp.Moderation.Input` / `.Output`.
- `AccessPrograms.Cyber` (`"standard"`, `"daybreak_blue"`, `"daybreak_red"`) applies to the cyber-security model programs.
- Enum-like string fields are not validated client-side; typos reach the API.

## Conversations

A conversation object stores history server-side so requests need not chain `PreviousResponseID`:

```go
conv, err := client.Conversations.New(ctx, conversations.ConversationNewParams{})
if err != nil {
	return err
}
resp, err := client.Responses.New(ctx, responses.ResponseNewParams{
	Model: openai.ChatModelGPT5_5,
	Input: responses.ResponseNewParamsInputUnion{OfString: openai.String("My favorite color is blue.")},
	Conversation: responses.ResponseNewParamsConversationUnion{
		OfConversationObject: &responses.ResponseConversationParam{ID: conv.ID},
	},
})
items, err := client.Conversations.Items.List(ctx, conv.ID, conversations.ItemListParams{})
```

Use either `Conversation` or `PreviousResponseID`, not both. Assistant messages carry a `Phase` (`commentary` or `final_answer`); resend assistant items unchanged so the phase survives.

## Responses WebSockets

`client.Responses.Connect` opens a reusable connection that carries `response.create` commands and the normal Responses events. It suits low-latency agent loops with many short turns.

```go
conn, err := client.Responses.Connect(ctx, responses.ResponseConnectionOptions{
	MaxMessageBytes:   16 << 20, // 0 = unlimited (default)
	MaxBufferedEvents: 1024,     // 0 = unlimited (default)
})
if err != nil {
	return err
}
defer func() { _ = conn.Close() }()

if err := conn.Create(ctx, responses.ResponsesClientEventResponseCreateParam{
	Model: openai.ChatModelGPT5_5,
	Input: responses.ResponsesClientEventResponseCreateInputUnionParam{OfString: openai.String("Pick a number.")},
}); err != nil {
	var de *websocket.DeliveryError
	if errors.As(err, &de) && de.MayHaveBeenSent {
		return err // never replay blindly: the server may already be running it
	}
	return err
}
first, err := conn.FinalResponse(ctx)
if err != nil {
	var pe *responses.ResponseProtocolError
	if errors.As(err, &pe) {
		log.Println("protocol error:", pe.Event.AsResponsesServerEventResponseWsError().Error.Code)
	}
	return err
}

input := responses.ResponseInputParam{
	responses.ResponseInputItemParamOfMessage("Double it.", responses.EasyInputMessageRoleUser),
}
if err := conn.Create(ctx, responses.ResponsesClientEventResponseCreateParam{
	Model:              openai.ChatModelGPT5_5,
	PreviousResponseID: openai.String(first.ID), // send only new input on later turns
	Input:              responses.ResponsesClientEventResponseCreateInputUnionParam{OfResponse: &input},
}); err != nil {
	return err
}
second, err := conn.FinalResponse(ctx)
```

### Connection Rules

| Rule | Detail |
|---|---|
| Options defaults | `MaxMessageBytes`, `MaxBufferedBytes`, `MaxBufferedEvents` unlimited; `MaxPendingSends` 16; `MaxLanes` 64 (lifetime, including closed lanes); `CloseTimeout` 5s |
| `ctx` on `Connect` | Bounds opening only, not the connection lifetime |
| `Create` vs `FinalResponse` | `Create` sends and returns; `FinalResponse` reads until `response.completed`, `failed`, or `incomplete` |
| Terminal events | End a turn, not the socket. Always call `Close` (graceful) or `Abort` (immediate) |
| `Recv` | Returns individual typed events (`ResponsesServerEventUnion`) with `RawJSON()` |
| Lanes | `conn.Lane("fork")` before sending a create with `StreamID: openai.String("fork")`; lanes run concurrently, creates on one lane run FIFO |
| Stream IDs | 1-256 chars of letters, digits, `_`, `-`, `.`; omit for the default lane; empty string is invalid |
| Create params | Leave `Stream` and `Background` unset; `Input.OfResponse` is a pointer |
| Server limits | 16 active responses (extras queue), 32 named streams per connection, 60-minute connection lifetime |
| Previous-response cache | Connection-local. With `Store: openai.Bool(false)` or ZDR, an uncached parent fails with `previous_response_not_found` |
| Recovery | `Reconnect` / `Recover` never replay commands; resume from a persisted ID or resend full context as a new chain |
| Unsupported | `js/wasm`, Azure clients, Bedrock clients |

Protocol error codes: `previous_response_not_found` (start a fresh chain with full context), `invalid_stream_id`, `websocket_stream_limit_reached` (reuse a stream or open another connection), `websocket_connection_limit_reached` (open a new connection).

### Incremental Snapshots

Feed events from `Recv` to a `responses.ResponseAccumulator` (one per lane) for text and tool-input snapshots:

```go
var acc responses.ResponseAccumulator
for {
	event, err := conn.Recv(ctx)
	if err != nil {
		return err
	}
	if err := acc.AddEvent(event); err != nil {
		return err
	}
	if event.Type == "response.completed" || event.Type == "response.failed" || event.Type == "response.incomplete" {
		fmt.Println(acc.Snapshot().OutputText())
		break
	}
}
acc.Reset() // ready for the next turn; the connection stays open
```

`Snapshot().OutputText()` rebuilds the full text each call. Read it at terminal events or on demand, not after every delta. `DetailedSnapshot()` exposes raw `json.RawMessage` fields for every observed item, part, and annotation.

## Response Fields Worth Knowing

| Field | Notes |
|---|---|
| `CreatedAt`, `CompletedAt` | `float64` Unix seconds; convert with `time.UnixMilli(int64(resp.CreatedAt * 1000))` |
| `OutputText()` | Concatenates all `output_text` parts |
| `Usage.InputTokensDetails.CachedTokens` / `.CacheWriteTokens` | Cache reads and writes |
| `Usage.OutputTokensDetails.ReasoningTokens` | Hidden reasoning token count |
| `PromptCacheDiagnostics`, `Moderation`, `AccessPrograms`, `PromptCacheOptions` | New since v3.39.0 |
| `compute_units` | Listed in the changelog but has no Go field; read `resp.Usage.JSON.ExtraFields["compute_units"].Raw()` |
