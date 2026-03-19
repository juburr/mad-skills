# Testing Reference

This file covers testing approaches beyond the core interaction testing patterns in `SKILL.md`: test runner setup, snapshot testing, visual regression, portable stories, coverage, and CI/CD.

## Test Runner (Webpack Projects)

The test-runner (`@storybook/test-runner`) uses Jest + Playwright. Superseded by the Vitest addon for Vite projects but required for Webpack.

### Setup

```bash
npm install @storybook/test-runner --save-dev
```

```json
{
  "scripts": {
    "test-storybook": "test-storybook"
  }
}
```

Requires a running Storybook instance:

```bash
# Terminal 1
npm run storybook

# Terminal 2
npm run test-storybook
```

### CLI Options

| Flag | Purpose |
|---|---|
| `--watch` | Watch mode |
| `--coverage` | Generate coverage reports |
| `--url <address>` | Target a deployed Storybook |
| `--browsers chromium firefox webkit` | Browser selection |
| `--maxWorkers <n>` | Parallel workers |
| `--shard <index/count>` | Distribute across CI machines |
| `--failOnConsole` | Fail on console errors |
| `--includeTags <tags>` | Include stories by tag |
| `--excludeTags <tags>` | Exclude stories by tag |

### Test Hook API

```typescript
// .storybook/test-runner.ts
import type { TestRunnerConfig } from '@storybook/test-runner';

const config: TestRunnerConfig = {
  setup() {
    // Runs once before all tests
  },
  async preVisit(page, context) {
    // Before each story renders
  },
  async postVisit(page, context) {
    // After each story renders
    const el = await page.$('#storybook-root');
    const innerHTML = await el.innerHTML();
    expect(innerHTML).toMatchSnapshot();
  },
};

export default config;
```

### Tag-Based Filtering

```typescript
const config: TestRunnerConfig = {
  tags: {
    include: ['test-only', 'pages'],
    exclude: ['no-tests'],
    skip: ['skip-test'],
  },
};
```

## Snapshot Testing

### HTML Snapshots (Test Runner)

```typescript
// .storybook/test-runner.ts
const config: TestRunnerConfig = {
  async postVisit(page, context) {
    const elementHandler = await page.$('#storybook-root');
    const innerHTML = await elementHandler.innerHTML();
    expect(innerHTML).toMatchSnapshot();
  },
};
```

### Image Snapshots (Test Runner)

```typescript
import { waitForPageReady } from '@storybook/test-runner';
import { toMatchImageSnapshot } from 'jest-image-snapshot';

const config: TestRunnerConfig = {
  setup() {
    expect.extend({ toMatchImageSnapshot });
  },
  async postVisit(page, context) {
    await waitForPageReady(page);
    const image = await page.screenshot();
    expect(image).toMatchImageSnapshot({
      customSnapshotsDir: `${process.cwd()}/__snapshots__`,
      customSnapshotIdentifier: context.id,
    });
  },
};
```

### Snapshot Testing with Portable Stories

```typescript
import { composeStories } from '@storybook/react-vite'; // match your framework
import * as stories from './Button.stories';

const { Primary } = composeStories(stories);

test('Button snapshot', async () => {
  await Primary.run();
  expect(document.body.firstChild).toMatchSnapshot();
});
```

## Visual Regression Testing (Chromatic)

```bash
npx storybook@latest add @chromatic-com/storybook
```

Configuration in `chromatic.config.json`:

```json
{
  "projectId": "Project:abc123",
  "buildScriptName": "build-storybook",
  "zip": true
}
```

Every story automatically becomes a visual test. Changes are detected by comparing screenshots against accepted baselines. Accept intentional changes as new baselines; fix unintentional regressions.

## Accessibility Testing (Detailed)

### axe-core Configuration

```typescript
// .storybook/preview.ts
parameters: {
  a11y: {
    test: 'error',
    context: {
      include: ['body'],
      exclude: ['.no-a11y-check'],
    },
    config: {
      rules: [
        { id: 'region', enabled: false },
        { id: 'color-contrast', enabled: true },
      ],
    },
    options: {
      runOnly: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice'],
    },
  },
}
```

### WCAG AAA Compliance

```typescript
parameters: {
  a11y: {
    options: {
      runOnly: [
        'wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa',
        'best-practice', 'wcag2aaa',
      ],
    },
  },
}
```

### Vitest Integration

Add annotations to `.storybook/vitest.setup.ts`:

```typescript
import * as a11yAddonAnnotations from '@storybook/addon-a11y/preview';

const annotations = setProjectAnnotations([
  a11yAddonAnnotations,
  previewAnnotations,
]);
```

## Portable Stories (External Test Frameworks)

Reuse Storybook stories in Vitest, Jest, or Playwright Component Tests.

Import `composeStories`, `composeStory`, and `setProjectAnnotations` from **your framework package**:

| Framework | Import from |
|---|---|
| `@storybook/react-vite` | `@storybook/react-vite` |
| `@storybook/nextjs-vite` | `@storybook/nextjs-vite` |
| `@storybook/nextjs` | `@storybook/nextjs` |
| `@storybook/react-webpack5` | `@storybook/react-webpack5` |

### composeStories (All Stories in a File)

```typescript
import { composeStories } from '@storybook/react-vite'; // match your framework
import * as stories from './Button.stories';

const { Primary, Secondary } = composeStories(stories);

test('renders primary button', async () => {
  await Primary.run();
  const button = screen.getByText('Click me');
  expect(button).not.toBeNull();
});

test('renders with overridden props', async () => {
  await Primary.run({ args: { ...Primary.args, children: 'Custom' } });
  const button = screen.getByText(/Custom/i);
  expect(button).not.toBeNull();
});
```

