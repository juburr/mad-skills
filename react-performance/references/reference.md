# React Performance Reference

Detailed code patterns, edge cases, and deeper explanations for each topic in the main skill file.

## Memoization Deep Dive

### React.memo Gotchas

**Custom comparators must compare ALL props:**

```tsx
function Chart({ data, onClick }) {
  // expensive rendering...
}

// Wrong: ignores onClick — handler changes silently break the component
const MemoizedChart = memo(Chart, (prev, next) => {
  return prev.data === next.data; // Missing onClick comparison
});

// Correct: compare every prop
const MemoizedChart = memo(Chart, (prev, next) => {
  return prev.data === next.data && prev.onClick === next.onClick;
});
```

**Children prop breaks memo** because JSX children create new object references:

```tsx
// Useless: children is always a new object
const WrapperMemo = memo(Wrapper);
<WrapperMemo>
  <Child /> {/* Still re-renders */}
</WrapperMemo>

// Fix: memo the child instead
const ChildMemo = memo(Child);
<Wrapper>
  <ChildMemo />
</Wrapper>
```

**memo does not prevent re-renders from internal state or context changes** — it only prevents re-renders caused by parent prop changes.

**Avoid deep equality in comparators.** `JSON.stringify` is slow and can freeze the UI with large datasets.

### useMemo Patterns

**Arrow function body syntax trap:**

```tsx
// Wrong: returns undefined (braces parsed as block, not object literal)
const opts = useMemo(() => { matchMode: 'whole-word', text }, [text]);

// Correct: wrap object literal in parentheses
const opts = useMemo(() => ({ matchMode: 'whole-word', text }), [text]);
```

**Cannot use hooks in loops — extract a component:**

```tsx
// Wrong: hook called inside map
function ReportList({ items }) {
  return items.map(item => {
    const data = useMemo(() => calculate(item), [item]); // Invalid
    return <Chart data={data} />;
  });
}

// Correct: extract component
function Report({ item }) {
  const data = useMemo(() => calculate(item), [item]);
  return <Chart data={data} />;
}

function ReportList({ items }) {
  return items.map(item => <Report key={item.id} item={item} />);
}
```

### useCallback Patterns

**Use updater functions to reduce dependencies:**

```tsx
// Bad: todos in deps causes frequent re-creation
const handleAdd = useCallback((text) => {
  setTodos([...todos, { id: nextId++, text }]);
}, [todos]);

// Good: updater removes the dependency
const handleAdd = useCallback((text) => {
  setTodos(prev => [...prev, { id: nextId++, text }]);
}, []);
```

**Move functions inside effects when possible:**

```tsx
// Okay: useCallback + effect dependency
const createOptions = useCallback(() => ({
  serverUrl: 'https://localhost:1234',
  roomId
}), [roomId]);

useEffect(() => {
  const conn = createConnection(createOptions());
  conn.connect();
  return () => conn.disconnect();
}, [createOptions]);

// Better: function inside effect, cleaner deps
useEffect(() => {
  const options = { serverUrl: 'https://localhost:1234', roomId };
  const conn = createConnection(options);
  conn.connect();
  return () => conn.disconnect();
}, [roomId]);
```

## Context Optimization

### Splitting State from Dispatch

```tsx
const CartStateContext = createContext(undefined);
const CartDispatchContext = createContext(undefined);

function CartProvider({ children }) {
  const [state, dispatch] = useReducer(cartReducer, { items: [], total: 0 });
  return (
    <CartStateContext.Provider value={state}>
      <CartDispatchContext.Provider value={dispatch}>
        {children}
      </CartDispatchContext.Provider>
    </CartStateContext.Provider>
  );
}

// Only reads dispatch — does NOT re-render when cart state changes
function AddButton({ item }) {
  const dispatch = useContext(CartDispatchContext);
  return <button onClick={() => dispatch({ type: 'ADD', item })}>Add</button>;
}
```

### Context Selectors

React has no built-in context selector. The `use-context-selector` library provides fine-grained subscriptions:

```tsx
import { createContext, useContextSelector } from 'use-context-selector';

const PersonContext = createContext(null);

// Only re-renders when firstName changes, not lastName
function FirstName() {
  const firstName = useContextSelector(PersonContext, (s) => s.firstName);
  return <div>{firstName}</div>;
}
```

## useEffect Dependency Pitfalls

### Object/Array Dependencies Causing Infinite Loops

