# Migrating from Zustand v4 to v5

Zustand v5 is a cleanup release — no new features, just removal of deprecated APIs and modernized defaults. Migration from v4 should be smooth. Update to the latest v4 first (v4.5.x) to surface deprecation warnings before upgrading to v5.

## Requirements

| Dependency | v4 Minimum | v5 Minimum |
|---|---|---|
| React | 16.8 | **18** |
| TypeScript | 4.0 | **4.5** |
| `use-sync-external-store` | bundled | **peer dependency** (only if using `zustand/traditional`) |

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

In v4, `create` accepted an optional equality function as a second argument (or via the hook call). In v5, `create` always uses `Object.is` — matching how React's `useState` works. The equality function parameter is gone.

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

In v4, a selector returning a new object reference on every call (e.g., `(s) => ({ a: s.a, b: s.b })`) caused unnecessary re-renders but usually worked. In v5, this pattern can trigger "Maximum update depth exceeded" errors due to stricter comparison in `useSyncExternalStore`.

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

### 4. Stricter `setState` with `replace` Flag

When calling `setState` with the replace flag set to `true`, v5 requires a **complete** state object. Passing a partial or empty object is a type error.

```ts
// v4 — allowed but produced invalid state
store.setState({}, true)

// v5 — type error; must provide complete state
store.setState({ count: 0, name: '' }, true)
```

If you are not using the `replace` flag (`setState(partial)` or `setState(partial, false)`), no change is needed.

### 5. `destroy` Method Removed

The `destroy()` method on the store API was deprecated in v4 and is removed in v5. Zustand stores with no active subscriptions are garbage collected automatically.

```ts
// v4 (deprecated)
const unsub = useStore.destroy()

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

### 7. `getInitialState` Added to Store API

v5 adds `getInitialState()` to the store API. This returns the state as it was when the store was first created and never changes. Use it for store resets:

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

All valid v5 import paths:

```ts
// Core
import { create } from 'zustand'
import { createStore } from 'zustand/vanilla'
import { useStore } from 'zustand'

// Traditional (equality function support)
import { createWithEqualityFn } from 'zustand/traditional'
import { useStoreWithEqualityFn } from 'zustand/traditional'

// Shallow comparison
import { useShallow } from 'zustand/react/shallow'  // React hook
import { shallow } from 'zustand/shallow'            // plain comparison function

// Middleware
import { devtools, persist, subscribeWithSelector, combine, redux } from 'zustand/middleware'
import { createJSONStorage } from 'zustand/middleware'
import { immer } from 'zustand/middleware/immer'
```

`useShallow` is also re-exported from `zustand/shallow` for convenience. Both `zustand/react/shallow` and `zustand/shallow` work.

## Store API Surface (v5)

```ts
// React store (from create)
useStore(selector)              // React hook
useStore.getState()             // get current state
useStore.setState(partial)      // shallow merge
useStore.setState(full, true)   // replace (requires complete state)
useStore.getInitialState()      // NEW in v5 — returns initial state
useStore.subscribe(listener)    // returns unsubscribe function
// useStore.destroy()           // REMOVED in v5

// Vanilla store (from createStore) — same API without the hook
store.getState()
store.setState(partial)
store.getInitialState()         // NEW in v5
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
10. **Run `npm install zustand@5`** and verify your test suite passes.
11. **Replace `getState()` with `getInitialState()`** in store reset logic and test cleanup.

## TypeScript Notes

- The double-parentheses pattern `create<T>()(...)` is unchanged in v5.
- `StoreApi` no longer includes `destroy`. If your code references `StoreApi['destroy']`, remove it.
- `setState` with `replace: true` now requires the partial type to be the full state type — incomplete objects are flagged at compile time.
- `StateCreator` generic signature is unchanged. Existing slice typings work without modification.
