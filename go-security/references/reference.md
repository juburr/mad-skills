# Go Security Reference

Detailed checklists, code examples, and tooling reference. Loaded on demand from `SKILL.md`.

## Go 1.24 Security Changes

### os.Root (Filesystem Sandboxing)

Introduced in Go 1.24. Provides safe "open within a directory" semantics, preventing path traversal and symlink races at the syscall level. **Require Go >= 1.24.3** — CVE-2025-22873 allowed escaping to the parent directory via filenames ending in `"../"` (e.g., `Root.Open("../")` opened the parent).

```go
root, err := os.OpenRoot("/var/data/uploads")
if err != nil {
    return err
}
defer root.Close()

// Safe: cannot escape /var/data/uploads via ../ or symlinks
f, err := root.Open(userProvidedFilename)
```

### Post-Quantum Key Exchange (X25519MLKEM768)

Go 1.24 enabled X25519MLKEM768 by default when `tls.Config.CurvePreferences` is nil. This is a hybrid key exchange combining X25519 (classical) with ML-KEM-768 (post-quantum). Disable with `GODEBUG=tlsmlkem=0` if interoperability issues arise.

### FIPS 140 Infrastructure

Go 1.24 introduced the Go Cryptographic Module and the `crypto/fips140` package. `GOFIPS140` is a **build-time** variable: `off` (default, no FIPS mode), `latest` (unfrozen, enables FIPS by default), `v1.0.0` (frozen snapshot submitted for CMVP validation — currently In Process, not yet validated), `v1.26.0` (frozen snapshot, Implementation Under Test), or `inprocess` (dynamic alias for the latest In Process module, Go 1.24.3+). Runtime enforcement is via `GODEBUG=fips140=on` (approved algorithms required) or `GODEBUG=fips140=only` (strict mode). All values except `off` enable FIPS mode by default. These are distinct controls. Check go.dev/doc/security/fips140 for current CMVP validation status before making compliance claims.

## Go 1.25 Security Changes

### CrossOriginProtection (CSRF)

`net/http.CrossOriginProtection` rejects non-safe cross-origin browser requests. Detection uses `Sec-Fetch-Site` header (widely supported since 2023) or `Origin` hostname comparison with `Host`. Requests lacking both headers are assumed same-origin or non-browser and allowed through.

```go
mux := http.NewServeMux()
mux.HandleFunc("/api/transfer", handleTransfer)

cop := http.NewCrossOriginProtection()
cop.AddTrustedOrigin("https://app.example.com")
// cop.AddInsecureBypassPattern("/webhooks/") // narrow scope only — buggy in Go 1.25.0, use Go >= 1.25.1

http.ListenAndServe(":8080", cop.Handler(mux))
```

**Warning: `AddInsecureBypassPattern` is buggy in Go 1.25.0 — use Go >= 1.25.1.** The API exists in 1.25.0 but CVE-2025-47910 caused bypass patterns to match more requests than intended due to ServeMux redirect behavior (e.g., a pattern for `/hello/` would also bypass `/hello`). Additionally, `AddInsecureBypassPattern` panics on invalid or conflicting patterns — test patterns before deployment.

### TLS SHA-1 Removal

Go 1.25 disallows SHA-1 signature algorithms in TLS 1.2 handshakes. Connections to legacy servers using SHA-1 certificates will fail. Re-enable with `GODEBUG=tlssha1=1` if compatibility with legacy infrastructure is required.

### ASan Leak Detection

Go 1.25 adjusts address sanitizer behavior for cgo builds. If you rely on `-asan` in CI, verify that leak detection at exit still produces expected results after upgrading.

## Go 1.26 Security Changes

### FIPS 140 Support (Expanded)

Go 1.26 ships FIPS 140-3 Go Cryptographic Module v1.26.0, adding `WithoutEnforcement` and `Enforced` to `crypto/fips140`:

```go
import "crypto/fips140"

if fips140.Enforced() {
    // Running in FIPS mode (GODEBUG=fips140=on or fips140=only)
}

// Temporarily relax for non-security operations (only in fips140=only mode)
fips140.WithoutEnforcement(func() {
    // Non-FIPS crypto allowed here
})
```