```tsx
// Bad: infinite loop — options is a new object every render
function ChatRoom({ roomId }) {
  const options = { serverUrl: 'https://localhost:1234', roomId };

  useEffect(() => {
    const conn = createConnection(options);
    conn.connect();
    return () => conn.disconnect();
  }, [options]); // New object every render = infinite reconnections
}

// Fix 1: move object inside the effect
useEffect(() => {
  const options = { serverUrl: 'https://localhost:1234', roomId };
  const conn = createConnection(options);
  conn.connect();
  return () => conn.disconnect();
}, [roomId]); // Primitive dependency

// Fix 2: extract primitive values
useEffect(() => { /* ... */ }, [secret.value]); // Instead of [secret]

// Fix 3: memoize the object
const options = useMemo(() => ({
  serverUrl: 'https://localhost:1234', roomId
}), [roomId]);
useEffect(() => { /* ... */ }, [options]);
```

### Stale Closures from Missing Dependencies

```tsx
// Bad: count is always 0 inside the interval
useEffect(() => {
  const id = setInterval(() => {
    setCount(count + 1); // Stale closure — always reads initial count
  }, 1000);
  return () => clearInterval(id);
}, []); // Missing count dependency

// Fix: updater function avoids the dependency
useEffect(() => {
  const id = setInterval(() => {
    setCount(c => c + 1); // Always reads latest value
  }, 1000);
  return () => clearInterval(id);
}, []);
```

### Over-specifying Dependencies

```tsx
// Bad: effect runs every render because formData is always new
const formData = { name, email };
useEffect(() => {
  saveToLocalStorage(formData);
}, [formData]);

// Good: depend on the actual primitive values
useEffect(() => {
  saveToLocalStorage({ name, email });
}, [name, email]);
```

## Key Prop Patterns

### Index as Key in Dynamic Lists

```tsx
// Bad: state mismatches after reorder/delete
todos.map((todo, index) => <TodoItem key={index} todo={todo} />);

// Good: stable unique IDs
todos.map(todo => <TodoItem key={todo.id} todo={todo} />);
```

Index as key is only acceptable when the list is static (never reordered, filtered, or items added/removed).

### Using Key to Intentionally Reset State

Changing a key forces React to destroy and recreate the component, resetting all internal state:

```tsx
// Reset form state when topic changes
<input key={topic} defaultValue={defaultValuesByTopic[topic]} />
```

### Never Use Unstable Keys

```tsx
// Never: random keys force full remount every render
<Item key={Math.random()} data={item} />
```

## Virtualization

### Library Comparison

| Library | Highlights |
|---|---|
| **@tanstack/react-virtual** | Framework-agnostic, headless (you control markup), most popular |
| **react-window** | Lightweight, FixedSizeList / VariableSizeList / FixedSizeGrid |
| **react-virtuoso** | Auto-handles dynamic heights, infinite scroll, grouped lists |

### @tanstack/react-virtual Example

```tsx
import { useVirtualizer } from '@tanstack/react-virtual';

function VirtualList({ items }) {
  const parentRef = useRef(null);

  const virtualizer = useVirtualizer({
    count: items.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 50,
    overscan: 5,
  });

  return (
    <div ref={parentRef} style={{ height: '400px', overflow: 'auto' }}>
      <div style={{ height: `${virtualizer.getTotalSize()}px`, position: 'relative' }}>
        {virtualizer.getVirtualItems().map((virtualItem) => (
          <div
            key={virtualItem.key}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              height: `${virtualItem.size}px`,
              transform: `translateY(${virtualItem.start}px)`,
            }}
          >
            {items[virtualItem.index]}
          </div>
        ))}
      </div>
    </div>
  );
}
```

### Dynamic Height Items

Use `measureElement` from @tanstack/react-virtual:

```tsx
const virtualizer = useVirtualizer({
  count: items.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 80,
});

// In each virtual item:
<div ref={virtualizer.measureElement} data-index={virtualItem.index}>
  {/* Variable height content */}
</div>
```

React Virtuoso handles dynamic heights automatically without manual measurement.

## Canvas/WebGL Patterns

### react-konva for 2D Canvas

```tsx
import { Stage, Layer, Circle } from 'react-konva';

function DataVisualization({ dataPoints }) {
  return (
    <Stage width={800} height={600}>
      <Layer>
        {dataPoints.map((point, i) => (
          <Circle
            key={i}
            x={point.x}
            y={point.y}
            radius={3}
            fill={point.color}
            listening={false} // Disable event listening for non-interactive shapes
          />
        ))}
      </Layer>
    </Stage>
  );
}
```

Set `listening={false}` on shapes that don't need interactivity to avoid per-shape event overhead.

