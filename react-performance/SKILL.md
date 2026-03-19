---
name: react-performance
description: Guides React performance optimization including re-render prevention,
  memoization, concurrent features, high-frequency updates, and performance-focused
  code review. Use when writing, reviewing, or debugging React applications for
  performance, or optimizing React rendering and bundle size.
---

# React Performance

Helps write high-performance React code and review existing code for performance issues across five dimensions: unnecessary re-renders, state management overhead, rendering pipeline efficiency, high-frequency update handling, and bundle/load performance.

## Measurement-First Workflow

Never optimize without a measured bottleneck. Follow this loop:

1. **Identify the symptom** — janky interaction, slow mount, large bundle, dropped frames.
2. **Profile** — select the right tool for the symptom class.
3. **Isolate the cause** — pinpoint the component, state update, or bundle chunk.
4. **Apply a targeted fix** — change one thing at a time.
5. **Re-measure** — confirm improvement with the same profiling tool.

| Symptom | Primary Tool | Secondary Tool |
|---|---|---|
| Unnecessary re-renders | React DevTools Profiler | React Scan |
| Slow component render | `React.Profiler` onRender | Chrome Performance flamechart |
| Janky interactions (high INP) | Chrome Performance tab | `useTransition` / `useDeferredValue` |
| Large bundle / slow initial load | Bundle analyzer | Lighthouse |
| Layout shifts (CLS) | Lighthouse | `web-vitals` library |
| High-frequency update drops | Chrome Performance tab | RAF batching / direct DOM refs |

## How Re-renders Work

Understand these rules before optimizing:

1. **State change** triggers a render of that component and all descendants.
2. **Parent renders → children render** regardless of whether props changed (unless memoized).
3. **Context value change** re-renders every consumer of that context.
4. **Props alone do not trigger re-renders** in unmemoized components — the parent re-rendering is what causes child re-renders.

## Preventing Re-renders: Composition First

Composition patterns prevent re-renders structurally without memoization overhead. Prefer these over `React.memo`.

### Move State Down

Extract frequently changing state into the smallest possible child component:

```tsx
// Bad: typing re-renders ExpensiveChart
function Dashboard() {
  const [search, setSearch] = useState('');
  return (
    <>
      <input value={search} onChange={e => setSearch(e.target.value)} />
      <ExpensiveChart />
    </>
  );
}

// Good: search state isolated — ExpensiveChart unaffected
function SearchInput() {
  const [search, setSearch] = useState('');
  return <input value={search} onChange={e => setSearch(e.target.value)} />;
}

function Dashboard() {
  return (
    <>
      <SearchInput />
      <ExpensiveChart />
    </>
  );
}
```

### Children as Props

Components passed as `children` are created in the parent scope and hold stable references when the wrapper's state changes:

```tsx
function ScrollTracker({ children }) {
  const [scrollY, setScrollY] = useState(0);
  return (
    <div onScroll={e => setScrollY(e.target.scrollTop)}>
      <ScrollIndicator y={scrollY} />
      {children}
    </div>
  );
}

// ExpensiveContent does NOT re-render on scroll
<ScrollTracker>
  <ExpensiveContent />
</ScrollTracker>
```

## Memoization APIs

Use memoization when composition patterns are insufficient.

| API | Caches | Use When |
|---|---|---|
| `React.memo(Component)` | Component output | Expensive component receives same props frequently |
| `useMemo(() => val, deps)` | Computed value | Expensive computation, or stabilizing object/array references for memo'd children |
| `useCallback(fn, deps)` | Function reference | Stabilizing callbacks passed to memo'd children or used as effect deps |

### When NOT to Memoize

- Component is cheap to render (comparison cost exceeds render cost)
- Props change on nearly every render anyway
- `useCallback` without `React.memo` on the receiving component (adds overhead with no benefit)
- `useMemo` for trivial sub-millisecond computations
- Passing `children` as JSX to a memo'd component (children create new object references each render — memo the children instead, or restructure with composition)

### Stabilize Non-Primitive Props

For `React.memo` to be effective, all non-primitive props must have stable references:

```tsx
// Bad: new object every render defeats memo on Profile
<Profile person={{ name, age }} />

// Good: stable reference via useMemo
const person = useMemo(() => ({ name, age }), [name, age]);
<Profile person={person} />

// Best: pass primitives directly (no useMemo needed)
<Profile name={name} age={age} />
```

Hoist constant objects and arrays outside the component body entirely.

### React Compiler

React Compiler (stable) auto-memoizes components, values, and callbacks at build time as a Babel plugin. Compatible with React 17+.

- **New code:** Write without manual memoization; let the compiler handle it.
- **Existing code:** Manual `memo`/`useMemo`/`useCallback` continue to work alongside the compiler.
- **Keep manual memoization when:** values are effect dependencies and you need precise control over when effects fire.

## State Management for Performance

### Bail-Out Behavior

