---
name: react-mui
description: Guides building React UIs with Material UI (MUI). Covers component
  APIs, theming, sx prop styling, dark mode, responsive layouts, and version
  migration (v3-v7, plus v9 alpha). Use when writing, reviewing, or migrating React code that
  uses @mui/material or @material-ui packages.
---

# Material UI

## Setup

```bash
npm install @mui/material @emotion/react @emotion/styled
# Icons (optional)
npm install @mui/icons-material
```

### App Entry Point

```tsx
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';

const theme = createTheme(); // default Material Design theme

function App() {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      {/* your app */}
    </ThemeProvider>
  );
}
```

## Imports

Always use direct (second-level) imports for faster development builds. Barrel imports like `@mui/material` can cause significantly slower startup and rebuild times (up to 6x slower for `@mui/icons-material`).

```tsx
// Correct — faster dev startup and rebuilds
import Button from '@mui/material/Button';
import { styled } from '@mui/material/styles';
import Stack from '@mui/material/Stack';

// Avoid — barrel imports slow down dev server startup and hot reloads
import { Button, Stack } from '@mui/material';
```

In v7+, deep imports beyond one level (e.g., `@mui/material/styles/createTheme`) no longer work due to the `exports` field in package.json.

To enforce path imports automatically:
- **Codemod:** `npx @mui/codemod@latest v5.0.0/path-imports <path>`
- **VS Code:** Add to `.vscode/settings.json`:
  ```json
  { "typescript.preferences.autoImportSpecifierExcludeRegexes": ["^@mui/[^/]+$"] }
  ```

## Component Quick Reference

### Layout

| Component | Purpose | Key Props |
|-----------|---------|-----------|
| `Box` | Generic container with `sx` support | `component`, `sx` |
| `Container` | Centered content with max-width | `maxWidth` (`xs`-`xl`\|`false`), `fixed`, `disableGutters` |
| `Grid` | 12-column responsive flexbox grid | `container`, `size`, `spacing`, `offset`, `columns` |
| `Stack` | One-dimensional flex layout | `direction`, `spacing`, `divider` |

Grid example:
```tsx
<Grid container spacing={2}>
  <Grid size={{ xs: 12, sm: 6, md: 4 }}><Card /></Grid>
  <Grid size={{ xs: 12, sm: 6, md: 4 }}><Card /></Grid>
  <Grid size={{ xs: 12, sm: 6, md: 4 }}><Card /></Grid>
</Grid>
```

### Inputs

| Component | Purpose | Key Props |
|-----------|---------|-----------|
| `Button` | Clickable action | `variant` (`contained`\|`outlined`\|`text`), `color`, `size`, `startIcon`, `endIcon`, `disabled` |
| `IconButton` | Icon-only button | `color`, `size`, `edge`, `aria-label` (required) |
| `TextField` | Text input with label | `variant` (`outlined`\|`filled`\|`standard`), `label`, `value`, `onChange`, `error`, `helperText`, `multiline`, `select` |
| `Select` | Dropdown select | `value`, `onChange`, `label`, `multiple` |
| `Checkbox` | Toggle check | `checked`, `onChange`, `indeterminate`, `color` |
| `Switch` | Toggle switch | `checked`, `onChange`, `color` |
| `Radio` + `RadioGroup` | Single selection | `value`, `onChange` on RadioGroup |
| `Slider` | Range input | `value`, `onChange`, `min`, `max`, `step`, `marks` |
| `Autocomplete` | Searchable select | `options`, `value`, `onChange`, `renderInput`, `multiple`, `freeSolo` |
| `ToggleButtonGroup` | Segmented toggle | `value`, `onChange`, `exclusive` |
| `Rating` | Star rating | `value`, `onChange`, `precision`, `max` |
| `Fab` | Floating action button | `color`, `size`, `variant` (`circular`\|`extended`) |

### Data Display

| Component | Purpose | Key Props |
|-----------|---------|-----------|
| `Typography` | Text rendering | `variant` (`h1`-`h6`, `subtitle1`-`2`, `body1`-`2`, `button`, `caption`, `overline`), `color`, `component`, `noWrap`, `gutterBottom` |
| `Avatar` | User/entity icon | `src`, `alt`, `variant` (`circular`\|`rounded`\|`square`) |
| `Badge` | Status indicator | `badgeContent`, `color`, `variant`, `overlap`, `invisible` |
| `Chip` | Compact element | `label`, `variant` (`filled`\|`outlined`), `onDelete`, `icon`, `avatar`, `color` |
| `Divider` | Visual separator | `orientation`, `variant`, `textAlign` |
| `List` | Vertical list | Use with `ListItem`, `ListItemButton`, `ListItemText`, `ListItemIcon` |
| `Table` | Data table | Use with `TableHead`, `TableBody`, `TableRow`, `TableCell`, `TablePagination` |
| `Tooltip` | Hover hint | `title`, `placement`, `arrow` |