### react-three-fiber for WebGL/3D

```tsx
import { Canvas } from '@react-three/fiber';

<Canvas frameloop="demand">
  {/* Only re-renders when props change or invalidate() is called */}
  <Scene />
</Canvas>
```

### Instanced Rendering for Massive Object Counts

Reduce thousands of draw calls to one:

```tsx
function Points({ data, temp = new THREE.Object3D() }) {
  const meshRef = useRef();

  useEffect(() => {
    data.forEach((point, i) => {
      temp.position.set(point.x, point.y, point.z);
      temp.updateMatrix();
      meshRef.current.setMatrixAt(i, temp.matrix);
    });
    meshRef.current.instanceMatrix.needsUpdate = true;
  }, [data]);

  return (
    <instancedMesh ref={meshRef} args={[null, null, data.length]}>
      <sphereGeometry args={[0.1, 8, 8]} />
      <meshBasicMaterial />
    </instancedMesh>
  );
}
```

### Adaptive Performance Monitoring

```tsx
const [dpr, setDpr] = useState(1.5);

<Canvas dpr={dpr}>
  <PerformanceMonitor
    onIncline={() => setDpr(2)}
    onDecline={() => setDpr(1)}
    flipflops={3}
    onFallback={() => setDpr(1)}
  >
    <Scene />
  </PerformanceMonitor>
</Canvas>
```

## Web Workers with Comlink

### Basic Pattern

Worker file:

```ts
import * as Comlink from 'comlink';

function sortLargeDataset(data: number[]): number[] {
  return data.sort((a, b) => a - b);
}

Comlink.expose({ sortLargeDataset });
```

React component:

```tsx
function DataProcessor({ rawData }) {
  const workerRef = useRef<Comlink.Remote<WorkerApi> | null>(null);
  const workerInstance = useRef<Worker | null>(null);
  const [result, setResult] = useState(null);

  useEffect(() => {
    workerInstance.current = new Worker(
      new URL('./worker.ts', import.meta.url),
      { type: 'module' }
    );
    workerRef.current = Comlink.wrap<WorkerApi>(workerInstance.current);
    return () => workerInstance.current?.terminate();
  }, []);

  const handleProcess = async () => {
    if (workerRef.current) {
      const sorted = await workerRef.current.sortLargeDataset(rawData);
      setResult(sorted);
    }
  };

  return <button onClick={handleProcess}>Process</button>;
}
```

Key points:
- All sync functions become Promise-based when wrapped with Comlink
- Initialize workers in `useEffect` (not during SSR)
- Always `terminate()` workers on cleanup
- Use `vite-plugin-comlink` for Vite integration

## Form Performance

### Controlled vs Uncontrolled

Controlled inputs (`value` + `onChange`) trigger a state update and re-render on every keystroke. In large forms, this re-renders the entire form component tree per keystroke.

Uncontrolled inputs hold state in the DOM and read it via refs on demand (e.g., on submit). Zero re-renders during typing.

### react-hook-form Pattern

```tsx
import { useForm } from 'react-hook-form';

function FastForm() {
  const { register, handleSubmit } = useForm();
  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input {...register('name')} />
      <input {...register('email')} />
      <button type="submit">Submit</button>
    </form>
  );
}
```

For controlled third-party components, `Controller` wraps them with scoped re-rendering:

```tsx
import { useForm, Controller } from 'react-hook-form';

<Controller
  name="date"
  control={control}
  render={({ field }) => <DatePicker {...field} />}
/>
```

Isolate form state within the form component. Never lift form field state to a parent or global store.

## Debounce and Throttle

### Debouncing Search Input

```tsx
import { useState, useMemo, useEffect, useRef } from 'react';
import debounce from 'lodash.debounce';

function SearchInput({ onSearch }) {
  const [displayValue, setDisplayValue] = useState('');
  const onSearchRef = useRef(onSearch);
  onSearchRef.current = onSearch;

  const debouncedSearch = useMemo(
    () => debounce((query) => onSearchRef.current(query), 300),
    [] // Truly stable — reads latest callback via ref
  );

  useEffect(() => {
    return () => debouncedSearch.cancel();
  }, [debouncedSearch]);

  const handleChange = (e) => {
    setDisplayValue(e.target.value);
    debouncedSearch(e.target.value);
  };

  return <input value={displayValue} onChange={handleChange} />;
}
```

Use a ref to capture the latest callback so the debounced function is created once and never recreated when the parent passes a new callback identity. This preserves the pending timer across re-renders.

### Throttling Scroll Handlers