Runtime enforcement: `GODEBUG=fips140=on` (approved algorithms required) or `GODEBUG=fips140=only` (strict — all crypto must use FIPS-approved algorithms). Build-time module selection: `GOFIPS140=off` (default), `GOFIPS140=latest` (unfrozen, enables FIPS), `GOFIPS140=v1.0.0` or `v1.26.0` (frozen snapshots, enable FIPS), or `GOFIPS140=inprocess` (latest In Process module, Go 1.24.3+). All values except `off` default the `fips140` GODEBUG to `on`. Check go.dev/doc/security/fips140 for current CMVP validation status before making compliance claims.

### Post-Quantum Key Exchange (Expanded)

Go 1.24 enabled X25519MLKEM768 by default. Go 1.26 adds SecP256r1MLKEM768 and SecP384r1MLKEM1024 as additional defaults. To restrict for compatibility:

```go
tlsConfig := &tls.Config{
    CurvePreferences: []tls.CurveID{
        tls.X25519,
        tls.CurveP256,
    },
}
```

Disable per feature: `GODEBUG=tlsmlkem=0` disables X25519MLKEM768 (Go 1.24 default), `GODEBUG=tlssecpmlkem=0` disables SecP256r1MLKEM768 and SecP384r1MLKEM1024 (Go 1.26 defaults). Explicit `CurvePreferences` can control both sets. Only restrict if you encounter interoperability issues with older clients/servers.

### Custom Randomness Hardening

Go 1.26: many crypto APIs (key generation in `crypto/rsa`, `crypto/ecdsa`, `crypto/ed25519`, `crypto/ecdh`, signing operations, etc.) now ignore the caller-provided `random` parameter and use a secure internal source. This prevents attacks where a weak RNG is injected via the randomness parameter. Direct reads from `crypto/rand.Reader` still work if overridden, but higher-level APIs refuse the custom source.

For deterministic testing, use `testing/cryptotest.SetGlobalRandom`. To temporarily restore old behavior (rare, not recommended):

```
GODEBUG=cryptocustomrand=1
```

Overriding `crypto/rand.Reader` or passing custom `io.Reader` to crypto APIs should be treated as a **security smell** during review — confirm whether it still affects the specific call sites in the target Go version.

### url.Parse Host Colon Rejection

Go 1.26 rejects URLs with colons in the host field, closing a class of parsing ambiguities that could lead to SSRF or routing confusion.

### ReverseProxy.Director Deprecation

```go
// DEPRECATED — vulnerable to hop-by-hop header stripping
proxy := &httputil.ReverseProxy{
    Director: func(req *http.Request) {
        req.Header.Set("X-Internal-Auth", token) // can be stripped by client
    },
}

// SAFE — use Rewrite instead
proxy := &httputil.ReverseProxy{
    Rewrite: func(r *httputil.ProxyRequest) {
        r.SetURL(targetURL)
        r.Out.Header.Set("X-Internal-Auth", token)
    },
}
```

The `Rewrite` function receives a `ProxyRequest` with separate `In` (client) and `Out` (backend) requests, preventing client-controlled headers from interfering with proxy-added headers.

### Heap Base Address Randomization

Go 1.26 randomizes the heap base address on 64-bit platforms at startup, making heap address prediction harder. Can be disabled with `GOEXPERIMENT=norandomizedheapbase64`. No code changes needed.

### runtime/secret Package (Experimental)

The `runtime/secret` package is available as an **experiment** — requires `GOEXPERIMENT=runtimesecret` at build time. Supported on amd64 and arm64 (Linux only). It securely erases temporaries from registers, stack, and heap used in cryptographic operations. Primarily relevant for crypto library authors, not general application code.

## Code Examples by Category

### SSRF-Safe HTTP Client with DNS Rebinding Protection

The key insight: validating the resolved IP *at DNS resolution time* is insufficient because DNS responses can change between resolution and connection. Validate at dial time.

