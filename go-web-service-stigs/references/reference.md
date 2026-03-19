# Reference: Go Implementation Patterns and Evidence Artifacts

Detailed Go code patterns, evidence guidance, and configuration references for DISA STIG compliance. Each section is tagged with the STIG controls it satisfies.

## TLS Configuration (STIG-Compliant)

**Controls:** V-206439, V-206440, SRG-APP-000014-API-000020, SRG-APP-000439-API-001010

### Full server configuration (TLS-App)

```go
import (
    "crypto/tls"
    "net/http"
    "time"
)

func newServer(handler http.Handler) *http.Server {
    return &http.Server{
        Addr:    ":8443",
        Handler: handler,
        TLSConfig: &tls.Config{
            // NIST SP 800-52 Rev 2: TLS 1.2 minimum; TLS 1.3 support required
            MinVersion: tls.VersionTLS12,

            // NIST SP 800-52 Rev 2 required cipher suites (TLS 1.2)
            // TLS 1.3 suites are not configurable in Go. In non-FIPS mode,
            // Go also negotiates TLS_CHACHA20_POLY1305_SHA256 (not NIST-approved).
            // Enable GODEBUG=fips140=on to restrict to approved suites only.
            CipherSuites: []uint16{
                tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
                tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
                tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
                tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
            },

            // FIPS-approved NIST curves
            CurvePreferences: []tls.CurveID{
                tls.CurveP384,
                tls.CurveP256,
            },
        },
        // Slowloris defense: ReadHeaderTimeout is critical
        ReadHeaderTimeout: 5 * time.Second,
        ReadTimeout:       15 * time.Second,
        WriteTimeout:      15 * time.Second,
        IdleTimeout:       60 * time.Second,
        MaxHeaderBytes:    1 << 20, // 1 MB
    }
}
```

### Outbound client TLS hardening

```go
client := &http.Client{
    Timeout: 30 * time.Second,
    Transport: &http.Transport{
        TLSClientConfig: &tls.Config{
            MinVersion: tls.VersionTLS12,
            // Never set InsecureSkipVerify: true in production
        },
        TLSHandshakeTimeout:   10 * time.Second,
        ResponseHeaderTimeout: 10 * time.Second,
    },
}
```

### FIPS TLS behavior

When `GODEBUG=fips140=on` is set, `crypto/tls` automatically restricts to FIPS-approved cipher suites, protocol versions, signature algorithms, and key exchange mechanisms. The explicit cipher suite list above is defense-in-depth and documents intent for auditors.

**Note**: `tls.Config.PreferServerCipherSuites` is deprecated and ignored by Go. Do not rely on it for compliance. Go automatically selects the best mutually supported cipher suite based on hardware and security properties.

### Evidence artifacts for TLS

- TLS configuration source code showing `MinVersion` and cipher suite settings
- Gateway/LB TLS policy export (if TLS-Edge)
- TLS scan results (e.g., `testssl.sh` or `sslyze` output) showing enabled/disabled versions and suites
- Network diagram showing trust boundaries and TLS termination points
- Proof that no plaintext listener is exposed beyond localhost

---

## Trusted Proxy and Client IP Extraction

**Controls:** V-206362 (log source of events), V-206363 (log client IP, not proxy IP), SRG-APP-000095-API-001795