### composeStory (Single Story)

```typescript
import { composeStory } from '@storybook/react-vite'; // match your framework
import meta, { Primary as PrimaryStory } from './Button.stories';

const Primary = composeStory(PrimaryStory, meta);

test('renders primary button', async () => {
  await Primary.run();
});
```

### Setup File for Portable Stories

Include preview annotations from each addon you use so composed stories behave the same as in Storybook.

For Vitest:

```typescript
// vitest.setup.ts
import { beforeAll } from 'vitest';
import { setProjectAnnotations } from '@storybook/react-vite'; // match your framework
import * as previewAnnotations from './.storybook/preview';
// Import preview annotations from addons you use, e.g.:
// import * as a11yAddonAnnotations from '@storybook/addon-a11y/preview';

const annotations = setProjectAnnotations([
  // a11yAddonAnnotations,
  previewAnnotations,
]);
beforeAll(annotations.beforeAll);
```

For Jest:

```typescript
// jest.setup.ts
import { beforeAll } from '@jest/globals';
import { setProjectAnnotations } from '@storybook/react-vite'; // match your framework
import * as previewAnnotations from './.storybook/preview';
// Import preview annotations from addons you use, e.g.:
// import * as a11yAddonAnnotations from '@storybook/addon-a11y/preview';

const annotations = setProjectAnnotations([
  // a11yAddonAnnotations,
  previewAnnotations,
]);
beforeAll(annotations.beforeAll);
```

#### Next.js + Jest

Next.js projects using `@storybook/nextjs` with Jest require additional setup: the `next/jest.js` transformer and module aliases for Next.js mocks.

```javascript
// jest.config.js
const nextJest = require('next/jest');
const { getPackageAliases } = require('@storybook/nextjs/export-mocks');

const createJestConfig = nextJest({ dir: './' });

module.exports = createJestConfig({
  testEnvironment: 'jsdom',
  setupFilesAfterEnv: ['./jest.setup.ts'],
  moduleNameMapper: {
    ...getPackageAliases(), // resolves Next.js mock modules
  },
});
```

```typescript
// jest.setup.ts
import { beforeAll } from '@jest/globals';
import { setProjectAnnotations } from '@storybook/nextjs';
import * as previewAnnotations from './.storybook/preview';

const annotations = setProjectAnnotations([previewAnnotations]);
beforeAll(annotations.beforeAll);
```

### Composed Story Properties

| Property | Description |
|---|---|
| `args` | Resolved args |
| `argTypes` | Arg type definitions |
| `id` | Unique story identifier |
| `parameters` | Story parameters |
| `play` | Play function (if defined) |
| `run()` | Mount component and execute play function |
| `storyName` | Display name |
| `tags` | Story tags |

### Overriding Globals

```typescript
test('renders in Spanish', async () => {
  const Primary = composeStory(PrimaryStory, meta, {
    globals: { locale: 'es' },
  });
  await Primary.run();
});
```

### Testing Error Boundaries

```typescript
const { ThrowError } = composeStories(stories);

test('Button throws error', async () => {
  await expect(ThrowError.run()).rejects.toThrowError('Something went wrong');
});
```

## Test Coverage

### With Vitest Addon

```bash
npm install --save-dev @vitest/coverage-istanbul  # or @vitest/coverage-v8
```

```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    coverage: {
      provider: 'istanbul',
    },
  },
});
```

```bash
npx vitest --project=storybook --coverage
```

### With Test Runner (addon-coverage)

```bash
npx storybook@latest add @storybook/addon-coverage
```

```typescript
// .storybook/main.ts
// Use AddonOptionsWebpack for Webpack projects, AddonOptionsVite for Vite projects.
import type { AddonOptionsWebpack } from '@storybook/addon-coverage';

const coverageConfig: AddonOptionsWebpack = {
  istanbul: {
    include: ['**/stories/**'],
    exclude: ['**/exampleDirectory/**'],
  },
};

const config: StorybookConfig = {
  addons: [
    { name: '@storybook/addon-coverage', options: coverageConfig },
  ],
};
```

```bash
npm run test-storybook -- --coverage
npx nyc report --reporter=lcov -t coverage/storybook --report-dir coverage/storybook
```

## CI/CD Integration

### GitHub Actions with Vitest Addon

```yaml
name: Storybook Tests
on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: mcr.microsoft.com/playwright:v1.52.0-noble
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22.12.0
      - run: npm ci
      - run: npx vitest --project=storybook
```

### GitHub Actions with Test Runner

```yaml
name: Storybook Tests
on: push

jobs:
  test:
    timeout-minutes: 60
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: '.nvmrc'
      - run: yarn
      - run: npx playwright install --with-deps
      - run: yarn build-storybook --quiet
      - name: Serve and test
        run: |
          npx concurrently -k -s first -n "SB,TEST" -c "magenta,blue" \
            "npx http-server storybook-static --port 6006 --silent" \
            "npx wait-on tcp:127.0.0.1:6006 && yarn test-storybook"
```

### Parallelization

**Vitest addon:** Vitest handles parallelization automatically via its worker pool.

**Test runner:** Use `--shard` for distribution across machines:

```bash
npm run test-storybook -- --shard=1/3  # Machine 1
npm run test-storybook -- --shard=2/3  # Machine 2
npm run test-storybook -- --shard=3/3  # Machine 3
```

### Docker

Use Playwright's official image for consistent browser environments:

```dockerfile
FROM mcr.microsoft.com/playwright:v1.52.0-noble
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build-storybook
CMD ["npm", "run", "test-storybook"]
```
