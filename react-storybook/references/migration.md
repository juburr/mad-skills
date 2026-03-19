# Storybook Migration Guide

Step-by-step instructions for upgrading across major Storybook versions. Covers every major transition from the original `@kadira/storybook` (v2) through v10.

**Golden rules:**

- Upgrade **one major version at a time** (exception: 6 → 8 can be direct).
- Always run upgrade commands from the **repository root**.
- Always use the official upgrade tool — manual version bumps miss automigrations.

## Upgrade Command (v6.4+)

The automated upgrade tool was introduced in v6.4. For all upgrades from 6.4 onward:

```bash
npx storybook@latest upgrade
```

This automatically: detects all Storybook projects (including monorepo packages), runs automigrations, and provides guidance for manual steps. Always start here.

Post-upgrade:

```bash
npx storybook@latest doctor         # health check
npx storybook@latest automigrate    # re-run if needed
npx storybook@latest migrate --list # list available codemods
```

In monorepos, use `STORYBOOK_PROJECT_ROOT` to limit scope if needed.

---

## 2.x → 3.x

The `@kadira/storybook` project was donated to the community and rebranded.

### Breaking Changes

- **Package rename**: All packages changed from `@kadira/*` to `@storybook/*`.
- **Webpack 2**: Upgraded from Webpack 1 to Webpack 2. Custom webpack config functions receive a Webpack 2 config object.
- **Embedded addons deprecated**: Built-in addons removed from core. Install them separately (e.g., `@storybook/addon-actions`, `@storybook/addon-links`).

### Migration Steps

1. Replace all `@kadira/storybook` imports/dependencies with `@storybook/react`
2. Replace `@kadira/storybook-addons` with `@storybook/addons`
3. Replace other `@kadira/storybook-addon-*` packages with `@storybook/addon-*`
4. Update any custom webpack config for Webpack 2 compatibility
5. Install any previously built-in addons as separate packages

---

## 3.x → 4.x

### Breaking Changes

- **React 16.3+ required**: Storybook's UI adopted Emotion, requiring React 16.3+.
- **Webpack 4 + Babel 7**: Major toolchain upgrade. Custom webpack configs may need updates.
- **Story parameters introduced**: New API for passing metadata to addons (backgrounds, viewport, etc.).
- **Generic addons**: Addons became framework-agnostic rather than framework-specific.
- **React Native packager removed**: RN packager and built-in RN addons removed from core.

### Migration Steps

1. Update React to 16.3+
2. Update custom webpack configs for Webpack 4 compatibility
3. Update custom Babel configs for Babel 7 compatibility
4. Install any React Native addons separately if needed

---

## 4.x → 5.x

### Breaking Changes

- **Webpack config full control mode changed**: Custom `webpack.config.js` function signature changed (old `(baseConfig, mode, defaultConfig)` → new `({ config, mode })`).
- **Theming overhaul**: Complete rewrite of theming API. Themes now use `create()` from `@storybook/theming`.
- **Story hierarchy defaults changed**: Story sorting and hierarchy behavior updated.
- **Options addon deprecated**: Replaced with global parameters (`parameters` export in `preview.js`). Backward compatibility maintained until 6.0.
- **URL structure changed**: Story URLs use new ID format.
- **Keyboard shortcuts changed**: New shortcut scheme.
- **`--secure` flag renamed to `--https`**.

### Key Additions in 5.x

- **5.2**: **Component Story Format (CSF)** introduced — the ES module format that became Storybook's standard. `storySort` option for controlling sidebar order.
- **5.3**: New declarative config files: `main.js`, `preview.js`, `manager.js` (replacing `config.js`, `addons.js`, `presets.js`).

### Migration Steps

1. Update custom webpack configs to new function signature
2. Migrate theming code to new `create()` API
3. Replace `@storybook/addon-options` with `parameters`
4. Update any URL-dependent code for new story ID format
5. (5.3) Migrate from `config.js`/`addons.js` to `main.js`/`preview.js` (optional but strongly recommended — this becomes required in later versions)

