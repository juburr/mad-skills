---
name: react-storybook
description: Guides building and testing React-TypeScript components with Storybook.
  Covers CSF3 story format, interaction testing with play functions, accessibility
  testing, visual regression testing, portable stories, and CI/CD integration. Use
  when writing stories, component tests, or configuring Storybook for React-TypeScript
  projects.
---

# Storybook for React-TypeScript

## Setup

```bash
npm create storybook@latest
```

Auto-detects the project and configures the appropriate framework:

| Framework | Use when |
|---|---|
| `@storybook/react-vite` | Pure React + Vite projects (preferred default) |
| `@storybook/nextjs-vite` | Next.js 14.1+ projects (recommended) |
| `@storybook/nextjs` | Next.js 14.1+ projects that require custom Webpack/Babel configuration |
| `@storybook/react-webpack5` | Non-Next.js Webpack-based projects or when app-runtime parity is required |

For testing addons:

```bash
npx storybook add @storybook/addon-a11y
npx storybook add @storybook/addon-vitest   # Vite-based frameworks only (react-vite, nextjs-vite)
npx storybook add @chromatic-com/storybook
```

For Webpack projects, the Vitest addon is not supported. Use `@storybook/test-runner` instead (see `references/testing.md`).

For configuration details (`.storybook/main.ts`, `preview.ts`, Vitest addon setup, builder comparison), read `references/configuration.md`.

## Writing Stories (CSF3)

Every story file has a **default export** (component metadata) and **named exports** (individual stories). Code examples below use Storybook 9+ import paths (e.g., `storybook/test`). For Storybook 8, see the import path evolution table in `references/versions.md`.

```typescript
import type { Meta, StoryObj } from '@storybook/react';
import { fn } from 'storybook/test';
import { Button } from './Button';

const meta = {
  component: Button,
  title: 'Components/Button', // optional: auto-inferred from file path
  tags: ['autodocs'],
  args: {
    onClick: fn(), // spy function for callback tracking
  },
} satisfies Meta<typeof Button>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Primary: Story = {
  args: {
    primary: true,
    label: 'Click me',
  },
};

export const Secondary: Story = {
  args: {
    primary: false,
    label: 'Secondary',
  },
};
```

### Key Types

| Type | Purpose |
|---|---|
| `Meta<typeof Component>` | Default export (component metadata) |
| `StoryObj<typeof meta>` | Individual story objects (infers args from meta) |
| `Decorator` | Decorator functions |
| `Preview` | `.storybook/preview.ts` config |
| `StorybookConfig` | `.storybook/main.ts` config |

### Why `satisfies` Instead of Type Annotation

Using `satisfies Meta<typeof Button>` preserves the narrower type so `StoryObj<typeof meta>` can infer exact args. Using `: Meta<typeof Button>` widens the type and loses specificity.

### Args Composition

```typescript
export const PrimaryLarge: Story = {
  args: {
    ...Primary.args,
    size: 'large',
  },
};

// Cross-file composition
import * as HeaderStories from './Header.stories';

export const LoggedIn: Story = {
  args: {
    ...HeaderStories.LoggedIn.args,
  },
};
```

### Decorators

Wrap stories in providers, layout containers, or context. Execution order: Global -> Component -> Story (outermost to innermost).

```typescript
// Component-level decorator
const meta = {
  component: Page,
  decorators: [
    (Story, { parameters }) => (
      <ThemeProvider theme={parameters.theme || 'light'}>
        <Story />
      </ThemeProvider>
    ),
  ],
} satisfies Meta<typeof Page>;

// Story-level decorator
export const DarkMode: Story = {
  parameters: { theme: 'dark' },
  decorators: [
    (Story) => (
      <div style={{ background: '#333', padding: '1rem' }}>
        <Story />
      </div>
    ),
  ],
};
```

### Render Functions

Override default rendering when args alone are insufficient:

```typescript
export const WithState: Story = {
  // Must be a named function (not arrow) when using hooks
  render: function Render() {
    const [count, setCount] = React.useState(0);
    return <Button onClick={() => setCount(c => c + 1)} label={`Count: ${count}`} />;
  },
};
```

