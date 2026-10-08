# New API Families

API surfaces added to `github.com/openai/openai-go/v3` after v3.24.0: the beta Agents API, Live, Decisions, Realtime additions, webhook verification and endpoint management, Safety, content provenance checks, Skills, and Admin (verified against v3.73.0). All snippets assume `ctx context.Context` and `client openai.Client`.

## Beta Agents API (`client.Beta.Agents`)

Hosted agents that run multi-turn work in an environment (none, OpenAI-hosted container, or your own workspace), call tools, spawn subagents, and publish artifacts. Every request sends `OpenAI-Beta: agents=v1` automatically. The hand-written helpers are documented as experimental; expect changes between minor releases.

### Object Model

| Object | Accessor | Purpose |
|---|---|---|
| Agent | `client.Beta.Agents` | Reusable configuration: `Model` (plain string), `Instructions`, `Tools`, `Text` (output format), `Reasoning`, `MultiAgent`. Stores no credentials |
| Environment | `BetaAgentSessionNewParams.Environment` | `OfParamNone`, `OfParamOpenAIHosted` (files, skills, network policy, packages, desktop, container size), `OfParamSelfHosted` |
| Session | `.Sessions` | One running conversation of an agent in an environment. Status: `idle`, `in_progress`, `requires_action`, `failed` |
| Turn | `.Sessions.Turns` | One unit of work triggered by input. Status: `queued`, `in_progress`, `waiting`, `completed`, `failed`, `cancelled` |
| Item | `.Sessions.Items`, `.Sessions.Turns.Items` | Transcript entries: messages, function calls and outputs, reasoning, MCP calls, web search, commands, computer use |
| Subagent | `.Sessions.Subagents` | Child agent spawned when `MultiAgent{Enabled: true}` |
| Vault / Credential | `.Vaults`, `.Vaults.Credentials` | Write-only secrets attached via `VaultIDs`: `static_bearer` and `mcp_oauth` for MCP servers, `environment_variable` for sandbox egress |
| Artifact | `.Sessions.Artifacts` | Immutable file published by a completed hosted turn |
| Trace | `.Sessions.Traces` | OTLP JSON trace per root turn |
| Events | `.Sessions.Events` | `New` posts input (message, cancel, tool result, approval); `StreamStreaming` follows the SSE event stream |

The SDK's `api.md` lists `Sessions.Events.Stream`; the Go method is `Sessions.Events.StreamStreaming`.

### Typed Turn with Local Tools

`Sessions.Stream` drives one turn on an idle session: it subscribes to events, posts the input, runs registered local tool handlers, and stops when the turn finishes and the session returns to idle. `NewBetaAgentOutput` binds a JSON schema to a typed parser.