```go
import (
    "fmt"
    "net"
    "net/http"
    "syscall"
    "time"
)

func newSSRFSafeClient() *http.Client {
    dialer := &net.Dialer{
        Timeout: 5 * time.Second,
        Control: func(network, address string, c syscall.RawConn) error {
            host, _, err := net.SplitHostPort(address)
            if err != nil {
                return err
            }
            ip := net.ParseIP(host)
            if ip == nil {
                return fmt.Errorf("invalid IP: %s", host)
            }
            if isBlockedIP(ip) {
                return fmt.Errorf("blocked IP range: %s", ip)
            }
            return nil
        },
    }

    return &http.Client{
        Timeout: 10 * time.Second,
        Transport: &http.Transport{
            DialContext:           dialer.DialContext,
            Proxy:                nil, // disable proxy env vars
            TLSHandshakeTimeout:  5 * time.Second,
            ResponseHeaderTimeout: 5 * time.Second,
            MaxIdleConns:         10,
            IdleConnTimeout:      30 * time.Second,
            DisableKeepAlives:    true,
        },
        CheckRedirect: func(req *http.Request, via []*http.Request) error {
            if len(via) >= 3 {
                return fmt.Errorf("too many redirects")
            }
            // Defense-in-depth: strip sensitive headers on cross-host redirect.
            // Go already strips Authorization/Cookie on cross-domain redirects,
            // but this protects against subdomain forwarding and proxy-auth leakage.
            if req.URL.Host != via[0].URL.Host {
                req.Header.Del("Authorization")
                req.Header.Del("Cookie")
                req.Header.Del("Proxy-Authorization")
            }
            return nil
        },
    }
}

// isBlockedIP returns true for IPs that should not be reachable from SSRF-prone code paths.
// Covers both IPv4 and IPv6 ranges.
func isBlockedIP(ip net.IP) bool {
    return ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() ||
        ip.IsLinkLocalMulticast() || ip.IsUnspecified()
}
```

The `Control` callback fires after DNS resolution but before the TCP connection is established. The `address` parameter contains the resolved IP and port. Note: if dialing by IP for HTTPS, ensure `tls.Config.ServerName` is set appropriately for SNI.

### JWT Validation (Algorithm Confusion Prevention)

```go
import (
    "fmt"
    "github.com/golang-jwt/jwt/v5"
)

// UNSAFE — accepts any algorithm the token claims
token, err := jwt.Parse(tokenString, func(t *jwt.Token) (any, error) {
    return publicKey, nil // algorithm confusion: RS256 token could claim HS256
})

// SAFE — enforce expected algorithm
token, err := jwt.Parse(tokenString, func(t *jwt.Token) (any, error) {
    if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
        return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
    }
    return publicKey, nil
}, jwt.WithValidMethods([]string{"RS256"}),
   jwt.WithIssuer("https://auth.example.com"),
   jwt.WithAudience("my-service"),
   jwt.WithExpirationRequired(),
)
```

Key points:
- `jwt.WithValidMethods` rejects tokens claiming unexpected algorithms.
- Always validate `iss`, `aud`, and require `exp`.
- Never use `github.com/dgrijalva/jwt-go` (archived, has known CVEs).

### SQL Injection Prevention

```go
// UNSAFE — string interpolation
query := fmt.Sprintf("SELECT * FROM users WHERE name = '%s'", userName)
rows, err := db.Query(query)

// SAFE — parameterized query
rows, err := db.Query("SELECT * FROM users WHERE name = ?", userName)

// SAFE — with sqlx named queries
rows, err := db.NamedQuery("SELECT * FROM users WHERE name = :name",
    map[string]any{"name": userName})
```

ORM caution:
```go
// UNSAFE — gorm with raw SQL from user input
db.Raw("SELECT * FROM users WHERE role = " + userRole).Scan(&users)

// SAFE — gorm parameterized
db.Raw("SELECT * FROM users WHERE role = ?", userRole).Scan(&users)

// SAFE — gorm query builder
db.Where("role = ?", userRole).Find(&users)
```

### text/template vs html/template XSS

```go
// UNSAFE — text/template performs NO escaping
import "text/template"
t := template.Must(template.New("page").Parse(`<p>Hello, {{.Name}}</p>`))
t.Execute(w, data) // if Name = "<script>alert(1)</script>", XSS occurs

// SAFE — html/template auto-escapes by context
import "html/template"
t := template.Must(template.New("page").Parse(`<p>Hello, {{.Name}}</p>`))
t.Execute(w, data) // Name is HTML-escaped automatically
```

Escape-bypass types require extra caution:
```go
// DANGEROUS — only use with trusted, sanitized content
data := struct{ Bio template.HTML }{
    Bio: template.HTML(userInput), // XSS if userInput is not sanitized
}
```

### HTTP Server Hardening (Complete Example)

