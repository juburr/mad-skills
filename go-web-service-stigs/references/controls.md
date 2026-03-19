# STIG Control Crosswalk Matrix

Maps DISA STIG control IDs across three sources to implementation objectives for Go web services. Use this matrix to identify all control IDs implicated by a finding, determine responsibility, and verify applicability.

## How to Use This Matrix

1. **During review**: when a compliance gap is found, look up the implementation objective to find all related control IDs across documents.
2. **For reporting**: cite all implicated IDs from the "Control IDs" column.
3. **For filtering**: use the "Applies when" column to determine if a control is in scope for the service architecture.
4. **For delegation**: use the "Resp." column to determine who must implement the fix.

## Responsibility Key

| Code | Meaning |
|---|---|
| **APP** | Go service code and configuration |
| **GW/EDGE** | API gateway, ingress controller, WAF, load balancer |
| **SHARED** | Both app and edge must cooperate |
| **PLATFORM** | Infrastructure: K8s, Vault, SIEM, HSM, IdP |

## Applicability Tags

| Tag | Meaning |
|---|---|
| **Always** | Applies to every Go web service |
| **TLS-App** | Service terminates TLS itself |
| **TLS-Edge** | TLS terminated at gateway/LB |
| **Tokens** | JWT/OAuth2 bearer tokens used |
| **Cookies** | Browser cookie-based sessions |
| **APIKeys** | API key authentication supported |
| **DB** | Service queries a database |
| **CORS** | Browser cross-origin clients |
| **Cache** | Caching of sensitive or policy data |
| **Cmd** | Service triggers privileged/remote commands |
| **GW** | Mandated API gateway in architecture |
| **FIPS** | FIPS-mandated deployment environment |
| **Issuer** | Service issues tokens/assertions (IdP role) |

---

## Matrix: TLS and Transport Security

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Encrypt data in transit | API: SRG-APP-000014-API-000020, Web: V-206439 | Always | SHARED | No plaintext listener beyond localhost; HTTPS-only or behind TLS ingress | TLS config source; gateway policy; TLS scan |
| Use TLS 1.2 minimum | API: SRG-APP-000439-API-001010, Web: V-206439 | Always | SHARED | `MinVersion: tls.VersionTLS12`; no legacy SSL | TLS scan showing TLS 1.2/1.3 only |
| FIPS-approved cipher suites | API: SRG-APP-000630-API-001375 | FIPS | SHARED | NIST SP 800-52 Rev 2 suites; `GODEBUG=fips140=on` | Build logs; FIPS verification log |
| Remove export/weak ciphers | Web: V-206440 | Always | SHARED | No RC4, 3DES, export suites | TLS scan |
| Disable HTTP/1.x downgrade | Web: V-264363 | Always | SHARED | Validate protocol version at edge | Ingress config |

## Matrix: Authentication and Authorization

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Enforce approved authorizations | API: SRG-APP-000033-API-000070, Web: V-206356 | Always | SHARED | Centralized authz middleware; per-route scope/role checks; deny-by-default | Authz design doc; route table; tests |
| Restrict privileged features | API: SRG-APP-000340-API-000675 | Always | APP | Admin routes require elevated roles; log all privilege access attempts | Authz tests; audit logs |
| Require periodic reauthentication | API: SRG-APP-000389-API-000820 | Tokens | SHARED | Enforce max `auth_time` age; step-up auth for high-risk operations | Token policy docs |
| Use approved enterprise ICAM | API: SRG-APP-000148-API-000255 | Always | PLATFORM+APP | Validate tokens from ICAM-approved IdP; no local auth bypass | Auth architecture doc |
| Limit invalid logon attempts | ASD: V-222432 | Always | APP/PLATFORM | If local auth: enforce lockout/throttle (3 attempts in 15 min) | IdP policy or throttle config |
| Fail to secure state | ASD: V-222585 | Always | APP | Fail closed on auth errors; deny on dependency outage | Unit tests for deny-on-error |