```go
import (
    "net"
    "net/http"
    "strings"
)

// trustedProxyCIDRs must contain ONLY the specific CIDRs of your
// ingress controllers or load balancers — NOT broad RFC 1918 ranges.
// Using broad ranges (e.g., 10.0.0.0/8) allows any host on the
// private network to forge X-Forwarded-For and spoof client IPs,
// defeating audit source-IP accuracy (V-206362, V-206363) and
// IP-based rate limiting.
//
// Populate from deployment config (env vars, config file, or
// service discovery) — these are examples only.
var trustedProxyCIDRs []*net.IPNet

func init() {
    // Replace with your actual ingress/gateway CIDRs
    ingressCIDRs := []string{
        "10.0.1.0/24",   // example: ingress controller subnet
        "10.0.2.10/32",  // example: specific load balancer IP
    }
    for _, cidr := range ingressCIDRs {
        _, network, err := net.ParseCIDR(cidr)
        if err != nil {
            panic("invalid trusted proxy CIDR: " + cidr)
        }
        trustedProxyCIDRs = append(trustedProxyCIDRs, network)
    }
}

func clientIP(r *http.Request) string {
    host, _, err := net.SplitHostPort(r.RemoteAddr)
    if err != nil {
        return r.RemoteAddr
    }
    remoteIP := net.ParseIP(host)
    if remoteIP == nil {
        return host
    }

    // Only trust X-Forwarded-For if the immediate sender is a trusted proxy
    trusted := false
    for _, cidr := range trustedProxyCIDRs {
        if cidr.Contains(remoteIP) {
            trusted = true
            break
        }
    }
    if !trusted {
        return host
    }

    // Walk X-Forwarded-For from right to left, skip trusted proxies
    xff := r.Header.Get("X-Forwarded-For")
    if xff == "" {
        return host
    }
    parts := strings.Split(xff, ",")
    for i := len(parts) - 1; i >= 0; i-- {
        ip := strings.TrimSpace(parts[i])
        parsed := net.ParseIP(ip)
        if parsed == nil {
            continue
        }
        isTrusted := false
        for _, cidr := range trustedProxyCIDRs {
            if cidr.Contains(parsed) {
                isTrusted = true
                break
            }
        }
        if !isTrusted {
            return ip
        }
    }
    return host
}
```

---

## Audit Logging

**Controls:** V-206357, V-206360 (when), V-206361 (where), V-206362 (source), V-206363 (client IP behind proxy), V-206364 (outcome), V-206365 (identity), V-206366 (alert on log failure), V-222444, SRG-APP-000095-API-001745/1765/1775/1785/1795

### Structured audit event

```go
type AuditEvent struct {
    Timestamp   time.Time `json:"ts"`
    RequestID   string    `json:"rid"`
    Actor       string    `json:"actor"`
    ActorType   string    `json:"actor_type"` // "user", "service", "apikey"
    Action      string    `json:"action"`
    Method      string    `json:"method"`
    Path        string    `json:"path"`
    Status      int       `json:"status"`
    Success     bool      `json:"success"`
    SourceIP    string    `json:"src_ip"`
    Component   string    `json:"component"` // handler/module name
    DurationMS  int64     `json:"dur_ms"`
    ErrorClass  string    `json:"err_class,omitempty"`
    TraceID     string    `json:"trace_id,omitempty"`
}
```

### Request logging middleware

```go
func auditMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        rid := r.Header.Get("X-Request-Id")
        if rid == "" {
            rid = generateRequestID() // use crypto/rand or UUID
        }
        ctx := context.WithValue(r.Context(), ctxKeyRequestID, rid)
        r = r.WithContext(ctx)

        start := time.Now()
        rw := &statusWriter{ResponseWriter: w, status: 200}
        next.ServeHTTP(rw, r)

        ev := AuditEvent{
            Timestamp:  start.UTC(),
            RequestID:  rid,
            Actor:      actorFromContext(ctx), // extracted by auth middleware
            Method:     r.Method,
            Path:       r.URL.Path,
            Status:     rw.status,
            Success:    rw.status < 400,
            SourceIP:   clientIP(r),
            DurationMS: time.Since(start).Milliseconds(),
        }
        emitAudit(ev)
    })
}

type statusWriter struct {
    http.ResponseWriter
    status int
}

func (w *statusWriter) WriteHeader(code int) {
    w.status = code
    w.ResponseWriter.WriteHeader(code)
}
```

### Header redaction (sensitive data protection)

Use an allowlist — only copy headers known to be safe for logging. A denylist approach risks leaking secrets in custom or nonstandard headers.

```go
// safeHeaders returns only explicitly approved headers for audit logging.
// Allowlist approach: headers not listed here are excluded entirely.
// This prevents leaking secrets in custom auth headers (V-222444).
var loggableHeaders = map[string]bool{
    "accept":           true,
    "accept-encoding":  true,
    "accept-language":  true,
    "cache-control":    true,
    "content-length":   true,
    "content-type":     true,
    "host":             true,
    "origin":           true,
    "referer":          true,
    "user-agent":       true,
    "x-forwarded-for":  true,
    "x-forwarded-proto": true,
    "x-request-id":     true,
}

func safeHeaders(h http.Header) map[string][]string {
    out := make(map[string][]string)
    for k, v := range h {
        if loggableHeaders[strings.ToLower(k)] {
            out[k] = v
        }
    }
    return out
}
```

