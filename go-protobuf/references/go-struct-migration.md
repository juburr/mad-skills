# Go Struct Migration to Protobuf

## The protojson Package

Package: `google.golang.org/protobuf/encoding/protojson`

### MarshalOptions

```go
type MarshalOptions struct {
    Multiline        bool    // Format with newlines; if Indent is "", uses default indent
    Indent           string  // Indent chars (spaces/tabs only); non-empty implies Multiline=true
    AllowPartial     bool    // Allow missing required fields without error
    UseProtoNames    bool    // Use proto field names (snake_case) instead of lowerCamelCase
    UseEnumNumbers   bool    // Emit enum values as integers instead of string names
    EmitUnpopulated  bool    // Emit all fields including unset ones (see table below)
    EmitDefaultValues bool   // Like EmitUnpopulated but preserves presence-sensing (no null)
    Resolver         interface {
        protoregistry.ExtensionTypeResolver
        protoregistry.MessageTypeResolver
    } // For expanding google.protobuf.Any; defaults to protoregistry.GlobalTypes
}
```

**EmitUnpopulated** emits zero-valued fields as:

| JSON value | Protobuf field |
|---|---|
| `false` | proto3 boolean |
| `0` | proto3 numeric |
| `""` | proto3 string/bytes |
| `null` | proto2 scalar fields, message fields |
| `[]` | list fields |
| `{}` | map fields |

**EmitDefaultValues** is similar but does NOT emit `null` for presence-sensing fields (optional, proto2 scalars, message fields). `EmitUnpopulated` takes precedence as it is a strict superset.

### UnmarshalOptions

```go
type UnmarshalOptions struct {
    AllowPartial   bool  // Allow missing required fields
    DiscardUnknown bool  // Ignore unknown fields and enum name values
    RecursionLimit int   // Max nesting depth; 0 = default limit
    Resolver       interface {
        protoregistry.MessageTypeResolver
        protoregistry.ExtensionTypeResolver
    } // For google.protobuf.Any and extensions; defaults to GlobalTypes
}
```

### Proto3 Canonical JSON Mapping

- Field names default to **lowerCamelCase** in JSON. Override with `json_name` option in `.proto` or `UseProtoNames` in Go.
- `int64`, `uint64`, `fixed64`, `sfixed64` serialize as **quoted strings** to avoid IEEE 754 precision loss.
- `bytes` fields serialize as **base64-encoded strings**.
- Enum values serialize as **string names** by default (use `UseEnumNumbers` for integers).
- `null` is accepted for any field (treated as "not present"). Serializers should not emit `null` unless for `google.protobuf.NullValue`.
- Unknown fields: the JSON parser should reject them by default. Use `DiscardUnknown` to ignore.

## Shared Schema Semantics Across Protobuf, JSON, and XML

When one domain model must be exposed over protobuf (gRPC/events), JSON (REST), and XML (legacy integrations), standardize semantics early:

| Concept | Protobuf | JSON | XML | Guidance |
|---|---|---|---|---|
| Timestamp | `google.protobuf.Timestamp` | RFC3339 string | text value or attribute | Normalize to UTC; document timezone assumptions |
| Duration | `google.protobuf.Duration` | string with `s` suffix (e.g. `"3.5s"`) | text value | Keep unit semantics explicit |
| Binary payload | `bytes` | base64 string | base64 text/CDATA | Treat as opaque; avoid accidental UTF-8 decoding |
| Enum/state | `enum` | string name (default) or number | text token | Publish allowed values and unknown-value behavior |
| Optional scalar | `optional` + presence | omitted vs `null` | missing element vs empty element | Define omission semantics per field |
| Partial update | `FieldMask` | comma path string | custom element/attribute list | Keep path grammar aligned with proto field names |

Practical pattern: keep `.proto` as canonical schema, then add explicit adapter layers for JSON and XML edge contracts rather than relying on implicit struct-tag behavior.

### Well-Known Type JSON Representations