## Matrix: Audit Logging

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Generate audit logs | Web: V-206357 | Always | APP | Logs for startup/shutdown, access, authentication; action name / event type in audit records | Log samples; log schema |
| Log when (date and time) | Web: V-206360 | Always | APP | UTC timestamp in every audit record | Log samples |
| Use system clock for timestamps | Web: V-206367 | Always | PLATFORM+APP | Timestamps from internal system clock; UTC or local with UTC offset | NTP config; log samples |
| Log where in server | Web: V-206361 | Always | APP | Component/handler name in audit records | Log schema |
| Log source of event | Web: V-206362 | Always | APP | Source IP and identifiers in audit records | Log samples |
| Log client IP (behind proxy) | Web: V-206363 | Always | APP | Client IP via trusted-proxy extraction, not proxy IP | Trusted proxy config; log samples |
| Log outcome (success/failure) | Web: V-206364 | Always | APP | Success/failure status in every audit record | Log samples |
| Log identity | Web: V-206365 | Always | APP | Actor identity (user/service/key) in audit records | Log samples |
| Alert on logging failure | Web: V-206366 | Always | PLATFORM+APP | Logging mechanism alerts ISSO and SA on processing failure | SIEM health alerts; watchdog config |
| Restrict log access | Web: V-206368 | Always | PLATFORM | Log files accessible only by privileged users | File permission evidence |
| Protect logs from modification | Web: V-206369 | Always | PLATFORM | Immutable log storage; access controls | SIEM config; access policies |
| Protect logs from deletion | Web: V-206370 | Always | PLATFORM | Log retention policies; access controls | Retention config; access policies |
| Back up logs | Web: V-206371 | Always | PLATFORM | Log backup to separate system or media | Backup evidence |
| Central logging integration | Web: V-206423 | Always | PLATFORM+APP | Ship to organizational SIEM | SIEM integration config |
| Log storage threshold alert | Web: V-206424 | Always | PLATFORM | Alert ISSO/SA at 75% log storage capacity | Alert config; threshold evidence |
| Do not log sensitive data | ASD: V-222444 | Always | APP | Redact tokens, passwords, keys, PII, session IDs | Redaction logic; log samples |
| Audit event type | API: SRG-APP-000095-API-001745 | Always | APP | Structured events with event_type/action field | Log schema |
| Audit authN/Z info | API: SRG-APP-000095-API-001765 | Always | APP | Log auth result, principal, scopes (not raw tokens) | Log samples |
| Audit exceptions/errors | API: SRG-APP-000095-API-001775 | Always | APP | Central error handler logs error class + correlation ID | Error log samples |
| Audit execution time | API: SRG-APP-000095-API-001785 | Always | APP | Latency metrics emitted per request; route labels | Metrics dashboard |
| Audit request/response details | API: SRG-APP-000095-API-001795 | Always | APP | Method, path, status, duration, client IP (via trusted proxy) | Log samples |
| Audit privileged access attempts | API: SRG-APP-000091-API-001730 | Always | APP | Log privileged actions with full audit context | Audit log samples |
| Monitor/alerts | API: SRG-APP-000089-API-000120 | Always | PLATFORM+APP | Metrics (latency, errors, rate); alerts for spikes | Dashboards; alert rules |
| Audit records for data access | ASD: V-222453 | Always | APP | Audit reads/writes for sensitive data categories | Log samples |
| Audit privilege modifications | ASD: V-222454 | Always | APP | Audit admin/role changes | Log samples |
| Audit security object changes | ASD: V-222455 | Always | APP | Audit changes to policies/roles | Log samples |

## Matrix: Input Validation and Injection Prevention

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Parameterized queries | API: SRG-APP-000447-API-001030 | DB | APP | No SQL string concatenation; use bound parameters | Code samples; gosec G201/G202 |
| Server-side input validation | API: SRG-APP-000447-API-001035, Web: V-206411 | Always | APP | Validate type, range, length, charset on all inputs | Validation tests |
| Protect from command injection | ASD: V-222604 | Always | APP | No `os/exec` with user input; fixed binary + allowlisted args | Code review; gosec G204 |
| Canonicalization safety | ASD: V-222605 | Always | APP | Normalize/decode before authz; consistent path handling | Tests |
| Encode outputs | API: SRG-APP-000516-API-001295 | Always | APP | JSON encoding; HTML template escaping; no reflection | Tests |
| Use WAF | API: SRG-APP-000516-API-001305 | Always | GW/EDGE | App still validates input independently | WAF policy evidence |