For detailed patterns (generics, unions, callbacks, children, argTypes, useArgs), read `references/stories.md`.

## Testing

Every story can be **render tested** (smoke test) when executed by the Vitest addon or test-runner. Beyond that, Storybook supports interaction testing, accessibility testing, visual regression, and portable stories.

### Interaction Testing with Play Functions

Play functions simulate user behavior and assert on component state in a real browser.

```typescript
import { expect, fn, userEvent, within } from 'storybook/test';

export const FilledForm: Story = {
  args: { onSubmit: fn() },
  play: async ({ args, canvas, userEvent, step }) => {
    await step('Fill in the form', async () => {
      await userEvent.type(canvas.getByLabelText('Email'), 'user@example.com');
      await userEvent.type(canvas.getByLabelText('Password'), 'supersecret');
    });

    await step('Submit the form', async () => {
      await userEvent.click(canvas.getByRole('button', { name: 'Submit' }));
    });

    await expect(args.onSubmit).toHaveBeenCalledWith({
      email: 'user@example.com',
      password: 'supersecret',
    });
  },
};
```

### The storybook/test Module

| Export | Purpose |
|---|---|
| `expect` | Vitest-compatible assertions (includes jest-dom matchers) |
| `fn` | Create spy/mock functions |
| `spyOn` | Spy on object methods |
| `userEvent` | Simulate user interactions (click, type, etc.) |
| `within` | Scope queries to a DOM subtree |
| `screen` | Query the full rendered document |
| `waitFor` | Wait for assertions to pass (polling) |
| `fireEvent` | Low-level DOM events (prefer `userEvent` when possible) |
| `mocked` | Type-safe access to mocked module functions |
| `clearAllMocks` | Clear all mock call history |
| `isMockFunction` | Type guard for mock functions |

### Play Function Context

```typescript
play: async ({
  canvas,        // scoped Testing Library queries
  userEvent,     // user interaction simulator
  args,          // story args (including fn() spies)
  step,          // group interactions into labeled steps
  mount,         // control when the component mounts
  canvasElement, // raw DOM element
}) => { /* ... */ }
```

### Canvas Queries (Testing Library)

Query priority (most to least accessible):

| Query | Use for |
|---|---|
| `canvas.getByRole('button', { name: 'Submit' })` | Interactive elements (preferred) |
| `canvas.getByLabelText('Email')` | Form fields |
| `canvas.getByPlaceholderText('Enter email')` | Inputs without labels |
| `canvas.getByText('Hello')` | Static text content |
| `canvas.getByTestId('submit-btn')` | Last resort |

Variants: `queryBy*` (returns null if not found), `findBy*` (async, waits for appearance), `getAllBy*`/`queryAllBy*`/`findAllBy*` (multiple elements).

### User Event Methods

All must be awaited:

| Method | Example |
|---|---|
| `click(el)` | `await userEvent.click(canvas.getByRole('button'))` |
| `dblClick(el)` | `await userEvent.dblClick(canvas.getByText('Item'))` |
| `type(el, text)` | `await userEvent.type(canvas.getByRole('textbox'), 'hello')` |
| `clear(el)` | `await userEvent.clear(canvas.getByRole('textbox'))` |
| `selectOptions(el, values)` | `await userEvent.selectOptions(select, ['opt1'])` |
| `hover(el)` / `unhover(el)` | `await userEvent.hover(canvas.getByText('Tooltip'))` |
| `tab()` | `await userEvent.tab()` |
| `keyboard(keys)` | `await userEvent.keyboard('{Enter}')` |

### Assertions

```typescript
// DOM state
await expect(canvas.getByRole('button')).toBeVisible();
await expect(canvas.getByRole('button')).toBeDisabled();
await expect(canvas.getByRole('button')).toHaveTextContent('Submit');
await expect(canvas.getByRole('textbox')).toHaveValue('hello');
await expect(canvas.queryByRole('alert')).not.toBeInTheDocument();

// Spy/mock assertions
await expect(args.onClick).toHaveBeenCalled();
await expect(args.onClick).toHaveBeenCalledTimes(1);
await expect(args.onSubmit).toHaveBeenCalledWith(
  expect.objectContaining({ email: 'user@example.com' })
);
```