```go
type Weather struct {
	City    string  `json:"city"`
	TempC   float64 `json:"temp_c"`
	Summary string  `json:"summary"`
}

func runWeatherTurn(ctx context.Context, client openai.Client, lookup func(context.Context, string) (map[string]any, error)) (*openai.BetaAgentParsedTurnResult[Weather], error) {
	out, err := openai.NewBetaAgentOutput(map[string]any{
		"type": "object",
		"properties": map[string]any{
			"city":    map[string]any{"type": "string"},
			"temp_c":  map[string]any{"type": "number"},
			"summary": map[string]any{"type": "string"},
		},
	}, func(data []byte) (Weather, error) {
		var w Weather
		err := json.Unmarshal(data, &w)
		return w, err
	})
	if err != nil {
		return nil, err
	}

	agent, err := client.Beta.Agents.New(ctx, openai.BetaAgentNewParams{
		Model:        openai.ChatModelGPT6Sol,
		Name:         openai.String("weather-bot"),
		Instructions: openai.String("Use get_weather, then answer with the JSON schema."),
		Tools: []openai.PersistedAgentToolParamUnion{
			openai.PersistedAgentToolParamOfParamFunction(
				"Look up the current weather for a city.",
				"get_weather",
				map[string]any{
					"type":                 "object",
					"properties":           map[string]any{"city": map[string]any{"type": "string"}},
					"required":             []string{"city"},
					"additionalProperties": false,
				},
			),
		},
		Text: openai.AgentTextParam{Format: out.Format()},
	})
	if err != nil {
		return nil, err
	}

	// No Input: the session starts idle, ready for Sessions.Stream.
	session, err := client.Beta.Agents.Sessions.New(ctx, openai.BetaAgentSessionNewParams{
		AgentID: openai.String(agent.ID),
		Environment: openai.EnvironmentParamUnion{
			OfParamOpenAIHosted: &openai.EnvironmentParamOpenAIHosted{ContainerSize: "small"},
		},
	})
	if err != nil {
		return nil, err
	}

	stream := client.Beta.Agents.Sessions.Stream(ctx, session.ID, openai.AgentSessionStreamParams{
		Input: "What's the weather in Paris?", // string or []openai.AgentSessionInputMessageParam
		ToolHandlers: map[string]openai.AgentToolHandler{
			"get_weather": func(ctx context.Context, args map[string]any) (any, error) {
				city, _ := args["city"].(string)
				return lookup(ctx, city) // string, map[string]any, []InputContentParamUnion, or nil
			},
		},
		OnToolError: func(_ context.Context, f openai.BetaAgentToolError) {
			// The API only receives "Tool handler failed."; f.Err stays local and may be sensitive.
			log.Printf("tool %s failed at %s stage: %v", f.ToolName, f.Stage, f.Err)
		},
	}).WithResultCollection() // required when reading events before FinalResult
	defer func() { _ = stream.Close() }()

	for stream.Next() {
		event := stream.Current()
		if event.Type == "agent.session.turn.output_text.delta" {
			fmt.Print(event.AsAgentSessionTurnOutputTextDelta().Delta)
		}
	}
	if err := stream.Err(); err != nil {
		return nil, err
	}

	result, err := out.FinalResult(stream)
	if err != nil {
		var hosted *openai.BetaAgentTurnResultError
		var parse *openai.BetaAgentOutputParseError
		switch {
		case errors.As(err, &hosted):
			return nil, fmt.Errorf("turn did not complete (%s): %w", hosted.Reason, err)
		case errors.As(err, &parse):
			return nil, fmt.Errorf("final answer did not parse: %w", err)
		}
		return nil, err
	}
	return result, nil // result.OutputParsed, result.OutputText(), result.Turn.Usage
}
```

### Agents Helper Reference

| Helper | Behavior |
|---|---|
| `Sessions.Stream(ctx, sessionID, AgentSessionStreamParams)` | Fails fast unless the session is `idle`. Must be the session's only input writer |
| `AgentToolHandler` | `func(ctx, map[string]any) (any, error)`. A `map` result is sent JSON-encoded as a string. Unregistered tools are left for manual `Events.New` |
| `OnToolError` | Called synchronously with `BetaAgentToolError{Err, ToolName, SessionID, TurnID, CallID, Stage}`; stage is `arguments`, `execution`, or `output` |
| `stream.Close()` | Releases local resources only. It does not cancel the backend turn |
| `stream.FinalResult()` | Untyped `*BetaAgentTurnResult{Turn, Messages}`; also drives tool handlers. Returns `requires_action` if an action has no handler |
| `NewBetaAgentOutput[T](schema, parse)` | Closes every object and marks all properties required. Rejects `oneOf`, `allOf`, `not`, root `anyOf`/`$ref`, `additionalProperties: true` |
| `out.Format()` | Value for `AgentTextParam.Format` on the agent or session; use the same schema in both places |
| `out.FinalResult(stream)` | Accepts `*AgentSessionStream` or the `Sessions.NewStreaming` stream; returns `*BetaAgentParsedTurnResult[T]` |
| `openai.BetaAgentSessionFinalResult(stream)` | Untyped result from a `Sessions.NewStreaming` creation stream (input supplied at creation, no local tools) |
| `openai.BetaAgentSessionWithResultCollection(stream)` | Call before the first `Next()` when iterating a creation stream and then collecting |
| `Environments.Files.Prepare(ctx, map[dest]localPath)` | Uploads local files for `EnvironmentParamOpenAIHosted.Files`. Destinations must be under `/workspace/` (not `/workspace` or `/workspace/outputs`). You own cleanup of `Uploads` |
| `Environments.Files.Upload(ctx, envID, src, dest)` | Stages a file into a live environment |
| `Sessions.Artifacts.ForResult(result).Download(ctx, path, w)` | Finds the artifact for that turn and path and streams it |

`BetaAgentTurnResultError.Reason` values: `turn_failed`, `turn_cancelled`, `session_failed`, `requires_action`, `observation_failed`, `observation_incomplete`, `collection_not_enabled`, `unsupported_stream`.

### Manual Event Handling

Use `Events.StreamStreaming` plus `Events.New` to follow an active session or answer required actions yourself:

```go
stream := client.Beta.Agents.Sessions.Events.StreamStreaming(ctx, sessionID)
defer func() { _ = stream.Close() }()

err := client.Beta.Agents.Sessions.Events.New(ctx, sessionID, openai.BetaAgentSessionEventNewParams{
	Events: []openai.AgentSessionInputParamUnion{openai.AgentSessionInputParamOfParamAgentSessionInputMessage(
		[]openai.AgentSessionInputMessageParam{{Content: []openai.InputContentParamUnion{
			openai.InputContentParamOfParamInputText("Summarize the repository."),
		}}},
	)},
	IdempotencyKey: openai.String("turn-1"),
})
if err != nil {
	return err
}

for stream.Next() {
	ev := stream.Current()
	if ev.Type != "agent.session.requires_action" {
		continue
	}
	for _, action := range ev.Session.RequiredActions {
		if call, ok := action.AsAny().(openai.AgentSessionRequiredActionFunctionCall); ok {
			r := openai.AgentSessionInputParamOfParamAgentSessionInputToolResult(call.CallID, true, call.TurnID)
			r.OfParamAgentSessionInputToolResult.Output = openai.AgentFunctionCallOutputParamUnion{OfString: openai.String(`{"ok":true}`)}
			if err := client.Beta.Agents.Sessions.Events.New(ctx, sessionID, openai.BetaAgentSessionEventNewParams{
				Events: []openai.AgentSessionInputParamUnion{r},
			}); err != nil {
				return err
			}
		}
	}
}
if err := stream.Err(); err != nil {
	return err
}

// Cancel the backend turn (closing a stream never does this).
cancel := openai.NewAgentSessionInputParamAgentSessionInputCancel()
err = client.Beta.Agents.Sessions.Events.New(ctx, sessionID, openai.BetaAgentSessionEventNewParams{
	Events: []openai.AgentSessionInputParamUnion{{OfParamAgentSessionInputCancel: &cancel}},
})
```

### Agents Caveats

- `Events.New` returns only an `error`; success (HTTP 202) means accepted, not durably applied.
- With `OfParamNone`, `Input` is required at session creation. To get an idle session for `Sessions.Stream`, use an OpenAI-hosted environment without initial input, or a self-hosted one.
- Saved agents use `Persisted*` tool params (no `Authorization`); session overrides use `AgentToolParamUnion`. Do not mix them.
- String enums such as `Network.Access` (`enabled`, `disabled`, `restricted`) and `ContainerSize` (`small`, `medium`, `large`) are not validated client-side.
- Session tools include MCP (`AgentToolParamMcp` with `McpTransportParamOfParamHTTP(url)`) and computer use (`AgentToolParamComputerUse`). Answer computer-use approval requests with `AgentSessionInputParamOfParamAgentSessionInputComputerUseApprovalRequestResult`.

## Live API (`client.Live`, `live` package)

A voice session on `gpt-live-1` that can delegate tasks to your backend (`ClientDelegationParam`) or to a Responses model the API manages. The Go SDK covers the REST control plane only: the WebRTC SDP exchange, SIP call control, forks, and recordings. `client.Live.Sideband` and `client.Live.Forks` have no methods; there is no Go WebSocket client for Live.

```go
res, err := client.Live.New(ctx, live.LiveNewParams{
	Session: live.MediaSessionConfigParam{
		Model:        live.MediaSessionConfigModelGPTLive1,
		Instructions: openai.String("You are a concise voice concierge."), // fixed for the session
		Store:        openai.Bool(true),                                    // required for Fork and DownloadRecording
		Audio: live.MediaSessionConfigAudioParam{Output: live.MediaSessionConfigAudioOutputParam{
			Voice: live.MediaSessionConfigAudioOutputVoiceUnionParam{OfBuiltIn: openai.Opt(live.BuiltInVoiceMarin)},
		}},
		Delegation: live.MediaSessionConfigDelegationUnionParam{OfResponses: &live.MediaSessionConfigDelegationResponsesParam{
			Responses: live.ResponsesDelegationConfigParam{
				Model:        openai.ChatModelGPT6Sol,
				Instructions: openai.String("Business rules and tool workflow go here."),
				Tools:        []live.ResponsesDelegationConfigToolUnionParam{{OfWebSearch: &live.ResponsesDelegationConfigToolWebSearchParam{}}},
			},
		}},
	},
	Transport: live.LiveNewParamsTransport{Sdp: browserOffer},
})
if err != nil {
	return err
}
// Return res.Transport.Sdp to the browser as the remote answer; keep res.Session.ID ("live_...").
```