```tsx
import { useEffect, useMemo } from 'react';
import throttle from 'lodash.throttle';

function useThrottledScroll(callback, delay = 100) {
  const throttled = useMemo(
    () => throttle(callback, delay, { leading: true, trailing: true }),
    [callback, delay]
  );

  useEffect(() => {
    window.addEventListener('scroll', throttled, { passive: true });
    return () => {
      window.removeEventListener('scroll', throttled);
      throttled.cancel();
    };
  }, [throttled]);
}
```

### useDeferredValue vs Debounce/Throttle

| | useDeferredValue | Debounce/Throttle |
|---|---|---|
| **Reduces re-renders** | Yes (defers rendering) | No (reduces function calls) |
| **Reduces HTTP requests** | No | Yes |
| **Fixed delay** | No (adaptive, React-managed) | Yes (configurable) |
| **Interruptible** | Yes (concurrent rendering) | No |
| **Use for** | Expensive re-renders from fast input | Rate-limiting API calls and side effects |

## flushSync

Force synchronous DOM update when you need immediate DOM access after a state change:

```tsx
import { flushSync } from 'react-dom';

function TodoList() {
  const [todos, setTodos] = useState([]);
  const listRef = useRef(null);

  const handleAdd = (text) => {
    flushSync(() => {
      setTodos([...todos, { id: Date.now(), text }]);
    });
    // DOM is now updated — safe to scroll
    listRef.current.lastChild.scrollIntoView({ behavior: 'smooth' });
  };

  return (
    <ul ref={listRef}>
      {todos.map(todo => <li key={todo.id}>{todo.text}</li>)}
    </ul>
  );
}
```

**Caveats:**
- Bypasses batching — use as a last resort
- Group multiple state updates inside a single `flushSync` call
- Cannot be called during render or inside `useEffect`
- May flush unrelated pending updates for consistency
- Prefer `useLayoutEffect` for post-render DOM measurement

## useSyncExternalStore

### Basic Pattern

```tsx
import { useSyncExternalStore } from 'react';

function useOnlineStatus() {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

function subscribe(callback) {
  window.addEventListener('online', callback);
  window.addEventListener('offline', callback);
  return () => {
    window.removeEventListener('online', callback);
    window.removeEventListener('offline', callback);
  };
}

function getSnapshot() {
  return navigator.onLine;
}

function getServerSnapshot() {
  return true; // SSR fallback
}
```

### Media Query Hook

```tsx
function useMediaQuery(query) {
  return useSyncExternalStore(
    (callback) => {
      const mql = window.matchMedia(query);
      mql.addEventListener('change', callback);
      return () => mql.removeEventListener('change', callback);
    },
    () => window.matchMedia(query).matches,
    () => false
  );
}
```

Define `subscribe` and `getSnapshot` outside the component or memoize them to prevent resubscription on every render.

## Normalized State

### Entity Maps vs Nested State

Normalized state treats the store like a relational database with `byId` lookups:

```ts
// Nested (problematic): updating a comment forces new references up the entire tree
const posts = [{ id: 'p1', comments: [{ id: 'c1', text: '...' }] }];

// Normalized (optimal): O(1) lookups, minimal re-render cascading
const state = {
  posts: { byId: { p1: { id: 'p1', commentIds: ['c1'] } }, allIds: ['p1'] },
  comments: { byId: { c1: { id: 'c1', text: '...' } }, allIds: ['c1'] },
};
```

Updating `comments.byId.c1` only creates new references for that comment and the comments slice — the posts slice reference stays the same, so components rendering posts skip re-renders.

### Structural Sharing with Immer

Immer preserves references to unchanged state subtrees:

```ts
import { produce } from 'immer';

const next = produce(state, draft => {
  draft.posts.byId.p1.title = 'New';
});

next.comments === state.comments; // true — shared reference
next.posts.byId.p1 === state.posts.byId.p1; // false — changed
```

## SSR and Hydration

### Hydration Cost

Traditional SSR renders the full application on the server, then hydrates the entire component tree on the client. The hydration delay grows with component count and blocks interactivity until complete.

### Selective Hydration with Suspense

React 18+ supports selective hydration with Suspense boundaries:

```tsx
<Suspense fallback={<NavSkeleton />}>
  <Navigation />       {/* Hydrates first */}
</Suspense>

<Suspense fallback={<ContentSkeleton />}>
  <MainContent />      {/* Hydrates second */}
</Suspense>

<Suspense fallback={<SidebarSkeleton />}>
  <Sidebar />          {/* Hydrates last */}
</Suspense>
```

