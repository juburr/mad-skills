# Static review checklist

Use this when the repository cannot be built or profiled locally. Mark findings as **hypotheses** until measured.

## 1) Algorithmic shape

- Is there accidental quadratic behavior?
- Is data re-parsed, re-sorted, or re-hashed repeatedly?
- Are lookups repeated inside loops when one precomputation would do?
- Is the algorithm doing expensive work for data that will later be discarded?

## 2) Data structures

- Are hot paths using node-based containers where flat storage would likely work?
- Are there deep pointer chains in traversal-heavy code?
- Is `std::unordered_map`/`std::unordered_set` used in a hot path where `absl::flat_hash_map`, `boost::unordered_flat_map`, or `ankerl::unordered_dense::map` would avoid node allocation?
- Are tiny objects heap-allocated one-by-one?
- Is `std::vector<bool>` used where `std::vector<std::uint8_t>` or `std::bitset` would be safer/faster?

## 3) Copies and ownership

- Are strings or buffers copied when a non-owning view would suffice?
- Are temporary `std::string` or `std::vector` objects created in inner loops?
- Are values passed by value unnecessarily when they are large?
- Are there conversions that allocate repeatedly?

## 4) Allocation churn

- Are containers grown repeatedly without `reserve`?
- Are request-scoped temporaries allocated from the general heap instead of a reusable buffer or arena?
- Are logging/formatting paths allocating on every hot operation?
- Does the code allocate on a critical branch?

## 5) Locality

- Are large structs copied or scanned when only a few fields are needed?
- Can hot/cold field splitting shrink the hot working set?
- Would SoA improve kernels that touch only selected fields?
- Are indices into contiguous storage feasible?

## 6) Concurrency

- Are there shared counters or queues updated on every iteration?
- Is a mutex taken per item?
- Could thread-local accumulation or sharding remove shared writes?
- Are per-thread fields likely packed onto the same cache line?
- Is `std::pmr::monotonic_buffer_resource` shared across threads (it is **not** thread-safe — must be `synchronized_pool_resource`)?
- Is `std::hardware_destructive_interference_size` used in a public header (ABI hazard — see memory-layout reference)?

## 7) Code generation blockers

- Is aliasing ambiguity preventing vectorization?
- Are there unpredictable branches in tight loops?
- Is the loop body too opaque for the optimizer because of abstraction or side effects?
- Are tiny virtual calls sitting in the hottest loop?

## 8) Build configuration

- Is the project obviously benchmarking Debug builds?
- Is the profiler build missing symbols?
- Would frame pointers help the profiling workflow? (Recall upstream GCC/Clang still default to omitting them on `-O1+`.)
- Would PGO/LTO be plausible only after source-level fixes?
- Is `RelWithDebInfo` being treated as `-O3` when it actually defaults to `-O2 -g -DNDEBUG`?
- Is `-march=native` baked into a portable release build?
- Would BOLT or AutoFDO/CSSPGO add value (large frontend-bound binary, production profile available)?

## Review output format

When you cannot run code, report like this:

```text
Measured status: not measured locally
Top hypotheses:
1. ...
2. ...
3. ...

Why I think these are high leverage:
- ...
- ...

Lowest-risk first changes:
- ...
- ...

What to measure next:
- ...
```
