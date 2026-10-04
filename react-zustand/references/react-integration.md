# React Integration

Patterns for using Zustand in React applications, including scoped stores, Next.js App Router, SSR hydration, and testing. Verified against Zustand v5.0.15.

## Standard Usage

### Selecting State

Select the smallest unit of state each component needs. Zustand uses `Object.is` equality by default — primitives and stable references are efficient.

```tsx
// Good: atomic selector
const bears = useBearStore((s) => s.bears)

// Good: action is a stable reference
const addBear = useBearStore((s) => s.addBear)

// Bad: no selector = re-renders on every state change
const everything = useBearStore()
```

### Selecting Multiple Values

Wrap multi-value selectors with `useShallow` to prevent unnecessary re-renders (or infinite loops in v5).

```tsx
import { useShallow } from 'zustand/react/shallow'

// Object pick
const { nuts, honey } = useBearStore(
  useShallow((s) => ({ nuts: s.nuts, honey: s.honey })),
)

// Array pick
const [nuts, honey] = useBearStore(
  useShallow((s) => [s.nuts, s.honey]),
)

// Derived value producing new reference (e.g., Object.keys)
const mealKeys = useMealStore(useShallow((s) => Object.keys(s.meals)))
```

### Exposing Custom Hooks Instead of Raw Stores

Encapsulate store access behind purpose-specific hooks. Prevents broad subscriptions and documents intended usage.

```ts
// store.ts
const useStoreBase = create<AppState>()(/* ... */)

// Public hooks
export const useBears = () => useStoreBase((s) => s.bears)
export const useBearActions = () => useStoreBase((s) => s.actions)

// Do NOT export useStoreBase directly
```

### Generated Selector Hooks

Eliminate selector boilerplate by generating `.use.<key>()` hooks for every top-level state key.

```ts
import type { StoreApi, UseBoundStore } from 'zustand'

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
const bears = useBearStore.use.bears()         // atomic selector, type-safe
const increment = useBearStore.use.increment() // stable action ref
```

Keys are captured when `createSelectors` runs — state keys added later get no hook. For a vanilla store, constrain `S extends StoreApi<object>` and build each hook with `useStore(_store, (s) => s[k as keyof typeof s])` instead of calling the store.

## Scoped Stores via Context

Use the vanilla store + React Context pattern when:
- Multiple instances of the same store type are needed (e.g., per-form, per-panel).
- Store needs initialization from props.
- Test isolation is required without global mocking.
- The app server-renders (Next.js, Remix) and the store holds per-user data.

### Store Factory

```ts
// bear-store.ts
import { createStore } from 'zustand/vanilla'

export interface BearState {
  bears: number
  actions: { addBear: () => void }
}

export type BearStore = ReturnType<typeof createBearStore>

export const createBearStore = (initialBears = 0) =>
  createStore<BearState>()((set) => ({
    bears: initialBears,
    actions: {
      addBear: () => set((s) => ({ bears: s.bears + 1 })),
    },
  }))
```

### Context Provider

Create the store once per provider instance with a lazy `useState` initializer (the pattern used in the upstream docs). A `useRef` with a null check also works.

```tsx
// bear-store-provider.tsx
'use client'

import { createContext, useContext, useState, type ReactNode } from 'react'
import { useStore } from 'zustand'
import { createBearStore, type BearState, type BearStore } from './bear-store'

const BearStoreContext = createContext<BearStore | null>(null)

export const BearStoreProvider = ({
  children,
  initialBears,
}: {
  children: ReactNode
  initialBears?: number
}) => {
  const [store] = useState(() => createBearStore(initialBears))
  return <BearStoreContext.Provider value={store}>{children}</BearStoreContext.Provider>
}

export const useBearStore = <T,>(selector: (state: BearState) => T): T => {
  const store = useContext(BearStoreContext)
  if (!store) throw new Error('Missing BearStoreProvider')
  return useStore(store, selector)
}
```

Props are read only when the store is created. To react to later prop changes, remount the provider with a `key` (simplest), or sync them in an effect that calls `store.setState` inside a block body.

### Usage in Components

```tsx
// Scoped to each provider instance
<BearStoreProvider initialBears={5}>
  <BearCounter />
</BearStoreProvider>

<BearStoreProvider initialBears={10}>
  <BearCounter />  {/* separate store instance */}
</BearStoreProvider>
```

## Next.js App Router

### Core Constraint

React Server Components cannot use Zustand stores (no hooks, no client-side state). A global module-level store that is written during a server render would **leak state across user requests**.

### Required Architecture

1. Create a **store factory** (not a global store).
2. Create a **Context provider** (client component) that instantiates the store.
3. Wrap the provider in a layout, passing server-fetched data as `initialState` props.
4. Consume via a custom hook that reads from Context.

The scoped store via Context pattern above is exactly the pattern needed. Wrap it in a layout:

```tsx
// app/layout.tsx
import { BearStoreProvider } from '@/providers/bear-store-provider'

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html>
      <body>
        <BearStoreProvider initialBears={10}>
          {children}
        </BearStoreProvider>
      </body>
    </html>
  )
}
```

**Rules:**
- Never write to a module-level store during server rendering.
- Use `createStore` (vanilla) + Context instead of `create` (React hook) for per-request stores.
- RSCs can pass initial data as props to client provider components; props must be serializable.
- Nest providers at route level when stores should be route-scoped.

### Module-Level Stores with `unstable_ssrSafe` (Experimental)

For client-only state that never needs server data (UI toggles, carts filled after mount), v5.0.9+ offers `unstable_ssrSafe` from `zustand/middleware`. It makes every `setState` throw during SSR, so a global store cannot leak data between requests. Server renders always show the initial state, and writes must happen after mount. The API is experimental; prefer the Context pattern when server data must seed the store.

## SSR and Persist Hydration

When using `persist` middleware with SSR (Next.js, Remix), the server has no access to `localStorage`. On the server, persist runs as an in-memory store and does not attach `store.persist` — touch `store.persist` only in client effects. The server renders default state while the client hydrates persisted state, which can cause hydration mismatches.

### Solution A: `skipHydration` + Manual Rehydrate

```ts
const useStore = create<CounterState>()(
  persist(
    (set) => ({ count: 0, inc: () => set((s) => ({ count: s.count + 1 })) }),
    {
      name: 'counter-storage',
      skipHydration: true,
    },
  ),
)

// In a client component:
useEffect(() => {
  void useStore.persist.rehydrate()
}, [])
```

### Solution B: Hydration Flag in State

```tsx
const useStore = create<CounterState & HydrationState>()(
  persist(
    (set) => ({
      count: 0,
      inc: () => set((s) => ({ count: s.count + 1 })),
      _hasHydrated: false,
      setHasHydrated: (val: boolean) => set({ _hasHydrated: val }),
    }),
    {
      name: 'counter-storage',
      skipHydration: true, // required for SSR — see below
      partialize: (s) => ({ count: s.count }), // never persist the flag
      onRehydrateStorage: () => (state) => {
        state?.setHasHydrated(true)
      },
    },
  ),
)

// Once, in a client component near the root:
useEffect(() => {
  void useStore.persist.rehydrate()
}, [])

// In components:
const hasHydrated = useStore((s) => s._hasHydrated)
if (!hasHydrated) return <Skeleton />
```

Keep `skipHydration: true` in SSR apps. Without it, synchronous `localStorage` hydrates during client-side store creation, so `_hasHydrated` is already `true` on the first client render while the server rendered `<Skeleton />` — a hydration mismatch.

### Solution C: `useHydration` Hook (No Extra State)

```ts
const useHydration = () => {
  const [hydrated, setHydrated] = useState(false)

  useEffect(() => {
    const unsubHydrate = useStore.persist.onHydrate(() => setHydrated(false)) // manual rehydrate
    const unsubFinish = useStore.persist.onFinishHydration(() => setHydrated(true))
    setHydrated(useStore.persist.hasHydrated()) // after subscribing, so no event is missed
    return () => {
      unsubHydrate()
      unsubFinish()
    }
  }, [])

  return hydrated
}
```

Starting from `false` keeps the first client render identical to the server render.

## Resetting Store State

### Using `getInitialState`

```ts
const useStore = create<State & Actions>()((set, get, store) => ({
  count: 0,
  inc: () => set((s) => ({ count: s.count + 1 })),
  reset: () => set(store.getInitialState()),
}))

// Reset from outside (replace=true removes any extra runtime keys)
useStore.setState(useStore.getInitialState(), true)
```

On a persisted store, `getInitialState()` returns the creator's defaults and the reset writes them to storage. Call `store.persist.clearStorage()` too if the stored item should be removed rather than overwritten.

## Testing

### Recommended Stack

- **Test runner:** Vitest or Jest
- **UI testing:** React Testing Library (`user-event` calls are already wrapped in `act`)
- **Network mocking:** Mock Service Worker (MSW)

### Store Unit Tests

Test store logic directly without React rendering.

```ts
import { useCounter } from './counter-store'

describe('counter store', () => {
  afterEach(() => {
    useCounter.setState(useCounter.getInitialState(), true)
  })

  it('increments', () => {
    useCounter.getState().inc(5)
    expect(useCounter.getState().count).toBe(5)
  })

  it('resets between tests', () => {
    expect(useCounter.getState().count).toBe(0)
  })
})
```

### Component Tests

