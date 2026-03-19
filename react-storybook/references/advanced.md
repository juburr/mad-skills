# Advanced Storybook Patterns

## Module Mocking

### Automocking (Recommended, Storybook 10+)

Mocked modules **must** be registered at the **project-level preview config** (`.storybook/preview.ts`), not inside story files. Per-story behavior is customized via `beforeEach`.

```typescript
import { sb } from 'storybook/test';

// All exports become mock functions
sb.mock(import('../lib/session.ts'));
sb.mock(import('uuid'));

// Spy-only mode (preserves implementation, wraps in spies)
sb.mock(import('../lib/analytics.ts'), { spy: true });
```

Create mock files in `__mocks__` directories alongside the real module:

```typescript
// lib/__mocks__/session.ts
export function getUserFromSession() {
  return { name: 'Mocked User', role: 'admin' };
}
```

For node_modules, create mocks in the project root `__mocks__` directory:

```typescript
// __mocks__/uuid.ts
export function v4() {
  return '1234-5678-90ab-cdef';
}
```

Use mocked modules in stories:

```typescript
import type { Meta, StoryObj } from '@storybook/react';
import { mocked } from 'storybook/test';
import { getUserFromSession } from '../lib/session';
import { AuthButton } from './AuthButton';

const meta = {
  component: AuthButton,
  beforeEach: async () => {
    mocked(getUserFromSession).mockReturnValue({
      name: 'John Doe',
      role: 'admin',
    });
  },
} satisfies Meta<typeof AuthButton>;

export default meta;
type Story = StoryObj<typeof meta>;

export const LoggedIn: Story = {};

export const AsViewer: Story = {
  beforeEach: async () => {
    mocked(getUserFromSession).mockReturnValue({
      name: 'Jane Doe',
      role: 'viewer',
    });
  },
};
```

### Subpath Imports (Alternative)

Configure in `package.json`:

```json
{
  "imports": {
    "#lib/session": {
      "storybook": "./lib/session.mock.ts",
      "default": "./lib/session.ts"
    }
  }
}
```

Create mock files with `fn()` wrappers:

```typescript
// lib/session.mock.ts
import { fn } from 'storybook/test';
import * as actual from './session';

export const getUserFromSession = fn(actual.getUserFromSession)
  .mockName('getUserFromSession');
```

Update component imports to use subpaths:

```typescript
// AuthButton.tsx
import { getUserFromSession } from '#lib/session';
```

Requires `moduleResolution` set to `"Bundler"`, `"NodeNext"`, or `"Node16"`.

### Builder Aliases (Vite)

```typescript
// .storybook/main.ts
const config: StorybookConfig = {
  viteFinal: async (config) => {
    if (config.resolve) {
      config.resolve.alias = {
        ...config.resolve?.alias,
        '@/lib/session': import.meta.resolve('./lib/session.mock.ts'),
      };
    }
    return config;
  },
};
```

### Asserting on Mocked Module Calls

```typescript
import { saveNote } from '../app/actions';

export const SaveFlow: Story = {
  play: async ({ canvas, userEvent }) => {
    await userEvent.click(canvas.getByRole('menuitem', { name: /done/i }));
    await expect(saveNote).toHaveBeenCalled();
  },
};
```

## Mocking Context Providers

### Theme Provider

```typescript
// .storybook/preview.tsx
const preview: Preview = {
  decorators: [
    (Story, { parameters }) => {
      const { theme = 'light' } = parameters;
      return (
        <ThemeProvider theme={themes[theme]}>
          <Story />
        </ThemeProvider>
      );
    },
  ],
};
```

Per-story: `parameters: { theme: 'dark' }`.

### React Router

```typescript
import { MemoryRouter, Route, Routes } from 'react-router-dom';

const meta = {
  component: UserProfile,
  decorators: [
    (Story) => (
      <MemoryRouter initialEntries={['/users/123']}>
        <Routes>
          <Route path="/users/:id" element={<Story />} />
        </Routes>
      </MemoryRouter>
    ),
  ],
} satisfies Meta<typeof UserProfile>;
```

### Next.js (App Router)

Both `@storybook/nextjs-vite` and `@storybook/nextjs` support `nextjs.appDirectory: true` for components that use `next/navigation`. Set this parameter for any story that imports App Router APIs. Both frameworks provide identical built-in mock modules — substitute your framework package in the import paths below.

