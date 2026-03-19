# Go Protobuf Reference

Detailed reference material for encoding, buf configuration, advanced gRPC patterns, and protobuf reflection. Load this file when the main SKILL.md summaries are insufficient.

## Wire Format Encoding

### Tag Structure

Every field on the wire is prefixed by a tag: `(field_number << 3) | wire_type`.

| Wire Type | Value | Used For |
|---|---|---|
| VARINT | 0 | `int32`, `int64`, `uint32`, `uint64`, `sint32`, `sint64`, `bool`, `enum` |
| I64 | 1 | `fixed64`, `sfixed64`, `double` |
| LEN | 2 | `string`, `bytes`, embedded messages, packed repeated fields |
| I32 | 5 | `fixed32`, `sfixed32`, `float` |

Wire types 3 and 4 (SGROUP/EGROUP) are deprecated.

### Varint Encoding

Varints use 7 bits per byte for payload and 1 bit (MSB) as a continuation flag. Smaller values use fewer bytes:

| Value Range | Bytes Used |
|---|---|
| 0–127 | 1 |
| 128–16383 | 2 |
| 16384–2097151 | 3 |
| Up to 2^63 | Up to 10 |

**Negative integers with `int32`/`int64`:** Negative values are sign-extended to 64 bits, always taking 10 bytes. Use `sint32`/`sint64` for frequently negative values — zigzag encoding maps negative values to small positive varints (`-1` -> `1`, `1` -> `2`, `-2` -> `3`, etc.).

### Tag Size by Field Number

The tag itself is a varint. Since 3 bits are used for the wire type, the field number occupies the remaining bits:

- Field numbers 1–15: tag fits in 1 byte (4 bits for field number + 3 bits for wire type = 7 bits, within single varint byte)
- Field numbers 16–2047: tag needs 2 bytes
- Field numbers 2048–262143: tag needs 3 bytes

**Optimization:** Assign field numbers 1–15 to the most frequently populated fields. For a message serialized millions of times, this saves 1 byte per field per message.

### Packed Repeated Fields

Proto3 uses packed encoding for repeated scalar fields by default. Instead of repeating the tag for each element, elements are concatenated into a single length-delimited field:

```
// Unpacked (proto2 default): each element has its own tag
tag(1, VARINT) | value1 | tag(1, VARINT) | value2 | tag(1, VARINT) | value3

// Packed (proto3 default): one tag, length, then all values
tag(1, LEN) | length | value1 | value2 | value3
```

### Default Value Omission

In proto3, fields with default/zero values are not serialized:
- Numeric: `0` is omitted
- Bool: `false` is omitted
- String: `""` is omitted
- Bytes: empty `[]byte` is omitted
- Enums: value `0` is omitted
- Messages: `nil` is omitted

This means zero-valued fields consume zero bytes on the wire.

### Compatible Field Type Changes

Types sharing the same wire type can be swapped without breaking wire compatibility (though values may be truncated):

| Compatible Group | Wire Type |
|---|---|
| `int32`, `uint32`, `int64`, `uint64`, `bool` | Varint |
| `sint32`, `sint64` | ZigZag varint (compatible with each other only) |
| `fixed32`, `sfixed32` | 32-bit fixed |
| `fixed64`, `sfixed64` | 64-bit fixed |
| `string`, `bytes` | Length-delimited (compatible if bytes are valid UTF-8) |
| `enum` with any varint integer type | Varint |

Changing between groups (e.g., `int32` to `fixed32`, or `string` to `int32`) **corrupts data** — the decoder interprets bytes with the wrong wire type.

## buf Lint Rule Categories

### MINIMAL

Fundamental rules. No downside to applying them:
- Enum values must have a zero value with `_UNSPECIFIED` suffix
- Enum values must be prefixed with enum name in UPPER_SNAKE_CASE
- Package must be defined
- All files of the same package in the same directory
- Directory path matches package name

### STANDARD (default)

Everything in MINIMAL plus:
- Field names must be `lower_snake_case`
- Message names must be `PascalCase`
- Service names must be `PascalCase` and suffixed with `Service`
- RPC names must be `PascalCase`
- RPC request/response types must be unique per RPC (not shared)
- RPC request types suffixed with `Request`, response with `Response`
- Prefer dedicated request/response messages over `google.protobuf.Empty` for public APIs
- Enum value zero must be suffixed with `_UNSPECIFIED`
- No `required` fields (proto2)

