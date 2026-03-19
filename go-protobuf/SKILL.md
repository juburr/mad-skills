---
name: go-protobuf
description: Guides writing production-ready Protocol Buffer definitions and Go
  protobuf code using google.golang.org/protobuf. Covers proto3 schema design,
  gRPC services, JSON/XML interop, NATS messaging, and OpenAPI documentation.
  Use when writing .proto files, generating Go protobuf code, integrating gRPC
  or protobuf serialization in Go projects, or migrating Go structs to protobuf.
---

# Go Protobuf

## Package

Use `google.golang.org/protobuf` — the official, maintained Go protobuf module.

**Do NOT use these deprecated alternatives:**

| Package | Status |
|---|---|
| `github.com/golang/protobuf` | Legacy wrapper; v1.4+ delegates to `google.golang.org/protobuf` internally. Do not add as a direct dependency. |
| `github.com/gogo/protobuf` | Abandoned community fork. Incompatible with the Opaque API, editions, lazy decoding, and other modern features. Migrate away from it. |

If an existing codebase uses `github.com/golang/protobuf`, update to at least v1.4 so it interoperates with `google.golang.org/protobuf`. Then migrate imports to `google.golang.org/protobuf` directly.

## Proto File Fundamentals

### File Structure

```protobuf
edition = "2024";  // or: syntax = "proto3";
package mycompany.myservice.v1;
option go_package = "github.com/mycompany/myservice/gen/myservicev1";
import "google/protobuf/timestamp.proto";
```

### Scalar Types

| Proto Type | Go Type | Wire Format | Notes |
|---|---|---|---|
| `int32` / `int64` | `int32` / `int64` | varint | Inefficient for negatives; use `sint*` instead |
| `uint32` / `uint64` | `uint32` / `uint64` | varint | Non-negative integers |
| `sint32` / `sint64` | `int32` / `int64` | zigzag varint | Efficient for frequently negative values |
| `fixed32` / `fixed64` | `uint32` / `uint64` | fixed 4/8 bytes | Efficient when values consistently > ~2^28/2^56 |
| `sfixed32` / `sfixed64` | `int32` / `int64` | fixed 4/8 bytes | Signed fixed-width |
| `float` / `double` | `float32` / `float64` | fixed 4/8 bytes | |
| `bool` | `bool` | varint | |
| `string` | `string` | length-delimited | Must be UTF-8 or 7-bit ASCII |
| `bytes` | `[]byte` | length-delimited | Raw binary data |

### Field Number Rules

| Range | Tag Size | Guidance |
|---|---|---|
| 1–15 | 1 byte | Reserve for the most frequently set fields |
| 16–2047 | 2 bytes | General use |
| 2048–2^29-1 | 3+ bytes | Rarely used fields |
| 19000–19999 | — | Reserved by the protobuf runtime; cannot be used |

**Rules:** Never reuse a field number — use `reserved`. Never change a field's wire type. Reserve both removed numbers and names.

```protobuf
message User {
  reserved 6, 9 to 11;
  reserved "old_field_name", "deprecated_field";
}
```

### Enums

Always define a zero-value `_UNSPECIFIED` entry. Prefix enum values with the enum type name in UPPER_SNAKE_CASE to avoid namespace collisions (enum values share a namespace within the parent scope in proto3).

```protobuf
enum OrderStatus {
  ORDER_STATUS_UNSPECIFIED = 0;
  ORDER_STATUS_PENDING = 1;
  ORDER_STATUS_CONFIRMED = 2;
  ORDER_STATUS_SHIPPED = 3;
  ORDER_STATUS_DELIVERED = 4;
  ORDER_STATUS_CANCELLED = 5;
}
```

**Prefer enums over booleans** when a field may gain additional states in the future.

### Maps

```protobuf
map<string, Project> projects = 1;
```

Keys must be `string`, `bool`, or integer types — not `float`, `double`, `bytes`, enums, or messages. Values can be any type except another map. Map fields cannot be `repeated`.

### Oneof

Use oneof when exactly one of several fields should be set at a time. Setting one field clears any previously set field in the same oneof group.

```protobuf
message Event {
  string event_id = 1;
  oneof payload {
    UserCreated user_created = 2;
    OrderPlaced order_placed = 3;
    PaymentProcessed payment_processed = 4;
  }
}
```