| Proto Type | JSON Representation | Example |
|---|---|---|
| `google.protobuf.Timestamp` | RFC 3339 string | `"2024-01-15T12:30:00.000Z"` |
| `google.protobuf.Duration` | Seconds with `s` suffix | `"3.500s"` |
| `google.protobuf.Struct` | JSON object | `{"key": "value"}` |
| `google.protobuf.Value` | Any JSON primitive/object/array | `42`, `"hello"`, `null` |
| `google.protobuf.ListValue` | JSON array | `[1, 2, 3]` |
| `google.protobuf.Any` | Object with `@type` field | `{"@type": "type.googleapis.com/...", ...}` |
| `google.protobuf.FieldMask` | Comma-separated string | `"foo,bar.baz"` |
| Wrapper types (e.g., `Int32Value`) | Corresponding JSON primitive | `42`, `"hello"` |
| `google.protobuf.Empty` | Empty object | `{}` |

For `Any` containing a well-known type with special JSON mapping, the value is placed under a `"value"` key alongside `@type`.

### Usage Example

```go
import "google.golang.org/protobuf/encoding/protojson"

// Marshal with options
opts := protojson.MarshalOptions{
    Multiline:       true,
    Indent:          "  ",
    UseProtoNames:   true,   // snake_case field names
    EmitDefaultValues: true, // include zero-valued fields
}
jsonBytes, err := opts.Marshal(msg)

// Unmarshal with options
uopts := protojson.UnmarshalOptions{
    DiscardUnknown: true, // tolerate extra fields from newer schemas
}
err = uopts.Unmarshal(jsonBytes, msg)
```

## Migrating Go Structs to Protobuf: Problematic Patterns

### interface{} / any

Protobuf has no dynamic type. Solutions:

| Go Pattern | Protobuf Equivalent | Trade-off |
|---|---|---|
| `interface{}` for any JSON | `google.protobuf.Value` or `Struct` | No size reduction; round-trips JSON losslessly |
| `interface{}` for known types | `oneof` with explicit cases | Type-safe; best performance |
| `interface{}` for arbitrary protos | `google.protobuf.Any` | Requires type URL; needs resolver to unmarshal |

```protobuf
// oneof for known type sets
message Event {
  oneof payload {
    CreateEvent create = 1;
    UpdateEvent update = 2;
    DeleteEvent delete = 3;
  }
}

// google.protobuf.Value for arbitrary JSON
import "google/protobuf/struct.proto";
message Config {
  google.protobuf.Struct metadata = 1;  // map[string]any equivalent
  google.protobuf.Value  setting = 2;   // any single JSON value
}

// google.protobuf.Any for arbitrary proto messages
import "google/protobuf/any.proto";
message Envelope {
  google.protobuf.Any payload = 1;
}
```

Go usage with `structpb`:
```go
import "google.golang.org/protobuf/types/known/structpb"

val, _ := structpb.NewValue(map[string]interface{}{
    "key": "value",
    "num": 42,
})
```

**`structpb.NewValue` pitfall:** It rejects custom named types even when the underlying type matches. For example, `type customString string` passed to `structpb.NewValue` errors with `proto: invalid type`. Only exact Go primitive types (`string`, `float64`, `bool`, `nil`, `map[string]interface{}`, `[]interface{}`) are accepted.

### map[CustomType]Value

Protobuf map keys can ONLY be: `int32`, `int64`, `uint32`, `uint64`, `sint32`, `sint64`, `fixed32`, `fixed64`, `sfixed32`, `sfixed64`, `bool`, `string`.

NOT allowed as keys: `float`, `double`, `bytes`, `enum`, `message`.

```go
// Go struct with problematic map
type Data struct {
    ByIP   map[net.IP]string    // net.IP is []byte - can't be a key
    ByEnum map[MyEnum]Config    // enums can't be map keys
    ByFloat map[float64]string  // floats can't be map keys
}

// Solution: convert keys to allowed types
// map<string, string> by_ip = 1;   // use string representation of IP
// Use repeated message with enum + value fields instead of map for enum keys
```

### Deeply Nested Anonymous Structs

```go
// Go allows anonymous nested structs
type Request struct {
    Auth struct {
        Token string
        Scope struct {
            Read  bool
            Write bool
        }
    }
}

// Protobuf requires named messages
message Scope {
  bool read = 1;
  bool write = 2;
}
message Auth {
  string token = 1;
  Scope scope = 2;
}
message Request {
  Auth auth = 1;
}
```

### Pointer Semantics and Nil vs Zero Value

In proto3 without `optional`, there is no presence tracking. Zero value = not set.

