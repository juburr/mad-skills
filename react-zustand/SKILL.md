---
name: react-zustand
description: Guides Zustand state management including store design, selectors,
  middleware, TypeScript patterns, performance optimization, and high-frequency
  update handling. Use when writing, reviewing, or debugging front-end applications
  that use Zustand for state management.
---

# Zustand

Lightweight state management for React and framework-agnostic applications. Zustand stores are plain JavaScript objects exposed as hooks — no providers, no boilerplate. Zustand v5 requires React 18+ and TypeScript 4.5+.

## Canonical Imports (v5)

```ts
// React store (most common)
import { create } from 'zustand'

// Vanilla store (framework-agnostic)
import { createStore } from 'zustand/vanilla'

// Bind vanilla store into React
import { useStore } from 'zustand'

// Shallow comparison utilities
import { useShallow } from 'zustand/react/shallow'
import { shallow } from 'zustand/shallow'

// Equality-function variant (requires use-sync-external-store peer dep)
import { createWithEqualityFn } from 'zustand/traditional'

// Middleware
import { devtools, persist, subscribeWithSelector, combine } from 'zustand/middleware'
import { immer } from 'zustand/middleware/immer'
import { redux } from 'zustand/middleware'
```

**Review rule:** `create` in v5 no longer accepts a custom equality function. Use `createWithEqualityFn` from `zustand/traditional` or wrap selectors with `useShallow`.

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
counterStore.subscribe((state) => console.log(state))
```

## Update Semantics

- `set(partial)` performs a **shallow merge** by default.
- `set(partial, true)` **replaces** the entire state. Use with extreme caution — this wipes actions if they live in state.
- Use updater functions for state based on previous state: `set((s) => ({ count: s.count + 1 }))`.
- Never mutate state directly. `getState().obj.field = value` is always a bug.

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

Group all actions under an `actions` key. Actions are stable references that never trigger re-renders, making this safe to select without `useShallow`.

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

### Pattern C: External Actions

Actions defined outside the store via `setState`. Useful for code splitting or calling actions without a hook.

```ts
export const useBearStore = create<{ bears: number }>()(() => ({ bears: 0 }))
export const inc = () => useBearStore.setState((s) => ({ bears: s.bears + 1 }))
```

**Caveat:** Middlewares that modify `set` or `get` (e.g., immer's draft updater, subscribeWithSelector) are **not** applied to `store.getState()` / `store.setState()`. If you rely on middleware behavior, prefer store-defined actions or call them via `useBearStore.getState().someAction()`.

## Slices Pattern

Compose a single store from modular slices. Apply middleware only at the combined store level — never inside individual slices.

```ts
import { create, StateCreator } from 'zustand'

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

Select the smallest unit of state each component needs. Zustand uses `Object.is` by default — primitives and stable references are compared efficiently.

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

**When `useShallow` is NOT needed:**
- Selecting a single primitive value
- Selecting a stable reference (action function, actions namespace object)

**When `useShallow` is NOT enough:**
- Deeply nested state comparison — use `createWithEqualityFn` with a deep equality function instead

### Auto-Generated Selectors

Eliminate selector boilerplate by generating `.use.<key>()` hooks for every state key.

```ts
import { StoreApi, UseBoundStore } from 'zustand'

type WithSelectors<S> = S extends { getState: () => infer T }
  ? S & { use: { [K in keyof T]: () => T[K] } }
  : never

const createSelectors = <S extends UseBoundStore<StoreApi<object>>>(_store: S) => {
  const store = _store as WithSelectors<typeof _store>
  store.use = {} as any
  for (const k of Object.keys(store.getState())) {
    ;(store.use as any)[k] = () => store((s) => s[k as keyof typeof s])
  }
  return store
}

// Usage
const useBearStore = createSelectors(useBearStoreBase)
const bears = useBearStore.use.bears()       // atomic selector, type-safe
const increment = useBearStore.use.increment() // stable action ref
```

## High-Frequency Update Patterns

For real-time data streams (WebSocket feeds, live telemetry, rapid polling), standard React state updates are too expensive. Use these patterns in order of increasing throughput.