### Log protection requirements

- Restrict log file access to privileged users only (V-206368).
- Protect logs from unauthorized modification (V-206369).
- Protect logs from unauthorized deletion (V-206370).
- Back up logs to a separate system or media (V-206371).
- Ship logs to a central SIEM/log aggregation system (V-206423).
- Alert ISSO and SA when log storage reaches 75% capacity (V-206424).
- Alert ISSO and SA on logging processing failures (V-206366).
- Evidence: SIEM integration configuration, log pipeline architecture, access control policies, alert configurations.

---

## Error Handling

**Controls:** V-222585, V-222600, SRG-APP-000266-API-000535, V-206413

### Central error response pattern

```go
type apiError struct {
    Status  int    // HTTP status code
    Code    string // stable error code for clients
    Message string // safe for external consumption
    Err     error  // internal only, never sent to client
}

func writeError(w http.ResponseWriter, r *http.Request, e apiError) {
    rid, _ := r.Context().Value(ctxKeyRequestID).(string)

    // Internal log: full detail with correlation ID
    slog.Error("request error",
        "rid", rid,
        "code", e.Code,
        "status", e.Status,
        "err", e.Err,
    )

    // Client response: generic, no internals
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(e.Status)
    json.NewEncoder(w).Encode(map[string]any{
        "error": map[string]any{
            "code":       e.Code,
            "message":    e.Message,
            "request_id": rid,
        },
    })
}
```

### Fail-secure startup pattern

```go
func main() {
    // Fail closed: if security preconditions are not met, do not start serving
    if err := loadTLSCerts(); err != nil {
        log.Fatalf("TLS cert load failed: %v", err)
    }
    if err := initPolicyEngine(); err != nil {
        log.Fatalf("policy engine init failed: %v", err)
    }
    if err := verifyFIPSMode(); err != nil {
        log.Fatalf("FIPS verification failed: %v", err)
    }

    // Only start accepting traffic after all checks pass
    srv := newServer(handler)
    log.Fatal(srv.ListenAndServeTLS(certFile, keyFile))
}

func verifyFIPSMode() error {
    if os.Getenv("REQUIRE_FIPS") == "true" {
        if !fips140.Enabled() {
            return fmt.Errorf("FIPS mode required but not enabled")
        }
    }
    return nil
}
```

---

## Session Management

**Controls:** V-206352, V-206398, V-206414, V-206415, V-206431, V-222577, V-222581, V-222582, V-222603

### Cookie configuration

```go
func setSessionCookie(w http.ResponseWriter, sessionID string) {
    http.SetCookie(w, &http.Cookie{
        Name:     "sid",
        Value:    sessionID,                // server-generated only
        Path:     "/",
        Secure:   true,                     // require HTTPS (V-206435)
        HttpOnly: true,                     // prevent script access (V-206438)
        SameSite: http.SameSiteLaxMode,     // CSRF mitigation
        MaxAge:   28800,                    // 8 hours absolute max (V-206414)
    })
}
```

### Session ID generation

```go
import "crypto/rand"

func generateSessionID() (string, error) {
    b := make([]byte, 32) // 256-bit entropy (V-206431)
    if _, err := rand.Read(b); err != nil {
        return "", fmt.Errorf("session ID generation failed: %w", err)
    }
    return base64.RawURLEncoding.EncodeToString(b), nil
}
```

### Session lifecycle checklist

- Generate session IDs server-side with `crypto/rand`. Never accept client-provided IDs (V-206398).
- Rotate session ID on successful authentication (V-222582).
- Invalidate session on logout. Clear server-side session state (V-222578).
- Enforce absolute timeout of 8 hours or less (V-206414).
- Enforce inactivity timeout (V-206415). Typical: 5-20 minutes depending on risk level.
- Never embed session IDs in URLs (V-222581).
- Never log session IDs (V-222577, V-222444).

---

## Input Validation

**Controls:** SRG-APP-000447-API-001030/1035, V-222604, V-222605, V-206411

### Validation helpers

```go
import (
    "fmt"
    "regexp"
    "strconv"
)

// Enforce integer within bounds
func requireIntRange(name, v string, min, max int) (int, error) {
    n, err := strconv.Atoi(v)
    if err != nil || n < min || n > max {
        return 0, fmt.Errorf("%s: must be integer between %d and %d", name, min, max)
    }
    return n, nil
}

// Enforce safe identifier pattern
var safeIDPattern = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,64}$`)