## Matrix: Error Handling and Information Disclosure

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| No sensitive data in errors | API: SRG-APP-000266-API-000535, ASD: V-222600 | Always | APP | Generic errors; no stack traces, SQL, paths to client | Negative tests |
| Minimize error detail | Web: V-206413 | Always | APP | No identity, paths, or module names in errors | Response samples |
| Disable debugging/traces | Web: V-206413 | Always | APP | No pprof, expvar, debug endpoints on public port | Config; route inventory |
| Fail to secure state | ASD: V-222585 | Always | APP | Fail closed on init/shutdown/abort; safe defaults | Tests; startup logic |

## Matrix: Secrets Management

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| No embedded credentials | ASD: V-222642 | Always | APP | No passwords/keys/tokens in source, configs, CI files | gosec G101; secret scan |
| Encrypt data at rest | Web: V-206408 | Always | PLATFORM | KMS/Vault for sensitive storage | Storage encryption evidence |
| Protect crypto keys for tokens | API: SRG-APP-000965-API-001655 | Tokens | PLATFORM | Keys loaded from secure store; no keys in repo | Key management docs |
| Protect private signing keys | API: SRG-APP-000970-API-001660 | Tokens | PLATFORM | HSM or Vault; rotation mechanism; least privilege | Key custody docs |

## Matrix: Session Management

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Server-side session management | Web: V-206352 | Cookies | APP | Session state managed server-side | Session implementation |
| System-generated session IDs | Web: V-206398 | Cookies | APP | IDs from `crypto/rand`; never accept client-provided | Session ID generation code |
| Session ID entropy (FIPS RNG) | Web: V-206431 | Cookies | APP/PLATFORM | 256-bit minimum; CSPRNG; FIPS RNG if mandated | Generation code; FIPS evidence |
| Absolute timeout <= 8 hours | Web: V-206414 | Cookies | APP | `MaxAge` or session store enforces max 8 hours | Config evidence |
| Inactivity timeout | Web: V-206415 | Cookies | APP | Idle timeout enforced in session store (5/10/20 min per risk level) | Config evidence |
| Invalidate on logout | Web: V-206397, ASD: V-222578 | Cookies | APP | Logout clears server-side state; rotates ID | Tests |
| No session IDs in URLs | ASD: V-222581 | Cookies | APP | Cookie-only transport | Code review |
| No session ID reuse | ASD: V-222582 | Cookies | APP | Rotate ID on authentication | Tests |
| Do not expose session IDs | ASD: V-222577 | Cookies | APP | Not in logs, URLs, or error messages | Log review |
| CSRF protection | ASD: V-222603 | Cookies | APP | CSRF tokens or SameSite cookies | Tests |
| Cookie encryption (Secure flag) | Web: V-206435 | Cookies | APP | `Secure: true` on session cookies | Response headers |
| HttpOnly cookies | Web: V-206438 | Cookies | APP | `HttpOnly: true` on session cookies | Response headers |
| No cookie compression with secrets | Web: V-206437 | Cookies | APP/GW | Avoid compression side-channels | Config evidence |
| Consistent inbound IP | Web: V-264361 | Cookies | APP | Policy-sensitive; may need compensating controls | Architecture doc |

## Matrix: Token Security

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Validate token claims | API: SRG-APP-000400-API-000850 | Tokens | APP | Validate iss/aud/exp/nbf; reject alg=none; verify signature | Token validation tests |
| Audience-restrict tokens | API: SRG-APP-000441-API-001020 | Tokens | APP | `aud` must contain this API | Tests |
| Access tokens expire | API: SRG-APP-000400-API-000860 | Tokens | PLATFORM+APP | Validate `exp`; enforce max TTL if policy requires | Token policy docs |
| Refresh tokens expire | API: SRG-APP-000400-API-000865 | Tokens | PLATFORM+APP | Enforce refresh token TTL and rotation | Token policy |
| Time-restrict access tokens | API: SRG-APP-001025-API-001715 | Tokens | PLATFORM+APP | Enforce max TTL; reject excessive `exp` | Tests |
| Protect session IDs via encryption | API: SRG-APP-000219-API-000460 | Tokens/Cookies | SHARED | No tokens in URLs; TLS everywhere | Architecture doc |
| Do not return internal tokens | API: SRG-APP-000400-API-000855 | Tokens | APP | Never echo Authorization headers; sanitize responses | Tests; code review |
| Replay-resistant privileged auth | ASD: V-222530 | Tokens | APP | Nonce/jti tracking; short-lived privileged tokens; refresh rotation | Auth flow design |
| FIPS-validated token signatures | API: SRG-APP-000630-API-001375 | FIPS+Tokens | PLATFORM+APP | Approved algorithms; FIPS module for signing | CMVP evidence |

