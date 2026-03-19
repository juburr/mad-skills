---
name: go-security
description: Guides secure Go coding practices and security reviews. Use when writing,
  reviewing, or auditing Go code for vulnerabilities including injection, path traversal,
  race conditions, authentication flaws, cryptographic misuse, HTTP hardening gaps,
  SSRF, and supply-chain risks.
---

# Go Security

Covers Go 1.24+ with awareness of Go 1.25 and 1.26 security features. Covers both writing secure Go code and reviewing existing code for vulnerabilities. Check the project's `go.mod` (`go` directive and `toolchain` line) to determine the target Go version and adjust advice accordingly.

## Review Workflow

When reviewing Go code for security issues, follow this sequence:

1. **Triage dangerous primitives** — Scan for the high-risk signals in the table below. Their presence determines which deeper checklists to apply.
2. **Check HTTP hardening** — For any service exposing HTTP: timeouts, body limits, CSRF, debug endpoints.
3. **Check auth/authz** — Verify authentication middleware coverage, JWT validation, and authorization enforcement.
4. **Check data handling** — Parsing strictness, injection surfaces, template escaping.
5. **Check supply chain** — Dependency vulnerabilities, CI pipeline tooling.
6. **Consult detailed checklists** — For any flagged area, read `references/reference.md` for expanded guidance and code examples.

## Danger Signal Triage

Scan for these primitives first. If present, apply the corresponding checklist section.

| Signal | What to look for | Risk |
|---|---|---|
| `unsafe` | `unsafe.Pointer`, `uintptr` arithmetic, `unsafe.String`/`Slice` | Type system bypass, memory corruption |
| `cgo` | `import "C"`, `#cgo` directives | Memory corruption, UB, linking risks |
| `os/exec` | `exec.Command`, especially with `sh -c` | Command injection, PATH hijacking |
| File I/O with user input | `os.Open`, `os.ReadFile`, `http.ServeFile`, `http.Dir` | Path traversal, symlink escape, dotfile leak |
| Archive extraction | `archive/zip`, `archive/tar` with user-supplied archives | Zip/Tar Slip (write outside target dir) |
| Reverse proxy | `httputil.ReverseProxy`, especially `.Director` | Header injection, hop-by-hop stripping |
| TLS config | `tls.Config`, `InsecureSkipVerify` | MitM, disabled verification |
| `database/sql` | `fmt.Sprintf` or string concat building queries | SQL injection |
| `text/template` | Used for HTML output instead of `html/template` | XSS (no escaping) |
| `template.HTML` | Bypass types in `html/template` with user data | XSS (escaping disabled) |
| `math/rand` | Used for security tokens, keys, or nonces | Predictable randomness |
| `encoding/json` | Decoding into `map[string]any` or missing size limits | Type confusion, resource exhaustion |
| Debug endpoints | `/debug/pprof` routes exposed | Information disclosure |
| `http.DefaultClient` | Used for outbound requests without timeout/proxy control | SSRF, unbounded requests |

## Language & Semantic Pitfalls

### unsafe and cgo

- Treat all `unsafe` usage as a manual memory safety zone. Verify pointer arithmetic, alignment, and lifetime guarantees.
- For `cgo`: audit linked C libraries independently. Note that Go's race detector and sanitizers have limited coverage across the cgo boundary.
- gosec rule: G103 (unsafe blocks).

### Integer Conversions

- Conversions from larger to smaller integer types (e.g., `int64` to `int32`) silently truncate. This can bypass length checks, cause negative values, or corrupt offsets.
- gosec rules: G109, G115.

### Error Handling

- Unchecked errors on security-sensitive operations (auth checks, file permission changes, crypto operations) can silently succeed when they should fail.
- Watch for `defer` blocks that swallow errors from `Close()` / `Flush()` where failure matters.
- gosec rule: G104.

### Race Conditions

- Security decisions (auth, rate limiting, permission checks) based on shared mutable state without synchronization are exploitable via TOCTOU.
- Concurrent map access without locks causes runtime panics.
- Goroutines spawned per request must have bounded lifetime via context cancellation. Unbounded goroutines are a DoS vector.
- Use `go test -race` in CI for all packages.

