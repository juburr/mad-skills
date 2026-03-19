# MUI Component Reference

## 1. Layout Components

| Component | Purpose | Default Element |
|-----------|---------|-----------------|
| `Box` | Generic container with sx prop support | `div` |
| `Container` | Centered content wrapper with max-width | `div` |
| `Grid` | CSS flexbox grid layout system | `div` |
| `Stack` | One-dimensional flex layout | `div` |

### Box

The most basic layout component. Renders a `<div>` by default and supports all `sx` system props directly.

```tsx
import Box from '@mui/material/Box';

// All system props work directly
<Box sx={{ display: 'flex', gap: 2, p: 2, bgcolor: 'background.paper' }}>
  {children}
</Box>

// Render as a different element
<Box component="section" sx={{ p: 2, border: '1px solid grey' }}>
  {children}
</Box>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `component` | `React.ElementType` | `'div'` | Root element to render |
| `sx` | `SxProps<Theme>` | - | System prop for styles |

All system properties (margin, padding, display, etc.) can be passed directly or via `sx`.

### Container

Centers content horizontally with responsive max-width.

```tsx
import Container from '@mui/material/Container';

<Container maxWidth="lg">
  {/* Content centered, max-width at 'lg' breakpoint */}
</Container>

<Container fixed>
  {/* Fixed width matching current breakpoint */}
</Container>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `maxWidth` | `'xs' \| 'sm' \| 'md' \| 'lg' \| 'xl' \| false` | `'lg'` | Max container width |
| `fixed` | `boolean` | `false` | Fixed width matching breakpoint |
| `disableGutters` | `boolean` | `false` | Remove horizontal padding |

### Grid

Responsive grid layout using CSS flexbox. Uses a 12-column system by default.

```tsx
import Grid from '@mui/material/Grid';

// Basic responsive grid
<Grid container spacing={2}>
  <Grid size={{ xs: 12, sm: 6, md: 4 }}>
    <Item />
  </Grid>
  <Grid size={{ xs: 12, sm: 6, md: 4 }}>
    <Item />
  </Grid>
  <Grid size={{ xs: 12, sm: 6, md: 4 }}>
    <Item />
  </Grid>
</Grid>

// Auto-sizing items
<Grid container spacing={2}>
  <Grid size="grow">{/* Fills remaining space */}</Grid>
  <Grid size="auto">{/* Sizes to content */}</Grid>
</Grid>

// With offset
<Grid container spacing={2}>
  <Grid size={6} offset={3}>
    {/* Centered column */}
  </Grid>
</Grid>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `container` | `boolean` | `false` | Enables flex container behavior |
| `size` | `ResponsiveStyleValue<'auto' \| 'grow' \| number \| false>` | - | Column size for items |
| `spacing` | `ResponsiveStyleValue<number \| string>` | `0` | Gap between items (container only) |
| `columns` | `ResponsiveStyleValue<number>` | `12` | Number of columns |
| `direction` | `ResponsiveStyleValue<'row' \| 'row-reverse' \| 'column' \| 'column-reverse'>` | `'row'` | Flex direction (container only) |
| `offset` | `ResponsiveStyleValue<'auto' \| number>` | - | Column offset for items |
| `columnSpacing` | `ResponsiveStyleValue<number \| string>` | - | Horizontal spacing override |
| `rowSpacing` | `ResponsiveStyleValue<number \| string>` | - | Vertical spacing override |
| `wrap` | `'nowrap' \| 'wrap' \| 'wrap-reverse'` | `'wrap'` | Flex wrap (container only) |

### Stack

One-dimensional layout component for arranging children with consistent spacing.

```tsx
import Stack from '@mui/material/Stack';
import Divider from '@mui/material/Divider';

// Vertical stack (default)
<Stack spacing={2}>
  <Item />
  <Item />
  <Item />
</Stack>

// Horizontal stack with dividers
<Stack direction="row" spacing={2} divider={<Divider orientation="vertical" flexItem />}>
  <Item />
  <Item />
</Stack>

// Responsive direction
<Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
  <Item />
  <Item />
</Stack>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `direction` | `ResponsiveStyleValue<'row' \| 'row-reverse' \| 'column' \| 'column-reverse'>` | `'column'` | Layout direction |
| `spacing` | `ResponsiveStyleValue<number \| string>` | `0` | Space between children |
| `divider` | `React.ReactNode` | - | Element inserted between children |
| `useFlexGap` | `boolean` | `false` | Use CSS `gap` instead of margins |

---

## 2. Input Components

| Component | Purpose | Default Element |
|-----------|---------|-----------------|
| `Button` | Standard button with text/icon | `button` |
| `IconButton` | Button for icon-only actions | `button` |
| `ButtonGroup` | Group of buttons | `div` |
| `Fab` | Floating action button | `button` |
| `Checkbox` | Checkbox input | `span` (SwitchBase) |
| `Radio` / `RadioGroup` | Radio button selection | `span` / `div` |
| `Rating` | Star rating input | `span` |
| `Select` | Dropdown select input | inherits Input |
| `Slider` | Range slider input | `span` |
| `Switch` | Toggle switch | `span` |
| `TextField` | Text input with label | `div` (FormControl) |
| `ToggleButton` / `ToggleButtonGroup` | Segmented control | `button` / `div` |
| `Autocomplete` | Combobox with filtering | `div` |

### Button

```tsx
import Button from '@mui/material/Button';

// Variants
<Button variant="text">Text</Button>
<Button variant="contained">Contained</Button>
<Button variant="outlined">Outlined</Button>

// With icons
<Button variant="contained" startIcon={<SendIcon />}>Send</Button>
<Button variant="outlined" endIcon={<DeleteIcon />}>Delete</Button>

// Loading state
<Button loading variant="contained">Submit</Button>
<Button loading loadingPosition="start" startIcon={<SaveIcon />} variant="contained">
  Save
</Button>

// As a link
<Button href="/about" variant="contained">About</Button>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `'text' \| 'outlined' \| 'contained'` | `'text'` | Visual style |
| `color` | `'inherit' \| 'primary' \| 'secondary' \| 'success' \| 'error' \| 'info' \| 'warning'` | `'primary'` | Theme color |
| `size` | `'small' \| 'medium' \| 'large'` | `'medium'` | Button size |
| `disabled` | `boolean` | `false` | Disabled state |
| `fullWidth` | `boolean` | `false` | Take full container width |
| `startIcon` | `React.ReactNode` | - | Icon before children |
| `endIcon` | `React.ReactNode` | - | Icon after children |
| `href` | `string` | - | Link URL (renders as `<a>`) |
| `loading` | `boolean \| null` | `null` | Show loading state |
| `loadingPosition` | `'start' \| 'end' \| 'center'` | `'center'` | Loading indicator position |
| `disableElevation` | `boolean` | `false` | Remove contained shadow |

### IconButton

```tsx
import IconButton from '@mui/material/IconButton';
import DeleteIcon from '@mui/icons-material/Delete';

<IconButton aria-label="delete" color="primary" size="large">
  <DeleteIcon />
</IconButton>

// With edge alignment
<IconButton edge="start" aria-label="menu">
  <MenuIcon />
</IconButton>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `color` | `'inherit' \| 'default' \| 'primary' \| 'secondary' \| ...` | `'default'` | Theme color |
| `size` | `'small' \| 'medium' \| 'large'` | `'medium'` | Button size |
| `edge` | `'start' \| 'end' \| false` | `false` | Negative margin for alignment |
| `disabled` | `boolean` | `false` | Disabled state |
| `loading` | `boolean \| null` | `null` | Show loading state |

### ButtonGroup