In Go (Open Struct API), oneof fields become an interface with wrapper types. Use a type switch:

```go
switch p := event.Payload.(type) {
case *pb.Event_UserCreated:  handleUserCreated(p.UserCreated)
case *pb.Event_OrderPlaced:  handleOrderPlaced(p.OrderPlaced)
case nil:                    // no payload set
}
```

### Field Presence (proto3)

| Declaration | Presence Tracked? | Go Type (Open API) |
|---|---|---|
| `string name = 1;` | No (implicit) | `string` |
| `optional string name = 1;` | Yes (explicit) | `*string` |
| `Message msg = 1;` | Yes (always) | `*Message` |
| `repeated string tags = 1;` | No (empty = not set) | `[]string` |
| `map<string, int32> m = 1;` | No (empty = not set) | `map[string]int32` |

### Well-Known Types

Import from `google/protobuf/` and use the corresponding Go packages under `google.golang.org/protobuf/types/known/`:

| Proto Type | Go Package | Common Conversions |
|---|---|---|
| `google.protobuf.Timestamp` | `timestamppb` | `timestamppb.Now()`, `timestamppb.New(t)`, `.AsTime()` |
| `google.protobuf.Duration` | `durationpb` | `durationpb.New(d)`, `.AsDuration()` |
| `google.protobuf.FieldMask` | `fieldmaskpb` | `fieldmaskpb.New(m, paths...)` |
| `google.protobuf.Any` | `anypb` | `anypb.New(m)`, `.UnmarshalNew()` |
| `google.protobuf.Struct` | `structpb` | `structpb.NewStruct(map[string]any{...})` |
| `google.protobuf.Value` | `structpb` | `structpb.NewStringValue(s)`, `.AsInterface()` |
| `google.protobuf.Empty` | `emptypb` | `&emptypb.Empty{}` |
| Wrappers (`StringValue`, etc.) | `wrapperspb` | `wrapperspb.String(s)`, `.GetValue()` |

**Prefer dedicated request/response messages over `google.protobuf.Empty` for public APIs.**
`google.protobuf.Empty` is fine for truly empty operations (especially internal APIs), but
named messages provide a safer evolution path when fields may be added later.

## Code Generation

### Toolchain

Install the compiler and Go plugins:

```bash
# protoc-gen-go: generates .pb.go (messages, enums)
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest

# protoc-gen-go-grpc: generates _grpc.pb.go (service stubs)
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
```

### Using buf (Recommended)

Prefer buf over raw `protoc`. It handles dependency management, linting, and breaking-change detection.

`buf.yaml`:

```yaml
version: v2
modules:
  - path: proto
lint:
  use: [STANDARD]
breaking:
  use: [FILE]
deps:
  - buf.build/googleapis/googleapis
```

`buf.gen.yaml`:

```yaml
version: v2
managed:
  enabled: true  # Auto-sets go_package, java_package, etc.
  override:
    - file_option: go_package_prefix
      value: github.com/mycompany/myservice/gen
plugins:
  - remote: buf.build/protocolbuffers/go
    out: gen
    opt: paths=source_relative
  - remote: buf.build/grpc/go
    out: gen
    opt: paths=source_relative
```

Commands: `buf generate`, `buf lint`, `buf breaking --against '.git#branch=main'`, `buf format -w`, `buf push`.

Run `buf lint` and `buf breaking` in CI so style and compatibility checks are enforced continuously.

### Validation with protovalidate

Use `protovalidate` (successor to `protoc-gen-validate`) for constraint validation using CEL expressions:

```protobuf
import "buf/validate/validate.proto";
message CreateOrderRequest {
  string customer_id = 1 [(buf.validate.field).string.min_len = 1];
  int32 quantity = 2 [(buf.validate.field).int32.gt = 0];
}
```

```go
import "github.com/bufbuild/protovalidate-go"
validator, _ := protovalidate.New()
if err := validator.Validate(req); err != nil { /* handle constraint violations */ }
```

### Open Struct API vs Opaque API

The **Opaque API** is the default for Edition 2024+ and recommended for new code. It uses getter/setter methods instead of direct struct fields, enables lazy decoding, and prevents accidental Go `reflect` usage (use `protoreflect` instead). Oneof fields use regular getters instead of interface wrapper types.

