---
name: react-zustand
description: Guides Zustand v5 state management including store design, selectors,
  middleware (persist, devtools, immer), TypeScript patterns, SSR/Next.js, testing,
  performance optimization, and high-frequency update handling. Use when writing,
  reviewing, debugging, or upgrading front-end applications that use Zustand for
  state management.
---

# Zustand

Lightweight state management for React and framework-agnostic applications. Zustand stores are plain JavaScript objects exposed as hooks — no providers, no boilerplate.

> **Verified against Zustand v5.0.15** (released 2026-08-13). v5 requires TypeScript 4.5+ and, for the React entry points, React 18+. All v5.0.x releases are API-compatible, but devtools, persist, and `shallow` behavior changed across patch releases. If your knowledge of Zustand predates v5.0.5, read `references/version-notes.md` before relying on recalled behavior.

```bash
npm install zustand@^5.0.15
```

Optional peer dependencies — install only what you use:

| Package | Needed for |
|---|---|
| `immer` | `zustand/middleware/immer` |
| `use-sync-external-store` | `zustand/traditional` (`createWithEqualityFn`, `useStoreWithEqualityFn`) |
| `@redux-devtools/extension` (dev) | Typing of `devtools` options (`DevtoolsOptions`) |

## Canonical Imports (v5)

```ts
// React store (most common)
import { create } from 'zustand'

// Vanilla store (framework-agnostic; also re-exported from 'zustand')
import { createStore } from 'zustand/vanilla'

// Bind any store (vanilla or bound) into React
import { useStore } from 'zustand'

// Types
import type { StateCreator, StoreApi, UseBoundStore, ExtractState } from 'zustand'

// Shallow comparison utilities
import { useShallow } from 'zustand/react/shallow' // also exported from 'zustand/shallow'
import { shallow } from 'zustand/shallow'

// Equality-function variant (requires use-sync-external-store peer dep)
import { createWithEqualityFn, useStoreWithEqualityFn } from 'zustand/traditional'

// Middleware
import { devtools, persist, createJSONStorage, subscribeWithSelector, combine, redux } from 'zustand/middleware'
import { unstable_ssrSafe } from 'zustand/middleware' // experimental (v5.0.9+); API may change
import { immer } from 'zustand/middleware/immer' // not exported from 'zustand/middleware'
```

**Review rule:** `create` in v5 no longer accepts a custom equality function. Use `createWithEqualityFn` from `zustand/traditional` or wrap selectors with `useShallow`. Flag default imports (`import create from 'zustand'`) — removed in v5. Flag per-middleware paths like `zustand/middleware/persist` — they ship only type declarations and fail at runtime.

## Store Creation

### React Store (Hook-Based)

`create` returns a React hook with store API methods attached (`setState`, `getState`, `getInitialState`, `subscribe`).

```ts
import { create } from 'zustand'

type State = { count: number }
type Actions = { inc: (by: number) => void }

// Note: create<T>()((set) => ...) uses double parentheses for TypeScript inference
export const useCounter = create<State & Actions>()((set) => ({
  count: 0,
  inc: (by) => set((s) => ({ count: s.count + by })),
}))
```

### Vanilla Store (Framework-Agnostic)

`createStore` returns a store object without React dependency. Use `useStore(store, selector)` to consume in React.

```ts
import { createStore } from 'zustand/vanilla'

const counterStore = createStore<State & Actions>()((set) => ({
  count: 0,
  inc: (by) => set((s) => ({ count: s.count + by })),
}))

// Access outside React
counterStore.getState().count
counterStore.setState({ count: 5 })
counterStore.subscribe((state, prevState) => console.log(state, prevState))
```

## Update Semantics

- `set(partial)` performs a **shallow merge** by default.
- `set(partial, true)` **replaces** the entire state and requires a complete state object (type error otherwise). It wipes actions if they live in state.
- Use updater functions for state based on previous state: `set((s) => ({ count: s.count + 1 }))`.
- An updater that returns the current state object (`set((s) => s)`) is a no-op. Any other `set` creates a new state object and notifies every listener, even if all values are equal — selectors decide whether components re-render.
- Never mutate state directly. `getState().obj.field = value` is always a bug.
- `set`, `get`, and the store API cannot be used while the initializer runs. `create((set, get) => ({ a: 1, b: get().a }))` throws because state does not exist yet — compute derived initial values locally instead.

## State and Actions Organization

### Pattern A: Colocated Actions (Recommended Default)

Actions live alongside state in the store for encapsulation.

```ts
export const useBearStore = create<BearState>()((set) => ({
  bears: 0,
  inc: () => set((s) => ({ bears: s.bears + 1 })),
}))
```