---

## 5.x → 6.x

A major release introducing Args, Controls, and the modern story authoring model.

### Breaking Changes

- **Hoisted CSF annotations**: Story metadata syntax changed.

  ```typescript
  // Old (5.x) — metadata attached to story function
  Basic.story = { name: 'My Story', parameters: { ... } };

  // New (6.x) — hoisted to top level
  Basic.storyName = 'My Story';
  Basic.parameters = { ... };
  ```

- **Args passed as first argument**: Story functions now receive `args` as the first parameter.

  ```typescript
  // Old (5.x)
  export const Basic = () => <Button label="hello" />;

  // New (6.x)
  export const Basic = (args) => <Button {...args} />;
  Basic.args = { label: 'hello' };
  ```

- **Deprecated addons removed**: `addon-info`, `addon-notes`, `addon-contexts`, `addon-centered` no longer supported. Replace with `addon-docs` or `layout: 'centered'` parameter.
- **Hierarchy separators simplified**: Only `/` supported. A codemod handles conversion.
- **CRA support extracted**: Built-in Create React App support moved to `@storybook/preset-create-react-app`.
- **`addParameters`/`addDecorator` deprecated**: Use declarative `parameters`/`decorators` exports in `preview.js`.
- **New addon presets**: `addon-actions`, `addon-backgrounds`, `addon-knobs`, `addon-links` now include built-in presets that may conflict with manual registration.
- **Docs breaking changes**: `Preview` → `Canvas`, `Props` → `ArgsTable`, DocsPage slots concept removed, docs theming separated.

### Key Additions in 6.x

- **6.0**: Args, Controls, `addon-essentials` bundle, Composition, zero-config TypeScript.
- **6.1**: React 17 support, async loaders API, fast search.
- **6.2**: Vue 3, Webpack 5 (experimental), pluggable bundlers, ESM support.
- **6.3**: Webpack 5 stable, Vite community builder, `addon-knobs` deprecated.
- **6.4**: **CSF3** (object stories), **play functions**, Story Store v7 (opt-in), automigrate tool.
- **6.5**: Webpack 5 lazy compilation, Vite builder stable, React 18 support, opt-in MDX2.

### Migration Steps

1. Run `npx sb upgrade` (or manually update dependencies for pre-6.4)
2. Update CSF annotations to hoisted format (codemod: `npx storybook@latest migrate upgrade-hierarchy-separators`)
3. Adopt args pattern for new stories (existing `storiesOf` still works)
4. Replace `addon-info`/`addon-notes` with `addon-docs`
5. Replace `addon-centered` with `parameters: { layout: 'centered' }`
6. Move from `addParameters`/`addDecorator` to declarative exports in `preview.js`
7. Add `@storybook/preset-create-react-app` if using CRA
8. Install `@storybook/addon-essentials` to replace individual addon installations

---

## 6.x → 7.x

A major architectural overhaul introducing the Framework API and going ESM-first.

### Prerequisites

- Node.js 16+ (Node 14 dropped)

### Breaking Changes

- **`framework` field required** in `.storybook/main.js`. This is a new concept — framework packages bundle renderer + builder + framework config.

  ```javascript
  // Old (6.x)
  module.exports = {
    stories: ['../src/**/*.stories.@(js|tsx)'],
    addons: ['@storybook/addon-essentials'],
    core: { builder: 'webpack5' },
  };

  // New (7.x)
  module.exports = {
    stories: ['../src/**/*.stories.@(js|tsx)'],
    addons: ['@storybook/addon-essentials'],
    framework: '@storybook/react-webpack5', // or @storybook/react-vite
    // No more core.builder — framework includes it
  };
  ```

- **CLI binaries renamed**:

  ```bash
  # Old (6.x)
  start-storybook -p 6006
  build-storybook -o storybook-static

  # New (7.x)
  storybook dev -p 6006
  storybook build -o storybook-static
  ```