Both `useState` and `useReducer` skip re-renders when the new value is identical via `Object.is`. Use updater functions to access current state without stale closures:

```tsx
setCount(c => c + 1); // Always reads latest value
```

### Lazy Initialization

Pass a function (not a function call) to defer expensive initialization to the first render:

```tsx
// Bad: runs every render
const [data, setData] = useState(parseExpensiveData(raw));

// Good: runs only on first render
const [data, setData] = useState(() => parseExpensiveData(raw));
```

### Context Optimization

Split contexts to minimize re-render blast radius:

1. **Separate by domain** — `UserContext`, `ThemeContext`, not one monolithic `AppContext`.
2. **Separate state from dispatch** — components that only dispatch actions skip state-change re-renders.
3. **Memoize provider values** — wrap the value object in `useMemo`.

```tsx
function Provider({ children }) {
  const [state, dispatch] = useReducer(reducer, initialState);
  return (
    <DispatchContext.Provider value={dispatch}>
      <StateContext.Provider value={state}>
        {children}
      </StateContext.Provider>
    </DispatchContext.Provider>
  );
}
```

### State Colocation

Keep state as close to its consumers as possible. Decision order:

1. Used by one component → local `useState`
2. Used by one child → colocate with that child
3. Shared between siblings → lift to closest common parent
4. Prop drilling painful → localized Context provider
5. Truly global → external store (Zustand, Jotai, Redux Toolkit)

### useSyncExternalStore

Subscribe to external data sources (WebSocket, browser APIs, third-party stores) without tearing in concurrent mode. Define `subscribe` outside the component to prevent resubscription on every render. `getSnapshot` must return an immutable value.

## Concurrent Features

### useTransition

Mark state updates as non-urgent. The UI stays responsive while the transition renders in the background:

```tsx
const [query, setQuery] = useState('');
const [filterQuery, setFilterQuery] = useState('');
const [isPending, startTransition] = useTransition();

function handleChange(e) {
  setQuery(e.target.value);          // Urgent: update input immediately
  startTransition(() => {
    setFilterQuery(e.target.value);  // Non-urgent: triggers interruptible re-render
  });
}

// Memoize so urgent re-renders (from setQuery) skip the expensive work
const filtered = useMemo(() => filterLargeList(filterQuery), [filterQuery]);
```

**Do not run expensive synchronous computation inside the `startTransition` callback.** The callback runs synchronously in the event handler — only the resulting re-render is interruptible. Move heavy work to render-time derivation (as above), `useDeferredValue`, or a Web Worker.

### useDeferredValue

Defer re-rendering of a value until higher-priority work completes. Works like built-in debouncing with no fixed delay:

```tsx
const deferredQuery = useDeferredValue(query);
const isStale = query !== deferredQuery;
```

Wrap the consuming component in `React.memo` so it actually skips re-renders when the deferred value hasn't changed yet.

**When to still use debounce/throttle instead:** reducing HTTP request volume, rate-limiting API calls, or preventing multiple invocations of side-effectful functions.

### Automatic Batching

React 18+ batches all state updates (event handlers, promises, timeouts, native events) into a single render. Use `flushSync` from `react-dom` only when synchronous DOM access is required immediately after a state update (e.g., scroll-to-bottom, focus management).

### Code Splitting

Use `React.lazy` + `Suspense` for route-level and component-level splitting:

```tsx
const Dashboard = lazy(() => import('./Dashboard'));

<Suspense fallback={<Loading />}>
  <Dashboard />
</Suspense>
```

Declare lazy components at module level, not inside other components.

## High-Frequency Update Patterns

For data streams faster than React can render (WebSocket feeds, sensor data, animations), use these patterns in order of increasing throughput.

### Tier 1: RAF Batching — Ingest Fast, Render Slow

Buffer incoming events in a ref, flush to React state once per animation frame:

```tsx
useEffect(() => {
  let buffer = [];
  let rafId = null;

  const flush = () => {
    if (buffer.length > 0) {
      const batch = buffer;
      buffer = [];
      setMessages(prev => [...prev, ...batch].slice(-MAX_MESSAGES));
    }
    rafId = requestAnimationFrame(flush);
  };
  rafId = requestAnimationFrame(flush);

  const unsub = stream.subscribe(msg => buffer.push(msg));
  return () => { cancelAnimationFrame(rafId); unsub(); };
}, [stream]);
```

### Tier 2: Direct DOM via Refs — Bypass React Entirely

Subscribe directly and write to DOM elements via refs. Zero React re-renders:

```tsx
function LivePrice({ store }) {
  const ref = useRef(null);

  useEffect(() => {
    return store.subscribe(state => {
      if (ref.current) ref.current.textContent = state.price.toFixed(2);
    });
  }, [store]);

  return <span ref={ref}>{store.getState().price.toFixed(2)}</span>;
}
```

**Safe for:** text content, inline styles, CSS classes React does not control.
**Breaks React when:** modifying DOM structure or attributes React also manages.