```typescript
import type { Meta, StoryObj } from '@storybook/nextjs-vite'; // or @storybook/nextjs
import { expect } from 'storybook/test';
import { getRouter } from '@storybook/nextjs-vite/navigation.mock'; // or @storybook/nextjs/navigation.mock
import { ProfilePage } from './ProfilePage';

const meta = {
  component: ProfilePage,
  parameters: {
    nextjs: {
      appDirectory: true,
      navigation: {
        pathname: '/profile/123',
      },
    },
  },
} satisfies Meta<typeof ProfilePage>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {};

export const NavigatesOnSave: Story = {
  play: async ({ canvas, userEvent }) => {
    await userEvent.click(canvas.getByRole('button', { name: 'Save' }));
    await expect(getRouter().push).toHaveBeenCalledWith('/profile');
  },
};
```

Available Next.js mock modules (replace `nextjs-vite` with `nextjs` for the webpack framework):

| Mock module | Mocks | Key parameter |
|---|---|---|
| `@storybook/nextjs-vite/navigation.mock` | `next/navigation` (App Router) | `nextjs.navigation` (`pathname`, `query`, `segments`) |
| `@storybook/nextjs-vite/router.mock` | `next/router` (Pages Router) | `nextjs.router` (`pathname`, `asPath`, `query`) |
| `@storybook/nextjs-vite/headers.mock` | `next/headers` (`headers()`, `cookies()`, `draftMode()`) | N/A (use mock utilities directly) |
| `@storybook/nextjs-vite/cache.mock` | `next/cache` (`revalidatePath`, `revalidateTag`) | N/A (use mock utilities directly) |

Set `nextjs.appDirectory: true` at the story, component, or global level (in `.storybook/preview.ts`) to enable App Router mocks.

### Redux Store

```typescript
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { rootReducer } from '../store';

const meta = {
  component: Dashboard,
  decorators: [
    (Story) => {
      const store = configureStore({
        reducer: rootReducer,
        preloadedState: {
          user: { name: 'Test User', loggedIn: true },
          notifications: { count: 3 },
        },
      });
      return (
        <Provider store={store}>
          <Story />
        </Provider>
      );
    },
  ],
} satisfies Meta<typeof Dashboard>;
```

### Zustand Store

```typescript
import { create } from 'zustand';
import { fn } from 'storybook/test';

const useTestStore = create(() => ({
  count: 0,
  increment: fn(),
  decrement: fn(),
}));

const meta = {
  component: Counter,
  decorators: [
    (Story) => {
      useTestStore.setState({ count: 0 });
      return <Story />;
    },
  ],
} satisfies Meta<typeof Counter>;

export const WithHighCount: Story = {
  decorators: [
    (Story) => {
      useTestStore.setState({ count: 99 });
      return <Story />;
    },
  ],
};
```

### Multiple Providers

```typescript
// .storybook/preview.tsx
const preview: Preview = {
  decorators: [
    // Outermost first
    (Story) => (
      <QueryClientProvider client={queryClient}>
        <Story />
      </QueryClientProvider>
    ),
    (Story, { parameters }) => (
      <ThemeProvider theme={themes[parameters.theme || 'light']}>
        <Story />
      </ThemeProvider>
    ),
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
};
```

## Testing Components with React Hooks

### useState

```typescript
export const ToggleButton: Story = {
  render: function Render() {
    const [isActive, setIsActive] = React.useState(false);
    return (
      <Button
        label={isActive ? 'Active' : 'Inactive'}
        onClick={() => setIsActive(!isActive)}
        primary={isActive}
      />
    );
  },
  play: async ({ canvas, userEvent }) => {
    const button = canvas.getByRole('button');
    await expect(button).toHaveTextContent('Inactive');

    await userEvent.click(button);
    await expect(button).toHaveTextContent('Active');

    await userEvent.click(button);
    await expect(button).toHaveTextContent('Inactive');
  },
};
```

### useEffect

```typescript
export const AutoFocus: Story = {
  play: async ({ canvas }) => {
    const input = canvas.getByRole('textbox');
    await expect(input).toHaveFocus();
  },
};
```

### Custom Hooks

Test components that use custom hooks by rendering them normally. Storybook runs in a real browser so hooks work as expected:

```typescript
export const DebouncedSearch: Story = {
  play: async ({ canvas, userEvent }) => {
    const input = canvas.getByRole('searchbox');
    await userEvent.type(input, 'react');

    // Wait for debounced results
    const results = await canvas.findByRole('list');
    await expect(results).toBeInTheDocument();
  },
};
```

