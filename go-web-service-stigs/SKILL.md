---
name: go-web-service-stigs
description: Guides DISA STIG compliance reviews for custom Go HTTP web services and
  APIs. Use when auditing Go code against the Application Security and Development
  STIG, Web Server SRG, or API SRG, mapping Go implementation patterns to STIG control
  IDs, generating compliance evidence, or hardening Go services for DoD environments.
---

# Go Web Service STIGs

Compliance-focused review guidance for custom Go HTTP services against three DISA sources:

- **Application Security and Development (ASD) STIG** — application-level security controls
- **Web Server Security Requirements Guide (SRG)** — transport, sessions, logging, least functionality
- **API SRG (V1R1)** — API-specific controls: rate limiting, API keys, telemetry, circuit breakers, token management

This skill maps STIG control intent to Go microservice architecture. It does not duplicate general Go security guidance — use the `go-security` skill for that. This skill focuses on what DISA specifically requires and how to prove compliance.

## Applicability Questions

Determine which control families apply by answering these questions about the service under review:

| Question | If yes, apply controls tagged |
|---|---|
| Does the Go service terminate TLS itself? | `TLS-App` |
| Is TLS terminated at a gateway/LB/ingress? | `TLS-Edge` |
| Does the service use cookie-based sessions? | `Cookies` |
| Does the service use JWT/OAuth2 bearer tokens? | `Tokens` |
| Does the service issue or manage API keys? | `APIKeys` |
| Does the service query a database? | `DB` |
| Does the service serve browser clients with CORS? | `CORS` |
| Is there a mandated API gateway in the architecture? | `GW` |
| Does the service cache sensitive or policy data? | `Cache` |
| Does the service trigger privileged or remote commands? | `Cmd` |
| Is the service deployed in a FIPS-mandated environment? | `FIPS` |

Controls tagged `Always` apply to every Go web service.

## Responsibility Model

Each STIG control maps to an implementation responsibility:

| Responsibility | Who implements | Example |
|---|---|---|
| **APP** | Go service code and config | Input validation, error handling, authz checks |
| **GW/EDGE** | API gateway, ingress, WAF, LB | TLS termination, gateway rate limiting, WAF rules |
| **SHARED** | Both layers must cooperate | Auth (gateway validates token format; app validates claims) |
| **PLATFORM** | Infrastructure: K8s, Vault, SIEM, HSM | Key management, log aggregation, FIPS module provision |

The Go service must never defeat controls enforced at other layers (e.g., exposing a plaintext listener, trusting spoofed headers from untrusted sources).

Many Web Server SRG and API SRG controls can be fully satisfied by infrastructure components — a service mesh (Istio, Linkerd), API gateway (Kong, Envoy), ingress controller, or cloud-native platform feature — rather than Go code. When that is the case, document the infrastructure component, its configuration, and how it satisfies the control. The Go service only needs to cooperate (e.g., not bypassing mTLS by exposing a plaintext port). Do not reimplement controls in Go that are already enforced by the platform; instead, produce evidence showing the platform satisfies the requirement and the Go service does not undermine it.

## Compliance Review Workflow

1. **Determine applicability** — Answer the questions above to identify which control families are in scope.
2. **Check TLS and transport** — Verify no plaintext exposure, approved TLS versions, FIPS cipher suites if required.
3. **Check authentication and authorization** — Verify auth middleware coverage, fail-closed behavior, token/session validation.
4. **Check audit logging completeness** — Verify structured logs capture who/what/when/where/outcome/source with redaction.
5. **Check input validation and injection** — Verify server-side validation, parameterized queries, no command injection paths.
6. **Check error handling** — Verify no information leakage, fail-secure on dependency failures.
7. **Check secrets management** — Verify no embedded credentials in code, configs, or logs.
8. **Check attack surface** — Verify no debug endpoints, unnecessary routes, or sample code in production.
9. **Check rate limiting and telemetry** — Verify throttling, monitoring, and audit events for rate-limit triggers.
10. **Check token and session security** — Verify claim validation, timeouts, cookie hardening, replay resistance.
11. **Check FIPS compliance** — If `FIPS` tag applies, verify build and runtime FIPS configuration.
12. **Map findings to control IDs** — For each issue, read `references/controls.md` to identify all implicated STIG IDs.
13. **Generate evidence** — For each passing control, read `references/reference.md` for evidence artifact guidance.