- **Webpack 4 dropped**: Only Webpack 5 or Vite supported.
- **Babel mode v7 exclusively**: No Babel 6 compatibility.
- **IE11 dropped**: Code transpiled for Chrome >= 100, no polyfills shipped.
- **ESM-first approach**: No CommonJS polyfills shipped. TypeScript config (`main.ts`) supported.
- **`storiesOf` deprecated**: Still functional via `storyStoreV6` compat flag, fully removed in 8.0.
- **MDX2 default**: Breaking syntax changes from MDX1. MDX1 compat available via `@storybook/mdx1-csf`.
- **`*.stories.mdx` deprecated**: Should be split into CSF stories (`.stories.ts`) + MDX docs (`.mdx`).

**Package consolidation:**

| Old Package (6.x) | New Package (7.x) |
|---|---|
| `@storybook/addons` | Split: `@storybook/preview-api` + `@storybook/manager-api` |
| `@storybook/client-api` | `@storybook/preview-api` |
| `@storybook/store` | `@storybook/preview-api` |
| `@storybook/api` | `@storybook/manager-api` |
| `@storybook/preview-web` | `@storybook/preview-api` |
| `@storybook/channel-postmessage` | `@storybook/channels` |
| `@storybook/channel-websocket` | `@storybook/channels` |

**Framework packages** (choose one based on your renderer + builder):

| Framework | Use when |
|---|---|
| `@storybook/react-vite` | React + Vite |
| `@storybook/react-webpack5` | React + Webpack 5 |
| `@storybook/nextjs` | Next.js (webpack-based) |
| `@storybook/vue3-vite` | Vue 3 + Vite |
| `@storybook/vue3-webpack5` | Vue 3 + Webpack 5 |
| `@storybook/angular` | Angular |
| `@storybook/svelte-vite` | Svelte + Vite |
| `@storybook/svelte-webpack5` | Svelte + Webpack 5 |
| `@storybook/sveltekit` | SvelteKit |
| `@storybook/web-components-vite` | Web Components + Vite |
| `@storybook/web-components-webpack5` | Web Components + Webpack 5 |

**Type renames:**

| Old Type | New Type |
|---|---|
| `Story` | `StoryFn` or `StoryObj` |
| `ComponentStory` | `StoryObj` |
| `ComponentMeta` | `Meta` |
| `DecoratorFn` | `Decorator` |
| `XFramework` | `XRenderer` |

**Root HTML ID changed**: `#root` → `#storybook-root`. Update any selectors targeting the story root.

**Autodocs**: Documentation pages now appear in sidebar via the `autodocs` tag (replaces addon-docs page generation config).

### Available Codemods

```bash
npx storybook@latest migrate csf-2-to-3 --glob="**/*.stories.tsx"
npx storybook@latest migrate mdx-to-csf --glob="**/*.stories.mdx"
```

### Migration Steps

1. Run `npx storybook@latest upgrade` from repo root
2. Review and accept automigrations (framework field, builder packages, etc.)
3. Update old package imports (`@storybook/addons` → `@storybook/preview-api` / `@storybook/manager-api`)
4. Remove standalone builder packages (`@storybook/builder-webpack5`, `@storybook/manager-webpack5`)
5. Update CLI scripts: `start-storybook` → `storybook dev`, `build-storybook` → `storybook build`
6. If using MDX: resolve MDX2 syntax issues or install `@storybook/mdx1-csf` for compat
7. Split any `*.stories.mdx` files into `.stories.ts` + `.mdx`
8. Update TypeScript types (`Story` → `StoryFn`/`StoryObj`, etc.)
9. Update any `#root` CSS selectors to `#storybook-root`
10. Run `npx storybook@latest doctor`
11. Verify: `npm run storybook`

---

## 7.x → 8.x

### Prerequisites

- Node.js 18+ (Node 16 dropped)

### Breaking Changes

**Removed APIs** — these were deprecated in 7.x and are now gone:

| Removed | Replacement | Codemod |
|---|---|---|
| `storiesOf` API | CSF (default + named exports) | `npx storybook@latest migrate storiesof-to-csf --glob="**/*.stories.tsx"` |
| `*.stories.mdx` format | CSF stories + separate MDX docs | `npx storybook@latest migrate mdx-to-csf --glob="**/*.stories.mdx"` |
| Storyshots | Interaction tests, visual tests, test-runner | Manual migration |
| Knobs addon (no v8-compatible release) | Controls (built-in args/controls) | Manual migration |
| `@storybook/testing-library` | `@storybook/test` | Import path update |
| `@storybook/jest` | `@storybook/test` | Import path update |
| CSF2 template pattern (still works, but CSF3 preferred) | CSF3 object stories | `npx storybook@latest migrate csf-2-to-3 --glob="**/*.stories.tsx"` |

**Deprecated shim packages removed**: `@storybook/addons`, `@storybook/client-api`, `@storybook/preview-web`, `@storybook/store`. These were kept as shims in 7.x but are now gone.

**Testing consolidation:**

```typescript
// Old (7.x) — two separate packages
import { expect } from '@storybook/jest';
import { userEvent, within } from '@storybook/testing-library';

// New (8.x) — single package
import { expect, fn, userEvent, within } from '@storybook/test';
```

**Implicit actions changed**: `argTypesRegex`-based automatic actions no longer fire during rendering or play functions. Use `fn()` from `@storybook/test` to create explicit spy functions in args. Actions panel display for non-spy callbacks still works.

**MDX3**: Upgraded from MDX2 to MDX3. MDX1 compat (`@storybook/mdx1-csf`) no longer available.

**Docgen default changed**: `react-docgen` is now the default (faster, less complete). To restore full prop inference:

```typescript
const config: StorybookConfig = {
  typescript: {
    reactDocgen: 'react-docgen-typescript',
  },
};
```

**Babel removal**: `@babel/core` and `babel-loader` removed from the webpack5 builder. If your project requires Babel, install it separately.

**Webpack5 builder**: `useSWC` option removed. `fastRefresh` option removed.

**UI layout state changed**: `showNav`/`showPanel` → pixel-based `navSize`/`bottomPanelHeight`/`rightPanelWidth`.

### Migration Steps

1. Run `npx storybook@latest upgrade` from repo root
2. Review and accept automigrations
3. Run `npx storybook@latest doctor` to check for issues
4. If you had `storiesOf`, `*.stories.mdx`, or Storyshots, run the appropriate codemods
5. Update test imports from `@storybook/jest` + `@storybook/testing-library` to `@storybook/test`
6. Replace any remaining Knobs usage with args/controls
7. Add `fn()` to callback args where implicit actions were relied upon
8. Update any remaining `@storybook/addons` imports to `@storybook/preview-api` / `@storybook/manager-api`
9. Verify Storybook starts: `npm run storybook`

---

## 8.x → 9.x

### Prerequisites

- Node.js 20+ (Node 18 dropped)
- Vite 5+ (Vite 4 dropped)
- TypeScript 4.9+
- npm 10+, pnpm 9+, or yarn 4+
- Next.js 14.1+ (if applicable)
- Vitest 3+ (if using test addon)
- Svelte 5+ (if applicable)
- Angular 18+ (if applicable)

### Package Consolidation

The biggest change — many packages moved or were absorbed into core.

**Import path changes:**

```typescript
// Old (8.x)                                            // New (9.x+)
import { fn } from '@storybook/test';                   // import { fn } from 'storybook/test';
import { action } from '@storybook/addon-actions';      // import { action } from 'storybook/actions';
import { useArgs } from '@storybook/preview-api';       // import { useArgs } from 'storybook/preview-api';
import { addons } from '@storybook/manager-api';        // import { addons } from 'storybook/manager-api';
import { styled } from '@storybook/theming';            // import { styled } from 'storybook/theming';
```

**Full package mapping:**