### COMMENTS

Enforces comments on protobuf elements:
- `COMMENT_ENUM` — enums must have comments
- `COMMENT_ENUM_VALUE` — enum values must have comments
- `COMMENT_FIELD` — fields must have comments
- `COMMENT_MESSAGE` — messages must have comments
- `COMMENT_ONEOF` — oneofs must have comments
- `COMMENT_RPC` — RPCs must have comments
- `COMMENT_SERVICE` — services must have comments

### UNARY_RPC

Outlaws streaming RPCs. Use for protocols that do not support streaming (e.g., Twirp, Connect in unary-only mode).

### Custom buf.yaml Configuration

```yaml
version: v2
modules:
  - path: proto
lint:
  use:
    - STANDARD
    - COMMENTS
  except:
    - COMMENT_FIELD  # Opt out of per-field comment requirement
  enum_zero_value_suffix: _UNSPECIFIED
  rpc_allow_google_protobuf_empty_requests: false
  rpc_allow_google_protobuf_empty_responses: false
  service_suffix: Service
breaking:
  use:
    - FILE  # Most strict; also available: PACKAGE, WIRE, WIRE_JSON
```

### Breaking Change Detection Levels

| Level | Detects |
|---|---|
| `FILE` | Any change that breaks generated code (field renames, reordering, etc.) |
| `PACKAGE` | Breaking changes at package level (allows file reorganization) |
| `WIRE` | Only binary wire-format incompatibilities |
| `WIRE_JSON` | Wire-format and JSON-format incompatibilities |

## Production gRPC Operations Checklist

Set and review these before production launch:

- **Transport security:** TLS everywhere; mTLS for service-to-service when required.
- **Identity and authorization:** interceptor-based authn/authz (JWT/OIDC, SPIFFE/SVID, RBAC).
- **Deadlines:** every client call uses context deadlines/timeouts.
- **Retries:** only for idempotent methods, with capped exponential backoff and jitter.
- **Resource limits:** max receive/send message sizes, stream concurrency, connection limits.
- **Keepalive:** tune intervals/timeouts for load balancers and long-lived streams.
- **Observability:** OpenTelemetry spans/metrics + structured logs with request IDs.
- **Health/readiness:** expose gRPC health service and wire to orchestrator probes.
- **Reflection policy:** enable for internal/debug deployments; disable on untrusted public edges unless needed.
- **Graceful shutdown:** stop accepting new RPCs, drain active RPCs, then force-stop at timeout.

## Protobuf Reflection (`protoreflect`)

Use `protoreflect` when working with messages generically (logging, middleware, validation, custom serialization). Never use Go's `reflect` package on proto messages.

### Walking Message Fields

```go
import "google.golang.org/protobuf/reflect/protoreflect"

func LogFields(msg proto.Message) {
    m := msg.ProtoReflect()
    m.Range(func(fd protoreflect.FieldDescriptor, v protoreflect.Value) bool {
        fmt.Printf("%s: %v\n", fd.Name(), v)
        return true  // continue iteration
    })
}
```

### Checking Field Presence

```go
m := msg.ProtoReflect()
fd := m.Descriptor().Fields().ByName("order_id")
if m.Has(fd) {
    val := m.Get(fd)
    // field is populated
}
```

### Dynamic Message Creation

```go
import "google.golang.org/protobuf/reflect/protoreflect"
import "google.golang.org/protobuf/types/dynamicpb"

// Create a message from a descriptor (useful for plugins and generic tools).
md := someFileDescriptor.Messages().ByName("MyMessage")
dynMsg := dynamicpb.NewMessage(md)
```

### When to Use protoreflect

| Use Case | Approach |
|---|---|
| Logging/debugging all fields | `protoreflect.Range()` |
| Generic middleware (redacting PII) | Check field options via descriptor |
| Custom serialization format | Walk fields with descriptors |
| Schema introspection | `protoreflect.MessageDescriptor` |
| **Normal application code** | **Use generated getters/setters instead** |

