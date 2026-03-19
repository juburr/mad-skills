# Rust Performance Reference

Detailed code examples, tooling setup, and implementation patterns. Loaded on demand from `SKILL.md`.

## Alternative Allocator Setup

### mimalloc

```toml
# Cargo.toml
[dependencies]
mimalloc = "0.1"
```

```rust
#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;
```

### jemalloc

```toml
# Cargo.toml
[dependencies]
tikv-jemallocator = "0.6"
```

```rust
#[global_allocator]
static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;
```

For additional throughput on Linux, enable transparent huge pages. With `tikv-jemallocator`, the env var may need a prefix because jemalloc is built with `--with-jemalloc-prefix=_rjem_` by default:

```bash
# Try the standard name first:
MALLOC_CONF="thp:always,metadata_thp:always" ./my_binary
# If that has no effect, use the prefixed name:
_RJEM_MALLOC_CONF="thp:always,metadata_thp:always" ./my_binary
```

**Caveat**: jemalloc can be incompatible with unusual page sizes on some targets (e.g., some AArch64 Linux builds). Validate on your deployment architecture.

### Choosing Between Allocators

- **mimalloc** tends to win in benchmarks for short-lived allocations and multi-threaded workloads. Worth benchmarking on musl targets where the default allocator can be significantly slower (up to 7x reported in some workloads).
- **jemalloc** excels for long-running servers with complex allocation patterns and fragmentation concerns. Better memory return behavior under sustained load.
- Always benchmark both against the system allocator for your specific workload. Allocator performance is highly workload-dependent.

## Arena Allocators

Use arenas when allocating many short-lived objects with similar lifetimes (AST nodes, per-request state, ECS components).

### bumpalo

```toml
[dependencies]
bumpalo = "3"
```

```rust
use bumpalo::Bump;

let arena = Bump::new();
let val = arena.alloc(42u64);        // allocated in arena
let s = arena.alloc_str("hello");    // string in arena
// All arena memory freed when `arena` is dropped
```

Objects allocated in the arena are freed together on drop. Individual deallocation is not possible. This makes allocation extremely fast (bump pointer) but requires that all objects share a lifetime.

### typed-arena

```rust
use typed_arena::Arena;

let arena = Arena::new();
let node = arena.alloc(AstNode { ... });
// All nodes freed when arena is dropped
```

Simpler API than bumpalo but restricted to a single type per arena.

## String Interning

For datasets with many duplicate strings, interning stores each unique string once and returns lightweight handles.

### lasso

```toml
[dependencies]
lasso = "0.7"
```

```rust
use lasso::{Rodeo, Spur};

let mut rodeo = Rodeo::default();
let key: Spur = rodeo.get_or_intern("hello");
let key2: Spur = rodeo.get_or_intern("hello");
assert_eq!(key, key2);  // same handle; O(1) equality
let resolved: &str = rodeo.resolve(&key);
```

- `Rodeo` for single-threaded, `ThreadedRodeo` for multi-threaded
- `Spur` is a `u32` handle -- 4 bytes vs 24 bytes for `String`
- Equality and hashing on handles is O(1) regardless of string length

Use interning when profiling shows many duplicate strings consuming memory, or when string equality checks are a bottleneck.

## Fast Formatting and Parsing

In hot paths, `format!()` and `to_string()` both allocate a new `String`. For numeric formatting and parsing, specialized crates avoid the overhead of the generic `fmt` machinery:

- **`itoa`** -- Fast integer-to-string formatting into a caller-provided buffer.
- **`ryu`** -- Fast float-to-string formatting (used internally by `serde_json`).
- **`lexical-core`** -- Fast string-to-number parsing for integers and floats.

```rust
// itoa: format integer without allocating a String
let mut buf = itoa::Buffer::new();
let s: &str = buf.format(12345u64);  // writes into stack buffer

// ryu: format float without allocating
let mut buf = ryu::Buffer::new();
let s: &str = buf.format(3.14159f64);
```

Use these when profiling shows formatting or parsing as a bottleneck in logging, serialization, or text processing.

## Zero-Copy Patterns

### bytes Crate

`Bytes` (from `tokio-rs/bytes`) provides reference-counted byte buffers for networking:

```rust
use bytes::{Bytes, BytesMut, BufMut};

let mut buf = BytesMut::with_capacity(1024);
buf.put_slice(b"hello world");

let frozen: Bytes = buf.freeze();
let slice: Bytes = frozen.slice(0..5);  // O(1), no copy
```