## Matrix: API Key Management

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| FIPS-validated RNG for key generation | API: SRG-APP-000224-API-000475 | APIKeys | PLATFORM+APP | `crypto/rand`; FIPS module if mandated | Key generation code; FIPS evidence |
| FIPS-validated encryption/hashing for keys | API: SRG-APP-000231-API-000490 | APIKeys | PLATFORM+APP | Store hashed only; never plaintext | Storage design |
| Protected key storage | API: SRG-APP-000915-API-001610 | APIKeys | PLATFORM+APP | Keys not in repo/configmaps; Vault/HSM/encrypted DB | Storage architecture |
| Usage restrictions on keys | API: SRG-APP-000141-API-000240 | APIKeys | SHARED | Scope to endpoints/methods/env; least privilege | Key policy docs |
| Monitor key usage anomalies | API: SRG-APP-000095-API-001740 | APIKeys | PLATFORM+APP | Per-key usage metrics (hashed key ID) | Metrics; alert definitions |

## Matrix: Rate Limiting and DoS Protection

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Employ throttling | API: SRG-APP-000247-API-000520 | Always | SHARED | App-level and/or gateway throttle; return 429 | Rate limit config |
| Per-client rate limits | API: SRG-APP-000247-API-000870 | Always | SHARED | Client identified by key/token/IP; per-client buckets | Rate limit plan |
| Audit rate-limit events (app) | API: SRG-APP-000095-API-001750 | Always | APP | Log when throttle triggers (not every request) | Event log samples |
| Audit rate-limit events (gateway) | API: SRG-APP-000095-API-001755 | GW | GW/EDGE | Gateway rate-limit logging enabled | Gateway logs |
| Limit simultaneous sessions | Web: V-206350 | Always | SHARED | Connection limits, per-client concurrency caps, worker pool bounds | Gateway config; load test results; server config |
| Restrict DoS attacks | Web: V-206410 | Always | SHARED | Timeouts, input character set restrictions, body size limits | Server config; gateway config |

## Matrix: Attack Surface Reduction

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Only necessary services | Web: V-206375 | Always | APP | No unused endpoints, features, or sample content (Swagger UI, demo endpoints) unless access-controlled | Route inventory; deployment config |
| Not a proxy server | Web: V-206376 | Always | APP | Web server does not also function as a proxy server; remove all proxy modules/config | Architecture doc |
| Disable unnecessary API services | API: SRG-APP-000645-API-001385 | Always | APP+GW | Remove legacy/unused routes; disable non-secure features | Route inventory |
| Limit endpoint exposure | API: SRG-APP-000141-API-000245 | Always | SHARED | No admin/debug endpoints on public interface | Network policy; route table |
| Disable WebDAV | Web: V-206383 | Always | APP | Not applicable to Go unless explicitly implemented | N/A for pure API services |
| No directory listings | Web: V-206412 | Always | APP | Do not serve directory listings on missing pages | Config; tests |
| Restrict data volume | API: SRG-APP-000439-API-001005 | Always | APP | Pagination defaults; max page size; field filtering | API docs showing limits |
| Document all API elements | API: SRG-APP-000098-API-000145 | Always | APP | OpenAPI/Swagger maintained and in sync with routes | OpenAPI spec |

## Matrix: CORS

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Explicit allowed origins | API: SRG-APP-000251-API-000525 | CORS | APP/GW | Allowlist origins; no `*` with credentials; per-env config | CORS config |

## Matrix: Caching

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Encrypt cached sensitive data | API: SRG-APP-000231-API-000495 | Cache | SHARED | Encryption-at-rest for cache; or avoid caching sensitive data | Cache policy doc |
| Cache invalidation mechanism | API: SRG-APP-000400-API-000845 | Cache | APP | Versioned cache keys; explicit invalidation hooks | Cache invalidation doc |