### Pattern B: Actions Namespace

Group all actions under an `actions` key. The `actions` object keeps its reference across shallow-merged updates, so selecting it never triggers re-renders and does not need `useShallow`.

```ts
export const useBearStore = create<BearState>()((set) => ({
  bears: 0,
  actions: {
    inc: () => set((s) => ({ bears: s.bears + 1 })),
    reset: () => set({ bears: 0 }),
  },
}))

// Safe — actions object reference is stable
const { inc, reset } = useBearStore((s) => s.actions)
```

**Persist caveat:** JSON serializes the nested `actions` object as `{}`, and the default shallow merge then overwrites the real actions on rehydration. Always `partialize` data-only fields when combining this pattern with `persist`.

### Pattern C: External Actions

Actions defined outside the store via `setState`. Useful for code splitting or calling actions without a hook.

```ts
export const useBearStore = create<{ bears: number }>()(() => ({ bears: 0 }))
export const inc = () => useBearStore.setState((s) => ({ bears: s.bears + 1 }))
```

The built-in middlewares patch `store.setState`, so external actions still get Immer drafts, persistence, and DevTools logging (`useBearStore.setState(fn, false, 'bears/inc')`). A custom middleware that only wraps the `set` argument passed to the initializer does **not** affect `store.setState` — the upstream README's "middlewares that modify `set` or `get` are not applied to `getState` and `setState`" warning refers to that case.

## Slices Pattern

Compose a single store from modular slices. Apply middleware only at the combined store level — never inside individual slices.

```ts
import { create, type StateCreator } from 'zustand'

interface FishSlice { fishes: number; addFish: () => void }
interface BearSlice { bears: number; addBear: () => void; eatFish: () => void }
type Store = FishSlice & BearSlice

const createFishSlice: StateCreator<Store, [], [], FishSlice> = (set) => ({
  fishes: 0,
  addFish: () => set((s) => ({ fishes: s.fishes + 1 })),
})

const createBearSlice: StateCreator<Store, [], [], BearSlice> = (set) => ({
  bears: 0,
  addBear: () => set((s) => ({ bears: s.bears + 1 })),
  eatFish: () => set((s) => ({ fishes: s.fishes - 1 })),
})

export const useBoundStore = create<Store>()((...a) => ({
  ...createFishSlice(...a),
  ...createBearSlice(...a),
}))
```

**Review rule:** Flag `persist()` or `devtools()` calls inside `createXSlice` functions — middleware belongs on the combined store.

## Performance: Selectors and Re-renders

### Atomic Selectors (Baseline)

Select the smallest unit of state each component needs. Zustand compares selector output with `Object.is` — primitives and stable references are compared efficiently.

```ts
// Good: atomic pick, re-renders only when bears changes
const bears = useBearStore((s) => s.bears)

// Bad: no selector = re-renders on every state change
const state = useBearStore()
```

### Multi-Value Selectors Require `useShallow`

Selectors returning new objects or arrays create fresh references on every call. In v5, this can cause **infinite render loops** ("Maximum update depth exceeded").

```ts
// Bad: new object reference every call — causes re-renders or loops
const { nuts, honey } = useBearStore((s) => ({ nuts: s.nuts, honey: s.honey }))

// Good: useShallow compares top-level properties
import { useShallow } from 'zustand/react/shallow'
const { nuts, honey } = useBearStore(
  useShallow((s) => ({ nuts: s.nuts, honey: s.honey })),
)

// Also works with arrays
const [nuts, honey] = useBearStore(
  useShallow((s) => [s.nuts, s.honey]),
)
```

The same loop occurs with inline fallbacks: `(s) => s.items ?? []` or `(s) => s.action ?? (() => {})`. Hoist the fallback to a module-level constant.

`useShallow` is unnecessary for a single primitive or a stable reference (action function, actions namespace object). It is not enough for deeply nested comparisons — use `createWithEqualityFn` with a deep equality function instead.

### `shallow` Comparison Rules (v5.0.8+)

| Input | Comparison |
|---|---|
| Plain objects | Own enumerable keys, order-insensitive; values by `Object.is` |
| Arrays / ordered iterables | Index by index |
| `Map` / `Set` | Entries, order-insensitive |
| Different prototypes | Always `false` (e.g., `{}` vs `Object.create(proto)`, two different classes) |

### Selector Cost

Selectors run on every render of the consuming component and on every store update, so keep them cheap. Derive expensive values in actions (store the result) or memoize them outside the selector. Module-level or `useCallback`-stable selectors let React skip a small amount of per-render bookkeeping (v5.0.7+), but they do not stop the selector from running.