## Advanced gRPC Patterns

### Server Streaming

```go
// Server implementation.
func (s *server) WatchOrders(
    req *pb.WatchOrdersRequest,
    stream pb.OrderService_WatchOrdersServer,
) error {
    ch := s.store.Watch(stream.Context(), req.GetFilter())
    for event := range ch {
        if err := stream.Send(event); err != nil {
            return err
        }
    }
    return nil
}

// Client consumption.
stream, err := client.WatchOrders(ctx, req)
if err != nil {
    return err
}
for {
    event, err := stream.Recv()
    if err == io.EOF {
        break
    }
    if err != nil {
        return err
    }
    process(event)
}
```

### Client Streaming

```go
// Server implementation.
func (s *server) UploadLineItems(
    stream pb.OrderService_UploadLineItemsServer,
) error {
    var items []*pb.LineItem
    for {
        item, err := stream.Recv()
        if err == io.EOF {
            return stream.SendAndClose(&pb.UploadSummary{
                Count: int32(len(items)),
            })
        }
        if err != nil {
            return err
        }
        items = append(items, item)
    }
}
```

### Bidirectional Streaming

```go
func (s *server) Chat(stream pb.OrderService_ChatServer) error {
    for {
        msg, err := stream.Recv()
        if err == io.EOF {
            return nil
        }
        if err != nil {
            return err
        }
        reply := processChat(msg)
        if err := stream.Send(reply); err != nil {
            return err
        }
    }
}
```

### Interceptor Chains

```go
server := grpc.NewServer(
    grpc.ChainUnaryInterceptor(
        recoveryInterceptor,   // Outermost: catches panics
        loggingInterceptor,    // Logs request/response
        authInterceptor,       // Validates authentication
        validationInterceptor, // Validates request fields
    ),
    grpc.ChainStreamInterceptor(
        streamRecoveryInterceptor,
        streamLoggingInterceptor,
        streamAuthInterceptor,
    ),
)
```

### Health Checking

```go
import "google.golang.org/grpc/health"
import healthpb "google.golang.org/grpc/health/grpc_health_v1"

healthServer := health.NewServer()
healthpb.RegisterHealthServer(server, healthServer)

// Set service health status.
healthServer.SetServingStatus("myservice.v1.OrderService", healthpb.HealthCheckResponse_SERVING)
```

### Server Reflection

Enable reflection for tools like `grpcurl` and `grpc_cli`:

```go
import "google.golang.org/grpc/reflection"

reflection.Register(server)
```

### Metadata (Headers)

```go
import "google.golang.org/grpc/metadata"

// Client: send metadata.
md := metadata.Pairs("authorization", "Bearer "+token)
ctx := metadata.NewOutgoingContext(ctx, md)
resp, err := client.GetOrder(ctx, req)

// Server: read metadata.
md, ok := metadata.FromIncomingContext(ctx)
if ok {
    tokens := md.Get("authorization")
}
```

### Deadlines and Timeouts

```go
// Client: set deadline.
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()
resp, err := client.GetOrder(ctx, req)

// Server: check deadline.
if deadline, ok := ctx.Deadline(); ok {
    if time.Until(deadline) < 100*time.Millisecond {
        return nil, status.Error(codes.DeadlineExceeded, "insufficient time remaining")
    }
}
```

### Rich Error Details

Use `errdetails` to attach structured information to gRPC errors:

```go
import (
    "google.golang.org/grpc/status"
    "google.golang.org/grpc/codes"
    "google.golang.org/genproto/googleapis/rpc/errdetails"
)

// Server: return error with field violations.
st := status.New(codes.InvalidArgument, "invalid request")
br := &errdetails.BadRequest{
    FieldViolations: []*errdetails.BadRequest_FieldViolation{
        {Field: "email", Description: "must be a valid email address"},
        {Field: "age", Description: "must be positive"},
    },
}
st, _ = st.WithDetails(br)
return nil, st.Err()

// Client: extract details.
st, _ := status.FromError(err)
for _, detail := range st.Details() {
    if br, ok := detail.(*errdetails.BadRequest); ok {
        for _, v := range br.GetFieldViolations() {
            log.Printf("field %s: %s", v.GetField(), v.GetDescription())
        }
    }
}
```