```tsx
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useCounter } from './counter-store'
import { Counter } from './Counter'

afterEach(() => {
  useCounter.setState(useCounter.getInitialState(), true)
})

it('displays count and increments on click', async () => {
  render(<Counter />)
  expect(screen.getByText('Count: 0')).toBeInTheDocument()

  await userEvent.click(screen.getByRole('button', { name: /increment/i }))
  expect(screen.getByText('Count: 1')).toBeInTheDocument()
})
```

Wrap direct `store.setState` calls made while components are mounted in `act(() => { ... })` (block body — persisted `setState` may return a Promise).

### Testing Scoped (Context-Based) Stores

Wrap components in the provider with controlled initial state.

```tsx
it('renders with initial bears', () => {
  render(
    <BearStoreProvider initialBears={42}>
      <BearCounter />
    </BearStoreProvider>,
  )
  expect(screen.getByText('42')).toBeInTheDocument()
})
```

### Auto-Reset Mock for Global Stores

For many global stores, mock `zustand` so every store created by `create` or `createStore` resets after each test. A manual mock replaces the entire module: keep `export * from 'zustand'` and wrap both `create` and `createStore`, or `useStore`, `createStore`, and everything else become `undefined` in tests. Load the real implementations with `vi.importActual` / `jest.requireActual`.

```ts
// __mocks__/zustand.ts — Vitest. Place next to the configured `root`.
import { afterEach, vi } from 'vitest'
import { act } from '@testing-library/react'
import type * as ZustandExportedTypes from 'zustand'
export * from 'zustand'

const { create: actualCreate, createStore: actualCreateStore } =
  await vi.importActual<typeof ZustandExportedTypes>('zustand')

// Reset fns return setState's result: a pending write for persisted stores with async storage
export const storeResetFns = new Set<() => unknown>()

const createUncurried = <T>(stateCreator: ZustandExportedTypes.StateCreator<T>) => {
  const store = actualCreate(stateCreator)
  const initialState = store.getInitialState()
  storeResetFns.add(() => store.setState(initialState, true))
  return store
}

// Supports both create<T>()(creator) and create(creator)
export const create = (<T>(stateCreator: ZustandExportedTypes.StateCreator<T>) =>
  typeof stateCreator === 'function'
    ? createUncurried(stateCreator)
    : createUncurried) as typeof ZustandExportedTypes.create

const createStoreUncurried = <T>(stateCreator: ZustandExportedTypes.StateCreator<T>) => {
  const store = actualCreateStore(stateCreator)
  const initialState = store.getInitialState()
  storeResetFns.add(() => store.setState(initialState, true))
  return store
}

export const createStore = (<T>(stateCreator: ZustandExportedTypes.StateCreator<T>) =>
  typeof stateCreator === 'function'
    ? createStoreUncurried(stateCreator)
    : createStoreUncurried) as typeof ZustandExportedTypes.createStore

afterEach(async () => {
  await act(async () => {
    await Promise.all([...storeResetFns].map((resetFn) => resetFn()))
  })
})
```

The mock replaces only the `zustand` specifier. Stores created with `createStore` imported from `zustand/vanilla` (like the store factory above) bypass it and leak between tests. Mock that entry point too. A store may end up registered by both mocks; resetting it twice is harmless.

```ts
// __mocks__/zustand/vanilla.ts
import { afterEach, vi } from 'vitest'
import { act } from '@testing-library/react'
import type * as ZustandVanillaTypes from 'zustand/vanilla'
export * from 'zustand/vanilla'

const { createStore: actualCreateStore } =
  await vi.importActual<typeof ZustandVanillaTypes>('zustand/vanilla')

const storeResetFns = new Set<() => unknown>()

const createStoreUncurried = <T>(stateCreator: ZustandVanillaTypes.StateCreator<T>) => {
  const store = actualCreateStore(stateCreator)
  const initialState = store.getInitialState()
  storeResetFns.add(() => store.setState(initialState, true))
  return store
}

export const createStore = (<T>(stateCreator: ZustandVanillaTypes.StateCreator<T>) =>
  typeof stateCreator === 'function'
    ? createStoreUncurried(stateCreator)
    : createStoreUncurried) as typeof ZustandVanillaTypes.createStore

afterEach(async () => {
  await act(async () => {
    await Promise.all([...storeResetFns].map((resetFn) => resetFn()))
  })
})
```

Enable both mocks in a file listed in `test.setupFiles`:

```ts
// vitest.setup.ts
import { vi } from 'vitest'

vi.mock('zustand')
vi.mock('zustand/vanilla')
```

For Jest, put the files in `__mocks__/zustand.ts` and `__mocks__/zustand/vanilla.ts` adjacent to `node_modules` (applied automatically, no `jest.mock` call needed), drop the `vitest` import, and replace each `await vi.importActual<...>(...)` call with `jest.requireActual<...>(...)`:

```ts
const { create: actualCreate, createStore: actualCreateStore } =
  jest.requireActual<typeof ZustandExportedTypes>('zustand')
```
