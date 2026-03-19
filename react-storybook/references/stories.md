# Writing Stories for Complex Components

This file covers advanced story patterns for components with complex prop types. For CSF3 basics, args, decorators, and play functions, see `SKILL.md`.

## ArgTypes (Controls Configuration)

```typescript
const meta = {
  component: Button,
  argTypes: {
    backgroundColor: { control: 'color' },

    size: {
      control: { type: 'select' },
      options: ['small', 'medium', 'large'],
    },

    // Map simple values to complex types (JSX, objects)
    icon: {
      control: { type: 'select' },
      options: ['None', 'Star', 'Heart'],
      mapping: {
        None: null,
        Star: <StarIcon />,
        Heart: <HeartIcon />,
      },
    },

    // Disable a control
    children: { control: false },
  },
} satisfies Meta<typeof Button>;
```

## Runtime Arg Updates with useArgs

```typescript
import { useArgs } from 'storybook/preview-api';

export const Controlled: Story = {
  args: { isChecked: false },
  render: function Render(args) {
    const [{ isChecked }, updateArgs] = useArgs();

    function onChange() {
      updateArgs({ isChecked: !isChecked });
    }

    return <Checkbox {...args} isChecked={isChecked} onChange={onChange} />;
  },
};
```

## Components with Generics

TypeScript generic type parameters are not valid in value expressions, so pass the base component and use a render function for the generic instantiation:

```typescript
interface DataTableProps<T> {
  data: T[];
  columns: Column<T>[];
  onRowClick?: (row: T) => void;
}

type User = { id: number; name: string; email: string };

const meta = {
  component: DataTable,
  render: (args) => <DataTable<User> {...args} />,
} satisfies Meta<typeof DataTable>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {
  args: {
    data: [{ id: 1, name: 'Alice', email: 'alice@example.com' }],
    columns: [
      { key: 'name', header: 'Name' },
      { key: 'email', header: 'Email' },
    ],
  },
};
```

## Components with Union Props

```typescript
interface AlertProps {
  severity: 'error' | 'warning' | 'info' | 'success';
  children: React.ReactNode;
}

const meta = {
  component: Alert,
  argTypes: {
    severity: {
      control: { type: 'select' },
      options: ['error', 'warning', 'info', 'success'],
    },
  },
} satisfies Meta<typeof Alert>;

export const Error: Story = { args: { severity: 'error', children: 'Error!' } };
export const Warning: Story = { args: { severity: 'warning', children: 'Warning!' } };
```

## Components with Callback Props

```typescript
import { fn, expect } from 'storybook/test';

const meta = {
  component: SearchInput,
  args: {
    onChange: fn(),
    onSubmit: fn(),
    onClear: fn(),
  },
} satisfies Meta<typeof SearchInput>;

export const WithSearch: Story = {
  play: async ({ args, canvas, userEvent }) => {
    await userEvent.type(canvas.getByRole('textbox'), 'search term');
    await expect(args.onChange).toHaveBeenCalled();

    await userEvent.click(canvas.getByRole('button', { name: 'Search' }));
    await expect(args.onSubmit).toHaveBeenCalledWith('search term');
  },
};
```

## Components with Children (ReactNode)

```typescript
const meta = {
  component: Card,
  render: (args) => (
    <Card {...args}>
      <p>Card content goes here</p>
    </Card>
  ),
} satisfies Meta<typeof Card>;
```

## Context-Aware Decorators

```typescript
const meta = {
  component: Page,
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
} satisfies Meta<typeof Page>;

export const DarkMode: Story = {
  parameters: { theme: 'dark' },
};
```

## Parameters (Addon Configuration)

Static metadata for configuring addons. Not reactive (unlike args).

```typescript
const meta = {
  component: Button,
  parameters: {
    backgrounds: {
      options: {
        light: { name: 'Light', value: '#ffffff' },
        dark: { name: 'Dark', value: '#333333' },
      },
    },
    layout: 'centered', // 'centered' | 'fullscreen' | 'padded'
    a11y: { test: 'error' },
  },
} satisfies Meta<typeof Button>;
```

## Render Functions with Context

```typescript
export const WithContext: Story = {
  render: (args, { globals, parameters }) => (
    <div data-theme={globals.theme}>
      <Button {...args} />
    </div>
  ),
};
```

## File Naming and Organization

- `Button.stories.tsx` — standard (use `.tsx` when stories contain JSX)
- `Button.stories.ts` — when stories are args-only (no JSX)
- Co-locate story files with components: `src/components/Button/Button.stories.tsx`

```
src/
  components/
    Button/
      Button.tsx
      Button.stories.tsx
      Button.test.tsx
    Form/
      Form.tsx
      Form.stories.tsx
```

## Story Display Names

```typescript
export const Primary: Story = { args: { label: 'Button' } };

// Custom display name
export const Primary: Story = {
  name: 'Primary Button',
  args: { label: 'Button' },
};
```