- Multiple `Bytes` handles share the same underlying memory
- Like `Vec::with_capacity`, `BytesMut::with_capacity` reserves space without initializing it. The key advantage over `Vec<u8>` is reference-counted shared ownership and O(1) slicing.
- Slicing is O(1) -- creates a new handle pointing into the same allocation

### Memory-Mapped Files

```toml
[dependencies]
memmap2 = "0.9"
```

```rust
use memmap2::Mmap;
use std::fs::File;

let file = File::open("large_data.bin")?;
let mmap = unsafe { Mmap::map(&file)? };
let data: &[u8] = &mmap;  // zero-copy access to file contents
```

- Up to 7x faster than buffered file reads on SSDs
- OS manages page caching; only accessed pages are loaded into physical memory
- Best for: databases, search indexes, large read-only datasets
- `unsafe` is required because the file could be modified externally while mapped

### Serde Zero-Copy Deserialization

Serde supports borrowing `&str` and `&[u8]` directly from the input buffer, avoiding string allocation when possible. Use `Cow<'a, str>` for the most robust pattern -- it borrows when the input is clean and allocates only when the deserializer must transform the data (e.g., unescaping JSON escape sequences like `\n` or `\"`):

```rust
use serde::Deserialize;
use std::borrow::Cow;

#[derive(Deserialize)]
struct Record<'a> {
    #[serde(borrow)]
    name: Cow<'a, str>,      // borrows when no escapes; allocates only when unescaping
    #[serde(borrow)]
    tags: Vec<Cow<'a, str>>, // Vec itself allocates, but string data may borrow
}

let json = r#"{"name": "alice", "tags": ["admin", "user"]}"#;
let record: Record<'_> = serde_json::from_str(json)?;
// record.name borrows from json when no escape sequences are present
```

**Caveats**:
- `&'a str` fields fail deserialization (not just allocate) when the source string contains escape sequences. `Cow<'a, str>` handles both cases gracefully.
- Collection fields like `Vec<Cow<'a, str>>` still allocate the `Vec` itself; only the string data may be zero-copy.
- The deserialized struct borrows from the input, so the input must outlive the struct.
- Only works with formats that store strings inline (JSON, TOML).

### rkyv (Zero-Copy Archive)

For maximum deserialization performance, `rkyv` can access archived data directly from a byte buffer with no deserialization step:

```toml
[dependencies]
rkyv = "0.8"
```

```rust
use rkyv::{Archive, Serialize, Deserialize, rancor::Error};

#[derive(Archive, Serialize, Deserialize)]
struct Config {
    name: String,
    values: Vec<u64>,
}

// Serialize
let bytes = rkyv::to_bytes::<Error>(&config)?;

// Zero-copy access -- no deserialization
let archived = rkyv::access::<ArchivedConfig, Error>(&bytes)?;
println!("{}", archived.name);  // accessed directly from bytes
```

In the project's own benchmarks, rkyv outperforms bincode, flatbuffers, postcard, and serde_json for both serialization and deserialization. Real-world results depend on data shape and access patterns -- benchmark with your data. Use when deserialization is a profiled bottleneck and you control both the writer and reader.

## SIMD and Auto-Vectorization

### State of SIMD in Rust

- **`std::simd` (portable SIMD)** remains nightly-only. Stabilization is blocked by mask type semantics and Swizzle API design.
- **`std::arch`** provides stable access to platform-specific intrinsics (`_mm256_add_ps`, etc.). Requires `unsafe` and manual feature detection.
- **`wide` crate** provides portable SIMD types on stable Rust. Less optimal codegen than `std::simd` but works today.

### Helping Auto-Vectorization

LLVM auto-vectorizes loops when it can prove safety. Common blockers and fixes:

1. **Bounds checks prevent vectorization.** Use iterators instead of indexed access.
2. **Use `chunks_exact()` / `chunks_exact_mut()`** instead of `chunks()`. The exact variant tells LLVM the remainder is handled separately, enabling vectorization of the main loop body.
3. **Enable wider SIMD** (homogeneous deployment only): `RUSTFLAGS="-C target-feature=+avx2,+fma"` emits AVX2/FMA instructions unconditionally. **This will crash (SIGILL) on CPUs without those features.** Only use when you control the deployment target. For portable binaries, use runtime feature detection (`is_x86_feature_detected!`) with `#[target_feature(enable = "avx2")]` on specific functions instead.
4. **Avoid early returns** in the inner loop body -- they prevent vectorization.
5. **Keep loop bodies simple** -- function calls (unless inlined) prevent vectorization.

### Verifying Vectorization

```bash
cargo install cargo-show-asm
cargo asm --lib my_crate::hot_function
```