| Aspect | Open Struct (legacy) | Opaque (recommended) |
|---|---|---|
| Field access | Direct struct fields | Getter/setter methods |
| Presence | Pointer types (`*string`) | `Has()`/`Clear()` methods |
| Performance | Baseline | Better; lazy decoding |

For proto3 files, opt in: `option features.(pb.go).api_level = API_OPAQUE;` (requires `import "google/protobuf/go_features.proto";`). Use `API_HYBRID` for incremental migration.

```go
// Open Struct API (legacy)             Opaque API (Edition 2024+)
order.OrderId = "abc"                // order.SetOrderId("abc")
fmt.Println(order.OrderId)           // fmt.Println(order.GetOrderId())
if order.Priority != nil { ... }     // if order.HasPriority() { order.ClearPriority() }
```

## Go Protobuf API

### Core Operations (`proto` package)

```go
import "google.golang.org/protobuf/proto"

data, err := proto.Marshal(msg)          // Serialize to binary wire format
err := proto.Unmarshal(data, msg)        // Deserialize from binary wire format
clone := proto.Clone(msg).(*pb.MyMsg)    // Deep copy
proto.Merge(dst, src)                    // Merge src fields into dst
equal := proto.Equal(msg1, msg2)         // Structural equality
proto.Reset(msg)                         // Clear all fields
n := proto.Size(msg)                     // Serialized byte size
```

### JSON Serialization (`protojson` package)

```go
import "google.golang.org/protobuf/encoding/protojson"

opts := protojson.MarshalOptions{
    Multiline:       true,  Indent: "  ",    // Pretty-print
    UseProtoNames:   true,                    // snake_case fields (default: camelCase)
    EmitUnpopulated: false,                   // Omit zero-value fields (default)
}
jsonBytes, err := opts.Marshal(msg)

uopts := protojson.UnmarshalOptions{DiscardUnknown: true}
err := uopts.Unmarshal(jsonBytes, msg)
```

**Key behaviors:** Field names default to `lowerCamelCase` (override with `UseProtoNames` or per-field `json_name`). `Timestamp` -> RFC 3339, `Duration` -> `"3.5s"`, `int64`/`uint64` -> quoted strings, `bytes` -> base64, `Any` -> includes `@type` field. For full `MarshalOptions`/`UnmarshalOptions` field reference, read `references/go-struct-migration.md`.

### Testing (`protocmp` package)

```go
import (
    "testing"
    "github.com/google/go-cmp/cmp"
    "google.golang.org/protobuf/testing/protocmp"
)

// Always use protocmp.Transform() — never reflect.DeepEqual on proto messages.
if diff := cmp.Diff(want, got, protocmp.Transform()); diff != "" {
    t.Errorf("mismatch (-want +got):\n%s", diff)
}
```

## gRPC Services

### Service Definition

```protobuf
service OrderService {
  // Unary RPC.
  rpc GetOrder(GetOrderRequest) returns (GetOrderResponse);

  // Server streaming — server sends multiple responses.
  rpc WatchOrders(WatchOrdersRequest) returns (stream OrderEvent);

  // Client streaming — client sends multiple requests.
  rpc UploadLineItems(stream LineItem) returns (UploadSummary);
}
```

**Always define unique request and response messages per RPC.** Never share them across RPCs.

### Server Implementation

```go
type orderServer struct {
    pb.UnimplementedOrderServiceServer  // Embed for forward compatibility
}

func (s *orderServer) GetOrder(
    ctx context.Context,
    req *pb.GetOrderRequest,
) (*pb.GetOrderResponse, error) {
    order, err := s.store.Get(ctx, req.GetOrderId())
    if err != nil {
        return nil, status.Errorf(codes.NotFound, "order %s not found", req.GetOrderId())
    }
    return &pb.GetOrderResponse{Order: order}, nil
}
```

### Client Connection

```go
conn, err := grpc.NewClient("dns:///api.example.com:443",
    grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{})),
)
if err != nil { log.Fatal(err) }
defer conn.Close()
client := pb.NewOrderServiceClient(conn)
```

`grpc.NewClient` replaces the deprecated `grpc.Dial`. For local/insecure development: `grpc.WithTransportCredentials(insecure.NewCredentials())`.

### Error Handling

Use `google.golang.org/grpc/status` and `google.golang.org/grpc/codes`:

```go
// Server: return nil, status.Errorf(codes.InvalidArgument, "order_id must not be empty")
// Client: st, ok := status.FromError(err); if ok { switch st.Code() { ... } }
```

