# Material UI Migration Reference

Comprehensive guide for migrating between Material UI major versions. Covers package renames, API breaking changes, styling system changes, codemods, and step-by-step checklists.

## Table of Contents

- [Version Overview](#version-overview)
- [v3 to v4 Migration](#v3-to-v4-migration)
- [v4 to v5 Migration](#v4-to-v5-migration)
- [v5 to v6 Migration](#v5-to-v6-migration)
- [v6 to v7 Migration](#v6-to-v7-migration)
- [v7 to v9 Migration](#v7-to-v9-migration)
- [Grid v1 to Grid v2 Migration](#grid-v1-to-grid-v2-migration)
- [Migrating from Deprecated APIs](#migrating-from-deprecated-apis)
- [Pickers Migration](#pickers-migration)
- [Migrating from JSS to Emotion](#migrating-from-jss-to-emotion)
- [Pigment CSS Integration](#pigment-css-integration)
- [Codemod Reference](#codemod-reference)

---

## Version Overview

| Migration | Difficulty | Key Changes |
|-----------|-----------|-------------|
| v3 -> v4 | Moderate | React Hooks, JSS v10, typography variants, spacing API |
| v4 -> v5 | **Major** | `@material-ui/*` -> `@mui/*`, JSS -> Emotion, theme restructure |
| v5 -> v6 | Minor | Pigment CSS (opt-in), Grid2 stabilized, minimal breaking changes |
| v6 -> v7 | Minor | ESM exports, Grid renamed, deprecated APIs removed, CSS layers |
| v7 -> v9 | Minor | **v9 is alpha/pre-release.** v8 skipped, `disableEscapeKeyDown` removed from Dialog/Modal |

---

## v3 to v4 Migration

### Checklist

- [ ] Update `@material-ui/core` to `^4.0.0`
- [ ] Update React to `>=16.8.0` (Hooks required)
- [ ] Update `@material-ui/styles` to `^4.0.0` if used
- [ ] Update JSS to v10 (remove `react-jss` if present)
- [ ] Migrate typography variants
- [ ] Migrate `theme.spacing.unit` to `theme.spacing()`
- [ ] Update deprecated component props

### Package Changes

```
@material-ui/core: ^3.x.x -> ^4.0.0
@material-ui/styles: ^3.x.x -> ^4.0.0
react: ^16.3.0 -> ^16.8.0 (minimum)
```

### Key Breaking Changes

#### Styles (JSS v10)

- JSS v10 is **not** backward compatible with v9. Remove `react-jss` from `package.json`.
- `StylesProvider` replaces `JssProvider`.
- Remove first argument from `withTheme()`:
  ```diff
  -const DeepChild = withTheme()(DeepChildRaw);
  +const DeepChild = withTheme(DeepChildRaw);
  ```
- Rename `convertHexToRGB` to `hexToRgb`.
- Keyframe animations require `$` prefix: `animation: '$mui-ripple-enter ...'`.

#### Theme

- `theme.spacing.unit` is deprecated. Use `theme.spacing()`:
  ```diff
  -paddingTop: theme.spacing.unit * 12,
  +paddingTop: theme.spacing(12),
  ```
- `theme.palette.augmentColor()` no longer performs side effects; use the returned value.
- Remove `useNextVariants: true` from typography config.

#### Typography Variant Renames

```
display4 -> h1       headline -> h5
display3 -> h2       title -> h6
display2 -> h3       subheading -> subtitle1
display1 -> h4       body2 -> body1, body1 -> body2
```

- Default variant changed from `body2` to `body1`.
- Rename `headlineMapping` to `variantMapping`.
- `color="default"` renamed to `color="initial"`.

#### Button

```diff
-<Button variant="raised" />    ->  <Button variant="contained" />
-<Button variant="flat" />      ->  <Button variant="text" />
-<Button variant="fab" />       ->  <Fab />
-<Button variant="extendedFab" /> -> <Fab variant="extended" />
```

#### Grid Spacing API

```diff
-spacing: PropTypes.oneOf([0, 8, 16, 24, 32, 40])
+spacing: PropTypes.oneOf([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
```

#### Other Component Changes

- `Container` moved from `@material-ui/lab` to `@material-ui/core`.
- `Slider` moved from `@material-ui/lab` to `@material-ui/core`.
- `Divider`: `inset` prop removed, use `variant="inset"`.
- `ExpansionPanel`: `CollapseProps` renamed to `TransitionProps`.
- `TableCell`: `numeric` removed, use `align="right"`; `padding="dense"` -> `size="small"`.
- `SvgIcon`: `nativeColor` renamed to `htmlColor`.
- `Tabs`: `fullWidth` and `scrollable` removed, use `variant="scrollable"`.
- `Paper`: default elevation reduced.

#### Codemod

```bash
npx @mui/codemod@latest v4.0.0/theme-spacing-api src
```

---

## v4 to v5 Migration

This is the **largest migration** between any two MUI versions. The package namespace changes from `@material-ui/*` to `@mui/*`, and the default styling engine changes from JSS to Emotion.

### Checklist

- [ ] Update React to `>=17.0.0`
- [ ] Update TypeScript to `>=3.5`
- [ ] Install v5 packages: `@mui/material`, `@mui/styles` (temporary for JSS)
- [ ] Install Emotion: `@emotion/react`, `@emotion/styled`
- [ ] Replace all `@material-ui/*` imports with `@mui/*`
- [ ] Run `preset-safe` codemod
- [ ] Run `variant-prop` codemod (if keeping `variant="standard"`)
- [ ] Run `link-underline-hover` codemod (if keeping `underline="hover"`)
- [ ] Ensure `ThemeProvider` is at the root of your app
- [ ] Set up `StyledEngineProvider` with `injectFirst` if using JSS alongside Emotion
- [ ] Address manual breaking changes (styles, themes, components)
- [ ] Progressively migrate from JSS to Emotion/styled/sx
- [ ] Remove `@material-ui/*` packages

### Package Name Changes

```
@material-ui/core         -> @mui/material
@material-ui/icons        -> @mui/icons-material
@material-ui/styles       -> @mui/styles
@material-ui/system       -> @mui/system
@material-ui/lab          -> @mui/lab
@material-ui/types        -> @mui/types
@material-ui/unstyled     -> @mui/base
@material-ui/codemod      -> @mui/codemod
@material-ui/styled-engine -> @mui/styled-engine
@material-ui/styled-engine-sc -> @mui/styled-engine-sc
@material-ui/private-theming -> @mui/private-theming
```

### Codemods

Run these in order, committing after each:

```bash
# Main migration codemod (handles most changes)
npx @mui/codemod@latest v5.0.0/preset-safe <path>

# If you want to keep variant="standard" (default changed to "outlined")
npx @mui/codemod@latest v5.0.0/variant-prop <path>

# If you want to keep underline="hover" (default changed to "always")
npx @mui/codemod@latest v5.0.0/link-underline-hover <path>

# Fix nested imports
npx @mui/codemod@latest v5.0.0/optimal-imports <path>

# Migrate JSS to styled API (optional)
npx @mui/codemod@latest v5.0.0/jss-to-styled <path>

# Migrate JSS to tss-react (alternative)
npx @mui/codemod@latest v5.0.0/jss-to-tss-react <path>
```

### Styling System Changes

#### JSS -> Emotion

- The default styling engine changes from JSS to Emotion.
- JSS utilities (`makeStyles`, `withStyles`) move to deprecated `@mui/styles`.
- You can continue using JSS temporarily via `@mui/styles` while migrating.
- `@mui/styles` requires `ThemeProvider` (no default theme).

#### Import Changes for JSS Utilities

```diff
-import { makeStyles } from '@mui/material/styles';
+import { makeStyles } from '@mui/styles';

-import { withStyles } from '@mui/material/styles';
+import { withStyles } from '@mui/styles';

-import { createStyles } from '@mui/material/styles';
+import { createStyles } from '@mui/styles';

-import { StylesProvider } from '@mui/material/styles';
+import { StylesProvider } from '@mui/styles';
```

#### CSS Injection Order

When using JSS alongside Emotion, inject Emotion first:

```jsx
import { StyledEngineProvider } from '@mui/material/styles';

<StyledEngineProvider injectFirst>
  {/* Your component tree */}
</StyledEngineProvider>
```

#### JSS `$` Syntax -> Global Class Names

```diff
// State classes
-'&$focused': { ... }
+'&.Mui-focused': { ... }

// Nested classes
-'& $notchedOutline': { ... }
+'& .MuiOutlinedInput-notchedOutline': { ... }

// Or using exported classes constants
+import { outlinedInputClasses } from '@mui/material/OutlinedInput';
+[`& .${outlinedInputClasses.notchedOutline}`]: { ... }
```

### Theme Structure Changes

#### Renamed APIs

```diff
-import { createMuiTheme } from '@mui/material/styles';
+import { createTheme } from '@mui/material/styles';

-import { MuiThemeProvider } from '@mui/material/styles';
+import { ThemeProvider } from '@mui/material/styles';

-import { fade } from '@mui/material/styles';
+import { alpha } from '@mui/material/styles';
```

#### Theme Restructuring

```diff
// Props -> components.defaultProps
-props: { MuiButton: { disableRipple: true } }
+components: { MuiButton: { defaultProps: { disableRipple: true } } }

// Overrides -> components.styleOverrides
-overrides: { MuiButton: { root: { padding: 0 } } }
+components: { MuiButton: { styleOverrides: { root: { padding: 0 } } } }

// Palette mode
-theme.palette.type -> theme.palette.mode

// Spacing returns string
-theme.spacing(2) => 16
+theme.spacing(2) => '16px'
```

#### Breakpoint Changes

- `down(key)` now excludes the specified breakpoint (use next breakpoint up):
  ```diff
  -theme.breakpoints.down('sm')  // was [0, md)
  +theme.breakpoints.down('md')  // now [0, md)
  ```
- Default breakpoint values changed: `md: 960->900`, `lg: 1280->1200`, `xl: 1920->1536`.
- `theme.breakpoints.width()` removed; use `theme.breakpoints.values`.

### Key Component Changes

#### Default Variant Changes

- `TextField`, `FormControl`, `Select`: default variant `"standard"` -> `"outlined"`.
- `Link`: default underline `"hover"` -> `"always"`.

#### Components Moved from Lab to Core

`Alert`, `AlertTitle`, `Autocomplete`, `AvatarGroup`, `Pagination`, `PaginationItem`, `Rating`, `Skeleton`, `SpeedDial`, `SpeedDialAction`, `SpeedDialIcon`, `ToggleButton`, `ToggleButtonGroup`, `usePagination`.

#### Renamed Components

- `ExpansionPanel` -> `Accordion` (and all sub-components).
- `GridList` -> `ImageList`, `GridListTile` -> `ImageListItem`, `GridListTileBar` -> `ImageListItemBar`.
- `RootRef` removed (use `ref` prop directly).

#### Color Prop Defaults Changed to "primary"

`Button`, `Checkbox`, `Radio`, `Switch`: default color changed from "secondary"/"default" to "primary".

#### Transition Props Consolidated

```diff
// Dialog, Menu, Popover, Snackbar
-onEnter={onEnter}
-onExited={onExited}
+TransitionProps={{ onEnter, onExited }}
```

#### Other Notable Changes

- `Dialog`: `disableBackdropClick` removed; use `onClose` with reason check.
- `Modal`: `onEscapeKeyDown` removed; use `onClose` with `reason === "escapeKeyDown"`.
- `Hidden`: deprecated; use `sx` prop or `useMediaQuery`.
- `Tooltip`: now interactive by default; use `disableInteractive` for old behavior.
- `IconButton`: default size reduced to 40px; use `size="large"` for old 48px.
- `Slider`: `ValueLabelComponent`/`ThumbComponent` moved to `components` prop.
- `Autocomplete`: `renderOption` signature changed; `getOptionSelected` -> `isOptionEqualToValue`.
- `Stepper`: root changed from `Paper` to `<div>`; built-in padding removed.
- `Typography`: `srOnly` variant removed; use `visuallyHidden` utility.

#### Shape Naming Consistency

- `circle` -> `circular` (Avatar, Badge, Fab, Pagination)
- `rect`/`rectangle` -> `rectangular` (Badge, Skeleton)
- `round` -> `circular` (Fab, Pagination)

---

## v5 to v6 Migration

v6 introduces minimal breaking changes. The biggest addition is Pigment CSS (opt-in) for zero-runtime CSS-in-JS.

### Checklist

- [ ] Update `@mui/material` to `^6.0.0` and related packages
- [ ] Update Node.js to `>=14`
- [ ] Update TypeScript to `>=4.7`
- [ ] Run `v6.0.0/grid-v2-props` codemod if using Grid2
- [ ] Run `v6.0.0/list-item-button-prop` codemod if using ListItem button prop
- [ ] Run `v6.0.0/styled`, `v6.0.0/sx-prop`, `v6.0.0/theme-v6` codemods for `theme.applyStyles()`
- [ ] Address Grid2 spacing changes (now uses CSS `gap`)
- [ ] Address Accordion heading wrapper changes
- [ ] If using React 18 or below, set up `react-is` resolution to match your React version
- [ ] Optionally migrate to Pigment CSS

### Browser Support Changes

- Node.js 14 (up from 12)
- Chrome 109, Edge 121, Firefox 115, Safari 15.4
- IE 11 support completely removed (including legacy bundle)

### Breaking Changes

#### Grid2 Stabilized

```diff
-import { Unstable_Grid2 as Grid2 } from '@mui/material';
+import { Grid2 } from '@mui/material';

-import Grid from '@mui/material/Unstable_Grid2';
+import Grid from '@mui/material/Grid2';
```

Size and offset props renamed:

```diff
-<Grid xs={12} sm={6} xsOffset={2} smOffset={3}>
+<Grid size={{ xs: 12, sm: 6 }} offset={{ xs: 2, sm: 3 }}>

-<Grid xs>          // auto-grow
+<Grid size="grow">
```

Codemod: `npx @mui/codemod@latest v6.0.0/grid-v2-props <path>`

The Grid now uses CSS `gap` instead of margins. `disableEqualOverflow` prop removed.

#### Accordion Changes

- Summary wrapped in a heading element (`<h3>` by default). Customize via `slotProps.heading.component`.
- From v6.3.0: Summary root is now a `<button>`, content and icon wrapper are `<span>`.

#### ListItem Deprecated Props Removed

```diff
-<ListItem button />
+<ListItemButton />
```

Codemod: `npx @mui/codemod@latest v6.0.0/list-item-button-prop <path>`

#### Button Loading State (v6.4.0+)

```diff
-import { LoadingButton } from '@mui/lab';
+import { Button } from '@mui/material';
// Use loading prop directly on Button
```

#### Typography color prop

`color` prop is no longer a system prop. Use `sx` for callback-based colors:

```diff
-<Typography color={(theme) => theme.palette.primary.main}>
+<Typography sx={{ color: (theme) => theme.palette.primary.main }}>
```

### New Features

#### theme.applyStyles()

New utility for color-mode-specific styles, replacing `theme.palette.mode` checks:

```diff
-borderColor: theme.palette.mode === 'dark' ? '#fff' : '#000',
+borderColor: '#000',
+...theme.applyStyles('dark', { borderColor: '#fff' })
```

Codemods:

```bash
npx @mui/codemod@latest v6.0.0/styled <path>
npx @mui/codemod@latest v6.0.0/sx-prop <path>
npx @mui/codemod@latest v6.0.0/theme-v6 <path>  # for theme files
```

#### Stabilized APIs

```diff
-import { experimental_extendTheme as extendTheme } from '@mui/material/styles';
-import { Experimental_CssVarsProvider as CssVarsProvider } from '@mui/material/styles';
+import { extendTheme, CssVarsProvider } from '@mui/material/styles';
```

### Testing Changes

Ripple effect performance improvements require wrapping `fireEvent` in `act`:

```diff
-fireEvent.click(button);
+await act(async () => fireEvent.mouseDown(button));
```

Affects: all buttons, Checkbox, Chip, Radio Group, Switch, Tabs.

---

## v6 to v7 Migration

v7 focuses on ESM support, slot standardization, and cleaning up deprecated APIs.

### Checklist

- [ ] Update `@mui/material` and related packages to `^7.0.0`
- [ ] Update TypeScript to `>=4.9`
- [ ] Set `moduleResolution` to `"bundler"` (or `"node16"`) in `tsconfig.json` — required for v7's `exports` field
- [ ] If using React 18 or below, set up `react-is` resolution to match your React version
- [ ] Remove deep imports (more than one level)
- [ ] Remove modern bundle aliases
- [ ] Update Grid/Grid2 imports (Grid2 -> Grid, Grid -> GridLegacy)
- [ ] Run `v7.0.0/grid-props` codemod if upgrading from legacy Grid
- [ ] Run `v7.0.0/lab-removed-components` codemod
- [ ] Run `v7.0.0/input-label-size-normal-medium` codemod
- [ ] Remove usage of deprecated APIs that were removed in v7

### Package Layout (ESM Exports)

Deep imports beyond one level no longer work:

```diff
-import createTheme from '@mui/material/styles/createTheme';
+import { createTheme } from '@mui/material/styles';
```

Remove modern bundle aliases:

```diff
resolve: {
  alias: {
-   '@mui/material': '@mui/material/modern',
-   '@mui/styled-engine': '@mui/styled-engine/modern',
  }
}
```

Remove Vite icons alias (no longer necessary):

```diff
-{ find: /^@mui\/icons-material\/(.*)/, replacement: "@mui/icons-material/esm/$1" }
```

### TypeScript `moduleResolution`

v7's `exports` field requires a `moduleResolution` that supports it. The legacy `"node"` mode ignores `exports`, causing broken imports and missing types:

```diff
// tsconfig.json
{
  "compilerOptions": {
+   "module": "preserve",
+   "moduleResolution": "bundler"
  }
}
```

Use `"bundler"` for projects using Vite, webpack, Next.js, or esbuild. See `typescript.md` for details.

### Grid Renaming

- Deprecated `Grid` -> `GridLegacy`
- `Grid2` -> `Grid`

Three paths:

1. **Upgrade from legacy Grid**: Run `npx @mui/codemod@next v7.0.0/grid-props <path>`
2. **Keep using legacy Grid**: Change imports to `GridLegacy`
3. **Already using Grid2**: Change imports from `Grid2` to `Grid`

```diff
// If keeping legacy Grid
-import Grid from '@mui/material/Grid';
+import Grid from '@mui/material/GridLegacy';

// If already on Grid2
-import Grid from '@mui/material/Grid2';
+import Grid from '@mui/material/Grid';
```

### Deprecated APIs Removed in v7

- `createMuiTheme` -> use `createTheme`
- `experimentalStyled` -> use `styled`
- `Dialog`/`Modal` `onBackdropClick` prop -> use `onClose` with reason check
- `Hidden` / `PigmentHidden` components -> use `sx` or `useMediaQuery`
- `MuiRating-readOnly` class -> `Mui-readOnly`
- `StepButtonIcon` type -> `StepButtonProps['icon']`
- `StyledEngineProvider` from `'@mui/material'` -> import from `'@mui/material/styles'`
- Lab components (Alert, Autocomplete, etc.) removed from `@mui/lab` -> import from `@mui/material`

Codemod: `npx @mui/codemod v7.0.0/lab-removed-components <path>`

### InputLabel Size Prop

```diff
-<InputLabel size="normal">
+<InputLabel size="medium">
```

Codemod: `npx @mui/codemod v7.0.0/input-label-size-normal-medium <path>`

### Theme Behavior Changes (CSS Variables Mode)

When CSS theme variables are enabled with light/dark color schemes, the theme object no longer changes between modes. Use `theme.vars.*` for CSS variable references:

```js
const Custom = styled('div')(({ theme }) => ({
  color: theme.vars.palette.text.primary,
  background: theme.vars.palette.primary.main,
}));
```

Use `color-mix()` for runtime alpha adjustments:

```js
color: `color-mix(in srgb, ${theme.vars.palette.text.primary}, transparent 50%)`
```

Opt out with `<ThemeProvider forceThemeRerender />`.

### Native Color (v7.3.0+)

Opt-in feature replacing JS color manipulation with CSS `color-mix()`:

```js
const theme = createTheme({ cssVariables: { nativeColor: true } });
```

Replace `alpha()`, `lighten()`, `darken()` with theme adapter functions:

```diff
-import { alpha } from '@mui/material/styles';
-alpha(theme.palette.primary.main, 0.3)
+theme.alpha(theme.palette.primary.main, 0.3)
```

Codemod: `npx @mui/codemod@latest v7.0.0/theme-color-functions <path>`

---

## v7 to v9 Migration

> **v9 is alpha/pre-release (9.0.0-alpha.0).** This section reflects the current alpha state. Breaking changes may still be added before stable release. Do not use in production without evaluating alpha risk.

v8 was skipped.

### Checklist

- [ ] Update `@mui/material` to v9 (currently `@next` tag only)
- [ ] Replace `disableEscapeKeyDown` on Dialog/Modal with `onClose` reason check
- [ ] Test ButtonBase click event propagation changes
- [ ] Replace system props on Grid with `sx`
- [ ] Update tests for Backdrop `aria-hidden` change
- [ ] Remove `MuiTouchRipple` from theme `components` types if referenced
- [ ] Review testing setup for JSDOM auto-detection changes

### Breaking Changes

#### Dialog & Modal: `disableEscapeKeyDown` Removed

```diff
-<Dialog open={open} disableEscapeKeyDown onClose={handleClose}>
+<Dialog open={open} onClose={(event, reason) => {
+  if (reason !== 'escapeKeyDown') {
+    handleClose(event, reason);
+  }
+}}>
```

#### ButtonBase: Click Event Propagation

Enter and Spacebar key presses now produce a `MouseEvent` that bubbles to ancestors (instead of `KeyboardEvent`). This may affect event handlers that check `event instanceof KeyboardEvent` or test assertions on event types.

#### Backdrop: No Longer Adds `aria-hidden`

The Backdrop component no longer adds `aria-hidden="true"` to the Root slot by default. Update tests and a11y assumptions accordingly.

#### Grid: System Props Removed

The Grid component no longer supports system props directly. Use the `sx` prop instead:

```diff
-<Grid container mt={2} px={3}>
+<Grid container sx={{ mt: 2, px: 3 }}>
```

#### MuiTouchRipple: Removed from Theme Types

`MuiTouchRipple` has been removed from the theme `components` types (`ComponentsProps`, `ComponentsOverrides`, `ComponentsVariants`). TouchRipple has been an internal component since v5 and never consumed theme overrides, so the types were misleading. Remove any `MuiTouchRipple` entries from your theme configuration.

#### Testing: JSDOM Auto-Detection

v9 removes all usage of `process.env.NODE_ENV === 'test'` for behavior changes. The libraries now auto-detect DOM environments that don't support layout (JSDOM, happy-dom) via user agent sniffing. `NODE_ENV` is used exclusively for tree-shaking.

#### Autocomplete

- The listbox no longer toggles on right-click. Left-click behavior is unchanged.
- `freeSolo` type constraints may have changed; verify TypeScript compilation.

---

## Grid v1 to Grid v2 Migration

Grid v2 replaces the legacy Grid with CSS variables and CSS `gap`.

### Why Upgrade

- CSS variables instead of class-based specificity
- All grid items automatically (no `item` prop needed)
- Offset feature for flexible positioning
- No depth limitation on nested grids
- No negative margin overflow issues

### Migration Steps

#### 1. Update Import

```diff
// v7
-import Grid from '@mui/material/GridLegacy';
+import Grid from '@mui/material/Grid';

// v6
-import Grid from '@mui/material/Grid';
+import Grid from '@mui/material/Grid2';

// v5
-import Grid from '@mui/material/Grid';
+import Grid from '@mui/material/Unstable_Grid2';
```

#### 2. Remove Legacy Props

```diff
-<Grid item zeroMinWidth>
+<Grid>
```

#### 3. Update Size Props (v6+)

```diff
-<Grid xs={12} sm={6}>
+<Grid size={{ xs: 12, sm: 6 }}>

-<Grid xs={6}>
+<Grid size={6}>

-<Grid xs>        // auto-grow
+<Grid size="grow">
```

Codemods:
- v7: `npx @mui/codemod@next v7.0.0/grid-props <path>`
- v6: `npx @mui/codemod@latest v6.0.0/grid-v2-props <path>`

#### Container Width

Grid v2 does not auto-grow to full width:

```diff
-<Grid container>
+<Grid container sx={{ width: '100%' }}>
```

---

## Migrating from Deprecated APIs

Material UI deprecates APIs over time in preparation for the next major version. Use this codemod to handle all deprecations at once:

```bash
npx @mui/codemod@latest deprecations/all <path>
```

### Key Deprecation Patterns

#### slots/slotProps Standardization

The `components`, `componentsProps`, `*Component`, and `*Props` patterns are deprecated in favor of `slots` and `slotProps`:

```diff
// Component slots
-<Autocomplete PaperComponent={CustomPaper} PopperComponent={CustomPopper} />
+<Autocomplete slots={{ paper: CustomPaper, popper: CustomPopper }} />

// Component slot props
-<Autocomplete ChipProps={chipProps} ListboxProps={listboxProps} />
+<Autocomplete slotProps={{ chip: chipProps, listbox: listboxProps }} />

// Transition slots
-<Accordion TransitionComponent={CustomTransition} TransitionProps={{ unmountOnExit: true }} />
+<Accordion slots={{ transition: CustomTransition }} slotProps={{ transition: { unmountOnExit: true } }} />
```

This pattern applies to: Accordion, Alert, Autocomplete, Avatar, AvatarGroup, Backdrop, Badge, and many more.

#### Composed CSS Classes -> Atomic Classes

Composed CSS classes are deprecated in favor of separate atomic classes:

```diff
-.MuiButton-containedPrimary
+.MuiButton-contained.MuiButton-colorPrimary

-.MuiAlert-standardSuccess
+.MuiAlert-standard.MuiAlert-colorSuccess
```

#### System Props -> sx Prop

System props on Box, Typography, Link, Grid, Stack are deprecated:

```diff
-<Button mr={2}>
+<Button sx={{ mr: 2 }}>
```

Codemod: `npx @mui/codemod@latest v6.0.0/system-props <path>`

#### Theme Variants Location

Custom variants move inside `styleOverrides.root`:

```diff
createTheme({
  components: {
    MuiButton: {
-     variants: [ ... ],
+     styleOverrides: { root: { variants: [ ... ] } },
    },
  },
});
```

Codemod: `npx @mui/codemod@latest v6.0.0/theme-v6 <path>`

---

## Pickers Migration

Date and time pickers moved from `@material-ui/pickers` to `@mui/lab` (v5 alpha) and then to `@mui/x-date-pickers` (stable).

### Key Changes

```diff
// Provider
-import { MuiPickersUtilsProvider } from '@material-ui/pickers';
+import { LocalizationProvider } from '@mui/x-date-pickers';
+import { AdapterDateFns } from '@mui/x-date-pickers/AdapterDateFns';

// Components
-import { KeyboardDatePicker } from '@material-ui/pickers';
+import { DatePicker } from '@mui/x-date-pickers';

// Variants split into separate components
-<DatePicker variant="inline" />
+<DesktopDatePicker />
```

New required `renderInput` prop (in v5 lab):

```jsx
<DatePicker renderInput={(props) => <TextField {...props} />} />
```

For stable pickers, migrate to `@mui/x-date-pickers` / `@mui/x-date-pickers-pro`.

---

## Migrating from JSS to Emotion

Two recommended approaches for migrating away from `makeStyles`/`withStyles`:

### Option 1: styled / sx API (Recommended)

```bash
npx @mui/codemod@latest v5.0.0/jss-to-styled <path>
```

Use `sx` for simple responsive styles:

```diff
-const useStyles = makeStyles((theme) => ({
-  wrapper: { display: 'flex' },
-  chip: { padding: theme.spacing(1, 1.5), boxShadow: theme.shadows[1] }
-}));
-
-function App() {
-  const classes = useStyles();
-  return (
-    <div className={classes.wrapper}>
-      <Chip className={classes.chip} label="Chip" />
-    </div>
-  );
-}
+function App() {
+  return (
+    <Box sx={{ display: 'flex' }}>
+      <Chip label="Chip" sx={{ py: 1, px: 1.5, boxShadow: 1 }} />
+    </Box>
+  );
+}
```

Use `styled` for reusable styled components:

```diff
-const useStyles = makeStyles((theme) => ({
-  root: { display: 'flex', borderRadius: 20, background: theme.palette.grey[50] },
-  label: { color: theme.palette.primary.main }
-}));
+const Root = styled('div')(({ theme }) => ({
+  display: 'flex', borderRadius: 20, background: theme.palette.grey[50],
+}));
+const Label = styled('span')(({ theme }) => ({
+  color: theme.palette.primary.main,
+}));
```

### Option 2: tss-react

A drop-in replacement for `makeStyles` API backed by Emotion:

```bash
npx @mui/codemod@latest v5.0.0/jss-to-tss-react <path>
```

```diff
-import makeStyles from '@material-ui/styles/makeStyles';
+import { makeStyles } from 'tss-react/mui';

-const useStyles = makeStyles((theme) => ({ ... }));
+const useStyles = makeStyles()((theme) => ({ ... }));

-const classes = useStyles();
+const { classes } = useStyles();
```

After completing JSS migration, uninstall `@mui/styles`.

---

## Pigment CSS Integration

Pigment CSS is an opt-in zero-runtime CSS-in-JS engine available in v6+.

### When to Use

- Need React Server Component (RSC) support
- Want build-time style extraction (smaller bundles)
- Using Next.js App Router or Vite

### Limitations

- No dynamic styles based on runtime variables (state, props)
- `ownerState` callbacks in theme not supported
- Must use CSS variables for dynamic values

### Setup

```bash
npm install @mui/material-pigment-css @pigment-css/react
# Plus framework plugin: @pigment-css/nextjs-plugin or @pigment-css/vite-plugin
```

### Key Migration Patterns

Replace `styled` import:

```diff
-import { styled } from '@mui/material/styles';
+import { styled } from '@mui/material-pigment-css';
```

Replace layout component imports:

```diff
-import Container from '@mui/material/Container';
+import Container from '@mui/material-pigment-css/Container';

-import Stack from '@mui/material/Stack';
+import Stack from '@mui/material-pigment-css/Stack';
```

Move dynamic values to CSS variables:

```js
// Before: runtime value in sx
<Box sx={{ width: `max(${6 - index}px, 3px)` }} />

// After: CSS variable via inline style
<Box
  sx={{ width: 'max(6px - var(--offset), 3px)' }}
  style={{ '--offset': `${index}px` }}
/>
```

Move theme `defaultProps` to `DefaultPropsProvider`:

```jsx
import DefaultPropsProvider from '@mui/material/DefaultPropsProvider';

<DefaultPropsProvider value={{
  MuiButtonBase: { disableRipple: true },
}}>
  {/* app */}
</DefaultPropsProvider>
```

---

## Codemod Reference

### Running Codemods

```bash
npx @mui/codemod@latest <codemod-name> <path>

# Options
--dry          # Preview changes without writing
--parser tsx   # Parser (default: tsx)
--print        # Print transformed files to stdout
--packageName  # Custom package name (e.g., @org/ui)
```

### Available Codemods by Version

#### v4 Codemods

| Codemod | Description |
|---------|-------------|
| `v4.0.0/theme-spacing-api` | Migrate `theme.spacing.unit` to `theme.spacing()` |

#### v5 Codemods

| Codemod | Description |
|---------|-------------|
| `v5.0.0/preset-safe` | Main migration codemod (run once per folder) |
| `v5.0.0/variant-prop` | Add `variant="standard"` where default changed |
| `v5.0.0/link-underline-hover` | Add `underline="hover"` where default changed |
| `v5.0.0/optimal-imports` | Fix nested color imports |
| `v5.0.0/jss-to-styled` | Migrate JSS `makeStyles` to `styled` API |
| `v5.0.0/jss-to-tss-react` | Migrate JSS to `tss-react` |

#### v6 Codemods

| Codemod | Description |
|---------|-------------|
| `v6.0.0/grid-v2-props` | Migrate Grid2 size/offset props |
| `v6.0.0/list-item-button-prop` | Migrate ListItem button to ListItemButton |
| `v6.0.0/styled` | Migrate styled to use `theme.applyStyles()` |
| `v6.0.0/sx-prop` | Migrate sx prop to use `theme.applyStyles()` |
| `v6.0.0/theme-v6` | Migrate theme overrides to v6 format |
| `v6.0.0/system-props` | Move system props to sx prop |

#### v7 Codemods

| Codemod | Description |
|---------|-------------|
| `v7.0.0/grid-props` | Migrate legacy Grid to Grid v2 |
| `v7.0.0/lab-removed-components` | Update lab imports to @mui/material |
| `v7.0.0/input-label-size-normal-medium` | Update InputLabel size prop |
| `v7.0.0/theme-color-functions` | Migrate to theme color adapter functions |

#### Deprecation Codemods

| Codemod | Description |
|---------|-------------|
| `deprecations/all` | Run all deprecation codemods |
| `deprecations/accordion-props` | Migrate TransitionComponent/TransitionProps to slots |
| `deprecations/alert-props` | Migrate components/componentsProps to slots |
| `deprecations/alert-classes` | Migrate composed CSS classes |
| `deprecations/autocomplete-props` | Migrate *Component/*Props to slots |
| `deprecations/button-classes` | Migrate composed CSS classes |
| `deprecations/chip-classes` | Migrate composed CSS classes |
| `deprecations/badge-props` | Migrate components/componentsProps to slots |
| `deprecations/backdrop-props` | Migrate TransitionComponent to slots |