| Old Package (8.x) | New Path (9.x+) |
|---|---|
| `@storybook/test` | `storybook/test` |
| `@storybook/addon-actions` | `storybook/actions` |
| `@storybook/addon-viewport` | `storybook/viewport` |
| `@storybook/addon-highlight` | `storybook/highlight` |
| `@storybook/manager-api` | `storybook/manager-api` |
| `@storybook/preview-api` | `storybook/preview-api` |
| `@storybook/theming` | `storybook/theming` |
| `@storybook/addon-essentials` | Removed (features now in core) |
| `@storybook/addon-controls` | Removed (core feature) |
| `@storybook/addon-interactions` | Removed (core feature) |
| `@storybook/addon-backgrounds` | Removed (core feature) |
| `@storybook/addon-measure` | Removed (core feature) |
| `@storybook/addon-outline` | Removed (core feature) |
| `@storybook/addon-toolbars` | Removed (core feature) |
| `@storybook/blocks` | `@storybook/addon-docs/blocks` |

**Addon changes:**

```typescript
// .storybook/main.ts — before (8.x)
addons: [
  '@storybook/addon-essentials',
  '@storybook/experimental-addon-test',
  '@storybook/addon-storysource',
],

// .storybook/main.ts — after (9.x)
addons: [
  '@storybook/addon-docs',   // only if you want docs
  '@storybook/addon-a11y',   // if needed
  '@storybook/addon-vitest', // renamed from experimental-addon-test
],
// viewport, controls, interactions, actions are now built-in
```

**Config changes:**

```typescript
// preview.ts — globals renamed to initialGlobals
// Old (8.x)
const preview: Preview = {
  globals: { theme: 'light' },
};

// New (9.x)
const preview: Preview = {
  initialGlobals: { theme: 'light' },
};
```

**A11y addon:**

```typescript
// Old (8.x)
parameters: { a11y: { element: '#my-target' } }

// New (9.x)
parameters: { a11y: { context: '#my-target' } }
```

**`experimental_afterEach` stabilized** to `afterEach`.

**`autodocs` config option removed**: Use `tags: ['autodocs']` in preview.ts or per-component.

**Storysource addon removed.** Use the built-in Code Panel in the docs addon.

**Framework removals** (webpack5 builders dropped for these; React webpack5 still supported):
- `@storybook/svelte-webpack5` → `@storybook/svelte-vite`
- `@storybook/preact-webpack5` → `@storybook/preact-vite`
- `@storybook/vue3-webpack5` → `@storybook/vue3-vite`
- `@storybook/web-components-webpack5` → `@storybook/web-components-vite`
- `@storybook/html-webpack5` → `@storybook/html-vite`

**`@storybook/experimental-nextjs-vite` stabilized** to `@storybook/nextjs-vite`.

**Framework-based imports replace renderer-based**: Import types from framework packages (e.g., `@storybook/react-vite`) instead of renderer packages (e.g., `@storybook/react`).

### Migration Steps

1. Check all prerequisites (Node 20+, Vite 5+, TS 4.9+, etc.)
2. Run `npx storybook@latest upgrade` from repo root
3. Review and accept automigrations
4. Update imports from `@storybook/*` to `storybook/*` paths (see table)
5. Remove `@storybook/addon-essentials` from addons; keep only `@storybook/addon-docs` and `@storybook/addon-a11y`
6. Rename `@storybook/experimental-addon-test` to `@storybook/addon-vitest`
7. Replace `globals` with `initialGlobals` in preview.ts
8. Replace `a11y: { element }` with `a11y: { context }` if used
9. Replace `experimental_afterEach` with `afterEach`
10. If using a removed webpack5 framework, migrate to the Vite equivalent
11. Run `npx storybook@latest doctor`
12. Verify: `npm run storybook`

---

## 9.x → 10.x

### Prerequisites

- Node.js **20.19+** or **22.12+** (stricter than 9.x)
- `tsconfig.json` `moduleResolution` must support `types` condition (`"Bundler"`, `"NodeNext"`, or `"Node16"`)