Other detail types: `RetryInfo` (retry delay), `DebugInfo` (stack traces), `QuotaFailure` (rate limits), `PreconditionFailure`.

### Server Lifecycle

```go
lis, err := net.Listen("tcp", ":50051")
if err != nil { log.Fatal(err) }

server := grpc.NewServer(/* interceptors, credentials */)
pb.RegisterOrderServiceServer(server, &orderServer{})
healthpb.RegisterHealthServer(server, health.NewServer())
reflection.Register(server)

// Graceful shutdown on signal.
go func() {
    sigCh := make(chan os.Signal, 1)
    signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
    <-sigCh
    log.Println("shutting down...")
    // GracefulStop waits for in-flight RPCs to complete.
    // Use a timeout to fall back to forced Stop.
    done := make(chan struct{})
    go func() { server.GracefulStop(); close(done) }()
    select {
    case <-done:
    case <-time.After(10 * time.Second):
        server.Stop()
    }
}()

log.Printf("serving on %s", lis.Addr())
if err := server.Serve(lis); err != nil { log.Fatal(err) }
```

## Protobuf over NATS

NATS payloads are `[]byte`, making protobuf a natural serialization choice. Use `proto.Marshal`/`proto.Unmarshal` directly. Do not use the deprecated `EncodedConn` protobuf encoder.

```go
// Publish: marshal then send.
data, err := proto.Marshal(msg)
if err != nil {
    return fmt.Errorf("marshal: %w", err)
}
if err := nc.Publish("orders.created", data); err != nil {
    return fmt.Errorf("publish: %w", err)
}

// Subscribe: receive then unmarshal.
nc.Subscribe("orders.created", func(m *nats.Msg) {
    var order pb.Order
    if err := proto.Unmarshal(m.Data, &order); err != nil {
        log.Printf("unmarshal error: %v", err)
        return
    }
    processOrder(&order)
})

// Request/Reply.
reqData, err := proto.Marshal(req)
if err != nil {
    return fmt.Errorf("marshal: %w", err)
}
reply, err := nc.Request("orders.get", reqData, 5*time.Second)
if err != nil {
    return fmt.Errorf("request: %w", err)
}
var resp pb.GetOrderResponse
if err := proto.Unmarshal(reply.Data, &resp); err != nil {
    return fmt.Errorf("unmarshal: %w", err)
}
```

JetStream uses the same marshal/unmarshal pattern. Call `m.Ack()` after successful unmarshal and processing, `m.Nak()` on unmarshal errors.

## Proto3 Canonical JSON Mapping Details

### Field Name Mapping

Proto field names are `snake_case`. The canonical JSON encoding uses `lowerCamelCase`:

| Proto Field | JSON Key (default) | JSON Key (`UseProtoNames`) |
|---|---|---|
| `order_id` | `orderId` | `order_id` |
| `line_items` | `lineItems` | `line_items` |
| `is_active` | `isActive` | `is_active` |

Override per-field with `json_name`:

```protobuf
string order_id = 1 [json_name = "order-id"];  // JSON key: "order-id"
```

### Numeric Type Precision

| Proto Type | JSON Representation | Reason |
|---|---|---|
| `int32`, `uint32`, `sint32` | Number | Fits in IEEE 754 double |
| `int64`, `uint64`, `sint64` | Quoted string (`"123"`) | Exceeds IEEE 754 double precision |
| `fixed32`, `sfixed32` | Number | Fits in IEEE 754 double |
| `fixed64`, `sfixed64` | Quoted string | Exceeds IEEE 754 double precision |
| `float`, `double` | Number | Standard JSON number |
| Special float values | `"NaN"`, `"Infinity"`, `"-Infinity"` | Quoted strings |

### Well-Known Type JSON Details

**Timestamp:**
- Format: RFC 3339 with optional nanosecond precision
- Range: `"0001-01-01T00:00:00Z"` to `"9999-12-31T23:59:59.999999999Z"`
- Always UTC (Z suffix)

**Duration:**
- Format: seconds with `s` suffix, optional fractional nanoseconds
- Examples: `"0s"`, `"3.5s"`, `"-1.5s"`, `"1000000s"`