For generated `.use.<key>()` selector hooks and scoped stores, read `references/react-integration.md`.

## High-Frequency Update Patterns

For real-time data streams (WebSocket feeds, live telemetry, rapid polling), standard React state updates are too expensive. Use these patterns in order of increasing throughput.

### Tier 1: `subscribeWithSelector` — Targeted External Listeners

Subscribe to minimal state slices outside React. Only fires when the selected value changes.

```ts
import { subscribeWithSelector } from 'zustand/middleware'
import { shallow } from 'zustand/shallow'

const usePriceStore = create<PriceState>()(
  subscribeWithSelector((set) => ({
    price: 0,
    volume: 0,
    setPrice: (p: number) => set({ price: p }),
  })),
)

const unsub = usePriceStore.subscribe(
  (s) => [s.price, s.volume] as const,
  ([price, volume], [prevPrice]) => console.log(prevPrice, '->', price, volume),
  { equalityFn: shallow, fireImmediately: true },
)
```

### Tier 2: Ingest Fast, Publish Slow (RAF Batching)

Buffer incoming events and flush to the store at a bounded cadence.

```ts
const useStreamStore = create<StreamState>()((set) => {
  let buffer: StreamEvent[] = []
  let rafId: number | null = null

  return {
    latest: null,
    count: 0,
    ingest: (event) => {
      buffer.push(event)
      if (rafId === null) {
        rafId = requestAnimationFrame(() => {
          const batch = buffer
          buffer = []
          rafId = null
          set((s) => ({ latest: batch[batch.length - 1], count: s.count + batch.length }))
        })
      }
    },
  }
})
```

Prefer storing **latest snapshot** or **rolling aggregates** (count, min/max, last timestamp) over ever-growing event arrays.

### Tier 3: Transient Updates — Bypass React Entirely

Subscribe directly and update DOM via refs. Zero React re-renders.

```tsx
const TickerDisplay = () => {
  const ref = useRef<HTMLSpanElement>(null)

  useEffect(() => {
    return useTickerStore.subscribe((s) => {
      if (ref.current) ref.current.textContent = s.price.toFixed(2)
    })
  }, [])

  return <span ref={ref}>{useTickerStore.getState().price.toFixed(2)}</span>
}
```

**Caveat:** Transient updates bypass React's rendering model. Do not use them when other components or layout depend on the transient value.

## Middleware

### Stacking Order

Use the order exercised by Zustand's own middleware typing tests: **devtools > subscribeWithSelector > persist > immer**. Other orders can work at runtime, but this order avoids TypeScript inference issues.

```ts
const useStore = create<MyState>()(
  devtools(
    subscribeWithSelector(
      persist(
        immer((set) => ({
          bears: 0,
          inc: () => set((s) => { s.bears++ }),
        })),
        { name: 'bear-storage' },
      ),
    ),
    { name: 'BearStore', enabled: process.env.NODE_ENV !== 'production' },
  ),
)
```

**Why order matters:**
- `devtools` outermost — it adds the action-name parameter to `setState`. Middlewares that patch `setState` outside it lose that parameter's type.
- `immer` innermost — it transforms `set` to accept mutable drafts, so the state creator sees the Immer API.
- Write middleware calls inline inside `create<T>()(...)`. Wrapping them in a helper function breaks contextual type inference.

### Devtools

- Name actions via the third `set` argument: `set((s) => ({ bears: s.bears + 1 }), undefined, 'bears/increment')`. An object `{ type, ...payload }` also works.
- Unnamed updates are labeled `anonymousActionType` if set, else the caller name inferred from the stack trace (v5.0.5+; e.g., `Object.inc`), else `'anonymous'`. Inference is best-effort and breaks under minification — name important actions explicitly.
- **Always pass `enabled` explicitly.** The default only disables devtools when `import.meta.env.MODE === 'production'` (ESM build) or `process.env.NODE_ENV === 'production'` (CJS build). Bundlers that resolve the ESM build without defining `import.meta.env` (common in webpack-based setups) leave devtools connected in production. Use `enabled: import.meta.env.DEV` in Vite, `enabled: process.env.NODE_ENV !== 'production'` elsewhere.
- `store.devtools?.cleanup()` (v5.0.5+) disconnects a store — call it when discarding dynamically created stores. `store.devtools` is `undefined` whenever devtools did not connect (disabled, production, no extension, SSR), despite its type, so keep the `?.`.
- `actionsDenylist: ['internal/.*']` hides matching actions in the DevTools UI (filtering happens in the extension; actions are still sent).

