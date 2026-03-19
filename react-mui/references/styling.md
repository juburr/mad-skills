# MUI Theming and Styling Reference

## createTheme() API

`createTheme(options?) => Theme`

Generates a complete theme object from partial options.

```tsx
import { createTheme, ThemeProvider } from "@mui/material/styles";

const theme = createTheme({
  palette: { ... },
  typography: { ... },
  spacing: 8,
  breakpoints: { ... },
  shadows: [...],
  shape: { ... },
  zIndex: { ... },
  transitions: { ... },
  components: { ... },
  cssVariables: false, // set to true to enable CSS variables mode
  colorSchemes: { light: true, dark: true },
});
```

### Deep Merging Multiple Theme Fragments

The multi-argument form `createTheme(options, ...args)` works for backward compatibility, but the MUI docs warn this behavior may be removed in future versions. For forward-compatible code, use `deepmerge` explicitly:

```tsx
import { createTheme } from "@mui/material/styles";
import { deepmerge } from "@mui/utils";

const tokens = { palette: { primary: { main: "#1976d2" } } };
const overrides = { typography: { fontFamily: "Inter, sans-serif" } };

const theme = createTheme(deepmerge(tokens, overrides));
```

## Full Theme Structure

### palette

Controls all colors. The `mode` determines light/dark defaults.

```tsx
const theme = createTheme({
  palette: {
    mode: "light", // 'light' | 'dark'
    primary: { main: "#1976d2", light: "#42a5f5", dark: "#1565c0", contrastText: "#fff" },
    secondary: { main: "#9c27b0" },
    error: { main: "#d32f2f" },
    warning: { main: "#ed6c02" },
    info: { main: "#0288d1" },
    success: { main: "#2e7d32" },
    // Override surface colors
    background: { default: "#fff", paper: "#fff" },
    text: { primary: "rgba(0,0,0,0.87)", secondary: "rgba(0,0,0,0.6)", disabled: "rgba(0,0,0,0.38)" },
    divider: "rgba(0,0,0,0.12)",
    // Only `main` is required; light, dark, contrastText are auto-calculated
    action: {
      active: "rgba(0,0,0,0.54)",
      hover: "rgba(0,0,0,0.04)",
      hoverOpacity: 0.04,
      selected: "rgba(0,0,0,0.08)",
      selectedOpacity: 0.08,
      disabled: "rgba(0,0,0,0.26)",
      disabledBackground: "rgba(0,0,0,0.12)",
      disabledOpacity: 0.38,
      focus: "rgba(0,0,0,0.12)",
      focusOpacity: 0.12,
      activatedOpacity: 0.12,
    },
    common: { black: "#000", white: "#fff" },
    grey: { 50: "#fafafa", 100: "#f5f5f5", /* ... */ 900: "#212121" },
    contrastThreshold: 3,
    tonalOffset: 0.2,
    getContrastText: (background: string) => string,
  },
});
```

Adding custom palette colors with TypeScript:

```tsx
declare module "@mui/material/styles" {
  interface PaletteOptions {
    neutral?: PaletteColorOptions;
  }
  interface Palette {
    neutral: PaletteColor;
  }
}

const theme = createTheme({
  palette: {
    neutral: { main: "#64748B", contrastText: "#fff" },
  },
});
```

### typography

Controls font rendering for all text. Accepts an object or a function `(palette) => options`.

Default font: `"Roboto", "Helvetica", "Arial", sans-serif`, default size: 14px.

```tsx
const theme = createTheme({
  typography: {
    fontFamily: '"Inter", "Helvetica", "Arial", sans-serif',
    fontSize: 14,         // base font size in px
    htmlFontSize: 16,     // browser html font size (for rem calculation)
    fontWeightLight: 300,
    fontWeightRegular: 400,
    fontWeightMedium: 500,
    fontWeightBold: 700,
    // Override individual variants
    h1: { fontSize: "2.5rem", fontWeight: 700, lineHeight: 1.167 },
    h2: { fontSize: "2rem", fontWeight: 600 },
    h3: { fontSize: "1.75rem" },
    h4: { fontSize: "1.5rem" },
    h5: { fontSize: "1.25rem" },
    h6: { fontSize: "1rem", fontWeight: 500 },
    subtitle1: { fontSize: "1rem", lineHeight: 1.75 },
    subtitle2: { fontSize: "0.875rem", fontWeight: 500 },
    body1: { fontSize: "1rem", lineHeight: 1.5 },
    body2: { fontSize: "0.875rem", lineHeight: 1.43 },
    button: { fontSize: "0.875rem", fontWeight: 500, textTransform: "uppercase" },
    caption: { fontSize: "0.75rem", lineHeight: 1.66 },
    overline: { fontSize: "0.75rem", textTransform: "uppercase", lineHeight: 2.66 },
    allVariants: { /* CSS properties applied to every variant */ },
  },
});
```

