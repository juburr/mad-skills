---
name: go-logging
description: Guides structured logging implementation in Go web services using log/slog
  and the standard library. Use when adding logging to Go services, choosing logging
  strategies, implementing HTTP request logging middleware, configuring log levels,
  handling error propagation with logs, or reviewing logging code for correctness,
  security, and performance.
---

# Go Logging

Covers `log/slog` (Go 1.21+) as the primary logging solution, the legacy `log` package, and design patterns for production Go web services. Prefer `log/slog` for all new code. Check the project's `go.mod` `go` directive to confirm slog availability.

## Library Selection

| Need | Recommendation |
|---|---|
| New project, no special requirements | `log/slog` (standard library) |
| Existing project using `log` | Migrate to `log/slog`; `slog.SetDefault` bridges the legacy `log` package |
| Extreme throughput (>100k logs/sec) | `zerolog` or `zap` with slog bridge — see `references/third-party-libraries.md` |
| Existing project using logrus | Migrate to `log/slog`; logrus is in maintenance mode |

## Legacy `log` Package

The `log` package provides unstructured, levelless logging. Understand it for maintaining legacy code, but do not use it in new services.

```go
log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile) // timestamp + caller
log.SetPrefix("[myapp] ")
log.SetOutput(os.Stderr)

log.Print("server starting")            // prints and continues
log.Fatalf("bind failed: %v", err)      // prints and calls os.Exit(1)
log.Panicf("invariant broken: %v", err) // prints and panics
```

Key limitations: no log levels, no structured key-value pairs, no JSON output, no handler abstraction. `Fatal` calls `os.Exit(1)`, bypassing all deferred functions. `Panic` runs deferred functions during stack unwinding but terminates the goroutine if unrecovered. Avoid both in library code.

## `log/slog` — Structured Logging

### Setup

```go
// Development: human-readable text to stderr
logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{
    Level:     slog.LevelDebug,
    AddSource: true,
}))

// Production: JSON to stdout for log aggregation
logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    Level: slog.LevelInfo,
}))

slog.SetDefault(logger) // also redirects legacy log.Print calls
```

### Log Levels

| Level | Value | Use for |
|---|---|---|
| `Debug` | -4 | Developer diagnostics; disabled in production |
| `Info` | 0 | Normal operations: startup, shutdown, request served |
| `Warn` | 4 | Degraded state the system can recover from: retries, fallbacks, deprecated usage |
| `Error` | 8 | Failures requiring attention: failed requests, broken integrations |

Do not log at `Error` unless something is genuinely broken. A 404 is not an error — it is normal traffic. Reserve `Error` for conditions that need investigation.

Custom levels are supported (e.g., `const LevelTrace = slog.Level(-8)`). Implement `ReplaceAttr` to map custom levels to human-readable names.

### Dynamic Log Levels

Change verbosity at runtime without restarting the service:

```go
var level slog.LevelVar
level.Set(slog.LevelInfo)

handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: &level})
slog.SetDefault(slog.New(handler))

// Later, from an admin endpoint or signal handler:
level.Set(slog.LevelDebug)
```

### Log Level from Environment

Set the initial log level from an environment variable (e.g., `LOG_LEVEL`) at startup:

```go
func parseLogLevel(env string) slog.Level {
    switch strings.ToLower(os.Getenv(env)) {
    case "debug", "trace":
        return slog.LevelDebug
    case "warn", "warning":
        return slog.LevelWarn
    case "error":
        return slog.LevelError
    default:
        return slog.LevelInfo
    }
}

var level slog.LevelVar
level.Set(parseLogLevel("LOG_LEVEL"))

handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: &level})
slog.SetDefault(slog.New(handler))
```

Using `slog.LevelVar` here serves double duty — it reads the initial level from the environment and still allows runtime changes via an admin endpoint or signal handler (see Dynamic Log Levels above). This is preferable to compiling in a fixed level or logging everything and filtering externally, which wastes I/O and storage at scale.

### Structured Attributes

```go
slog.Info("request handled",
    slog.String("method", r.Method),
    slog.String("path", r.URL.Path),
    slog.Int("status", statusCode),
    slog.Duration("latency", elapsed),
)
```

Prefer typed `slog.String`, `slog.Int`, `slog.Duration` functions over `slog.Any` — they avoid interface boxing allocations. Use consistent key naming (snake_case) across the service.

### Groups

Namespace related attributes with `slog.Group` to avoid key collisions. For example, `slog.Group("http", slog.String("method", "GET"), slog.Int("status", 200))` produces `{"http":{"method":"GET","status":200}}` in JSON output.

### Child Loggers

Create child loggers with `With` to attach context that applies to all subsequent messages:

```go
// Service-level child logger
dbLogger := logger.With(slog.String("component", "database"))

// Request-scoped child logger
reqLogger := logger.With(
    slog.String("request_id", requestID),
    slog.String("user_id", userID),
)
reqLogger.Info("processing order", slog.String("order_id", orderID))
```

`WithGroup` nests all subsequent attributes under a group name — `logger.WithGroup("auth").Info("login", slog.String("user", email))` produces `{"auth":{"user":"..."}}`. Attributes passed to `With` are formatted once at creation, not on every log call — use child loggers for repeated context.

### Context Integration

Pass context to log calls to enable trace correlation:

```go
slog.InfoContext(ctx, "order created", slog.String("order_id", id))
```

A custom handler can extract trace IDs, request IDs, or other values from `context.Context` and include them automatically. This is the recommended pattern for correlating logs with distributed traces.

### ReplaceAttr

Customize attribute formatting globally:

```go
handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
        // Rename "msg" key to "message" for ELK compatibility
        if a.Key == slog.MessageKey {
            a.Key = "message"
        }
        // Redact sensitive keys
        if a.Key == "password" || a.Key == "token" || a.Key == "authorization" {
            return slog.String(a.Key, "REDACTED")
        }
        return a
    },
})
```

Keep `ReplaceAttr` logic fast — it runs on every attribute of every log call.

### LogValuer — Lazy Evaluation and Redaction

Implement `slog.LogValuer` on types to control their log representation:

```go
// Redact sensitive types
type Token string

func (Token) LogValue() slog.Value {
    return slog.StringValue("REDACTED")
}

// Defer expensive computation — only evaluated if level is enabled
type ExpensiveQuery struct{ db *sql.DB }

func (q ExpensiveQuery) LogValue() slog.Value {
    stats := q.db.Stats() // only called when this log level is active
    return slog.GroupValue(
        slog.Int("open", stats.OpenConnections),
        slog.Int("idle", stats.Idle),
    )
}
```

### Custom Handlers

Implement the `slog.Handler` interface (four methods: `Enabled`, `Handle`, `WithAttrs`, `WithGroup`) for specialized behavior like multi-destination routing, sampling, or enrichment. Do not embed `slog.Handler`. Use the official handler writing guide at `github.com/golang/example/blob/master/slog-handler-guide/README.md`. Validate with `testing/slogtest.Run` (Go 1.22+) or `testing/slogtest.TestHandler`.

## Design Patterns

### Error Handling: Log or Return, Never Both

The most common logging anti-pattern is logging an error and then returning it. This produces duplicate messages as the error propagates up the call stack.

```go
// WRONG — logs the same error at every layer
func (s *Service) Process(ctx context.Context, id string) error {
    _, err := s.repo.Fetch(ctx, id)
    if err != nil {
        slog.ErrorContext(ctx, "fetch failed", slog.String("err", err.Error()))
        return fmt.Errorf("process: %w", err) // caller logs it again
    }
    return nil
}

// CORRECT — return with context, log once at the boundary
func (s *Service) Process(ctx context.Context, id string) error {
    _, err := s.repo.Fetch(ctx, id)
    if err != nil {
        return fmt.Errorf("process %s: %w", id, err)
    }
    return nil
}
```

Log errors at **error boundaries** — HTTP handlers, gRPC interceptors, message consumers, background job runners. These are the top of the call stack where errors stop propagating.

```go
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    err := h.service.Process(r.Context(), r.PathValue("id"))
    if err != nil {
        slog.ErrorContext(r.Context(), "request failed",
            slog.String("err", err.Error()),
            slog.String("path", r.URL.Path),
        )
        http.Error(w, "internal error", http.StatusInternalServerError)
    }
}
```

### When Multiple Log Messages Are Warranted

A single request or operation should typically produce **one** log message per significant state transition. Multiple messages are justified when:

| Scenario | Example |
|---|---|
| Long-running operation with phases | `"migration started"` ... `"migration completed"` |
| Retry loops | Log each attempt with attempt number, log final outcome |
| Partial success | Log the overall result plus individual failures |
| Audit trail requirements | Separate entries for authentication, authorization, and action |

Avoid logging every function entry/exit. If you need call-level granularity, use tracing (OpenTelemetry spans), not logs.

### Logger Propagation

Inject loggers explicitly rather than relying on globals or context:

```go
// PREFERRED — explicit dependency injection
type OrderService struct {
    logger *slog.Logger
    repo   OrderRepository
}

func NewOrderService(logger *slog.Logger, repo OrderRepository) *OrderService {
    return &OrderService{
        logger: logger.With(slog.String("component", "orders")),
        repo:   repo,
    }
}
```

