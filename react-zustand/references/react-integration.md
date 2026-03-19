# React Integration

Patterns for using Zustand in React applications, including scoped stores, Next.js App Router, SSR hydration, and testing.

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

## Scoped Stores via Context

Use the vanilla store + React Context pattern when:
- Multiple instances of the same store type are needed (e.g., per-form, per-panel).
- Store needs initialization from props.
- Test isolation is required without global mocking.

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

```tsx
// bear-store-provider.tsx
'use client'

import { createContext, useContext, useRef, type ReactNode } from 'react'
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
  const storeRef = useRef<BearStore | null>(null)
  if (storeRef.current === null) {
    storeRef.current = createBearStore(initialBears)
  }

  return (
    <BearStoreContext.Provider value={storeRef.current}>
      {children}
    </BearStoreContext.Provider>
  )
}

export const useBearStore = <T,>(selector: (state: BearState) => T): T => {
  const store = useContext(BearStoreContext)
  if (!store) throw new Error('Missing BearStoreProvider')
  return useStore(store, selector)
}
```

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

React Server Components cannot use Zustand stores (no hooks, no client-side state). A global module-level store on the server would **leak state across user requests**.

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
- Never define stores as global module-level variables in the App Router.
- Use `createStore` (vanilla) + Context instead of `create` (React hook) for server-compatible patterns.
- RSCs can pass initial data as props to client provider components.
- Nest providers at route level when stores should be route-scoped.

## SSR and Persist Hydration

When using `persist` middleware with SSR (Next.js, Remix), the server has no access to `localStorage`. This causes hydration mismatches: the server renders with default state while the client hydrates with persisted state.

### Solution A: `skipHydration` + Manual Rehydrate

```ts
const useStore = create(
  persist(
    (set) => ({ count: 0, inc: () => set((s) => ({ count: s.count + 1 })) }),
    {
      name: 'counter-storage',
      skipHydration: true,
    },
  )
)

// In a client component:
useEffect(() => {
  useStore.persist.rehydrate()
}, [])
```

### Solution B: Hydration Gate with Loading State

```ts
const useStore = create(
  persist(
    (set) => ({
      count: 0,
      _hasHydrated: false,
      setHasHydrated: (val: boolean) => set({ _hasHydrated: val }),
    }),
    {
      name: 'counter-storage',
      onRehydrateStorage: () => (state) => {
        state?.setHasHydrated(true)
      },
    },
  )
)

// In component:
const hasHydrated = useStore((s) => s._hasHydrated)
if (!hasHydrated) return <Skeleton />
```

### Solution C: `persist.hasHydrated()` API

```ts
// Wait for hydration in a hook
const useHydration = () => {
  const [hydrated, setHydrated] = useState(useStore.persist.hasHydrated())

  useEffect(() => {
    const unsub = useStore.persist.onFinishHydration(() => setHydrated(true))
    return () => unsub()
  }, [])

  return hydrated
}
```

## Resetting Store State

### Using `getInitialState`

```ts
const useStore = create<State & Actions>()((set) => ({
  count: 0,
  inc: () => set((s) => ({ count: s.count + 1 })),
}))

// Reset to initial state (replace=true removes any extra runtime keys)
const reset = () => useStore.setState(useStore.getInitialState(), true)
```

### In Tests

```ts
afterEach(() => {
  useStore.setState(useStore.getInitialState(), true)
})
```

The `true` flag replaces state entirely, ensuring a clean reset including any accumulated derived state.

## Testing

### Recommended Stack

- **Test runner:** Vitest or Jest
- **UI testing:** React Testing Library
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

### Testing Scoped (Context-Based) Stores

Wrap components in the provider with controlled initial state.

```tsx
it('renders with initial bears', () => {
  render(
    <BearStoreProvider initialBears={42}>
      <BearCounter />
    </BearStoreProvider>
  )
  expect(screen.getByText('42')).toBeInTheDocument()
})
```

### Mock Pattern for Test Isolation (Alternative)

For global stores, create a mock module that resets stores automatically. Store all created stores in a `Set`, and in `afterEach`, iterate and reset each to its initial state.

```ts
// __mocks__/zustand.ts (simplified)
import { create as actualCreate } from 'zustand'

const storeResetFns = new Set<() => void>()

const createUncurried = <T>(stateCreator: any) => {
  const store = actualCreate(stateCreator)
  const initialState = store.getInitialState()
  storeResetFns.add(() => store.setState(initialState, true))
  return store
}

// Support both curried create<T>()((set) => ...) and uncurried create((set) => ...)
export const create = (<T>(stateCreator?: any) => {
  return stateCreator === undefined
    ? createUncurried  // curried: create<T>() returns initializer
    : createUncurried(stateCreator) // uncurried: create((set) => ...)
}) as typeof actualCreate

afterEach(() => {
  storeResetFns.forEach((fn) => fn())
})
```
