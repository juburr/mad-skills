# Redux to Zustand Migration Guide

Pragmatic, incremental migration path from Redux (or Redux Toolkit) to Zustand. Supports teams that want to migrate one slice at a time with zero downtime.

## Concept Mapping

| Redux | Zustand |
|---|---|
| `configureStore()` | `create()` (React) or `createStore()` (vanilla) |
| `createSlice()` | Slice creator function with `StateCreator` type |
| `combineReducers()` | Spread slices: `create((...a) => ({ ...sliceA(...a), ...sliceB(...a) }))` |
| `useSelector(selector)` | `useStore(selector)` |
| `useDispatch()` + `dispatch(action)` | Direct action call: `useStore((s) => s.doThing)` |
| `<Provider store={store}>` | Not needed (global by default) or Context for scoped stores |
| `createAsyncThunk` | Async function inside store action using `set`/`get` |
| Redux DevTools | `devtools` middleware + action naming via third `set` arg |
| RTK Query | Replace with TanStack Query (React Query) alongside Zustand |
| `reselect` / `createSelector` | Inline selectors + `useShallow` for multi-value picks |

## Migration Strategy

1. **Identify one Redux slice** — pick one that is mostly local UI state or simple data (not RTK Query cache).
2. **Create a Zustand store** mirroring that slice's state and actions.
3. **Replace `useSelector`** calls with `useStore(selector)` in consuming components, one at a time.
4. **Remove the Redux slice** once all consumers are migrated.
5. **Repeat** for remaining slices. Redux and Zustand can coexist during migration.
6. **Remove `<Provider>`** and Redux dependencies once all slices are migrated.

Both Redux and Zustand can coexist in the same application. No "big bang" cutover is needed.

## Example Translation: Reducer to Actions

### Redux Slice (Before)

```ts
import { createSlice, PayloadAction } from '@reduxjs/toolkit'

interface TodosState {
  items: Todo[]
  filter: 'all' | 'active' | 'completed'
}

const todosSlice = createSlice({
  name: 'todos',
  initialState: { items: [], filter: 'all' } as TodosState,
  reducers: {
    addTodo: (state, action: PayloadAction<string>) => {
      state.items.push({ id: Date.now(), text: action.payload, done: false })
    },
    toggleTodo: (state, action: PayloadAction<number>) => {
      const todo = state.items.find((t) => t.id === action.payload)
      if (todo) todo.done = !todo.done
    },
    setFilter: (state, action: PayloadAction<TodosState['filter']>) => {
      state.filter = action.payload
    },
  },
})
```

### Zustand Store (After — Action Style)

```ts
import { create } from 'zustand'

interface TodosStore {
  items: Todo[]
  filter: 'all' | 'active' | 'completed'
  addTodo: (text: string) => void
  toggleTodo: (id: number) => void
  setFilter: (filter: TodosStore['filter']) => void
}

export const useTodosStore = create<TodosStore>()((set) => ({
  items: [],
  filter: 'all',
  addTodo: (text) =>
    set((s) => ({
      items: [...s.items, { id: Date.now(), text, done: false }],
    })),
  toggleTodo: (id) =>
    set((s) => ({
      items: s.items.map((t) => (t.id === id ? { ...t, done: !t.done } : t)),
    })),
  setFilter: (filter) => set({ filter }),
}))
```

Note: RTK's Immer-based mutations (e.g., `state.items.push(...)`) become immutable spread updates. To keep mutation syntax, add the `immer` middleware.

### Zustand Store with Immer (Preserving Mutation Syntax)

```ts
import { create } from 'zustand'
import { immer } from 'zustand/middleware/immer'

export const useTodosStore = create<TodosStore>()(
  immer((set) => ({
    items: [],
    filter: 'all',
    addTodo: (text) =>
      set((s) => {
        s.items.push({ id: Date.now(), text, done: false })
      }),
    toggleTodo: (id) =>
      set((s) => {
        const todo = s.items.find((t) => t.id === id)
        if (todo) todo.done = !todo.done
      }),
    setFilter: (filter) => set({ filter }),
  }))
)
```

## Example Translation: Component Consumption

### Redux Component (Before)