React prioritizes hydrating components the user attempts to interact with.

### React Server Components

Server Components render entirely on the server with zero client-side JavaScript. They can directly access databases and backend resources:

- Server components can render client components and pass serializable props
- Client components cannot import server components but can receive them as `children`
- Only Client Components (marked with `'use client'`) are hydrated on the client

## Image Optimization

### Lazy Loading

```html
<!-- Native lazy loading -->
<img src="image.jpg" loading="lazy" alt="Description" />
```

Use `loading="lazy"` on all below-fold images. For above-fold LCP images, omit `loading="lazy"` and consider `fetchpriority="high"`.

### Responsive Images

```html
<img
  srcset="image-320w.jpg 320w, image-640w.jpg 640w, image-1280w.jpg 1280w"
  sizes="(max-width: 600px) 100vw, (max-width: 1200px) 50vw, 33vw"
  src="image-640w.jpg"
  alt="Responsive"
/>
```

### Format Selection

AVIF compresses ~20% smaller than WebP but takes longer to encode. WebP is recommended for most use cases. Serve both for best coverage via `<picture>` or framework image components.

## Bundle Optimization

### Barrel File Risks

Barrel files (`index.ts` re-exporting everything) can defeat tree shaking when modules use CJS, contain side effects, or lack `"sideEffects": false` in package.json. Modern ESM bundlers can tree-shake barrel re-exports when properly configured, but barrel files still add dev server startup overhead (especially Vite) and can obscure dependency graphs.

```ts
// Risk: may pull unused exports depending on bundler config and module format
import { Button } from '@company/ui';

// Safer: bypasses barrel entirely
import { Button } from '@company/ui/Button';
```

Verify tree shaking effectiveness with a bundle analyzer rather than assuming barrel files are always problematic.

### Dynamic Imports

Bundlers (Webpack, Vite, Rollup) detect `import()` calls automatically. Each split chunk bundles the component plus its unique dependencies. Shared libraries are typically extracted into separate common or vendor chunks by the bundler's splitting strategy.

Wrap lazy-loaded components in error boundaries for resilience:

```tsx
<ErrorBoundary fallback={<p>Failed to load.</p>}>
  <Suspense fallback={<Loading />}>
    <LazyComponent />
  </Suspense>
</ErrorBoundary>
```

### Library Import Hygiene

```ts
// Bad: imports entire lodash (~70KB)
import _ from 'lodash';

// Good: imports only debounce (~2KB)
import debounce from 'lodash/debounce';

// Also good: tree-shakeable ES module variant
import { debounce } from 'lodash-es';
```

## Profiling Setup

### React DevTools Profiler

Enable "Record why each component rendered while profiling" in DevTools settings. The flamegraph shows render time by color (yellow = slow, blue = fast, gray = skipped). The ranked chart orders by individual render time (excluding children).

### React.Profiler Component

```tsx
<Profiler id="Sidebar" onRender={onRender}>
  <Sidebar />
</Profiler>

function onRender(id, phase, actualDuration, baseDuration, startTime, commitTime) {
  // id: profiler tree identifier
  // phase: "mount" | "update" | "nested-update"
  // actualDuration: ms spent rendering (with memoization)
  // baseDuration: estimated ms without memoization
  // startTime: when React began rendering
  // commitTime: when React committed the update
}
```

Profiling is disabled in production builds by default. Use `react-dom/profiling` for production profiling.

### React Scan

Zero-config installation:

```bash
npx -y react-scan@latest init
```

Highlights unnecessary re-renders with colored outlines. The `trackUnnecessaryRenders` option marks renders that produced no DOM changes.

### web-vitals Library

```ts
import { onCLS, onINP, onLCP } from 'web-vitals';

function sendToAnalytics(metric) {
  const body = JSON.stringify({
    name: metric.name,
    value: metric.value,
    delta: metric.delta,
    id: metric.id,
  });
  navigator.sendBeacon('/analytics', body);
}

onCLS(sendToAnalytics);
onINP(sendToAnalytics);
onLCP(sendToAnalytics);
```

### Passive Event Listeners

Mark event listeners as passive when the handler never calls `preventDefault()` — allows the browser to scroll without waiting:

```tsx
window.addEventListener('wheel', handleWheel, { passive: true });
window.addEventListener('touchmove', handleTouch, { passive: true });
```

Events that benefit from `passive: true`: `touchstart`, `touchmove`, `touchend`, `wheel`. The `scroll` event itself cannot be canceled, so passive is irrelevant for it.