## Mocking Network Requests (MSW)

Use [MSW](https://mswjs.io/) with `msw-storybook-addon` to intercept network requests at the service worker level. This is the recommended approach for components that fetch data via `fetch()` or API clients.

### Setup

```bash
npm install msw msw-storybook-addon --save-dev
npx msw init public/
```

```typescript
// .storybook/preview.ts
import { initialize, mswLoader } from 'msw-storybook-addon';

initialize();

const preview: Preview = {
  loaders: [mswLoader],
};
```

Ensure `.storybook/main.ts` includes `staticDirs: ['../public']` so the service worker is served.

### Per-Story Handlers

```typescript
import { http, HttpResponse } from 'msw';

export const WithUsers: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get('/api/users', () =>
          HttpResponse.json([
            { id: 1, name: 'Alice' },
            { id: 2, name: 'Bob' },
          ])
        ),
      ],
    },
  },
};

export const NetworkError: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get('/api/users', () =>
          HttpResponse.error()
        ),
      ],
    },
  },
};
```

### GraphQL

```typescript
import { graphql, HttpResponse } from 'msw';

export const WithData: Story = {
  parameters: {
    msw: {
      handlers: [
        graphql.query('GetUsers', () =>
          HttpResponse.json({
            data: { users: [{ id: 1, name: 'Alice' }] },
          })
        ),
      ],
    },
  },
};
```

## Loaders (Async Data Before Render — Advanced Escape Hatch)

Prefer args for data, decorators for providers, and module mocks for imports. Use loaders only when the story truly needs async setup before render.

```typescript
const meta = {
  component: TodoItem,
  render: (args, { loaded: { todo } }) => <TodoItem {...args} {...todo} />,
} satisfies Meta<typeof TodoItem>;

export const FromAPI: Story = {
  loaders: [
    async () => ({
      todo: await (
        await fetch('https://jsonplaceholder.typicode.com/todos/1')
      ).json(),
    }),
  ],
};
```

Loader precedence (lowest to highest): Global -> Component -> Story. All loaders at the same level run in parallel. Later loaders override earlier ones with matching keys.

## Story Globals (Storybook 9+)

Set context variables per-story:

```typescript
export const Default: Story = {
  args: { label: 'Button' },
};

export const Dark: Story = {
  ...Default,
  globals: { theme: 'dark' },
};

export const Mobile: Story = {
  ...Default,
  globals: { viewport: 'mobile' },
};
```

## Variant Testing Pattern

Test individual variants while showing a combined story in the sidebar:

```typescript
export const Small: Story = {
  tags: ['!dev', '!autodocs'],
  args: { size: 'small', label: 'Small' },
};

export const Large: Story = {
  tags: ['!dev', '!autodocs'],
  args: { size: 'large', label: 'Large' },
};

// Combined view for sidebar
export const AllSizes: Story = {
  tags: ['!test'],
  render: () => (
    <>
      <Button size="small" label="Small" />
      <Button size="medium" label="Medium" />
      <Button size="large" label="Large" />
    </>
  ),
};
```

## Common TypeScript Errors

**Type '...' is not assignable to type 'Args'**
Use `satisfies Meta<typeof Component>` instead of `: Meta<typeof Component>`.

**Property '...' does not exist on type**
Ensure `StoryObj<typeof meta>` uses `typeof meta` (not `typeof Component`).

**Cannot find module '@storybook/test'**
In Storybook 9+, import from `storybook/test` (not `@storybook/test`).

## Performance Optimization

- Use `react-docgen` instead of `react-docgen-typescript` for faster builds (trade-off: less complete prop extraction).
- Use `build: { test: {} }` in main.ts for optimized production builds.
- Limit stories per file (aim for under 20 per component).
- Use lazy-loaded decorators for heavy providers.

## When to Use Which Test Type

| Test Type | Best For |
|---|---|
| Render tests (stories) | Smoke testing, visual documentation |
| Interaction tests (play) | User flows, form validation, callbacks |
| Accessibility tests | WCAG compliance, keyboard navigation |
| Visual regression | Pixel-perfect UI, design system consistency |
| Portable stories | Integration with existing test suites |
| Unit tests (external) | Pure logic, utilities, hooks in isolation |
| E2E tests | Full application flows across pages |
