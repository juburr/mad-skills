# Material UI TypeScript Reference

TypeScript patterns, type imports, and component typing for MUI v5 through v7. Covers import strategies, generic components, wrapping patterns, theme augmentation, and v7-specific type changes.

## Type Import Patterns

### `moduleResolution` Requirement

v7's `exports` field in `package.json` requires TypeScript to use a module resolution mode that understands `exports`. The legacy `"node"` (aka `"node10"`) mode ignores `exports` entirely, causing imports like `@mui/material/useAutocomplete` to fail with "module not found" errors and breaking type inheritance chains across module boundaries.

```jsonc
// tsconfig.json — required for MUI v7
{
  "compilerOptions": {
    "module": "preserve",
    "moduleResolution": "bundler"
  }
}
```

Use `"bundler"` for any project using a bundler (Vite, webpack, Next.js, esbuild). This is what MUI uses in their own repo and what TypeScript recommends for bundled frontend applications. Only use `"node16"` / `"nodenext"` if the code runs directly in Node.js without a bundler (it requires `.js` extensions on all relative imports).

If `moduleResolution` is not updated, symptoms include:
- `UseAutocompleteProps` or other types appearing unresolvable from `@mui/material/useAutocomplete`
- Properties from parent interfaces (e.g., `onChange` on `AutocompleteProps`) showing as nonexistent
- TS2307 "Cannot find module" errors on valid single-level deep imports

**Build tool caveat:** Setting `moduleResolution` in `tsconfig.json` is necessary but not sufficient if your build tool ships its own TypeScript version. For example, microbundle (last updated 2022) pins TypeScript 4.1 internally, which predates the `"bundler"` option (added in TypeScript 5.0) and cannot resolve `exports` fields. If your IDE shows correct types but your build fails, verify that your build tool uses your project's TypeScript version, not a bundled one. Tools like tsup, Vite, and tsc use the project's own TypeScript as a peer dependency and do not have this issue.

### v7 ESM `exports` Field Impact

v7 enforces the `exports` field in `package.json`. Deep imports beyond one level no longer resolve:

```tsx
// BROKEN in v7 — deep imports restricted by exports field
import createTheme from "@mui/material/styles/createTheme";
import type { ButtonProps } from "@mui/material/Button/Button";

// CORRECT — single-level deep imports
import { createTheme } from "@mui/material/styles";
import type { ButtonProps } from "@mui/material/Button";
```

This applies equally to value imports and type imports. The available import paths are:
- `@mui/material` — top-level barrel (re-exports all components and types)
- `@mui/material/<ComponentName>` — component barrel (e.g., `@mui/material/Button`)
- `@mui/material/styles` — theme, styled, color utilities
- `@mui/material/useAutocomplete` — Autocomplete hook and its types
- `@mui/material/utils` — utility types (`SlotProps`, `CreateSlotsAndSlotProps`)

### Importing Component Props Types

Every component exports its props interface from its barrel file:

```tsx
// Direct import from component barrel (recommended for dev build speed)
import type { ButtonProps } from "@mui/material/Button";
import type { TextFieldProps } from "@mui/material/TextField";
import type { AutocompleteProps } from "@mui/material/Autocomplete";
import type { DialogProps } from "@mui/material/Dialog";

// Top-level barrel (also works, but slower dev builds)
import type { ButtonProps, TextFieldProps } from "@mui/material";
```

### Using `React.ComponentProps` as an Alternative

When you do not want to look up the exact props type name, derive it from the component:

```tsx
import Button from "@mui/material/Button";
import Autocomplete from "@mui/material/Autocomplete";

type MyButtonProps = React.ComponentProps<typeof Button>;

// For generic components like Autocomplete, ComponentProps resolves
// to the props with default type parameters (all false/undefined).
// Prefer the explicit import when you need specific generic arguments.
type DefaultAutocompleteProps = React.ComponentProps<typeof Autocomplete>;
```

`React.ComponentProps<typeof Component>` works for any component, but for generics like `Autocomplete` it locks you into default type parameters. Use the named export (e.g., `AutocompleteProps<MyOption, true, false, false>`) when you need control over generics.