Default variant sizes (px values before rem conversion):

| Variant   | Weight  | Size | Line Height | Letter Spacing |
|-----------|---------|------|-------------|----------------|
| h1        | 300     | 96   | 1.167       | -1.5px         |
| h2        | 300     | 60   | 1.2         | -0.5px         |
| h3        | 400     | 48   | 1.167       | 0              |
| h4        | 400     | 34   | 1.235       | 0.25px         |
| h5        | 400     | 24   | 1.334       | 0              |
| h6        | 500     | 20   | 1.6         | 0.15px         |
| subtitle1 | 400     | 16   | 1.75        | 0.15px         |
| subtitle2 | 500     | 14   | 1.57        | 0.1px          |
| body1     | 400     | 16   | 1.5         | 0.15px         |
| body2     | 400     | 14   | 1.43        | 0.15px         |
| button    | 500     | 14   | 1.75        | 0.4px          |
| caption   | 400     | 12   | 1.66        | 0.4px          |
| overline  | 400     | 12   | 2.66        | 1px            |

Utility: `theme.typography.pxToRem(px)` converts pixel values to rem.

#### responsiveFontSizes

```tsx
import { createTheme, responsiveFontSizes } from "@mui/material/styles";

let theme = createTheme();
theme = responsiveFontSizes(theme, {
  breakpoints: ["sm", "md", "lg"],
  factor: 2,               // strength of resize (default 2)
  variants: ["h1", "h2"],  // which variants to resize
  disableAlign: false,      // keep line-height alignment
});
```

### spacing

Default: 8px scaling factor. `theme.spacing(n)` returns `${8 * n}px`.

```tsx
// Number multiplier (default 8)
const theme = createTheme({ spacing: 4 });
theme.spacing(2); // '8px'

// Function
const theme = createTheme({
  spacing: (factor: number) => `${0.25 * factor}rem`,
});
theme.spacing(2); // '0.5rem'

// Array
const theme = createTheme({
  spacing: [0, 4, 8, 16, 32, 64],
});
theme.spacing(2); // '8px'
```

Multiple arity support:

```tsx
theme.spacing(1, 2);      // '8px 16px'
theme.spacing(1, "auto");  // '8px auto'
theme.spacing(1, 2, 3, 4); // '8px 16px 24px 32px'
```

### breakpoints

Default values:

| Key  | Value  | Description  |
|------|--------|--------------|
| `xs` | 0px    | extra-small  |
| `sm` | 600px  | small        |
| `md` | 900px  | medium       |
| `lg` | 1200px | large        |
| `xl` | 1536px | extra-large  |

```tsx
const theme = createTheme({
  breakpoints: {
    values: { xs: 0, sm: 600, md: 900, lg: 1200, xl: 1536 },
    unit: "px",
    step: 5,
  },
});
```

Custom breakpoints with TypeScript:

```tsx
declare module "@mui/material/styles" {
  interface BreakpointOverrides {
    xs: false; sm: false; md: false; lg: false; xl: false;
    mobile: true; tablet: true; laptop: true; desktop: true;
  }
}

const theme = createTheme({
  breakpoints: {
    values: { mobile: 0, tablet: 640, laptop: 1024, desktop: 1200 },
  },
});
```

Breakpoint helpers:

```tsx
theme.breakpoints.up("md")              // '@media (min-width:900px)'
theme.breakpoints.down("md")            // '@media (max-width:899.95px)'
theme.breakpoints.between("sm", "lg")   // '@media (min-width:600px) and (max-width:1199.95px)'
theme.breakpoints.only("md")            // '@media (min-width:900px) and (max-width:1199.95px)'
theme.breakpoints.not("md")             // '@media (max-width:899.95px), (min-width:1200px)'
```