```protobuf
// proto3 - no presence (cannot distinguish 0 from "not set")
message Person {
  int32 age = 1;          // age=0 is indistinguishable from unset
}

// proto3 with optional - has presence (Go generates pointer field)
message Person {
  optional int32 age = 1; // nil pointer = unset; *0 = explicitly zero
}
```

In Go, `optional` fields generate pointer types with `Has*()` and `Clear*()` methods. Message fields always have presence (nil = not set).

### time.Time and time.Duration

```go
// Go struct
type Event struct {
    CreatedAt time.Time
    TTL       time.Duration
}
```

```protobuf
import "google/protobuf/timestamp.proto";
import "google/protobuf/duration.proto";

message Event {
  google.protobuf.Timestamp created_at = 1;  // JSON: "2024-01-15T12:00:00Z"
  google.protobuf.Duration ttl = 2;          // JSON: "300s"
}
```

```go
import (
    timestamppb "google.golang.org/protobuf/types/known/timestamppb"
    durationpb  "google.golang.org/protobuf/types/known/durationpb"
)
event := &pb.Event{
    CreatedAt: timestamppb.Now(),
    Ttl:       durationpb.New(5 * time.Minute),
}
t := event.CreatedAt.AsTime()   // back to time.Time
d := event.Ttl.AsDuration()     // back to time.Duration
```

### []byte

Maps directly to `bytes` field type. Serialized as base64 in JSON.

```protobuf
message File {
  bytes content = 1;  // Go type: []byte; JSON: base64 string
}
```

### Custom JSON Marshaling

`json.Marshaler` / `json.Unmarshaler` interfaces have no protobuf equivalent. Generated proto types use `protojson` for JSON serialization. Workarounds:

- Write adapter functions that convert between your custom type and the proto message.
- Use `protoc-gen-go-json` plugin to generate standard `json.Marshaler`/`json.Unmarshaler` that delegate to `protojson`.

### Struct Tags vs Protobuf Field Naming

```go
type User struct {
    FirstName string `json:"first_name,omitempty"`
}
```

In protobuf, the field name in `.proto` defines the proto name. JSON name defaults to lowerCamelCase. Use `json_name` option to override:

```protobuf
// Default behavior:
message User {
  string first_name = 1;  // JSON: "firstName" (lowerCamelCase)
}

// Override with json_name:
message User {
  string first_name = 1 [json_name = "first_name"];  // JSON: "first_name"
}
```

Or use `UseProtoNames: true` in `MarshalOptions` to always emit snake_case.

### Embedded Structs

Protobuf has no struct embedding. Use explicit composition:

```go
// Go
type Base struct { ID string; CreatedAt time.Time }
type User struct { Base; Name string }

// Protobuf - must be explicit composition
message Base {
  string id = 1;
  google.protobuf.Timestamp created_at = 2;
}
message User {
  Base base = 1;  // no embedding, must access as user.Base.Id
  string name = 2;
}
```

### Circular References

Protobuf supports them (a message can reference itself), but they can cause infinite loops in reflection-based code and JSON serialization.

```protobuf
message TreeNode {
  string value = 1;
  repeated TreeNode children = 2;  // valid, self-referencing
}
```

### Union / Sum Types

Use `oneof`. At most one field in a `oneof` can be set at a time. Setting one clears the others.

```protobuf
message Shape {
  oneof shape {
    Circle circle = 1;
    Rectangle rectangle = 2;
    Triangle triangle = 3;
  }
}
```

### Private Fields

Protobuf generated code has only exported fields. Private fields in Go structs cannot be represented. Exported accessors can wrap internal state, but the generated struct itself has no private fields for user data.

### Custom Types (net.IP, url.URL, etc.)

Map to primitive types and convert in application code:

| Go Type | Protobuf Field | Notes |
|---|---|---|
| `net.IP` | `string` or `bytes` | String for human-readable, bytes for efficiency |
| `url.URL` | `string` | Store as string, parse in application |
| `big.Int` | `string` or `bytes` | No native big integer in protobuf |
| `uuid.UUID` | `string` or `bytes` | 16 bytes or RFC 4122 string |

### Generics

Protobuf has no generics. A `Container[T]` in Go must become separate messages or use `google.protobuf.Any`.

### omitempty Behavior Differences

