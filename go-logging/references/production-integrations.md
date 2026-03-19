# Production Integrations

Logging infrastructure patterns for Go web services. Organized by whether Go code changes are required or if the integration is handled externally.

## Architecture: Stdout-First Principle

In containerized environments, the standard pattern is:

1. **Go service** logs structured JSON to **stdout**.
2. **Platform agent** (Fluentd, Fluent Bit, Alloy, Filebeat) collects stdout.
3. **Aggregation backend** (Loki, Elasticsearch, CloudWatch) stores and indexes logs.

This decouples log production from log shipping. Most integrations below follow this pattern and require no Go code changes beyond structured JSON output.

## OpenTelemetry (Go Code Required)

The `otelslog` bridge connects Go's `log/slog` to OpenTelemetry's log signal, enabling correlation between logs, traces, and metrics.

### Setup

```bash
go get go.opentelemetry.io/contrib/bridges/otelslog
go get go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp
go get go.opentelemetry.io/otel/sdk/log
```

### Configuration

```go
import (
    "go.opentelemetry.io/contrib/bridges/otelslog"
    "go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp"
    sdklog "go.opentelemetry.io/otel/sdk/log"
)

func initLogger(ctx context.Context) (*slog.Logger, func()) {
    exporter, err := otlploghttp.New(ctx)
    if err != nil {
        log.Fatalf("failed to create log exporter: %v", err)
    }

    provider := sdklog.NewLoggerProvider(
        sdklog.WithProcessor(sdklog.NewBatchProcessor(exporter)),
    )

    handler := otelslog.NewHandler("my-service",
        otelslog.WithLoggerProvider(provider),
    )
    logger := slog.New(handler)

    cleanup := func() {
        if err := provider.Shutdown(ctx); err != nil {
            log.Printf("failed to shutdown log provider: %v", err)
        }
    }
    return logger, cleanup
}
```

### Trace Correlation

Use `slog.InfoContext(ctx, ...)` instead of `slog.Info(...)`. The `otelslog` handler extracts the active span from context and attaches `trace_id` and `span_id` to the log record automatically.

```go
func (h *OrderHandler) Create(w http.ResponseWriter, r *http.Request) {
    ctx, span := tracer.Start(r.Context(), "CreateOrder")
    defer span.End()

    // trace_id and span_id are attached automatically
    slog.InfoContext(ctx, "order created", slog.String("order_id", id))
}
```

### Performance Notes

- The `otelslog` bridge targets zero heap allocations for log calls with up to 5 non-complex attributes.
- Use `sdklog.NewBatchProcessor` (not simple processor) in production to buffer and batch-export logs.
- The OTel log signal is stable as of OpenTelemetry Go contrib v0.58+, though check for updates.

### Dual Output

For services that need both stdout logging and OTel export, use a multi-handler:

```go
jsonHandler := slog.NewJSONHandler(os.Stdout, nil)
otelHandler := otelslog.NewHandler("my-service")

// Use a fan-out handler (e.g., samber/slog-multi or custom)
logger := slog.New(multiHandler(jsonHandler, otelHandler))
```

## Kubernetes

No Go code changes required. Kubernetes expects containers to log to stdout/stderr.

### Requirements

- Output structured JSON (one JSON object per line, no multi-line exceptions).
- Include standard fields: `time` (RFC 3339), `level`, `msg`, `source` (optional).
- Do not write to files inside the container — they are lost on restart.

### How Collection Works

1. Container runtime (containerd) captures stdout/stderr to `/var/log/pods/`.
2. A DaemonSet agent (Fluentd, Fluent Bit, Alloy, Filebeat) tails these files.
3. Agent ships logs to the aggregation backend.

### Sidecar Pattern

For applications that must write to files (legacy constraints), use a sidecar container that tails the file and re-emits to its own stdout:

```yaml
containers:
  - name: app
    volumeMounts:
      - name: logs
        mountPath: /var/log/app
  - name: log-forwarder
    image: busybox
    command: ["sh", "-c", "tail -F /var/log/app/app.log"]
    volumeMounts:
      - name: logs
        mountPath: /var/log/app
```

Prefer stdout directly when possible — sidecars add resource overhead and complexity.

## Fluentd / Fluent Bit