### Feedback

| Component | Purpose | Key Props |
|-----------|---------|-----------|
| `Alert` | Status message | `severity` (`error`\|`warning`\|`info`\|`success`), `variant`, `onClose`, `action` |
| `Dialog` | Modal dialog | `open`, `onClose`, `maxWidth`, `fullWidth`, `fullScreen` |
| `Snackbar` | Temporary notification | `open`, `onClose`, `autoHideDuration`, `message`, `anchorOrigin` |
| `CircularProgress` | Spinner | `color`, `size`, `variant` (`indeterminate`\|`determinate`), `value` |
| `LinearProgress` | Progress bar | `color`, `variant` (`indeterminate`\|`determinate`\|`buffer`\|`query`), `value`, `valueBuffer` |
| `Skeleton` | Loading placeholder | `variant` (`text`\|`rectangular`\|`rounded`\|`circular`), `width`, `height` |
| `Backdrop` | Overlay | `open`, `onClick` |

### Surfaces

| Component | Purpose | Key Props |
|-----------|---------|-----------|
| `Card` | Content container | Use with `CardHeader`, `CardMedia`, `CardContent`, `CardActions` |
| `Paper` | Elevated surface | `elevation` (0-24), `variant` (`elevation`\|`outlined`), `square` |
| `AppBar` | Top bar | `position` (`fixed`\|`sticky`\|`static`), `color` |
| `Accordion` | Expandable panel | Use with `AccordionSummary`, `AccordionDetails` |
| `Toolbar` | Horizontal bar | `variant` (`regular`\|`dense`), `disableGutters` |

### Navigation

| Component | Purpose | Key Props |
|-----------|---------|-----------|
| `Tabs` + `Tab` | Tab navigation | `value`, `onChange`, `variant` (`standard`\|`scrollable`\|`fullWidth`) |
| `Drawer` | Side panel | `open`, `onClose`, `variant` (`permanent`\|`persistent`\|`temporary`), `anchor` |
| `Menu` + `MenuItem` | Context menu | `anchorEl`, `open`, `onClose` |
| `Breadcrumbs` | Path navigation | `separator`, `maxItems` |
| `Pagination` | Page navigation | `count`, `page`, `onChange`, `variant`, `shape` |
| `BottomNavigation` | Mobile bottom bar | `value`, `onChange` |
| `SpeedDial` | Floating actions | `ariaLabel`, `icon`, `open` |
| `Stepper` | Multi-step flow | `activeStep`, `orientation` (`horizontal`\|`vertical`) |
| `Link` | Anchor link | `href`, `underline` (`always`\|`hover`\|`none`), `color` |

### Transitions

| Component | Effect |
|-----------|--------|
| `Collapse` | Height expansion |
| `Fade` | Opacity transition |
| `Grow` | Scale + fade in |
| `Slide` | Slide from edge |
| `Zoom` | Scale from center |

All accept: `in` (boolean), `timeout` (ms), `unmountOnExit`.

## Styling with `sx`

The `sx` prop is the primary styling mechanism. It supports theme-aware shorthand, responsive values, and nesting.

```tsx
<Box
  sx={{
    // Spacing: uses theme.spacing() (default 8px unit)
    p: 2,              // padding: 16px
    mt: 3,             // marginTop: 24px
    gap: 1,            // gap: 8px

    // Colors: dot-notation into theme.palette
    bgcolor: 'primary.main',
    color: 'text.secondary',

    // Responsive values
    width: { xs: '100%', sm: '50%', md: 300 },

    // Pseudo-selectors
    '&:hover': { bgcolor: 'primary.dark' },

    // Nested selectors
    '& .MuiButton-root': { ml: 1 },

    // Callback for theme access
    border: (theme) => `1px solid ${theme.palette.divider}`,
  }}
/>
```