Look for SIMD instructions (`vmovaps`, `vaddps`, `vfmadd`) in the output. If you see scalar instructions (`movss`, `addss`) in a loop that should vectorize, check for the blockers above.

Alternatively, use Compiler Explorer (godbolt.org) for small snippets -- paste the function and select the Rust nightly compiler with `-O` optimization.

### SoA for SIMD

Structure-of-Arrays layout naturally aligns with SIMD processing:

```rust
// Process all X coordinates with SIMD (auto-vectorizes well)
for (x, vx) in positions_x.iter_mut().zip(velocities_x.iter()) {
    *x += vx * dt;
}

// Process all Y coordinates with SIMD
for (y, vy) in positions_y.iter_mut().zip(velocities_y.iter()) {
    *y += vy * dt;
}
```

This pattern gives the compiler contiguous, aligned memory to vectorize over -- much better than iterating an AoS `Vec<Particle>` where fields are interleaved.

## Compile-Time Computation

### const fn

Rust 1.83+ (late 2024) significantly expanded `const fn` on stable:
- Mutable references in const contexts
- Mutable raw pointers and interior mutability (`UnsafeCell`)
- References to static items

Use `const fn` to move computation from runtime to compile time:

```rust
const fn compute_lookup_table() -> [u8; 256] {
    let mut table = [0u8; 256];
    let mut i = 0;
    while i < 256 {
        table[i] = (i as u8).wrapping_mul(37);
        i += 1;
    }
    table
}

const LOOKUP: [u8; 256] = compute_lookup_table();
```

**Limitation**: `const fn` on stable cannot invoke trait methods. Const traits are an active area of development (tracked in the Rust project goals) but have no guaranteed stabilization date. Check the `const_trait_impl` tracking issue for current status.

### const Generics

Prefer `[T; N]` over `Vec<T>` when sizes are compile-time-known. This eliminates heap allocation and enables stack allocation:

```rust
fn process<const N: usize>(data: &[f64; N]) -> [f64; N] {
    let mut result = [0.0; N];
    for i in 0..N {
        result[i] = data[i] * 2.0;
    }
    result
}
```

Generic const expressions (`where [(); N + 1]:`) remain nightly-only.

### Build Scripts for Code Generation

`build.rs` can generate Rust source at compile time for:
- Pre-computed lookup tables too complex for `const fn`
- Parser code generated from grammars
- Embedded binary resources (`include_bytes!`)
- FFI bindings (via `bindgen`)

```rust
// build.rs
fn main() {
    let out_dir = std::env::var("OUT_DIR").unwrap();
    let path = std::path::Path::new(&out_dir).join("generated.rs");
    std::fs::write(&path, generate_table()).unwrap();
    // Note: cargo::KEY=VALUE syntax requires Rust 1.77+; use cargo:KEY=VALUE for older toolchains
    println!("cargo:rerun-if-changed=build.rs");
}
```

```rust
// src/lib.rs
include!(concat!(env!("OUT_DIR"), "/generated.rs"));
```

## Detailed Profiling Setup

### DHAT Heap Profiling with dhat-rs

```toml
[dependencies]
dhat = "0.3"

[features]
dhat-heap = []  # enable for profiling runs only
```

```rust
#[cfg(feature = "dhat-heap")]
#[global_allocator]
static ALLOC: dhat::Alloc = dhat::Alloc;

fn main() {
    #[cfg(feature = "dhat-heap")]
    let _profiler = dhat::Profiler::new_heap();

    // ... application code ...
}
```

```bash
cargo run --release --features dhat-heap
# Produces dhat-heap.json; open it in https://nnethercote.github.io/dh_view/dh_view.html
```

dhat-rs identifies:
- Hot allocation sites (where most allocations happen)
- Short-lived allocations (allocated and freed quickly -- candidates for stack or arena)
- Peak memory contributors

**Note**: Unlike Valgrind DHAT, the dhat-rs crate does **not** profile copy functions (`memcpy`, `strcpy`). For copy hotspots, use `perf`, `samply`, or Cachegrind/Callgrind instead.

### Criterion Benchmarking

```toml
[dev-dependencies]
criterion = { version = "0.5", features = ["html_reports"] }

[[bench]]
name = "my_benchmark"
harness = false
```

```rust
// benches/my_benchmark.rs
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_hot_function(c: &mut Criterion) {
    let data = setup_test_data();
    c.bench_function("hot_function", |b| {
        b.iter(|| hot_function(black_box(&data)))
    });
}

criterion_group!(benches, bench_hot_function);
criterion_main!(benches);
```