Go `json:",omitempty"` skips zero values. Proto3 implicit presence does the same by default. But proto3 `optional` fields emit even zero values when explicitly set, which has no `omitempty` equivalent.

## XML and Protobuf

### prototext Format

The `encoding/prototext` package serializes protobuf to a human-readable text format (NOT XML). Used for debugging, config files, and text-based proto storage.

```go
import "google.golang.org/protobuf/encoding/prototext"

text, _ := prototext.Format(msg)
// Output: name: "Alice"  age: 30
```

### XML Schema to Proto Definitions

No official XML support in the Go protobuf library. Available tools:

| Tool | Direction | Notes |
|---|---|---|
| `entur/schema2proto` | XSD to .proto | Java-based; can modify existing proto files; supports merging |
| `chemag/xml2proto` | XML documents to proto wire | C++; works with protobuf 3.0 |
| `protosdc.org` Proto Converter | XSD to proto + other targets | Supports Kotlin, Rust, Python output too |

### Proto as Intermediate Between JSON and XML

Pattern: Define schema in `.proto`, generate code, then use separate serializers:

```
.proto definition
    |
    +-- protojson --> JSON
    +-- prototext --> text format
    +-- proto.Marshal --> binary wire format
    +-- custom code + encoding/xml --> XML
```

For XML output from proto messages, use protobuf reflection to walk fields and emit XML:

```go
import (
    "encoding/xml"
    "google.golang.org/protobuf/reflect/protoreflect"
)

func ProtoToXML(msg proto.Message) ([]byte, error) {
    // Walk msg.ProtoReflect().Range() and build XML elements
    // using field descriptors for element names
}
```

## Protobuf as Source of Truth for Multiple Formats

### Proto to JSON Schema

| Tool | JSON Schema Versions | Status |
|---|---|---|
| `pubg/protoc-gen-jsonschema` | draft-04 through 2020-12 | Active; supports K8s patterns |
| `bufbuild/protoschema-plugins` | Draft 2020-12 | Alpha; by Buf team |
| `chrusty/protoc-gen-jsonschema` | Default | Archived June 2024 |

Usage with `pubg/protoc-gen-jsonschema`:
```bash
protoc --jsonschema_out=. --jsonschema_opt=draft=2020-12 myservice.proto
```

### Proto to OpenAPI

| Tool | OpenAPI Version | Notes |
|---|---|---|
| `grpc-ecosystem/grpc-gateway` (`protoc-gen-openapiv2`) | 2.0 | Widely used with gRPC-Gateway |
| `solo-io/protoc-gen-openapi` | 3.0 | Supports `$ref`, descriptions from comments |
| `lst85/protoc-gen-openapi` | 3.0 | Converts all proto types to JSON Schema equivalents |
| `google/gnostic` | 2.0 and 3.0 | Bidirectional: OpenAPI to/from proto representation |

Reverse direction (OpenAPI to proto): `nytimes/openapi2proto` generates proto3 schemas and gRPC service definitions from OpenAPI/Swagger specs.

### Proto vs Avro vs Thrift

| Aspect | Protobuf | Avro | Thrift |
|---|---|---|---|
| Schema in payload | No (external) | Yes (self-describing) | No (external) |
| Schema evolution | Field numbers; `reserved` | Reader/writer schemas | Field IDs |
| Dynamic schemas | No | Yes (strength for ETL) | No |
| RPC framework | gRPC (separate) | No built-in | Built-in (multiple protocols) |
| Key ecosystem | gRPC, cloud-native | Kafka, Hadoop, Spark | Legacy Facebook-origin systems |

Cross-format tool: `rightlag/aptos` converts JSON Schema to Avro, Protobuf, or Thrift schemas.

### Proto as Canonical Schema Concept

Define your data model once in `.proto` files, then generate:
- Go/Java/Python structs via `protoc-gen-go` etc.
- JSON Schema via `protoc-gen-jsonschema`
- OpenAPI specs via `protoc-gen-openapi`
- gRPC services via `protoc-gen-go-grpc`
- Validation rules via `protoc-gen-validate`
- Database schemas via custom plugins

This eliminates schema drift across API docs, validation, and code.

## Common Migration Pitfalls

### Field Numbering Strategy