**FieldMask:**
- Serialized as a single comma-separated string of paths
- Paths use camelCase in JSON (converted from snake_case proto names)
- Example: `"firstName,lastName,address.city"`

**Any:**
- Contains `@type` field with full type URL
- Remaining fields are the serialized message
- If the contained message has a special JSON mapping (like Timestamp), the value is placed under a `"value"` key

**Struct/Value/ListValue:**
- Transparent JSON mapping — `Struct` is a JSON object, `ListValue` is a JSON array, `Value` is any JSON primitive/object/array

### EmitUnpopulated vs EmitDefaultValues

| Option | Scalar (int32=0) | String (="") | Message (=nil) | Optional int32 (unset) |
|---|---|---|---|---|
| Neither (default) | Omitted | Omitted | Omitted | Omitted |
| `EmitDefaultValues` | `0` | `""` | Omitted | Omitted |
| `EmitUnpopulated` | `0` | `""` | `null` | `null` |

`EmitDefaultValues` preserves presence semantics (optional fields that are unset stay omitted). `EmitUnpopulated` is a strict superset that also emits `null` for unset presence-tracking fields.

## gRPC-Gateway Configuration

### HTTP Method Mapping

```protobuf
import "google/api/annotations.proto";

service UserService {
  // GET with path parameter.
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = {
      get: "/v1/users/{user_id}"
    };
  }

  // POST with body.
  rpc CreateUser(CreateUserRequest) returns (User) {
    option (google.api.http) = {
      post: "/v1/users"
      body: "*"
    };
  }

  // PATCH with partial body.
  rpc UpdateUser(UpdateUserRequest) returns (User) {
    option (google.api.http) = {
      patch: "/v1/users/{user.user_id}"
      body: "user"
    };
  }

  // DELETE.
  rpc DeleteUser(DeleteUserRequest) returns (google.protobuf.Empty) {
    option (google.api.http) = {
      delete: "/v1/users/{user_id}"
    };
  }

  // Additional bindings (multiple HTTP methods for one RPC).
  rpc ListUsers(ListUsersRequest) returns (ListUsersResponse) {
    option (google.api.http) = {
      get: "/v1/users"
      additional_bindings {
        get: "/v1/organizations/{org_id}/users"
      }
    };
  }
}
```

### OpenAPI v2 Annotations

```protobuf
import "protoc-gen-openapiv2/options/annotations.proto";

option (grpc.gateway.protoc_gen_openapiv2.options.openapiv2_swagger) = {
  info: {
    title: "Order Service API"
    version: "1.0"
    description: "API for managing orders."
    contact: {
      name: "API Support"
      email: "api@example.com"
    }
  }
  schemes: HTTPS
  consumes: "application/json"
  produces: "application/json"
  security_definitions: {
    security: {
      key: "BearerAuth"
      value: {
        type: TYPE_API_KEY
        in: IN_HEADER
        name: "Authorization"
      }
    }
  }
};
```

### Field Behavior Annotations

```protobuf
import "google/api/field_behavior.proto";

message CreateOrderRequest {
  // The order to create.
  Order order = 1 [(google.api.field_behavior) = REQUIRED];
}

message Order {
  // Output only. Server-assigned order ID.
  string order_id = 1 [(google.api.field_behavior) = OUTPUT_ONLY];

  // Required. Customer placing the order.
  string customer_id = 2 [(google.api.field_behavior) = REQUIRED];

  // Immutable. Cannot be changed after creation.
  string currency = 3 [(google.api.field_behavior) = IMMUTABLE];
}
```

These annotations propagate to the generated OpenAPI spec as field-level documentation.

### Serving Swagger UI

```go
import (
    "net/http"
    "github.com/grpc-ecosystem/grpc-gateway/v2/runtime"
)

mux := runtime.NewServeMux()
// Register gRPC-Gateway handlers...

// Serve OpenAPI spec.
http.HandleFunc("/swagger.json", func(w http.ResponseWriter, r *http.Request) {
    http.ServeFile(w, r, "docs/myservice.swagger.json")
})

// Serve Swagger UI (use a static file server or embed).
http.Handle("/swagger/", http.StripPrefix("/swagger/", http.FileServer(http.Dir("swagger-ui"))))
```