func requireSafeID(name, v string) error {
    if !safeIDPattern.MatchString(v) {
        return fmt.Errorf("%s: invalid identifier", name)
    }
    return nil
}

// Request body size limit
func limitBody(next http.Handler, maxBytes int64) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
        next.ServeHTTP(w, r)
    })
}
```

### Parameterized queries (SQL injection prevention)

```go
// PostgreSQL with positional parameters
row := db.QueryRowContext(ctx,
    `SELECT email FROM users WHERE id = $1 AND tenant_id = $2`,
    userID, tenantID,
)

// MySQL with ? placeholders
rows, err := db.QueryContext(ctx,
    `SELECT name FROM items WHERE category = ? AND status = ? LIMIT ?`,
    category, "active", pageSize,
)
```

**Code review flags for SQL injection:**
- `fmt.Sprintf` or `+` concatenation building SQL strings
- `gorm.Raw()` or `sqlx.Get` with hand-built query strings
- Dynamic table/column names from user input (use allowlists)

### Command injection prevention

```go
// If external tool execution is required, use fixed binary + strict args
cmd := exec.CommandContext(ctx, "/usr/bin/safe-tool", "--mode", "status")
cmd.Env = []string{"PATH=/usr/bin"} // control environment
out, err := cmd.CombinedOutput()
```

Never pass user input to `sh -c`, `bash -c`, or `cmd.exe /C`. Never construct the executable path from user input.

---

## Rate Limiting

**Controls:** SRG-APP-000247-API-000520/000870, SRG-APP-000095-API-001750

### Token bucket middleware

```go
import (
    "math"
    "net/http"
    "sync"
    "time"
)

// WARNING: This in-memory limiter is a developer reference only.
// In multi-replica deployments (Kubernetes, etc.), in-memory limiters
// do not enforce policy globally across instances.
// For production compliance, enforce rate limiting at the API gateway
// or use a shared store (Redis, Envoy, etc.).
type rateLimiter struct {
    mu         sync.Mutex
    buckets    map[string]*bucket
    rate       float64
    burst      float64
    maxBuckets int // cap to prevent memory exhaustion from high-cardinality keys
}

type bucket struct {
    tokens float64
    last   time.Time
}

func newRateLimiter(ratePerSec, burst float64, maxBuckets int) *rateLimiter {
    return &rateLimiter{
        buckets:    make(map[string]*bucket),
        rate:       ratePerSec,
        burst:      burst,
        maxBuckets: maxBuckets,
    }
}

// evictStalest removes the bucket with the oldest last-access time.
// Called under lock when bucket count reaches maxBuckets.
func (rl *rateLimiter) evictStalest() {
    var oldestKey string
    var oldestTime time.Time
    first := true
    for k, b := range rl.buckets {
        if first || b.last.Before(oldestTime) {
            oldestKey = k
            oldestTime = b.last
            first = false
        }
    }
    if !first {
        delete(rl.buckets, oldestKey)
    }
}

func (rl *rateLimiter) allow(key string) bool {
    rl.mu.Lock()
    defer rl.mu.Unlock()

    if rl.buckets == nil {
        rl.buckets = make(map[string]*bucket)
    }

    b, ok := rl.buckets[key]
    if !ok {
        if rl.maxBuckets > 0 && len(rl.buckets) >= rl.maxBuckets {
            rl.evictStalest()
        }
        b = &bucket{tokens: rl.burst, last: time.Now()}
        rl.buckets[key] = b
    }

    now := time.Now()
    elapsed := now.Sub(b.last).Seconds()
    b.last = now
    b.tokens = math.Min(rl.burst, b.tokens+elapsed*rl.rate)

    if b.tokens < 1 {
        return false
    }
    b.tokens--
    return true
}