## Filesystem & Path Safety

### Path Traversal

- `filepath.Join(base, userInput)` + `filepath.Clean` is **not** safe alone. Must verify the result stays within `base` after cleaning, and consider symlinks.
- Prefer `os.Root` (Go 1.24+) for rooted filesystem operations. **Require Go >= 1.24.3** — CVE-2025-22873 allowed escaping to the parent directory via filenames ending in `"../"`. For pre-1.24 codebases, use a manual prefix check as a fallback (see `references/reference.md`).
- gosec rule: G304.

### Static File Serving

- `http.Dir` follows symlinks out of the directory tree and serves dotfiles (`.git`, `.env`).
- Use a custom `http.FileSystem` wrapper to block dotfiles and restrict symlink traversal.

### Archive Extraction

- Validate that extracted paths do not contain `..` segments or absolute paths after cleaning.
- Enforce extraction under a controlled directory.
- gosec rule: G305.

### File Permissions

- Do not write secrets or configs with modes `0777` or `0666`. Use `0600` for secrets, `0644` for non-sensitive configs.
- Use `os.CreateTemp` / `os.MkdirTemp` for temp files, not predictable paths.
- gosec rules: G301-G307.

## OS Command Execution

- `exec.Command` does not invoke a shell, but the invoked program may interpret arguments in dangerous ways.
- Never construct the executable path from user input. Use a fixed, fully qualified path.
- Never pass user input to `sh -c` or `cmd.exe /C`.
- Control the environment with `Cmd.Env` to prevent `PATH` hijacking and env-variable injection.
- gosec rule: G204.

## HTTP Server Hardening

### Timeouts

Always set `ReadHeaderTimeout` on `http.Server`. Set `WriteTimeout` and `IdleTimeout` based on response semantics — `WriteTimeout` can break streaming responses, SSE, and long-polling handlers, so adjust or use per-request deadlines for those.

```go
srv := &http.Server{
    ReadHeaderTimeout: 10 * time.Second,
    WriteTimeout:      30 * time.Second, // omit or increase for streaming/SSE
    IdleTimeout:       120 * time.Second,
    MaxHeaderBytes:    1 << 20, // 1 MB
}
```

gosec rule: G112 (slowloris), G114 (serve functions without timeout support).

### Request Body Limits

Wrap the request body with `http.MaxBytesReader` before parsing. Without it, a client can send unlimited data.

```go
r.Body = http.MaxBytesReader(w, r.Body, 10<<20) // 10 MB limit
```

For streaming, use `json.NewDecoder` / `xml.NewDecoder` instead of `io.ReadAll`.

### CSRF Protection

Go 1.25 introduced `http.CrossOriginProtection` for cookie-authenticated endpoints:
- Rejects non-safe cross-origin browser requests (detects via `Sec-Fetch-Site` or `Origin` header comparison).
- Define trusted origins explicitly with `AddTrustedOrigin`.
- **`AddInsecureBypassPattern` is buggy in Go 1.25.0 — use Go >= 1.25.1.** CVE-2025-47910: bypass patterns matched more requests than intended due to ServeMux redirect behavior (e.g., a pattern for `/hello/` also bypassed `/hello`). The API exists in 1.25.0 but should not be relied on until 1.25.1+. It can also panic on invalid/conflicting patterns.
- Ensure state-changing actions are never on GET/HEAD/OPTIONS.

### Multipart Upload Limits

`Request.ParseMultipartForm` can consume significant memory and disk. Always apply `MaxBytesReader` to the body *before* calling `ParseMultipartForm`, and set a reasonable `maxMemory` parameter. Validate content type, file extension, and magic bytes on uploaded files.

### Debug Endpoints

Never expose `/debug/pprof` in production. It leaks goroutine stacks, memory profiles, and internal state. Guard behind auth middleware or bind to a separate internal listener.

### Request Smuggling

- Go 1.26 tightens `url.Parse` to reject colons in host fields. Opt out with `GODEBUG=urlstrictcolons=0` if legacy compatibility is needed.
- Validate and normalize `Host` headers and forwarded headers behind proxies.
- gosec rule: G113.

## Reverse Proxies & Header Trust

