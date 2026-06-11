# C++ language-level performance patterns

Source-visible patterns where cost is predictable from the code alone — the core material for static performance review. Treat findings as hypotheses until measured; pair with `review-checklist.md`.

## Moves and return values

### `noexcept` move constructors
Signal: a type stored in `std::vector` (or any reallocating container) whose move constructor is not `noexcept` — often because a user-declared copy operation, move operation, or destructor suppressed the implicit moves (rule of zero/five).
Cost: `std::vector` growth uses `std::move_if_noexcept`; a potentially-throwing move silently degrades every reallocation to element-wise copies.
Action: make moves `noexcept` (or follow the rule of zero so the compiler generates them) and pin it with a `static_assert`.

```cpp
// Before: declaring ~Widget() suppresses the implicit move ctor; vector copies on growth
struct Widget { std::string name; ~Widget() { log(name); } };

// After: defaulted noexcept moves restored alongside the destructor
struct Widget {
  std::string name;
  Widget(Widget&&) noexcept = default;
  Widget& operator=(Widget&&) noexcept = default;
  Widget(const Widget&) = default;
  Widget& operator=(const Widget&) = default;
  ~Widget() { log(name); }
};
static_assert(std::is_nothrow_move_constructible_v<Widget>);
```

Cheap audit: drop the `static_assert` next to any type that lives in a growing `std::vector`. It costs nothing at runtime and turns a silent pessimization into a compile error.

### RVO / NRVO and `return std::move(local)`
Signal: `return std::move(local);` where `local` is a local variable of the return type.
Cost: it blocks NRVO and forces a move where the compiler could construct in place — a pessimization (clang warns via `-Wpessimizing-move` / `-Wmove`).
Action: write `return local;` — the compiler elides the copy, or treats `local` as an rvalue and moves it automatically.

```cpp
// Before: forces a move, blocks NRVO
std::vector<int> f() { std::vector<int> v = build(); return std::move(v); }

// After: NRVO elides entirely (move is the automatic fallback)
std::vector<int> f() { std::vector<int> v = build(); return v; }
```

Two cases that do **not** get NRVO: returning a *member* (decide explicitly between copy and `std::move`) and returning a *function parameter* — but a by-value parameter is moved implicitly by `return param;` (C++11), so the explicit `std::move(param)` is merely redundant (clang `-Wredundant-move`), not needed.

### Sink parameters
Signal: a constructor/setter takes `const T&` and copies into a member, or the codebase maintains `const T&` / `T&&` overload pairs for the same operation.
Cost: `const T&` + member assignment always copies, even when the caller passed a temporary; overload pairs duplicate code combinatorially.
Action: take the parameter by value and `std::move` it into place — one copy for lvalue callers, one move for rvalue callers, no overload pair.

### `emplace_back` vs `push_back`
Signal: `push_back(T(args...))` constructing a temporary, or `emplace_back` used where a plain copy/move is intended.
Cost: the temporary costs one extra move (often cheap); the sharper risk is `emplace_back(new T)` into a smart-pointer container, which leaks if the container's allocation throws before ownership is taken.
Action: use `emplace_back(args...)` to construct in place from constructor arguments; keep `push_back(x)` for copying/moving an existing object (same cost, clearer intent). Never pass a raw `new` expression into emplace.

## Indirection costs

### `std::shared_ptr`
Signal: hot paths copy `shared_ptr` by value — parameters, loop bodies, lambda captures — without sharing or extending ownership.
Cost: every copy/destroy is an atomic RMW on the refcount; under multi-thread contention the control block's cache line bounces between cores.
Action: pass `const std::shared_ptr<T>&`, `T&`, or `T*` for non-owning access; copy only at genuine ownership-transfer points. Create with `std::make_shared` so object and control block share one allocation.