No Go code changes required. These run as DaemonSets or sidecars and collect logs from stdout or files.

### Fluent Bit vs Fluentd

| Feature | Fluent Bit | Fluentd |
|---|---|---|
| Memory footprint | ~650 KB | ~40 MB |
| Plugin ecosystem | Smaller, built-in | Extensive, Ruby plugins |
| Use case | Edge collection, forwarding | Aggregation, complex routing |

### Parsing Go JSON Logs

Fluent Bit configuration to parse JSON from container stdout:

```ini
[INPUT]
    Name              tail
    Path              /var/log/containers/*.log
    Parser            docker
    Tag               kube.*

[FILTER]
    Name              kubernetes
    Match             kube.*
    Merge_Log         On
    K8S-Logging.Parser On

[OUTPUT]
    Name              es
    Match             *
    Host              elasticsearch
    Port              9200
    Logstash_Format   On
```

`Merge_Log On` tells Fluent Bit to parse the JSON body of Go's structured logs and merge the fields into the top-level log record.

## ELK Stack (Elasticsearch, Logstash, Kibana)

No Go code changes required. The Go service logs JSON to stdout; collection is handled by Filebeat or Fluentd.

### Key Configuration

- Use `ReplaceAttr` to rename slog's `msg` key to `message` if your ELK pipeline expects it.
- Include a `service.name` field for filtering in Kibana.
- Use `slog.Group("labels", ...)` for fields that should become Elasticsearch label fields.

## journald / systemd (RHEL / Linux)

### Option 1: Automatic (No Go Code)

When a Go service runs as a systemd unit, stdout/stderr is captured by journald automatically:

```ini
# /etc/systemd/system/myapp.service
[Service]
ExecStart=/usr/local/bin/myapp
StandardOutput=journal
StandardError=journal
SyslogIdentifier=myapp
```

Query with:

```bash
journalctl -u myapp.service --since "1 hour ago" -o json-pretty
```

Structured JSON logged to stdout appears as the `MESSAGE` field in journald.

### Option 2: Native Journal Protocol (Go Code)

For direct journal integration with custom structured fields, use `github.com/coreos/go-systemd/v22/journal`:

```go
import "github.com/coreos/go-systemd/v22/journal"

journal.Send("order created", journal.PriInfo, map[string]string{
    "ORDER_ID":  orderID,
    "USER_ID":   userID,
    "COMPONENT": "orders",
})
```

Custom fields become queryable journal fields:

```bash
journalctl COMPONENT=orders ORDER_ID=abc123
```

This approach is only useful for services running directly on systemd hosts (not in containers).

### Option 3: Syslog (Go Code)

Go's standard library includes `log/syslog` for BSD syslog (RFC 3164) output:

```go
import "log/syslog"

writer, err := syslog.Dial("tcp", "syslog-server:514",
    syslog.LOG_INFO|syslog.LOG_DAEMON, "myapp")
if err != nil {
    log.Fatal(err)
}

handler := slog.NewJSONHandler(writer, nil)
slog.SetDefault(slog.New(handler))
```

Note: `log/syslog` is frozen, does not support RFC 5424 structured data, and is not available on Windows. For cross-platform or RFC 5424 syslog, use a third-party library.

## Dapr

No Go code changes required. Dapr's sidecar architecture captures application stdout.

### Configuration

Enable JSON logging in your Dapr deployment annotation:

```yaml
annotations:
  dapr.io/enabled: "true"
  dapr.io/log-as-json: "true"
```

Or via Helm for the Dapr system services:

```bash
helm install dapr dapr/dapr --namespace dapr-system --set global.logAsJson=true
```

Dapr's sidecar logs and your application logs can both be collected by Fluentd/Fluent Bit for unified aggregation.

## Grafana Loki

### Option 1: Agent Collection (No Go Code)

Use Grafana Alloy (successor to Promtail) as a DaemonSet to collect stdout logs and ship to Loki. This is the recommended approach.

### Option 2: Direct Push (Go Code)

For environments without a log collection agent, push logs directly from Go:

```go
import (
    slogmulti "github.com/samber/slog-multi"
    slogloki "github.com/samber/slog-loki"
    "github.com/grafana/loki-client-go/loki"
)

func initLokiLogger() *slog.Logger {
    config, _ := loki.NewDefaultConfig("http://loki:3100/loki/api/v1/push")
    config.TenantID = "my-tenant"
    client, _ := loki.New(config)

    lokiHandler := slogloki.Option{
        Level:  slog.LevelInfo,
        Client: client,
    }.NewLokiHandler()

    // Fan-out: stdout for local debugging + Loki for aggregation
    logger := slog.New(slogmulti.Fanout(
        slog.NewJSONHandler(os.Stdout, nil),
        lokiHandler,
    ))
    return logger
}
```

Direct push adds a dependency on Loki availability. Prefer agent-based collection for resilience.

## Cloud Provider Logging

### AWS CloudWatch

No Go code required if using ECS/EKS with the `awslogs` driver or Fluent Bit. The service logs JSON to stdout; the platform agent ships to CloudWatch.

For Lambda, stdout is automatically captured by CloudWatch Logs.

### GCP Cloud Logging

No Go code required on GKE — stdout JSON is automatically ingested. GCP recognizes `severity` as the level field. Use `ReplaceAttr` to rename slog's `level` key to `severity` for native integration:

```go
ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
    if a.Key == slog.LevelKey {
        a.Key = "severity"
    }
    return a
},
```

### Azure Monitor

No Go code required on AKS with Container Insights enabled. JSON stdout is collected automatically.

## Log Rotation (File-Based Environments)

For services running outside containers where file-based logging is needed:

### Using lumberjack

```go
import "gopkg.in/natefinch/lumberjack.v2"

rotator := &lumberjack.Logger{
    Filename:   "/var/log/myapp/app.log",
    MaxSize:    100,  // megabytes
    MaxBackups: 5,
    MaxAge:     30,   // days
    Compress:   true,
    LocalTime:  false, // use UTC for timestamps in filenames
}

// Dual output: file rotation + stdout
writer := io.MultiWriter(os.Stdout, rotator)
handler := slog.NewJSONHandler(writer, &slog.HandlerOptions{
    Level: slog.LevelInfo,
})
slog.SetDefault(slog.New(handler))
```

Lumberjack assumes single-process access to the log file. Do not point multiple processes at the same file.

### Using logrotate (External)

For systemd services, configure `/etc/logrotate.d/myapp`:

```
/var/log/myapp/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

`copytruncate` avoids the need for signal-based reopen. The Go process continues writing to the same file descriptor.

## Observability Pipeline Architecture

### Three Pillars

| Signal | Tool | Go integration |
|---|---|---|
| Logs | slog + collection agent | JSON to stdout |
| Traces | OpenTelemetry SDK | `otel` trace SDK + context propagation |
| Metrics | OpenTelemetry SDK or Prometheus | `otel` metric SDK or `prometheus/client_golang` |

### Correlation

Link logs to traces by including `trace_id` and `span_id` in log records. Use `slog.InfoContext(ctx, ...)` with an OTel-aware handler (e.g., `otelslog`), or extract them manually:

```go
span := trace.SpanFromContext(ctx)
if span.SpanContext().IsValid() {
    logger = logger.With(
        slog.String("trace_id", span.SpanContext().TraceID().String()),
        slog.String("span_id", span.SpanContext().SpanID().String()),
    )
}
```

### Push vs Pull Logging

| Pattern | How it works | When to use |
|---|---|---|
| **Pull (agent-based)** | Agent tails files/stdout on the node | Standard for K8s, systemd, containers |
| **Push (direct)** | Application sends logs to backend over HTTP/gRPC | Serverless, edge nodes without agents, direct Loki/OTLP push |

Prefer pull-based collection — it decouples your application from the logging backend's availability. Push is appropriate when no agent infrastructure exists or for serverless environments.

### Standard Field Names

Use consistent field names across services for effective aggregation and querying:

| Field | Key | Source |
|---|---|---|
| Timestamp | `time` | slog default |
| Log level | `level` | slog default |
| Message | `msg` | slog default |
| Service name | `service` | Set via `logger.With()` at startup |
| Environment | `env` | Set via `logger.With()` at startup |
| Request ID | `request_id` | HTTP middleware |
| Trace ID | `trace_id` | OTel context or middleware |
| Caller | `source` | `AddSource: true` in HandlerOptions |