## Danger Signal Triage

Scan for these Go code patterns first. Each maps to specific STIG controls.

| Signal | What to look for | STIG implication |
|---|---|---|
| Plaintext listener | `http.ListenAndServe` on non-loopback | TLS violation (V-206439, SRG-APP-000014) |
| `InsecureSkipVerify` | `tls.Config{InsecureSkipVerify: true}` | Defeats transport security verification |
| Missing timeouts | `http.Server{}` without `ReadHeaderTimeout` | DoS risk (V-206410) |
| `net/http/pprof` import | Debug profiling in production | Attack surface (V-206413, SRG-APP-000645) |
| `os/exec` with user input | `exec.Command` using request data | Command injection (V-222604) |
| SQL string concat | `fmt.Sprintf` building queries | SQL injection (SRG-APP-000447) |
| `math/rand` for secrets | Tokens/keys using non-crypto RNG | Weak randomness (SRG-APP-000224) |
| Hardcoded credentials | Passwords/keys/tokens in source | Embedded auth data (V-222642) |
| `Authorization` in logs | Logging raw tokens or cookies | Sensitive data in logs (V-222444) |
| `*` CORS origin | `Access-Control-Allow-Origin: *` with credentials | CORS violation (SRG-APP-000251) |
| Missing `exp` validation | JWT accepted without expiry check | Token expiry (SRG-APP-000400) |
| `expvar` exposed | Default variable export on public port | Information disclosure (V-222600) |

## TLS and Transport Security

**Key controls:** V-206439, V-206440, SRG-APP-000014-API-000020, SRG-APP-000439-API-001010

### When Go terminates TLS (TLS-App)

```go
srv := &http.Server{
    Addr:    ":8443",
    Handler: handler,
    TLSConfig: &tls.Config{
        MinVersion: tls.VersionTLS12,
        CipherSuites: []uint16{
            tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
            tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
            tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
            tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
        },
        CurvePreferences: []tls.CurveID{tls.CurveP384, tls.CurveP256},
    },
    ReadHeaderTimeout: 5 * time.Second,
    ReadTimeout:       15 * time.Second,
    WriteTimeout:      15 * time.Second,
    IdleTimeout:       60 * time.Second,
    MaxHeaderBytes:    1 << 20,
}
```

These cipher suites align with NIST SP 800-52 Rev 2 required ("shall") suites for TLS 1.2. TLS 1.3 cipher suites are not configurable in Go. In non-FIPS mode, Go negotiates `TLS_CHACHA20_POLY1305_SHA256` which is not a NIST-approved algorithm. If your compliance regime requires FIPS-only algorithms, enable Go FIPS mode (`GODEBUG=fips140=on`) so `crypto/tls` restricts to approved cipher suites only.

### When TLS terminates at gateway (TLS-Edge)

The Go service must still:
- Not expose any plaintext listener beyond localhost.
- Accept traffic only from trusted ingress (network policy or header validation).
- Trust `X-Forwarded-*` headers only from known proxy CIDRs. See `references/reference.md` for trusted proxy implementation.

## Authentication and Authorization

**Key controls:** V-206356, SRG-APP-000033-API-000070, SRG-APP-000340-API-000675

- Apply auth middleware by default. Explicitly allowlist public routes — never denylist protected ones.
- Enforce authorization at both middleware (coarse) and handler (fine-grained resource-level) layers.
- Fail closed: if token parsing, policy lookup, or dependency check fails, deny the request.
- Log all authorization failures with actor, action, and outcome (ties to audit requirements below).

