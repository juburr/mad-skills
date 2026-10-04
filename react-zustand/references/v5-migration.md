# Migrating from Zustand v4 to v5

Zustand v5 is a cleanup release — no new features, just removal of deprecated APIs and modernized defaults. Migration from v4 should be smooth. Update to the latest v4 first (v4.5.7) to surface deprecation warnings, then upgrade straight to the latest v5.0.x (v5.0.15 at the time of writing) rather than v5.0.0 — later patch releases fix persist races, devtools typing, and React Native module resolution.

## Requirements

| Dependency | v4 Minimum | v5 Minimum |
|---|---|---|
| React | 16.8 | **18** (optional peer — not needed for vanilla-only use) |
| TypeScript | 3.4 (downlevel types) | **4.5** |
| `use-sync-external-store` | regular dependency | **peer dependency** (only if using `zustand/traditional`) |
| React Native 0.79+ | 4.5.7 | **5.0.4** (earlier v5 builds hit `import.meta` errors under Hermes) |

Install `use-sync-external-store` as a peer dependency only if you use `createWithEqualityFn` or `useStoreWithEqualityFn` from `zustand/traditional`. If you only use `create` from `zustand`, it is not needed — v5 uses React 18's native `useSyncExternalStore`.

## Breaking Changes

### 1. Default Exports Removed

v5 drops all default exports. Use named imports.

```ts
// v4 (deprecated default export)
import create from 'zustand'

// v5
import { create } from 'zustand'
```

This applies to all entry points. If your codebase used `import create from 'zustand'`, switch to `import { create } from 'zustand'`.

### 2. Custom Equality Function Removed from `create`

In v4, the hook returned by `create` accepted an optional equality function as its second argument (`useStore(selector, shallow)`, deprecated since v4.4). In v5, hooks from `create` always compare selector output with `Object.is` — matching how React's `useState` works. The equality function parameter is gone.

**Migration Option A — `createWithEqualityFn` (drop-in replacement):**

```ts
// v4
import { create } from 'zustand'
import { shallow } from 'zustand/shallow'

const useStore = create(myStateCreator)
const value = useStore(selector, shallow)

// v5
import { createWithEqualityFn as create } from 'zustand/traditional'
import { shallow } from 'zustand/shallow'

const useStore = create(myStateCreator, Object.is)
const value = useStore(selector, shallow)
```

Note: `createWithEqualityFn` requires `use-sync-external-store` as a peer dependency. Pass `Object.is` as the default equality function (second argument to `createWithEqualityFn`) to preserve v4 behavior for selectors that do not specify their own.

**Migration Option B — `useShallow` (recommended for new code):**

Wrap selectors that return new objects or arrays with `useShallow` instead of passing an equality function.

```ts
// v4
const { nuts, honey } = useStore(
  (s) => ({ nuts: s.nuts, honey: s.honey }),
  shallow,
)

// v5
import { useShallow } from 'zustand/react/shallow'

const { nuts, honey } = useStore(
  useShallow((s) => ({ nuts: s.nuts, honey: s.honey })),
)
```

**When to use which:**

| Scenario | Approach |
|---|---|
| Large codebase, many `shallow` call sites | `createWithEqualityFn` — minimal diff |
| New code or small number of selectors | `useShallow` — no extra peer dependency |
| Deep equality needed | `createWithEqualityFn` with a deep-equal function |

### 3. Unstable Selectors Now Cause Infinite Loops

In v4, a selector returning a new object reference on every call (e.g., `(s) => ({ a: s.a, b: s.b })`) caused unnecessary re-renders but usually worked, because v4 memoized selections through `useSyncExternalStoreWithSelector`. v5 passes `selector(getState())` to React's native `useSyncExternalStore` as the snapshot, so a new reference on every call looks like a constantly changing store and can trigger "Maximum update depth exceeded".

Fix by applying `useShallow` or selecting atomic values:

```ts
// Breaks in v5 — new object reference every call
const { a, b } = useStore((s) => ({ a: s.a, b: s.b }))

// Fix: useShallow
import { useShallow } from 'zustand/react/shallow'
const { a, b } = useStore(useShallow((s) => ({ a: s.a, b: s.b })))

// Fix: atomic selectors (no wrapper needed)
const a = useStore((s) => s.a)
const b = useStore((s) => s.b)
```