## Matrix: Resilience

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Circuit breaker pattern | API: SRG-APP-000945-API-001635 | Always | APP | Outbound calls use timeouts + breaker; prevent cascading failure | Resilience tests |

## Matrix: Build Integrity

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Cryptographic hash of artifacts | ASD: V-222645 | Always | PLATFORM | Signed builds; SBOM; integrity verification | Build pipeline config; SBOM |

## Matrix: Gateway Requirements

| Implementation Objective | Control IDs | Applies | Resp. | Code Review Checks | Evidence |
|---|---|---|---|---|---|
| Clients route through gateway | API: SRG-APP-000419-API-000945 | GW | PLATFORM/GW | App rejects direct access (network policy) | Arch diagram; security groups |
| API must use a gateway | API: SRG-APP-000435-API-000995 | Always | PLATFORM/GW | App validates trusted-hop headers from gateway only | Gateway policy |
| Gateway audits privileged access | API: SRG-APP-000091-API-001725 | GW | GW/EDGE | Request-id/user-id propagated to gateway logs | Gateway logs + SIEM |
| Gateway audits event type | API: SRG-APP-000095-API-001735 | GW | GW/EDGE | Gateway log includes event type | Gateway log format |
| Gateway audits rate limiting | API: SRG-APP-000095-API-001755 | GW | GW/EDGE | Gateway rate-limit logging enabled | Gateway logs |
| Gateway audits authN/Z | API: SRG-APP-000095-API-001760 | GW | GW/EDGE | Gateway logs principal and auth decision | Gateway logs |
| Gateway audits exceptions | API: SRG-APP-000095-API-001770 | GW | GW/EDGE | Error logging enabled at gateway | Gateway logs |
| Gateway audits latency | API: SRG-APP-000095-API-001780 | GW | GW/EDGE | Gateway latency metrics/logging | Metrics dashboard |
| Gateway audits req/resp details | API: SRG-APP-000095-API-001790 | GW | GW/EDGE | Request metadata logged; secrets avoided | Gateway log fields |

## Matrix: Token Issuance (IdP Role Only)

These controls apply only if the Go service acts as a token issuer (identity provider). Mark **Not Applicable** if the service only validates tokens issued by an external IdP.

| Implementation Objective | Control IDs | Applies | Resp. | Evidence |
|---|---|---|---|---|
| Restrict who generates assertions | API: SRG-APP-000975-API-001665 | Issuer | PLATFORM+APP | Component boundary doc |
| Issue assertions per I&A policy | API: SRG-APP-000980-API-001670 | Issuer | PLATFORM | IdP policy docs |
| Refresh assertions per policy | API: SRG-APP-000985-API-001675 | Issuer | PLATFORM | Policy docs |
| Revoke assertions per policy | API: SRG-APP-000990-API-001680 | Issuer | PLATFORM | Revocation procedure |
| Time-restrict assertions | API: SRG-APP-000995-API-001685 | Issuer | PLATFORM | TTL configs |
| Audience-restrict assertions | API: SRG-APP-001000-API-001690 | Issuer | PLATFORM | Audience configs |
| Generate access tokens per policy | API: SRG-APP-001005-API-001695 | Issuer | PLATFORM | IdP policies |
| Issue access tokens per policy | API: SRG-APP-001010-API-001700 | Issuer | PLATFORM | IdP policies |
| Refresh access tokens per policy | API: SRG-APP-001015-API-001705 | Issuer | PLATFORM | IdP policies |
| Revoke access tokens per policy | API: SRG-APP-001020-API-001710 | Issuer | PLATFORM | Token revocation procedure |

## Not Applicable Controls

The following ASD STIG control families typically do not apply to REST/JSON or gRPC Go services. Mark as **Not Applicable** with rationale:

| Control Family | Rationale |
|---|---|
| WS-Security timestamp controls | SOAP/WS-Security not implemented |
| SAML assertion timing (NotBefore/NotOnOrAfter) | SAML assertions not processed by this service |
| SAML OneTimeUse/SubjectConfirmation | SAML not implemented |
| WebDAV restrictions (V-206383) | WebDAV not implemented in Go API services |
| Static type system requirement (SRG-APP-000516-API-001300) | Go is statically typed; inherently satisfied |