### `std::function`
Signal: `std::function` parameters or members on hot call paths, especially with large captures.
Cost: type erasure means an indirect call (no inlining) plus a heap allocation when the callable exceeds the implementation's small-buffer size.
Action: in hot paths take a template / `auto&&` callable parameter or pass the lambda directly to the algorithm; for non-owning callable parameters use `std::function_ref` (C++26) or a third-party `function_ref`. Reserve `std::function` for stored, type-erased callbacks off the hot path.

### Virtual dispatch
Signal: virtual calls in inner loops; interfaces with one production implementation; closed type sets dispatched through inheritance.
Cost: the indirect call itself is minor on modern predictors — the dominant loss is missed inlining and the optimizations inlining would unlock.
Action: mark classes/methods `final` where the hierarchy is closed (enables compiler devirtualization); LTO + PGO add speculative devirtualization of hot call sites; for closed sets consider `std::variant` + `std::visit` or CRTP. Hoist the dispatch out of the loop when the dynamic type is loop-invariant.

## `std::string`

- SSO: short strings don't allocate — capacity is 15 chars (libstdc++, MSVC) or 22 (libc++). Copies at or below that are cheap; copy-avoidance matters above it.
- `reserve()` before concatenation/append loops; each growth past capacity reallocates and copies the whole string.
- Prefer `+=` chains (append into existing capacity) over `a + b + c` (each `+` materializes a temporary).
- Take `std::string_view` for read-only parameters; flag `c_str()`-to-`std::string` round trips and `std::string(sv)` conversions that re-allocate what the caller already owned.

## Exceptions

Signal: exceptions thrown on expected, frequent paths — parse failures, lookup misses, loop exits.
Cost: the happy path is essentially free (table-based unwinding adds no executed instructions to non-throwing code, only binary size), but an actual throw costs on the order of microseconds — unwinder invocation plus RTTI handler matching — thousands of times a plain return.
Action: keep exceptions for exceptional conditions; use return codes, `std::optional`, or `std::expected` for frequent failures. Mark non-throwing functions `noexcept`: smaller unwind tables, sometimes better codegen, and it feeds the vector-move optimization above.

## Stream and formatting I/O

- `std::ios::sync_with_stdio(false)` when the program does not mix C stdio and C++ streams on the same stream — synchronized mode routes every standard-stream operation (`cin`/`cout`/`cerr`/`clog`) through C stdio; `fstream`/`stringstream` are unaffected.
- `'\n'` instead of `std::endl` — `endl` writes a newline **and flushes**; in a loop that is one flush per line.
- Read large files in blocks (`istream::read`, `fread`, or memory-mapping) rather than char-by-char or per-line `getline` in tight loops.
- `std::format` / fmt beats `ostringstream` for formatting — no stream state, locale, or virtual sentry machinery per operation.

## Quick checks (one-liners)

- `[[likely]]` / `[[unlikely]]` / `__builtin_expect`: block layout only, and only for measured >95% biased branches — see the branch guidance in `SKILL.md`.
- `[[gnu::noinline]]` / `[[msvc::noinline]]` (and `always_inline` / `__forceinline`): bisection tools for inlining and code-layout experiments; the plain `inline` keyword is not an inlining hint that matters.
- `constexpr` / `consteval`: move table generation and invariant computation to compile time instead of startup or per-call work.
- `std::bitset` / word-wise bit ops over `bool` arrays for masks and set membership — 8× denser, enables word-at-a-time operations (and sidesteps the `std::vector<bool>` trap; see memory-layout reference).

## Static review triggers

When reading code without running it, flag:

- user-declared destructor or copy operations on a vector-element type with no defaulted `noexcept` moves
- `return std::move(local);` on a local of the return type
- `shared_ptr` taken by value in functions that never store or extend ownership
- `std::function` in a per-item callback position inside a hot loop
- virtual calls in inner loops with no `final`, variant, or hoisting consideration
- `a + b + c` string chains and append loops with no `reserve`
- `throw` used for expected outcomes (not-found, parse failure, end-of-input)
- `std::endl` inside loops; `getline`/per-char reads over large inputs; missing `sync_with_stdio(false)` in stream-heavy C++-only tools