Inline fallbacks create new references too:

```ts
// Breaks in v5 — new function/array on every call when the value is missing
const action = useStore((s) => s.action ?? (() => {}))
const items = useStore((s) => s.items ?? [])

// Fix: hoist fallbacks to module-level constants
const NOOP = () => {}
const EMPTY: Item[] = []
const action = useStore((s) => s.action ?? NOOP)
const items = useStore((s) => s.items ?? EMPTY)
```

### 4. Stricter `setState` with `replace` Flag

When calling `setState` with the replace flag set to `true`, v5 requires a **complete** state object. Passing a partial or empty object is a type error.

```ts
// v4 — allowed but produced invalid state
store.setState({}, true)

// v5 — type error; must provide complete state
store.setState({ count: 0, name: '' }, true)
```

If you are not using the `replace` flag (`setState(partial)` or `setState(partial, false)`), no change is needed.

A flag computed at runtime (`boolean`) matches neither overload. Cast the argument tuple instead of using `as any`:

```ts
const args = [{ count: 0, name: '' }, shouldReplace] as Parameters<typeof store.setState>
store.setState(...args)
```

### 5. `destroy` Method Removed

The `destroy()` method on the store API was deprecated in v4 and is removed in v5. Zustand stores with no active subscriptions are garbage collected automatically.

```ts
// v4 (deprecated)
useStore.destroy()

// v5 — no replacement needed
// Stores are garbage collected when unreferenced.
// To unsubscribe a specific listener, use the unsubscribe function returned by subscribe().
const unsub = useStore.subscribe(listener)
unsub() // clean up
```

### 6. Persist Middleware No Longer Writes Initial State

In v4 (prior to v4.5.5), the `persist` middleware wrote the initial state to storage during store creation. In v5, this behavior is removed — the store only writes to storage when `setState` is called.

If your application depends on the initial state being present in storage before any user interaction (e.g., a random seed or server-provided default), explicitly call `setState` after store creation:

```ts
const useStore = create(
  persist(
    (set) => ({
      seed: Math.random(),
    }),
    { name: 'my-store' },
  ),
)

// Explicitly persist initial state if needed
useStore.setState(useStore.getState())
```

### 7. Use `getInitialState` for Resets

`getInitialState()` was added in v4.5.0, so it is already available once you are on the latest v4. It returns the state produced by the initializer and never changes (on persisted stores: the defaults, not hydrated values). Prefer it over hand-maintained `initialState` constants for store resets:

```ts
const useStore = create<State & Actions>()((set, get, store) => ({
  count: 0,
  name: '',
  reset: () => set(store.getInitialState()),
}))

// Or externally:
useStore.setState(useStore.getInitialState(), true)
```

This is particularly useful for test cleanup — reset all stores to initial state between tests.

### 8. Module System Changes

- **UMD and SystemJS builds dropped.** Use ESM or CJS.
- **ES5 output dropped.** v5 targets modern JavaScript. If you need ES5, transpile `zustand` in your build pipeline.
- **Entry points reorganized** in `package.json` `exports` field. Direct deep imports into internal files may break — use only the documented entry points.

## Import Path Reference

All documented v5 import paths:

```ts
// Core
import { create } from 'zustand'
import { createStore } from 'zustand/vanilla' // also exported from 'zustand'
import { useStore } from 'zustand'
import type { StateCreator, StoreApi, UseBoundStore, ExtractState } from 'zustand' // ExtractState: v5.0.3+

// Traditional (equality function support)
import { createWithEqualityFn } from 'zustand/traditional'
import { useStoreWithEqualityFn } from 'zustand/traditional'

// Shallow comparison
import { useShallow } from 'zustand/react/shallow'  // React hook
import { shallow } from 'zustand/shallow'            // plain comparison function

// Middleware
import { devtools, persist, subscribeWithSelector, combine, redux } from 'zustand/middleware'
import { createJSONStorage } from 'zustand/middleware'
import { unstable_ssrSafe } from 'zustand/middleware' // experimental, v5.0.9+
import { immer } from 'zustand/middleware/immer'
```