func (rl *rateLimiter) middleware(keyFunc func(*http.Request) string) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            key := keyFunc(r)
            if !rl.allow(key) {
                // Emit audit event for rate-limit enforcement (API SRG requirement)
                emitRateLimitEvent(r, key)
                http.Error(w, `{"error":{"code":"rate_limited","message":"too many requests"}}`,
                    http.StatusTooManyRequests)
                return
            }
            next.ServeHTTP(w, r)
        })
    }
}
```

**Client identification strategies** (choose one consistently per API SRG):
- API key ID (hashed, not the raw key)
- Token subject (`sub` claim)
- Client IP (only when identity-based identification is not available)

---

## Token Validation

**Controls:** SRG-APP-000400-API-000850/855/860/865, SRG-APP-000441-API-001020, V-222530

### JWT validation checklist

```go
// Claims embeds RegisteredClaims for standard field validation.
type Claims struct {
    jwt.RegisteredClaims
    Scope string `json:"scope"`
}

func (c *Claims) HasScope(required string) bool {
    for _, s := range strings.Fields(c.Scope) {
        if s == required {
            return true
        }
    }
    return false
}

// keyFunc returns the public key for signature verification.
// In production, load keys from a JWKS endpoint and cache them.
func keyFunc(token *jwt.Token) (any, error) {
    // Verify signing method matches expectations (defense-in-depth
    // alongside WithValidMethods)
    switch token.Method.Alg() {
    case "RS256":
        return rsaPublicKey, nil
    case "ES256":
        return ecdsaPublicKey, nil
    default:
        return nil, fmt.Errorf("unexpected signing method: %s", token.Method.Alg())
    }
}

func validateToken(r *http.Request) (*Claims, error) {
    tokenStr := extractBearerToken(r)
    if tokenStr == "" {
        return nil, errors.New("missing bearer token")
    }

    // ParseWithClaims: second arg is a claims instance for typed
    // deserialization; third arg is the keyfunc for signature
    // verification; remaining args are parser options.
    token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, keyFunc,
        jwt.WithValidMethods([]string{"RS256", "ES256"}),
        jwt.WithIssuer(expectedIssuer),
        jwt.WithAudience(thisAPIAudience),
        jwt.WithExpirationRequired(),
    )
    if err != nil {
        return nil, fmt.Errorf("token validation failed: %w", err)
    }

    claims, ok := token.Claims.(*Claims)
    if !ok {
        return nil, errors.New("unexpected claims type")
    }

    // Enforce max token age if organizational policy requires it
    if claims.IssuedAt != nil {
        age := time.Since(claims.IssuedAt.Time)
        if age > maxTokenAge {
            return nil, errors.New("token exceeds maximum age")
        }
    }

    return claims, nil
}
```

**Anti-replay for privileged flows (V-222530):**
- Use short-lived tokens for privileged sessions
- Implement refresh token rotation (single-use refresh tokens)
- Include nonce/jti claim and track used values for sensitive operations
- Use idempotency keys for state-changing privileged operations

---

## API Key Management

**Controls:** SRG-APP-000224-API-000475, SRG-APP-000231-API-000490, SRG-APP-000915-API-001610

### Key generation (CSPRNG)

```go
import "crypto/rand"

func generateAPIKey() (keyID, rawKey string, err error) {
    // Key ID: short, loggable identifier
    idBytes := make([]byte, 8)
    if _, err := rand.Read(idBytes); err != nil {
        return "", "", err
    }
    keyID = hex.EncodeToString(idBytes)

    // Raw key: high entropy, given to client once
    keyBytes := make([]byte, 32) // 256-bit
    if _, err := rand.Read(keyBytes); err != nil {
        return "", "", err
    }
    rawKey = base64.RawURLEncoding.EncodeToString(keyBytes)

    return keyID, rawKey, nil
}
```

### Key storage (hashed only)

```go
import "crypto/sha256"

type StoredKey struct {
    KeyID      string    `json:"key_id"`
    KeyHash    []byte    `json:"key_hash"`    // SHA-256 of raw key
    Scopes     []string  `json:"scopes"`      // allowed operations
    AllowedIPs []string  `json:"allowed_ips"` // IP restrictions
    ExpiresAt  time.Time `json:"expires_at"`
    RevokedAt  *time.Time `json:"revoked_at,omitempty"`
}

