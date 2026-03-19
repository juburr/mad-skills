# Third-Party Logging Libraries

Detailed usage for `uber-go/zap`, `rs/zerolog`, and `sirupsen/logrus`, including slog bridge configuration and migration guidance.

## When to Use a Third-Party Library

Stick with `log/slog` unless you have a measured need:

| Reason to switch | Library |
|---|---|
| Need zero-allocation logging at >100k logs/sec | `zerolog` |
| Need runtime level changes via HTTP, complex core composition, or hook pipelines | `zap` |
| Migrating legacy logrus code incrementally | Bridge logrus to slog handler |

## uber-go/zap

### Overview

Zap provides two logger types: `Logger` for zero-allocation structured logging on hot paths, and `SugaredLogger` for printf-style convenience where performance is less critical.

### Quick Start

```go
// Production: JSON, Info level, sampling enabled, stack traces on Error+
logger, _ := zap.NewProduction()
defer logger.Sync()

// Development: console, Debug level, stack traces on Warn+
logger, _ := zap.NewDevelopment()
defer logger.Sync()
```

### Structured Logging

```go
logger.Info("request handled",
    zap.String("method", "GET"),
    zap.String("path", "/api/orders"),
    zap.Int("status", 200),
    zap.Duration("latency", elapsed),
)
```

Zap fields (`zap.String`, `zap.Int`, etc.) are strongly typed and avoid interface boxing. The `Logger` achieves zero allocations through pre-allocated field encoders.

### SugaredLogger

```go
sugar := logger.Sugar()
sugar.Infow("request handled",
    "method", "GET",
    "status", 200,
)
sugar.Infof("server listening on %s", addr) // printf-style
```

`SugaredLogger` allocates for the variadic `...any` arguments. Use `Logger` on hot paths.

### Child Loggers

```go
// Add permanent fields
childLogger := logger.With(
    zap.String("service", "orders"),
    zap.String("version", "v1.2.0"),
)

// Named sub-loggers (adds a "logger" field)
authLogger := logger.Named("auth")
authLogger.Info("login") // {"logger":"auth","msg":"login"}
```

### AtomicLevel — Runtime Level Changes

```go
atom := zap.NewAtomicLevelAt(zap.InfoLevel)
logger := zap.New(zapcore.NewCore(
    zapcore.NewJSONEncoder(zap.NewProductionEncoderConfig()),
    zapcore.AddSync(os.Stdout),
    atom,
))

// Expose an HTTP endpoint for runtime level changes
mux.Handle("PUT /log/level", atom) // PUT with {"level":"debug"}
```

### Sampling

Zap's production config enables sampling by default: after the first N entries of a given level and message per second, it logs every Mth entry.

```go
core := zapcore.NewSamplerWithOptions(
    baseCore,
    time.Second, // tick interval
    100,         // log first 100 per second
    10,          // then every 10th
)
```

### Hooks

```go
core := zapcore.RegisterHooks(baseCore, func(entry zapcore.Entry) error {
    if entry.Level >= zapcore.ErrorLevel {
        errorCounter.Inc() // export as metric
    }
    return nil
})
```

### slog Bridge

Use zap as a backend for slog to preserve zap's performance while adopting slog's API:

```go
import "go.uber.org/zap/exp/zapslog"

zapLogger, _ := zap.NewProduction()
slogHandler := zapslog.NewHandler(zapLogger.Core(), nil)
slog.SetDefault(slog.New(slogHandler))

// Now all slog calls go through zap
slog.Info("handled", slog.String("path", "/api"))
```

### Migrating from Zap to slog

| Zap | slog equivalent |
|---|---|
| `zap.String("k", "v")` | `slog.String("k", "v")` |
| `zap.Int("k", 1)` | `slog.Int("k", 1)` |
| `logger.With(fields...)` | `logger.With(attrs...)` |
| `logger.Named("sub")` | `logger.WithGroup("sub")` (not exact: Named adds a `logger` key, WithGroup nests attributes) |
| `zap.NewAtomicLevel()` | `slog.LevelVar` |
| `zapcore.NewSampler(...)` | Custom `slog.Handler` with sampling logic |

## rs/zerolog

### Overview

Zerolog is the fastest Go logging library, achieving zero-allocation JSON logging through a fluent API that writes directly to an `io.Writer` without intermediate encoding steps.

### Quick Start

```go
// Global logger to stdout
zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
log := zerolog.New(os.Stdout).With().Timestamp().Logger()

// With caller info
log = log.With().Caller().Logger()
```

### Fluent API

```go
log.Info().
    Str("method", "GET").
    Str("path", "/api/orders").
    Int("status", 200).
    Dur("latency", elapsed).
    Msg("request handled")
```

Every chain must end with `.Msg("")` or `.Send()`. Forgetting this is a common bug — the log entry is silently discarded.

### Child Loggers

```go
childLog := log.With().
    Str("component", "database").
    Str("host", dbHost).
    Logger()

childLog.Info().Str("query", q).Msg("executing")
```

### Context Integration

```go
// Store logger in context
ctx = log.With().Str("request_id", reqID).Logger().WithContext(ctx)

// Retrieve from context
zerolog.Ctx(ctx).Info().Msg("processing")
```

### Log Levels

```go
zerolog.SetGlobalLevel(zerolog.InfoLevel)

// Per-logger level
debugLog := log.Level(zerolog.DebugLevel)
```