```tsx
import ButtonGroup from '@mui/material/ButtonGroup';
import Button from '@mui/material/Button';

<ButtonGroup variant="contained" aria-label="action buttons">
  <Button>One</Button>
  <Button>Two</Button>
  <Button>Three</Button>
</ButtonGroup>

// Vertical orientation
<ButtonGroup orientation="vertical" variant="outlined">
  <Button>Top</Button>
  <Button>Middle</Button>
  <Button>Bottom</Button>
</ButtonGroup>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `'text' \| 'outlined' \| 'contained'` | `'outlined'` | Button style |
| `color` | same as Button | `'primary'` | Theme color |
| `size` | `'small' \| 'medium' \| 'large'` | `'medium'` | Group size |
| `orientation` | `'horizontal' \| 'vertical'` | `'horizontal'` | Layout direction |
| `disabled` | `boolean` | `false` | Disable all buttons |
| `fullWidth` | `boolean` | `false` | Take full width |

### TextField

The most commonly used input component. Wraps FormControl, InputLabel, Input, and FormHelperText.

```tsx
import TextField from '@mui/material/TextField';

// Basic
<TextField label="Name" variant="outlined" />

// Controlled
<TextField label="Email" value={email} onChange={(e) => setEmail(e.target.value)} />

// Validation
<TextField label="Username" required error={!!error} helperText={error || 'Required'} />

// Multiline
<TextField label="Bio" multiline rows={4} />

// Select mode
<TextField select label="Country" value={country} onChange={handleChange}>
  <MenuItem value="us">United States</MenuItem>
  <MenuItem value="uk">United Kingdom</MenuItem>
</TextField>

// Variants
<TextField variant="outlined" label="Outlined" />
<TextField variant="filled" label="Filled" />
<TextField variant="standard" label="Standard" />
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `'outlined' \| 'filled' \| 'standard'` | `'outlined'` | Visual style |
| `label` | `React.ReactNode` | - | Input label |
| `value` | `unknown` | - | Controlled value |
| `defaultValue` | `unknown` | - | Uncontrolled default |
| `onChange` | `(event) => void` | - | Change handler |
| `error` | `boolean` | `false` | Error state |
| `helperText` | `React.ReactNode` | - | Helper/error text below input |
| `required` | `boolean` | `false` | Mark as required |
| `disabled` | `boolean` | `false` | Disabled state |
| `fullWidth` | `boolean` | `false` | Take full width |
| `size` | `'small' \| 'medium'` | `'medium'` | Input size |
| `multiline` | `boolean` | `false` | Render as textarea |
| `rows` | `number \| string` | - | Fixed row count (multiline) |
| `maxRows` | `number \| string` | - | Max rows (auto-resize) |
| `minRows` | `number \| string` | - | Min rows (auto-resize) |
| `select` | `boolean` | `false` | Render as Select |
| `type` | `string` | - | HTML input type |
| `placeholder` | `string` | - | Placeholder text |
| `autoComplete` | `string` | - | HTML autocomplete attribute |
| `autoFocus` | `boolean` | `false` | Focus on mount |
| `name` | `string` | - | HTML name attribute |
| `id` | `string` | - | HTML id (links label) |
| `inputRef` | `React.Ref` | - | Ref to underlying input |
| `color` | `'primary' \| 'secondary' \| 'error' \| 'info' \| 'success' \| 'warning'` | `'primary'` | Focus color |
| `slotProps` | `object` | - | Props for sub-components (input, inputLabel, htmlInput, formHelperText) |

### Select

Standalone select component (also available via TextField with `select` prop).

```tsx
import Select, { SelectChangeEvent } from '@mui/material/Select';
import MenuItem from '@mui/material/MenuItem';
import FormControl from '@mui/material/FormControl';
import InputLabel from '@mui/material/InputLabel';

// Basic
<FormControl fullWidth>
  <InputLabel id="age-label">Age</InputLabel>
  <Select labelId="age-label" value={age} label="Age" onChange={handleChange}>
    <MenuItem value={10}>Ten</MenuItem>
    <MenuItem value={20}>Twenty</MenuItem>
    <MenuItem value={30}>Thirty</MenuItem>
  </Select>
</FormControl>

// Multiple select
<Select multiple value={names} onChange={handleChange} renderValue={(selected) => selected.join(', ')}>
  {options.map((name) => (
    <MenuItem key={name} value={name}>{name}</MenuItem>
  ))}
</Select>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `value` | `Value \| ''` | - | Selected value |
| `onChange` | `(event: SelectChangeEvent<Value>, child?) => void` | - | Change handler |
| `label` | `React.ReactNode` | - | Label (for outlined variant) |
| `labelId` | `string` | - | ID of associated InputLabel |
| `multiple` | `boolean` | `false` | Allow multiple selections |
| `native` | `boolean` | `false` | Use native `<select>` |
| `displayEmpty` | `boolean` | `false` | Show value when empty |
| `renderValue` | `(value: Value) => React.ReactNode` | - | Custom value renderer |
| `open` | `boolean` | - | Controlled open state |
| `onOpen` | `(event) => void` | - | Open callback |
| `onClose` | `(event) => void` | - | Close callback |
| `autoWidth` | `boolean` | `false` | Auto-width popover |
| `variant` | `'outlined' \| 'standard' \| 'filled'` | `'outlined'` | Visual style |
| `MenuProps` | `Partial<MenuProps>` | - | Props for dropdown Menu |

### Checkbox

```tsx
import Checkbox from '@mui/material/Checkbox';
import FormControlLabel from '@mui/material/FormControlLabel';

// With label
<FormControlLabel control={<Checkbox defaultChecked />} label="Remember me" />

// Controlled
<Checkbox checked={checked} onChange={(e) => setChecked(e.target.checked)} />

// Indeterminate
<Checkbox indeterminate checked={indeterminate} onChange={handleChange} />
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `checked` | `boolean` | - | Controlled checked state |
| `defaultChecked` | `boolean` | - | Uncontrolled default |
| `onChange` | `(event, checked) => void` | - | Change handler |
| `indeterminate` | `boolean` | `false` | Indeterminate state |
| `color` | `'primary' \| 'secondary' \| 'error' \| 'default' \| ...` | `'primary'` | Check color |
| `size` | `'small' \| 'medium' \| 'large'` | `'medium'` | Size |
| `disabled` | `boolean` | `false` | Disabled state |
| `required` | `boolean` | `false` | Required state |
| `value` | `any` | - | Value (for form submission) |

### Radio / RadioGroup

```tsx
import Radio from '@mui/material/Radio';
import RadioGroup from '@mui/material/RadioGroup';
import FormControlLabel from '@mui/material/FormControlLabel';
import FormControl from '@mui/material/FormControl';
import FormLabel from '@mui/material/FormLabel';

<FormControl>
  <FormLabel>Gender</FormLabel>
  <RadioGroup value={value} onChange={(e) => setValue(e.target.value)}>
    <FormControlLabel value="female" control={<Radio />} label="Female" />
    <FormControlLabel value="male" control={<Radio />} label="Male" />
    <FormControlLabel value="other" control={<Radio />} label="Other" />
  </RadioGroup>
</FormControl>

// Horizontal layout
<RadioGroup row value={value} onChange={handleChange}>
  <FormControlLabel value="a" control={<Radio />} label="A" />
  <FormControlLabel value="b" control={<Radio />} label="B" />
</RadioGroup>
```

**RadioGroup key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `value` | `any` | - | Controlled selected value |
| `defaultValue` | `any` | - | Uncontrolled default |
| `onChange` | `(event, value: string) => void` | - | Change handler |
| `name` | `string` | auto | Name for radio inputs |
| `row` | `boolean` | `false` | Horizontal layout |

**Radio key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `color` | `'primary' \| 'secondary' \| 'default' \| ...` | `'primary'` | Radio color |
| `size` | `'small' \| 'medium'` | `'medium'` | Size |
| `disabled` | `boolean` | `false` | Disabled state |

### Switch

```tsx
import Switch from '@mui/material/Switch';
import FormControlLabel from '@mui/material/FormControlLabel';

<FormControlLabel control={<Switch defaultChecked />} label="Notifications" />

// Controlled
<Switch checked={checked} onChange={(e) => setChecked(e.target.checked)} />
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `checked` | `boolean` | - | Controlled checked state |
| `defaultChecked` | `boolean` | - | Uncontrolled default |
| `onChange` | `(event, checked) => void` | - | Change handler |
| `color` | `'primary' \| 'secondary' \| 'error' \| 'default' \| ...` | `'primary'` | Track color |
| `size` | `'small' \| 'medium'` | `'medium'` | Size |
| `disabled` | `boolean` | `false` | Disabled state |
| `edge` | `'start' \| 'end' \| false` | `false` | Edge alignment |

### Slider

```tsx
import Slider from '@mui/material/Slider';