### Persist

```ts
import { persist, createJSONStorage } from 'zustand/middleware'

persist(
  (set, get) => ({ /* state + actions */ }),
  {
    name: 'app-storage', // unique storage key (required)
    storage: createJSONStorage(() => sessionStorage), // default: window.localStorage
    partialize: (s) => ({ theme: s.theme, recent: s.recent }),
    version: 2,
    migrate: (persisted, fromVersion) => migrateSettings(persisted, fromVersion),
  },
)
```

Key options to enforce in reviews:

| Option | Purpose |
|---|---|
| `name` | Required. Unique storage key. |
| `storage` | `createJSONStorage(() => engine)` for custom engines; `replacer`/`reviver` for custom serialization. |
| `partialize` | Persist data fields only (exclude secrets, transient flags, actions). |
| `version` + `migrate` | Handle schema changes across releases. `migrate` may be async. |
| `merge` | Default is a shallow merge — customize for nested objects or to validate. |
| `skipHydration` | Manual hydration for SSR. Call `store.persist.rehydrate()` in a client `useEffect`. |
| `onRehydrateStorage` | `(state) => (hydratedState, error) => void` — the inner callback receives the latest state (v5.0.12+). |

Review rules:
- **Validate what you read.** `createJSONStorage` casts parsed JSON to your state type without checks; corrupt, stale, or tampered storage reaches the store. Validate in `merge` or a custom `PersistStorage` (e.g., with a schema library).
- **Hydration timing.** Synchronous storage (`localStorage`) hydrates during store creation unless an async `migrate` runs; async storage never does. Gate UI on `store.persist.hasHydrated()` / `onFinishHydration` when display depends on persisted values.
- **No initial write (v5).** Persist only writes on `setState`. Call `setState` after creation if the initial value must be stored.
- **`setState` return value (v5.0.8+).** On a persisted store, `set`/`setState` return the storage's `setItem` result — a Promise for async storage. Use a block body in effects (`useEffect(() => { store.setState(x) }, [])`). The expression form `useEffect(() => store.setState(x))` is a type error on persisted stores (`'unknown' is not assignable to 'void | Destructor'`) and returns a Promise from the effect with async storage.
- **Server rendering.** When the storage getter throws (no `window` on the server), persist degrades to a plain in-memory store (each `set` call from an action logs a warning) and does **not** attach `store.persist`. Only touch `store.persist` in client code.
- **`clearStorage()` cancels an in-flight hydration** (v5.0.15+). In that case `hasHydrated()` stays `false` until the next `rehydrate()` — call it if UI is gated on hydration. After a completed hydration the flag stays `true`. Concurrent `rehydrate()` calls resolve last-call-wins (v5.0.10+).

For custom storage engines, validation code, Map/Set persistence, cross-tab sync, devtools options, and `unstable_ssrSafe`, read `references/middleware.md`.

### Immer

Requires installing `immer`. Allows mutable draft syntax inside `set`.

**Gotcha:** If Immer cannot draft an object (e.g., class instances without `[immerable] = true`), mutations apply in place, the state reference does not change, and Zustand skips notifying subscribers.

## TypeScript Patterns

### Double Parentheses

`create<T>()(...)` is required because TypeScript cannot partially infer generic type parameters. The outer call provides the state type; the inner call infers middleware types. The same applies to `createStore<T>()(...)` and `createWithEqualityFn<T>()(...)`.

### Slice Typing

Use `StateCreator<CombinedState, Middlewares, [], SliceType>` for each slice to get proper type checking across the combined store. Immer-typed slices compose correctly as of v5.0.11.

### Middleware Mutator Types

When slices use middleware, include mutator types in the `StateCreator` generic, outermost-first (matching the wrapping order): `['zustand/devtools', never]`, `['zustand/subscribeWithSelector', never]`, `['zustand/persist', PersistedState]` (the `partialize` return type; use `unknown` if inference fails), `['zustand/immer', never]`, `['zustand/redux', Action]`.

```ts
const createFishSlice: StateCreator<Store, [['zustand/devtools', never], ['zustand/immer', never]], [], FishSlice> = (set) => ({
  fishes: 0,
  addFish: () => set((s) => { s.fishes++ }, undefined, 'fish/add'),
})
```

### `combine` and `ExtractState` for Inferred Types

`combine` avoids the double-parentheses pattern by inferring types from the initial state object. Use `ExtractState` (exported since v5.0.3) to name the inferred type.