- After the browser applies the answer, wait for `session.started` on the data channel before sending commands.
- Restrict what the untrusted browser data channel may send with `Client.DataChannel.AllowedClientEvents`.
- SIP: `client.Live.Sessions.Accept`, `Reject` (status 300-699), `Refer`, `Hangup`, triggered by the `live.transport.incoming` webhook. `live.call.incoming` is deprecated.
- `client.Live.Sessions.Fork` (new SDP) and `DownloadRecording` (raw `*http.Response`) need `Store: true`.

## Decisions (`client.Decisions`)

Evaluates ordered classification and scoring questions against shared input in one call. Answers return in question order; any answer may be a refusal.

```go
d, err := client.Decisions.New(ctx, openai.DecisionNewParams{
	Model: openai.ChatModelGPT6Luna,
	Input: openai.DecisionNewParamsInputUnion{OfString: openai.String(ticketText)},
	Questions: []openai.DecisionNewParamsQuestionUnion{
		{OfPredicate: &openai.DecisionNewParamsQuestionPredicate{
			Name: openai.String("is_refund"), Instructions: "Does the customer ask for a refund?"}},
		{OfChoice: &openai.DecisionNewParamsQuestionChoice{
			Name: openai.String("team"), Instructions: "Which team should handle it?",
			Choices: []openai.DecisionNewParamsQuestionChoiceChoice{
				{Value: openai.DecisionNewParamsQuestionChoiceChoiceValueUnion{OfString: openai.String("billing")}},
				{Value: openai.DecisionNewParamsQuestionChoiceChoiceValueUnion{OfString: openai.String("support")}},
			}}},
		{OfScore: &openai.DecisionNewParamsQuestionScore{
			Name: openai.String("urgency"), Instructions: "How urgent is it?",
			Levels: []openai.DecisionNewParamsQuestionScoreLevel{{Label: "low"}, {Label: "medium"}, {Label: "high"}}}},
	},
	SafetyIdentifier: openai.String(hashedUserID),
})
if err != nil {
	return err
}
for _, a := range d.Answers {
	switch v := a.AsAny().(type) {
	case openai.DecisionAnswerPredicate:
		fmt.Println(v.Name, v.Probability)
	case openai.DecisionAnswerChoice:
		fmt.Println(v.Name, v.Choice.AsString(), v.Confidence)
	case openai.DecisionAnswerScore:
		fmt.Println(v.Name, v.Score)
	case openai.DecisionAnswerRefusal:
		fmt.Println(v.Name, "refused")
	}
}
```

Input may also be user messages with text and image (data URL) parts, up to 128 images. The SDK has no Decisions-specific model constant.

## Realtime Additions (`client.Realtime`)

| Feature | API |
|---|---|
| Realtime 2 models | `realtime.RealtimeSessionCreateRequestModelGPTRealtime2` and `gpt-realtime-2.1`, `gpt-realtime-2.1-mini`, `gpt-realtime-whisper` |
| Reasoning | `RealtimeSessionCreateRequestParam.Reasoning: realtime.RealtimeReasoningParam{Effort: realtime.RealtimeReasoningEffortLow}` |
| Server-side WebRTC call | `client.Realtime.Calls.New(ctx, realtime.CallNewParams{Sdp, Session})` returns `*http.Response` whose body is the SDP answer |
| Translation sessions | `client.Realtime.Translations.ClientSecrets.New(...)` returns an ephemeral `ek_...` key; the model is a free-form string |
| SIP | `Calls.Accept`, `Hangup`, `Refer`, `Reject` (unchanged) |

The SDK has no Realtime WebSocket client; use the ephemeral client secret from a browser or your own WebSocket client.

## Webhooks

Verification is a method on `client.Webhooks`; there is no package-level `webhooks.Verify` function.