Usage in styled:

```tsx
const Root = styled("div")(({ theme }) => ({
  padding: theme.spacing(1),
  [theme.breakpoints.up("md")]: {
    padding: theme.spacing(2),
  },
}));
```

### shadows

Array of 25 box-shadow strings (indices 0-24). `shadows[0]` is always `"none"`.

```tsx
const theme = createTheme({
  shadows: [
    "none",
    "0px 2px 1px -1px rgba(0,0,0,0.2), ...",
    // ... provide all 25 entries
  ],
});
```

### shape

```tsx
const theme = createTheme({
  shape: { borderRadius: 4 }, // default: 4 (px)
});
```

### zIndex

Default values:

```tsx
const theme = createTheme({
  zIndex: {
    mobileStepper: 1000,
    fab: 1050,
    speedDial: 1050,
    appBar: 1100,
    drawer: 1200,
    modal: 1300,
    snackbar: 1400,
    tooltip: 1500,
  },
});
```

### transitions

```tsx
const theme = createTheme({
  transitions: {
    easing: {
      easeInOut: "cubic-bezier(0.4, 0, 0.2, 1)",
      easeOut: "cubic-bezier(0.0, 0, 0.2, 1)",
      easeIn: "cubic-bezier(0.4, 0, 1, 1)",
      sharp: "cubic-bezier(0.4, 0, 0.6, 1)",
    },
    duration: {
      shortest: 150,
      shorter: 200,
      short: 250,
      standard: 300,
      complex: 375,
      enteringScreen: 225,
      leavingScreen: 195,
    },
  },
});
```

Usage:

```tsx
theme.transitions.create("background-color", {
  duration: theme.transitions.duration.standard,
  easing: theme.transitions.easing.easeInOut,
  delay: 0,
});
// Returns: 'background-color 300ms cubic-bezier(0.4, 0, 0.2, 1) 0ms'

theme.transitions.create(["color", "transform"], {
  duration: 500,
});
```

## ThemeProvider

Injects the theme into the component tree via React context.

```tsx
import { ThemeProvider, createTheme } from "@mui/material/styles";
import CssBaseline from "@mui/material/CssBaseline";

const theme = createTheme({ /* ... */ });

function App() {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      {/* app content */}
    </ThemeProvider>
  );
}
```

### Nesting ThemeProviders

Inner ThemeProviders can receive a function to extend the outer theme:

```tsx
<ThemeProvider theme={outerTheme}>
  <ThemeProvider theme={(outerTheme) => createTheme({ ...outerTheme, /* overrides */ })}>
    {/* inner content uses merged theme */}
  </ThemeProvider>
</ThemeProvider>
```

### ThemeProvider Props (with colorSchemes)

| Prop                         | Default         | Description                                               |
|------------------------------|-----------------|-----------------------------------------------------------|
| `theme`                      | (required)      | Theme object or function `(outerTheme) => Theme`          |
| `defaultMode`                | `"system"`      | Initial mode: `"light"`, `"dark"`, or `"system"`          |
| `noSsr`                      | `false`         | Skip double-render for SSR hydration                      |
| `disableTransitionOnChange`  | `false`         | Instantly switch color scheme without CSS transitions      |
| `modeStorageKey`             | `"mui-mode"`    | localStorage key for storing mode                         |
| `colorSchemeStorageKey`      | `"mui-color-scheme"` | localStorage key for storing color scheme            |
| `storageManager`             | `localStorage`  | Custom storage manager or `null` to disable               |

## sx Prop

The `sx` prop provides a superset of CSS with theme-aware shorthand properties. Available on all MUI components.

### Theme-Aware Properties

Properties that map numeric values to theme tokens:

| sx Property                       | CSS Property       | Theme Key            |
|-----------------------------------|--------------------|-----------------------|
| `m`, `mt`, `mr`, `mb`, `ml`, `mx`, `my` | `margin-*`   | `theme.spacing`      |
| `p`, `pt`, `pr`, `pb`, `pl`, `px`, `py` | `padding-*`  | `theme.spacing`      |
| `bgcolor`                         | `background-color` | `theme.palette`      |
| `color`                           | `color`            | `theme.palette`      |
| `typography`                      | font properties    | `theme.typography`   |
| `displayPrint`                    | `display` (print)  | --                   |
| `border`                          | `border`           | `theme.palette.divider` (for colors) |
| `borderColor`                     | `border-color`     | `theme.palette`      |
| `borderRadius`                    | `border-radius`    | `theme.shape.borderRadius` (multiplier) |
| `boxShadow`                       | `box-shadow`       | `theme.shadows` (index) |
| `zIndex`                          | `z-index`          | `theme.zIndex`       |
| `gap`, `rowGap`, `columnGap`      | `gap`              | `theme.spacing`      |

### Basic Usage

```tsx
<Box
  sx={{
    bgcolor: "primary.main",         // theme.palette.primary.main
    color: "primary.contrastText",    // theme.palette.primary.contrastText
    p: 2,                             // theme.spacing(2) = '16px'
    m: 1,                             // theme.spacing(1) = '8px'
    borderRadius: 1,                  // theme.shape.borderRadius * 1 = '4px'
    boxShadow: 3,                     // theme.shadows[3]
    typography: "body1",              // spreads theme.typography.body1
    width: 1 / 2,                     // '50%' (fractions 0-1 become percentages)
    width: 300,                       // '300px' (integers > 1 become px)
  }}
/>
```

### Responsive Values

```tsx
// Object syntax (maps to breakpoints)
<Box sx={{ width: { xs: "100%", sm: "50%", md: "33%" } }} />

// Array syntax (mobile-first: xs, sm, md, lg, xl)
<Box sx={{ width: [1, 1 / 2, 1 / 3] }} />
// Equivalent to: width: { xs: '100%', sm: '50%', md: '33%' }

// Skip breakpoints with null
<Box sx={{ width: [1, null, 1 / 2] }} />
// xs: 100%, sm: (inherited from xs), md: 50%
```

### Nesting and Pseudo-Selectors

```tsx
<Box
  sx={{
    "& .child": { color: "text.secondary" },
    "&:hover": { bgcolor: "action.hover" },
    "&:focus-visible": { outline: "2px solid", outlineColor: "primary.main" },
    "& .MuiSlider-thumb": { borderRadius: "50%" },
  }}
/>
```

### Callback Syntax (Access Theme)

```tsx
<Box sx={(theme) => ({
  color: theme.palette.primary.main,
  [theme.breakpoints.up("md")]: {
    fontSize: "1.2rem",
  },
})} />
```

### Array Syntax (Merge Multiple Style Objects)

```tsx
<Box
  sx={[
    { color: "primary.main", p: 2 },
    (theme) => ({
      [theme.breakpoints.up("md")]: { p: 4 },
    }),
    (theme) => theme.applyStyles("dark", {
      bgcolor: "grey.900",
    }),
  ]}
/>
```

## styled() API

Creates styled components with theme access. Re-exported from `@mui/material/styles` with the MUI theme pre-configured.

### Basic Usage

```tsx
import { styled } from "@mui/material/styles";

const StyledDiv = styled("div")(({ theme }) => ({
  backgroundColor: theme.palette.background.paper,
  padding: theme.spacing(2),
  borderRadius: theme.shape.borderRadius,
  color: theme.palette.text.primary,
}));

// Usage: <StyledDiv>content</StyledDiv>
```

### Styling Existing MUI Components

```tsx
import { styled } from "@mui/material/styles";
import Button from "@mui/material/Button";

const PrimaryButton = styled(Button)(({ theme }) => ({
  backgroundColor: theme.palette.primary.dark,
  "&:hover": {
    backgroundColor: theme.palette.primary.main,
  },
}));
```

### Custom Props with shouldForwardProp

```tsx
interface StyledBoxProps {
  isActive?: boolean;
}

const StyledBox = styled("div", {
  shouldForwardProp: (prop) => prop !== "isActive",
})<StyledBoxProps>(({ theme, isActive }) => ({
  backgroundColor: isActive ? theme.palette.primary.main : theme.palette.grey[200],
  padding: theme.spacing(2),
}));

// Usage: <StyledBox isActive>content</StyledBox>
```

### Options for Internal Components