```tsx
import { useSelector, useDispatch } from 'react-redux'
import { addTodo, toggleTodo } from './todosSlice'

const TodoList = () => {
  const todos = useSelector((state: RootState) => state.todos.items)
  const dispatch = useDispatch()

  return (
    <>
      <button onClick={() => dispatch(addTodo('New'))}>Add</button>
      {todos.map((t) => (
        <div key={t.id} onClick={() => dispatch(toggleTodo(t.id))}>
          {t.text}
        </div>
      ))}
    </>
  )
}
```

### Zustand Component (After)

```tsx
import { useTodosStore } from './todosStore'

const TodoList = () => {
  const todos = useTodosStore((s) => s.items)
  const addTodo = useTodosStore((s) => s.addTodo)
  const toggleTodo = useTodosStore((s) => s.toggleTodo)

  return (
    <>
      <button onClick={() => addTodo('New')}>Add</button>
      {todos.map((t) => (
        <div key={t.id} onClick={() => toggleTodo(t.id)}>
          {t.text}
        </div>
      ))}
    </>
  )
}
```

Key differences:
- No `useDispatch` — call actions directly.
- No `Provider` wrapping required.
- Selectors are passed directly to the store hook.

## Transitional Pattern: Redux Middleware Bridge

For teams that depend heavily on reducers and action types, Zustand's `redux` middleware preserves the dispatch/reducer pattern during transition.

```ts
import { create } from 'zustand'
import { redux } from 'zustand/middleware'

type State = { count: number }
type Action = { type: 'inc'; by?: number } | { type: 'reset' }

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'inc':
      return { count: state.count + (action.by ?? 1) }
    case 'reset':
      return { count: 0 }
  }
}

export const useCounter = create(redux(reducer, { count: 0 }))

// Components use dispatch just like Redux:
const dispatch = useCounter((s) => s.dispatch)
dispatch({ type: 'inc', by: 5 })
```

This is a stepping stone. Once the team is comfortable with Zustand, replace the reducer with direct actions.

## Async Actions (Replacing createAsyncThunk)

Redux uses `createAsyncThunk` for async operations. In Zustand, use `async` functions with `set`/`get` directly.

### Redux Async Thunk (Before)

```ts
const fetchTodos = createAsyncThunk('todos/fetch', async () => {
  const res = await fetch('/api/todos')
  return res.json()
})

// In slice extraReducers:
builder.addCase(fetchTodos.pending, (state) => { state.loading = true })
builder.addCase(fetchTodos.fulfilled, (state, action) => {
  state.loading = false
  state.items = action.payload
})
builder.addCase(fetchTodos.rejected, (state) => {
  state.loading = false
  state.error = 'Failed to fetch'
})
```

### Zustand Async Action (After)

```ts
export const useTodosStore = create<TodosStore>()((set) => ({
  items: [],
  loading: false,
  error: null as string | null,
  fetchTodos: async () => {
    set({ loading: true, error: null })
    try {
      const res = await fetch('/api/todos')
      const items = await res.json()
      set({ items, loading: false })
    } catch {
      set({ loading: false, error: 'Failed to fetch' })
    }
  },
}))
```

## Adding DevTools Parity

Redux projects typically rely on Redux DevTools. Restore this capability with the `devtools` middleware and named actions.

```ts
import { devtools } from 'zustand/middleware'

export const useTodosStore = create<TodosStore>()(
  devtools(
    (set) => ({
      items: [],
      addTodo: (text) =>
        set(
          (s) => ({ items: [...s.items, { id: Date.now(), text, done: false }] }),
          false,
          'todos/addTodo',  // action name for DevTools
        ),
    }),
  )
)
```

Use a consistent naming convention (e.g., `feature/action`) for traceability.

## v5 Migration Gotchas for Redux Teams

- **Object/array selectors need stable outputs.** React-Redux `useSelector` uses strict `===` reference equality by default (unless you pass a custom `equalityFn` like `shallowEqual`). Zustand v5 likewise compares selector outputs by reference (`Object.is`). Multi-value selectors that construct new objects or arrays must be wrapped with `useShallow` (or return a stable reference) to avoid unnecessary re-renders and potential infinite loops.
- **No `Provider` means no test isolation by default.** Use `setState` / `getInitialState` to reset stores between tests, or use the vanilla store + Context pattern for scoped test instances.
- **RTK Query has no direct Zustand equivalent.** For server state caching, use TanStack Query alongside Zustand (Zustand for client state, TanStack Query for server state).