```go
const maxWebhookBody = 1 << 20 // 1 MiB; bound unauthenticated input before reading

client := openai.NewClient(option.WithWebhookSecret(os.Getenv("OPENAI_WEBHOOK_SECRET")))

http.HandleFunc("/openai/webhook", func(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxWebhookBody))
	if err != nil {
		http.Error(w, "body too large or unreadable", http.StatusRequestEntityTooLarge)
		return
	}
	event, err := client.Webhooks.Unwrap(body, r.Header) // verifies, then decodes
	if err != nil {
		http.Error(w, "invalid signature", http.StatusBadRequest)
		return
	}
	switch e := event.AsAny().(type) {
	case webhooks.ResponseCompletedWebhookEvent:
		log.Println("response completed:", e.Data.ID)
	case webhooks.AgentSessionIdleWebhookEvent:
		log.Println("agent session idle:", e.Data.ID) // Data.ID is the session ID
	case webhooks.SafetyWarningIssuedWebhookEvent:
		log.Println("safety case:", e.Data.ID) // look up with client.Safety.Cases.Get
	case webhooks.LiveTransportIncomingWebhookEvent:
		log.Println("incoming SIP call:", e.Data.SessionID)
	}
	w.WriteHeader(http.StatusOK)
})
```

| Method | Purpose |
|---|---|
| `Unwrap(body, headers, opts...)` | Verify and decode into `UnwrapWebhookEventUnion` |
| `VerifySignature(body, headers, opts...)` | Verify only (default tolerance 5 minutes) |
| `UnwrapWithTolerance` / `VerifySignatureWithTolerance` | Custom timestamp tolerance |
| `...WithToleranceAndTime` | Inject the current time (tests) |

- Pass the raw body bytes; do not re-marshal parsed JSON.
- The secret comes from `option.WithWebhookSecret`, `OPENAI_WEBHOOK_SECRET`, or per call (`client.Webhooks.Unwrap(body, h, option.WithWebhookSecret(s))`; per-call secrets work since v3.53.0).
- `whsec_`-prefixed secrets must be valid base64 decoding to at least 24 bytes.
- The SDK does not deduplicate deliveries; use `webhook-id` for idempotency.
- New event types: `agent.session.created|action_required|in_progress|idle|failed`, `safety.warning_issued`, `safety.deactivation_issued`, `safety.alert.created`, `safety.org_alert.created`, `live.transport.incoming`. `RealtimeCallIncomingWebhookEvent.Data.SipMediaSecurity` is `srtp`, `rtp`, or empty.

### Webhook Endpoint Management

```go
ep, err := client.Webhooks.New(ctx, webhooks.WebhookNewParams{
	Name:       "prod",
	URL:        "https://example.com/openai/webhook",
	EventTypes: []string{"response.completed", "agent.session.idle"},
})
if err != nil {
	return err
}
secret := ep.SigningSecret // returned only by New and RotateSecret; store it now
```

Other methods: `Get`, `Update`, `List` / `ListAutoPaging`, `Delete`, `RotateSecret(id, WebhookRotateSecretParams{KeepOldSecretActiveFor24Hours})`, `Test(id, WebhookTestParams{EventType})`, and `client.Webhooks.EventTypes.List`.

## Smaller Services

| Service | Accessor | Notes |
|---|---|---|
| Safety cases / alerts | `client.Safety.Cases.Get`, `client.Safety.Alerts.Get` | Read-only lookups for IDs delivered by safety webhooks |
| Content provenance checks | `client.ContentProvenanceChecks.New(ctx, openai.ContentProvenanceCheckNewParams{File: openai.File(r, "photo.png", "image/png")})` | Returns C2PA and SynthID results; `not_detected` does not prove content is not AI-generated |
| Skills | `client.Skills`, `.Versions`, `.Content` | Upload zipped skill bundles; reference them from hosted agent environments with `openai.HostedSkillParamOfParamSkillReference(skillID)` |
| Admin | `client.Admin.Organization.*` | Requires `option.WithAdminAPIKey` or `OPENAI_ADMIN_KEY`. API keys, audit logs, usage and costs, users, groups, roles, projects, rate limits, spend limits and alerts, data retention, external storage, certificates |
| Beta Responses mirror | `client.Beta.Responses` | Same shape as `client.Responses` plus `Betas []string` for opt-in beta features |

## Deprecated Surfaces

| Surface | Status | Use instead |
|---|---|---|
| `client.Videos` (Sora) | Deprecated in v3.51.0; the service shut down on 2026-09-24 | No replacement in the SDK |
| `client.Beta.Assistants`, `client.Beta.Threads` | Deprecated | Responses API, Conversations, or beta Agents |
| MCP `ConnectorID` | Deprecated for models released after 2026-09-01 | `ServerURL` or `TunnelID` |
| `client.Images.NewVariation` | Endpoint retired | Image edits with a GPT Image model |
| `webhooks.LiveCallIncomingWebhookEvent` | Deprecated | `live.transport.incoming` |
| Admin project `Geography` | Deprecated | `Residency` |
