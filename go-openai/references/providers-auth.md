# Providers and Authentication

OpenAI-compatible servers (vLLM, Ollama, OpenRouter), the plain-HTTP credential policy, Azure OpenAI, Amazon Bedrock, data residency, mutual TLS, workload identity, X.509 workload identity, and admin keys for `github.com/openai/openai-go/v3` (verified against v3.73.0). Snippets assume `ctx context.Context`.

## Credential Sources

`openai.NewClient()` applies these environment variables before explicit options:

| Variable | Equivalent option | Notes |
|---|---|---|
| `OPENAI_API_KEY` | `option.WithAPIKey` | Sent as `Authorization: Bearer` |
| `OPENAI_ADMIN_KEY` | `option.WithAdminAPIKey` | Used only by `client.Admin.Organization.*` |
| `OPENAI_BASE_URL` | `option.WithBaseURL` | |
| `OPENAI_ORG_ID` | `option.WithOrganization` | `OpenAI-Organization` header |
| `OPENAI_PROJECT_ID` | `option.WithProject` | `OpenAI-Project` header |
| `OPENAI_WEBHOOK_SECRET` | `option.WithWebhookSecret` | |
| `OPENAI_CUSTOM_HEADERS` | `option.WithHeader` per line | Newline-separated `Name: value` lines |

- A set-but-empty variable still counts as set.
- An ambient `OPENAI_API_KEY` is sent to whatever base URL you configure, including third-party servers. Pass `option.WithAPIKey("")` to send no `Authorization` header at all (v3.24 sent an empty `Bearer `).
- Admin endpoints ignore `WithAPIKey`; they need the admin key. Regular endpoints ignore the admin key.
- There is no API-key provider or callback option. For rotating credentials use workload identity, or a middleware that sets `Authorization`.

## OpenAI-Compatible Servers

```go
// Local vLLM or Ollama
client := openai.NewClient(
	option.WithBaseURL("http://localhost:8000/v1/"), // Ollama: http://localhost:11434/v1/
	option.WithAPIKey("not-needed"),                // placeholder; also overrides an ambient OPENAI_API_KEY
)

// Remote server without auth: send no Authorization header at all
remote := openai.NewClient(
	option.WithBaseURL("http://inference.internal:8000/v1/"),
	option.WithAPIKey(""),
)
```

| Provider | Base URL | Auth |
|---|---|---|
| OpenAI | `https://api.openai.com/v1/` (default) | `OPENAI_API_KEY` |
| vLLM | `http://localhost:8000/v1/` | Usually none; `--api-key` makes it require Bearer |
| Ollama | `http://localhost:11434/v1/` | Any non-empty placeholder |
| TGI | `http://localhost:8080/v1/` | Usually none |
| OpenRouter | `https://openrouter.ai/api/v1/` | OpenRouter key |

- Use the model name the server serves (`Model: "meta-llama/Llama-3.3-70B-Instruct"`); `shared.ChatModel` is a string alias.
- Most compatible servers implement Chat Completions; Responses API support varies. Prefer Chat Completions unless the server documents `/v1/responses`.
- Send provider-specific parameters with `params.SetExtraFields(map[string]any{...})` and read provider-specific response fields from `.JSON.ExtraFields`.
- `client.Get` / `client.Post` accept only paths relative to the base URL. Absolute URLs return `request path must be a relative URL reference`; use a per-request `option.WithBaseURL` for another host.
- Middleware may rewrite path and query but not scheme, host, or port; origin changes fail with `request URL origin must match the configured base URL`. Cross-origin redirects fail.

### Reasoning Text from Compatible Servers

OpenAI models never return chain-of-thought text. Compatible servers return it in non-standard fields:

| Server | Field (message and stream delta) |
|---|---|
| vLLM (current) | `reasoning` |
| vLLM (older), DeepSeek API | `reasoning_content` |
| OpenRouter | Varies by upstream; check both |

