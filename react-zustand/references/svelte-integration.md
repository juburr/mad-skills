# Svelte Integration

Zustand is React-first, but its vanilla store API (`zustand/vanilla`) can be adapted to work with Svelte's reactivity system. This is useful for shared state in mixed-framework projects (e.g., Astro with both React and Svelte islands) or when Zustand's middleware ecosystem is preferred over Svelte-native stores.

## How Svelte Stores Work

Svelte considers any object with a `.subscribe(callback)` method to be a store. The `$store` syntax auto-subscribes and unsubscribes in components.

For `$store` auto-subscription to work, the `.subscribe` method must:
1. Accept a callback `(value) => void`.
2. Call the callback immediately with the current value.
3. Return an unsubscribe function `() => void`.

## Why Zustand Isn't Drop-In Compatible

Zustand's `.subscribe` does not call the callback immediately with the current value — it only fires on future changes. This breaks Svelte's `$` auto-subscription, which expects the initial value on subscribe.

## The Adapter Pattern

Bridge the gap with a thin wrapper that creates a Svelte `readable` store seeded with `getState()` and updated via Zustand's `subscribe`.

```ts
// lib/zustandToSvelte.ts
import { readable } from 'svelte/store'
import type { StoreApi } from 'zustand'

export function zustandToSvelte<S extends StoreApi<any>>(zustandStore: S) {
  type T = ReturnType<S['getState']>

  const svelteReadable = readable<T>(zustandStore.getState(), (set) => {
    // Re-read current state — covers changes between adapter creation and first
    // subscriber (e.g., persist middleware rehydration).
    set(zustandStore.getState())
    const unsub = zustandStore.subscribe((value: T) => set(value))
    return () => unsub()
  })

  return {
    ...zustandStore,                                // preserve getState, setState
    subscribe: svelteReadable.subscribe,            // override for Svelte $store compatibility
    zustandSubscribe: zustandStore.subscribe,        // original Zustand subscribe for external listeners
  }
}
```

**How it works:**
- `readable(initialValue, startFn)` creates a Svelte-compatible store.
- The `start` function re-reads `getState()` on first subscription, preventing stale snapshots when state changes between adapter creation and first subscriber (common with persist rehydration).
- `zustandStore.subscribe(...)` forwards future updates.
- `subscribe` is overridden for Svelte's `$` auto-subscription.
- `zustandSubscribe` preserves the original Zustand subscribe function for non-Svelte code. The `S extends StoreApi<any>` generic retains middleware-enhanced typings (e.g., `subscribeWithSelector` overloads).

## Creating a Store

```ts
// lib/counter.store.ts
import { createStore } from 'zustand/vanilla'
import { devtools, persist } from 'zustand/middleware'
import { zustandToSvelte } from './zustandToSvelte'

interface CounterState {
  value: number
  actions: {
    increment: () => void
    decrement: () => void
    reset: () => void
  }
}

const counterStore = zustandToSvelte(
  createStore<CounterState>()(
    devtools(
      persist(
        (set) => ({
          value: 0,
          actions: {
            increment: () => set((s) => ({ value: s.value + 1 })),
            decrement: () => set((s) => ({ value: s.value - 1 })),
            reset: () => set({ value: 0 }),
          },
        }),
        { name: 'counter-storage' },
      ),
    ),
  ),
)

export default counterStore
```

Middleware (`devtools`, `persist`, etc.) works identically to the React setup since it operates on the vanilla store layer.

## Using in Svelte Components

```svelte
<script>
  import counterStore from '$lib/counter.store'
</script>

<p>Count: {$counterStore.value}</p>

<button on:click={() => $counterStore.actions.increment()}>+1</button>
<button on:click={() => $counterStore.actions.decrement()}>-1</button>
<button on:click={() => $counterStore.actions.reset()}>Reset</button>
```

Key points:
- `$counterStore` auto-subscribes using the overridden `.subscribe`.
- Access state properties directly: `$counterStore.value`.
- Call actions via the state object: `$counterStore.actions.increment()`.

## Using Outside Components

`getState` and `setState` work directly on the adapted store. For subscriptions, use `zustandSubscribe` (the original Zustand API) since `subscribe` is overridden for Svelte.

```ts
import counterStore from '$lib/counter.store'

// Read state
const currentValue = counterStore.getState().value

// Update state
counterStore.setState({ value: 42 })

// Subscribe to changes (use zustandSubscribe, not the Svelte-overridden subscribe)
const unsub = counterStore.zustandSubscribe((state) => {
  console.log('Counter changed:', state.value)
})

// Clean up when done
unsub()
```

## Caveats

### Whole-Store Subscription

The `$counterStore` syntax subscribes to the entire state object. Svelte will re-run reactive statements whenever any property changes, unlike Zustand's React integration where selectors narrow reactivity.

**Mitigation:** For performance-critical components, use derived stores to narrow reactivity:

```svelte
<script>
  import counterStore from '$lib/counter.store'
  import { derived } from 'svelte/store'

  // Only reacts to value changes, not other state
  const value = derived(counterStore, ($s) => $s.value)
</script>

<p>{$value}</p>
```

### Writable Stores

The adapter creates a read-only Svelte store. `$counterStore = newValue` assignment syntax does not work. Use actions or `setState` for updates.

### High-Frequency Updates

The same principles from the main skill apply:
- For very rapid updates, avoid triggering Svelte reactivity on every event.
- Buffer events and flush at a bounded cadence (e.g., `requestAnimationFrame`).
- For display-only high-frequency values, consider direct DOM updates outside Svelte's reactive system.

## Mixed-Framework Projects (e.g., Astro)

When both React and Svelte components share state:

1. Create a single vanilla store (`createStore`).
2. In React: consume with `useStore(vanillaStore, selector)`.
3. In Svelte: consume with `zustandToSvelte(vanillaStore)` and `$` syntax.

Both frameworks subscribe to the same underlying store. Changes made in one framework are immediately visible in the other.

```ts
// shared-store.ts
import { createStore } from 'zustand/vanilla'

export const sharedStore = createStore((set) => ({
  count: 0,
  inc: () => set((s) => ({ count: s.count + 1 })),
}))
```

```tsx
// React component
import { useStore } from 'zustand'
import { sharedStore } from './shared-store'

const Counter = () => {
  const count = useStore(sharedStore, (s) => s.count)
  return <div>{count}</div>
}
```

```svelte
<!-- Svelte component -->
<script>
  import { zustandToSvelte } from '$lib/zustandToSvelte'
  import { sharedStore } from './shared-store'

  const store = zustandToSvelte(sharedStore)
</script>

<p>{$store.count}</p>
```
