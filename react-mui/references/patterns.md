# MUI Patterns and Recipes

Production-ready patterns for common Material UI layouts and component compositions. All examples use MUI v6+ with TypeScript.

## Table of Contents

- [Page Layout Patterns](#page-layout-patterns)
- [Common UI Patterns](#common-ui-patterns)
- [Component Composition Patterns](#component-composition-patterns)
- [Performance Patterns](#performance-patterns)

---

## Page Layout Patterns

### Dashboard Layout (AppBar + Drawer + Main Content)

The canonical MUI dashboard uses a permanent Drawer on desktop and a mobile AppBar with a temporary Drawer. The layout is a flex row with the sidebar and main content side by side.

```tsx
import * as React from 'react';
import { styled } from '@mui/material/styles';
import Box from '@mui/material/Box';
import CssBaseline from '@mui/material/CssBaseline';
import MuiDrawer, { drawerClasses } from '@mui/material/Drawer';
import AppBar from '@mui/material/AppBar';
import Toolbar from '@mui/material/Toolbar';
import Typography from '@mui/material/Typography';
import IconButton from '@mui/material/IconButton';
import MenuIcon from '@mui/icons-material/Menu';
import Stack from '@mui/material/Stack';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemIcon from '@mui/material/ListItemIcon';
import ListItemText from '@mui/material/ListItemText';
import HomeIcon from '@mui/icons-material/Home';
import AnalyticsIcon from '@mui/icons-material/Analytics';
import Divider from '@mui/material/Divider';
import Avatar from '@mui/material/Avatar';

const DRAWER_WIDTH = 240;

// Permanent drawer for desktop
const Drawer = styled(MuiDrawer)({
  width: DRAWER_WIDTH,
  flexShrink: 0,
  boxSizing: 'border-box',
  [`& .${drawerClasses.paper}`]: {
    width: DRAWER_WIDTH,
    boxSizing: 'border-box',
  },
});

interface NavItem {
  text: string;
  icon: React.ReactNode;
  path: string;
}

const navItems: NavItem[] = [
  { text: 'Home', icon: <HomeIcon />, path: '/' },
  { text: 'Analytics', icon: <AnalyticsIcon />, path: '/analytics' },
];

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const [mobileOpen, setMobileOpen] = React.useState(false);

  const sidebarContent = (
    <Stack sx={{ height: '100%', justifyContent: 'space-between' }}>
      <List dense>
        {navItems.map((item) => (
          <ListItem key={item.text} disablePadding>
            <ListItemButton>
              <ListItemIcon>{item.icon}</ListItemIcon>
              <ListItemText primary={item.text} />
            </ListItemButton>
          </ListItem>
        ))}
      </List>
      <Stack direction="row" sx={{ p: 2, gap: 1, alignItems: 'center', borderTop: '1px solid', borderColor: 'divider' }}>
        <Avatar sx={{ width: 36, height: 36 }} alt="User" />
        <Typography variant="body2" sx={{ fontWeight: 500 }}>User Name</Typography>
      </Stack>
    </Stack>
  );

  return (
    <Box sx={{ display: 'flex' }}>
      <CssBaseline />
      {/* Mobile AppBar - visible only on xs */}
      <AppBar
        position="fixed"
        sx={{
          display: { xs: 'block', md: 'none' },
          boxShadow: 0,
          bgcolor: 'background.paper',
          borderBottom: '1px solid',
          borderColor: 'divider',
        }}
      >
        <Toolbar>
          <IconButton
            edge="start"
            aria-label="open navigation"
            onClick={() => setMobileOpen(true)}
          >
            <MenuIcon />
          </IconButton>
          <Typography variant="h6" sx={{ color: 'text.primary' }}>Dashboard</Typography>
        </Toolbar>
      </AppBar>

      {/* Mobile drawer - temporary, slides in from left */}
      <MuiDrawer
        variant="temporary"
        open={mobileOpen}
        onClose={() => setMobileOpen(false)}
        sx={{ display: { xs: 'block', md: 'none' } }}
        slotProps={{ paper: { sx: { width: DRAWER_WIDTH } } }}
      >
        {sidebarContent}
      </MuiDrawer>

      {/* Desktop drawer - permanent, always visible */}
      <Drawer
        variant="permanent"
        sx={{
          display: { xs: 'none', md: 'block' },
          [`& .${drawerClasses.paper}`]: { backgroundColor: 'background.paper' },
        }}
      >
        {sidebarContent}
      </Drawer>

      {/* Main content area */}
      <Box component="main" sx={{ flexGrow: 1, overflow: 'auto' }}>
        <Stack spacing={2} sx={{ mx: 3, pb: 5, mt: { xs: 8, md: 0 } }}>
          {children}
        </Stack>
      </Box>
    </Box>
  );
}
```

**Key points:**
- Use `display: { xs: 'none', md: 'block' }` to toggle between mobile/desktop navs.
- Permanent drawer on desktop, temporary on mobile.
- Main content uses `flexGrow: 1` and `overflow: auto`.
- Mobile content gets `mt: { xs: 8, md: 0 }` to clear the fixed AppBar.

**Accessibility:** The hamburger button needs `aria-label="open navigation"`. The drawer should trap focus when open on mobile.

---

### Marketing / Landing Page Layout

A marketing page uses a floating AppBar with backdrop blur, sections stacked vertically, and a footer. The AppBar collapses to a hamburger menu on mobile.

```tsx
import * as React from 'react';
import { styled, alpha } from '@mui/material/styles';
import AppBar from '@mui/material/AppBar';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Container from '@mui/material/Container';
import CssBaseline from '@mui/material/CssBaseline';
import Divider from '@mui/material/Divider';
import Drawer from '@mui/material/Drawer';
import IconButton from '@mui/material/IconButton';
import MenuItem from '@mui/material/MenuItem';
import Stack from '@mui/material/Stack';
import Toolbar from '@mui/material/Toolbar';
import Typography from '@mui/material/Typography';
import MenuIcon from '@mui/icons-material/Menu';
import CloseIcon from '@mui/icons-material/Close';

const StyledToolbar = styled(Toolbar)(({ theme }) => ({
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  borderRadius: `calc(${theme.shape.borderRadius}px + 8px)`,
  backdropFilter: 'blur(24px)',
  border: '1px solid',
  borderColor: (theme.vars || theme).palette.divider,
  backgroundColor: theme.vars
    ? `rgba(${theme.vars.palette.background.defaultChannel} / 0.4)`
    : alpha(theme.palette.background.default, 0.4),
  boxShadow: (theme.vars || theme).shadows[1],
  padding: '8px 12px',
}));

const navLinks = ['Features', 'Pricing', 'Testimonials', 'FAQ'];

export default function MarketingPage() {
  const [drawerOpen, setDrawerOpen] = React.useState(false);

  return (
    <>
      <CssBaseline />
      <AppBar
        position="fixed"
        sx={{ boxShadow: 0, bgcolor: 'transparent', backgroundImage: 'none', mt: '28px' }}
      >
        <Container maxWidth="lg">
          <StyledToolbar variant="dense" disableGutters>
            {/* Logo + desktop nav */}
            <Box sx={{ flexGrow: 1, display: 'flex', alignItems: 'center' }}>
              <Typography variant="h6" sx={{ mr: 2 }}>Logo</Typography>
              <Box sx={{ display: { xs: 'none', md: 'flex' } }}>
                {navLinks.map((link) => (
                  <Button key={link} variant="text" color="info" size="small">
                    {link}
                  </Button>
                ))}
              </Box>
            </Box>

            {/* Desktop auth buttons */}
            <Box sx={{ display: { xs: 'none', md: 'flex' }, gap: 1 }}>
              <Button variant="text" size="small">Sign in</Button>
              <Button variant="contained" size="small">Sign up</Button>
            </Box>

            {/* Mobile hamburger */}
            <Box sx={{ display: { xs: 'flex', md: 'none' } }}>
              <IconButton aria-label="Menu" onClick={() => setDrawerOpen(true)}>
                <MenuIcon />
              </IconButton>
              <Drawer
                anchor="top"
                open={drawerOpen}
                onClose={() => setDrawerOpen(false)}
              >
                <Box sx={{ p: 2, backgroundColor: 'background.default' }}>
                  <Box sx={{ display: 'flex', justifyContent: 'flex-end' }}>
                    <IconButton onClick={() => setDrawerOpen(false)}>
                      <CloseIcon />
                    </IconButton>
                  </Box>
                  {navLinks.map((link) => (
                    <MenuItem key={link}>{link}</MenuItem>
                  ))}
                  <Divider sx={{ my: 3 }} />
                  <MenuItem>
                    <Button variant="contained" fullWidth>Sign up</Button>
                  </MenuItem>
                  <MenuItem>
                    <Button variant="outlined" fullWidth>Sign in</Button>
                  </MenuItem>
                </Box>
              </Drawer>
            </Box>
          </StyledToolbar>
        </Container>
      </AppBar>

      {/* Hero section */}
      <Box sx={{ pt: { xs: 14, sm: 20 }, pb: { xs: 8, sm: 12 } }}>
        <Container>
          <Stack spacing={2} sx={{ alignItems: 'center' }}>
            <Typography variant="h1" sx={{ fontSize: 'clamp(3rem, 10vw, 3.5rem)', textAlign: 'center' }}>
              Your headline here
            </Typography>
            <Typography sx={{ textAlign: 'center', color: 'text.secondary', width: { sm: '100%', md: '80%' } }}>
              Subheadline describing your product value proposition.
            </Typography>
          </Stack>
        </Container>
      </Box>

      {/* Additional sections separated by Dividers */}
      <Divider />
      {/* <Features />, <Pricing />, <FAQ />, <Footer /> */}
    </>
  );
}
```

**Key points:**
- Transparent AppBar with `backdropFilter: 'blur(24px)'` for a frosted glass effect.
- Top-anchored Drawer for mobile menu.
- Use `Container maxWidth="lg"` for consistent section widths.
- Font sizing with `clamp()` for fluid responsive typography.

---

### Authentication Pages (Sign In / Sign Up)

A centered card on a full-viewport background. Uses `FormControl` + `FormLabel` + `TextField` pattern for accessible form fields.

```tsx
import * as React from 'react';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import MuiCard from '@mui/material/Card';
import Checkbox from '@mui/material/Checkbox';
import CssBaseline from '@mui/material/CssBaseline';
import Divider from '@mui/material/Divider';
import FormControl from '@mui/material/FormControl';
import FormControlLabel from '@mui/material/FormControlLabel';
import FormLabel from '@mui/material/FormLabel';
import Link from '@mui/material/Link';
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';
import { styled } from '@mui/material/styles';

const Card = styled(MuiCard)(({ theme }) => ({
  display: 'flex',
  flexDirection: 'column',
  alignSelf: 'center',
  width: '100%',
  padding: theme.spacing(4),
  gap: theme.spacing(2),
  margin: 'auto',
  [theme.breakpoints.up('sm')]: {
    maxWidth: '450px',
  },
  boxShadow:
    'hsla(220, 30%, 5%, 0.05) 0px 5px 15px 0px, hsla(220, 25%, 10%, 0.05) 0px 15px 35px -5px',
  ...theme.applyStyles('dark', {
    boxShadow:
      'hsla(220, 30%, 5%, 0.5) 0px 5px 15px 0px, hsla(220, 25%, 10%, 0.08) 0px 15px 35px -5px',
  }),
}));

const PageContainer = styled(Stack)(({ theme }) => ({
  height: '100dvh',
  minHeight: '100%',
  padding: theme.spacing(2),
  [theme.breakpoints.up('sm')]: {
    padding: theme.spacing(4),
  },
  '&::before': {
    content: '""',
    display: 'block',
    position: 'absolute',
    zIndex: -1,
    inset: 0,
    backgroundImage: 'radial-gradient(ellipse at 50% 50%, hsl(210, 100%, 97%), hsl(0, 0%, 100%))',
    backgroundRepeat: 'no-repeat',
    ...theme.applyStyles('dark', {
      backgroundImage: 'radial-gradient(at 50% 50%, hsla(210, 100%, 16%, 0.5), hsl(220, 30%, 5%))',
    }),
  },
}));

export default function SignIn() {
  const [emailError, setEmailError] = React.useState(false);
  const [emailErrorMessage, setEmailErrorMessage] = React.useState('');
  const [passwordError, setPasswordError] = React.useState(false);
  const [passwordErrorMessage, setPasswordErrorMessage] = React.useState('');

  const validateInputs = () => {
    const email = document.getElementById('email') as HTMLInputElement;
    const password = document.getElementById('password') as HTMLInputElement;
    let isValid = true;

    if (!email.value || !/\S+@\S+\.\S+/.test(email.value)) {
      setEmailError(true);
      setEmailErrorMessage('Please enter a valid email address.');
      isValid = false;
    } else {
      setEmailError(false);
      setEmailErrorMessage('');
    }

    if (!password.value || password.value.length < 6) {
      setPasswordError(true);
      setPasswordErrorMessage('Password must be at least 6 characters long.');
      isValid = false;
    } else {
      setPasswordError(false);
      setPasswordErrorMessage('');
    }
    return isValid;
  };

  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    if (emailError || passwordError) {
      event.preventDefault();
      return;
    }
    const data = new FormData(event.currentTarget);
    console.log({ email: data.get('email'), password: data.get('password') });
  };

  return (
    <>
      <CssBaseline />
      <PageContainer direction="column" justifyContent="space-between">
        <Card variant="outlined">
          <Typography component="h1" variant="h4" sx={{ fontSize: 'clamp(2rem, 10vw, 2.15rem)' }}>
            Sign in
          </Typography>
          <Box component="form" onSubmit={handleSubmit} noValidate sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <FormControl>
              <FormLabel htmlFor="email">Email</FormLabel>
              <TextField
                error={emailError}
                helperText={emailErrorMessage}
                id="email"
                type="email"
                name="email"
                placeholder="your@email.com"
                autoComplete="email"
                required
                fullWidth
                variant="outlined"
                color={emailError ? 'error' : 'primary'}
              />
            </FormControl>
            <FormControl>
              <FormLabel htmlFor="password">Password</FormLabel>
              <TextField
                error={passwordError}
                helperText={passwordErrorMessage}
                id="password"
                type="password"
                name="password"
                placeholder="******"
                autoComplete="current-password"
                required
                fullWidth
                variant="outlined"
                color={passwordError ? 'error' : 'primary'}
              />
            </FormControl>
            <FormControlLabel control={<Checkbox value="remember" color="primary" />} label="Remember me" />
            <Button type="submit" fullWidth variant="contained" onClick={validateInputs}>
              Sign in
            </Button>
          </Box>
          <Divider>or</Divider>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <Button fullWidth variant="outlined">Sign in with Google</Button>
            <Typography sx={{ textAlign: 'center' }}>
              Don't have an account? <Link href="/sign-up" variant="body2">Sign up</Link>
            </Typography>
          </Box>
        </Card>
      </PageContainer>
    </>
  );
}
```

**Key points:**
- Radial gradient background with dark mode support via `theme.applyStyles('dark', {...})`.
- Card centered with `margin: 'auto'` and max-width on `sm` breakpoint.
- `FormControl` + `FormLabel` provides accessible labeling separate from `TextField`.
- Use `100dvh` for full dynamic viewport height (accounts for mobile browser chrome).

**Accessibility:** Each field has `htmlFor`/`id` linking, error states use `helperText`, and color changes to `error` on invalid inputs.

---

### Checkout / Multi-Step Form Layout

A split-screen layout with order summary on the left and a stepper form on the right. On mobile, it stacks vertically.

```tsx
import * as React from 'react';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Grid from '@mui/material/Grid';
import Stack from '@mui/material/Stack';
import Step from '@mui/material/Step';
import StepLabel from '@mui/material/StepLabel';
import Stepper from '@mui/material/Stepper';
import Typography from '@mui/material/Typography';
import ChevronLeftIcon from '@mui/icons-material/ChevronLeft';
import ChevronRightIcon from '@mui/icons-material/ChevronRight';

const steps = ['Shipping address', 'Payment details', 'Review your order'];

function getStepContent(step: number) {
  switch (step) {
    case 0:
      return <Typography>Address form fields here</Typography>;
    case 1:
      return <Typography>Payment form fields here</Typography>;
    case 2:
      return <Typography>Order review here</Typography>;
    default:
      throw new Error('Unknown step');
  }
}

export default function CheckoutPage() {
  const [activeStep, setActiveStep] = React.useState(0);

  return (
    <Grid container sx={{ height: { sm: '100dvh' } }}>
      {/* Left panel - order summary (desktop only) */}
      <Grid
        size={{ xs: 12, md: 5, lg: 4 }}
        sx={{
          display: { xs: 'none', md: 'flex' },
          flexDirection: 'column',
          backgroundColor: 'background.paper',
          borderRight: '1px solid',
          borderColor: 'divider',
          pt: 16,
          px: 10,
          gap: 4,
        }}
      >
        <Typography variant="h6">Order Summary</Typography>
        {/* Order items listed here */}
      </Grid>

      {/* Right panel - stepper form */}
      <Grid
        size={{ xs: 12, md: 7, lg: 8 }}
        sx={{ display: 'flex', flexDirection: 'column', pt: { xs: 2, sm: 16 }, px: { xs: 2, sm: 10 }, gap: { xs: 4, md: 8 } }}
      >
        {/* Desktop stepper */}
        <Stepper activeStep={activeStep} sx={{ display: { xs: 'none', md: 'flex' }, width: '100%' }}>
          {steps.map((label) => (
            <Step key={label}>
              <StepLabel>{label}</StepLabel>
            </Step>
          ))}
        </Stepper>

        {/* Mobile stepper */}
        <Stepper activeStep={activeStep} alternativeLabel sx={{ display: { xs: 'flex', md: 'none' } }}>
          {steps.map((label) => (
            <Step key={label}>
              <StepLabel>{label}</StepLabel>
            </Step>
          ))}
        </Stepper>

        {/* Step content */}
        <Box sx={{ maxWidth: 600 }}>
          {activeStep === steps.length ? (
            <Stack spacing={2}>
              <Typography variant="h5">Thank you for your order!</Typography>
              <Button variant="contained" sx={{ width: { xs: '100%', sm: 'auto' } }}>
                Go to my orders
              </Button>
            </Stack>
          ) : (
            <>
              {getStepContent(activeStep)}
              <Box sx={{ display: 'flex', flexDirection: { xs: 'column-reverse', sm: 'row' }, justifyContent: activeStep !== 0 ? 'space-between' : 'flex-end', gap: 1, mt: 2 }}>
                {activeStep !== 0 && (
                  <Button startIcon={<ChevronLeftIcon />} onClick={() => setActiveStep((s) => s - 1)} variant="text">
                    Previous
                  </Button>
                )}
                <Button endIcon={<ChevronRightIcon />} onClick={() => setActiveStep((s) => s + 1)} variant="contained" sx={{ width: { xs: '100%', sm: 'fit-content' } }}>
                  {activeStep === steps.length - 1 ? 'Place order' : 'Next'}
                </Button>
              </Box>
            </>
          )}
        </Box>
      </Grid>
    </Grid>
  );
}
```

**Key points:**
- Split-screen layout with `Grid` container and responsive `size` props.
- Two steppers rendered -- one for desktop (`display: none` on xs) and one for mobile with `alternativeLabel`.
- Navigation buttons reverse column direction on mobile for better thumb reach.

---

### Blog / Article Layout

A content-focused layout with a responsive card grid. Featured articles get larger cards, secondary articles are smaller.

```tsx
import * as React from 'react';
import Box from '@mui/material/Box';
import Card from '@mui/material/Card';
import CardContent from '@mui/material/CardContent';
import CardMedia from '@mui/material/CardMedia';
import Chip from '@mui/material/Chip';
import Container from '@mui/material/Container';
import Grid from '@mui/material/Grid';
import Typography from '@mui/material/Typography';
import { styled } from '@mui/material/styles';

interface Article {
  title: string;
  description: string;
  image?: string;
  tag: string;
  author: string;
}

const StyledCard = styled(Card)(({ theme }) => ({
  display: 'flex',
  flexDirection: 'column',
  padding: 0,
  height: '100%',
  backgroundColor: (theme.vars || theme).palette.background.paper,
  '&:hover': {
    backgroundColor: 'transparent',
    cursor: 'pointer',
  },
  '&:focus-visible': {
    outline: '3px solid',
    outlineColor: 'hsla(210, 98%, 48%, 0.5)',
    outlineOffset: '2px',
  },
}));

const TruncatedText = styled(Typography)({
  display: '-webkit-box',
  WebkitBoxOrient: 'vertical',
  WebkitLineClamp: 2,
  overflow: 'hidden',
  textOverflow: 'ellipsis',
});

export default function BlogLayout({ articles }: { articles: Article[] }) {
  return (
    <Container maxWidth="lg" sx={{ py: { xs: 4, sm: 8 } }}>
      <Typography variant="h1" gutterBottom>Blog</Typography>
      <Typography sx={{ mb: 4 }}>Stay in the loop with the latest updates</Typography>

      {/* Category filters */}
      <Box sx={{ display: 'inline-flex', gap: 3, mb: 4, overflow: 'auto' }}>
        <Chip label="All categories" size="medium" clickable />
        <Chip label="Engineering" size="medium" variant="outlined" clickable />
        <Chip label="Product" size="medium" variant="outlined" clickable />
      </Box>

      {/* Card grid */}
      <Grid container spacing={2}>
        {/* Featured articles (2 columns on desktop) */}
        {articles.slice(0, 2).map((article, i) => (
          <Grid key={i} size={{ xs: 12, md: 6 }}>
            <StyledCard variant="outlined" tabIndex={0}>
              {article.image && (
                <CardMedia component="img" alt={article.title} image={article.image} sx={{ aspectRatio: '16 / 9', borderBottom: '1px solid', borderColor: 'divider' }} />
              )}
              <CardContent sx={{ flexGrow: 1 }}>
                <Typography variant="caption">{article.tag}</Typography>
                <Typography variant="h6" gutterBottom>{article.title}</Typography>
                <TruncatedText variant="body2" color="text.secondary">
                  {article.description}
                </TruncatedText>
              </CardContent>
            </StyledCard>
          </Grid>
        ))}

        {/* Secondary articles (3 columns on desktop) */}
        {articles.slice(2).map((article, i) => (
          <Grid key={i} size={{ xs: 12, md: 4 }}>
            <StyledCard variant="outlined" tabIndex={0} sx={{ height: '100%' }}>
              {article.image && (
                <CardMedia component="img" alt={article.title} image={article.image} sx={{ height: { sm: 'auto', md: '50%' }, aspectRatio: { sm: '16 / 9', md: '' } }} />
              )}
              <CardContent sx={{ flexGrow: 1 }}>
                <Typography variant="caption">{article.tag}</Typography>
                <Typography variant="h6" gutterBottom>{article.title}</Typography>
                <TruncatedText variant="body2" color="text.secondary">
                  {article.description}
                </TruncatedText>
              </CardContent>
            </StyledCard>
          </Grid>
        ))}
      </Grid>
    </Container>
  );
}
```

**Key points:**
- Featured articles span 6 columns each (half-width), secondary articles span 4 (third-width).
- Use `-webkit-line-clamp` for text truncation.
- Cards are focusable (`tabIndex={0}`) with `focus-visible` outline for keyboard navigation.
- `aspectRatio: '16 / 9'` on CardMedia for consistent image sizing.

---

### Pricing Page Section

A data-driven pricing grid with a highlighted "recommended" tier.

```tsx
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Card from '@mui/material/Card';
import CardActions from '@mui/material/CardActions';
import CardContent from '@mui/material/CardContent';
import Chip from '@mui/material/Chip';
import Container from '@mui/material/Container';
import Divider from '@mui/material/Divider';
import Grid from '@mui/material/Grid';
import Typography from '@mui/material/Typography';
import CheckCircleIcon from '@mui/icons-material/CheckCircleRounded';
import AutoAwesomeIcon from '@mui/icons-material/AutoAwesome';

interface Tier {
  title: string;
  price: string;
  description: string[];
  buttonText: string;
  buttonVariant: 'outlined' | 'contained';
  highlighted?: boolean;
}

const tiers: Tier[] = [
  { title: 'Free', price: '0', description: ['10 users', '2 GB storage', 'Email support'], buttonText: 'Sign up free', buttonVariant: 'outlined' },
  { title: 'Pro', price: '15', description: ['50 users', '10 GB storage', 'Priority support', 'Analytics'], buttonText: 'Start now', buttonVariant: 'contained', highlighted: true },
  { title: 'Enterprise', price: '30', description: ['Unlimited users', '30 GB storage', 'Phone support'], buttonText: 'Contact us', buttonVariant: 'outlined' },
];

export default function PricingSection() {
  return (
    <Container sx={{ py: { xs: 4, sm: 12 }, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: { xs: 3, sm: 6 } }}>
      <Typography component="h2" variant="h4" sx={{ textAlign: 'center' }}>Pricing</Typography>
      <Grid container spacing={3} sx={{ alignItems: 'center', justifyContent: 'center' }}>
        {tiers.map((tier) => (
          <Grid key={tier.title} size={{ xs: 12, sm: 6, md: 4 }}>
            <Card
              sx={[
                { p: 2, display: 'flex', flexDirection: 'column', gap: 4 },
                tier.highlighted && ((theme) => ({
                  border: 'none',
                  background: 'radial-gradient(circle at 50% 0%, hsl(220, 20%, 35%), hsl(220, 30%, 6%))',
                  boxShadow: '0 8px 12px hsla(220, 20%, 42%, 0.2)',
                  ...theme.applyStyles('dark', {
                    background: 'radial-gradient(circle at 50% 0%, hsl(220, 20%, 20%), hsl(220, 30%, 16%))',
                  }),
                })),
              ]}
            >
              <CardContent>
                <Box sx={{ mb: 1, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <Typography component="h3" variant="h6" sx={tier.highlighted ? { color: 'grey.100' } : undefined}>
                    {tier.title}
                  </Typography>
                  {tier.highlighted && <Chip icon={<AutoAwesomeIcon />} label="Recommended" />}
                </Box>
                <Box sx={{ display: 'flex', alignItems: 'baseline', ...(tier.highlighted ? { color: 'grey.50' } : {}) }}>
                  <Typography variant="h2">${tier.price}</Typography>
                  <Typography variant="h6">&nbsp;/ month</Typography>
                </Box>
                <Divider sx={{ my: 2 }} />
                {tier.description.map((line) => (
                  <Box key={line} sx={{ py: 1, display: 'flex', gap: 1.5, alignItems: 'center' }}>
                    <CheckCircleIcon sx={{ width: 20, color: tier.highlighted ? 'primary.light' : 'primary.main' }} />
                    <Typography variant="subtitle2" sx={tier.highlighted ? { color: 'grey.50' } : undefined}>
                      {line}
                    </Typography>
                  </Box>
                ))}
              </CardContent>
              <CardActions>
                <Button fullWidth variant={tier.buttonVariant}>{tier.buttonText}</Button>
              </CardActions>
            </Card>
          </Grid>
        ))}
      </Grid>
    </Container>
  );
}
```

**Key points:**
- Highlighted tier uses a radial gradient background with dark mode variant.
- Use the `sx` array syntax `sx={[baseStyles, conditionalStyles]}` for conditional styling.
- Data-driven: define tiers as an array and map over them.

---

### Footer

A responsive footer with newsletter signup, link columns, social icons, and copyright.

```tsx
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Container from '@mui/material/Container';
import IconButton from '@mui/material/IconButton';
import InputLabel from '@mui/material/InputLabel';
import Link from '@mui/material/Link';
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';
import GitHubIcon from '@mui/icons-material/GitHub';
import LinkedInIcon from '@mui/icons-material/LinkedIn';
import TwitterIcon from '@mui/icons-material/X';

const linkColumns = [
  { title: 'Product', links: ['Features', 'Pricing', 'FAQ'] },
  { title: 'Company', links: ['About', 'Careers', 'Press'] },
  { title: 'Legal', links: ['Terms', 'Privacy', 'Contact'] },
];

export default function Footer() {
  return (
    <Container sx={{ display: 'flex', flexDirection: 'column', gap: { xs: 4, sm: 8 }, py: { xs: 8, sm: 10 } }}>
      <Box sx={{ display: 'flex', flexDirection: { xs: 'column', sm: 'row' }, width: '100%', justifyContent: 'space-between' }}>
        {/* Newsletter */}
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: { xs: '100%', sm: '60%' } }}>
          <Box sx={{ width: { xs: '100%', sm: '60%' } }}>
            <Typography variant="body2" sx={{ fontWeight: 600, mt: 2 }}>Join the newsletter</Typography>
            <Typography variant="body2" sx={{ color: 'text.secondary', mb: 2 }}>
              Subscribe for weekly updates.
            </Typography>
            <InputLabel htmlFor="email-newsletter">Email</InputLabel>
            <Stack direction="row" spacing={1} useFlexGap>
              <TextField id="email-newsletter" hiddenLabel size="small" variant="outlined" fullWidth placeholder="Your email" sx={{ width: '250px' }} slotProps={{ htmlInput: { 'aria-label': 'Enter your email' } }} />
              <Button variant="contained" size="small" sx={{ flexShrink: 0 }}>Subscribe</Button>
            </Stack>
          </Box>
        </Box>

        {/* Link columns - hidden on mobile */}
        {linkColumns.map((col) => (
          <Box key={col.title} sx={{ display: { xs: 'none', sm: 'flex' }, flexDirection: 'column', gap: 1 }}>
            <Typography variant="body2" sx={{ fontWeight: 'medium' }}>{col.title}</Typography>
            {col.links.map((link) => (
              <Link key={link} color="text.secondary" variant="body2" href="#">{link}</Link>
            ))}
          </Box>
        ))}
      </Box>

      {/* Bottom bar */}
      <Box sx={{ display: 'flex', justifyContent: 'space-between', pt: { xs: 4, sm: 8 }, borderTop: '1px solid', borderColor: 'divider' }}>
        <div>
          <Link color="text.secondary" variant="body2" href="#">Privacy Policy</Link>
          <Typography sx={{ display: 'inline', mx: 0.5, opacity: 0.5 }}>&bull;</Typography>
          <Link color="text.secondary" variant="body2" href="#">Terms of Service</Link>
        </div>
        <Stack direction="row" spacing={1} sx={{ color: 'text.secondary' }}>
          <IconButton color="inherit" size="small" aria-label="GitHub"><GitHubIcon /></IconButton>
          <IconButton color="inherit" size="small" aria-label="X"><TwitterIcon /></IconButton>
          <IconButton color="inherit" size="small" aria-label="LinkedIn"><LinkedInIcon /></IconButton>
        </Stack>
      </Box>
    </Container>
  );
}
```

---

## Common UI Patterns

### Responsive Navigation (AppBar with Mobile Drawer)

See the [Dashboard Layout](#dashboard-layout-appbar--drawer--main-content) pattern above for the full implementation. The key technique:

```tsx
// Desktop: permanent sidebar
<Drawer variant="permanent" sx={{ display: { xs: 'none', md: 'block' } }}>
  {navContent}
</Drawer>

// Mobile: fixed AppBar with hamburger that opens temporary drawer
<AppBar sx={{ display: { xs: 'block', md: 'none' } }}>
  <Toolbar>
    <IconButton aria-label="open navigation" onClick={() => setOpen(true)}>
      <MenuIcon />
    </IconButton>
  </Toolbar>
</AppBar>
<Drawer variant="temporary" open={open} onClose={() => setOpen(false)} sx={{ display: { xs: 'block', md: 'none' } }}>
  {navContent}
</Drawer>
```

For the marketing page variant (no sidebar, top drawer), use `anchor="top"` on the Drawer and a transparent, floating AppBar.

---

### Data Table with Sorting, Selection, and Pagination

A fully-featured table with column sorting, row selection via checkboxes, and pagination.

```tsx
import * as React from 'react';
import { alpha } from '@mui/material/styles';
import Box from '@mui/material/Box';
import Checkbox from '@mui/material/Checkbox';
import IconButton from '@mui/material/IconButton';
import Paper from '@mui/material/Paper';
import Table from '@mui/material/Table';
import TableBody from '@mui/material/TableBody';
import TableCell from '@mui/material/TableCell';
import TableContainer from '@mui/material/TableContainer';
import TableHead from '@mui/material/TableHead';
import TablePagination from '@mui/material/TablePagination';
import TableRow from '@mui/material/TableRow';
import TableSortLabel from '@mui/material/TableSortLabel';
import Toolbar from '@mui/material/Toolbar';
import Tooltip from '@mui/material/Tooltip';
import Typography from '@mui/material/Typography';
import DeleteIcon from '@mui/icons-material/Delete';
import FilterListIcon from '@mui/icons-material/FilterList';
import { visuallyHidden } from '@mui/utils';

interface Data {
  id: number;
  name: string;
  email: string;
  role: string;
}

type Order = 'asc' | 'desc';

interface HeadCell {
  id: keyof Data;
  label: string;
  numeric: boolean;
}

const headCells: readonly HeadCell[] = [
  { id: 'name', numeric: false, label: 'Name' },
  { id: 'email', numeric: false, label: 'Email' },
  { id: 'role', numeric: false, label: 'Role' },
];

function descendingComparator<T>(a: T, b: T, orderBy: keyof T) {
  if (b[orderBy] < a[orderBy]) return -1;
  if (b[orderBy] > a[orderBy]) return 1;
  return 0;
}

function getComparator<Key extends keyof any>(order: Order, orderBy: Key) {
  return order === 'desc'
    ? (a: { [key in Key]: number | string }, b: { [key in Key]: number | string }) => descendingComparator(a, b, orderBy)
    : (a: { [key in Key]: number | string }, b: { [key in Key]: number | string }) => -descendingComparator(a, b, orderBy);
}

// Table head with sort labels
function EnhancedTableHead({
  numSelected, rowCount, order, orderBy, onSelectAllClick, onRequestSort,
}: {
  numSelected: number; rowCount: number; order: Order; orderBy: string;
  onSelectAllClick: (e: React.ChangeEvent<HTMLInputElement>) => void;
  onRequestSort: (e: React.MouseEvent, property: keyof Data) => void;
}) {
  return (
    <TableHead>
      <TableRow>
        <TableCell padding="checkbox">
          <Checkbox
            color="primary"
            indeterminate={numSelected > 0 && numSelected < rowCount}
            checked={rowCount > 0 && numSelected === rowCount}
            onChange={onSelectAllClick}
            slotProps={{ input: { 'aria-label': 'select all' } }}
          />
        </TableCell>
        {headCells.map((cell) => (
          <TableCell key={cell.id} align={cell.numeric ? 'right' : 'left'} sortDirection={orderBy === cell.id ? order : false}>
            <TableSortLabel active={orderBy === cell.id} direction={orderBy === cell.id ? order : 'asc'} onClick={(e) => onRequestSort(e, cell.id)}>
              {cell.label}
              {orderBy === cell.id ? (
                <Box component="span" sx={visuallyHidden}>
                  {order === 'desc' ? 'sorted descending' : 'sorted ascending'}
                </Box>
              ) : null}
            </TableSortLabel>
          </TableCell>
        ))}
      </TableRow>
    </TableHead>
  );
}

// Toolbar changes appearance when items are selected
function EnhancedTableToolbar({ numSelected }: { numSelected: number }) {
  return (
    <Toolbar sx={[{ pl: { sm: 2 }, pr: { xs: 1, sm: 1 } }, numSelected > 0 && { bgcolor: (theme) => alpha(theme.palette.primary.main, theme.palette.action.activatedOpacity) }]}>
      {numSelected > 0 ? (
        <Typography sx={{ flex: '1 1 100%' }} color="inherit" variant="subtitle1">{numSelected} selected</Typography>
      ) : (
        <Typography sx={{ flex: '1 1 100%' }} variant="h6">Users</Typography>
      )}
      {numSelected > 0 ? (
        <Tooltip title="Delete"><IconButton><DeleteIcon /></IconButton></Tooltip>
      ) : (
        <Tooltip title="Filter list"><IconButton><FilterListIcon /></IconButton></Tooltip>
      )}
    </Toolbar>
  );
}

export default function EnhancedTable({ rows }: { rows: Data[] }) {
  const [order, setOrder] = React.useState<Order>('asc');
  const [orderBy, setOrderBy] = React.useState<keyof Data>('name');
  const [selected, setSelected] = React.useState<readonly number[]>([]);
  const [page, setPage] = React.useState(0);
  const [rowsPerPage, setRowsPerPage] = React.useState(5);

  const handleRequestSort = (_: React.MouseEvent, property: keyof Data) => {
    const isAsc = orderBy === property && order === 'asc';
    setOrder(isAsc ? 'desc' : 'asc');
    setOrderBy(property);
  };

  const handleSelectAllClick = (event: React.ChangeEvent<HTMLInputElement>) => {
    if (event.target.checked) { setSelected(rows.map((n) => n.id)); return; }
    setSelected([]);
  };

  const handleClick = (_: React.MouseEvent, id: number) => {
    const selectedIndex = selected.indexOf(id);
    let newSelected: readonly number[] = [];
    if (selectedIndex === -1) newSelected = [...selected, id];
    else if (selectedIndex === 0) newSelected = selected.slice(1);
    else if (selectedIndex === selected.length - 1) newSelected = selected.slice(0, -1);
    else newSelected = [...selected.slice(0, selectedIndex), ...selected.slice(selectedIndex + 1)];
    setSelected(newSelected);
  };

  const visibleRows = React.useMemo(
    () => [...rows].sort(getComparator(order, orderBy)).slice(page * rowsPerPage, page * rowsPerPage + rowsPerPage),
    [order, orderBy, page, rowsPerPage, rows],
  );

  return (
    <Paper sx={{ width: '100%' }}>
      <EnhancedTableToolbar numSelected={selected.length} />
      <TableContainer>
        <Table sx={{ minWidth: 750 }} aria-labelledby="tableTitle">
          <EnhancedTableHead numSelected={selected.length} rowCount={rows.length} order={order} orderBy={orderBy} onSelectAllClick={handleSelectAllClick} onRequestSort={handleRequestSort} />
          <TableBody>
            {visibleRows.map((row) => {
              const isSelected = selected.includes(row.id);
              return (
                <TableRow hover onClick={(e) => handleClick(e, row.id)} role="checkbox" aria-checked={isSelected} tabIndex={-1} key={row.id} selected={isSelected} sx={{ cursor: 'pointer' }}>
                  <TableCell padding="checkbox">
                    <Checkbox color="primary" checked={isSelected} slotProps={{ input: { 'aria-labelledby': `row-${row.id}` } }} />
                  </TableCell>
                  <TableCell component="th" id={`row-${row.id}`} scope="row">{row.name}</TableCell>
                  <TableCell>{row.email}</TableCell>
                  <TableCell>{row.role}</TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </TableContainer>
      <TablePagination rowsPerPageOptions={[5, 10, 25]} component="div" count={rows.length} rowsPerPage={rowsPerPage} page={page} onPageChange={(_, p) => setPage(p)} onRowsPerPageChange={(e) => { setRowsPerPage(parseInt(e.target.value, 10)); setPage(0); }} />
    </Paper>
  );
}
```

**Key points:**
- `TableSortLabel` with visually hidden sort direction text for screen readers.
- `useMemo` for sorted + paginated rows to avoid re-sorting on every render.
- Toolbar background changes when items are selected using `alpha()`.
- Checkbox `indeterminate` state when only some rows are selected.

**Accessibility:** Each row has `role="checkbox"` and `aria-checked`. The select-all checkbox uses `indeterminate`. Sort labels include visually hidden text for screen readers.

---

### Form Layouts

#### Single-Column Form

```tsx
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import FormControl from '@mui/material/FormControl';
import FormLabel from '@mui/material/FormLabel';
import TextField from '@mui/material/TextField';

export default function SingleColumnForm() {
  return (
    <Box component="form" noValidate sx={{ display: 'flex', flexDirection: 'column', gap: 2, maxWidth: 450 }}>
      <FormControl>
        <FormLabel htmlFor="name">Name</FormLabel>
        <TextField id="name" name="name" required fullWidth variant="outlined" />
      </FormControl>
      <FormControl>
        <FormLabel htmlFor="email">Email</FormLabel>
        <TextField id="email" name="email" type="email" required fullWidth variant="outlined" />
      </FormControl>
      <FormControl>
        <FormLabel htmlFor="message">Message</FormLabel>
        <TextField id="message" name="message" multiline rows={4} required fullWidth variant="outlined" />
      </FormControl>
      <Button type="submit" variant="contained">Submit</Button>
    </Box>
  );
}
```

#### Multi-Column Form with Grid

```tsx
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Checkbox from '@mui/material/Checkbox';
import FormControl from '@mui/material/FormControl';
import FormControlLabel from '@mui/material/FormControlLabel';
import FormHelperText from '@mui/material/FormHelperText';
import Grid from '@mui/material/Grid';
import InputLabel from '@mui/material/InputLabel';
import MenuItem from '@mui/material/MenuItem';
import Select from '@mui/material/Select';
import TextField from '@mui/material/TextField';

export default function MultiColumnForm() {
  return (
    <Box component="form" noValidate>
      <Grid container spacing={2} sx={{ mb: 2 }}>
        <Grid size={{ xs: 12, sm: 6 }}>
          <TextField label="First Name" name="firstName" required fullWidth />
        </Grid>
        <Grid size={{ xs: 12, sm: 6 }}>
          <TextField label="Last Name" name="lastName" required fullWidth />
        </Grid>
        <Grid size={{ xs: 12, sm: 6 }}>
          <TextField label="Email" name="email" type="email" required fullWidth />
        </Grid>
        <Grid size={{ xs: 12, sm: 6 }}>
          <FormControl fullWidth>
            <InputLabel id="role-label">Role</InputLabel>
            <Select labelId="role-label" name="role" label="Role" defaultValue="">
              <MenuItem value="dev">Developer</MenuItem>
              <MenuItem value="design">Designer</MenuItem>
              <MenuItem value="pm">Product Manager</MenuItem>
            </Select>
            <FormHelperText>Select your department role</FormHelperText>
          </FormControl>
        </Grid>
        <Grid size={{ xs: 12 }}>
          <FormControlLabel control={<Checkbox name="agree" />} label="I agree to the terms" />
        </Grid>
      </Grid>
      <Button type="submit" variant="contained" size="large">Submit</Button>
    </Box>
  );
}
```

**Key points:**
- MUI v6 Grid uses `size={{ xs: 12, sm: 6 }}` instead of `xs={12} sm={6}` props.
- `FormControl` + `InputLabel` + `Select` + `FormHelperText` is the proper Select composition.
- Always link labels to inputs via `htmlFor`/`id` or `labelId`.

---

### Stepper Form (Multi-Step Wizard)

```tsx
import * as React from 'react';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Step from '@mui/material/Step';
import StepLabel from '@mui/material/StepLabel';
import Stepper from '@mui/material/Stepper';
import Typography from '@mui/material/Typography';

const steps = ['Account details', 'Personal info', 'Confirmation'];

export default function StepperForm() {
  const [activeStep, setActiveStep] = React.useState(0);
  const [skipped, setSkipped] = React.useState(new Set<number>());

  const isStepOptional = (step: number) => step === 1;
  const isStepSkipped = (step: number) => skipped.has(step);

  const handleNext = () => {
    let newSkipped = skipped;
    if (isStepSkipped(activeStep)) {
      newSkipped = new Set(newSkipped.values());
      newSkipped.delete(activeStep);
    }
    setActiveStep((prev) => prev + 1);
    setSkipped(newSkipped);
  };

  const handleBack = () => setActiveStep((prev) => prev - 1);

  const handleSkip = () => {
    if (!isStepOptional(activeStep)) throw new Error("Can't skip non-optional step.");
    setActiveStep((prev) => prev + 1);
    setSkipped((prev) => { const s = new Set(prev.values()); s.add(activeStep); return s; });
  };

  return (
    <Box sx={{ width: '100%' }}>
      <Stepper activeStep={activeStep}>
        {steps.map((label, index) => (
          <Step key={label} completed={isStepSkipped(index) ? false : undefined}>
            <StepLabel optional={isStepOptional(index) ? <Typography variant="caption">Optional</Typography> : undefined}>
              {label}
            </StepLabel>
          </Step>
        ))}
      </Stepper>
      {activeStep === steps.length ? (
        <Typography sx={{ mt: 2 }}>All steps completed</Typography>
      ) : (
        <>
          <Typography sx={{ mt: 2, mb: 1 }}>Step {activeStep + 1} content</Typography>
          <Box sx={{ display: 'flex', pt: 2 }}>
            <Button disabled={activeStep === 0} onClick={handleBack} sx={{ mr: 1 }}>Back</Button>
            <Box sx={{ flex: '1 1 auto' }} />
            {isStepOptional(activeStep) && (
              <Button color="inherit" onClick={handleSkip} sx={{ mr: 1 }}>Skip</Button>
            )}
            <Button onClick={handleNext} variant="contained">
              {activeStep === steps.length - 1 ? 'Finish' : 'Next'}
            </Button>
          </Box>
        </>
      )}
    </Box>
  );
}
```

---

### Responsive Card Grid

A responsive grid of product or content cards using the Grid component.

```tsx
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Card from '@mui/material/Card';
import CardActions from '@mui/material/CardActions';
import CardContent from '@mui/material/CardContent';
import CardMedia from '@mui/material/CardMedia';
import Grid from '@mui/material/Grid';
import Typography from '@mui/material/Typography';

interface Product {
  id: string;
  title: string;
  description: string;
  image: string;
  price: string;
}

export default function ProductGrid({ products }: { products: Product[] }) {
  return (
    <Grid container spacing={3}>
      {products.map((product) => (
        <Grid key={product.id} size={{ xs: 12, sm: 6, md: 4, lg: 3 }}>
          <Card sx={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
            <CardMedia component="img" alt={product.title} height="200" image={product.image} />
            <CardContent sx={{ flexGrow: 1 }}>
              <Typography gutterBottom variant="h6">{product.title}</Typography>
              <Typography variant="body2" color="text.secondary">{product.description}</Typography>
              <Typography variant="h6" sx={{ mt: 2 }}>{product.price}</Typography>
            </CardContent>
            <CardActions>
              <Button size="small">Add to Cart</Button>
              <Button size="small">Details</Button>
            </CardActions>
          </Card>
        </Grid>
      ))}
    </Grid>
  );
}
```

**Key points:**
- Use `height: '100%'` and `flexDirection: 'column'` on Card so all cards in a row are the same height.
- `flexGrow: 1` on CardContent pushes CardActions to the bottom.
- Breakpoints: 1 column on mobile, 2 on sm, 3 on md, 4 on lg.

---

### Modal Dialogs

#### Confirmation Dialog

```tsx
import * as React from 'react';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogActions from '@mui/material/DialogActions';
import DialogContent from '@mui/material/DialogContent';
import DialogContentText from '@mui/material/DialogContentText';
import DialogTitle from '@mui/material/DialogTitle';

interface ConfirmDialogProps {
  open: boolean;
  title: string;
  message: string;
  onConfirm: () => void;
  onCancel: () => void;
}

export default function ConfirmDialog({ open, title, message, onConfirm, onCancel }: ConfirmDialogProps) {
  return (
    <Dialog open={open} onClose={onCancel} aria-labelledby="confirm-dialog-title" aria-describedby="confirm-dialog-description">
      <DialogTitle id="confirm-dialog-title">{title}</DialogTitle>
      <DialogContent>
        <DialogContentText id="confirm-dialog-description">{message}</DialogContentText>
      </DialogContent>
      <DialogActions>
        <Button onClick={onCancel}>Cancel</Button>
        <Button onClick={onConfirm} autoFocus variant="contained" color="error">Delete</Button>
      </DialogActions>
    </Dialog>
  );
}
```

**Accessibility:** Use `aria-labelledby` and `aria-describedby` linking to `DialogTitle` and `DialogContentText` `id` attributes.

#### Form Dialog

```tsx
import * as React from 'react';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogActions from '@mui/material/DialogActions';
import DialogContent from '@mui/material/DialogContent';
import DialogContentText from '@mui/material/DialogContentText';
import DialogTitle from '@mui/material/DialogTitle';
import TextField from '@mui/material/TextField';

export default function FormDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    const data = Object.fromEntries(formData.entries());
    console.log(data);
    onClose();
  };

  return (
    <Dialog open={open} onClose={onClose}>
      <DialogTitle>Subscribe</DialogTitle>
      <DialogContent>
        <DialogContentText>Enter your email to subscribe to updates.</DialogContentText>
        <form onSubmit={handleSubmit} id="subscribe-form">
          <TextField autoFocus required margin="dense" id="email" name="email" label="Email Address" type="email" fullWidth variant="standard" />
        </form>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button type="submit" form="subscribe-form">Subscribe</Button>
      </DialogActions>
    </Dialog>
  );
}
```

**Key points:** Use a `form` element with an `id` inside `DialogContent`, then reference it with `form="subscribe-form"` on the submit button in `DialogActions`. This lets the button live outside the `<form>` tag.

#### Full-Screen Dialog

```tsx
import * as React from 'react';
import AppBar from '@mui/material/AppBar';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import IconButton from '@mui/material/IconButton';
import Slide from '@mui/material/Slide';
import Toolbar from '@mui/material/Toolbar';
import Typography from '@mui/material/Typography';
import CloseIcon from '@mui/icons-material/Close';
import { TransitionProps } from '@mui/material/transitions';

const Transition = React.forwardRef(function Transition(
  props: TransitionProps & { children: React.ReactElement<unknown> },
  ref: React.Ref<unknown>,
) {
  return <Slide direction="up" ref={ref} {...props} />;
});

export default function FullScreenDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  return (
    <Dialog fullScreen open={open} onClose={onClose} slots={{ transition: Transition }}>
      <AppBar sx={{ position: 'relative' }}>
        <Toolbar>
          <IconButton edge="start" color="inherit" onClick={onClose} aria-label="close">
            <CloseIcon />
          </IconButton>
          <Typography sx={{ ml: 2, flex: 1 }} variant="h6">Title</Typography>
          <Button autoFocus color="inherit" onClick={onClose}>Save</Button>
        </Toolbar>
      </AppBar>
      {/* Full-screen content here */}
    </Dialog>
  );
}
```

**Key points:**
- Use `slots={{ transition: Transition }}` (MUI v6+) instead of `TransitionComponent`.
- The slide transition animates from bottom.
- The AppBar inside the dialog uses `position: 'relative'` (not fixed/sticky).

---

### Search with Input Adornment

```tsx
import FormControl from '@mui/material/FormControl';
import InputAdornment from '@mui/material/InputAdornment';
import OutlinedInput from '@mui/material/OutlinedInput';
import SearchIcon from '@mui/icons-material/SearchRounded';

export default function SearchBar() {
  return (
    <FormControl sx={{ width: { xs: '100%', md: '25ch' } }} variant="outlined">
      <OutlinedInput
        size="small"
        placeholder="Search..."
        startAdornment={
          <InputAdornment position="start" sx={{ color: 'text.primary' }}>
            <SearchIcon fontSize="small" />
          </InputAdornment>
        }
        inputProps={{ 'aria-label': 'search' }}
      />
    </FormControl>
  );
}
```

---

### Notification System (Snackbar)

```tsx
import * as React from 'react';
import Alert, { AlertColor } from '@mui/material/Alert';
import Snackbar from '@mui/material/Snackbar';

interface Notification {
  message: string;
  severity: AlertColor;
}

const NotificationContext = React.createContext<{
  show: (message: string, severity?: AlertColor) => void;
}>({ show: () => {} });

export function useNotification() {
  return React.useContext(NotificationContext);
}

export function NotificationProvider({ children }: { children: React.ReactNode }) {
  const [notification, setNotification] = React.useState<Notification | null>(null);

  const show = React.useCallback((message: string, severity: AlertColor = 'info') => {
    setNotification({ message, severity });
  }, []);

  const handleClose = (_?: React.SyntheticEvent | Event, reason?: string) => {
    if (reason === 'clickaway') return;
    setNotification(null);
  };

  return (
    <NotificationContext.Provider value={{ show }}>
      {children}
      <Snackbar open={!!notification} autoHideDuration={4000} onClose={handleClose} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
        {notification ? (
          <Alert onClose={handleClose} severity={notification.severity} variant="filled" sx={{ width: '100%' }}>
            {notification.message}
          </Alert>
        ) : undefined}
      </Snackbar>
    </NotificationContext.Provider>
  );
}
```

**Usage:**
```tsx
const { show } = useNotification();
show('Item saved successfully!', 'success');
show('Something went wrong.', 'error');
```

**Key points:**
- Wrap your app with `NotificationProvider`.
- Snackbar uses `anchorOrigin` to position on screen.
- Ignore `clickaway` reason to prevent accidental dismissal.
- Combine `Snackbar` with `Alert` for colored severity indicators.

---

### Loading States and Skeletons

Use `Skeleton` as a placeholder while content loads. Match the skeleton shape to your content.

```tsx
import Box from '@mui/material/Box';
import Card from '@mui/material/Card';
import CardContent from '@mui/material/CardContent';
import Skeleton from '@mui/material/Skeleton';
import Typography from '@mui/material/Typography';

interface ContentCardProps {
  loading?: boolean;
  title?: string;
  description?: string;
  image?: string;
}

export default function ContentCard({ loading, title, description, image }: ContentCardProps) {
  return (
    <Card sx={{ maxWidth: 345 }}>
      {loading ? (
        <Skeleton variant="rectangular" width="100%" height={140} />
      ) : (
        <Box component="img" src={image} alt={title} sx={{ width: '100%', height: 140, objectFit: 'cover' }} />
      )}
      <CardContent>
        {loading ? (
          <>
            <Skeleton variant="text" sx={{ fontSize: '1.25rem' }} />
            <Skeleton variant="text" width="80%" />
            <Skeleton variant="text" width="60%" />
          </>
        ) : (
          <>
            <Typography variant="h6">{title}</Typography>
            <Typography variant="body2" color="text.secondary">{description}</Typography>
          </>
        )}
      </CardContent>
    </Card>
  );
}
```

**Skeleton variants:**
- `text` -- matches text line height, full width by default
- `rectangular` -- for images, banners, media
- `circular` -- for avatars
- `rounded` -- rectangular with rounded corners

---

### Empty State

```tsx
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Typography from '@mui/material/Typography';
import InboxIcon from '@mui/icons-material/InboxRounded';

export default function EmptyState({ title, description, actionLabel, onAction }: {
  title: string; description: string; actionLabel?: string; onAction?: () => void;
}) {
  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', py: 8, gap: 2, color: 'text.secondary' }}>
      <InboxIcon sx={{ fontSize: 64, opacity: 0.5 }} />
      <Typography variant="h6" color="text.primary">{title}</Typography>
      <Typography variant="body2" sx={{ textAlign: 'center', maxWidth: 400 }}>{description}</Typography>
      {actionLabel && onAction && (
        <Button variant="contained" onClick={onAction} sx={{ mt: 2 }}>{actionLabel}</Button>
      )}
    </Box>
  );
}
```

---

## Component Composition Patterns

### List Composition (List + ListItem + ListItemButton + ListItemIcon + ListItemText)

```tsx
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemIcon from '@mui/material/ListItemIcon';
import ListItemText from '@mui/material/ListItemText';
import Divider from '@mui/material/Divider';
import HomeIcon from '@mui/icons-material/Home';
import SettingsIcon from '@mui/icons-material/Settings';

interface NavItem {
  text: string;
  icon: React.ReactNode;
  selected?: boolean;
  onClick?: () => void;
}

export default function NavList({ items, secondaryItems }: { items: NavItem[]; secondaryItems?: NavItem[] }) {
  return (
    <>
      <List dense>
        {items.map((item) => (
          <ListItem key={item.text} disablePadding>
            <ListItemButton selected={item.selected} onClick={item.onClick}>
              <ListItemIcon>{item.icon}</ListItemIcon>
              <ListItemText primary={item.text} />
            </ListItemButton>
          </ListItem>
        ))}
      </List>
      {secondaryItems && (
        <>
          <Divider />
          <List dense>
            {secondaryItems.map((item) => (
              <ListItem key={item.text} disablePadding>
                <ListItemButton onClick={item.onClick}>
                  <ListItemIcon>{item.icon}</ListItemIcon>
                  <ListItemText primary={item.text} />
                </ListItemButton>
              </ListItem>
            ))}
          </List>
        </>
      )}
    </>
  );
}
```

**Key points:**
- Use `ListItemButton` (not deprecated `ListItem button` prop) for clickable items.
- `disablePadding` on `ListItem` when using `ListItemButton` inside it.
- `dense` prop on `List` for compact nav menus.
- `selected` prop on `ListItemButton` highlights the active item.

---

### Form Field Composition (FormControl + InputLabel + Select + FormHelperText)

```tsx
import FormControl from '@mui/material/FormControl';
import FormHelperText from '@mui/material/FormHelperText';
import InputLabel from '@mui/material/InputLabel';
import MenuItem from '@mui/material/MenuItem';
import Select, { SelectChangeEvent } from '@mui/material/Select';

export default function SelectField({
  label, name, value, options, error, helperText, onChange,
}: {
  label: string; name: string; value: string; error?: boolean; helperText?: string;
  options: { value: string; label: string }[];
  onChange: (event: SelectChangeEvent) => void;
}) {
  const labelId = `${name}-label`;
  return (
    <FormControl fullWidth error={error}>
      <InputLabel id={labelId}>{label}</InputLabel>
      <Select labelId={labelId} name={name} value={value} label={label} onChange={onChange}>
        {options.map((opt) => (
          <MenuItem key={opt.value} value={opt.value}>{opt.label}</MenuItem>
        ))}
      </Select>
      {helperText && <FormHelperText>{helperText}</FormHelperText>}
    </FormControl>
  );
}
```

**Key points:**
- `InputLabel` gets a `labelId`, `Select` references it via `labelId`.
- Pass `label` to `Select` so the outlined variant properly notches the label.
- `error` prop on `FormControl` cascades to all child components.

---

### Dialog Composition (Dialog + DialogTitle + DialogContent + DialogActions)

```
Dialog
  DialogTitle        -- heading text, gets aria-labelledby linking
  DialogContent      -- scrollable body area
    DialogContentText -- descriptive text, gets aria-describedby linking
    (form fields, content)
  DialogActions      -- action buttons (Cancel, Submit, etc.)
```

Always provide `aria-labelledby` and `aria-describedby` linking the Dialog to its title and description `id` attributes:

```tsx
<Dialog open={open} onClose={onClose} aria-labelledby="dialog-title" aria-describedby="dialog-desc">
  <DialogTitle id="dialog-title">Edit Profile</DialogTitle>
  <DialogContent>
    <DialogContentText id="dialog-desc">Update your profile information.</DialogContentText>
    {/* form fields */}
  </DialogContent>
  <DialogActions>
    <Button onClick={onClose}>Cancel</Button>
    <Button variant="contained">Save</Button>
  </DialogActions>
</Dialog>
```

---

### Card Composition (Card + CardMedia + CardContent + CardActions)

```
Card
  CardMedia          -- image or video (use component="img" with alt text)
  CardContent        -- text content area
  CardActions        -- action buttons at the bottom
```

For equal-height cards in a grid, use `height: '100%'` on Card and `flexGrow: 1` on CardContent:

```tsx
<Card sx={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
  <CardMedia component="img" alt="description" height="200" image="/image.jpg" />
  <CardContent sx={{ flexGrow: 1 }}>
    <Typography variant="h6">Title</Typography>
    <Typography variant="body2" color="text.secondary">Description</Typography>
  </CardContent>
  <CardActions>
    <Button size="small">Action</Button>
  </CardActions>
</Card>
```

---

### Table Composition

```
TableContainer (wraps for horizontal scroll)
  Table
    TableHead
      TableRow
        TableCell (use TableSortLabel inside for sortable columns)
    TableBody
      TableRow (use hover, selected, onClick for interactive rows)
        TableCell (use component="th" scope="row" for first cell)
  TablePagination (placed outside Table, inside Paper)
```

See the [Data Table](#data-table-with-sorting-selection-and-pagination) pattern above for the full implementation.

---

## Performance Patterns

### Virtualized Lists

For long lists (hundreds or thousands of items), use virtualization to render only visible items. Use `react-window` or similar with MUI components:

```tsx
import * as React from 'react';
import { FixedSizeList, ListChildComponentProps } from 'react-window';
import ListItem from '@mui/material/ListItem';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';

function renderRow(props: ListChildComponentProps) {
  const { index, style } = props;
  return (
    <ListItem style={style} key={index} component="div" disablePadding>
      <ListItemButton>
        <ListItemText primary={`Item ${index + 1}`} />
      </ListItemButton>
    </ListItem>
  );
}

export default function VirtualizedList({ itemCount = 1000 }: { itemCount?: number }) {
  return (
    <FixedSizeList height={400} width="100%" itemSize={46} itemCount={itemCount} overscanCount={5}>
      {renderRow}
    </FixedSizeList>
  );
}
```

**Key points:**
- Install `react-window` separately (`npm install react-window @types/react-window`).
- Use `overscanCount` to render extra items above/below viewport for smoother scrolling.
- For variable height items, use `VariableSizeList` instead.

---

### Lazy Loading with Skeleton

Show skeleton placeholders while components or data load asynchronously:

```tsx
import * as React from 'react';
import Grid from '@mui/material/Grid';
import Skeleton from '@mui/material/Skeleton';
import Card from '@mui/material/Card';
import CardContent from '@mui/material/CardContent';

function SkeletonCard() {
  return (
    <Card>
      <Skeleton variant="rectangular" height={200} />
      <CardContent>
        <Skeleton variant="text" sx={{ fontSize: '1.5rem' }} />
        <Skeleton variant="text" width="80%" />
        <Skeleton variant="text" width="60%" />
      </CardContent>
    </Card>
  );
}

export default function LazyCardGrid({ loading, children }: { loading: boolean; children: React.ReactNode }) {
  if (loading) {
    return (
      <Grid container spacing={3}>
        {Array.from({ length: 6 }).map((_, i) => (
          <Grid key={i} size={{ xs: 12, sm: 6, md: 4 }}>
            <SkeletonCard />
          </Grid>
        ))}
      </Grid>
    );
  }
  return <>{children}</>;
}
```

---

### Memoization with MUI Components

Avoid unnecessary re-renders of styled components and heavy component trees:

```tsx
import * as React from 'react';
import { styled } from '@mui/material/styles';
import Card from '@mui/material/Card';
import CardContent from '@mui/material/CardContent';
import Typography from '@mui/material/Typography';

// Define styled components outside the render function (module scope)
// This prevents re-creating the styled component on every render
const StyledCard = styled(Card)(({ theme }) => ({
  padding: theme.spacing(2),
  '&:hover': { boxShadow: theme.shadows[4] },
}));

// Memoize expensive child components
const ExpensiveContent = React.memo(function ExpensiveContent({ data }: { data: string[] }) {
  return (
    <CardContent>
      {data.map((item, i) => (
        <Typography key={i} variant="body2">{item}</Typography>
      ))}
    </CardContent>
  );
});

// Memoize sx objects that are defined inline to prevent re-renders
export default function OptimizedCard({ data }: { data: string[] }) {
  // Stable sx reference -- only create once
  const containerSx = React.useMemo(() => ({
    display: 'flex',
    gap: 2,
    flexDirection: 'column' as const,
  }), []);

  return (
    <StyledCard sx={containerSx}>
      <ExpensiveContent data={data} />
    </StyledCard>
  );
}
```

**Key points:**
- Define `styled()` components at module scope, not inside render functions.
- Use `React.memo` for child components that receive stable props.
- Memoize `sx` objects with `useMemo` if they contain computed values and the component re-renders frequently.
- For static `sx` objects (object literals with no computed values), React's reconciliation handles them efficiently without memoization in most cases.