### Tier 1: `subscribeWithSelector` — Targeted External Listeners

Subscribe to minimal state slices outside React. Only fires when the selected value changes.

```ts
import { subscribeWithSelector } from 'zustand/middleware'
import { shallow } from 'zustand/shallow'

const useStore = create(
  subscribeWithSelector((set) => ({
    price: 0,
    volume: 0,
    setPrice: (p: number) => set({ price: p }),
  }))
)

const unsub = useStore.subscribe(
  (s) => s.price,
  (price, prev) => console.log('price:', prev, '->', price),
  { equalityFn: shallow, fireImmediately: true },
)
```

### Tier 2: Ingest Fast, Publish Slow (RAF Batching)

Buffer incoming events and flush to the store at a bounded cadence.

```ts
const useStreamStore = create<StreamState>()((set) => {
  let buffer: Event[] = []
  let rafId: number | null = null

  return {
    latest: null as Event | null,
    count: 0,
    ingest: (event: Event) => {
      buffer.push(event)
      if (!rafId) {
        rafId = requestAnimationFrame(() => {
          const batch = buffer
          buffer = []
          rafId = null
          set({ latest: batch[batch.length - 1], count: batch.length })
        })
      }
    },
  }
})
```

Prefer storing **latest snapshot** or **rolling aggregates** (count, min/max, last timestamp) over ever-growing event arrays.

### Tier 3: Transient Updates — Bypass React Entirely

Subscribe directly and update DOM via refs. Zero React re-renders.

```ts
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

**Caveat:** Transient updates bypass React's rendering model. Do not use with concurrent features or when the component tree depends on the transient value for layout.

## Middleware

### Stacking Order

Prefer the middleware stacking order used in Zustand's middleware typing tests: **devtools > subscribeWithSelector > persist > immer**. Other orders can work at runtime, but this order avoids TypeScript inference issues and matches the canonical examples.

```ts
const useStore = create<MyState>()(
  devtools(
    subscribeWithSelector(
      persist(
        immer((set) => ({
          bears: 0,
          inc: () => set((s) => { s.bears++ }),
        })),
        { name: 'bear-storage' }
      )
    )
  )
)
```

**Why order matters:**
- Prefer `devtools` outermost — it augments `setState` with action type tracking. Inner placement loses action names.
- `immer` should be innermost — it transforms `set` to accept mutable drafts, so the state creator sees the Immer API.

### Devtools

Name actions via the third `set` parameter for readable DevTools traces. Use `{ enabled: false }` to disable in production.

```ts
set((s) => ({ bears: s.bears + 1 }), false, 'bears/increment')
```

### Persist

Canonical persist setup uses `createJSONStorage`:

```ts
import { persist, createJSONStorage } from 'zustand/middleware'