### Testing Async Behavior

```typescript
export const LoadsData: Story = {
  play: async ({ canvas }) => {
    // findBy* waits for element to appear
    const heading = await canvas.findByRole('heading', { name: 'User Profile' });
    await expect(heading).toBeInTheDocument();

    const items = await canvas.findAllByRole('listitem');
    await expect(items).toHaveLength(5);
  },
};
```

### Testing Form Validation

```typescript
export const ValidationErrors: Story = {
  play: async ({ canvas, userEvent }) => {
    await userEvent.click(canvas.getByRole('button', { name: 'Submit' }));
    await expect(canvas.getByText('Email is required')).toBeInTheDocument();

    await userEvent.type(canvas.getByLabelText('Email'), 'notanemail');
    await userEvent.click(canvas.getByRole('button', { name: 'Submit' }));
    await expect(canvas.getByText('Invalid email address')).toBeInTheDocument();
  },
};
```

### Mocking with fn()

```typescript
// Mock return values via beforeEach
export const WithMockedAPI: Story = {
  args: { getUsers: fn() },
  beforeEach: async ({ args }) => {
    args.getUsers.mockResolvedValue([
      { id: 1, name: 'Alice' },
      { id: 2, name: 'Bob' },
    ]);
  },
  play: async ({ canvas }) => {
    const items = await canvas.findAllByRole('listitem');
    await expect(items).toHaveLength(2);
  },
};

// Mock rejected values for error states
export const NetworkError: Story = {
  args: {
    fetchData: fn().mockRejectedValue(new Error('Network error')),
  },
  play: async ({ canvas }) => {
    const alert = await canvas.findByRole('alert');
    await expect(alert).toHaveTextContent('Network error');
  },
};
```

### Controlling Mount Timing

```typescript
export const WithPreparedData: Story = {
  play: async ({ mount, canvas }) => {
    MockDate.set('2024-12-25');
    const canvasEl = await mount();
    await expect(canvasEl.getByText('December 25, 2024')).toBeInTheDocument();
  },
};
```

### Accessibility Testing

The `@storybook/addon-a11y` addon runs axe-core checks against rendered stories.

```typescript
// Project-wide in .storybook/preview.ts
const preview: Preview = {
  parameters: {
    a11y: {
      test: 'error', // 'error' = fail, 'todo' = warn, 'off' = skip
      options: {
        runOnly: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice'],
      },
    },
  },
};

// Per-story override
export const Decorative: Story = {
  parameters: { a11y: { test: 'off' } },
};
```

Recommended workflow: set `test: 'error'` project-wide, mark known violations as `test: 'todo'`, fix progressively, remove overrides as components pass.

### Running Tests

```bash
# Vitest addon (recommended for Vite projects)
npx vitest --project=storybook
npx vitest --project=storybook --coverage

# Test runner (Webpack projects, requires running Storybook)
npm run test-storybook
npm run test-storybook -- --coverage
```

### Vitest Addon vs Test Runner

| Feature | Vitest Addon | Test Runner |
|---|---|---|
| Interaction tests | Yes | Yes |
| Accessibility tests | Yes | Yes |
| Visual tests | Yes | No |
| Snapshot tests | No | Yes |
| Storybook UI integration | Yes | No |
| Editor extensions | Yes | No |
| Requires running Storybook | No | Yes |
| Works with Webpack | No | Yes |

For detailed testing patterns (test runner hooks, snapshot testing, image snapshots, tag filtering, Chromatic visual testing, portable stories, coverage configuration, CI/CD integration), read `references/testing.md`.

## Lifecycle Hooks

```typescript
const meta = {
  component: DateDisplay,
  // Runs before each story; return cleanup function for teardown
  async beforeEach() {
    MockDate.set('2024-02-14');
    return () => MockDate.reset();
  },
} satisfies Meta<typeof DateDisplay>;
```