**Shorthand properties:** `m`, `mt`, `mr`, `mb`, `ml`, `mx`, `my`, `p`, `pt`, `pr`, `pb`, `pl`, `px`, `py`, `bgcolor`, `color`, `display`, `overflow`, `textOverflow`, `visibility`, `whiteSpace`, `flexDirection`, `flexWrap`, `justifyContent`, `alignItems`, `alignContent`, `order`, `flex`, `flexGrow`, `flexShrink`, `alignSelf`, `width`, `maxWidth`, `minWidth`, `height`, `maxHeight`, `minHeight`, `boxSizing`, `position`, `zIndex`, `top`, `right`, `bottom`, `left`, `boxShadow`, `borderRadius`, `border`, `borderTop`, `borderRight`, `borderBottom`, `borderLeft`, `borderColor`, `typography`, `fontFamily`, `fontSize`, `fontStyle`, `fontWeight`, `letterSpacing`, `lineHeight`, `textAlign`, `textTransform`, `gap`, `columnGap`, `rowGap`, `gridColumn`, `gridRow`, `gridAutoFlow`, `gridAutoColumns`, `gridAutoRows`, `gridTemplateColumns`, `gridTemplateRows`, `gridTemplateAreas`, `gridArea`.

## Theme Creation

```tsx
import { createTheme } from '@mui/material/styles';

const theme = createTheme({
  palette: {
    primary: { main: '#1976d2' },
    secondary: { main: '#9c27b0' },
    // Only main is required; light, dark, contrastText auto-calculated
  },
  typography: {
    fontFamily: '"Inter", "Roboto", "Helvetica", "Arial", sans-serif',
    h1: { fontSize: '2.5rem', fontWeight: 700 },
    button: { textTransform: 'none' }, // disable ALL-CAPS buttons
  },
  shape: { borderRadius: 8 },
  components: {
    // Global default props
    MuiButton: {
      defaultProps: { variant: 'contained', disableElevation: true },
      styleOverrides: {
        root: { borderRadius: 20 },
      },
    },
    MuiTextField: {
      defaultProps: { variant: 'outlined', size: 'small' },
    },
  },
});
```

### Dark Mode

```tsx
const theme = createTheme({
  colorSchemes: { light: true, dark: true }, // enables CSS color scheme switching
  cssVariables: { colorSchemeSelector: 'class' },
});

// Toggle in component:
import { useColorScheme } from '@mui/material/styles';

function ThemeToggle() {
  const { mode, setMode } = useColorScheme();
  if (!mode) return null; // mode is undefined during SSR / first hydration render
  return (
    <IconButton onClick={() => setMode(mode === 'light' ? 'dark' : 'light')}>
      {mode === 'light' ? <DarkModeIcon /> : <LightModeIcon />}
    </IconButton>
  );
}

// Add to index.html <body> before React root to prevent flash:
// <script> from @mui/material: InitColorSchemeScript
import InitColorSchemeScript from '@mui/material/InitColorSchemeScript';
// Render before <App /> in the body
```

### Responsive Breakpoints

Default breakpoints: `xs: 0`, `sm: 600`, `md: 900`, `lg: 1200`, `xl: 1536`.

```tsx
// In sx prop
sx={{ display: { xs: 'none', md: 'block' } }}

// In styled()
const Responsive = styled('div')(({ theme }) => ({
  padding: theme.spacing(1),
  [theme.breakpoints.up('md')]: { padding: theme.spacing(3) },
}));

// In JS
import useMediaQuery from '@mui/material/useMediaQuery';
const isMobile = useMediaQuery((theme) => theme.breakpoints.down('sm'));
```

## Common Composition Patterns

### Dialog

```tsx
<Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
  <DialogTitle>Confirm Action</DialogTitle>
  <DialogContent>
    <DialogContentText>Are you sure?</DialogContentText>
  </DialogContent>
  <DialogActions>
    <Button onClick={handleClose}>Cancel</Button>
    <Button onClick={handleConfirm} variant="contained">Confirm</Button>
  </DialogActions>
</Dialog>
```

### Card

```tsx
<Card>
  <CardMedia component="img" height={200} image="/photo.jpg" alt="Description" />
  <CardContent>
    <Typography variant="h6">Title</Typography>
    <Typography variant="body2" color="text.secondary">Description text.</Typography>
  </CardContent>
  <CardActions>
    <Button size="small">Learn More</Button>
  </CardActions>
</Card>
```

### Form

```tsx
<Stack spacing={2} component="form" onSubmit={handleSubmit}>
  <TextField label="Email" type="email" required />
  <TextField label="Password" type="password" required />
  <FormControlLabel control={<Checkbox />} label="Remember me" />
  <Button type="submit" variant="contained">Sign In</Button>
</Stack>
```

### Responsive App Shell

