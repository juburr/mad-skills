# Storybook Configuration

## Project Structure

```
.storybook/
  main.ts          # Core configuration (addons, framework, stories globs)
  preview.ts       # Story rendering config (decorators, parameters, globals)
  manager.ts       # UI configuration (theme, sidebar behavior)
  vitest.setup.ts  # Vitest addon setup (portable stories annotations)
```

## main.ts

```typescript
import type { StorybookConfig } from '@storybook/react-vite';

const config: StorybookConfig = {
  stories: ['../src/**/*.mdx', '../src/**/*.stories.@(js|jsx|mjs|ts|tsx)'],

  addons: [
    '@storybook/addon-docs',
    '@storybook/addon-a11y',
    '@storybook/addon-vitest',
    '@chromatic-com/storybook',
  ],

  framework: {
    name: '@storybook/react-vite',
    options: {},
  },

  staticDirs: ['../public'],

  typescript: {
    reactDocgen: 'react-docgen-typescript', // or 'react-docgen' (faster, less complete)
  },

  // Tag filtering (Storybook 10+)
  tags: {
    experimental: { defaultFilterSelection: 'exclude' },
  },

  // Customize Vite config
  viteFinal: async (config) => {
    return config;
  },

  build: { test: {} }, // optimized production builds
};

export default config;
```

### For Next.js (Vite)

Requires Next.js >= 14.1. Recommended over the webpack-based Next.js integration for faster startup and better testing support.

```typescript
import type { StorybookConfig } from '@storybook/nextjs-vite';

const config: StorybookConfig = {
  framework: {
    name: '@storybook/nextjs-vite',
    options: {},
  },
  // ... same stories, addons as the react-vite example above.
};

export default config;
```

### For Next.js (Webpack)

Requires Next.js >= 14.1. Use this when your project relies on custom Webpack/Babel configuration that is incompatible with Vite. Provides the same Next.js-specific features as `@storybook/nextjs-vite` (image, font, and router mocking).

```typescript
import type { StorybookConfig } from '@storybook/nextjs';

const config: StorybookConfig = {
  stories: ['../src/**/*.mdx', '../src/**/*.stories.@(js|jsx|mjs|ts|tsx)'],

  addons: [
    '@storybook/addon-docs',
    '@storybook/addon-a11y',
    // Do NOT add @storybook/addon-vitest here — it requires a Vite-based framework.
    // Use @storybook/test-runner for Webpack projects (see testing.md).
    '@chromatic-com/storybook',
  ],

  framework: {
    name: '@storybook/nextjs',
    options: {},
  },

  webpackFinal: async (config) => {
    return config;
  },
};

export default config;
```

### For Webpack 5

```typescript
import type { StorybookConfig } from '@storybook/react-webpack5';

const config: StorybookConfig = {
  stories: ['../src/**/*.mdx', '../src/**/*.stories.@(js|jsx|mjs|ts|tsx)'],

  addons: [
    '@storybook/addon-docs',
    '@storybook/addon-a11y',
    // Do NOT add @storybook/addon-vitest here — it requires a Vite-based framework.
    // Use @storybook/test-runner for Webpack projects (see testing.md).
    '@chromatic-com/storybook',
  ],

  framework: {
    name: '@storybook/react-webpack5',
    options: {},
  },

  webpackFinal: async (config) => {
    return config;
  },
};

export default config;
```

### Story Loading Patterns

```typescript
// Glob patterns (default)
stories: ['../src/**/*.stories.@(js|jsx|ts|tsx)']

// Directory-based with title prefix
stories: [{
  directory: '../packages/components',
  files: '*.stories.*',
  titlePrefix: 'MyComponents',
}]
```

## preview.ts