// Basic
<Slider value={value} onChange={(e, val) => setValue(val)} />

// Range slider
<Slider value={[20, 80]} onChange={(e, val) => setRange(val)} />

// Discrete with marks
<Slider defaultValue={30} step={10} marks min={0} max={100} valueLabelDisplay="auto" />

// Custom marks
<Slider
  marks={[
    { value: 0, label: '0' },
    { value: 50, label: '50' },
    { value: 100, label: '100' },
  ]}
/>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `value` | `number \| number[]` | - | Controlled value |
| `defaultValue` | `number \| number[]` | - | Uncontrolled default |
| `onChange` | `(event, value, activeThumb) => void` | - | Change handler |
| `onChangeCommitted` | `(event, value) => void` | - | Fired on mouse up |
| `min` | `number` | `0` | Minimum value |
| `max` | `number` | `100` | Maximum value |
| `step` | `number \| null` | `1` | Step increment (`null` = marks only) |
| `marks` | `boolean \| Mark[]` | `false` | Show marks |
| `valueLabelDisplay` | `'on' \| 'auto' \| 'off'` | `'off'` | Value label visibility |
| `valueLabelFormat` | `string \| (value, index) => ReactNode` | identity | Format value label |
| `orientation` | `'horizontal' \| 'vertical'` | `'horizontal'` | Slider orientation |
| `color` | `'primary' \| 'secondary' \| ...` | `'primary'` | Slider color |
| `size` | `'small' \| 'medium'` | `'medium'` | Size |
| `track` | `'normal' \| false \| 'inverted'` | `'normal'` | Track display mode |
| `disabled` | `boolean` | `false` | Disabled state |

### Rating

```tsx
import Rating from '@mui/material/Rating';

<Rating value={value} onChange={(e, newValue) => setValue(newValue)} />

// Read-only
<Rating value={3.5} readOnly precision={0.5} />

// Custom max
<Rating max={10} value={value} onChange={(e, val) => setValue(val)} />
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `value` | `number \| null` | - | Controlled value |
| `defaultValue` | `number` | `null` | Uncontrolled default |
| `onChange` | `(event, value: number \| null) => void` | - | Change handler |
| `max` | `number` | `5` | Maximum rating |
| `precision` | `number` | `1` | Minimum increment (e.g., `0.5`) |
| `readOnly` | `boolean` | `false` | Read-only display |
| `disabled` | `boolean` | `false` | Disabled state |
| `size` | `'small' \| 'medium' \| 'large'` | `'medium'` | Size |
| `name` | `string` | - | Input name |

### Autocomplete

```tsx
import Autocomplete from '@mui/material/Autocomplete';
import TextField from '@mui/material/TextField';

// Basic
<Autocomplete
  options={['Option 1', 'Option 2', 'Option 3']}
  renderInput={(params) => <TextField {...params} label="Choose" />}
/>

// With objects
<Autocomplete
  options={movies}
  getOptionLabel={(option) => option.title}
  renderInput={(params) => <TextField {...params} label="Movie" />}
/>

// Multiple
<Autocomplete
  multiple
  options={tags}
  value={selectedTags}
  onChange={(e, newValue) => setSelectedTags(newValue)}
  renderInput={(params) => <TextField {...params} label="Tags" />}
/>

// Free solo (allow arbitrary input)
<Autocomplete
  freeSolo
  options={suggestions}
  renderInput={(params) => <TextField {...params} label="Search" />}
/>

// Async loading
<Autocomplete
  options={options}
  loading={loading}
  onInputChange={(e, value) => fetchOptions(value)}
  renderInput={(params) => (
    <TextField {...params} label="Search" slotProps={{
      input: {
        ...params.InputProps,
        endAdornment: (
          <>
            {loading ? <CircularProgress color="inherit" size={20} /> : null}
            {params.InputProps.endAdornment}
          </>
        ),
      },
    }} />
  )}
/>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `options` | `Value[]` | required | Array of options |
| `renderInput` | `(params) => React.ReactNode` | required | Render the input (must be TextField-compatible) |
| `value` | `Value \| Value[] \| null` | - | Controlled value |
| `onChange` | `(event, value, reason, details?) => void` | - | Change handler |
| `inputValue` | `string` | - | Controlled input text |
| `onInputChange` | `(event, value, reason) => void` | - | Input text change handler |
| `getOptionLabel` | `(option) => string` | `(x) => x` | Option label extractor |
| `isOptionEqualToValue` | `(option, value) => boolean` | `===` | Option equality check |
| `multiple` | `boolean` | `false` | Allow multiple selections |
| `freeSolo` | `boolean` | `false` | Allow arbitrary input |
| `loading` | `boolean` | `false` | Show loading state |
| `loadingText` | `React.ReactNode` | `'Loading...'` | Loading message |
| `noOptionsText` | `React.ReactNode` | `'No options'` | Empty state message |
| `disabled` | `boolean` | `false` | Disabled state |
| `fullWidth` | `boolean` | `false` | Take full width |
| `size` | `'small' \| 'medium'` | `'medium'` | Size |
| `disablePortal` | `boolean` | `false` | Render popup inline |
| `renderOption` | `(props, option, state, ownerState) => ReactNode` | - | Custom option renderer |
| `filterOptions` | `(options, state) => Value[]` | built-in | Custom filter function |
| `groupBy` | `(option) => string` | - | Group options by category |
| `limitTags` | `number` | `-1` | Max visible tags (multiple) |
| `disableClearable` | `boolean` | `false` | Hide clear button |

### ToggleButton / ToggleButtonGroup

```tsx
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';

// Exclusive selection
<ToggleButtonGroup exclusive value={alignment} onChange={(e, val) => setAlignment(val)}>
  <ToggleButton value="left"><FormatAlignLeftIcon /></ToggleButton>
  <ToggleButton value="center"><FormatAlignCenterIcon /></ToggleButton>
  <ToggleButton value="right"><FormatAlignRightIcon /></ToggleButton>
</ToggleButtonGroup>

// Multiple selection
<ToggleButtonGroup value={formats} onChange={(e, val) => setFormats(val)}>
  <ToggleButton value="bold"><FormatBoldIcon /></ToggleButton>
  <ToggleButton value="italic"><FormatItalicIcon /></ToggleButton>
</ToggleButtonGroup>
```

**ToggleButtonGroup key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `value` | `any` | - | Selected value(s) |
| `onChange` | `(event, value) => void` | - | Change handler |
| `exclusive` | `boolean` | `false` | Only one selection allowed |
| `orientation` | `'horizontal' \| 'vertical'` | `'horizontal'` | Layout direction |
| `size` | `'small' \| 'medium' \| 'large'` | `'medium'` | Size |
| `color` | `'standard' \| 'primary' \| 'secondary' \| ...` | `'standard'` | Active color |
| `fullWidth` | `boolean` | `false` | Take full width |
| `disabled` | `boolean` | `false` | Disable all buttons |

**ToggleButton key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `value` | `NonNullable<unknown>` | required | Button value |
| `selected` | `boolean` | - | Active state |
| `disabled` | `boolean` | `false` | Disabled state |
| `color` | `'standard' \| 'primary' \| 'secondary' \| ...` | `'standard'` | Active color |
| `size` | `'small' \| 'medium' \| 'large'` | `'medium'` | Size |

### Fab (Floating Action Button)

```tsx
import Fab from '@mui/material/Fab';
import AddIcon from '@mui/icons-material/Add';

// Circular (icon only)
<Fab color="primary" aria-label="add">
  <AddIcon />
</Fab>

// Extended (with text)
<Fab variant="extended" color="primary">
  <NavigationIcon sx={{ mr: 1 }} />
  Navigate
</Fab>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `'circular' \| 'extended'` | `'circular'` | Shape |
| `color` | `'default' \| 'primary' \| 'secondary' \| 'inherit' \| ...` | `'default'` | Color |
| `size` | `'small' \| 'medium' \| 'large'` | `'large'` | Size |
| `disabled` | `boolean` | `false` | Disabled state |
| `href` | `string` | - | Link URL |

### FormControlLabel

Wrapper that pairs a control (Checkbox, Radio, Switch) with a label.

```tsx
import FormControlLabel from '@mui/material/FormControlLabel';