- `httputil.ReverseProxy.Director` is **deprecated in Go 1.26** due to a security flaw: clients can use hop-by-hop headers to strip headers added by Director. Migrate to `Rewrite`, which provides separate `In` (client) and `Out` (backend) requests via `ProxyRequest`. Use `ProxyRequest.SetURL` and `ProxyRequest.SetXForwarded` for safe URL and header propagation.
- Protect security-sensitive headers (`Authorization`, `Cookie`, internal routing) from client manipulation.
- Do not trust `X-Forwarded-For`, `X-Real-IP`, or `X-Forwarded-Proto` unless the request came from a known proxy. Validate at ingress.
- Headers like HSTS, CSP, X-Content-Type-Options may be set at the application level or at an upstream proxy/ingress. Verify the deployment architecture before flagging their absence in Go code.

## Client-Side HTTP: SSRF, Redirects, Proxies

### SSRF Prevention

- Never use `http.DefaultClient` for requests where the URL is derived from user input.
- Use a custom `http.Client` with:
  - Explicit `Timeout` on the client.
  - `TLSHandshakeTimeout` and `ResponseHeaderTimeout` on the `Transport` to bound connection setup.
  - A custom `Transport.DialContext` that validates resolved IPs against an allowlist (reject private/loopback ranges).
- **DNS rebinding bypass**: IP validation at hostname resolution time is insufficient. The DNS response can change between validation and dial. Use `net.Dialer.Control` to validate the resolved IP at dial time (after resolution, before connection). See `references/reference.md` for a complete implementation.

### Proxy Environment Variables

- `http.DefaultTransport` reads `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` from the environment via `ProxyFromEnvironment`.
- For security-sensitive outbound calls, override `Transport.Proxy` with an explicit policy.

### Redirect Header Leakage

- Go's `http.Client` strips `Authorization`, `WWW-Authenticate`, and `Cookie` headers when redirecting to a domain that is not a subdomain match or exact match of the original. However, sensitive headers *are* forwarded to subdomains — consider subdomain-takeover risk and cookie domain scoping.
- Historically, other sensitive headers (e.g., `Proxy-Authorization`) had cross-origin redirect leakage bugs (GO-2025-3751). Keep Go patched.
- For high-security clients, set `CheckRedirect` as defense-in-depth to enforce explicit redirect policies.
- gosec rule: G119.

## Authentication & Authorization

### Route Protection

- Go's `net/http` has no framework-level auth enforcement. Every route must be explicitly wrapped with auth middleware. Audit for unprotected routes, especially new ones.
- Prefer a middleware chain that applies auth by default and explicitly opts out for public routes (allowlist, not denylist).

### JWT Validation

- Always validate the `alg` claim. Reject `none` and unexpected algorithms to prevent algorithm confusion attacks (e.g., RS256-to-HS256 where the public key is used as HMAC secret).
- Validate `iss`, `aud`, and `exp` claims even when using established libraries.
- Use `github.com/golang-jwt/jwt/v5`. The archived `github.com/dgrijalva/jwt-go` has known CVEs.

### Session & Cookie Security

- Set `Secure`, `HttpOnly`, `SameSite` attributes on session cookies.
- Do not store sensitive data in cookies without encryption/signing.

## SQL & Database Safety

- **Always** use parameterized queries (`db.Query("... WHERE id = ?", id)`). Never build queries with `fmt.Sprintf` or string concatenation using user input.
- Placeholder syntax varies by driver: `?` for MySQL, `$1`/`$2` for PostgreSQL (`lib/pq`, `pgx`), `@param` for some others.
- Watch for ORM raw/unsafe modes (e.g., `gorm.Raw()`, `sqlx.Get` with hand-built queries).
- gosec rules: G201, G202.

## Parsing, Encoding & Injection

### JSON

- Use `json.NewDecoder` with `DisallowUnknownFields()` and a size-limited reader for strict API endpoints.
- Decoding into `map[string]any` loses type safety. Prefer typed structs for security-sensitive data.
- Large integers lose precision when decoded into `float64`. Use `json.Number` or integer types.

### XML

