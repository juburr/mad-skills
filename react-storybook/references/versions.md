# Storybook Version History and Migration

## Storybook 8

- **`@storybook/test` module**: Consolidated `@storybook/jest` and `@storybook/testing-library` into a single package with Vitest-compatible APIs.
- **Visual testing addon**: Built-in Chromatic integration.
- **Performance**: 2-4x faster test builds with `--test` CLI flag. Up to 50% faster React startup via `react-docgen` (now default).
- **Vite 5 support**.

### Breaking Changes from 7 to 8

- `storiesOf` API removed; use CSF.
- `*.stories.mdx` removed; use CSF stories + MDX docs.
- Storyshots removed; use interaction/visual/test-runner tests.
- `@storybook/jest` and `@storybook/testing-library` removed; use `@storybook/test`.
- Knobs addon removed; use Controls.
- Webpack 4 no longer supported; must use Webpack 5.
- Vite projects must pre-configure framework plugins (`@vitejs/plugin-react`, etc.).
- `react-docgen` is the default (switch back via `typescript.reactDocgen` config).

## Storybook 9

- **Storybook Test**: Integrated Vitest + Playwright testing framework with interaction, accessibility, and visual tests unified.
- **Test widget**: New UI for running tests with watch mode and debug panels.
- **Story generation**: Create and edit stories via the Storybook UI.
- **Tag-based organization**: Filter and group stories by tag with sidebar badges.
- **Story globals**: Set context variables (theme, viewport, locale) per-story.
- **48% smaller bundle**.
- **`@storybook/nextjs-vite`**: Next.js framework with Vite (stabilized).
- **Experimental test addon renamed**: `@storybook/experimental-addon-test` became `@storybook/addon-vitest`.
- **Essential addons moved to core**: Viewport, Controls, Interactions, Actions.
- **Storysource addon removed**; use codePanel.

### Breaking Changes from 8 to 9

- Node.js 20+ required. Vite 4 dropped. TypeScript < 4.9 dropped.
- Webpack5 builder support dropped for Preact, Vue, and Web Components.
- Import paths changed (see table below).

### Import Path Changes (8 to 9)

```typescript
// Storybook 8
import { expect, fn, userEvent } from '@storybook/test';

// Storybook 9+
import { expect, fn, userEvent } from 'storybook/test';
```

## Storybook 10

- **ESM-only**: CommonJS support removed. `.storybook/main.ts` and presets must be valid ESM. 29% smaller install size.
- **Module automocking**: `sb.mock()` API inspired by Vitest's `vi.mock()`. Works with Vite and Webpack.
- **CSF Factories** (preview/experimental): Reduced TypeScript boilerplate. API may still change; prefer stable CSF3 for production work unless explicitly opting in.

  ```typescript
  // CSF Factories (preview feature, optional)
  const meta = preview.meta({ component: Button });
  export const Primary = meta.story({
    args: { label: 'Button', primary: true },
  });

  // Traditional CSF3 (stable, still supported)
  const meta = { component: Button } satisfies Meta<typeof Button>;
  export default meta;
  export const Primary: Story = { args: { label: 'Button', primary: true } };
  ```

- **Tag filtering enhancements**: `defaultFilterSelection` in main.ts config.
- **Node.js 20.19+ or 22.12+ required**.
- **`moduleResolution` must support `types` condition** (`"Bundler"`, `"NodeNext"`, or `"Node16"`).
- **MCP addon** (`@storybook/addon-mcp`): Experimental. Exposes component information and development workflows to AI agents over MCP at `http://localhost:6006/mcp`. Currently React-only.

## Upgrade Workflow

Upgrade **one major version at a time** (exception: 6 → 8 can be direct). Always run from the **repository root**:

```bash
npx storybook@latest upgrade

# Health check after upgrade
npx storybook@latest doctor

# Find available codemods
npx storybook@latest migrate --list

# Auto-apply codemods
npx storybook@latest automigrate
```

In monorepos, the upgrade tool is monorepo-aware: it detects Storybook projects at the root, supports selective vs bulk upgrades. Use `STORYBOOK_PROJECT_ROOT` to limit scope in very large monorepos.

For detailed step-by-step migration instructions across each major version (7→8, 8→9, 9→10), multi-version jump checklists, test-runner to Vitest migration, and common pitfalls, read `migration.md`.

## Version Compatibility Matrix

| Storybook | Node.js | React | Vite | Webpack | TypeScript |
|---|---|---|---|---|---|
| 8.x | 18+ | 16.8+ | 4-5 | 5 | 4.9+ |
| 9.x | 20+ | 16.8+ | 5+ | 5 | 4.9+ |
| 10.x | 20.19+ or 22.12+ | 16.8+ | 5+ | 5 | 4.9+ |

## Import Path Evolution

| Concept | Storybook 7 | Storybook 8 | Storybook 9+ |
|---|---|---|---|
| Test utilities | `@storybook/jest` + `@storybook/testing-library` | `@storybook/test` | `storybook/test` |
| Preview API | `@storybook/preview-api` | `@storybook/preview-api` | `storybook/preview-api` |
| Types | `@storybook/react` | `@storybook/react` | `@storybook/react` |

## Legacy Patterns to Never Reintroduce

| Removed Pattern | Replacement | Removed In |
|---|---|---|
| `storiesOf` API | CSF (default + named exports) | 8 |
| `*.stories.mdx` | CSF stories + separate MDX docs | 8 |
| Storyshots | Interaction/visual/test-runner tests | 8 |
| Knobs addon | Controls (built-in) | 8 |
| Storysource addon | codePanel | 9 |
| `@storybook/testing-library` | `storybook/test` | 8 (renamed in 9) |