| Hook | Scope | Purpose |
|---|---|---|
| `beforeAll` | Project (preview.ts) | Run once before all stories |
| `beforeEach` | Component or story | Run before each story renders; return cleanup function |
| `afterEach` | Component or story | Run after each story renders and interactions complete |
| `mount` | Play function | Control when the component mounts |

## Tags

Control story visibility, docs inclusion, and test execution.

| Tag | Default | Purpose |
|---|---|---|
| `dev` | Applied | Include in sidebar |
| `test` | Applied | Include in test runs |
| `autodocs` | Not applied | Include in auto-generated docs |
| `play-fn` | Auto-applied | Stories with play functions |

```typescript
// Remove with ! prefix
export const TestOnly: Story = { tags: ['!dev'] };       // hide from sidebar
export const DisplayOnly: Story = { tags: ['!test'] };   // skip in tests
```

## Documentation

### Autodocs

Add the `autodocs` tag to generate docs pages automatically from stories and component metadata:

```typescript
const meta = {
  component: Button,
  tags: ['autodocs'], // or set globally in preview.ts
} satisfies Meta<typeof Button>;
```

Use MDX only when you need prose, usage guidance, do/don't sections, or cross-component narratives. Autodocs handles standard API reference docs.

## Data Strategy Priority

When providing data to stories, prefer this order:

1. **Args** — for props and state variants (most common)
2. **Decorators** — for providers and layout context
3. **Module mocks** — for imported dependencies (`sb.mock` in preview.ts)
4. **MSW handlers** — for components that fetch data via `fetch()` or API clients (see `references/advanced.md`)
5. **Loaders** — only for true pre-render async setup (advanced escape hatch)

## Security

Treat built Storybook artifacts (`storybook-static/`) as **public web assets**. A December 2025 security advisory (affecting Storybook 7-10) revealed that `storybook build` could bundle `.env` variables into output. Ensure you are on the latest patch release for your major version. Never put secrets in Storybook-reachable env paths; use `STORYBOOK_`-prefixed variables for intentional exposure only.

## Anti-Patterns

- Do not use `getByTestId` when accessible queries (`getByRole`, `getByLabelText`) are available.
- Do not use synchronous assertions for async operations; always `await expect(...)`.
- Do not import from `@storybook/testing-library` or `@storybook/jest`; use `storybook/test` (Storybook 9+) or `@storybook/test` (Storybook 8).
- Do not use CSF2 template pattern in new code; use CSF3 object stories.
- Do not generate removed APIs: `storiesOf` (removed in 8), `*.stories.mdx` (removed in 8), Storyshots (removed in 8), Knobs (use Controls), Storysource (removed in 9).
- Do not test implementation details (internal state, private methods); test user-visible behavior.
- Do not mock everything; prefer realistic data and reserve mocks for external dependencies.
- Do not skip a11y tests for "internal" components; all rendered UI should be accessible.
- Do not put secrets in `.env` files accessible to Storybook builds.

## Reference Files

| File | Contents | When to load |
|---|---|---|
| `references/configuration.md` | `.storybook/main.ts`, `preview.ts`, Vitest addon setup, builder comparison, tsconfig, addons | Setting up or modifying Storybook configuration |
| `references/stories.md` | Detailed CSF3 patterns: generics, unions, callbacks, children, argTypes, useArgs, render functions | Writing stories for components with complex prop types |
| `references/testing.md` | Test runner setup, snapshot testing, image snapshots, Chromatic visual testing, portable stories, coverage, CI/CD | Setting up CI pipelines, visual regression testing, or using stories in external test frameworks |
| `references/advanced.md` | Module mocking (sb.mock, subpath imports), context providers (router, Redux, Zustand), Next.js App Router mocks, MSW network mocking, loaders, lifecycle hooks, tags | Mocking dependencies, wrapping components in providers, Next.js stories, or advanced story configuration |
| `references/versions.md` | Storybook 8/9/10 features, breaking changes, import path evolution, version compatibility | Checking version-specific features or compatibility |
| `references/migration.md` | Step-by-step upgrade instructions for 7→8, 8→9, 9→10, multi-version jumps, test-runner to Vitest migration, common pitfalls | Upgrading Storybook across one or more major versions |
