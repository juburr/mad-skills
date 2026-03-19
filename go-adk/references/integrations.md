# Integrations

MCP server integration, OpenAI/custom model providers, and Vertex AI configuration for ADK Go.

## MCP Toolset

Connect ADK agents to MCP (Model Context Protocol) servers using the official Go MCP SDK (`github.com/modelcontextprotocol/go-sdk`). Do **not** use the third-party `mark3labs/mcp-go`.

```go
import (
    "github.com/modelcontextprotocol/go-sdk/mcp"
    "google.golang.org/adk/tool/mcptoolset"
)
```

### Transport Types

| Transport | Use Case | Import |
|---|---|---|
| `mcp.CommandTransport` | Local subprocess (stdio) | `os/exec` |
| `mcp.StreamableClientTransport` | Remote HTTPS server (preferred) | - |
| In-memory | Testing / in-process | `mcp.NewInMemoryTransports()` |

### Stdio Transport (Local Process)

```go
import "os/exec"

mcpTools, err := mcptoolset.New(mcptoolset.Config{
    Transport: &mcp.CommandTransport{
        Command: exec.Command("npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"),
    },
})

agent, err := llmagent.New(llmagent.Config{
    Name:     "fs_agent",
    Model:    model,
    Toolsets: []tool.Toolset{mcpTools},
})
```

### Streamable HTTP Transport (Remote Server)

```go
mcpTools, err := mcptoolset.New(mcptoolset.Config{
    Transport: &mcp.StreamableClientTransport{
        Endpoint: "https://my-mcp-server.example.com/mcp/",
    },
})
```

With authentication (e.g., GitHub Copilot MCP):

```go
import "golang.org/x/oauth2"

ts := oauth2.StaticTokenSource(
    &oauth2.Token{AccessToken: os.Getenv("GITHUB_PAT")},
)
mcpTools, err := mcptoolset.New(mcptoolset.Config{
    Transport: &mcp.StreamableClientTransport{
        Endpoint:   "https://api.githubcopilot.com/mcp/",
        HTTPClient: oauth2.NewClient(ctx, ts),
    },
})
```

### In-Memory Transport (Testing)

Create an MCP server and client in the same process:

```go
type WeatherInput struct {
    City string `json:"city" jsonschema:"city name"`
}
type WeatherOutput struct {
    Summary string `json:"weather_summary"`
}

func GetWeather(ctx context.Context, req *mcp.CallToolRequest, input WeatherInput) (*mcp.CallToolResult, WeatherOutput, error) {
    return nil, WeatherOutput{Summary: "Sunny in " + input.City}, nil
}

clientTransport, serverTransport := mcp.NewInMemoryTransports()

server := mcp.NewServer(&mcp.Implementation{Name: "weather", Version: "v1.0.0"}, nil)
mcp.AddTool(server, &mcp.Tool{
    Name:        "get_weather",
    Description: "Gets weather for a city.",
}, GetWeather)
server.Connect(ctx, serverTransport, nil)

mcpTools, err := mcptoolset.New(mcptoolset.Config{
    Transport: clientTransport,
})
```

### Tool Filtering

Limit which MCP tools are exposed to the agent:

```go
// Using FilterToolset (preferred)
filtered := tool.FilterToolset(mcpTools, tool.StringPredicate([]string{
    "get_weather",
    "get_forecast",
}))

agent, err := llmagent.New(llmagent.Config{
    Toolsets: []tool.Toolset{filtered},
    // ...
})
```

### Human-in-the-Loop Confirmation

Require user approval before MCP tool execution:

```go
mcpTools, err := mcptoolset.New(mcptoolset.Config{
    Transport:           transport,
    RequireConfirmation: true,  // All tools require confirmation
})

// Or dynamic confirmation per tool:
mcpTools, err := mcptoolset.New(mcptoolset.Config{
    Transport: transport,
    RequireConfirmationProvider: func(toolName string, args any) bool {
        return toolName == "delete_file"  // Only confirm destructive tools
    },
})
```

### Generic Toolset Confirmation (`tool.WithConfirmation`)

As of v0.6.0, HITL confirmation can be applied to **any** `tool.Toolset`, not just MCP toolsets. This wraps every tool in the toolset with confirmation logic.