### Tier 3: Canvas/WebGL — Drop Out of React DOM

For tens of thousands of visual elements, render to Canvas or WebGL. Keep React for controls and UI chrome; use Canvas/WebGL for data visualization. Use instanced rendering for massive object counts.

## Code Review Checklists

### Re-renders

| Signal | Risk | Fix |
|---|---|---|
| No selector on `useContext` | All consumers re-render on any change | Split context; memoize provider value |
| Inline object/array literal as prop | New reference every render breaks `memo` | Hoist constant outside component or `useMemo` |
| Inline function prop to memo'd child | New reference every render | `useCallback`, or move handler into the child |
| `useCallback` without `memo` on child | Overhead with no benefit | Remove `useCallback` or add `memo` to child |
| No selector on store hook | Component subscribes to entire store | Select only needed fields |
| Spreading `{...props}` to memo'd child | Passes unstable props silently | Destructure and pass only needed props |
| `children` JSX to memo'd component | `children` is always a new object | Memo the children instead, or restructure composition |
| Runtime CSS-in-JS (styled-components, emotion) | Style injection on every render causes "Recalculate Style" overhead | Zero-runtime alternatives: Tailwind CSS, CSS Modules, vanilla-extract |

### State and Effects

| Signal | Risk | Fix |
|---|---|---|
| Object/array in `useEffect` deps | Effect fires every render (infinite loop risk) | Use primitive deps, move object inside effect, or `useMemo` |
| Missing `useEffect` deps (lint warning) | Stale closure reads outdated values | Add deps or use updater functions |
| `useState(expensiveFn())` | Runs every render, not just the first | `useState(() => expensiveFn())` lazy init |
| State too high in tree | Unrelated components re-render | Colocate state closer to consumers |
| Single context with mixed concerns | Theme change re-renders user-only consumers | Split into domain-specific contexts |
| Controlled input in large form | Every keystroke re-renders entire form | Uncontrolled inputs with refs (react-hook-form) |

### Bundle and Loading

| Signal | Risk | Fix |
|---|---|---|
| No route-level code splitting | Entire app loads upfront | `React.lazy` + `Suspense` per route |
| Barrel file imports (`from './index'`) | Can defeat tree shaking (CJS, side-effectful modules, misconfigured bundlers) | Verify `sideEffects: false` in package.json, or import from source files |
| Full library import (`import _ from 'lodash'`) | Entire library in bundle | Import specific functions or use `-es` variant |
| Large component always rendered | Blocks initial paint | Lazy-load below-fold and conditional content |
| Images without `loading="lazy"` | All images fetched on page load | Add `loading="lazy"` to below-fold images |
| Index as `key` in dynamic list | DOM thrashing on reorder; state mismatches | Use stable unique IDs from data |

### High-Frequency Updates

| Signal | Risk | Fix |
|---|---|---|
| `setState` per WebSocket/stream message | Render-per-message overwhelms React | RAF buffer pattern (Tier 1) |
| Frequent style/position updates via state | Layout thrash from re-renders | Direct DOM manipulation via refs (Tier 2) |
| Thousands of DOM nodes in list | Slow paint, high memory | Virtualization (@tanstack/react-virtual, react-window) |
| Heavy computation on main thread | UI freezes during processing | Web Worker with Comlink |
| Mouse/scroll handler updating state | 60+ state updates per second | Throttle, or `useDeferredValue` |

## Profiling Tools

| Tool | Use For |
|---|---|
| React DevTools Profiler | Flamegraph of component render times; "Why did this render?" |
| `React.Profiler` component | Programmatic render timing via `onRender` callback |
| React Scan | Zero-config visual overlay highlighting unnecessary re-renders |
| Chrome Performance tab | JS flamecharts, network waterfall, layout/paint events, React Performance Tracks |
| Lighthouse | High-level performance scoring and Core Web Vitals audit |
| `web-vitals` library | Measure LCP, INP, CLS in production (real-user monitoring) |
| Bundle analyzer | Visualize bundle contents (webpack-bundle-analyzer, source-map-explorer) |

## Alternatives and Extensions

- **Preact** — ~3KB React-compatible alternative with Signals for fine-grained reactivity without top-down re-rendering. Consider for bundle-critical applications.
- **Million.js** — Block virtual DOM compiler (<1KB) that replaces React's diffing with a more efficient approach for highly dynamic components.
- **React Scan** — Drop-in development tool that visually highlights unnecessary re-renders with zero code changes.

## Reference Files

| File | Contents | Read when |
|---|---|---|
| `references/reference.md` | Detailed code patterns for memoization gotchas, context optimization, useEffect pitfalls, virtualization, Canvas/WebGL, Web Workers, form performance, debounce/throttle, flushSync, key prop patterns, SSR/hydration, image optimization, normalized state, and profiling setup | Needing implementation examples, edge-case handling, or deeper explanations beyond the checklists above |