<FormControlLabel control={<Checkbox />} label="Accept terms" />
<FormControlLabel control={<Switch />} label="Dark mode" labelPlacement="start" />
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `control` | `React.ReactElement` | required | The control element |
| `label` | `React.ReactNode` | required | Label text/element |
| `labelPlacement` | `'end' \| 'start' \| 'top' \| 'bottom'` | `'end'` | Label position |
| `checked` | `boolean` | - | Controlled checked state |
| `disabled` | `boolean` | - | Disabled state |
| `onChange` | `(event, checked) => void` | - | Change handler |
| `value` | `unknown` | - | Value for form submission |
| `required` | `boolean` | - | Show required indicator |

---

## 3. Data Display Components

| Component | Purpose | Default Element |
|-----------|---------|-----------------|
| `Typography` | Text rendering with theme styles | varies by variant |
| `Avatar` | User/entity avatar image | `div` |
| `Badge` | Notification badge | `span` |
| `Chip` | Compact element for tags/filters | `div` |
| `Divider` | Visual separator | `hr` |
| `List` | Vertical list layout | `ul` |
| `Table` | Data table layout | `table` |
| `Tooltip` | Hover/focus tooltip | wraps child |

### Typography

```tsx
import Typography from '@mui/material/Typography';

// Heading variants
<Typography variant="h1">Heading 1</Typography>
<Typography variant="h4" gutterBottom>Section Title</Typography>

// Body text
<Typography variant="body1">Paragraph text.</Typography>
<Typography variant="body2" color="textSecondary">Secondary text.</Typography>

// Truncation
<Typography noWrap sx={{ maxWidth: 200 }}>
  This is a very long text that will be truncated with an ellipsis.
</Typography>

// Custom element
<Typography variant="h1" component="h2">
  Styled as h1, rendered as h2
</Typography>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `'h1' \| 'h2' \| 'h3' \| 'h4' \| 'h5' \| 'h6' \| 'subtitle1' \| 'subtitle2' \| 'body1' \| 'body2' \| 'button' \| 'caption' \| 'overline' \| 'inherit'` | `'body1'` | Typography style |
| `color` | `'primary' \| 'secondary' \| 'success' \| 'error' \| 'info' \| 'warning' \| 'textPrimary' \| 'textSecondary' \| 'textDisabled'` | - | Text color |
| `align` | `'inherit' \| 'left' \| 'center' \| 'right' \| 'justify'` | `'inherit'` | Text alignment |
| `gutterBottom` | `boolean` | `false` | Add bottom margin |
| `noWrap` | `boolean` | `false` | Truncate with ellipsis |
| `component` | `React.ElementType` | maps from variant | HTML element to render |

**Variant-to-element mapping:**
- h1-h6 -> `<h1>`-`<h6>`
- subtitle1, subtitle2 -> `<h6>`
- body1, body2, inherit -> `<p>`
- caption, overline, button -> `<span>` (no mapping)

### Avatar

```tsx
import Avatar from '@mui/material/Avatar';

// Image
<Avatar alt="User" src="/avatar.jpg" />

// Letter
<Avatar sx={{ bgcolor: 'primary.main' }}>JD</Avatar>

// Icon
<Avatar><PersonIcon /></Avatar>

// Shapes
<Avatar variant="rounded" src="/avatar.jpg" />
<Avatar variant="square" src="/avatar.jpg" />

// Sizes
<Avatar sx={{ width: 56, height: 56 }} src="/avatar.jpg" />
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `src` | `string` | - | Image URL |
| `alt` | `string` | - | Alt text for image |
| `variant` | `'circular' \| 'rounded' \| 'square'` | `'circular'` | Shape |
| `children` | `React.ReactNode` | - | Fallback content (letter/icon) |
| `sizes` | `string` | - | Responsive image sizes |
| `srcSet` | `string` | - | Responsive image srcSet |

### Badge

```tsx
import Badge from '@mui/material/Badge';
import MailIcon from '@mui/icons-material/Mail';

// Basic
<Badge badgeContent={4} color="primary">
  <MailIcon />
</Badge>

// Dot variant
<Badge variant="dot" color="error">
  <NotificationsIcon />
</Badge>

// Max value
<Badge badgeContent={1000} max={99} color="primary">
  <MailIcon />
</Badge>

// Custom position
<Badge badgeContent={4} anchorOrigin={{ vertical: 'bottom', horizontal: 'right' }}>
  <MailIcon />
</Badge>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `badgeContent` | `React.ReactNode` | - | Badge content |
| `color` | `'primary' \| 'secondary' \| 'default' \| 'error' \| ...` | `'default'` | Badge color |
| `variant` | `'standard' \| 'dot'` | `'standard'` | Badge style |
| `max` | `number` | `99` | Max count display |
| `showZero` | `boolean` | `false` | Show when zero |
| `invisible` | `boolean` | `false` | Hide badge |
| `overlap` | `'rectangular' \| 'circular'` | `'rectangular'` | Wrapped element shape |
| `anchorOrigin` | `{ vertical: 'top' \| 'bottom', horizontal: 'left' \| 'right' }` | `{ vertical: 'top', horizontal: 'right' }` | Badge position |

### Chip

```tsx
import Chip from '@mui/material/Chip';

// Basic
<Chip label="Chip" />
<Chip label="Clickable" onClick={handleClick} />
<Chip label="Deletable" onDelete={handleDelete} />

// Variants
<Chip label="Filled" variant="filled" color="primary" />
<Chip label="Outlined" variant="outlined" color="secondary" />

// With avatar/icon
<Chip avatar={<Avatar>M</Avatar>} label="Avatar Chip" />
<Chip icon={<FaceIcon />} label="With Icon" />
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `label` | `React.ReactNode` | - | Chip text |
| `variant` | `'filled' \| 'outlined'` | `'filled'` | Visual style |
| `color` | `'default' \| 'primary' \| 'secondary' \| 'error' \| ...` | `'default'` | Chip color |
| `size` | `'small' \| 'medium'` | `'medium'` | Size |
| `onClick` | `function` | - | Click handler (makes clickable) |
| `onDelete` | `function` | - | Delete handler (shows delete icon) |
| `icon` | `React.ReactElement` | - | Leading icon |
| `avatar` | `React.ReactElement` | - | Leading avatar |
| `deleteIcon` | `React.ReactElement` | - | Custom delete icon |
| `clickable` | `boolean` | - | Force clickable appearance |
| `disabled` | `boolean` | `false` | Disabled state |

### Divider

```tsx
import Divider from '@mui/material/Divider';

// Horizontal (default)
<Divider />

// With text
<Divider>OR</Divider>
<Divider textAlign="left">Section</Divider>

// Vertical (in flex container)
<Stack direction="row" spacing={2}>
  <Item />
  <Divider orientation="vertical" flexItem />
  <Item />
</Stack>

// Variants
<Divider variant="inset" />   {/* Indented from left */}
<Divider variant="middle" />  {/* Indented from both sides */}
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `orientation` | `'horizontal' \| 'vertical'` | `'horizontal'` | Direction |
| `variant` | `'fullWidth' \| 'inset' \| 'middle'` | `'fullWidth'` | Indentation style |
| `textAlign` | `'center' \| 'left' \| 'right'` | `'center'` | Text position |
| `flexItem` | `boolean` | `false` | Correct height in flex container |
| `children` | `React.ReactNode` | - | Text content |

### List

```tsx
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemIcon from '@mui/material/ListItemIcon';
import ListItemText from '@mui/material/ListItemText';