```go
// Public routes — no auth required
publicMux := http.NewServeMux()
publicMux.HandleFunc("GET /health", handleHealth)

// Protected routes — auth required
protectedMux := http.NewServeMux()
protectedMux.HandleFunc("POST /api/transfer", handleTransfer)

// Combine: auth middleware wraps only protected routes
mux := http.NewServeMux()
mux.Handle("/health", publicMux)
mux.Handle("/api/", authMiddleware(protectedMux))

srv := &http.Server{
    Addr:              ":8443",
    Handler:           mux,
    ReadHeaderTimeout: 10 * time.Second,
    ReadTimeout:       30 * time.Second,
    WriteTimeout:      60 * time.Second, // increase or omit for streaming/SSE
    IdleTimeout:       120 * time.Second,
    MaxHeaderBytes:    1 << 20, // 1 MB
    TLSConfig: &tls.Config{
        MinVersion: tls.VersionTLS12,
        // Go 1.24+ enables post-quantum KEX by default; no action needed
    },
}

// Bind pprof to a separate internal-only listener
go func() {
    debugMux := http.NewServeMux()
    debugMux.HandleFunc("/debug/pprof/", pprof.Index)
    http.ListenAndServe("127.0.0.1:6060", debugMux)
}()

srv.ListenAndServeTLS("cert.pem", "key.pem")
```

### Request Body Limiting Middleware

```go
func maxBodyMiddleware(maxBytes int64, next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
        next.ServeHTTP(w, r)
    })
}
```

### Path Traversal Prevention

```go
// UNSAFE — filepath.Join does not prevent traversal
path := filepath.Join("/var/uploads", userInput)
// userInput = "../../etc/passwd" → path = "/etc/passwd" after Clean

// PREFERRED — os.Root (Go 1.24+), traversal-resistant at the syscall level
root, err := os.OpenRoot(base)
if err != nil {
    return err
}
defer root.Close()
f, err := root.Open(userInput)

// LEGACY FALLBACK (pre-Go 1.24) — lexical-only prefix check.
// Prevents ../ traversal but does NOT prevent symlink/hardlink escapes
// or TOCTOU races. Has edge cases on case-insensitive filesystems and
// Windows UNC paths. Prefer os.Root for a real security boundary.
//
// Alternative: use filepath.IsLocal (Go 1.20+) as a cleaner lexical
// predicate — if IsLocal(path) returns true, Join(base, path) is
// guaranteed to stay within base lexically.
path := filepath.Join(base, filepath.Clean("/"+userInput))
if !strings.HasPrefix(path, filepath.Clean(base)+string(os.PathSeparator)) {
    return fmt.Errorf("path traversal attempt")
}
```

### Archive Extraction Safety

```go
func extractTarSafely(r io.Reader, destDir string) error {
    tr := tar.NewReader(r)
    for {
        hdr, err := tr.Next()
        if err == io.EOF {
            break
        }
        if err != nil {
            return err
        }

        // Reject absolute paths and traversal
        clean := filepath.Clean(hdr.Name)
        if filepath.IsAbs(clean) || strings.HasPrefix(clean, "..") {
            return fmt.Errorf("illegal path in archive: %s", hdr.Name)
        }

        target := filepath.Join(destDir, clean)
        if !strings.HasPrefix(target, filepath.Clean(destDir)+string(os.PathSeparator)) {
            return fmt.Errorf("path traversal in archive: %s", hdr.Name)
        }

        // Restrict permissions
        switch hdr.Typeflag {
        case tar.TypeDir:
            if err := os.MkdirAll(target, 0750); err != nil {
                return err
            }
        case tar.TypeReg:
            // Ensure parent directories exist for nested files
            if err := os.MkdirAll(filepath.Dir(target), 0750); err != nil {
                return err
            }
            f, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0640)
            if err != nil {
                return err
            }
            if _, err := io.Copy(f, io.LimitReader(tr, 100<<20)); err != nil { // 100 MB limit per file
                f.Close()
                return err
            }
            f.Close()
        default:
            // Skip symlinks and other special types
            continue
        }
    }
    return nil
}
```

### Structured Logging to Prevent Log Injection

```go
// UNSAFE — newlines in user input forge log entries
log.Printf("login attempt: user=%s", userInput)
// userInput = "admin\n2025-01-01 SUCCESS login: user=admin" → forged log line

// SAFE — structured logging separates data from format
slog.Info("login attempt", "user", userInput)
// Output: level=INFO msg="login attempt" user="admin\n2025-01-01 ..."
```