For HTTP middleware where dependency injection is impractical, `context.Context` is an acceptable transport:

```go
type ctxKey struct{}

func WithLogger(ctx context.Context, l *slog.Logger) context.Context {
    return context.WithValue(ctx, ctxKey{}, l)
}

func FromContext(ctx context.Context) *slog.Logger {
    if l, ok := ctx.Value(ctxKey{}).(*slog.Logger); ok {
        return l
    }
    return slog.Default()
}
```

### HTTP Request Logging

#### What to Log

Every completed request should include these fields:

| Field | Key | Source | Required |
|---|---|---|---|
| HTTP method | `method` | `r.Method` | Yes |
| Path | `path` | `r.URL.Path` | Yes |
| Status code | `status` | Response recorder | Yes |
| Latency | `latency` | `time.Since(start)` | Yes |
| Request ID | `request_id` | `X-Request-ID` header or generated UUID | Yes |
| Client IP | `client_ip` | `r.RemoteAddr` or `X-Forwarded-For` behind proxy | Yes |
| User identity | `user_id` | Auth middleware / context | Yes, if authenticated |
| Response size | `response_bytes` | Response recorder | Recommended |
| User agent | `user_agent` | `r.UserAgent()` | Recommended |
| Query string | `query` | `r.URL.RawQuery` | Optional |

Do not log: `Authorization` headers, bearer tokens, cookies, session IDs, or request/response bodies that may contain PII. Log user identity by an opaque identifier (user ID, username), never by credential.

#### One Log Entry vs Two

Log **one entry per request, on completion**. This is the standard pattern — it captures status, latency, and outcome in a single record, which simplifies querying and reduces log volume.

Log an additional entry on arrival only when:

| Scenario | Rationale |
|---|---|
| Long-running requests (file uploads, streaming) | Detect hangs — if the completion entry never appears, the arrival entry provides evidence |
| Audit-sensitive endpoints | Regulatory requirements may mandate recording intent before outcome |
| Debug mode | Temporarily enabled to troubleshoot request routing or middleware ordering |

When logging on arrival, use `Debug` level so it is suppressed in production by default.

#### Status Code to Log Level

| Status range | Level | Rationale |
|---|---|---|
| 2xx, 3xx | `Info` | Normal traffic |
| 400, 404, 405 | `Info` | Expected client behavior — a client sending a bad request is not a server problem |
| 401, 403, 429 | `Warn` | May indicate credential stuffing, broken auth, or abuse; worth surfacing |
| Other 4xx | `Warn` | Unusual client errors that may warrant review |
| 5xx | `Error` | Server-side failure requiring investigation |

A spike in 4xx responses may warrant alerting, but handle that at the monitoring layer (aggregation rules, dashboards), not by escalating individual log levels.

#### Middleware Example

Register logging middleware first (outermost) so the timer captures the full request lifecycle — auth context is still available because logging runs after `next.ServeHTTP` returns.

```go
func LoggingMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        requestID := r.Header.Get("X-Request-ID")
        if requestID == "" {
            requestID = uuid.NewString()
        }

        reqLogger := slog.Default().With(
            slog.String("request_id", requestID),
        )
        ctx := WithLogger(r.Context(), reqLogger)

        rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
        next.ServeHTTP(rec, r.WithContext(ctx))

        level := slog.LevelInfo
        if rec.status >= 500 {
            level = slog.LevelError
        } else if rec.status >= 400 {
            switch rec.status {
            case 400, 404, 405:
                // expected client behavior — keep at Info
            default:
                level = slog.LevelWarn
            }
        }

        reqLogger.Log(r.Context(), level, "request completed",
            slog.String("method", r.Method),
            slog.String("path", r.URL.Path),
            slog.Int("status", rec.status),
            slog.Duration("latency", time.Since(start)),
            slog.String("client_ip", r.RemoteAddr),
            slog.Int("response_bytes", rec.written),
        )
    })
}

type statusRecorder struct {
    http.ResponseWriter
    status  int
    written int
}

func (r *statusRecorder) WriteHeader(code int) {
    r.status = code
    r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
    n, err := r.ResponseWriter.Write(b)
    r.written += n
    return n, err
}

// Unwrap exposes the underlying ResponseWriter for http.ResponseController,
// preserving access to http.Flusher, http.Hijacker, etc.
func (r *statusRecorder) Unwrap() http.ResponseWriter {
    return r.ResponseWriter
}
```

### gRPC Interceptor Logging

Apply the same boundary-logging pattern with unary and stream interceptors. Log method, latency, and error status at the interceptor level — not inside individual RPC handlers.

## Security

### Sensitive Data

Never log passwords, tokens, API keys, credit card numbers, SSNs, or session IDs. Defense in depth:

1. **Type-level redaction** — implement `LogValuer` on sensitive types (strongest guarantee).
2. **Key-level redaction** — use `ReplaceAttr` to catch known sensitive key names.
3. **Code review** — flag raw `slog.Any` calls with user-controlled values.

### Log Injection

Structured JSON logging (`JSONHandler`) is inherently resistant to log injection because values are JSON-encoded. Newlines, control characters, and special characters are escaped automatically.

If using `TextHandler` or writing to plain text, sanitize user-controlled values before logging. Never pass user input as the message template — always pass it as an attribute value.

```go
// WRONG — user input in message string, defeats structured logging
// Variable messages break log aggregation and hide data from indexing
slog.Info(fmt.Sprintf("user logged in: %s", username))

// CORRECT — user input as structured attribute, queryable and aggregatable
slog.Info("user logged in", slog.String("username", username))
```

### Compliance Considerations

For GDPR, HIPAA, PCI-DSS: establish which fields are logged, enforce redaction at the type level, configure log retention policies in your aggregation system, and restrict access to raw logs. Structured logging makes automated compliance scanning feasible — unstructured `log.Printf` does not.

## Performance

### Allocation Characteristics

| Approach | Allocs/op | Notes |
|---|---|---|
| `slog` with typed attrs (<=5 attrs) | 0 | Attrs stored in Record's inline array |
| `slog` with >5 attrs | 1 | Spills to heap-allocated slice |
| `slog.Any()` with concrete type | 1 | Interface boxing |
| `log.Printf` | 1-2 | Format string parsing + allocation |

### Level Checking

slog's `Enabled` method is checked before any attribute evaluation. Disabled log calls cost only the `Enabled` check (~1ns). Combine with `LogValuer` for expensive computations to ensure zero work when the level is disabled.

### Log Sampling

For extremely high-throughput paths, implement a custom `slog.Handler` that logs a fraction of events (e.g., 1 in every N). Use an `atomic.Int64` counter to avoid contention. Community options include `github.com/samber/slog-sampling`.

### Log Rotation

For file-based logging outside containers, use `natefinch/lumberjack` as the `io.Writer` for the slog handler. In containerized environments, log to stdout and let the platform handle rotation. See `references/production-integrations.md` for detailed configuration.

## Testing

### Validating Custom Handlers

Use `testing/slogtest.Run` to validate that custom handlers comply with the `slog.Handler` interface contract.

### Asserting Log Output

Inject a `slog.New(slog.NewJSONHandler(&buf, nil))` with a `bytes.Buffer` writer, then assert on `buf.String()` contents after exercising the code under test. For richer assertions, use `github.com/thejerf/slogassert`.

## Third-Party Libraries

Prefer `log/slog` for new projects. Use third-party libraries only when slog's performance is measured and insufficient, or when migrating legacy code incrementally.

| Library | Status | Primary advantage | slog bridge |
|---|---|---|---|
| `uber-go/zap` | Active | Highest customizability, `AtomicLevel` | `zapslog.NewHandler` |
| `rs/zerolog` | Active | Fastest raw throughput, zero-alloc | Community adapters |
| `sirupsen/logrus` | Maintenance mode | Hooks ecosystem | Migrate to slog |

For detailed usage, migration patterns, and when to choose each library, read `references/third-party-libraries.md`.

## Production Integrations

| Integration | Go code needed? | Summary |
|---|---|---|
| OpenTelemetry | Yes | `otelslog` bridge correlates logs with traces via context |
| Kubernetes | No | Log JSON to stdout; K8s handles collection |
| Fluentd / Fluent Bit | No | DaemonSet or sidecar collects stdout/files |
| ELK / Logstash | No | Filebeat or Fluentd ships logs; no Go code |
| journald / systemd | Optional | Go's `log/syslog` or direct journal protocol |
| Dapr | No | Sidecar collects stdout; set `dapr.io/log-as-json: "true"` |
| Grafana Loki | Optional | Alloy/Promtail collects stdout, or use `slog-loki` for direct push |
| Cloud logging (AWS/GCP/Azure) | No | JSON to stdout; platform agents collect |
| Syslog | Yes | `log/syslog` package for RFC 3164 (BSD syslog) output |

For detailed setup instructions and Go code examples, read `references/production-integrations.md`.

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/third-party-libraries.md` | Detailed zap, zerolog, and logrus usage with migration patterns and slog bridge configuration | Working with zap, zerolog, or logrus, or migrating from them to slog |
| `references/production-integrations.md` | OpenTelemetry setup, log rotation, Kubernetes patterns, Loki direct push, journald integration, and observability pipeline architecture | Configuring production log pipelines, integrating with observability platforms, or setting up log collection infrastructure |