<List>
  <ListItem disablePadding>
    <ListItemButton>
      <ListItemIcon><InboxIcon /></ListItemIcon>
      <ListItemText primary="Inbox" secondary="5 new messages" />
    </ListItemButton>
  </ListItem>
  <ListItem disablePadding>
    <ListItemButton>
      <ListItemIcon><DraftsIcon /></ListItemIcon>
      <ListItemText primary="Drafts" />
    </ListItemButton>
  </ListItem>
</List>
```

**List key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `dense` | `boolean` | `false` | Compact padding |
| `disablePadding` | `boolean` | `false` | Remove vertical padding |
| `subheader` | `React.ReactNode` | - | List subheader content |

**ListItemButton key props:**
- `selected: boolean` - Selected state
- `disabled: boolean` - Disabled state
- `onClick: function` - Click handler
- `divider: boolean` - Show bottom divider

**ListItemText key props:**
- `primary: React.ReactNode` - Primary text
- `secondary: React.ReactNode` - Secondary text

### Table

```tsx
import Table from '@mui/material/Table';
import TableBody from '@mui/material/TableBody';
import TableCell from '@mui/material/TableCell';
import TableContainer from '@mui/material/TableContainer';
import TableHead from '@mui/material/TableHead';
import TableRow from '@mui/material/TableRow';
import Paper from '@mui/material/Paper';

<TableContainer component={Paper}>
  <Table>
    <TableHead>
      <TableRow>
        <TableCell>Name</TableCell>
        <TableCell align="right">Calories</TableCell>
      </TableRow>
    </TableHead>
    <TableBody>
      {rows.map((row) => (
        <TableRow key={row.name}>
          <TableCell>{row.name}</TableCell>
          <TableCell align="right">{row.calories}</TableCell>
        </TableRow>
      ))}
    </TableBody>
  </Table>
</TableContainer>
```

**Table key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `size` | `'small' \| 'medium'` | `'medium'` | Cell padding |
| `stickyHeader` | `boolean` | `false` | Sticky header row |
| `padding` | `'normal' \| 'checkbox' \| 'none'` | `'normal'` | Cell padding style |

**TableCell key props:**
- `align: 'left' | 'center' | 'right' | 'justify' | 'inherit'`
- `padding: 'normal' | 'checkbox' | 'none'`
- `sortDirection: 'asc' | 'desc' | false`
- `variant: 'head' | 'body' | 'footer'` (auto-detected from context)

### Tooltip

```tsx
import Tooltip from '@mui/material/Tooltip';

// Basic
<Tooltip title="Delete">
  <IconButton><DeleteIcon /></IconButton>
</Tooltip>

// Placement
<Tooltip title="Add" placement="top">
  <Button>Top</Button>
</Tooltip>

// With arrow
<Tooltip title="Info" arrow>
  <IconButton><InfoIcon /></IconButton>
</Tooltip>

// Controlled
<Tooltip open={open} onClose={handleClose} onOpen={handleOpen} title="Controlled">
  <Button>Hover me</Button>
</Tooltip>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `React.ReactNode` | required | Tooltip content |
| `children` | `React.ReactElement` | required | Trigger element |
| `placement` | `'top' \| 'bottom' \| 'left' \| 'right' \| 'top-start' \| 'top-end' \| ...` | `'bottom'` | Position |
| `arrow` | `boolean` | `false` | Show arrow |
| `open` | `boolean` | - | Controlled open state |
| `onOpen` | `(event) => void` | - | Open callback |
| `onClose` | `(event) => void` | - | Close callback |
| `enterDelay` | `number` | `100` | Show delay (ms) |
| `leaveDelay` | `number` | `0` | Hide delay (ms) |
| `followCursor` | `boolean` | `false` | Follow mouse |
| `disableInteractive` | `boolean` | `false` | Close when hovering tooltip |
| `disableHoverListener` | `boolean` | `false` | Ignore hover events |
| `disableFocusListener` | `boolean` | `false` | Ignore focus events |
| `disableTouchListener` | `boolean` | `false` | Ignore touch events |
| `describeChild` | `boolean` | `false` | Use as aria-describedby |

---

## 4. Feedback Components

| Component | Purpose | Default Element |
|-----------|---------|-----------------|
| `Alert` | Status messages | Paper-based `div` |
| `Backdrop` | Overlay behind modals | `div` |
| `Dialog` | Modal dialog window | Modal-based |
| `CircularProgress` | Circular loading indicator | `span` |
| `LinearProgress` | Linear loading bar | `span` |
| `Skeleton` | Content placeholder | `span` |
| `Snackbar` | Brief notification | `div` |

### Alert

```tsx
import Alert from '@mui/material/Alert';
import AlertTitle from '@mui/material/AlertTitle';

// Severities
<Alert severity="error">This is an error.</Alert>
<Alert severity="warning">This is a warning.</Alert>
<Alert severity="info">This is info.</Alert>
<Alert severity="success">This is success.</Alert>

// With title
<Alert severity="error">
  <AlertTitle>Error</AlertTitle>
  Something went wrong.
</Alert>

// Variants
<Alert variant="filled" severity="success">Filled</Alert>
<Alert variant="outlined" severity="info">Outlined</Alert>

// Dismissible
<Alert onClose={() => setOpen(false)}>Closeable alert</Alert>

// Custom action
<Alert severity="warning" action={<Button size="small">UNDO</Button>}>
  Item deleted.
</Alert>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `severity` | `'error' \| 'warning' \| 'info' \| 'success'` | `'success'` | Alert severity/color |
| `variant` | `'standard' \| 'filled' \| 'outlined'` | `'standard'` | Visual style |
| `color` | `'error' \| 'warning' \| 'info' \| 'success'` | from severity | Override color |
| `onClose` | `(event) => void` | - | Close handler (shows close button) |
| `action` | `React.ReactNode` | - | Custom action element |
| `icon` | `React.ReactNode \| false` | from severity | Custom icon or `false` to hide |
| `closeText` | `string` | `'Close'` | Close button aria label |

### Dialog

```tsx
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogContentText from '@mui/material/DialogContentText';
import DialogActions from '@mui/material/DialogActions';

<Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
  <DialogTitle>Confirm Delete</DialogTitle>
  <DialogContent>
    <DialogContentText>
      Are you sure you want to delete this item?
    </DialogContentText>
  </DialogContent>
  <DialogActions>
    <Button onClick={handleClose}>Cancel</Button>
    <Button onClick={handleConfirm} variant="contained" color="error">
      Delete
    </Button>
  </DialogActions>
</Dialog>

// Full-screen dialog
<Dialog fullScreen open={open} onClose={handleClose}>
  {/* ... */}
</Dialog>

// Form dialog
<Dialog open={open} onClose={handleClose}>
  <DialogTitle>Subscribe</DialogTitle>
  <DialogContent>
    <TextField autoFocus margin="dense" label="Email" type="email" fullWidth variant="standard" />
  </DialogContent>
  <DialogActions>
    <Button onClick={handleClose}>Cancel</Button>
    <Button onClick={handleSubscribe}>Subscribe</Button>
  </DialogActions>
</Dialog>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `open` | `boolean` | required | Visibility state |
| `onClose` | `(event, reason) => void` | - | Close handler. Reason: `'escapeKeyDown' \| 'backdropClick'` |
| `maxWidth` | `'xs' \| 'sm' \| 'md' \| 'lg' \| 'xl' \| false` | `'sm'` | Max width |
| `fullWidth` | `boolean` | `false` | Stretch to maxWidth |
| `fullScreen` | `boolean` | `false` | Full-screen mode |
| `scroll` | `'body' \| 'paper'` | `'paper'` | Scroll container |
| `transitionDuration` | `number \| { enter, exit }` | theme default | Transition duration |

### CircularProgress

```tsx
import CircularProgress from '@mui/material/CircularProgress';

// Indeterminate (default)
<CircularProgress />

// Determinate
<CircularProgress variant="determinate" value={75} />

// Sizes and colors
<CircularProgress size={24} />
<CircularProgress color="secondary" />
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `'determinate' \| 'indeterminate'` | `'indeterminate'` | Animation style |
| `value` | `number` | `0` | Progress (0-100, determinate) |
| `size` | `number \| string` | `40` | Diameter in px |
| `thickness` | `number` | `3.6` | Circle thickness |
| `color` | `'primary' \| 'secondary' \| 'inherit' \| ...` | `'primary'` | Color |
| `disableShrink` | `boolean` | `false` | Disable shrink animation |

### LinearProgress

```tsx
import LinearProgress from '@mui/material/LinearProgress';