```go
func RequireScope(scope string, next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        claims, err := validateToken(r)
        if err != nil {
            http.Error(w, "unauthorized", http.StatusUnauthorized)
            return // fail closed
        }
        if !claims.HasScope(scope) {
            http.Error(w, "forbidden", http.StatusForbidden)
            return
        }
        next.ServeHTTP(w, r)
    })
}
```

### Mutual TLS / Client Certificate Authentication

For DoD environments using CAC/PIV or other PKI-based authentication:

- Configure `tls.Config.ClientAuth` (e.g., `tls.RequireAndVerifyClientCert`) and `ClientCAs` with the trusted CA pool.
- Map the certificate identity (Subject DN or SAN) to an application principal for authorization decisions.
- Log the authenticated principal identity — not raw certificate serial numbers unless approved by policy.
- mTLS is often terminated at the edge (gateway/ingress). If so, validate that the gateway forwards identity in trusted headers and the Go service only trusts those headers from known proxy CIDRs.

See `references/reference.md` for implementation patterns.

### HTTP Method Enforcement

- Explicitly allow only required HTTP methods per route. Reject unrecognized methods with `405 Method Not Allowed`.
- Apply a global default-deny for uncommon methods (`TRACE`, `TRACK`, `CONNECT`, `PATCH` unless needed).
- Only handle `OPTIONS` on routes where CORS is required.

### Host Header Validation

- Never build absolute URLs from `r.Host` without validation. A poisoned `Host` header can cause bad redirects, cache poisoning, or SSRF-adjacent side effects.
- Enforce an allowlist of trusted hostnames for generating external-facing URLs. Configure per environment.

## Audit Logging Completeness

**Key controls:** V-206357, V-206360 through V-206366, V-206424, V-222444, SRG-APP-000095-API-001745/1765/1775/1785/1795

Every audit event must capture six fields to satisfy the Web Server SRG:

| Field | SRG requirement | Go source |
|---|---|---|
| **When** | Date and time (V-206360) | `time.Now().UTC()`, consistent timezone |
| **Where** | Where in the server (V-206361) | Handler/module name, service name |
| **Source** | Source of event / client IP (V-206362, V-206363) | Trusted-proxy-aware client IP extraction |
| **Outcome** | Success or failure (V-206364) | HTTP status code, boolean success flag |
| **Who** | Identity of user/process (V-206365) | Token subject, service identity, auth method |
| **What** | What happened (V-206357) | Action name, HTTP method + path, operation type |

Additionally, the logging mechanism must alert the ISSO and SA on logging processing failures (V-206366). Implement health checks or watchdog monitoring for the audit pipeline.

### Mandatory audit events (API SRG)

- Authentication attempts (success and failure)
- Authorization decisions (especially denials)
- Rate-limit enforcement triggers
- Exceptions and errors during processing
- Execution time / performance metrics (latency histograms)
- Request metadata: method, path, status, duration, correlation ID

### Redaction requirements (ASD STIG V-222444)

Never log: `Authorization` headers, raw tokens, passwords, session IDs, cookie values, API keys, PII, raw request/response bodies containing sensitive data. Use an allowlist approach — log only explicitly approved fields.

## Input Validation and Injection Prevention

**Key controls:** V-222604, SRG-APP-000447-API-001030/1035, V-222605

- Validate all ingress points: path parameters, query strings, headers, JSON body fields.
- Enforce type, range, length, and character set constraints server-side.
- Normalize/decode inputs before authorization decisions to prevent canonicalization bypasses.
- Use parameterized queries for all database access. Never build SQL with `fmt.Sprintf` or string concatenation.
- Avoid shell execution for request-driven behavior. If `os/exec` is required, use fixed binary paths with strict argument allowlists.

## Error Handling and Fail-Secure

**Key controls:** V-222585, V-222600, SRG-APP-000266-API-000535, V-206413

- Return generic error messages to clients. Never expose stack traces, SQL errors, file paths, or internal identifiers.
- Include a correlation ID (request ID) in both the client response and internal logs so auditors can trace without leaking internals.
- Fail to a secure state: if a required dependency (auth service, policy engine) is unavailable, deny requests rather than allowing them through.
- Readiness probes must fail until all security preconditions are met (FIPS module initialized, policy cache loaded, TLS certificates loaded).