```tsx
const StyledComponent = styled("div", {
  name: "MuiMyComponent",      // component name for theme.components
  slot: "Root",                 // slot name for styleOverrides
  overridesResolver: (props, styles) => styles.root,
})(({ theme }) => ({
  // styles
}));
```

### Array Syntax for Dark Mode

```tsx
const StyledCard = styled("div")(({ theme }) => [
  {
    backgroundColor: theme.palette.background.paper,
    color: theme.palette.text.primary,
    padding: theme.spacing(2),
  },
  theme.applyStyles("dark", {
    backgroundColor: theme.palette.grey[900],
    borderColor: theme.palette.grey[700],
  }),
]);
```

### The `as` Prop

Every styled component accepts an `as` prop to change the rendered element:

```tsx
const StyledButton = styled("button")({ /* styles */ });
// Render as anchor: <StyledButton as="a" href="/link">Link</StyledButton>
```

## CSS Variables Mode

Enable by setting `cssVariables: true` on `createTheme`. Generates CSS custom properties on `:root`.

```tsx
// Simple: enable with defaults
const theme = createTheme({
  cssVariables: true,
});

// Advanced: enable with custom configuration
const theme = createTheme({
  cssVariables: {
    cssVarPrefix: "mui",                      // default prefix: --mui-*
    colorSchemeSelector: "data",              // 'media' | 'class' | 'data' | custom string
    rootSelector: ":root",                    // selector for CSS variables
    disableCssColorScheme: false,             // disable CSS color-scheme property
  },
});
```

Generated CSS variables:

```css
:root {
  --mui-palette-primary-main: #1976d2;
  --mui-palette-primary-light: #42a5f5;
  --mui-palette-primary-dark: #1565c0;
  --mui-palette-primary-contrastText: #fff;
  --mui-palette-background-default: #fff;
  --mui-palette-background-paper: #fff;
  --mui-shadows-1: 0px 2px 1px ...;
  --mui-shape-borderRadius: 4px;
  --mui-spacing: 8px;
  /* ... */
}
```

Access variables in styled components via `theme.vars`:

```tsx
const StyledDiv = styled("div")(({ theme }) => ({
  color: theme.vars.palette.primary.main,         // var(--mui-palette-primary-main)
  backgroundColor: theme.vars.palette.background.default,
}));
```

For components outside ThemeProvider, use fallback:

```tsx
color: (theme.vars || theme).palette.primary.main;
```

### TypeScript Setup for CSS Variables

```tsx
import type {} from "@mui/material/themeCssVarsAugmentation";
```

### Channel Tokens for Opacity

```tsx
// Channel tokens are auto-generated (space-separated RGB values)
theme.palette.primary.mainChannel; // '25 118 210'

// Use in rgba() with slash notation
backgroundColor: `rgba(${theme.vars.palette.primary.mainChannel} / 0.12)`;
// DO NOT use comma: rgba(${...}, 0.12) will NOT work
```

### Using CSS Variables in External CSS

```css
.my-element {
  background-color: var(--mui-palette-primary-main);
  padding: var(--mui-spacing);
}
```

### CSS Cascade Layers

When integrating MUI with other CSS frameworks (e.g., Tailwind CSS v4), enable cascade layers for predictable override order:

```tsx
import { StyledEngineProvider } from "@mui/material/styles";

<StyledEngineProvider enableCssLayer>
  <ThemeProvider theme={theme}>...</ThemeProvider>
</StyledEngineProvider>
```

This wraps all MUI styles in `@layer mui`, allowing you to control specificity order without `!important`. For Next.js App Router, pass `enableCssLayer` via `AppRouterCacheProvider` options instead. For granular control, set `modularCssLayers: true` in `createTheme()` to split MUI styles into sub-layers (`mui.global`, `mui.components`, `mui.theme`, `mui.custom`, `mui.sx`).

## Dark Mode

### Dark Mode Only

```tsx
const darkTheme = createTheme({
  palette: { mode: "dark" },
});

function App() {
  return (
    <ThemeProvider theme={darkTheme}>
      <CssBaseline />
      <main>Dark mode app</main>
    </ThemeProvider>
  );
}
```

### Color Schemes (System Preference Detection)