```ts
import { create, type ExtractState } from 'zustand'
import { combine } from 'zustand/middleware'

const useBearStore = create(
  combine({ bears: 0 }, (set) => ({
    inc: () => set((s) => ({ bears: s.bears + 1 })),
  })),
)

type BearState = ExtractState<typeof useBearStore> // { bears: number; inc: () => void }
```

### Dynamic `replace` Flag

`setState(partial, flag)` with a runtime `boolean` flag fails overload resolution. Cast the argument tuple: `store.setState(...([next, flag] as Parameters<typeof store.setState>))`.

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| Direct state mutation | Updates don't propagate; components stale | Always use `set` / `setState` with immutable updates |
| `set(partial, true)` misuse | Actions wiped; state incomplete | Avoid replace flag unless providing complete state |
| Unstable selector output (v5) | "Maximum update depth exceeded" loop | Wrap with `useShallow` or return stable references |
| No selector | Component re-renders on every store change | Select only needed fields |
| `get()` inside the initializer | `TypeError` reading undefined at store creation | Compute derived initial values locally |
| Middleware inside slices | Unexpected behavior, double-wrapping | Apply middleware at the combined store level only |
| Persist + shallow merge on nested objects | Nested fields lost after rehydration | Provide custom `merge` function with deep merge |
| Persist + actions namespace | Actions become `{}` after reload | `partialize` data-only fields |
| Trusting `createJSONStorage` output | Corrupt or stale storage crashes components | Validate in `merge` or a custom `PersistStorage` |
| Async hydration "flash" | UI renders default state before hydration completes | Gate on `hasHydrated()` or `onFinishHydration` |
| Returning persisted `setState` from an effect | TS error `unknown` not assignable to `void \| Destructor` | Use a block body in the effect |
| `store.persist` used during SSR | `Cannot read properties of undefined` on the server | Access `store.persist` only in client effects |
| Devtools left at defaults | Store state exposed in production | Pass `enabled` explicitly |
| Immer + non-draftable objects | Subscriptions silently stop firing | Mark class instances with `[immerable] = true` |
| Global store in RSC/SSR | User data leaks across requests | Use per-request store factory + Context provider |

## Review Checklist

### Correctness

- [ ] No direct state mutation (`getState().obj.x = ...`)
- [ ] Replace flag (`true`) only used with complete state objects
- [ ] No `get()`/`set()` calls during store initialization
- [ ] Persist: `partialize` limits to data fields, hydration gated, nested merge safe, version/migrate present if schema evolves
- [ ] Persist: storage input validated before reaching the store
- [ ] No server-side global store in RSC / Next.js App Router patterns

### Performance

- [ ] Components use atomic selectors (no bare `useStore()`)
- [ ] Multi-value selectors use `useShallow` or return stable references (no inline `?? []` fallbacks)
- [ ] High-frequency updates use transient subscriptions or RAF batching

### Architecture

- [ ] Single store + slices, or justified multi-store design
- [ ] Middleware applied at combined store level, not inside slices
- [ ] Devtools: explicit `enabled`, named actions
- [ ] Actions model domain events, not raw setters

### TypeScript

- [ ] `create<T>()(...)` uses double parentheses
- [ ] Slice creators typed with `StateCreator<Combined, Mws, [], Slice>`
- [ ] Middleware mutator arrays match applied middleware

## Reference Files

| File | Contents | Read when |
|---|---|---|
| `references/version-notes.md` | v5.0.0–v5.0.15 release history, behavior changes per patch release, stale patterns, and minimum versions for specific fixes | Knowledge may predate v5.0.15, debugging behavior that differs by patch version, or choosing a minimum version |
| `references/middleware.md` | Devtools options and action naming, persist API, custom/validated storage, Map/Set persistence, cross-tab sync, subscribeWithSelector, immer, `unstable_ssrSafe`, custom middleware | Configuring or reviewing middleware beyond the rules above |
| `references/react-integration.md` | Scoped stores via Context, Next.js App Router setup, SSR hydration, generated selector hooks, resetting state, and testing (including store-reset mocks) | Building React applications with Zustand, especially with Next.js, scoped store instances, or tests |
| `references/v5-migration.md` | Breaking changes and step-by-step upgrade guide from Zustand v4 to v5, covering removed APIs, import changes, selector stability, and persist behavior | Upgrading an existing Zustand v4 codebase to v5 |
| `references/redux-migration.md` | Step-by-step Redux to Zustand migration with concept mapping, example translations, and transitional patterns | Migrating an existing Redux codebase to Zustand |
| `references/svelte-integration.md` | Svelte adapter pattern using vanilla stores, `$` auto-subscription wrapper, and caveats | Using Zustand in Svelte applications or mixed-framework projects |