## Secrets Management

**Key controls:** V-222642, V-222444

- No passwords, API keys, tokens, certificates, or private keys in source code, config files, Helm charts, CI configs, or `.env` files committed to the repository.
- Inject secrets at runtime via an approved secret store (Vault, AWS Secrets Manager, K8s secrets with encryption at rest).
- Never log secrets. If structured logging is used, redact sensitive fields explicitly.

## Attack Surface Reduction

**Key controls:** V-206375, V-206413, SRG-APP-000141-API-000245, SRG-APP-000645-API-001385

- Do not ship debug endpoints (`/debug/pprof`, `expvar`) enabled in production. Gate behind auth or build tags.
- Do not expose admin endpoints on public interfaces. Bind to a separate internal-only listener.
- Do not include Swagger UI, sample endpoints, or documentation endpoints unless explicitly required and access-controlled.
- Restrict static file serving to explicit paths. Do not mount `http.FileServer` at `/` without restrictions.
- Maintain a route inventory and justify each exposed endpoint.

## Rate Limiting and Telemetry

**Key controls:** SRG-APP-000247-API-000520/000870, SRG-APP-000095-API-001750, SRG-APP-000089-API-000120

- Implement rate limiting at the gateway and optionally per-service (defense in depth).
- Identify clients consistently: by API key ID, token subject, or IP address.
- Return `429 Too Many Requests` with a consistent response body.
- Emit an audit event every time rate limiting triggers (required by API SRG). Do not log every allowed request.
- Wire monitoring alerts for sustained throttling, auth failure spikes, and error rate anomalies.

## Token Security

**Key controls:** SRG-APP-000400-API-000850/855/860/865, SRG-APP-000441-API-001020, SRG-APP-001025-API-001715

When validating bearer tokens (JWT/OAuth2):

- Validate signature using trusted JWKS keys. Reject `alg: none`.
- Validate `iss` matches expected issuer.
- Validate `aud` contains this API's identifier.
- Validate `exp` is not expired and `nbf` is honored.
- Enforce maximum token TTL if organizational policy requires it.
- Never echo tokens back in responses (SRG-APP-000400-API-000855).
- Never log raw tokens.
- Implement refresh token rotation and replay resistance for privileged flows (V-222530).

## Session Management

**Key controls:** V-206352, V-206398, V-206414, V-206415, V-206431, V-222577, V-222581

When using cookie-based sessions:

- Generate session IDs server-side using `crypto/rand`. Never accept client-provided session IDs.
- Set cookie flags: `Secure`, `HttpOnly`, appropriate `SameSite`, scoped `Path`/`Domain`.
- Enforce absolute timeout (8 hours or less per V-206414) and inactivity timeout (V-206415).
- Rotate session ID on authentication. Invalidate on logout.
- Never embed session IDs in URLs. Never log session IDs.

## API Key Management

**Key controls:** SRG-APP-000224-API-000475, SRG-APP-000231-API-000490, SRG-APP-000915-API-001610, SRG-APP-000141-API-000240

- Generate API keys using `crypto/rand` (CSPRNG). In FIPS environments, use FIPS-validated RNG.
- Store only hashed keys (never plaintext). Use a KMS, Vault, or HSM where mandated.
- Enforce usage restrictions: scope to specific endpoints/methods, environment (dev/prod separation), IP allowlists.
- Monitor per-key usage for anomalies (SRG-APP-000095-API-001740).
- Design for key rotation: support multiple active keys per client during transitions.

## FIPS Cryptographic Compliance

**Key controls:** SRG-APP-000224-API-000475, SRG-APP-000231-API-000490, SRG-APP-000630-API-001375

Go 1.24+ includes a native FIPS 140-3 cryptographic module (v1.0.0, CAVP certificate A6650).

**Build-time**: freeze the FIPS module into the binary:

```bash
GOFIPS140=v1.0.0 go build -o myapp
```