## Working with Generic Component Types

### Autocomplete Generics

`AutocompleteProps` has four required type parameters (plus an optional fifth):

```tsx
import type { AutocompleteProps } from "@mui/material/Autocomplete";

// AutocompleteProps<Value, Multiple, DisableClearable, FreeSolo, ChipComponent?>
//   Value             — the option type
//   Multiple          — boolean: multi-select mode
//   DisableClearable  — boolean: whether clear button is hidden
//   FreeSolo          — boolean: whether arbitrary text is allowed
//   ChipComponent     — (optional) element type for multi-select chips

// Single-select, clearable, not free solo
type MySingleProps = AutocompleteProps<MyOption, false, false, false>;

// Multi-select, not clearable, not free solo
type MyMultiProps = AutocompleteProps<MyOption, true, true, false>;
```

### Autocomplete Hook Types

`UseAutocompleteProps` IS exported from `@mui/material/useAutocomplete` in v7 (and re-exported from the top-level barrel). It contains the behavioral props (`autoHighlight`, `openOnFocus`, `getOptionDisabled`, `filterOptions`, `onChange`, etc.), while `AutocompleteProps` extends it with UI props (`renderInput`, `size`, `sx`, slots/slotProps, etc.).

```tsx
// Importing hook types directly
import type {
  UseAutocompleteProps,
  AutocompleteChangeReason,
  AutocompleteChangeDetails,
  AutocompleteInputChangeReason,
  AutocompleteCloseReason,
  AutocompleteValue,
  AutocompleteFreeSoloValueMapping,
} from "@mui/material/useAutocomplete";

// Importing component types
import type {
  AutocompleteProps,
  AutocompleteRenderInputParams,
  AutocompleteRenderOptionState,
  AutocompleteRenderGroupParams,
  AutocompleteOwnerState,
  AutocompleteRenderGetTagProps,
} from "@mui/material/Autocomplete";
```

### TextField Variant Types

`TextField` uses a discriminated union based on the `variant` prop:

```tsx
import type {
  TextFieldProps,
  TextFieldVariants,
  BaseTextFieldProps,
  StandardTextFieldProps,
  FilledTextFieldProps,
  OutlinedTextFieldProps,
} from "@mui/material/TextField";

// TextFieldProps is a conditional type; narrow with the Variant parameter:
type OutlinedOnly = TextFieldProps<"outlined">;

// BaseTextFieldProps is the shared interface (variant-agnostic)
```

### Button TypeMap Pattern

`Button` uses the `OverridableComponent` pattern, allowing the `component` prop to change the rendered element and its accepted props:

```tsx
import type { ButtonProps, ButtonTypeMap } from "@mui/material/Button";

// ButtonProps accepts an optional RootComponent type parameter:
type LinkButtonProps = ButtonProps<"a", { href: string }>;

// This is equivalent to OverrideProps<ButtonTypeMap<{href: string}, 'a'>, 'a'>
```

## Wrapping and Extending MUI Components

### Simple Prop Forwarding Wrapper

```tsx
import Button from "@mui/material/Button";
import type { ButtonProps } from "@mui/material/Button";

interface PrimaryButtonProps extends Omit<ButtonProps, "color" | "variant"> {
  // Lock down color and variant; expose everything else
}

function PrimaryButton(props: PrimaryButtonProps) {
  return <Button color="primary" variant="contained" {...props} />;
}
```

### Wrapping a Generic Component (Autocomplete)

For components with type parameters, explicitly define the generics:

```tsx
import Autocomplete from "@mui/material/Autocomplete";
import TextField from "@mui/material/TextField";
import type { AutocompleteProps } from "@mui/material/Autocomplete";

interface SearchFieldProps<T>
  extends Omit<
    AutocompleteProps<T, false, false, false>,
    "renderInput"
  > {
  label: string;
  placeholder?: string;
}

function SearchField<T>({ label, placeholder, ...rest }: SearchFieldProps<T>) {
  return (
    <Autocomplete
      {...rest}
      renderInput={(params) => (
        <TextField {...params} label={label} placeholder={placeholder} />
      )}
    />
  );
}
```