func hashKey(rawKey string) []byte {
    h := sha256.Sum256([]byte(rawKey))
    return h[:]
}
```

---

## CORS Configuration

**Controls:** SRG-APP-000251-API-000525

```go
func corsMiddleware(allowedOrigins map[string]bool) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            origin := r.Header.Get("Origin")
            if origin != "" && allowedOrigins[origin] {
                w.Header().Set("Access-Control-Allow-Origin", origin)
                w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
                w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
                w.Header().Set("Access-Control-Max-Age", "86400")
                w.Header().Set("Access-Control-Allow-Credentials", "true")
                w.Header().Set("Vary", "Origin")
            }
            if r.Method == http.MethodOptions {
                w.WriteHeader(http.StatusNoContent)
                return
            }
            next.ServeHTTP(w, r)
        })
    }
}
```

**Configuration per environment:**
```go
var corsOrigins = map[string]map[string]bool{
    "production":  {"https://app.example.mil": true},
    "staging":     {"https://staging.example.mil": true},
    "development": {"http://localhost:3000": true},
}
```

---

## HTTP Security Headers

**Controls:** V-206439 (HSTS), V-206413 (information leakage), general hardening

```go
func securityHeaders(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        // HSTS: enforce HTTPS with 2-year max-age
        w.Header().Set("Strict-Transport-Security",
            "max-age=63072000; includeSubDomains; preload")

        // Prevent MIME-type sniffing
        w.Header().Set("X-Content-Type-Options", "nosniff")

        // Prevent clickjacking
        w.Header().Set("X-Frame-Options", "DENY")

        // Content Security Policy (adjust per application needs)
        w.Header().Set("Content-Security-Policy",
            "default-src 'self'; frame-ancestors 'none'")

        // Referrer policy
        w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")

        // Disable caching for sensitive API responses
        w.Header().Set("Cache-Control", "no-store")

        // Permissions policy
        w.Header().Set("Permissions-Policy",
            "geolocation=(), camera=(), microphone=()")

        next.ServeHTTP(w, r)
    })
}
```

These headers may be set at the application level or at an upstream proxy/ingress. Verify the deployment architecture before flagging their absence in Go code.

---

## FIPS Configuration Walkthrough

**Controls:** SRG-APP-000224-API-000475, SRG-APP-000630-API-001375

### Step 1: Verify Go version

```bash
go version  # must be Go 1.24 or later
```

### Step 2: Build with FIPS module

```bash
GOFIPS140=v1.0.0 go build -o myapp .
```

### Step 3: Enable FIPS at runtime

Option A: environment variable
```bash
GODEBUG=fips140=on ./myapp
```

Option B: pin in `go.mod`
```
go 1.24
godebug fips140=on
```

### Step 4: Verify FIPS is active

```go
import "crypto/fips140"

func init() {
    if !fips140.Enabled() {
        panic("FIPS 140-3 mode is not enabled")
    }
}
```

### Step 5: Collect evidence

- Build logs showing `GOFIPS140=v1.0.0`
- Runtime logs showing FIPS mode enabled
- Go version used (`go version`)
- CMVP validation status reference (CAVP certificate A6650, check NIST MIP for current CMVP status)

### Platform support

FIPS mode (`GODEBUG=fips140=on/only`) is not supported on all platforms. Unsupported platforms: OpenBSD, WebAssembly, AIX, 32-bit Windows. Verify your target GOOS/GOARCH is supported before relying on Go FIPS mode.

### FIPS mode effects on crypto/tls

When FIPS mode is enabled, `crypto/tls` automatically:
- Restricts to TLS 1.2 and 1.3 only
- Restricts to FIPS-approved cipher suites (AES-GCM with ECDHE; excludes ChaCha20-Poly1305)
- Restricts to FIPS-approved signature algorithms
- Restricts to FIPS-approved curves (P-256, P-384)
- Uses NIST SP 800-90A DRBG for randomness

### Minimal FIPS evidence checklist

- Build command showing `GOFIPS140=v1.0.0`
- Runtime `GODEBUG=fips140=on` or `fips140=only`
- Programmatic `fips140.Enabled()` log at startup
- TLS scan (testssl.sh/sslyze) showing only FIPS-approved protocol versions and cipher suites
- Go version (`go version`) confirming 1.24+
- CMVP validation status reference (CAVP certificate A6650)

---

## Mutual TLS / Client Certificate Authentication

**Controls:** SRG-APP-000033-API-000070 (approved authorizations), SRG-APP-000148-API-000255 (enterprise ICAM)

### Server-side mTLS configuration

```go
import (
    "crypto/tls"
    "crypto/x509"
    "os"
)