```bash
cargo bench                              # run all benchmarks
cargo bench -- hot_function              # run specific benchmark
cargo bench -- --save-baseline before    # save baseline
# ... make changes ...
cargo bench -- --baseline before         # compare against baseline
```

### iai-callgrind for CI

```toml
[dev-dependencies]
iai-callgrind = "0.14"

[[bench]]
name = "my_iai_bench"
harness = false
```

```rust
use iai_callgrind::{library_benchmark, library_benchmark_group, main};

#[library_benchmark]
fn bench_hot_function() -> u64 {
    hot_function(&setup_data())
}

library_benchmark_group!(name = my_group; benchmarks = bench_hot_function);
main!(library_benchmark_groups = my_group);
```

Results are deterministic (instruction counts, not wall-clock time), making them suitable for CI regression detection.

## Iterator Performance Patterns

### Iterators vs Manual Loops

Rust iterators compile to the same assembly as hand-written loops via monomorphization and inlining. Iterator chains can be faster because they naturally avoid bounds checks and enable loop fusion.

```rust
// These typically produce identical assembly:
let sum: u64 = data.iter().map(|x| x * 2).sum();

let mut sum: u64 = 0;
for x in data {
    sum += x * 2;
}
```

Prefer iterators -- they are idiomatic, composable, and often easier for LLVM to optimize.

### Avoiding Intermediate Allocations

```rust
// BAD: two allocations (collect then collect)
let result: Vec<u64> = data.iter()
    .filter(|x| **x > 10)
    .collect::<Vec<_>>()
    .iter()
    .map(|x| *x * 2)
    .collect();

// GOOD: single allocation, fused chain
let result: Vec<u64> = data.iter()
    .filter(|x| **x > 10)
    .map(|x| x * 2)
    .collect();
```

### collect with capacity

When `collect()` is unavoidable and you know the output size:

```rust
let output: Vec<_> = {
    let mut v = Vec::with_capacity(expected_size);
    v.extend(data.iter().filter(|x| x.is_valid()).map(|x| x.transform()));
    v
};
```

This avoids the geometric reallocation that `collect()` performs when it cannot predict the size from the iterator's `size_hint()`.

## Dynamic Dispatch Alternatives

### Enum Dispatch

When the set of types is closed (known at compile time), use an enum instead of `Box<dyn Trait>`:

```rust
// SLOW: heap allocation + vtable indirection per call
fn process(handler: Box<dyn Handler>) {
    handler.handle();
}

// FAST: no allocation, direct jump table
enum AnyHandler {
    Logging(LoggingHandler),
    Metrics(MetricsHandler),
    Auth(AuthHandler),
}

impl AnyHandler {
    fn handle(&self) {
        match self {
            Self::Logging(h) => h.handle(),
            Self::Metrics(h) => h.handle(),
            Self::Auth(h) => h.handle(),
        }
    }
}
```

Enum dispatch is a direct jump (or even inlined), while `dyn Trait` is an indirect call through a vtable pointer that prevents inlining and branch prediction.

### On-Stack Dynamic Dispatch

When you need `dyn Trait` but can avoid the `Box` allocation:

```rust
fn process(use_fast: bool) {
    let fast = FastImpl;
    let slow = SlowImpl;
    let handler: &dyn Handler = if use_fast { &fast } else { &slow };
    handler.handle();  // dynamic dispatch, no heap allocation
}
```

Both implementations live on the stack. Only the vtable pointer is used for dispatch.

## Tokio CPU/IO Separation Pattern

When offloading CPU-bound work from the async executor, bound concurrency:

```rust
use std::sync::Arc;
use tokio::sync::Semaphore;

let sem = Arc::new(Semaphore::new(num_cpus::get()));

for job in jobs {
    let permit = sem.clone().acquire_owned().await.unwrap();
    tokio::task::spawn_blocking(move || {
        let result = expensive_computation(&job);
        drop(permit);  // release when done
        result
    });
}
```

Without the semaphore, `spawn_blocking` will spawn up to its very large thread limit, potentially overwhelming the system. For sustained CPU parallelism, prefer a dedicated Rayon pool over `spawn_blocking`.

## Crossbeam Channels

`crossbeam-channel` is faster than `std::sync::mpsc` and supports `select!` across multiple channels:

```rust
use crossbeam_channel::{bounded, select};

let (tx1, rx1) = bounded(100);
let (tx2, rx2) = bounded(100);

select! {
    recv(rx1) -> msg => handle_type1(msg.unwrap()),
    recv(rx2) -> msg => handle_type2(msg.unwrap()),
}
```

Use `bounded` channels (not `unbounded`) in production to enforce backpressure and prevent memory exhaustion.