`useShallow` is also re-exported from `zustand/shallow` for convenience. Both `zustand/react/shallow` and `zustand/shallow` work.

Paths such as `zustand/middleware/devtools` or `zustand/middleware/persist` ship only `.d.ts` files: they type-check but fail at runtime. Import those middlewares from `zustand/middleware`.

## Store API Surface (v5)

```ts
// React store (from create)
useStore(selector)              // React hook
useStore.getState()             // get current state
useStore.setState(partial)      // shallow merge
useStore.setState(full, true)   // replace (requires complete state)
useStore.getInitialState()      // returns initial state (since v4.5.0)
useStore.subscribe(listener)    // returns unsubscribe function
// useStore.destroy()           // REMOVED in v5

// Vanilla store (from createStore) — same API without the hook
store.getState()
store.setState(partial)
store.getInitialState()
store.subscribe(listener)
```

The `subscribe` listener signature is unchanged: `(state: T, prevState: T) => void`.

## Step-by-Step Migration Checklist

1. **Update to latest v4** (v4.5.x) and fix all deprecation warnings.
2. **Verify React 18+ and TypeScript 4.5+** in your project.
3. **Replace default imports** with named imports (`import { create } from 'zustand'`).
4. **Audit selectors** for unstable references:
   - Selectors returning new objects/arrays → wrap with `useShallow` or split into atomic selectors.
   - Selectors using a second `shallow` argument → switch to `useShallow` or `createWithEqualityFn`.
5. **Install `use-sync-external-store`** as a peer dependency if using `zustand/traditional`.
6. **Remove `destroy()` calls** — use the unsubscribe function from `subscribe()` instead.
7. **Audit `setState(..., true)` calls** — ensure they provide complete state objects.
8. **Check persist middleware usage:**
   - If you relied on initial state being written to storage, add an explicit `setState` call.
   - Verify `version` + `migrate` are set if your persisted schema has changed.
9. **Update build config** if you relied on UMD/SystemJS builds or targeted ES5.
10. **Run `npm install zustand@^5.0.15`** and verify your test suite passes.
11. **Replace hand-written initial-state snapshots with `getInitialState()`** in store reset logic and test cleanup.
12. **Review behavior changes within v5.0.x** (below) if the codebase relies on persist return values, `shallow` with class instances, or DevTools action names.

## Behavior Changes Within v5.0.x

Patch releases after v5.0.0 changed a few observable behaviors. None require code changes for typical apps, but check these during review:

| Since | Change | Check |
|---|---|---|
| 5.0.5 | `shallow`/`useShallow` return `false` when prototypes differ | Selectors comparing class instances or `Object.create(...)` objects |
| 5.0.5 | Unnamed DevTools actions get stack-inferred names instead of `anonymous` | Tooling or tests that match on action names |
| 5.0.8 | Persisted `set`/`setState` return the storage `setItem` result | Effects written as `useEffect(() => store.setState(x))` |
| 5.0.8 | `shallow({ a: undefined }, { b: undefined })` is `false` | Selectors relying on the old equality |
| 5.0.12 | Inner `onRehydrateStorage` callback receives the latest state | Callbacks that assumed the merged snapshot |
| 5.0.15 | `persist.clearStorage()` cancels an in-flight hydration | UI gated on `hasHydrated()` after clearing |

## TypeScript Notes

- The double-parentheses pattern `create<T>()(...)` is unchanged in v5.
- `StoreApi` no longer includes `destroy`. If your code references `StoreApi['destroy']`, remove it.
- `setState` with `replace: true` now requires the partial type to be the full state type — incomplete objects are flagged at compile time.
- `StateCreator` generic signature is unchanged. Existing slice typings work without modification; immer-typed slices compose without errors from v5.0.11.
- `ExtractState<typeof store>` is exported from `zustand` since v5.0.3 — delete local copies of that helper.
- `StateStorage`, `PersistStorage`, and `PersistOptions` gained optional return-type parameters in v5.0.8; existing annotations keep compiling.