```go
import "google.golang.org/adk/tool"

// Static: all tools in the toolset require confirmation
confirmed := tool.WithConfirmation(myToolset, true, nil)

// Dynamic: per-tool confirmation decisions
confirmed := tool.WithConfirmation(myToolset, false, func(toolName string, toolInput any) bool {
    return toolName == "delete_record"
})

agent, err := llmagent.New(llmagent.Config{
    Name:     "safe_agent",
    Model:    model,
    Toolsets: []tool.Toolset{confirmed},
})
```

**How it works:** `WithConfirmation` returns a wrapped `Toolset` where each tool's execution checks confirmation status. When a tool requires confirmation, the agent emits a confirmation request event. The caller must approve it before the tool runs. Inside a tool function, use `ctx.ToolConfirmation()` to check status and `ctx.RequestConfirmation(hint, payload)` to trigger the approval flow.

**Note:** This API is marked **experimental** and may change before v1.0.

### mcptoolset.Config

```go
type Config struct {
    Client                      *mcp.Client               // Optional custom MCP client.
    Transport                   mcp.Transport              // Required.
    ToolFilter                  tool.Predicate             // Deprecated: use tool.FilterToolset instead.
    RequireConfirmation         bool                       // Static HITL flag for all tools.
    RequireConfirmationProvider ConfirmationProvider       // Dynamic HITL. Takes precedence over RequireConfirmation.
}

type ConfirmationProvider func(toolName string, toolInput any) bool
```

**Behavior notes:**
- MCP sessions are created lazily on first LLM request
- Automatic reconnection on `mcp.ErrConnectionClosed`, `mcp.ErrSessionMissing`, `io.ErrClosedPipe`, `io.EOF`
- Tool discovery happens via `ListTools()` with pagination
- `ToolFilter` is deprecated; use `tool.FilterToolset` (shown above) for new code

**Production notes:**
- For HTTP-based MCP servers with idle timeouts, the cached `*mcp.ClientSession` may go stale between requests. Mitigate by tuning server-side timeouts or recreating the toolset on connection errors.
- `StreamableClientTransport` supports `MaxRetries` for automatic request retries.

### Complete MCP Example

```go
package main

import (
    "context"
    "log"
    "os"
    "os/exec"

    "github.com/modelcontextprotocol/go-sdk/mcp"
    "google.golang.org/genai"

    "google.golang.org/adk/agent"
    "google.golang.org/adk/agent/llmagent"
    "google.golang.org/adk/cmd/launcher"
    "google.golang.org/adk/cmd/launcher/full"
    "google.golang.org/adk/model/gemini"
    "google.golang.org/adk/tool"
    "google.golang.org/adk/tool/mcptoolset"
)

func main() {
    ctx := context.Background()

    model, err := gemini.NewModel(ctx, "gemini-2.5-flash", &genai.ClientConfig{
        APIKey: os.Getenv("GOOGLE_API_KEY"),
    })
    if err != nil { log.Fatal(err) }

    mcpTools, err := mcptoolset.New(mcptoolset.Config{
        Transport: &mcp.CommandTransport{
            Command: exec.Command("npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"),
        },
    })
    if err != nil { log.Fatal(err) }

    a, err := llmagent.New(llmagent.Config{
        Name:        "fs_assistant",
        Model:       model,
        Description: "File system assistant.",
        Instruction: "Help the user manage files.",
        Toolsets:    []tool.Toolset{mcpTools},
    })
    if err != nil { log.Fatal(err) }

    config := &launcher.Config{AgentLoader: agent.NewSingleLoader(a)}
    l := full.NewLauncher()
    if err = l.Execute(ctx, config, os.Args[1:]); err != nil {
        log.Fatalf("Run failed: %v\n\n%s", err, l.CommandLineSyntax())
    }
}
```

## OpenAI Integration

As of ADK-Go v0.6.0, there is no official `model/openai` provider in the published module. To use OpenAI or other non-Gemini models, implement the `model.LLM` interface yourself or use a community adapter.

### Writing a Custom model.LLM Provider

Implement the `model.LLM` interface to use any LLM backend:

```go
package myprovider

import (
    "context"
    "iter"

    "google.golang.org/adk/model"
    "google.golang.org/genai"
)

type MyModel struct {
    name string
    // ... your client
}

func NewModel(name string /* , config ... */) (model.LLM, error) {
    return &MyModel{name: name}, nil
}

func (m *MyModel) Name() string { return m.name }

func (m *MyModel) GenerateContent(
    ctx context.Context,
    req *model.LLMRequest,
    stream bool,
) iter.Seq2[*model.LLMResponse, error] {
    return func(yield func(*model.LLMResponse, error) bool) {
        // 1. Convert req.Contents ([]*genai.Content) to your provider's format
        // 2. Convert req.Config (*genai.GenerateContentConfig) for temperature, etc.
        // 3. Convert req.Tools to your provider's tool/function format
        // 4. Call your LLM API
        // 5. Convert response back to model.LLMResponse

        // For non-streaming, yield a single response:
        yield(&model.LLMResponse{
            Content: &genai.Content{
                Parts: []*genai.Part{genai.NewPartFromText("Hello!")},
                Role:  "model",
            },
            TurnComplete: true,
        }, nil)

        // For streaming, yield multiple partial responses:
        // yield(&model.LLMResponse{Content: chunk1, Partial: true}, nil)
        // yield(&model.LLMResponse{Content: chunk2, Partial: true}, nil)
        // yield(&model.LLMResponse{Content: final, TurnComplete: true}, nil)
    }
}
```

**Key conversion requirements:**

| ADK Type | You Must Handle |
|---|---|
| `req.Contents` | Convert `[]*genai.Content` (with `Parts` containing text, function calls, function responses) to your format |
| `req.Config` | Map `Temperature`, `MaxOutputTokens`, `ResponseMIMEType`, etc. |
| `req.Tools` | Convert `genai.FunctionDeclaration` tool schemas to your provider's format |
| Response `Content` | Convert your provider's response to `*genai.Content` with appropriate `Parts` |
| Function calls | Map your provider's tool calls to `genai.FunctionCall` parts |
| Streaming | Set `Partial: true` for intermediate chunks, `TurnComplete: true` for final |

**Usage with ADK:**

```go
myModel, err := myprovider.NewModel("gpt-4o")
agent, err := llmagent.New(llmagent.Config{
    Name:  "my_agent",
    Model: myModel,
    // ... rest of config
})
```

### OpenAI Go SDK Reference

The official SDK is at `github.com/openai/openai-go`. Key usage:

```go
import (
    "github.com/openai/openai-go/v3"
    "github.com/openai/openai-go/v3/option"
)

client := openai.NewClient(option.WithAPIKey(os.Getenv("OPENAI_API_KEY")))

// For Azure OpenAI:
client := openai.NewClient(
    option.WithBaseURL("https://my-resource.openai.azure.com/openai"),
    option.WithAPIKey(os.Getenv("AZURE_OPENAI_KEY")),
)
```

## Gemini / Vertex AI Configuration

### Gemini API (Default)

```go
model, err := gemini.NewModel(ctx, "gemini-2.5-flash", &genai.ClientConfig{
    APIKey: os.Getenv("GOOGLE_API_KEY"),
})
```

Environment variables: `GOOGLE_API_KEY` or `GEMINI_API_KEY`.

### Vertex AI

```go
model, err := gemini.NewModel(ctx, "gemini-2.5-flash", &genai.ClientConfig{
    Project:  "my-gcp-project",
    Location: "us-central1",
    Backend:  genai.BackendVertexAI,
})
```

Environment variables:
- `GOOGLE_GENAI_USE_VERTEXAI=true`
- `GOOGLE_CLOUD_PROJECT=my-gcp-project`
- `GOOGLE_CLOUD_LOCATION=us-central1`

### Auto-Detection

With no explicit config, ADK checks environment variables:

```go
model, err := gemini.NewModel(ctx, "gemini-2.5-flash", &genai.ClientConfig{})
```

### genai.ClientConfig

```go
type ClientConfig struct {
    APIKey      string          // For Gemini API.
    Project     string          // GCP project for Vertex AI.
    Location    string          // GCP region for Vertex AI.
    Backend     Backend         // BackendGeminiAPI (default) or BackendVertexAI.
    HTTPOptions *HTTPOptions    // Custom HTTP headers.
}
```

## Key Dependencies

```
google.golang.org/adk                              # ADK core
google.golang.org/genai                             # Google GenAI types (Gemini/Vertex)
github.com/modelcontextprotocol/go-sdk              # Official MCP SDK v1.3.1+ (NOT mark3labs/mcp-go)
github.com/a2aproject/a2a-go                        # A2A protocol
github.com/openai/openai-go/v3                      # OpenAI SDK (for custom providers)
```