```go
func reasoningText(fields map[string]respjson.Field) string {
	for _, key := range []string{"reasoning", "reasoning_content"} {
		if f, ok := fields[key]; ok && f.Raw() != "null" {
			var s string
			if json.Unmarshal([]byte(f.Raw()), &s) == nil {
				return s
			}
		}
	}
	return ""
}

completion, err := client.Chat.Completions.New(ctx, params)
if err != nil {
	return err
}
fmt.Println(reasoningText(completion.Choices[0].Message.JSON.ExtraFields))
// Streaming: reasoningText(chunk.Choices[0].Delta.JSON.ExtraFields)
```

`Raw()` returns the JSON literal (quoted string), so unmarshal it before display.

## Plain-HTTP Credential Policy

| SDK versions | `http://` base URL with an API key |
|---|---|
| ≤ v3.68.0 | Allowed |
| **v3.69.0 – v3.71.0** | **Refused** unless `option.WithUnsafeAllowHTTP()` is set and the host is `localhost` or a loopback IP. Non-loopback HTTP fails with `openai: authenticated requests require HTTPS...` even with the option. Loopback requests bypass custom HTTP clients and proxies |
| ≥ v3.71.1 | Allowed again; `option.WithUnsafeAllowHTTP()` is a no-op kept for source compatibility |

The release notes say the restriction returns in the next major version. To stay forward compatible:

1. Do not pin v3.69.0, v3.70.0, or v3.71.0 when any keyed endpoint uses `http://`.
2. For local development servers, adding `option.WithUnsafeAllowHTTP()` documents intent and is harmless on v3.69.0+ (it does not compile on older versions).
3. For a remote server that requires a key, terminate TLS in front of it (Caddy, nginx, an ingress) and use `https://`.
4. For a remote server without auth, use `option.WithAPIKey("")`; requests without credentials were never restricted.

`azure.WithUnsafeAllowHTTP()` is separate and enforced: Azure clients require HTTPS except for loopback with that option.

## Azure OpenAI

Pick the pattern by API surface:

| Azure API | Client setup | Auth header |
|---|---|---|
| v1 API (`/openai/v1/`) + API key | `option.WithBaseURL(".../openai/v1/")` + `option.WithAPIKey(key)` | `Authorization: Bearer` |
| v1 API + Entra ID | `option.WithBaseURL(".../openai/v1/")` + token middleware (below) | `Authorization: Bearer` |
| Deployments API (`api-version`) + API key | `azure.WithEndpoint(endpoint, apiVersion)` + `azure.WithAPIKey(key)` | `Api-Key` |
| Deployments API + Entra ID | `azure.WithEndpoint(endpoint, apiVersion)` + `azure.WithTokenCredential(cred)` | `Authorization: Bearer` |

```go
// v1 API with an API key
client := openai.NewClient(
	option.WithBaseURL("https://my-resource.openai.azure.com/openai/v1/"),
	option.WithAPIKey(os.Getenv("AZURE_OPENAI_API_KEY")),
)
```

```go
// v1 API with Entra ID: azure.WithTokenCredential requires azure.WithEndpoint, so add the token in middleware
cred, err := azidentity.NewDefaultAzureCredential(nil)
if err != nil {
	return err
}
client := openai.NewClient(
	option.WithBaseURL("https://my-resource.openai.azure.com/openai/v1/"),
	option.WithAPIKey(""), // never forward an ambient OPENAI_API_KEY to Azure
	option.WithMiddleware(func(r *http.Request, next option.MiddlewareNext) (*http.Response, error) {
		tok, err := cred.GetToken(r.Context(), policy.TokenRequestOptions{
			Scopes: []string{"https://cognitiveservices.azure.com/.default"},
		})
		if err != nil {
			return nil, err
		}
		r.Header.Set("Authorization", "Bearer "+tok.Token)
		return next(r)
	}),
)
```

```go
// Deployments API with a dated api-version
client := openai.NewClient(
	azure.WithEndpoint("https://my-resource.openai.azure.com", "2024-10-21"),
	azure.WithTokenCredential(cred), // or azure.WithAPIKey(os.Getenv("AZURE_OPENAI_API_KEY"))
)
```

Rules enforced since v3.53.0:

- `option.WithBaseURL` combined with `azure.WithAPIKey` or `azure.WithTokenCredential` fails with `azure: authentication requires azure.WithEndpoint`.
- `azure.WithEndpoint` requires exactly one of `azure.WithAPIKey` or `azure.WithTokenCredential`, and rejects `option.WithAPIKey` / `option.WithAdminAPIKey`.
- Do not pass a `/openai/v1` URL to `azure.WithEndpoint`; it builds a wrong path. Use `option.WithBaseURL` for the v1 API.
- Azure credentials require HTTPS. `azure.WithUnsafeAllowHTTP()` allows loopback emulators only.
- Custom HTTP clients must be `*http.Client` (a custom `RoundTripper` is fine) so redirects can be validated.
- `azure.WithEndpoint` clients ignore ambient `OPENAI_*` variables. Plain v1 clients still read `OPENAI_ORG_ID` and `OPENAI_CUSTOM_HEADERS`.
- Put the deployment name in `Model`. With `azure.WithEndpoint`, chat, completions, embeddings, audio, and image calls are routed to `/openai/deployments/{model}/...`.
- `azure.WithTokenCredentialScopes([]string{...})` overrides the default `https://cognitiveservices.azure.com/.default` scope.
- Responses WebSockets are not available through Azure clients.

## Amazon Bedrock

`bedrock.NewClient` returns a normal `openai.Client` configured for Bedrock's OpenAI-compatible API, with AWS credential resolution and SigV4 signing:

```go
client, err := bedrock.NewClient(ctx, bedrock.Config{
	Endpoint:  bedrock.EndpointRuntime, // default: bedrock.EndpointMantle
	AWSRegion: "us-east-1",
})
if err != nil {
	return err // region and credential resolution happen here
}
completion, err := client.Chat.Completions.New(ctx, openai.ChatCompletionNewParams{
	Model:    openai.ChatModel("us.openai.gpt-5.6-sol"), // full inference-profile ID
	Messages: []openai.ChatCompletionMessageParamUnion{openai.UserMessage("Say hello!")},
})
```

| Endpoint | Default base URL | SigV4 service |
|---|---|---|
| `bedrock.EndpointMantle` | `https://bedrock-mantle.{region}.api.aws/openai/v1` | `bedrock-mantle` |
| `bedrock.EndpointRuntime` | `https://bedrock-runtime.{region}.amazonaws.com/openai/v1` | `bedrock` |

- Credential precedence: `APIKey` or `BedrockTokenProvider` (bearer), then static keys / `AWSProfile` / `AWSCredentialsProvider` (SigV4), then `AWS_BEARER_TOKEN_BEDROCK`, then the default AWS chain. An expired `AWS_BEARER_TOKEN_BEDROCK` shadows the default chain.
- Region: `AWSRegion`, `AWS_REGION`, `AWS_DEFAULT_REGION`, then AWS config. Base URL: `BaseURL`, `AWS_BEDROCK_BASE_URL`, then the default.
- Never pass `option.WithBaseURL`, `option.WithAPIKey`, or `option.WithDataResidency` to a Bedrock client; set `bedrock.Config` fields instead.
- Ambient `OPENAI_*` variables are not inherited.
- Model IDs are full inference-profile IDs such as `us.openai.gpt-5.6-sol`, `us.openai.gpt-5.6-terra`, `us.openai.gpt-5.6-luna`, or `global.openai.gpt-5.6-sol`.
- Non-streaming Chat Completions on Runtime with SigV4 is the live-verified path; Responses and streaming depend on the AWS deployment.
- Request bodies must be replayable (SigV4 re-signs every retry). Authenticated requests do not follow redirects.
- `bedrock` is a package in the main module. Importing it adds the AWS SDK; importing only the root package does not (since v3.55.0).

## Data Residency

```go
client := openai.NewClient(option.WithDataResidency(option.DataResidencyEU))
```

| Constant | Endpoint |
|---|---|
| `option.DataResidencyGlobal` | `https://api.openai.com/v1/` |
| `option.DataResidencyUS` | `https://us.api.openai.com/v1/` |
| `option.DataResidencyEU` | `https://eu.api.openai.com/v1/` |
| `option.DataResidencyAE` | `https://ae.api.openai.com/v1/` |

- Combining `WithDataResidency` and `WithBaseURL` in the same call is an error, reported at request time.
- It is rejected for Bedrock and Azure clients and for X.509 workload identity.
- It does not grant regional access; the project must be provisioned for that region. There is no environment variable for it.

