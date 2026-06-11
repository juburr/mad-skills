<div align="center">
    <img align="center" width="320" src=".resources/logos/mad-skills.png" alt="Mad Skills"><br />

</div>

**MAD SKILLS** is my personal collection of agent skills for [Claude Code](https://claude.ai/code), [Codex](https://developers.openai.com/codex/skills/), and [Gemini CLI](https://geminicli.com/), tailored specifically to my preferred tech stack and personal preferences. Contributions and fixes to existing skills are welcome.

## 🧰 Available Skills

<!-- Non-breaking spaces are used as a Markdown hack to control column width  -->
|Skill &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;  | Description |
|---|---|
| `cpp-performance` | Guides C++ performance optimization and review, covering benchmarking, `perf`, top-down microarchitecture analysis, flame graphs, cache and allocation tuning, false sharing, NUMA, `std::execution`/OpenMP/oneTBB, PGO/LTO/BOLT/AutoFDO, and compiler remarks. |
| `geospatial-imagery` | Guides geospatial imagery workflows including format conversion, GDAL operations, OGC protocols (WMS/WMTS/TMS), tile server development, front-end client integration (Cesium, OpenLayers), imagery sourcing, spatial indexing, and performance optimization. |
| `go-adk` | Guides development of AI agents using Google's [Agent Development Kit](https://github.com/google/adk-go) (ADK) for Go, including multi-agent orchestration, tool definition, MCP integration, and A2A connectivity. |
| `go-logging` | Guides structured logging implementation in Go web services using `log/slog` and the standard library, including HTTP request logging middleware, log levels, error propagation, security, and production integrations. |
| `go-mcp` | Guides development of [MCP](https://github.com/modelcontextprotocol/go-sdk) servers and clients in Go, including tool/resource/prompt registration, transport selection, authentication, and integration into existing services. |
| `go-openai` | Guides development with the official [OpenAI](https://github.com/openai/openai-go) Go SDK, including chat completions, streaming, tool calling, structured outputs, reasoning models, and OpenAI-compatible providers (Azure, vLLM, Ollama). |
| `go-performance` | Guides writing high-performance Go code and conducting performance-focused code reviews. |
| `go-protobuf` | Guides writing production-ready Protocol Buffer definitions and Go protobuf code using [google.golang.org/protobuf](https://pkg.go.dev/google.golang.org/protobuf). Covers proto3 schema design, gRPC services, JSON/XML interop, NATS messaging, and OpenAPI documentation. |
| `go-security` | Guides secure Go coding practices and security reviews. |
| `go-web-service-stigs` | Guides DISA STIG compliance for custom Go web services using the ASD STIG, Web Server SRG, and API STIG V1R1. |
| `podman-rpms` | Guides building RPMs that deploy containers with rootless [Podman](https://github.com/containers/podman) and [Quadlet](https://github.com/containers/podman/tree/main/pkg/systemd/quadlet) on RHEL 8/9/10, including air-gapped image delivery and Podman 4.x/5.x compatibility. |
| `postgres-rls` | Guides [PostgreSQL](https://www.postgresql.org/docs/current/ddl-rowsecurity.html) row-level security (RLS) policy design, implementation, review, debugging, and performance optimization, including USING/WITH CHECK semantics, claim-based access control, security_invoker views, and indexing strategies. |
| `react-mui` | Guides building React UIs with [Material UI](https://github.com/mui/material-ui) (MUI), covering component APIs, theming, styling, and version migration. |
| `react-performance` | Guides React performance optimization including re-render prevention, memoization, concurrent features, and high-frequency updates. |
| `react-storybook` | Guides building and testing React-TypeScript components with [Storybook](https://github.com/storybookjs/storybook), covering CSF3 story format, interaction testing with play functions, accessibility testing, visual regression testing, portable stories, Next.js App Router mocks, MSW network mocking, and CI/CD integration. |
| `react-zustand` | Guides [Zustand](https://github.com/pmndrs/zustand) state management including store design, selectors, middleware, TypeScript patterns, performance optimization, and high-frequency update handling. |
| `rust-performance` | Guides Rust performance optimization including profiling, build configuration, allocation reduction, data structure selection, hot loop tuning, memory layout, and parallelism. |
| `rust-security` | Guides secure Rust coding practices and security reviews. |
| `vllm-deployment` | Guides deploying, configuring, and troubleshooting [vLLM](https://github.com/vllm-project/vllm) OpenAI-compatible servers, including GPU/VRAM sizing, OOM diagnostics, air-gapped deployments, and vLLM-specific API extensions. |
| `writing-skills` | Guides creation and improvement of coding assistant skills targeting Claude Code, Codex, and Gemini CLI, covering SKILL.md authoring, frontmatter, progressive disclosure, cross-provider compatibility, descriptions, and validation. |

## 🔧 Installation

The install script copies skills to the user-level skills directory for each supported coding assistant:

| Assistant | User Skills | Project Skills |
|---|---|---|
| Claude Code | `~/.claude/skills/` | `.claude/skills/` |
| Codex | `~/.codex/skills/` | `.codex/skills/` |
| Gemini CLI | `~/.gemini/skills/` | `.gemini/skills/` |

```bash
# Install all skills (skips existing)
bash install.sh

# Replace existing skills with updated versions
bash install.sh --overwrite

# Replace only a specific skill
bash install.sh --overwrite go-adk

# Install to specific assistants only (default: all)
bash install.sh --targets claude,codex
```

To install a skill manually, copy the skill directory to the appropriate location:

```bash
cp -r ./go-adk ~/.claude/skills/go-adk
cp -r ./go-adk ~/.codex/skills/go-adk
cp -r ./go-adk ~/.gemini/skills/go-adk
```

## 🗑️ Uninstallation

The uninstall script removes skills from all three coding assistant directories. Only skills whose names match directories in this repository are removed. Skills installed from other sources are never touched.

```bash
# Remove all skills provided by this repo
bash uninstall.sh

# Remove only a specific skill
bash uninstall.sh go-adk

# Remove from specific assistants only (default: all)
bash uninstall.sh --targets gemini
```

> **Note:** The `writing-skills` skill is also included at the project level (`.claude/skills/`) by design, so it remains available when working in this repo even after uninstalling the user-wide copy.