// Indeterminate (default)
<LinearProgress />

// Determinate
<LinearProgress variant="determinate" value={progress} />

// Buffer
<LinearProgress variant="buffer" value={progress} valueBuffer={buffer} />
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `'determinate' \| 'indeterminate' \| 'buffer' \| 'query'` | `'indeterminate'` | Animation style |
| `value` | `number` | - | Progress (0-100) |
| `valueBuffer` | `number` | - | Buffer value (buffer variant) |
| `color` | `'primary' \| 'secondary' \| 'inherit' \| ...` | `'primary'` | Color |

### Skeleton

```tsx
import Skeleton from '@mui/material/Skeleton';

// Text placeholder
<Skeleton variant="text" sx={{ fontSize: '1rem' }} />

// Rectangular (for images/cards)
<Skeleton variant="rectangular" width={210} height={118} />

// Rounded
<Skeleton variant="rounded" width={210} height={60} />

// Circular (for avatars)
<Skeleton variant="circular" width={40} height={40} />

// Wrapping content (infers dimensions)
<Skeleton variant="rectangular">
  <Avatar />
</Skeleton>

// Wave animation
<Skeleton animation="wave" />

// No animation
<Skeleton animation={false} />
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `'text' \| 'rectangular' \| 'rounded' \| 'circular'` | `'text'` | Shape |
| `width` | `number \| string` | - | Width |
| `height` | `number \| string` | - | Height |
| `animation` | `'pulse' \| 'wave' \| false` | `'pulse'` | Animation style |
| `children` | `React.ReactNode` | - | Content to infer dimensions from |

### Snackbar

```tsx
import Snackbar from '@mui/material/Snackbar';
import Alert from '@mui/material/Alert';

// Basic
<Snackbar open={open} autoHideDuration={6000} onClose={handleClose} message="Note archived" />

// With Alert
<Snackbar open={open} autoHideDuration={6000} onClose={handleClose}>
  <Alert onClose={handleClose} severity="success" variant="filled" sx={{ width: '100%' }}>
    Success!
  </Alert>
</Snackbar>

// Position
<Snackbar anchorOrigin={{ vertical: 'top', horizontal: 'center' }} open={open} message="Top center" />
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `open` | `boolean` | - | Visibility state |
| `onClose` | `(event, reason) => void` | - | Close handler. Reason: `'timeout' \| 'clickaway' \| 'escapeKeyDown'` |
| `message` | `React.ReactNode` | - | Message text |
| `autoHideDuration` | `number \| null` | `null` | Auto-hide delay (ms) |
| `anchorOrigin` | `{ vertical: 'top' \| 'bottom', horizontal: 'left' \| 'center' \| 'right' }` | `{ vertical: 'bottom', horizontal: 'left' }` | Position |
| `action` | `React.ReactNode` | - | Action element |
| `children` | `React.ReactElement` | - | Custom content (overrides message) |
| `resumeHideDuration` | `number` | - | Resume delay after interaction |

### Backdrop

```tsx
import Backdrop from '@mui/material/Backdrop';
import CircularProgress from '@mui/material/CircularProgress';

<Backdrop open={loading} sx={{ color: '#fff', zIndex: (theme) => theme.zIndex.drawer + 1 }}>
  <CircularProgress color="inherit" />
</Backdrop>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `open` | `boolean` | required | Visibility state |
| `invisible` | `boolean` | `false` | Transparent backdrop |
| `transitionDuration` | `number \| { enter, exit }` | - | Transition duration |
| `children` | `React.ReactNode` | - | Content on top of backdrop |

---

## 5. Surface Components

| Component | Purpose | Default Element |
|-----------|---------|-----------------|
| `Paper` | Elevated surface | `div` |
| `Card` | Content card | `div` |
| `Accordion` | Expandable panel | `div` (Paper) |
| `AppBar` | Top application bar | `header` (Paper) |
| `Toolbar` | Bar content layout | `div` |

### Paper

Base surface component for elevation and theming.

```tsx
import Paper from '@mui/material/Paper';

<Paper elevation={3} sx={{ p: 2 }}>
  Content on elevated surface
</Paper>

// Outlined variant
<Paper variant="outlined" sx={{ p: 2 }}>
  Outlined surface
</Paper>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `elevation` | `number` (0-24) | `1` | Shadow depth |
| `variant` | `'elevation' \| 'outlined'` | `'elevation'` | Surface style |
| `square` | `boolean` | `false` | Remove border radius |

### Card

Extends Paper with card-specific semantics.

```tsx
import Card from '@mui/material/Card';
import CardContent from '@mui/material/CardContent';
import CardActions from '@mui/material/CardActions';
import CardHeader from '@mui/material/CardHeader';
import CardMedia from '@mui/material/CardMedia';

<Card>
  <CardHeader
    avatar={<Avatar>R</Avatar>}
    title="Card Title"
    subheader="September 14, 2024"
    action={<IconButton><MoreVertIcon /></IconButton>}
  />
  <CardMedia component="img" height="194" image="/image.jpg" alt="Description" />
  <CardContent>
    <Typography variant="body2" color="textSecondary">
      Card content text.
    </Typography>
  </CardContent>
  <CardActions>
    <Button size="small">Share</Button>
    <Button size="small">Learn More</Button>
  </CardActions>
</Card>

// Clickable card
<Card>
  <CardActionArea>
    <CardMedia component="img" height="140" image="/img.jpg" />
    <CardContent>
      <Typography variant="h5">Title</Typography>
    </CardContent>
  </CardActionArea>
</Card>
```

**Card key props (extends Paper):**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `raised` | `boolean` | `false` | Raised shadow |
| `elevation` | `number` | `1` | Shadow depth |
| `variant` | `'elevation' \| 'outlined'` | `'elevation'` | Surface style |

**CardHeader key props:**
- `title: React.ReactNode` - Header title
- `subheader: React.ReactNode` - Subtitle
- `avatar: React.ReactNode` - Leading avatar
- `action: React.ReactNode` - Trailing action

**CardMedia key props:**
- `image: string` - Background image URL
- `component: 'img' | 'video' | ...` - Media element
- `height: string | number` - Media height

### Accordion

```tsx
import Accordion from '@mui/material/Accordion';
import AccordionSummary from '@mui/material/AccordionSummary';
import AccordionDetails from '@mui/material/AccordionDetails';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';

// Basic
<Accordion>
  <AccordionSummary expandIcon={<ExpandMoreIcon />}>
    <Typography>Section 1</Typography>
  </AccordionSummary>
  <AccordionDetails>
    <Typography>Content for section 1.</Typography>
  </AccordionDetails>
</Accordion>

// Controlled
<Accordion expanded={expanded === 'panel1'} onChange={(e, isExpanded) => setExpanded(isExpanded ? 'panel1' : false)}>
  <AccordionSummary expandIcon={<ExpandMoreIcon />}>
    <Typography>Controlled Panel</Typography>
  </AccordionSummary>
  <AccordionDetails>
    <Typography>Controlled content.</Typography>
  </AccordionDetails>
</Accordion>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `expanded` | `boolean` | - | Controlled expanded state |
| `defaultExpanded` | `boolean` | `false` | Initial expanded state |
| `onChange` | `(event, expanded: boolean) => void` | - | Change handler |
| `disabled` | `boolean` | `false` | Disabled state |
| `disableGutters` | `boolean` | `false` | Remove vertical spacing |

### AppBar

```tsx
import AppBar from '@mui/material/AppBar';
import Toolbar from '@mui/material/Toolbar';
import Typography from '@mui/material/Typography';
import IconButton from '@mui/material/IconButton';
import MenuIcon from '@mui/icons-material/Menu';