```typescript
import type { Preview } from '@storybook/react';
import { ThemeProvider } from 'styled-components';

const preview: Preview = {
  decorators: [
    (Story) => (
      <ThemeProvider theme="default">
        <Story />
      </ThemeProvider>
    ),
  ],

  parameters: {
    controls: {
      matchers: {
        color: /(background|color)$/i,
        date: /Date$/i,
      },
    },
    a11y: {
      test: 'error',
    },
  },

  tags: ['autodocs'],

  initialGlobals: {
    locale: 'en',
  },

  async beforeAll() {
    // Run once before all stories
  },
  async beforeEach() {
    // Run before each story renders
  },
};

export default preview;
```

## Vitest Addon Setup

### vitest.setup.ts

```typescript
import { beforeAll } from 'vitest';
import { setProjectAnnotations } from '@storybook/react-vite'; // match your framework
import * as previewAnnotations from './preview';
import * as a11yAddonAnnotations from '@storybook/addon-a11y/preview';

const annotations = setProjectAnnotations([
  a11yAddonAnnotations,
  previewAnnotations,
]);

beforeAll(annotations.beforeAll);
```

### vitest.config.ts

```typescript
import { defineConfig, mergeConfig } from 'vitest/config';
import { playwright } from '@vitest/browser-playwright';
import { storybookTest } from '@storybook/addon-vitest/vitest-plugin';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dirname = path.dirname(fileURLToPath(import.meta.url));
import viteConfig from './vite.config';

export default mergeConfig(
  viteConfig,
  defineConfig({
    test: {
      projects: [
        {
          extends: true,
          plugins: [
            storybookTest({
              configDir: path.join(dirname, '.storybook'),
              storybookScript: 'yarn storybook --no-open',
            }),
          ],
          test: {
            name: 'storybook',
            browser: {
              enabled: true,
              provider: playwright({}),
              headless: true,
              instances: [{ browser: 'chromium' }],
            },
            setupFiles: ['./.storybook/vitest.setup.ts'],
          },
        },
      ],
      coverage: {
        provider: 'istanbul', // or 'v8'
      },
    },
  }),
);
```

## tsconfig Considerations

Ensure `tsconfig.json` includes:

```json
{
  "compilerOptions": {
    "jsx": "react-jsx",
    "moduleResolution": "bundler",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true,
    "types": ["vitest/globals"]
  },
  "include": ["src", ".storybook"]
}
```

For subpath imports (module mocking), `moduleResolution` must be `"Bundler"`, `"NodeNext"`, or `"Node16"`.

## Essential Addons

| Addon | Purpose |
|---|---|
| `@storybook/addon-docs` | Auto-generated documentation from stories |
| `@storybook/addon-a11y` | Accessibility checks via axe-core |
| `@storybook/addon-vitest` | Vitest-based component testing integration |
| `@chromatic-com/storybook` | Visual regression testing via Chromatic |
| `@storybook/addon-coverage` | Builder-based code coverage instrumentation (recommended with test-runner; Vitest addon uses Vitest's native coverage instead) |

## Builders: Vite vs Webpack

| Feature | Vite | Webpack 5 |
|---|---|---|
| Startup speed | Fast (ESM-native) | Slower (bundling required) |
| HMR | Near-instant | Slower |
| Vitest addon | Supported | Not supported |
| Module automocking | Supported | Supported (ESM entry points only) |
| Framework packages | `@storybook/react-vite`, `@storybook/nextjs-vite` | `@storybook/react-webpack5`, `@storybook/nextjs` |

Prefer Vite for new projects. The Vitest addon (recommended testing approach) requires a Vite-based framework. For Next.js 14.1+, prefer `@storybook/nextjs-vite` unless you need custom Webpack/Babel configuration (`@storybook/nextjs`).

## CLI Reference

```bash
npm create storybook@latest          # Install Storybook
npm run storybook                     # Start dev server
npm run build-storybook               # Build static output (to storybook-static/)
npx storybook add <addon>             # Add an addon
npx storybook@latest upgrade          # Upgrade (run from repo root)
npx storybook@latest doctor           # Health check
npx storybook@latest automigrate      # Auto-apply codemods
npx storybook@latest migrate --list   # List available codemods
```