### Hook System

```go
type MetricsHook struct{}

func (h MetricsHook) Run(e *zerolog.Event, level zerolog.Level, msg string) {
    if level >= zerolog.ErrorLevel {
        errorCounter.Inc()
    }
}

log = log.Hook(MetricsHook{})
```

### HTTP Middleware (hlog)

zerolog provides `github.com/rs/zerolog/hlog` for HTTP middleware:

```go
mux.Use(hlog.NewHandler(log))
mux.Use(hlog.RequestIDHandler("request_id", "X-Request-ID"))
mux.Use(hlog.MethodHandler("method"))
mux.Use(hlog.URLHandler("url"))
```

### Performance Notes

Zerolog achieves zero allocations by:
- Using a pre-allocated byte buffer per event
- Writing JSON tokens directly without reflection
- Reusing event objects via `sync.Pool`

Trade-off: the fluent API is less composable than slog's handler chain. Custom output formats require implementing `io.Writer` wrappers rather than handler interfaces.

### When to Choose Zerolog Over slog

- Measured need for zero-allocation logging in extreme-throughput paths
- Existing codebase heavily invested in zerolog's fluent API
- Need for zerolog's built-in HTTP middleware (`hlog`)

## sirupsen/logrus

### Status

Logrus has been in maintenance mode since 2020. It receives security fixes but no new features. Migrate to `log/slog` for new code.

### Core API (for maintaining existing code)

```go
logrus.WithFields(logrus.Fields{
    "user_id":  userID,
    "order_id": orderID,
}).Info("order created")

logrus.WithError(err).Error("failed to process order")
```

### Entry (Child Logger Equivalent)

```go
entry := logrus.WithFields(logrus.Fields{
    "component": "auth",
    "version":   "v2",
})
entry.Info("authenticating user")
```

### Formatters

```go
logrus.SetFormatter(&logrus.JSONFormatter{
    TimestampFormat: time.RFC3339Nano,
    FieldMap: logrus.FieldMap{
        logrus.FieldKeyMsg: "message",
    },
})
```

### Hook System

Logrus hooks fire on every log entry. They are often used for sending logs to external systems:

```go
type SlackHook struct{ webhookURL string }

func (h *SlackHook) Levels() []logrus.Level {
    return []logrus.Level{logrus.ErrorLevel, logrus.FatalLevel}
}

func (h *SlackHook) Fire(entry *logrus.Entry) error {
    // send to Slack
    return nil
}

logrus.AddHook(&SlackHook{webhookURL: url})
```

### Migration Path to slog

| Logrus pattern | slog equivalent |
|---|---|
| `logrus.WithFields(Fields{"k": v})` | `slog.With(slog.String("k", v))` |
| `logrus.WithError(err)` | `slog.Any("error", err)` |
| `logrus.SetFormatter(&JSONFormatter{})` | `slog.NewJSONHandler(os.Stdout, nil)` |
| `logrus.SetLevel(logrus.DebugLevel)` | `slog.HandlerOptions{Level: slog.LevelDebug}` |
| `logrus.AddHook(hook)` | Custom `slog.Handler` wrapping the base handler |
| `entry := logrus.WithFields(...)` | `child := logger.With(...)` |

### Incremental Migration Strategy

1. **Phase 1** — Wrap slog as a logrus hook or redirect logrus output to slog's handler. New code uses slog directly.
2. **Phase 2** — Convert modules one at a time from logrus to slog. Both coexist during migration.
3. **Phase 3** — Remove logrus dependency once all call sites are converted.

### Known Issues

- Thread safety: logrus is thread-safe by default, but `TextFormatter` requires `ForceColors: false` for concurrent use.
- Performance: logrus allocates an `Entry` per log call and uses reflection for field formatting. It is significantly slower than slog, zap, or zerolog.
- `Fatal` calls `os.Exit(1)`, which skips deferred functions — same caveat as the standard `log` package.

## Performance Comparison

Approximate benchmarks (lower is better). Run your own benchmarks on your hardware for decisions.

| Library | Time (ns/op) | Allocs/op | Bytes/op |
|---|---|---|---|
| `zerolog` | ~180 | 0 | 0 |
| `zap` (Logger) | ~200 | 0 | 0 |
| `slog` (JSONHandler) | ~300 | 0 (<=5 attrs) | 0-40 |
| `zap` (SugaredLogger) | ~400 | 1 | 80 |
| `logrus` | ~3000 | 10+ | 2000+ |

Live benchmarks updated weekly: `betterstack-community.github.io/go-logging-benchmarks`

## Community slog Handlers

The slog ecosystem includes community handlers for various backends:

| Handler | Package | Purpose |
|---|---|---|
| Zap bridge | `go.uber.org/zap/exp/zapslog` | Use zap core as slog backend |
| Loki | `github.com/samber/slog-loki` | Push logs directly to Grafana Loki |
| Multi-handler | `github.com/samber/slog-multi` | Fan-out to multiple handlers |
| Sampling | `github.com/samber/slog-sampling` | Rate-limit log output |
| Sentry | `github.com/samber/slog-sentry` | Send errors to Sentry |
| Slack/webhook | `github.com/samber/slog-slack` | Alert on high-severity logs |

Use `sloglint` (`github.com/go-simpler/sloglint`) to enforce consistent slog usage patterns across a codebase.