persist(
  (set, get) => ({
    // state + actions...
  }),
  {
    name: 'app-storage',
    storage: createJSONStorage(() => sessionStorage), // default: localStorage
  },
)
```

Key options to enforce in reviews:

| Option | Purpose |
|---|---|
| `name` | Required. Unique storage key. |
| `storage` | Use `createJSONStorage(() => engine)` for custom engines. Supports `replacer`/`reviver` options for custom serialization. |
| `partialize` | Exclude fields from persistence (secrets, actions). |
| `version` + `migrate` | Handle schema changes across releases. |
| `merge` | Customize for nested objects (default shallow merge loses nested fields). |
| `skipHydration` | Manual hydration for SSR. Call `store.persist.rehydrate()` in a client `useEffect`. |

**Non-serializable values:** If you persist `Date`, `Map`, `Set`, or class instances, use `createJSONStorage` with `replacer`/`reviver` options, or convert values to JSON-friendly shapes in `partialize` and reconstruct them on hydrate.

**Hydration timing:** With async storage, the store is not hydrated on initial render. Gate UI on `store.persist.hasHydrated()` or `onFinishHydration` if the display depends on persisted values.

**v5 note:** Persist no longer writes initial state to storage on store creation. If you need the initial value persisted (e.g., random seed or server-provided default), explicitly call `setState` after store creation.

### Immer

Requires installing `immer`. Allows mutable draft syntax inside `set`.

**Gotcha:** If Immer cannot proxy an object (e.g., class instances without `[immerable] = true`), Zustand sees "no change" and skips subscriptions.

## TypeScript Patterns

### Double Parentheses

`create<T>()(...)` is required because TypeScript cannot partially infer generic type parameters. The outer call provides the state type; the inner call infers middleware types.

### Slice Typing

Use `StateCreator<CombinedState, Middlewares, [], SliceType>` for each slice to get proper type checking across the combined store.

### Middleware Mutator Types

When slices use middleware, include mutator types in the `StateCreator` generic:
- `['zustand/immer', never]`
- `['zustand/devtools', never]`
- `['zustand/persist', PersistedState]`
- `['zustand/subscribeWithSelector', never]`

### `combine` for Inferred Types

`combine` avoids the double-parentheses pattern by inferring types from the initial state object.

```ts
const useStore = create(
  combine({ bears: 0 }, (set) => ({
    inc: () => set((s) => ({ bears: s.bears + 1 })),
  }))
)
```

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| Direct state mutation | Updates don't propagate; components stale | Always use `set` / `setState` with immutable updates |
| `set(partial, true)` misuse | Actions wiped; state incomplete | Avoid replace flag unless providing complete state |
| Unstable selector output (v5) | "Maximum update depth exceeded" loop | Wrap with `useShallow` or return stable references |
| No selector | Component re-renders on every store change | Select only needed fields |
| Middleware inside slices | Unexpected behavior, double-wrapping | Apply middleware at the combined store level only |
| Persist + shallow merge on nested objects | Nested fields lost after rehydration | Provide custom `merge` function with deep merge |
| Async hydration "flash" | UI renders default state before hydration completes | Gate on `hasHydrated()` or `onFinishHydration` |
| `getState`/`setState` vs middleware | Middleware transforms not applied | Middleware modifies `set`/`get` only, not `getState`/`setState` |
| Immer + non-proxyable objects | Subscriptions silently stop firing | Mark class instances with `[immerable] = true` |
| Global store in RSC/SSR | User data leaks across requests | Use per-request store factory + Context provider |

## Review Checklist

### Correctness

- [ ] No direct state mutation (`getState().obj.x = ...`)
- [ ] Replace flag (`true`) only used with complete state objects
- [ ] Persist: hydration gated, nested merge safe, version/migrate present if schema evolves
- [ ] No server-side global store in RSC / Next.js App Router patterns

### Performance

- [ ] Components use atomic selectors (no bare `useStore()`)
- [ ] Multi-value selectors use `useShallow` or return stable references
- [ ] High-frequency updates use transient subscriptions or RAF batching

### Architecture

- [ ] Single store + slices, or justified multi-store design
- [ ] Middleware applied at combined store level, not inside slices
- [ ] Devtools enabled with named actions
- [ ] Actions model domain events, not raw setters

### TypeScript

- [ ] `create<T>()(...)` uses double parentheses
- [ ] Slice creators typed with `StateCreator<Combined, Mws, [], Slice>`
- [ ] Middleware mutator arrays match applied middleware

## Reference Files

| File | Contents | Read when |
|---|---|---|
| `references/redux-migration.md` | Step-by-step Redux to Zustand migration with concept mapping, example translations, and transitional patterns | Migrating an existing Redux codebase to Zustand |
| `references/v5-migration.md` | Breaking changes and step-by-step upgrade guide from Zustand v4 to v5, covering removed APIs, import changes, selector stability, and persist behavior | Upgrading an existing Zustand v4 codebase to v5 |
| `references/react-integration.md` | React-specific patterns including scoped stores via Context, Next.js App Router setup, SSR hydration, and testing | Building React applications with Zustand, especially with Next.js or when scoped store instances are needed |
| `references/svelte-integration.md` | Svelte adapter pattern using vanilla stores, `$` auto-subscription wrapper, and caveats | Using Zustand in Svelte applications or mixed-framework projects |