## gosec Rule Quick Reference

| Rule | Category | Description |
|---|---|---|
| G101 | Credentials | Hardcoded credentials in source |
| G102 | Network | Binding to all interfaces (`0.0.0.0`) |
| G103 | Memory | Use of `unsafe` package |
| G104 | Errors | Unchecked error return values |
| G109 | Integers | Integer overflow via `strconv` |
| G110 | Resources | Decompression bomb (unbounded `io.Copy` from compressed stream) |
| G112 | HTTP | Slowloris (missing timeouts) |
| G113 | HTTP | Request smuggling patterns |
| G114 | HTTP | Serve functions that don't support timeouts |
| G115 | Integers | Integer conversion overflow |
| G116 | Supply chain | Trojan Source (Unicode bidi control characters) |
| G117 | Secrets | Secret exposure via JSON/XML marshaling of struct fields |
| G118 | Resources | Context propagation failures / goroutine leaks |
| G119 | HTTP | Unsafe redirect policy leaking headers |
| G201 | SQL | SQL query construction with `fmt.Sprintf` |
| G202 | SQL | SQL query construction with string concatenation |
| G204 | OS | Command execution with variable input |
| G301 | Filesystem | `os.Mkdir` with permissive mode |
| G302 | Filesystem | `os.Chmod` with permissive mode |
| G303 | Filesystem | Predictable temp file path |
| G304 | Filesystem | File path from tainted input (path traversal) |
| G305 | Filesystem | Archive entry extracting outside target directory |
| G306 | Filesystem | `os.WriteFile` with permissive mode |
| G307 | Filesystem | `os.Create` uses default 0o666 permissions (too permissive) |
| G401 | Crypto | Use of weak hash (MD5, SHA-1) for security |
| G402 | Crypto | TLS `InsecureSkipVerify` set to true |
| G403 | Crypto | RSA key smaller than 2048 bits |
| G404 | Crypto | Use of `math/rand` for security-sensitive value |
| G501 | Crypto | Import of `crypto/md5` |
| G502 | Crypto | Import of `crypto/des` |
| G503 | Crypto | Import of `crypto/rc4` |
| G504 | Crypto | Import of `net/http/cgi` |
| G505 | Crypto | Import of `crypto/sha1` |

## Tooling Setup

### govulncheck

```bash
go install golang.org/x/vuln/cmd/govulncheck@latest
govulncheck ./...
```

Interpret results:
- **"Your code is affected"** — Reachable call stacks use a vulnerable function. Prioritize fix.
- **Informational** — Vulnerable package imported but affected symbols not called. Lower priority but still update.

### gosec

```bash
go install github.com/securego/gosec/v2/cmd/gosec@latest
gosec ./...

# Exclude specific rules
gosec -exclude=G104 ./...

# JSON output for CI integration
gosec -fmt=json -out=results.json ./...
```

### Recommended CI Pipeline

```yaml
# Example GitHub Actions snippet
- name: Go Vet
  run: go vet ./...

- name: Race Detector Tests
  run: go test -race -count=1 ./...

- name: Vulnerability Check
  run: |
    go install golang.org/x/vuln/cmd/govulncheck@latest
    govulncheck ./...

- name: Security Scan
  run: |
    go install github.com/securego/gosec/v2/cmd/gosec@latest
    gosec ./...

- name: Fuzz Tests
  run: go test -fuzz=. -fuzztime=30s ./...
```

### Decompression Bomb Prevention

gosec G110 flags unbounded decompression. Always limit decompressed output:

```go
// UNSAFE
io.Copy(dst, gzipReader) // unlimited decompression

// SAFE
io.Copy(dst, io.LimitReader(gzipReader, maxDecompressedSize))
```

### Hardcoded Credential Detection

gosec G101 flags patterns that look like hardcoded credentials:

```go
// FLAGGED — hardcoded credential
const apiKey = "sk-live-abc123def456"

// SAFE — read from environment
apiKey := os.Getenv("API_KEY")
```

### Binding to All Interfaces

gosec G102 flags binding to `0.0.0.0`:

```go
// FLAGGED — accessible on all network interfaces
http.ListenAndServe(":8080", handler)

// Consider — bind to specific interface in production
http.ListenAndServe("127.0.0.1:8080", handler)
```