**Runtime**: enable FIPS enforcement:

```bash
GODEBUG=fips140=on ./myapp    # approved algorithms required
GODEBUG=fips140=only ./myapp  # strict: non-approved algorithms error
```

Or pin in `go.mod`:

```
go 1.24
godebug fips140=on
```

When `fips140=on`, `crypto/tls` automatically restricts to FIPS-approved cipher suites, versions, and algorithms. Explicit cipher suite configuration (as shown in the TLS section above) serves as documentation and defense-in-depth.

**Programmatic check:**

```go
import "crypto/fips140"

if !fips140.Enabled() {
    log.Fatal("FIPS mode required but not enabled")
}
```

**Platform caveats**: FIPS mode (`GODEBUG=fips140=on/only`) is not supported on OpenBSD, WebAssembly, AIX, or 32-bit Windows. Verify your target platform is supported before relying on Go FIPS mode for compliance.

**CMVP status**: the Go Cryptographic Module v1.0.0 is on the NIST Modules In Process list. Verify current certification status before making compliance claims. `fips140.Enabled()` proves FIPS mode is active at runtime, but does not prove your entire system is CMVP-validated end-to-end. Some Authorizing Officials may require fully certified modules.

## Circuit Breaker and Resilience

**Key controls:** SRG-APP-000945-API-001635

- Wrap outbound dependency calls with timeouts and circuit breaker logic.
- Open the breaker on repeated failures or timeouts to prevent cascading failure.
- Emit observability events when the breaker trips or recovers.
- Combine with retries using exponential backoff and jitter.

## CORS Configuration

**Key controls:** SRG-APP-000251-API-000525

- Use explicit origin allowlists. Never use `Access-Control-Allow-Origin: *` with credentials.
- Configure per-environment origin lists (dev/staging/prod).
- Set `Vary: Origin` when reflecting the origin header.

## Data Volume Limits

**Key controls:** SRG-APP-000439-API-001005

- Enforce pagination defaults and maximum page sizes on all list endpoints.
- Support field filtering to avoid returning unnecessary data.
- Apply `http.MaxBytesReader` to request bodies.

## CI/CD Tooling for Compliance Evidence

```bash
# Static analysis (maps to ASD injection, credential, and config findings)
gosec -fmt sarif -out gosec.sarif ./...

# Vulnerability scanning (dependency hygiene)
govulncheck ./...

# Race condition detection
go test -race -count=1 ./...

# FIPS build verification
GOFIPS140=v1.0.0 go build -o myapp
```

Key gosec rules that map to STIG findings:

| gosec rule | What it detects | STIG relevance |
|---|---|---|
| G101 | Hardcoded credentials | V-222642 |
| G108 | Profiling endpoint exposed | V-206413, SRG-APP-000645 |
| G112 | Missing `ReadHeaderTimeout` | V-206410 |
| G201/G202 | SQL injection | SRG-APP-000447 |
| G204 | Command injection | V-222604 |
| G402 | TLS config issues | V-206439 |
| G404 | Insecure random | SRG-APP-000224 |

## STIG Applicability Filter

Some ASD STIG controls target SOAP/WS-Security/SAML assertion handling. If the Go service is a REST/JSON or gRPC API that does not implement these protocols directly, mark those controls as **Not Applicable** with rationale. The `references/controls.md` matrix includes applicability tags for filtering.

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/reference.md` | Go code patterns (TLS, mTLS, trusted proxy, audit logging, error handling, session hardening, rate limiting, token validation, API key management, CORS, security headers, HTTP method enforcement, host header validation), evidence artifact templates, FIPS configuration walkthrough | Needing implementation patterns, evidence artifact templates, or detailed Go code examples for any compliance theme above |
| `references/controls.md` | Full STIG control crosswalk matrix: API SRG + Web Server SRG + ASD STIG IDs mapped to implementation objectives, applicability tags, responsibility assignments, evidence requirements, and Go pattern references | Mapping findings to specific STIG control IDs, determining which controls apply to a given architecture, or generating a compliance report |