<AppBar position="static">
  <Toolbar>
    <IconButton edge="start" color="inherit" aria-label="menu" sx={{ mr: 2 }}>
      <MenuIcon />
    </IconButton>
    <Typography variant="h6" sx={{ flexGrow: 1 }}>
      My App
    </Typography>
    <Button color="inherit">Login</Button>
  </Toolbar>
</AppBar>

// Fixed AppBar (add Toolbar spacer below)
<AppBar position="fixed">
  <Toolbar>{/* ... */}</Toolbar>
</AppBar>
<Toolbar /> {/* Spacer to push content below fixed AppBar */}
```

**AppBar key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `position` | `'fixed' \| 'absolute' \| 'sticky' \| 'static' \| 'relative'` | `'fixed'` | CSS position |
| `color` | `'default' \| 'inherit' \| 'primary' \| 'secondary' \| 'transparent' \| ...` | `'primary'` | Background color |
| `elevation` | `number` | `4` | Shadow depth |
| `enableColorOnDark` | `boolean` | `false` | Apply color in dark mode |

**Toolbar key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `'regular' \| 'dense'` | `'regular'` | Height variant |
| `disableGutters` | `boolean` | `false` | Remove horizontal padding |

---

## 6. Navigation Components

| Component | Purpose | Default Element |
|-----------|---------|-----------------|
| `BottomNavigation` | Mobile bottom nav | `div` |
| `Breadcrumbs` | Breadcrumb trail | `nav` |
| `Drawer` | Side navigation panel | Modal/div |
| `Link` | Styled anchor element | `a` |
| `Menu` | Dropdown menu | Popover |
| `MenuItem` | Menu item | `li` |
| `Pagination` | Page navigation | `nav` |
| `Stepper` | Multi-step workflow | `div` |
| `Tabs` / `Tab` | Tabbed navigation | `div` / `button` (ButtonBase) |

### Tabs / Tab

```tsx
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';

// Basic
const [value, setValue] = useState(0);

<Tabs value={value} onChange={(e, newValue) => setValue(newValue)}>
  <Tab label="Item One" />
  <Tab label="Item Two" />
  <Tab label="Item Three" />
</Tabs>

// With icons
<Tabs value={value} onChange={(e, v) => setValue(v)}>
  <Tab icon={<PhoneIcon />} label="Phone" />
  <Tab icon={<FavoriteIcon />} label="Favorites" />
</Tabs>

// Scrollable
<Tabs value={value} onChange={handleChange} variant="scrollable" scrollButtons="auto">
  {items.map((item, i) => <Tab key={i} label={item} />)}
</Tabs>

// Vertical
<Tabs orientation="vertical" value={value} onChange={handleChange}>
  <Tab label="Item 1" />
  <Tab label="Item 2" />
</Tabs>
```

**Tabs key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `value` | `any` | - | Selected tab value |
| `onChange` | `(event, value) => void` | - | Change handler |
| `variant` | `'standard' \| 'scrollable' \| 'fullWidth'` | `'standard'` | Display behavior |
| `orientation` | `'horizontal' \| 'vertical'` | `'horizontal'` | Layout direction |
| `centered` | `boolean` | `false` | Center tabs |
| `scrollButtons` | `'auto' \| true \| false` | `'auto'` | Show scroll buttons |
| `textColor` | `'primary' \| 'secondary' \| 'inherit'` | `'primary'` | Tab text color |
| `indicatorColor` | `'primary' \| 'secondary'` | `'primary'` | Indicator color |
| `allowScrollButtonsMobile` | `boolean` | `false` | Show scroll buttons on mobile |

**Tab key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `label` | `React.ReactNode` | - | Tab label |
| `icon` | `string \| React.ReactElement` | - | Tab icon |
| `iconPosition` | `'top' \| 'bottom' \| 'start' \| 'end'` | `'top'` | Icon position relative to label |
| `value` | `any` | child index | Tab value |
| `disabled` | `boolean` | `false` | Disabled state |
| `wrapped` | `boolean` | `false` | Allow label wrapping |

### Menu / MenuItem

```tsx
import Menu from '@mui/material/Menu';
import MenuItem from '@mui/material/MenuItem';

const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);
const open = Boolean(anchorEl);

<Button onClick={(e) => setAnchorEl(e.currentTarget)}>Open Menu</Button>
<Menu anchorEl={anchorEl} open={open} onClose={() => setAnchorEl(null)}>
  <MenuItem onClick={handleClose}>Profile</MenuItem>
  <MenuItem onClick={handleClose}>Settings</MenuItem>
  <Divider />
  <MenuItem onClick={handleClose}>Logout</MenuItem>
</Menu>
```

**Menu key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `anchorEl` | `HTMLElement \| null \| (() => HTMLElement)` | - | Anchor element |
| `open` | `boolean` | required | Visibility state |
| `onClose` | `(event, reason) => void` | - | Close handler |
| `variant` | `'menu' \| 'selectedMenu'` | `'selectedMenu'` | Focus behavior |
| `transitionDuration` | `number \| 'auto' \| { enter, exit }` | `'auto'` | Transition speed |

**MenuItem key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `selected` | `boolean` | `false` | Selected state |
| `disabled` | `boolean` | `false` | Disabled state |
| `dense` | `boolean` | `false` | Compact padding |
| `divider` | `boolean` | `false` | Bottom divider |

### Drawer

```tsx
import Drawer from '@mui/material/Drawer';

// Temporary (overlay)
<Drawer anchor="left" open={open} onClose={() => setOpen(false)}>
  <List>{/* navigation items */}</List>
</Drawer>

// Permanent (always visible)
<Drawer variant="permanent" anchor="left" sx={{ width: 240, '& .MuiDrawer-paper': { width: 240 } }}>
  <Toolbar />
  <List>{/* navigation items */}</List>
</Drawer>

// Persistent (push content)
<Drawer variant="persistent" open={open} anchor="left">
  <List>{/* navigation items */}</List>
</Drawer>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `'permanent' \| 'persistent' \| 'temporary'` | `'temporary'` | Drawer behavior |
| `anchor` | `'left' \| 'top' \| 'right' \| 'bottom'` | `'left'` | Slide direction |
| `open` | `boolean` | `false` | Open state |
| `onClose` | `(event, reason) => void` | - | Close handler (temporary only) |
| `elevation` | `number` | `16` | Shadow depth |
| `transitionDuration` | `number \| { enter, exit }` | theme default | Transition duration |

### Link

```tsx
import Link from '@mui/material/Link';

<Link href="/about">About</Link>
<Link href="#" underline="hover">Hover underline</Link>
<Link href="#" underline="none" color="secondary">No underline</Link>
<Link component="button" onClick={handleClick}>Button link</Link>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `href` | `string` | - | Link URL |
| `underline` | `'none' \| 'hover' \| 'always'` | `'always'` | Underline behavior |
| `color` | `TypographyProps['color']` | `'primary'` | Text color |
| `variant` | `TypographyProps['variant']` | `'inherit'` | Typography variant |
| `component` | `React.ElementType` | `'a'` | Root element |

### Breadcrumbs

```tsx
import Breadcrumbs from '@mui/material/Breadcrumbs';
import Link from '@mui/material/Link';
import Typography from '@mui/material/Typography';

<Breadcrumbs aria-label="breadcrumb">
  <Link underline="hover" href="/">Home</Link>
  <Link underline="hover" href="/category">Category</Link>
  <Typography color="textPrimary">Current Page</Typography>
</Breadcrumbs>

// Custom separator
<Breadcrumbs separator=">" aria-label="breadcrumb">
  <Link href="/">Home</Link>
  <Typography>Page</Typography>
</Breadcrumbs>

// Collapsed
<Breadcrumbs maxItems={2} aria-label="breadcrumb">
  <Link href="/">Home</Link>
  <Link href="/cat">Category</Link>
  <Link href="/cat/sub">Subcategory</Link>
  <Typography>Page</Typography>
</Breadcrumbs>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `separator` | `React.ReactNode` | `'/'` | Separator element |
| `maxItems` | `number` | `8` | Max items before collapsing |
| `itemsBeforeCollapse` | `number` | `1` | Items shown before ellipsis |
| `itemsAfterCollapse` | `number` | `1` | Items shown after ellipsis |