- Assign field numbers deliberately. Once assigned, they are permanent.
- Reserve numbers 1-15 for frequently used fields (they use 1 byte on the wire; 16-2047 use 2 bytes).
- Never reuse a deleted field's number. Use `reserved`:

```protobuf
message User {
  reserved 2, 5;                  // never reuse these numbers
  reserved "middle_name", "age";  // document what was removed
  string name = 1;
  string email = 3;
}
```

### Optional/Required Semantics

- Proto3 dropped `required` entirely (it was considered harmful for evolution).
- Proto3 `optional` adds presence tracking but is NOT the same as proto2 `required`.
- Proto2 `required` fields cause parse failure if missing; avoid in new schemas.

### Default Value Differences

| Type | Go zero value | Proto3 default | Difference |
|---|---|---|---|
| `bool` | `false` | `false` | Same |
| `int32` | `0` | `0` | Same, but proto3 omits from wire |
| `string` | `""` | `""` | Same, but proto3 omits from wire |
| `*Message` | `nil` | `nil` | Same |
| `[]T` (repeated) | `nil` | empty list | Go `nil` vs empty: proto treats both as "empty" |
| `map[K]V` | `nil` | empty map | Same as repeated |

Critical: in proto3 without `optional`, you cannot distinguish "field was explicitly set to 0" from "field was not sent." This breaks Go patterns that rely on pointer-nil checks.

### Backward Compatibility with Existing JSON APIs

When migrating an existing JSON API to use protobuf-generated types:

1. **Field name mapping**: Proto3 JSON uses lowerCamelCase by default. If your API uses snake_case, either use `json_name` on each field or set `UseProtoNames: true` globally.

2. **Unknown fields**: By default, protojson rejects unknown fields. Set `DiscardUnknown: true` to maintain backward compatibility when clients send fields you have removed.

3. **Enum representation**: Proto3 JSON uses string names by default. If your API used integers, clients sending integers will still be accepted (protojson accepts both), but your output changes from numbers to strings unless you set `UseEnumNumbers: true`.

4. **Null handling**: Proto3 JSON accepts `null` for any field (treated as default/unset). But serializers do NOT emit `null` by default. If your API contract expects `null` for absent fields, use `EmitUnpopulated: true`.

5. **Integer precision**: `int64`/`uint64` fields serialize as quoted strings in protojson. If your API previously used unquoted numbers, clients must handle both forms.

6. **Oneof evolution hazard**: Moving existing fields into a `oneof` is a breaking change. Old data with multiple fields set will lose all but one value, and which one survives depends on implementation-specific serialization order.

### Migration Checklist

1. Map each Go struct field to a proto field type. Flag problematic types (see Section 2).
2. Assign field numbers (do not auto-number; plan for future additions).
3. Add `optional` to fields where nil/zero distinction matters.
4. Use `json_name` options to match existing JSON field names.
5. Set `DiscardUnknown: true` in unmarshal options during transition.
6. Run existing JSON test fixtures through protojson round-trip to catch incompatibilities.
7. Use `proto.Equal` instead of `reflect.DeepEqual` for proto message comparison.
8. Do NOT embed proto messages in custom Go structs (can inadvertently satisfy `proto.Message` interface and cause panics).

## Migrating from gogo/protobuf

If the codebase uses `github.com/gogo/protobuf`, be aware of these incompatibilities:

| gogo Feature | Standard Equivalent | Migration Notes |
|---|---|---|
| `time.Time` fields via extension | `google.protobuf.Timestamp` | Must use `timestamppb` conversions |
| `time.Duration` fields via extension | `google.protobuf.Duration` | Must use `durationpb` conversions |
| Non-nullable struct fields | Pointer-based or Opaque API | v2 API does not support non-nullable message fields |
| Custom type extensions (`casttype`, `customtype`) | No equivalent | Write manual conversion functions |
| `gogoproto.nullable = false` | Remove; use proto3 defaults | Generated code uses value types differently |

**Key steps:**
1. Update `github.com/golang/protobuf` to at least v1.4 for interop
2. Regenerate all `.pb.go` files with standard `protoc-gen-go`
3. Replace gogo-specific struct access patterns with standard getter/setter calls
4. Replace `time.Time` direct usage with `timestamppb` conversions
5. Remove gogo-specific proto options from `.proto` files
6. Update all `reflect.DeepEqual` calls on proto messages to `proto.Equal`