For rich structured errors (field violations, retry info), use `errdetails` — see `references/reference.md`.

### Interceptors

```go
func loggingInterceptor(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
    start := time.Now()
    resp, err := handler(ctx, req)
    log.Printf("%s took %v err=%v", info.FullMethod, time.Since(start), err)
    return resp, err
}

server := grpc.NewServer(grpc.ChainUnaryInterceptor(recoveryInterceptor, loggingInterceptor, authInterceptor))
```

For server startup, graceful shutdown, and streaming interceptor patterns, see `references/reference.md`.

### Production Runtime Defaults

For production gRPC clients/servers, set these explicitly:

- Deadlines/timeouts on every RPC.
- TLS/mTLS policy and certificate rotation.
- AuthN/AuthZ interceptors (JWT/OIDC, mTLS identity, RBAC/ABAC).
- Message size limits (`grpc.MaxRecvMsgSize`, `grpc.MaxSendMsgSize`) and backpressure strategy.
- Keepalive settings for long-lived channels.
- Observability (OpenTelemetry tracing/metrics + structured logs with correlation IDs).
- Health checking enabled in production; reflection enabled only when appropriate.
- Retry policies only for idempotent operations with bounded exponential backoff.

**ConnectRPC** (`connectrpc.com/connect`): Simpler alternative to gRPC that works over HTTP/1.1 or HTTP/2, handling Connect, gRPC, and gRPC-Web protocols simultaneously via standard `net/http` handlers.

## Protobuf as Source of Truth

Define data models in `.proto` files, then generate Go code, JSON/OpenAPI schemas, and docs from that single source. For JSON use `protojson`; for XML convert via Go structs and `encoding/xml`. For migrating existing Go structs to protobuf, read `references/go-struct-migration.md`.

### OpenAPI Documentation via gRPC-Gateway

Annotate RPCs with `google.api.http` options to generate a REST reverse-proxy and OpenAPI specs:

```protobuf
import "google/api/annotations.proto";
rpc GetOrder(GetOrderRequest) returns (GetOrderResponse) {
  option (google.api.http) = { get: "/v1/orders/{order_id}" };
}
```

Use `google.api.field_behavior` annotations (`REQUIRED`, `OUTPUT_ONLY`, `IMMUTABLE`) to enrich the spec. Proto comments propagate to OpenAPI descriptions. For full gRPC-Gateway configuration, HTTP method mapping, and OpenAPI annotation reference, read `references/reference.md`.

## Design Best Practices

- **One request/response message per RPC.** Never share request or response types across RPCs.
- **Use `FieldMask` for partial updates.** Clients specify which fields to update; servers apply only those.
- **Prefer enums over booleans** for states that may gain values later.
- **Paginate List RPCs** with `page_size` + opaque `page_token`:

```protobuf
message ListOrdersRequest {
  int32 page_size = 1;       // Max results. Server may return fewer.
  string page_token = 2;     // Opaque token from previous response.
}
message ListOrdersResponse {
  repeated Order orders = 1;
  string next_page_token = 2;  // Empty = no more pages.
}
```
- **Use composition.** Embed common fields in nested messages instead of duplicating.
- **Use `optional` only when absence is meaningful.** Do not mark every field optional.
- **Comment every field, message, enum, and RPC.** Comments propagate to generated docs and OpenAPI.

### Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Message | `PascalCase` | `OrderLineItem` |
| Field | `snake_case` | `order_id` |
| Enum type | `PascalCase` | `OrderStatus` |
| Enum value | `UPPER_SNAKE_CASE`, prefixed with type name | `ORDER_STATUS_PENDING` |
| Service | `PascalCase`, suffixed with `Service` | `OrderService` |
| RPC method | `PascalCase` verb phrase | `GetOrder`, `ListOrders`, `CreateOrder` |
| Package | lowercase dot-separated with version | `mycompany.orders.v1` |
| File | `snake_case` matching primary message/service | `order_service.proto` |

### Schema Evolution

**Safe changes:**
- Add new fields with new field numbers
- Add new non-zero enum values
- Add new RPCs or messages
- Rename fields (wire format uses numbers, not names)

**Breaking changes — avoid these:**
- Remove or reuse a field number
- Change a field's wire type (e.g., `int32` to `string`)
- Change between `repeated` and non-repeated
- Move fields into or out of a `oneof`
- Remove enum values clients depend on
- Change package or service names