### Pagination

```tsx
import Pagination from '@mui/material/Pagination';

<Pagination count={10} page={page} onChange={(e, value) => setPage(value)} />
<Pagination count={10} color="primary" variant="outlined" shape="rounded" />
<Pagination count={10} size="small" />
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `count` | `number` | `1` | Total pages |
| `page` | `number` | - | Current page (controlled) |
| `onChange` | `(event, page: number) => void` | - | Page change handler |
| `color` | `'primary' \| 'secondary' \| 'standard'` | `'standard'` | Active color |
| `variant` | `'text' \| 'outlined'` | `'text'` | Button style |
| `shape` | `'circular' \| 'rounded'` | `'circular'` | Button shape |
| `size` | `'small' \| 'medium' \| 'large'` | `'medium'` | Size |
| `boundaryCount` | `number` | `1` | Pages at start/end |
| `siblingCount` | `number` | `1` | Pages around current |
| `showFirstButton` | `boolean` | `false` | Show first page button |
| `showLastButton` | `boolean` | `false` | Show last page button |

### Stepper

```tsx
import Stepper from '@mui/material/Stepper';
import Step from '@mui/material/Step';
import StepLabel from '@mui/material/StepLabel';

<Stepper activeStep={activeStep}>
  {steps.map((label) => (
    <Step key={label}>
      <StepLabel>{label}</StepLabel>
    </Step>
  ))}
</Stepper>

// Vertical
<Stepper activeStep={activeStep} orientation="vertical">
  {steps.map((label, index) => (
    <Step key={label}>
      <StepLabel>{label}</StepLabel>
      <StepContent>
        <Typography>{getStepContent(index)}</Typography>
        <Button onClick={handleNext}>Continue</Button>
      </StepContent>
    </Step>
  ))}
</Stepper>

// Alternative label placement
<Stepper activeStep={activeStep} alternativeLabel>
  {steps.map((label) => (
    <Step key={label}>
      <StepLabel>{label}</StepLabel>
    </Step>
  ))}
</Stepper>
```

**Stepper key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `activeStep` | `number` | `0` | Current step (0-based) |
| `orientation` | `'horizontal' \| 'vertical'` | `'horizontal'` | Layout direction |
| `alternativeLabel` | `boolean` | `false` | Labels below icons |
| `nonLinear` | `boolean` | `false` | Allow non-sequential navigation |
| `connector` | `React.ReactElement \| null` | `<StepConnector />` | Step connector |

---

## 7. Utility Components

| Component | Purpose |
|-----------|---------|
| `Modal` | Base overlay component (use Dialog/Drawer instead) |
| `Popover` | Positioned popup relative to anchor |
| `Popper` | Positioned popup (no backdrop) |
| `ClickAwayListener` | Detect clicks outside component |
| `Portal` | Render children in different DOM node |
| `Collapse` | Expand/collapse transition |
| `Fade` | Fade in/out transition |
| `Grow` | Grow/shrink transition |
| `Slide` | Slide in/out transition |
| `Zoom` | Zoom in/out transition |

### Modal

Low-level component used by Dialog, Drawer, Menu, and Popover. Prefer Dialog for most use cases.

```tsx
import Modal from '@mui/material/Modal';

<Modal open={open} onClose={handleClose}>
  <Box sx={{
    position: 'absolute', top: '50%', left: '50%',
    transform: 'translate(-50%, -50%)',
    width: 400, bgcolor: 'background.paper',
    boxShadow: 24, p: 4, borderRadius: 1,
  }}>
    <Typography variant="h6">Modal Title</Typography>
    <Typography>Modal content here.</Typography>
  </Box>
</Modal>
```

**Key props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `open` | `boolean` | required | Visibility state |
| `onClose` | `(event, reason) => void` | - | Close handler |
| `children` | `React.ReactElement` | required | Modal content |
| `keepMounted` | `boolean` | `false` | Keep in DOM when closed |
| `disableAutoFocus` | `boolean` | `false` | Don't auto-focus |
| `disableEnforceFocus` | `boolean` | `false` | Allow focus outside |
| `disablePortal` | `boolean` | `false` | Render inline |
| `disableScrollLock` | `boolean` | `false` | Allow body scroll |
| `hideBackdrop` | `boolean` | `false` | Hide backdrop |
| `container` | `HTMLElement \| (() => HTMLElement)` | `document.body` | Portal target |

### Transitions

All transition components share a common API pattern.

```tsx
import Collapse from '@mui/material/Collapse';
import Fade from '@mui/material/Fade';
import Grow from '@mui/material/Grow';
import Slide from '@mui/material/Slide';
import Zoom from '@mui/material/Zoom';

// Collapse - expand vertically
<Collapse in={checked}>
  <Paper sx={{ p: 2 }}>Content</Paper>
</Collapse>

// Fade
<Fade in={checked}>
  <Paper sx={{ p: 2 }}>Content</Paper>
</Fade>

// Grow - scale + fade
<Grow in={checked}>
  <Paper sx={{ p: 2 }}>Content</Paper>
</Grow>

// Slide - from direction
<Slide direction="up" in={checked} mountOnEnter unmountOnExit>
  <Paper sx={{ p: 2 }}>Content</Paper>
</Slide>

// Zoom
<Zoom in={checked}>
  <Paper sx={{ p: 2 }}>Content</Paper>
</Zoom>
```

**Common transition props:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `in` | `boolean` | `false` | Show/hide trigger |
| `timeout` | `number \| { enter, exit }` | varies | Duration in ms |
| `mountOnEnter` | `boolean` | `false` | Mount on first `in=true` |
| `unmountOnExit` | `boolean` | `false` | Unmount on exit |

**Collapse-specific:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `orientation` | `'horizontal' \| 'vertical'` | `'vertical'` | Collapse direction |
| `collapsedSize` | `number \| string` | `0` | Minimum collapsed size |

**Slide-specific:**
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `direction` | `'down' \| 'left' \| 'right' \| 'up'` | `'down'` | Slide direction |
| `container` | `HTMLElement \| (() => HTMLElement)` | - | Slide boundary |

---

## Common Patterns

### The `component` Prop

All MUI components accept a `component` prop to change the rendered HTML element:

```tsx
<Button component="a" href="/about">About</Button>
<Typography component="h1" variant="h4">Title</Typography>
<Box component="section">Content</Box>
<ListItemButton component="a" href="/settings">Settings</ListItemButton>
```

### The `sx` Prop

The `sx` prop works on all MUI components and supports:
- Theme-aware values: `sx={{ p: 2 }}` uses `theme.spacing(2)`
- Responsive values: `sx={{ width: { xs: '100%', md: '50%' } }}`
- Pseudo-selectors: `sx={{ '&:hover': { bgcolor: 'primary.dark' } }}`
- Nested selectors: `sx={{ '& .MuiButton-root': { ml: 1 } }}`
- Callbacks: `sx={{ color: (theme) => theme.palette.primary.main }}`

### The `slots` and `slotProps` Pattern

Modern MUI components use `slots` to replace sub-components and `slotProps` to pass props to them:

```tsx
<TextField
  slots={{ input: CustomInput }}
  slotProps={{
    input: { 'data-testid': 'custom-input' },
    inputLabel: { shrink: true },
    formHelperText: { sx: { ml: 0 } },
  }}
/>
```

### Color Prop Values

Most components accept these color values:
- `'primary'` - theme primary color
- `'secondary'` - theme secondary color
- `'error'` - theme error color
- `'warning'` - theme warning color
- `'info'` - theme info color
- `'success'` - theme success color
- `'inherit'` - inherit from parent
- `'default'` - neutral color (some components)

### Size Prop Values

Most components accept: `'small' | 'medium' | 'large'`

Some components (TextField, Slider, etc.) only support: `'small' | 'medium'`

### Accessibility Patterns

- Always provide `aria-label` or `aria-labelledby` for icon-only buttons
- Use `id` on TextField to link label and helperText
- Wrap RadioGroup with FormControl + FormLabel
- Use `aria-label` on Tabs for screen readers
- Use Dialog's `aria-labelledby` pointing to DialogTitle