```tsx
const theme = createTheme({
  colorSchemes: {
    dark: true,  // enables light (default) + dark mode
  },
});

// Automatically switches based on OS/browser prefers-color-scheme
function App() {
  return <ThemeProvider theme={theme}>...</ThemeProvider>;
}
```

Features enabled by `colorSchemes`:
- Automatic switching based on system preference
- Synchronization across browser tabs
- Optional transition disabling on switch

### Manual Dark Mode Toggle

Use the `useColorScheme` hook inside a `ThemeProvider`:

```tsx
import { useColorScheme, createTheme, ThemeProvider } from "@mui/material/styles";

function ModeToggle() {
  const { mode, setMode } = useColorScheme();
  if (!mode) return null; // mode is always undefined on first render — guard to avoid hydration mismatch

  return (
    <button onClick={() => setMode(mode === "dark" ? "light" : "dark")}>
      Current: {mode}
    </button>
  );
}

const theme = createTheme({ colorSchemes: { dark: true } });

function App() {
  return (
    <ThemeProvider theme={theme}>
      <ModeToggle />
    </ThemeProvider>
  );
}
```

### Customizing Both Color Schemes

```tsx
const theme = createTheme({
  colorSchemes: {
    light: {
      palette: {
        primary: { main: "#1976d2" },
        background: { default: "#f5f5f5" },
      },
    },
    dark: {
      palette: {
        primary: { main: "#90caf9" },
        background: { default: "#121212", paper: "#1e1e1e" },
      },
    },
  },
});
```

### theme.applyStyles() for Dark Mode Styling

Preferred over checking `theme.palette.mode`. Works with CSS variables and Pigment CSS.

```tsx
// In styled():
const MyComponent = styled("div")(({ theme }) => [
  {
    color: "#fff",
    backgroundColor: theme.palette.primary.main,
  },
  theme.applyStyles("dark", {
    backgroundColor: theme.palette.secondary.main,
  }),
]);

// In sx prop:
<Button
  sx={[
    (theme) => ({
      backgroundColor: theme.palette.primary.main,
    }),
    (theme) =>
      theme.applyStyles("dark", {
        backgroundColor: theme.palette.secondary.main,
      }),
  ]}
/>
```

`theme.applyStyles(mode, styles) => CSSObject`
- `mode`: `"light"` or `"dark"`
- `styles`: CSS object to apply for that mode

### Preventing SSR Dark Mode Flicker

With `cssVariables: true` and `colorSchemes`, use `InitColorSchemeScript`:

```tsx
import InitColorSchemeScript from "@mui/material/InitColorSchemeScript";

function MyDocument() {
  return (
    <html>
      <body>
        <InitColorSchemeScript defaultMode="system" />
        <App />
      </body>
    </html>
  );
}
```

### Dark Mode Edge Cases

**`useColorScheme().mode` is undefined on first render.** Always guard:
```tsx
const { mode, setMode } = useColorScheme();
if (!mode) return null; // prevents hydration mismatch
```

**Instant mode switching.** By default, CSS transitions animate during mode changes. To disable:
```tsx
<ThemeProvider theme={theme} disableTransitionOnChange />
```

**Force theme re-render.** When CSS variables mode is enabled, `ThemeProvider` does not re-render on mode switch (CSS variables handle it). If your code reads `theme.palette.mode` or uses runtime theme values that differ between modes, opt out:
```tsx
<ThemeProvider theme={theme} forceThemeRerender />
```

**Match native form controls to the theme.** Add `enableColorScheme` to `CssBaseline` so native inputs, selects, and scrollbars follow the theme's color scheme:
```tsx
<CssBaseline enableColorScheme />
```

## Component Customization via Theme

The `theme.components` key customizes all instances of a component.

Each component accepts: `defaultProps`, `styleOverrides`, and `variants`.

### defaultProps

Change default prop values globally:

```tsx
const theme = createTheme({
  components: {
    MuiButtonBase: {
      defaultProps: {
        disableRipple: true,
      },
    },
    MuiTextField: {
      defaultProps: {
        variant: "filled",
        size: "small",
      },
    },
  },
});
```

### styleOverrides

Override styles by slot name. Use `root` for the outermost element:

```tsx
const theme = createTheme({
  components: {
    MuiButton: {
      styleOverrides: {
        root: {
          fontSize: "1rem",
          borderRadius: 8,
          textTransform: "none",
        },
        contained: {
          boxShadow: "none",
          "&:hover": { boxShadow: "none" },
        },
      },
    },
    MuiCard: {
      styleOverrides: {
        root: {
          borderRadius: 12,
          boxShadow: "0 2px 8px rgba(0,0,0,0.1)",
        },
      },
    },
  },
});
```

### variants (in styleOverrides)

Apply conditional styles based on component props:

```tsx
const theme = createTheme({
  components: {
    MuiButton: {
      styleOverrides: {
        root: {
          variants: [
            {
              props: { variant: "contained", color: "primary" },
              style: { fontWeight: 700 },
            },
            {
              props: { size: "large" },
              style: { padding: "12px 24px", fontSize: "1.1rem" },
            },
            // Callback syntax for complex conditions
            {
              props: (props) => props.variant === "outlined" && props.color !== "inherit",
              style: { borderWidth: 2 },
            },
          ],
        },
      },
    },
  },
});
```

### Adding New Variants with TypeScript

```tsx
// Declare the new variant
declare module "@mui/material/Button" {
  interface ButtonPropsVariantOverrides {
    dashed: true;
  }
}

const theme = createTheme({
  components: {
    MuiButton: {
      styleOverrides: {
        root: {
          variants: [
            {
              props: { variant: "dashed" },
              style: {
                border: "2px dashed currentColor",
                textTransform: "none",
              },
            },
            {
              props: { variant: "dashed", color: "secondary" },
              style: {
                border: "4px dashed",
                borderColor: "red",
              },
            },
          ],
        },
      },
    },
  },
});
```

## CssBaseline and ScopedCssBaseline

`CssBaseline` applies global resets (normalize.css-like). Place inside `ThemeProvider`:

```tsx
<ThemeProvider theme={theme}>
  <CssBaseline />
  <App />
</ThemeProvider>
```

`ScopedCssBaseline` applies resets only to its children:

```tsx
import ScopedCssBaseline from "@mui/material/ScopedCssBaseline";

<ScopedCssBaseline>
  {/* normalized content */}
</ScopedCssBaseline>
```

Override CssBaseline via theme:

```tsx
const theme = createTheme({
  components: {
    MuiCssBaseline: {
      styleOverrides: `
        body {
          background-color: #fafafa;
        }
        @font-face {
          font-family: 'CustomFont';
          src: url('/fonts/custom.woff2') format('woff2');
        }
      `,
    },
  },
});
```

## GlobalStyles

Injects global CSS without CssBaseline:

```tsx
import GlobalStyles from "@mui/material/GlobalStyles";

// Hoist for performance
const globalStyles = (
  <GlobalStyles
    styles={(theme) => ({
      "*": { boxSizing: "border-box" },
      body: { backgroundColor: theme.palette.background.default },
      "h1, h2, h3": { color: theme.palette.text.primary },
    })}
  />
);

function App() {
  return (
    <ThemeProvider theme={theme}>
      {globalStyles}
      <Content />
    </ThemeProvider>
  );
}
```

## Responsive Design

### useMediaQuery Hook

```tsx
import useMediaQuery from "@mui/material/useMediaQuery";
import { useTheme } from "@mui/material/styles";

function MyComponent() {
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down("sm"));
  const isDesktop = useMediaQuery(theme.breakpoints.up("lg"));
  const prefersReducedMotion = useMediaQuery("(prefers-reduced-motion: reduce)");

  return <div>{isMobile ? "Mobile" : "Desktop"}</div>;
}
```

With theme callback:

```tsx
const matches = useMediaQuery((theme: Theme) => theme.breakpoints.up("md"));
```

Options:

```tsx
useMediaQuery(query, {
  defaultMatches: false,      // SSR default value
  noSsr: false,               // skip hydration double-render
  matchMedia: window.matchMedia, // custom implementation (e.g., for iframes)
  ssrMatchMedia: (query) => ({ matches: false }), // server-side implementation
});
```

### System Preference Detection

```tsx
const prefersDarkMode = useMediaQuery("(prefers-color-scheme: dark)");
```

### Responsive sx Values