### Forward and Backward Compatibility

Protobuf's binary wire format is designed for cross-version interop. A client compiled against **one version** of a proto definition can communicate with services running a **different version**, as long as changes are additive (non-breaking). You do **not** need to compile against multiple proto versions.

**How it works — unknown field preservation:**

| Scenario | What Happens |
|---|---|
| Old client receives message with new fields | New fields are stored as unknown bytes. They survive `proto.Marshal` round-trips — the old client can proxy or forward the message without data loss. |
| New client receives message missing new fields | New fields return their default zero values. Use `optional` + `Has()` if you need to distinguish "not sent" from "sent as zero." |
| Old client sends message to new server | New fields are absent; server sees defaults. Server must tolerate missing new fields (treat them as non-required). |

**Unknown field handling by format:**

| Format | On Unmarshal | On Marshal |
|---|---|---|
| Binary (`proto`) | Preserved by default | Included by default |
| JSON (`protojson`) | Error by default; `DiscardUnknown: true` to ignore | Not preserved (unknown fields lost) |
| Text (`prototext`) | Error by default; `DiscardUnknown: true` to ignore | `EmitUnknown: true` to include |

JSON APIs: `protojson` does not preserve unknown fields. Set `DiscardUnknown: true` on unmarshal to tolerate fields from older/newer clients.

**Multi-version client strategy:**

Compile against the **newest proto definition** you need to read. Older services will simply not populate the new fields (they'll be zero/default). Your client handles both cases:

```go
// Client compiled against v2 proto (which added priority field).
// Works with both v1 and v2 servers.
resp, err := client.GetOrder(ctx, req)
if err != nil { return err }

// v1 server: resp.Priority is ORDER_PRIORITY_UNSPECIFIED (zero value)
// v2 server: resp.Priority is the actual value
if resp.Priority != pb.OrderPriority_ORDER_PRIORITY_UNSPECIFIED {
    applyPriority(resp.Priority)
}
```

**When you must create a new package version** (e.g., `myservice.v2`):

- Changing the semantic meaning of existing fields
- Changing a field's type to an incompatible wire type
- Restructuring messages in ways that break wire compatibility
- Removing fields that older clients depend on without a deprecation period

For additive changes, stay in the same package — versioned packages are a last resort, not a default strategy. For compatible type change groups (which field types share wire types), see `references/reference.md`.

**`google.protobuf.Any` and versioning:** `Any` type URLs include the full package name (e.g., `type.googleapis.com/mycompany.myservice.v1.UserProfile`). Changing the package makes previously serialized `Any` values unresolvable. Treat the package name as part of the wire contract.

### Performance

- **Field numbers 1–15 use 1-byte tags** — reserve for frequently set fields (16+ use 2 bytes).
- **Use `sint32`/`sint64` for frequently negative values** — avoids 10-byte varints.
- **Use `fixed32`/`fixed64` when values consistently exceed ~2^28/2^56**.
- **Enable lazy decoding** (Opaque API) for submessages not always accessed.

### Anti-Patterns

| Anti-Pattern | Fix |
|---|---|
| `string` for everything | Use specific scalar types |
| Re-inventing `Timestamp`, `Duration` | Import well-known types from `google/protobuf/` |
| Reusing deleted field numbers | Use `reserved` |
| Overusing `google.protobuf.Empty` in public APIs | Prefer named request/response messages unless the operation is permanently empty |
| `bool is_active = 1;` (boolean blindness) | Use an enum — can evolve later |
| Huge monolithic messages | Split into focused messages |

## Reference Files

- **`references/reference.md`** — Wire format encoding, compatible type changes, buf lint rules, protoreflect, advanced gRPC (streaming, interceptors, health checks, rich errors, server lifecycle, graceful shutdown), protobuf over NATS, gRPC-Gateway config, proto3 JSON mapping. Read when needing encoding details, buf config, advanced gRPC patterns, NATS integration, or gRPC-Gateway setup.
- **`references/go-struct-migration.md`** — Migrating Go structs from JSON/XML to protobuf: type mapping, incompatible patterns (`interface{}`, custom map keys, embedded structs, generics), protojson options, migration checklist, backward-compatibility. Read when converting existing Go code with JSON-tagged structs to protobuf.