func newMTLSServer(handler http.Handler, clientCACertFile string) (*http.Server, error) {
    caCert, err := os.ReadFile(clientCACertFile)
    if err != nil {
        return nil, fmt.Errorf("read client CA cert: %w", err)
    }
    caPool := x509.NewCertPool()
    if !caPool.AppendCertsFromPEM(caCert) {
        return nil, fmt.Errorf("failed to parse client CA cert")
    }

    return &http.Server{
        Addr:    ":8443",
        Handler: handler,
        TLSConfig: &tls.Config{
            MinVersion: tls.VersionTLS12,
            ClientAuth: tls.RequireAndVerifyClientCert,
            ClientCAs:  caPool,
        },
        ReadHeaderTimeout: 5 * time.Second,
    }, nil
}
```

### Extracting client identity from certificate

```go
func clientIdentity(r *http.Request) (string, error) {
    if r.TLS == nil || len(r.TLS.PeerCertificates) == 0 {
        return "", errors.New("no client certificate presented")
    }
    cert := r.TLS.PeerCertificates[0]
    // Map Subject DN or SAN to application principal
    // Log the principal identity, not the raw certificate serial
    return cert.Subject.CommonName, nil
}
```

### Edge-terminated mTLS

When mTLS is terminated at the gateway (common with CAC/PIV), the Go service receives client identity in forwarded headers. Trust these headers only from known proxy CIDRs (see Trusted Proxy section).

---

## HTTP Method Enforcement

```go
func methodAllowlist(allowed map[string]http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        handler, ok := allowed[r.Method]
        if !ok {
            w.Header().Set("Allow", joinKeys(allowed))
            http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
            return
        }
        handler.ServeHTTP(w, r)
    })
}

func joinKeys(m map[string]http.Handler) string {
    keys := make([]string, 0, len(m))
    for k := range m {
        keys = append(keys, k)
    }
    return strings.Join(keys, ", ")
}
```

---

## Host Header Validation

```go
// trustedHosts is populated from deployment configuration.
// Never trust r.Host directly for building external-facing URLs.
var trustedHosts map[string]bool

func requireTrustedHost(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        host := r.Host
        if h, _, err := net.SplitHostPort(host); err == nil {
            host = h
        }
        if !trustedHosts[host] {
            http.Error(w, "invalid host", http.StatusBadRequest)
            return
        }
        next.ServeHTTP(w, r)
    })
}
```

---

## Evidence Artifact Templates

### Compliance finding output format

For each STIG control reviewed, document:

```
Control ID:       [V-XXXXXX or SRG-APP-XXXXXX-API-XXXXXX]
Control Title:    [requirement statement]
Source:           [ASD STIG / Web Server SRG / API SRG]
Applicability:    [Applicable / Not Applicable — with rationale if N/A]
Responsibility:   [APP / GW/EDGE / SHARED / PLATFORM]
Status:           [Satisfied / Not Satisfied / Partially Satisfied]
Evidence:         [code reference, config export, log sample, scan result]
Remediation:      [if not satisfied: specific action items]
```

### Evidence types by control family

| Control family | Code evidence | Config evidence | Runtime evidence |
|---|---|---|---|
| TLS/Transport | `tls.Config` source, no plaintext listeners | Gateway TLS policy export | TLS scan results (testssl.sh, sslyze) |
| Auth/Authz | Middleware chain, per-route scopes, fail-closed tests | IdP/gateway auth config | Auth failure audit logs |
| Audit logging | Structured log implementation, redaction logic | Log pipeline config, SIEM integration | Sample audit log entries showing all 6 fields |
| Error handling | Central error handler, no internal leakage tests | Debug mode disabled | Negative tests showing generic errors |
| Input validation | Validation middleware, parameterized queries | N/A | gosec scan results (G201, G202, G204) |
| Secrets | No hardcoded secrets in source | Vault/KMS integration | Secret scanning results (gosec G101) |
| Rate limiting | Throttle middleware, 429 response, audit events | Gateway rate limit config | Rate-limit audit log samples |
| Session mgmt | Cookie flags, session ID generation, timeout logic | N/A | Response headers showing Secure/HttpOnly |
| FIPS crypto | `crypto/fips140` check, build commands | `GOFIPS140` build config | FIPS mode verification log |
| Attack surface | No pprof/expvar imports, route inventory | Build tag gating for debug | Route list showing no debug endpoints |
