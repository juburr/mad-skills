# Middleware Reference

Detailed configuration and behavior for Zustand's built-in middleware, verified against v5.0.15. All middleware imports come from `zustand/middleware` except `immer` (`zustand/middleware/immer`).

## Devtools

Connects a store to the [Redux DevTools Extension](https://github.com/reduxjs/redux-devtools). Install `@redux-devtools/extension` as a dev dependency so `DevtoolsOptions` is fully typed.

### Options

| Option | Default | Purpose |
|---|---|---|
| `name` | extension default | Instance name shown in DevTools. Stores sharing a `name` and setting `store` share one connection. |
| `enabled` | see below | Connects when truthy and the extension is installed. Always set explicitly. |
| `anonymousActionType` | inferred | Label for updates without an action name. Overrides stack-trace inference. |
| `store` | — | Groups several stores under one `name`: action types become `` `${store}/${type}` `` and state is keyed by `store`. |
| `actionsDenylist` / `actionsAllowlist` | — | Regex string(s) passed to the extension to hide/show actions in the UI. Actions are still sent. |
| Other extension options (`maxAge`, `trace`, `serialize`, ...) | — | Passed through to `__REDUX_DEVTOOLS_EXTENSION__.connect()`. |

**`enabled` default:** the ESM build connects unless `import.meta.env.MODE === 'production'`; the CJS build connects unless `process.env.NODE_ENV === 'production'`. Bundlers that resolve the ESM build but don't define `import.meta.env` leave devtools connected in production builds when the extension is installed.

```ts
devtools(creator, {
  name: 'CartStore',
  enabled: import.meta.env.DEV, // Vite; elsewhere: process.env.NODE_ENV !== 'production'
})
```

### Action Names

`set` and `store.setState` accept a third argument when `devtools` is applied:

```ts
set((s) => ({ items: [...s.items, item] }), undefined, 'cart/addItem')
set({ items: [] }, undefined, { type: 'cart/clear', reason: 'checkout' })
useCartStore.setState({ open: true }, undefined, 'cart/open') // external action
```

Resolution order for the action type: explicit name > `anonymousActionType` > caller name inferred from `new Error().stack` (v5.0.5+; V8, SpiderMonkey, and JavaScriptCore formats since v5.0.13) > `'anonymous'`. Inferred names look like `Object.addItem` for object-literal actions and are mangled by minification.

### Multiple Stores, One DevTools Instance

```ts
const useBears = create<BearState>()(devtools(bearCreator, { name: 'App', store: 'bears' }))
const useFish = create<FishState>()(devtools(fishCreator, { name: 'App', store: 'fish' }))
// DevTools shows actions like "bears/addBear" and state { bears: {...}, fish: {...} }
```

### Cleanup

`store.devtools.cleanup()` (v5.0.5+) unsubscribes the extension connection and removes the store from a shared `name` group. Call it when discarding dynamically created stores (e.g., removing an entry from a keyed store map).

`store.devtools` is attached only when a connection was made. With `enabled: false`, in production builds, without the extension, or during SSR it is `undefined` even though its type says otherwise, so guard the call:

```ts
useCartStore.devtools?.cleanup()
```

### Redux DevTools Dispatch

With the `redux` middleware, actions dispatched from the DevTools UI are forwarded to the store's `dispatch`. The action type `__setState` is reserved for setting state from DevTools.

## Persist

### Options

| Option | Default | Notes |
|---|---|---|
| `name` | — (required) | Unique storage key. |
| `storage` | `createJSONStorage(() => window.localStorage)` | A `PersistStorage`. The getter runs lazily; if it throws (SSR), persistence is disabled for that store. |
| `partialize` | identity | Returns the persisted subset. Its return type is the `PersistedState` used in mutator types. |
| `version` | `0` | Stored alongside state. A mismatch triggers `migrate`. |
| `migrate` | — | `(persisted: unknown, version: number) => PersistedState \| Promise<PersistedState>` — the `partialize` shape, which is then passed to `merge`. Without it, mismatched data is discarded with a console error. |
| `merge` | shallow `{ ...current, ...persisted }` | `(persisted: unknown, current: State) => State`. Customize for nested state or validation. |
| `onRehydrateStorage` | — | `(state) => (hydratedState?, error?) => void`. Outer runs before hydration; inner runs after with the latest state, or with an error. |
| `skipHydration` | `false` | Skip automatic hydration at creation; call `store.persist.rehydrate()` manually. |

### `store.persist` API

| Method | Behavior |
|---|---|
| `rehydrate()` | Re-reads storage. Typed `Promise<void> \| void`; returns a real Promise only for async storage, but `await` works either way. Concurrent calls resolve last-call-wins (v5.0.10+). |
| `hasHydrated()` | `true` after the most recent hydration finished. |
| `onHydrate(fn)` | Listener called when hydration starts. Returns an unsubscribe function. |
| `onFinishHydration(fn)` | Listener called when hydration finishes. Returns an unsubscribe function. |
| `clearStorage()` | Removes the storage item and cancels any in-flight hydration (v5.0.15+). If it cancelled one, `hasHydrated()` stays `false` until the next `rehydrate()`; after a completed hydration it stays `true`. Does not reset in-memory state. |
| `getOptions()` / `setOptions(partial)` | Read or change options at runtime (e.g., switch `name` per user). |

`store.persist` is **not attached** when the storage getter throws (e.g., `window` is undefined during server rendering). Guard server code accordingly.

### Hydration Lifecycle

1. `onHydrate` listeners and the outer `onRehydrateStorage` run.
2. `storage.getItem(name)` — synchronous for `localStorage`, async otherwise.
3. Version check → `migrate` if versions differ.
4. `merge(persisted, current)` → state replaced with the result.
5. If migrated, the migrated state is written back.
6. Inner `onRehydrateStorage` callback runs with the latest state; `hasHydrated()` becomes `true`; `onFinishHydration` listeners run.

With synchronous storage, all six steps finish before `create` returns, so the first render already sees persisted values. With async storage, the first render sees defaults.

`store.getInitialState()` on a persisted store returns the creator's defaults, not hydrated values. Resetting with `set(store.getInitialState())` also writes those defaults to storage.

### Async Storage and `setState` Return Values

Since v5.0.8, persisted `set`/`setState` return whatever `storage.setItem` returns. With async storage this is a Promise you can await to know the write finished:

```ts
await useSettings.setState({ theme: 'dark' }) // resolves after the async setItem completes
```

`StateStorage<R>` and `PersistStorage<S, R>` carry the `setItem`/`removeItem` return type as `R` (default `unknown`).

### Validating Persisted Data

`createJSONStorage` casts parsed JSON straight to the state type. Validate before it reaches the store. The simplest hook is `merge`, which runs after any migration and receives `unknown`:

```ts
import { z } from 'zod'

const PersistedSettings = z.object({
  theme: z.enum(['light', 'dark']),
  recent: z.array(z.string()).max(20),
})
type PersistedSettings = z.infer<typeof PersistedSettings>

export const useSettings = create<SettingsState>()(
  persist(
    (set) => ({
      theme: 'light',
      recent: [],
      setTheme: (theme) => set({ theme }),
    }),
    {
      name: 'settings',
      version: 1,
      partialize: (s): PersistedSettings => ({ theme: s.theme, recent: s.recent }),
      merge: (persisted, current) => {
        const parsed = PersistedSettings.safeParse(persisted)
        return parsed.success ? { ...current, ...parsed.data } : current // fall back to defaults
      },
    },
  ),
)
```

For stricter control (e.g., rejecting data before `migrate`, or encrypting), implement a custom `PersistStorage<PersistedState>` whose `getItem` returns `null` for invalid payloads.

### Custom Storage Engines

Any object with `getItem`, `setItem`, and `removeItem` (sync or async) works with `createJSONStorage`:

```ts
import { persist, createJSONStorage, type StateStorage } from 'zustand/middleware'
import { get, set, del } from 'idb-keyval'

const idbStorage: StateStorage = {
  getItem: async (name) => (await get<string>(name)) ?? null,
  setItem: async (name, value) => { await set(name, value) },
  removeItem: async (name) => { await del(name) },
}

persist(creator, { name: 'big-store', storage: createJSONStorage(() => idbStorage) })
```

For React Native, pass `AsyncStorage` (or an MMKV adapter) the same way. Async engines mean the first render always sees defaults — gate on hydration.

### Map, Set, and Date

JSON drops `Map`/`Set` contents and turns `Date` into a string. Use `replacer`/`reviver`:

```ts
persist(creator, {
  name: 'collections',
  storage: createJSONStorage(() => localStorage, {
    replacer: (_key, value) => {
      if (value instanceof Map) return { __type: 'Map', entries: [...value] }
      if (value instanceof Set) return { __type: 'Set', values: [...value] }
      return value
    },
    reviver: (key, value) => {
      const v = value as { __type?: string; entries?: [unknown, unknown][]; values?: unknown[] }
      if (v?.__type === 'Map') return new Map(v.entries)
      if (v?.__type === 'Set') return new Set(v.values)
      if (key === 'updatedAt' && typeof value === 'string') return new Date(value)
      return value
    },
  }),
})
```

`Date` objects reach `replacer` already converted by `toJSON()`, so revive dates by key. Libraries such as `superjson` can replace hand-written replacers via a custom `PersistStorage`.

### Cross-Tab Sync

Persist does not listen for changes from other tabs. Rehydrate on the `storage` event:

```ts
window.addEventListener('storage', (e) => {
  if (e.key === useSettings.persist.getOptions().name && e.newValue) {
    void useSettings.persist.rehydrate()
  }
})
```

### Migrations

```ts
persist(creator, {
  name: 'settings',
  version: 2,
  migrate: (persisted, version) => {
    const s = persisted as Record<string, unknown>
    if (version < 1) s.recent = []
    if (version < 2) s.theme = s.darkMode ? 'dark' : 'light'
    return s as PersistedSettings
  },
})
```

Write migrations cumulatively (`if (version < n)` chains) so any older version upgrades. Pair migrations with validation — `migrate` receives `unknown`.

## subscribeWithSelector

Adds a selector overload to `store.subscribe`:

```ts
const unsub = useStore.subscribe(
  (s) => s.user?.id,              // selector
  (id, prevId) => track(id, prevId), // fires only when the selected value changes
  { equalityFn: Object.is, fireImmediately: false }, // defaults
)
```

Without a selector, `subscribe(listener)` behaves as usual. Use it for side effects outside render (analytics, syncing to non-React systems), unsubscribing in `useEffect` cleanup.

## Immer

```ts
import { immer } from 'zustand/middleware/immer'

const useTodos = create<TodoState>()(
  immer((set) => ({
    todos: [],
    toggle: (id) =>
      set((draft) => {
        const todo = draft.todos.find((t) => t.id === id)
        if (todo) todo.done = !todo.done
      }),
  })),
)
```

- `set` still accepts plain partial objects.
- In a recipe, either mutate the draft or return a new value — never both.
- Drafting `Map`/`Set` requires calling Immer's `enableMapSet()` once at startup.
- Class instances need `[immerable] = true`; otherwise mutations happen in place, the state reference does not change, and subscribers are not notified.
- Slice creators under `immer` use `StateCreator<Store, [['zustand/immer', never]], [], Slice>`; their types compose correctly as of v5.0.11.

## combine

`combine(initialState, creator)` infers the store type from `initialState` plus the creator's return. Inside the creator, `set` and `get` are typed against `initialState` only — actions are not visible through `get()`. Use the explicit `create<T>()` pattern when actions call other actions via `get()`.

## redux

`redux(reducer, initialState)` adds `dispatch` to both the state and the store (`useStore.dispatch(action)`). With `devtools`, each dispatched action appears under its own `type`. Use it as a transitional bridge from Redux, not as a default.

## unstable_ssrSafe (Experimental)

Added in v5.0.9 for module-level stores in SSR frameworks (Next.js). On the server (`typeof window === 'undefined'`), every `set`/`setState` call throws `Cannot set state of Zustand store in SSR`. A store that can never be written on the server can never leak one request's data into another.

```ts
import { create } from 'zustand'
import { unstable_ssrSafe as ssrSafe } from 'zustand/middleware'

export const useCartStore = create<CartState>()(
  ssrSafe((set) => ({
    items: [],
    add: (item) => set((s) => ({ items: [...s.items, item] })),
  })),
)
```

- Server renders always see the initial state. Write client-specific data after mount (effects, event handlers), never during render.
- The optional second argument overrides detection: `ssrSafe(creator, isServer)`.
- Place it outermost so no middleware can bypass the throwing `setState`.
- The name and API are explicitly unstable and expected to change; prefer the per-request store + Context pattern for production code that must pass server data into the store.

## Writing Custom Middleware

A middleware is `(config) => (set, get, api) => config(wrappedSet, get, api)`. To affect external `store.setState` calls as well, also reassign `api.setState`:

```ts
import type { StateCreator, StoreMutatorIdentifier } from 'zustand'

type Logger = <
  T,
  Mps extends [StoreMutatorIdentifier, unknown][] = [],
  Mcs extends [StoreMutatorIdentifier, unknown][] = [],
>(
  f: StateCreator<T, Mps, Mcs>,
  name?: string,
) => StateCreator<T, Mps, Mcs>

type LoggerImpl = <T>(f: StateCreator<T, [], []>, name?: string) => StateCreator<T, [], []>

const loggerImpl: LoggerImpl = (f, name) => (set, get, store) => {
  const loggedSet: typeof set = (...a) => {
    const result = set(...(a as Parameters<typeof set>))
    console.log(name ?? 'store', get())
    return result // keep persist's setItem result (a Promise for async storage)
  }
  const setState = store.setState
  store.setState = (...a) => {
    const result = setState(...(a as Parameters<typeof setState>))
    console.log(name ?? 'store', store.getState())
    return result
  }
  return f(loggedSet, get, store)
}

export const logger = loggerImpl as unknown as Logger
```

Wrappers must return what the wrapped `set`/`setState` returns — otherwise an outer `persist` loses its awaitable `setItem` result.

Middleware that adds properties to the store (like `persist` adds `store.persist`) must also declare a mutator by augmenting the `StoreMutators` interface (`declare module 'zustand' { interface StoreMutators<S, A> { ... } }`) and typing its signature with that mutator identifier, as the built-in middlewares do.
