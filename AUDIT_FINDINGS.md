# Full Project Audit Findings

- Repository: `cristake007/docker-containers`
- Audited base: `main`
- Audit branch: `audit/full-project-2026-08-05`
- Started: 2026-08-05
- Scope: every tracked file, with repeated security, correctness, maintainability, deployment, and test-coverage passes.

## Status

Audit in progress. Findings are appended when confirmed rather than collected only at the end.

## Confirmed findings

### F-001 — Production secret validation can be bypassed with empty values

- Severity: High
- Files: `.env`, `compose.yaml`, `docker/backend/entrypoint.sh`
- Category: Security / production hardening

The production entrypoint rejects only the exact committed placeholder values. Explicitly empty `APP_SECRET` or `JWT_PASSPHRASE` values do not match those placeholders and therefore pass the production guard. `JWT_PASSPHRASE` being empty also skips key generation entirely. The guard similarly does not validate minimum strength or presence.

Impact: a deployment can start with an empty Symfony application secret, or proceed without usable JWT keys, depending on the surrounding state. This defeats the stated fail-closed production guarantee and can produce either insecure cryptographic behavior or a partially broken deployment.

Recommendation: require non-empty values first, then reject known placeholders, and apply a documented minimum-strength policy. Fail explicitly when JWT key files are absent and no valid passphrase is supplied.

### F-002 — Raw database credentials are interpolated into a URI

- Severity: Medium
- File: `compose.yaml`
- Category: Correctness / configuration safety

`DATABASE_URL` is assembled as `postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/...`. A valid password containing URI-reserved characters such as `@`, `:`, `/`, `?`, `#`, or `%` can be parsed incorrectly or change the meaning of the URL.

Impact: production deployments can fail unexpectedly when strong generated credentials contain reserved characters. In some cases the parsed host, path, query, or password can differ from the intended values.

Recommendation: avoid constructing a connection URI from unescaped components. Supply a fully encoded `DATABASE_URL` as one secret, or use separate supported database connection parameters.

### F-003 — Production Nginx serves authentication over plaintext HTTP

- Severity: High
- Files: `deploy/nginx/app.prod.conf.example`, `compose.yaml`, `backend/config/packages/lexik_jwt_authentication.yaml`
- Category: Transport security / deployment correctness

The production example uses one server block with both `listen 80` and `listen 443 ssl` and serves the full frontend and `/api` application on both listeners. There is no separate port-80 redirect to HTTPS.

Impact: users can submit registration and login credentials over plaintext HTTP. In addition, production sets the JWT cookie as `Secure`, so authentication performed through the HTTP endpoint produces a cookie the browser will not send back over HTTP, creating a confusing partially broken authentication path.

Recommendation: use a dedicated port-80 server block that performs an unconditional permanent redirect to the HTTPS origin. Serve the application only from the TLS server block, and enable HSTS after TLS is verified.

### F-004 — Email identity is case-sensitive and not canonicalized

- Severity: Medium
- Files: `backend/src/Entity/User.php`, `backend/config/packages/security.yaml`, `backend/migrations/Version20260804220234.php`
- Category: Authentication correctness / data integrity

Registration stores the submitted email verbatim, the database uniqueness constraint uses a normal case-sensitive PostgreSQL `VARCHAR`, and the user provider performs an exact email lookup. Addresses such as `Person@example.com` and `person@example.com` can therefore become separate accounts and login depends on reproducing the original casing.

Impact: duplicate identities, confusing login failures, and ambiguous account ownership or recovery behavior.

Recommendation: canonicalize email addresses consistently before validation, persistence, and lookup, and enforce case-insensitive uniqueness at the database level (for example with a normalized column or an appropriate case-insensitive index/type).

### F-005 — Public authentication endpoints have no throttling

- Severity: Medium
- Files: `backend/config/packages/security.yaml`, `backend/src/Entity/User.php`
- Category: Authentication security / abuse resistance

The login firewall has no `login_throttling` configuration and the public registration endpoint has no application-level rate limit or abuse control.

Impact: the application is unnecessarily exposed to password guessing, credential stuffing, and automated account creation. External reverse-proxy limiting may help, but it is neither present nor documented in the supplied production configuration.

Recommendation: enable Symfony login throttling, add explicit rate limiting for registration, and document any complementary Nginx limits.

### F-006 — Repository EditorConfig is misplaced and partly ineffective

- Severity: Low
- File: `backend/.editorconfig`
- Category: Maintainability / configuration correctness

The only `.editorconfig` is inside `backend/` and declares `root = true`. Its rule for `compose.yaml` and `compose.*.yaml` therefore cannot apply to the repository-level Compose files it names, and the frontend, Docker, workflow, Nginx, and test files have no shared repository formatting policy.

Recommendation: move the repository-wide rules to `/.editorconfig`; keep backend-specific overrides in a nested file only when they differ.