```tsx
<Box sx={{ display: 'flex' }}>
  <AppBar position="fixed" sx={{ zIndex: (theme) => theme.zIndex.drawer + 1 }}>
    <Toolbar>
      <IconButton edge="start" color="inherit" aria-label="menu"
        sx={{ mr: 2, display: { sm: 'none' } }}
        onClick={() => setMobileOpen(!mobileOpen)}>
        <MenuIcon />
      </IconButton>
      <Typography variant="h6" noWrap>App Title</Typography>
    </Toolbar>
  </AppBar>
  <Drawer variant="permanent" sx={{ display: { xs: 'none', sm: 'block' }, width: 240,
    '& .MuiDrawer-paper': { width: 240, boxSizing: 'border-box' } }}>
    <Toolbar /> {/* spacer */}
    <List>{/* nav items */}</List>
  </Drawer>
  <Box component="main" sx={{ flexGrow: 1, p: 3 }}>
    <Toolbar /> {/* spacer */}
    {/* page content */}
  </Box>
</Box>
```

## The `slots` / `slotProps` Pattern

MUI components use `slots` to replace internal sub-components and `slotProps` to pass props to them. This pattern was introduced incrementally in v5/v6 (where older APIs like `components`/`componentsProps` were deprecated) and fully standardized across all components in v7. Prefer `slots`/`slotProps` over deprecated capitalized props.

```tsx
<TextField
  slotProps={{
    input: { startAdornment: <InputAdornment position="start">$</InputAdornment> },
    inputLabel: { shrink: true },
  }}
/>

<Snackbar
  slots={{ transition: Slide }}
  slotProps={{ transition: { direction: 'up' } }}
/>
```

## Next.js Integration

Install `@mui/material-nextjs` for proper SSR/hydration support:

```bash
npm install @mui/material-nextjs @emotion/cache
```

**App Router** — Wrap your layout in `AppRouterCacheProvider`:

```tsx
// src/app/layout.tsx
import { AppRouterCacheProvider } from '@mui/material-nextjs/v15-appRouter';
import { ThemeProvider } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import theme from './theme'; // your createTheme()

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <AppRouterCacheProvider>
          <ThemeProvider theme={theme}>
            <CssBaseline />
            {children}
          </ThemeProvider>
        </AppRouterCacheProvider>
      </body>
    </html>
  );
}
```

**Pages Router** — Use `documentGetInitialProps` + `DocumentHeadTags` in `_document.tsx` and `AppCacheProvider` in `_app.tsx`. See MUI Next.js integration docs for the full setup.

**Key gotcha:** Components using hooks (including `ThemeProvider`) must be in Client Components (`'use client'`). When passing `next/link` to a `component` prop, wrap it in a `'use client'` file to avoid Next.js restrictions.

## Key Gotchas

- Modern Grid (Grid2 in v6, Grid in v7+) uses `size`/`offset` props. Legacy Grid (Grid in v6, GridLegacy in v7) uses breakpoint props (`xs`, `sm`, `md`, ...). Use `size={{ xs: 12, md: 6 }}` on the modern Grid.
- `Button` text is uppercase by default. Set `textTransform: 'none'` in theme or `sx` to disable.
- `TextField` `select` prop turns it into a `Select` dropdown. Provide `MenuItem` children.
- `useMediaQuery` returns `false` on SSR first render. Use `noSsr` option or handle hydration mismatch.
- For icon-only buttons, always set `aria-label` for accessibility.
- `Autocomplete` requires `renderInput` prop: `renderInput={(params) => <TextField {...params} label="..." />}`.
- `Dialog` automatically links `aria-labelledby` to `DialogTitle` via context. Add explicit `aria-labelledby`/`aria-describedby` only when not using `DialogTitle` or `DialogContentText`.
- Use `component` prop (not `as`) to change rendered element: `<Button component="a" href="...">`.
- Wrap app in `<CssBaseline />` to normalize browser defaults.

## Reference Files

| File | Contents | When to load |
|------|----------|-------------|
| `references/components.md` | API reference for commonly used MUI components with props, types, and examples | Building with a component whose props you need to verify |
| `references/styling.md` | Complete theming and styling guide: createTheme, sx, styled, dark mode, CSS variables, responsive design | Customizing theme, building complex styles, or setting up dark mode |
| `references/migration.md` | Step-by-step migration guides for v3->v4, v4->v5, v5->v6, v6->v7, v7->v9 (alpha), Grid v2, and codemods | Upgrading MUI version or migrating from deprecated APIs |
| `references/patterns.md` | Production-ready page layouts (dashboard, auth, marketing) and UI patterns (data tables, forms, card grids) | Building full pages or complex UI compositions |
| `references/typescript.md` | TypeScript patterns: type imports, generic components (Autocomplete), wrapping/extending, theme augmentation, v7 type changes | Working with MUI types, wrapping components, augmenting theme, or migrating TypeScript code between versions |