```tsx
<Box
  sx={{
    // Object breakpoint syntax
    flexDirection: { xs: "column", md: "row" },
    p: { xs: 1, sm: 2, md: 3 },
    display: { xs: "block", md: "flex" },
    // Array syntax (mobile-first: xs, sm, md, lg, xl)
    gap: [1, 2, 3],
  }}
/>
```

### Responsive Grid Layout

```tsx
import Grid from "@mui/material/Grid";

<Grid container spacing={{ xs: 1, md: 2 }}>
  <Grid size={{ xs: 12, sm: 6, md: 4 }}>Item 1</Grid>
  <Grid size={{ xs: 12, sm: 6, md: 4 }}>Item 2</Grid>
  <Grid size={{ xs: 12, sm: 12, md: 4 }}>Item 3</Grid>
</Grid>
```

### Breakpoints in styled()

```tsx
const ResponsiveContainer = styled("div")(({ theme }) => ({
  padding: theme.spacing(2),
  [theme.breakpoints.up("sm")]: {
    padding: theme.spacing(3),
    maxWidth: 600,
  },
  [theme.breakpoints.up("md")]: {
    padding: theme.spacing(4),
    maxWidth: 900,
  },
  [theme.breakpoints.between("sm", "md")]: {
    backgroundColor: theme.palette.grey[100],
  },
}));
```

## State Classes

MUI components expose global CSS class names for states:

| State         | Class Name          |
|---------------|---------------------|
| active        | `.Mui-active`       |
| checked       | `.Mui-checked`      |
| completed     | `.Mui-completed`    |
| disabled      | `.Mui-disabled`     |
| error         | `.Mui-error`        |
| expanded      | `.Mui-expanded`     |
| focus visible | `.Mui-focusVisible` |
| focused       | `.Mui-focused`      |
| readOnly      | `.Mui-readOnly`     |
| required      | `.Mui-required`     |
| selected      | `.Mui-selected`     |

Always scope state classes to a component:

```tsx
// Correct: scoped to component
<Box sx={{ "& .MuiOutlinedInput-root.Mui-error": { color: "red" } }} />

// Wrong: global state class unscoped
<Box sx={{ "& .Mui-error": { color: "red" } }} /> // affects ALL components
```

## Localization

Apply a locale to translate built-in component text (e.g., table pagination, date pickers):

```tsx
import { createTheme } from "@mui/material/styles";
import { frFR } from "@mui/material/locale";

const theme = createTheme({ palette: { primary: { main: "#1976d2" } } }, frFR);
```

MUI provides 50+ locale imports (`zhCN`, `deDE`, `jaJP`, etc.). Import from `@mui/material/locale`.

### Right-to-Left (RTL)

For RTL languages (Arabic, Hebrew, etc.):

1. Set `dir="rtl"` on the HTML element
2. Set `direction: 'rtl'` in `createTheme()`
3. Configure the RTL stylis plugin for Emotion:

```tsx
import { CacheProvider } from "@emotion/react";
import createCache from "@emotion/cache";
import rtlPlugin from "stylis-plugin-rtl";
import { prefixer } from "stylis";

const rtlCache = createCache({ key: "muirtl", stylisPlugins: [prefixer, rtlPlugin] });
const theme = createTheme({ direction: "rtl" });

<CacheProvider value={rtlCache}>
  <ThemeProvider theme={theme}>...</ThemeProvider>
</CacheProvider>
```

Note: React portal components (e.g., Dialog) do not inherit `dir` from parent elements. Set `dir="rtl"` globally on `<html>` or `<body>` for portals to render correctly.

## Theme Type Augmentation

### Adding Custom Theme Properties

```tsx
declare module "@mui/material/styles" {
  interface Theme {
    status: { danger: string };
  }
  interface ThemeOptions {
    status?: { danger?: string };
  }
}

const theme = createTheme({
  status: { danger: "#e53e3e" },
});
```

### Adding Custom Palette Colors

```tsx
declare module "@mui/material/styles" {
  interface Palette {
    neutral: Palette["primary"];
  }
  interface PaletteOptions {
    neutral?: PaletteOptions["primary"];
  }
}

declare module "@mui/material/Button" {
  interface ButtonPropsColorOverrides {
    neutral: true;
  }
}
```