**Important:** When extending `AutocompleteProps` with `Omit`, always use literal `true`/`false` (not `boolean`) for the generic parameters. Using `boolean` forces TypeScript to evaluate both branches of every conditional type, creating 2^3 = 8 type variations and risking TS2589 errors. See [Avoiding TS2589](#avoiding-ts2589-excessively-deep-type-instantiation) for details. (If you need a wrapper that supports both single and multi-select modes, see Fix 3 in that section for a safe approach using `UseAutocompleteProps`.)

### Polymorphic Wrapper with `component` Prop

```tsx
import Typography from "@mui/material/Typography";
import type { TypographyProps } from "@mui/material/Typography";

// Fixed component type
function Heading(props: TypographyProps<"h2">) {
  return <Typography component="h2" variant="h4" {...props} />;
}

// Forwarded component type
function FlexibleHeading<C extends React.ElementType = "h2">(
  props: TypographyProps<C, { component?: C }>
) {
  return <Typography component={"h2" as C} variant="h4" {...props} />;
}
```

### Preserving `muiName` for Internal Detection

When wrapping a component that other MUI components detect (e.g., `ListItemIcon`, `Step`), preserve the `muiName` static property:

```tsx
import SvgIcon from "@mui/material/SvgIcon";
import type { SvgIconProps } from "@mui/material/SvgIcon";

const CustomIcon = (props: SvgIconProps) => <SvgIcon {...props} />;
CustomIcon.muiName = "SvgIcon"; // Required for MUI internal detection
```

### Ref Forwarding

Components passed as slot overrides or wrapped components used as `component` prop values must forward refs:

```tsx
import React from "react";
import type { ButtonProps } from "@mui/material/Button";

const FancyButton = React.forwardRef<HTMLButtonElement, ButtonProps>(
  (props, ref) => (
    <button ref={ref} className="fancy" {...props} />
  )
);
```

## Theme Type Augmentation

### Module Augmentation Path

All theme augmentation uses `@mui/material/styles`:

```tsx
// theme.d.ts (or any .d.ts / .ts file included in tsconfig)

declare module "@mui/material/styles" {
  // Add custom palette colors
  interface Palette {
    neutral: Palette["primary"];
  }
  interface PaletteOptions {
    neutral?: PaletteOptions["primary"];
  }

  // Add custom typography variants
  interface TypographyVariants {
    poster: React.CSSProperties;
  }
  interface TypographyVariantsOptions {
    poster?: React.CSSProperties;
  }

  // Add custom breakpoints
  interface BreakpointOverrides {
    xxl: true;
  }

  // Enable CSS theme variables
  interface CssThemeVariables {
    enabled: true;
  }
}
```

### Augmenting Component Props

Extend prop override interfaces to add custom values:

```tsx
// Allow color="neutral" on Button
declare module "@mui/material/Button" {
  interface ButtonPropsColorOverrides {
    neutral: true;
  }
  interface ButtonPropsVariantOverrides {
    dashed: true;
  }
  interface ButtonPropsSizeOverrides {
    extraLarge: true;
  }
}

// Allow size="extraSmall" on Autocomplete
declare module "@mui/material/Autocomplete" {
  interface AutocompletePropsSizeOverrides {
    extraSmall: true;
  }
}

// Allow color="neutral" on TextField
declare module "@mui/material/TextField" {
  interface TextFieldPropsColorOverrides {
    neutral: true;
  }
}
```

### Augmenting Slot Props

Override slot props interfaces to add custom properties:

```tsx
declare module "@mui/material/Autocomplete" {
  interface AutocompletePaperSlotPropsOverrides {
    variant?: "elevation" | "outlined";
  }
  interface AutocompletePopperSlotPropsOverrides {
    placement?: string;
  }
}
```

## v7 Type Changes from v5/v6

### Removed Types and Renames

| Removed / Changed | Replacement |
|---|---|
| `StepButtonIcon` type | `StepButtonProps["icon"]` |
| `TypographyOptions` (in theme context) | `TypographyVariantsOptions` |
| `Typography` (in theme context) | `TypographyVariants` |
| `createMuiTheme` | `createTheme` |
| `experimentalStyled` | `styled` |
| `StyledEngineProvider` from `@mui/material` | Import from `@mui/material/styles` |

### Minimum TypeScript Version

- v5: TypeScript >= 3.5
- v6: TypeScript >= 4.7
- v7: TypeScript >= 4.9

### Deep Import Path Module Augmentation

Theme augmentation that used deep import paths must be updated:

```tsx
// BROKEN in v7
declare module "@mui/material/styles/createTypography" {
  interface TypographyOptions { /* ... */ }
}
declare module "@mui/material/styles/createPalette" {
  interface PaletteOptions { /* ... */ }
}

// CORRECT in v7
declare module "@mui/material/styles" {
  interface TypographyVariantsOptions { /* ... */ }
  interface PaletteOptions { /* ... */ }
}
```

### Grid Type Changes

```tsx
// v6: Grid2 import
import Grid from "@mui/material/Grid2";
import type { Grid2Props } from "@mui/material/Grid2";

// v7: Grid2 renamed to Grid
import Grid from "@mui/material/Grid";
import type { GridProps } from "@mui/material/Grid";

// v7: Legacy Grid renamed to GridLegacy
import Grid from "@mui/material/GridLegacy";
import type { GridLegacyProps } from "@mui/material/GridLegacy";
```

### `react-is` Version Alignment

v7 depends on `react-is@19`. If your project uses React 18 or below, add a resolution pinning `react-is` to match your React major version:

```json
// package.json — React 18 (npm/pnpm)
{
  "overrides": {
    "react-is": "^18.0.0"
  }
}
// package.json — React 18 (Yarn)
{
  "resolutions": {
    "react-is": "^18.0.0"
  }
}

// package.json — React 17 (npm/pnpm)
{
  "overrides": {
    "react-is": "^17.0.0"
  }
}
```

## Slots and SlotProps Typing

### Using `slotProps` with Type Safety

The `slots`/`slotProps` pattern is fully typed. Each component defines its own `Slots` and `SlotProps` interfaces:

```tsx
import Autocomplete from "@mui/material/Autocomplete";
import TextField from "@mui/material/TextField";
import CustomPaper from "./CustomPaper";
import CustomPopper from "./CustomPopper";

<Autocomplete
  options={options}
  renderInput={(params) => <TextField {...params} label="Search" />}
  slots={{
    paper: CustomPaper,   // typed as JSXElementConstructor<PaperProps>
    popper: CustomPopper,  // typed as JSXElementConstructor<PopperProps>
  }}
  slotProps={{
    paper: { elevation: 8 },      // typed as Partial<PaperProps>
    popper: { placement: "top" },  // typed as Partial<PopperProps>
    chip: { size: "small" },       // typed as Partial<ChipProps>
    listbox: { sx: { maxHeight: 300 } },
  }}
/>
```

### Slot Props Override Interfaces

Components expose empty override interfaces that you can augment to add custom slot props:

```tsx
declare module "@mui/material/TextField" {
  interface TextFieldInputSlotPropsOverrides {
    customProp?: string;
  }
}

// Now customProp is accepted in slotProps.input
<TextField slotProps={{ input: { customProp: "value" } }} />
```

## Common Patterns

### Typing Event Handlers

```tsx
import type { AutocompleteChangeReason } from "@mui/material/Autocomplete";
import type { SelectChangeEvent } from "@mui/material/Select";

// Autocomplete onChange
const handleChange = (
  event: React.SyntheticEvent,
  value: MyOption | null,
  reason: AutocompleteChangeReason
) => { /* ... */ };

// Select onChange (uses its own event type)
const handleSelect = (event: SelectChangeEvent<string>) => {
  const value = event.target.value;
};

// TextField onChange
const handleInput = (event: React.ChangeEvent<HTMLInputElement>) => {
  const value = event.target.value;
};
```

### Typing `renderInput` for Autocomplete

```tsx
import type { AutocompleteRenderInputParams } from "@mui/material/Autocomplete";

const renderInput = (params: AutocompleteRenderInputParams) => (
  <TextField
    {...params}
    label="Search"
    slotProps={{
      input: {
        ...params.InputProps,
        startAdornment: (
          <>
            <SearchIcon />
            {params.InputProps.startAdornment}
          </>
        ),
      },
    }}
  />
);
```

### Typing `renderOption` for Autocomplete

```tsx
import type { AutocompleteRenderOptionState } from "@mui/material/Autocomplete";

// The props object includes a `key` property (added in v5.10.0)
const renderOption = (
  props: React.HTMLAttributes<HTMLLIElement> & { key: React.Key },
  option: MyOption,
  state: AutocompleteRenderOptionState
) => {
  const { key, ...rest } = props;
  return (
    <li key={key} {...rest}>
      {option.label} {state.selected && "(selected)"}
    </li>
  );
};
```

### Typing Custom `filterOptions`

```tsx
import { createFilterOptions } from "@mui/material/Autocomplete";

interface MyOption {
  id: number;
  label: string;
  description: string;
}

// Generic parameter inferred from usage, or specify explicitly:
const filterOptions = createFilterOptions<MyOption>({
  matchFrom: "any",
  stringify: (option) => `${option.label} ${option.description}`,
});
```

## Avoiding TS2589: Excessively Deep Type Instantiation

TS2589 ("Type instantiation is excessively deep and possibly infinite") is a long-standing issue with MUI's type system, tracked upstream at [mui/material-ui#19113](https://github.com/mui/material-ui/issues/19113) and [microsoft/TypeScript#34801](https://github.com/microsoft/TypeScript/issues/34801). It is not specific to v7 — it has existed since v4/v5 — but it can surface during migrations when type patterns are adjusted.

### Root Cause

MUI's slot system creates a **circular type reference** in heavily generic components. The chain for Autocomplete:

1. `AutocompleteProps` extends `AutocompleteSlotsAndSlotProps`
2. `AutocompleteSlotsAndSlotProps` contains 6 `SlotProps<..., AutocompleteOwnerState>` definitions
3. `AutocompleteOwnerState` extends `AutocompleteProps` (back to step 1)

Each slot also requires resolving `React.ComponentPropsWithRef<TSlotComponent>` for complex component types (`ChipProps`, `IconButtonProps`, `PaperProps`, `PopperProps`), each with their own deep type chains.

When TypeScript encounters an `Omit`, `Pick`, or other mapped type over this structure, it must traverse the full intersection, expanding all conditional types and slot definitions. This regularly exceeds TypeScript's instantiation depth budget (~50 levels).

### Most Affected Components

| Component | Severity | Reason |
|---|---|---|
| Autocomplete | High | 5 generic params, 6 slots, circular OwnerState reference |
| Select | Medium | Generic `<T>` + polymorphic `component` prop |
| TextField | Medium | Discriminated union across 3 variants, 6 slots |
| Button / LoadingButton | Medium | `ExtendButtonBase` + `OverridableComponent` layering |
| Any `styled()` wrapper | Medium | Each `styled()` layer adds type depth; ~4-5 levels triggers TS2589 |

### Fix 1: Use Literal `true`/`false`, Not `boolean`

The single most impactful fix. MUI's `AutocompleteValue` is a triple-nested conditional type that branches on `Multiple`, `DisableClearable`, and `FreeSolo`. Using `boolean` forces TypeScript to evaluate all 2^3 = 8 branch combinations.

```tsx
// BAD — 8x type branching, likely triggers TS2589
type Props = AutocompleteProps<MyOption, boolean, boolean, boolean>;
type Wrapped = Omit<Props, "renderInput">;

// GOOD — single branch, resolves quickly
type Props = AutocompleteProps<MyOption, false, false, false>;
type Wrapped = Omit<Props, "renderInput">;

// GOOD — multi-select variant
type MultiProps = AutocompleteProps<MyOption, true, false, false>;
```

### Fix 2: Use `Pick` Instead of `Omit`

`Omit` must traverse ALL keys of the type to exclude a few. `Pick` only resolves the keys you actually need.

```tsx
// BAD — resolves entire AutocompleteProps to exclude one key
interface MyProps extends Omit<
  AutocompleteProps<MyOption, false, false, false>,
  "renderInput"
> {}

// GOOD — only resolves the props you actually use
interface MyProps extends Pick<
  AutocompleteProps<MyOption, false, false, false>,
  "options" | "value" | "onChange" | "loading" | "disabled" | "sx"
> {
  label: string;
}
```

### Fix 3: Build a Flat Interface from `UseAutocompleteProps`

For wrapper components, bypass the slot/OwnerState circular chain entirely by extending the hook props (which have no circular references) and adding only the UI props you need:

```tsx
import type { UseAutocompleteProps } from "@mui/material/useAutocomplete";
import type { SxProps, Theme } from "@mui/material/styles";

// UseAutocompleteProps has NO circular type references
interface MyAutocompleteProps<T>
  extends UseAutocompleteProps<T, false, false, false> {
  label: string;
  placeholder?: string;
  size?: "small" | "medium";
  fullWidth?: boolean;
  loading?: boolean;
  sx?: SxProps<Theme>;
}
```

This avoids the `AutocompleteSlotsAndSlotProps` → `AutocompleteOwnerState` → `AutocompleteProps` cycle entirely.

If your wrapper genuinely supports both single-select and multi-select modes (toggled by a runtime prop), use `boolean` for the `Multiple` parameter — this is safe with `UseAutocompleteProps` because it has no circular type references:

```tsx
// Dual-mode wrapper — boolean is SAFE here (no slot/OwnerState chain)
interface DualModeAutocompleteProps<T>
  extends UseAutocompleteProps<T, boolean, false, false> {
  label: string;
  multiple?: boolean;
}
```

TypeScript distributes `AutocompleteValue<T, boolean, ...>` over the `true | false` union, producing exactly the union of single-select and multi-select value types — no `as any` cast needed.

Do NOT use `boolean` with `AutocompleteProps` in the same way; the circular slot chain makes it a TS2589 risk.

### Fix 4: Fix Generic Parameters to Concrete Types

Forwarding all generic parameters through a wrapper multiplies type resolution work. Fix the parameters to the specific variant you need:

```tsx
// BAD — forwarding all 4 generics through the wrapper
interface SearchFieldProps<T, M extends boolean | undefined, D extends boolean | undefined, F extends boolean | undefined>
  extends Omit<AutocompleteProps<T, M, D, F>, "renderInput"> {}

// GOOD — fix the boolean params, only forward the option type
interface SearchFieldProps<T>
  extends Omit<AutocompleteProps<T, false, false, false>, "renderInput"> {
  label: string;
}
```

### Fix 5: Cast `styled()` Wrappers to Preserve Types

Each `styled()` layer adds type depth. At 4-5 levels of styled inheritance, TS2589 triggers. Cast back to the original component type:

```tsx
import { styled } from "@mui/material/styles";
import Button from "@mui/material/Button";

// Without cast: adds type depth, may trigger TS2589 with further wrapping
const StyledButton = styled(Button)({ borderRadius: 20 });

// With cast: preserves original Button types without added depth
const StyledButton = styled(Button)({ borderRadius: 20 }) as typeof Button;
```

### Fix 6: Use Direct Imports, Not Barrel Imports

Barrel imports force TypeScript to resolve types for all ~76 MUI components. Direct imports resolve only the one you need:

```tsx
// SLOW — resolves all MUI component types
import { Autocomplete, TextField, Button } from "@mui/material";

// FAST — resolves only the specific component types
import Autocomplete from "@mui/material/Autocomplete";
import TextField from "@mui/material/TextField";
import Button from "@mui/material/Button";
```

Next.js 13.5+ can automate this with `optimizePackageImports: ["@mui/material", "@mui/icons-material"]` in `next.config.js`.

### Fix 7: `skipLibCheck` as a Last Resort

If you cannot restructure the types and need to unblock builds:

```json
{
  "compilerOptions": {
    "skipLibCheck": true
  }
}
```

This skips type checking of `.d.ts` files. It does not affect type checking of your own code, but it may mask legitimate type errors in third-party libraries or your own declaration files.
