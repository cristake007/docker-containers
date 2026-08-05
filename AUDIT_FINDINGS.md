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

### F-007 — The advertised task manager has no frontend task implementation

- Severity: High
- Files: `README.md`, `frontend/src/components/AuthenticatedApp.tsx`, `frontend/src/components/AppSidebar.tsx`, `frontend/src/api/auth.ts`, `frontend/.env.example`, `compose.override.yaml`
- Category: Functional completeness / architecture mismatch

The repository is presented as a task manager and the backend implements GraphQL task CRUD, but the frontend contains no GraphQL task client, task query, task form, task list, or task mutation. `VITE_GRAPHQL_URL` is configured but never consumed. After authentication every navigation item renders the same placeholder panel; changing sections only changes the heading.

Impact: the primary advertised application workflow is unavailable to users. The task domain can only be exercised manually through raw API requests or the shell smoke test, so the repository is not a complete full-stack task manager despite its documentation and configuration.

Recommendation: either implement the task vertical slice in the frontend and test it through the browser-facing client, or explicitly redefine the repository as an authentication/application-shell reference and remove unused task and GraphQL frontend claims/configuration.

### F-008 — API Platform browser assets are unreachable in the documented Nginx architecture

- Severity: Medium
- Files: `backend/config/packages/api_platform.yaml`, `backend/composer.json`, `docker/backend/Dockerfile`, `deploy/nginx/app.dev.conf.example`, `deploy/nginx/app.prod.conf.example`
- Category: Deployment correctness / static asset routing

Development enables GraphiQL, and Composer installs bundle assets under the backend application's `public/` directory. However, the application files exist only inside the PHP-FPM container, while host Nginx routes only `/api` to the front controller and routes every other path to Vite or the exported frontend. There is no shared mount, export step, or Nginx alias for backend public assets such as `/bundles/apiplatform/*`.

Impact: GraphiQL and other API Platform browser UIs can return HTML while their CSS/JavaScript requests are handled by the frontend and return 404 or `index.html`, producing broken styling and MIME-type failures. The current stack smoke test does not request these assets.

Recommendation: make an explicit architecture choice: disable browser UIs entirely, export/mount the required backend public assets to a host-readable location, or add an HTTP-serving layer that can serve the backend public directory. Add an asset request to CI so the chosen design is verified.

### F-009 — Frontend logout reports success even when the server rejects it

- Severity: Medium
- Files: `frontend/src/api/auth.ts`, `frontend/src/components/AuthenticatedApp.tsx`, `frontend/src/components/AuthenticatedApp.test.tsx`
- Category: Session correctness / error handling

`logout()` awaits `fetch()` but never checks `response.ok`. `AuthenticatedApp` therefore calls `onLoggedOut()` after any completed HTTP response, including 401, 403, 404, 500, or an invalid reverse-proxy response. Only a transport-level rejection prevents the local state change, and that rejection has no user-facing error handling.

Impact: the UI can show the login screen while the valid httpOnly JWT cookie remains in the browser. A refresh may silently authenticate the user again, and a user can reasonably believe a shared-device session was terminated when it was not.

Recommendation: require a successful response and verify the cookie-clearing contract before changing local authentication state. On failure, keep the authenticated UI state and show an actionable error. Add explicit non-2xx and network-failure tests.

### F-010 — Task collection queries are explicitly unbounded

- Severity: Medium
- File: `backend/src/Entity/Task.php`
- Category: Availability / query safety

The GraphQL `QueryCollection` sets `paginationEnabled: false`. Any authenticated account can create an unlimited number of tasks and then request the entire collection in one response. There is no resource-level cap or rate limit in the repository.

Impact: large accounts or automated abuse can force oversized database reads, object hydration, GraphQL serialization, memory use, and response payloads. Because registration is public and unthrottled, this is available to arbitrary remote accounts rather than only trusted operators.

Recommendation: restore pagination with a bounded maximum page size and add appropriate operation/rate limits. Keep collection sizes and GraphQL execution cost measurable.

### F-011 — Build and CI trust mutable third-party references

- Severity: Medium
- Files: `compose.yaml`, `docker/backend/Dockerfile`, `docker/frontend/Dockerfile`, `tests/stack-smoke.sh`, `.github/workflows/backend-container.yml`, `.github/workflows/frontend.yml`, `.github/workflows/stack-smoke.yml`
- Category: Supply-chain security / reproducibility

Runtime and build inputs use mutable tags such as `postgres:17-alpine`, `php:*`, `node:22-alpine`, `mlocati/php-extension-installer:2`, `composer:2.10.2`, and `nginx:alpine`. GitHub Actions are referenced by moving major tags such as `actions/checkout@v6` and `actions/setup-node@v4` rather than immutable commit SHAs.

Impact: the same source commit can build or execute different third-party code later without any repository change or review. A compromised or unexpectedly changed upstream tag can enter production images or CI with the repository's trust and credentials.

Recommendation: pin container images by digest and GitHub Actions by reviewed full commit SHA, then update them through an explicit dependency-update process.