- Go's `encoding/xml` does not automatically process external DTD entities (unlike many classic XXE-vulnerable parsers).
- If using third-party XML parsers (especially cgo bindings to libxml2), the XXE threat model changes. Audit entity expansion behavior.

### HTML Templates

- **Always** use `html/template` (not `text/template`) for HTML output. `text/template` performs zero escaping. Both have identical APIs, so the mistake compiles silently.
- Audit uses of escape-bypass types (`template.HTML`, `template.JS`, `template.URL`) with user-controlled data. These disable contextual escaping and introduce XSS.
- Watch for `fmt.Fprintf(w, userInput)` patterns that bypass template escaping entirely.

### Log Injection

- Sanitize user input in log entries to prevent log forging (newline injection, control characters).
- Use structured logging (`slog`) to separate data from format.

## Cryptography Essentials

### Secure Randomness

- Use `crypto/rand` for tokens, keys, nonces, and session IDs. Never `math/rand`.
- Go 1.26: many crypto APIs (key generation, signing, etc.) ignore caller-provided randomness parameters and use a secure internal source. Overriding `crypto/rand.Reader` or passing custom `io.Reader` to these APIs should be treated as a security smell. `GODEBUG=cryptocustomrand=1` restores old behavior (temporary); use `testing/cryptotest.SetGlobalRandom` for deterministic tests.

### TLS Configuration

- Never set `InsecureSkipVerify: true` in production. Always set `ServerName` when providing a custom `tls.Config`.
- Go 1.25 disallows SHA-1 signature algorithms in TLS 1.2 handshakes. Re-enable with `GODEBUG=tlssha1=1` if needed for legacy infrastructure.
- Go 1.24 enabled X25519MLKEM768 (post-quantum) by default; disable with `GODEBUG=tlsmlkem=0`. Go 1.26 adds SecP256r1MLKEM768 and SecP384r1MLKEM1024 as additional defaults; disable with `GODEBUG=tlssecpmlkem=0`. Explicit `tls.Config.CurvePreferences` can also control both sets.

### Weak Algorithms

- Do not use MD5, SHA-1, DES, or RC4 for security purposes (signatures, MACs, password hashing, encryption).
- For password hashing, use `golang.org/x/crypto/bcrypt` or `golang.org/x/crypto/argon2`.

### FIPS Awareness

- Go 1.24 introduced `crypto/fips140` with two distinct controls:
  - **Build-time module selection** (`GOFIPS140`): `off` (default), `latest` (unfrozen), `v1.0.0`/`v1.26.0` (frozen snapshots), or `inprocess` (dynamic alias, Go 1.24.3+). All values except `off` enable FIPS by default.
  - **Runtime enforcement** (`GODEBUG`): `fips140=on` (approved algorithms required) or `fips140=only` (strict mode).
- Check CMVP validation status at go.dev/doc/security/fips140 before making compliance claims.
- If FIPS signals are present in a codebase, route to compliance/crypto review. Detailed FIPS policy (validation status, 140-2 vs 140-3, module provenance) is out of scope for general security review.

### sync.Pool and Secret Data

- Buffers stored in `sync.Pool` that contain secrets (tokens, decrypted payloads) can be reused across requests and persist in memory. Zero secret data before returning buffers to a pool.

## Supply Chain & CI Pipeline

### Dependency Scanning

- Run `govulncheck ./...` in CI. It identifies whether vulnerable symbols are actually reachable via call stacks (low noise vs. naive CVE scanning).
- Keep Go itself and all dependencies updated. Subscribe to `golang-announce` for security releases.

### Trojan Source Detection

- Unicode bidi control characters can make code appear different in review than it is to the compiler.
- gosec rule G116 detects bidi control characters. Enable in CI.

### Recommended CI Security Checks

```
go vet ./...
go test -race ./...
govulncheck ./...
gosec ./...
```

Add targeted fuzz tests (`go test -fuzz`) for parsers and any code processing user-supplied input.

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/reference.md` | Go 1.24/1.25/1.26 security change details, expanded code examples for each vulnerability category, gosec rule mappings, tooling setup, DNS rebinding mitigation patterns, JWT validation examples, SSRF-safe dialer implementation | Needing code examples, version-specific details, gosec rule explanations, or implementation patterns for any checklist item above |