### ESM-Only Distribution

The primary breaking change. All Storybook packages are ESM-only.

**.storybook/main.ts must be valid ESM:**

```typescript
// ❌ CommonJS (no longer works)
module.exports = { ... };
const path = require('path');

// ✅ ESM
export default { ... };
import path from 'node:path';
```

If you need `__dirname` or `require` in ESM:

```typescript
import { createRequire } from 'node:module';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const require = createRequire(import.meta.url);
```

**Extensionless relative imports no longer work** in JS config files:

```typescript
// ❌ Old
import myPreset from './my-file';

// ✅ New — extension required
import myPreset from './my-file.js';
```

**Local addon resolution changed:**

```typescript
// Old (9.x)
addons: ['./my-addon.ts'],

// New (10.x) — must use import.meta.resolve
addons: [import.meta.resolve('./my-addon.ts')],
```

**core.builder must be a fully resolved path:**

```typescript
// Old (9.x)
core: { builder: '@storybook/builder-vite' },

// New (10.x)
core: { builder: import.meta.resolve('@storybook/builder-vite') },
```

**Removed x-only tags:**

```typescript
// Old (9.x)
tags: ['dev-only']     // → tags: ['dev', '!test', '!autodocs']
tags: ['docs-only']    // → tags: ['autodocs', '!dev', '!test']
tags: ['test-only']    // → tags: ['test', '!dev', '!autodocs']
```

### Migration Steps

1. Check Node.js version: must be **20.19+** or **22.12+**
2. Check `tsconfig.json`: `moduleResolution` must be `"Bundler"`, `"NodeNext"`, or `"Node16"`
3. Run `npx storybook@latest upgrade` from repo root
4. Review and accept automigrations
5. Convert any CommonJS config to ESM (see examples above)
6. Add file extensions to relative imports in config files
7. Update local addon paths to use `import.meta.resolve()`
8. Replace `-only` tags with explicit tag combinations
9. Run `npx storybook@latest doctor`
10. Verify: `npm run storybook`

---

## Test Runner → Vitest Addon Migration

Only applicable for **Vite-based frameworks** (react-vite, nextjs-vite, vue3-vite, svelte-vite, web-components-vite).

```bash
# 1. Remove old test dependencies
npm uninstall @storybook/test-runner @storybook/addon-coverage

# 2. Remove old config files
rm -f test-runner-jest.config.js .storybook/test-runner.ts

# 3. Install Vitest addon
npx storybook add @storybook/addon-vitest

# 4. Update package.json scripts
```

```json
{
  "scripts": {
    "test-storybook": "vitest --project=storybook"
  }
}
```

Update CI workflows: replace the build → serve → test-storybook pattern with `vitest --project=storybook` (no running Storybook instance needed).

---

## Multi-Version Jump Checklists

Upgrade one version at a time. Verify Storybook starts and tests pass at each step before proceeding.

### 5.x → 10.x (Five Steps)

| Step | Key Actions | Verify |
|---|---|---|
| **5 → 6** | Adopt `main.js`/`preview.js` config. Hoist CSF annotations. Replace addon-info/notes with addon-docs. Install addon-essentials. | Storybook starts |
| **6 → 7** | Add `framework` field. Remove standalone builder packages. Rename CLI (`storybook dev`/`build`). Update package imports. Handle MDX2. Update types. | Storybook starts |
| **7 → 8** | Remove storiesOf, *.stories.mdx, Storyshots, Knobs. Consolidate test imports to `@storybook/test`. Add explicit `fn()` for actions. | Storybook starts, tests pass |
| **8 → 9** | Update imports (`@storybook/*` → `storybook/*`). Remove essentials addon. Rename `globals` → `initialGlobals`. | Storybook starts, tests pass |
| **9 → 10** | Convert config to ESM. Update Node to 20.19+/22.12+. Fix moduleResolution. Resolve local addons. | Storybook starts, builds succeed |

### 6.x → 10.x (Special Case)

Storybook supports a direct **6 → 8** jump, skipping 7.x:

| Step | Key Actions |
|---|---|
| **6 → 8** | `npx storybook@8 upgrade` (handles both 6→7 and 7→8 changes). All breaking changes from both transitions apply. |
| **8 → 9** | See 8.x → 9.x section |
| **9 → 10** | See 9.x → 10.x section |

### 3.x/4.x → 10.x

For projects on very old versions, manually upgrade to 5.x first (update packages, adopt CSF), then follow the 5 → 10 checklist above. The automated upgrade tool is only available from 6.4+.

---

## Common Pitfalls

1. **Skipping `npx storybook@latest upgrade`**: Always use the official upgrade command. Manual version bumps miss automigrations and codemods.
2. **Multi-major jumps**: Never skip versions (except 6→8). Each version has breaking changes that build on the previous.
3. **Wrong working directory**: Always run upgrade from the **repository root**, not from a package subdirectory. The tool is monorepo-aware.
4. **Stale lockfile**: After upgrade, delete your lockfile and reinstall to avoid version conflicts between old and new Storybook packages.
5. **Community addon compatibility**: Community addons lag behind Storybook releases. Remove non-`@storybook` addons temporarily to isolate upgrade issues, then add them back once Storybook itself works.
6. **CommonJS lingering in 10.x**: Any `module.exports` or `require()` in `.storybook/` config will break. Also check presets and custom addons.
7. **Test infrastructure mismatch**: The Vitest addon only works with Vite-based frameworks. Webpack projects must keep the test-runner.
8. **Import path confusion in 9.x+**: Some imports moved from `@storybook/*` to `storybook/*`. Old paths may work as aliases temporarily but should be migrated.
9. **MDX syntax breaks**: MDX1 → MDX2 (in 7.x) and MDX2 → MDX3 (in 8.x) each have syntax differences. Watch for JSX expression handling changes.
10. **`#root` → `#storybook-root`**: If you have CSS or test selectors targeting the story root element, update them (changed in 7.0).

---

## Dependency Requirements by Version

| Dependency | 3.x | 4.x | 5.x | 6.x | 7.x | 8.x | 9.x | 10.x |
|---|---|---|---|---|---|---|---|---|
| Node.js | 6+ | 8+ | 8+ | 10+ | 16+ | 18+ | 20+ | 20.19+ / 22.12+ |
| Webpack | 2 | 4 | 4 | 4-5 | 5 / Vite 4+ | 5 / Vite 4-5 | 5 / Vite 5+ | 5 / Vite 5+ |
| Babel | 6 | 7 | 7 | 7 | 7 | 7 (optional) | 7 (optional) | 7 (optional) |
| React | 15+ | 16.3+ | 16+ | 16+ | 16.8+ | 16.8+ | 16.8+ | 16.8+ |
| TypeScript | — | — | 3+ | 3+ | 4.2+ | 4.9+ | 4.9+ | 4.9+ |
| Next.js | — | — | — | — | 12+ | 13.5+ | 14.1+ | 14.1+ |

## Story Format Evolution

| Version | Format | Status |
|---|---|---|
| 2.x+ | `storiesOf` API (imperative) | Deprecated 7.0, removed 8.0 |
| 5.2+ | CSF1 (ES module, function stories) | Still works |
| 6.0+ | CSF2 (Template.bind pattern, args) | Still works, prefer CSF3 |
| 6.4+ | CSF3 (object stories, `StoryObj`) | Current standard |
| 10.x | CSF Next / CSF Factories (preview) | Experimental, API may change |

## Config Format Evolution

| Version | Config Pattern |
|---|---|
| 2.x–5.2 | `config.js` + `addons.js` (imperative `configure()`, `addDecorator()`, `addParameters()`) |
| 5.3+ | `main.js` + `preview.js` + `manager.js` (declarative) |
| 7.0+ | `main.ts` + `preview.ts` (TypeScript supported, `framework` field required) |
| 10.x | Must be valid ESM (no CommonJS) |