## Mutual TLS with an API Key

```go
certificate, err := tls.LoadX509KeyPair("/secrets/openai/client-chain.pem", "/secrets/openai/client.key")
if err != nil {
	return err
}
base, ok := http.DefaultTransport.(*http.Transport)
if !ok {
	return errors.New("http.DefaultTransport is not an *http.Transport")
}
transport := base.Clone()
transport.Proxy = nil
transport.ResponseHeaderTimeout = 10 * time.Minute // keep the SDK default
transport.TLSClientConfig = &tls.Config{
	Certificates: []tls.Certificate{certificate},
	GetClientCertificate: func(*tls.CertificateRequestInfo) (*tls.Certificate, error) {
		return &certificate, nil // always present it, even if CA hints do not match
	},
}
client := openai.NewClient(
	option.WithBaseURL("https://mtls.api.openai.com/v1"), // EU: https://mtls-eu.api.openai.com/v1
	option.WithHTTPClient(&http.Client{
		Transport: transport,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse // only offer the certificate to the configured endpoint
		},
	}),
)
```

The certificate file holds the leaf followed by required intermediates. Rebuild the transport and client after rotating the certificate.

## Workload Identity

Exchange a cloud identity token for a short-lived OpenAI bearer token instead of storing an API key:

```go
client := openai.NewClient(option.WithWorkloadIdentity(auth.WorkloadIdentity{
	IdentityProviderID: "idp-123",
	ServiceAccountID:   "sa-456",
	Provider:           auth.K8sServiceAccountTokenProvider(""), // "" = default projected token path
}))
```

| Provider | Constructor |
|---|---|
| Kubernetes service account | `auth.K8sServiceAccountTokenProvider(path)` |
| Azure managed identity | `auth.AzureManagedIdentityTokenProvider(*auth.AzureManagedIdentityTokenProviderConfig)` (nil for defaults) |
| GCP | `auth.GCPIDTokenProvider(*auth.GCPIDTokenProviderConfig)` (nil for defaults) |
| Custom | Type with `TokenType() auth.SubjectTokenType` and `GetToken(ctx, auth.HTTPDoer) (string, error)` |

- Tokens are cached and refreshed 20 minutes before expiry by default (`RefreshBufferSeconds` overrides).
- Configuration errors surface at the first request, not at `NewClient`.
- Workload identity cannot call admin endpoints, and cannot be combined with `WithAPIKey` in the same call.
- After a 401, the SDK refreshes and replays once, but does not replay body-bearing requests when caller middleware is installed.
- OAuth failures return `*auth.OAuthError`; use `StatusCode` and `ErrorCode` (issuer descriptions are redacted).
- The Azure and GCP providers call their link-local metadata endpoints directly, bypassing proxies and custom transports, with a 5-second timeout.

## X.509 Workload Identity

Exchange an enrolled workload certificate for a bearer token over mTLS:

```go
certificate, err := tls.LoadX509KeyPair("workload.crt", "workload.key")
if err != nil {
	return err
}
transport, err := auth.NewX509Transport(&http.Transport{
	TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{certificate}},
})
if err != nil {
	return err
}
defer transport.Close()

client := openai.NewClient(option.WithX509WorkloadIdentity(auth.X509WorkloadIdentity{
	IdentityProviderID: "idp-123",
	ServiceAccountID:   "sa-456",
	Transport:          transport, // RefreshBuffer defaults to 5 minutes
}))
```

- API requests must target `https://mtls.api.openai.com/v1/`; another `OPENAI_BASE_URL`, data residency, Azure, Bedrock, custom HTTP clients, HTTPS proxies, and API keys are rejected.
- The minted bearer is not bound to the certificate. Revoking a certificate does not revoke tokens already issued.
- Rotating the certificate requires a new transport and client. `Close` stops new calls but lets in-flight requests finish.

## Admin API Keys

```go
admin := openai.NewClient(option.WithAdminAPIKey(os.Getenv("OPENAI_ADMIN_KEY")))
page, err := admin.Admin.Organization.Projects.List(ctx, openai.AdminOrganizationProjectListParams{})
```

Keep admin keys out of application services; use them only in provisioning and reporting jobs.
