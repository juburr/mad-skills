# Zustand Version Notes

Release history and behavior changes for `zustand` v5.0.0 through **v5.0.15** (the version this skill is verified against, released 2026-08-13). Use this file to reconcile outdated knowledge: if a pattern you remember is listed under "Stale Patterns", it no longer applies.

## Compatibility

| Zustand | React (React entry points only) | TypeScript | Notes |
|---|---|---|---|
| v5.0.x | 18+ (`react`, `@types/react` are optional peers) | 4.5+ | `use-sync-external-store` peer needed only for `zustand/traditional`; `immer` only for `zustand/middleware/immer` |
| v4.5.x | 16.8+ | — | Maintenance line; receives selected backports |

All v5.0.x releases are API-compatible. Upgrade to the latest 5.0.x; use these floors when a specific fix matters:

| Need | Minimum |
|---|---|
| React Native 0.79+ (Metro package exports, Hermes) | 5.0.4 (or 4.5.7 on v4) |
| `devtools.cleanup()`, inferred DevTools action names, prototype-aware `shallow` | 5.0.5 |
| Awaitable persisted `setState`, `shallow` fix for `undefined` values | 5.0.8 |
| `unstable_ssrSafe` | 5.0.9 |
| Concurrent `persist.rehydrate()` safety | 5.0.10 |
| Immer-typed slices compose without errors | 5.0.11 |
| `onRehydrateStorage` callback receives latest state | 5.0.12 |
| Inferred action names in Firefox/Safari | 5.0.13 |
| `clearStorage()` cancels in-flight hydration | 5.0.15 |

## Stale Patterns (if your Zustand knowledge predates v5.0.5)

- **`useStore(selector, shallow)` on a `create` store** — removed in v5. Use `useShallow(selector)` or `createWithEqualityFn` from `zustand/traditional`.
- **`import create from 'zustand'`** — default exports were removed in v5. Use named imports.
- **`getInitialState` is v5-only** — it was added in v4.5.0 and exists in both lines.
- **Persist writes initial state on creation** — removed in v5.0.0 and v4.5.5. Persist writes only on `setState`.
- **Persisted `setState` returns `void`** — since v5.0.8 it returns the storage's `setItem` result (a Promise for async storage). `useEffect(() => store.setState(x))` now returns that value from the effect.
- **`StateStorage` / `PersistStorage<S>` without a return type parameter** — since v5.0.8 they are `StateStorage<R = unknown>` and `PersistStorage<S, R = unknown>`; `PersistOptions` gained a third `PersistReturn` parameter. Existing annotations still compile because of the defaults.
- **Unnamed DevTools actions always show `anonymous`** — since v5.0.5 the caller name is inferred from the stack trace unless `anonymousActionType` is set.
- **`shallow({}, Object.create(null))` or two class instances with equal fields compare equal** — since v5.0.5 differing prototypes compare `false`.
- **`shallow({ a: undefined }, { b: undefined })` is `true`** — fixed in v5.0.8; key presence is now checked.
- **`ExtractState` must be hand-written** — exported from `zustand` since v5.0.3.
- **`import { devtools } from 'zustand/middleware/devtools'`** (and `.../persist`, `.../combine`, `.../subscribeWithSelector`, `.../redux`) — these paths ship only type declarations, so they type-check but fail at runtime. Import from `zustand/middleware`; only `immer` has its own entry (`zustand/middleware/immer`).
- **Context providers creating stores with `useRef` + null check** — still valid, but the upstream docs now use `const [store] = useState(() => createMyStore())`.
- **Docs URLs under `docs/guides/...`** — the upstream docs were restructured in v5.0.12 into `docs/learn/...` (guides) and `docs/reference/...` (APIs, middlewares, migrations).

## Release Highlights

### v5.0.15 (2026-08-13)
- `persist`: `clearStorage()` invalidates an in-flight async hydration, so the cleared value is not re-applied. The cancelled hydration never sets `hasHydrated()` to `true`.
- `devtools`: action-name inference handles V8 stack lines whose source path contains spaces.
- Docs: `createJSONStorage` documented as a prototyping helper without runtime validation; validate persisted data in production.

### v5.0.14 (2026-05-28)
- `devtools`: improved type inference for the initializer (the slice type `U` is preserved).

### v5.0.13 (2026-05-05)
- `devtools`: action-name inference supports Firefox/Safari stack formats; duplicate module augmentation removed.

### v5.0.12 (2026-03-16)
- `persist`: the post-rehydration `onRehydrateStorage` callback receives `get()` (the latest state) instead of the merged snapshot, so state updated during hydration is not lost.
- `devtools`: corrected the fallback `DevtoolsOptions` config type when `@redux-devtools/extension` types are absent.
- Docs restructured into `docs/learn` and `docs/reference`.

### v5.0.11 (2026-02-01)
- `immer`: added the `U` (slice) type parameter so `StateCreator<Store, [['zustand/immer', never]], [], Slice>` composes into a combined store.
- `persist`: default storage is `window.localStorage` (not the global `localStorage`).
- `devtools`: internal typing improvements.

### v5.0.10 (2026-01-12)
- `persist`: concurrent `rehydrate()` calls no longer race — a hydration version counter discards stale results (last call wins).

### v5.0.9 (2025-11-30)
- New experimental `unstable_ssrSafe` middleware: throws on any `setState` during SSR so module-level stores cannot leak request data.

### v5.0.8 (2025-08-19)
- `persist`: `set`/`setState` return the storage `setItem` result (awaitable for async storage); storage types gained a return-type parameter.
- `shallow`: objects with different keys holding `undefined` no longer compare equal.

### v5.0.7 (2025-07-31)
- `useStore` wraps `getSnapshot` in `useCallback` keyed on `(store, selector)`, letting React skip per-render store bookkeeping when the selector is stable.

### v5.0.6 (2025-06-26)
- `devtools`: stack-trace inference skipped when an explicit action name is passed (performance).
- `zustand/middleware` switched from `export *` to explicit named and type exports (no public names removed).

### v5.0.5 (2025-05-21)
- `devtools`: `store.devtools.cleanup()`; inferred action names for unnamed updates.
- `shallow`: returns `false` for objects with different prototypes.

### v5.0.4 (2025-05-01)
- Packaging: `react-native` export condition resolves the CJS build, fixing `import.meta` errors under Hermes / React Native 0.79+ (backported as v4.5.7).

### v5.0.3 (2025-01-07)
- `ExtractState<typeof store>` type exported.
- Build fix for entry aliases. (v4.5.6, same day, relaxed the `use-sync-external-store` dependency pin.)

### v5.0.2 (2024-12-04)
- `persist`: async `migrate` functions are awaited correctly.
- `devtools`: type error fixed for initializers whose return type differs from the store type.

### v5.0.1 (2024-10-30)
- `shallow`: fixed edge cases comparing iterables and `Map`-like values; entry comparison is order-insensitive.

### v5.0.0 (2024-10-14)
- No new features. Dropped default exports, deprecated APIs (including `destroy`), UMD/SystemJS, and ES5 output.
- React 18 and TypeScript 4.5 minimums; `use-sync-external-store` became a peer dependency.
- `create` no longer accepts equality functions; selectors must return stable references.
- Stricter `setState` types when `replace` is `true`.
- `persist` no longer stores the initial state at creation.

## Unreleased Upstream Changes

After v5.0.15, the upstream `main` branch contains only documentation and CI changes (notably: `create` docs state that `set`, `get`, and the store API cannot be used while the initializer runs). No v6 pre-release has been published.
