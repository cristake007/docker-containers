# Full Project Audit Findings

- Repository: `cristake007/docker-containers`
- Audited base: `main`
- Audited commit: `fc4c17967e93ab06cdc728970b616ae2538c9435`
- Audit branch: `audit/full-project-2026-08-05`
- Started: 2026-08-05
- Completed: 2026-08-05
- Scope: every tracked file, with repeated security, correctness, maintainability, deployment, and test-coverage passes.

## Status

Completed. `main` remained at the audited commit through the final verification pass. No application file was modified; this audit branch adds only this report.

## Summary

| Severity | Count |
| --- | ---: |
| High | 3 |
| Medium | 11 |
| Low | 7 |
| **Confirmed total** | **21** |

One additional product/security ambiguity requires an owner decision.

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

### F-012 — A partial JWT keypair cannot self-heal and existing keys are not validated

- Severity: Medium
- Files: `docker/backend/entrypoint.sh`, `backend/config/packages/lexik_jwt_authentication.yaml`, `compose.yaml`
- Category: Authentication availability / key lifecycle

The entrypoint attempts key generation when either `private.pem` or `public.pem` is missing, but invokes `lexik:jwt:generate-keypair --skip-if-exists`. The exact locked Lexik JWT bundle version is 3.2.0; its command considers the pair to “already exist” when either file exists and returns success without creating the missing half. The following `chmod`/`chown` then encounters the absent file and aborts startup because the script uses `set -e`.

The entrypoint also treats any two existing files as valid. It does not verify that they parse, match one another, or that the configured passphrase can decrypt the private key.

Impact: an interrupted first boot, accidental deletion of one key, key corruption, a passphrase change without coordinated key rotation, or a mismatched restored volume can leave production unable to authenticate and unable to repair itself automatically. The failure message may point at file permissions rather than the underlying keypair state.

Recommendation: manage the keypair atomically. If either file is absent, fail with an explicit recovery instruction or regenerate both under an intentional rotation policy; never combine partial-pair detection with `--skip-if-exists`. Validate the complete pair and passphrase before starting PHP-FPM.

### F-013 — The supplied production Nginx configuration is not tested by CI

- Severity: Medium
- Files: `deploy/nginx/app.dev.conf.example`, `deploy/nginx/app.prod.conf.example`, `tests/stack-smoke.sh`, `.github/workflows/backend-container.yml`, `.github/workflows/stack-smoke.yml`
- Category: Verification gap / deployment correctness

No workflow path filter includes `deploy/nginx/**`. The stack smoke test creates a separate simplified Nginx configuration at runtime rather than loading or deriving from either checked-in example.

Impact: production routing and transport defects can be merged without running any relevant workflow. This is demonstrated by the current successful stack workflow despite the plaintext-HTTP production block and the missing API Platform asset route identified in F-003 and F-008.

Recommendation: make Nginx example changes trigger CI, syntax-test the actual checked-in configuration through a deterministic template step, and exercise the HTTP-to-HTTPS behavior plus every public route family that the examples claim to support.

### F-014 — Security-critical backend behavior lacks code-level automated tests

- Severity: Medium
- Files: `backend/composer.json`, `backend/src/**`, `frontend/src/components/AuthView.test.tsx`, `frontend/src/components/AuthenticatedApp.test.tsx`, `tests/backend-smoke.sh`, `tests/stack-smoke.sh`
- Category: Test coverage / regression risk

The repository has useful shell smoke tests, but no backend PHPUnit/API Platform functional test suite. Validators, processors, security expressions, the Doctrine ownership extension, registration edge cases, and key lifecycle behavior are not independently tested. Frontend tests cover mode switching and a successful navigation/logout path but omit API and network failures.

The shell smoke test does not cover empty production secrets, email case normalization, invalid-login throttling, unauthenticated GraphQL requests, another user's update attempt, logout failure, session-probe failure, API Platform assets, or the actual production Nginx file.

Impact: security and authorization behavior is concentrated in configuration and framework integration points where small changes can silently alter semantics. Happy-path CI can remain green while meaningful failure paths regress.

Recommendation: add focused backend functional tests for every public operation and authorization boundary, plus frontend failure-path tests. Keep the end-to-end shell smoke test as a separate integration layer rather than using it as the only proof.

### F-015 — Session probing treats outages and authentication failures as the same state

- Severity: Medium
- Files: `frontend/src/App.tsx`, `frontend/src/api/auth.ts`
- Category: Session correctness / resilience

`me()` returns `null` for every non-success HTTP status, including 500 and 502, rather than only for an unauthenticated response. A network rejection is not caught by `App`; the promise still reaches `finally`, removes the loading state, and can leave an unhandled rejection while rendering the login view.

Impact: a reverse-proxy or backend outage is presented as “logged out” even though a valid JWT cookie may still exist. Users may enter credentials repeatedly during an outage, and the application gives no retry or service-error state.

Recommendation: define a precise `/api/me` contract, distinguish unauthenticated from unavailable/error responses, catch transport failures, and render a retryable error state without discarding the known session state.

### F-016 — Sidebar persistence writes a cookie that is never read

- Severity: Low
- File: `frontend/src/components/ui/sidebar.tsx`
- Category: Dead behavior / unnecessary client state

The sidebar writes `sidebar_state` to `document.cookie` whenever it is toggled, but no repository code reads that cookie and `SidebarProvider` is always created with its default `defaultOpen=true`. Reloading therefore resets the sidebar despite the claimed persistence mechanism.

Impact: the feature does not work, and every request unnecessarily carries a client UI preference cookie. The cookie is also created without explicit `SameSite` or `Secure` attributes, although its value is not sensitive.

Recommendation: use local storage for this client-only preference, or intentionally read and apply the cookie. Remove the write if persistence is not required.

### F-017 — Task mutation ownership expressions fail open when prior state is absent

- Severity: Low
- File: `backend/src/Entity/Task.php`
- Category: Authorization hardening / ambiguous framework dependency

Update and delete authorize with `(previous_object === null or previous_object.getOwner() == user)`. The current Doctrine query extension prevents the observed cross-user path in the smoke test, so this is not a demonstrated bypass in the present execution path. However, the expression itself grants access when the framework does not provide a prior object, making authorization depend on an implicit lifecycle assumption and a second mechanism remaining correctly registered.

Impact: a processor/provider change, framework behavior change, or future operation that lacks `previous_object` can turn a defense-in-depth expression into a fail-open authorization rule.

Recommendation: make the mutation rule fail closed by requiring a non-null prior object owned by the current user, and add explicit cross-user update and delete tests.

### F-018 — Production GraphQL schema discovery is not explicitly restricted

- Severity: Low
- Files: `backend/config/packages/api_platform.yaml`, `backend/config/packages/security.yaml`
- Category: Information exposure / production hardening

GraphiQL is disabled when kernel debugging is off, but GraphQL introspection is not explicitly disabled or access-controlled in production. The general `/api` firewall authenticates opportunistically and operation-level rules protect data operations; there is no explicit production policy for schema discovery.

Impact: an unauthenticated client may enumerate the complete GraphQL schema, mutations, object names, and argument structure. This does not grant data access by itself, but it reduces discovery cost for attackers and conflicts with a least-information production posture when public schema discovery is unnecessary.

Recommendation: decide and document whether public introspection is intentional. Disable it in production or require suitable authentication if the schema is private.

### F-019 — The end-to-end test leaves JWT cookie jars in temporary storage

- Severity: Low
- File: `tests/stack-smoke.sh`
- Category: Test hygiene / credential handling

The script creates `ALICE_JAR` and `BOB_JAR` with `mktemp`, stores authenticated JWT cookies in them, and never removes those files in its cleanup function.

Impact: tokens remain on a developer or CI host until external temporary-file cleanup or runner destruction. The current tokens are short-lived test credentials, so the immediate severity is low, but secret-bearing test artifacts should not be deliberately abandoned.

Recommendation: create all temporary files under a private temporary directory with a restrictive `umask`, and remove the directory from the existing trap on every exit path.

### F-020 — Brand colors are duplicated as raw values across the component layer

- Severity: Low
- Files: `frontend/src/index.css`, `frontend/src/components/AppSidebar.tsx`, `frontend/src/components/AuthenticatedApp.tsx`, `frontend/src/components/NavUser.tsx`, `frontend/src/components/ui/sidebar.tsx`, `frontend/src/components/ui/tooltip.tsx`
- Category: Duplication / maintainability

The stylesheet defines semantic primary/destructive variables, but application and generated-style components repeatedly embed `#164194` and `#D41131` in long utility strings. The same hover, active, and icon color logic is duplicated in multiple menu items.

Impact: a brand adjustment requires coordinated edits across unrelated files and makes visual inconsistencies likely. Repeated utility fragments also obscure the actual interaction semantics.

Recommendation: express brand states through semantic theme tokens or reusable variants, then remove component-level literal colors and duplicated menu-state class strings.

### F-021 — The Vitest configuration is excluded from TypeScript project checking

- Severity: Low
- Files: `frontend/tsconfig.node.json`, `frontend/tsconfig.json`, `frontend/vitest.config.ts`
- Category: Build configuration / verification gap

`tsconfig.node.json` includes only `vite.config.ts`, and the root project references only the app and that node configuration. `npm run typecheck` therefore does not type-check `vitest.config.ts` as part of the configured TypeScript project.

Impact: invalid configuration API usage or Node-side type regressions in the test configuration can evade the dedicated type-check step and surface only when Vitest happens to execute the affected path.

Recommendation: include both Vite and Vitest configuration files in the node project, or create a shared configuration project that covers all TypeScript build/test tooling.

## Open product/security ambiguity

### A-001 — Public self-registration may conflict with the intended deployment model

- Files: `backend/src/Entity/User.php`, `backend/config/packages/security.yaml`, `frontend/src/components/AuthView.tsx`

Anyone reaching the application can create an account and immediately receives effective `ROLE_USER` access. There is no invitation, approval, email verification, domain restriction, activation state, or administrator gate.

This is correct for a public self-service task application, but it is a high-impact access-control defect if the intended product is private or internal. The repository does not state this decision clearly enough to resolve the ambiguity.

Required decision: explicitly classify the application as public self-registration or restricted membership, then enforce and test that policy. Registration abuse controls from F-005 remain necessary in either model.

## Prioritized remediation order

1. **Immediate:** F-003, F-001, and F-007. Prevent plaintext authentication, enforce real production secrets, and resolve whether this is a working task application or only an application-shell reference.
2. **Next security/correctness pass:** F-008, F-009, F-012, F-002, F-004, F-005, F-010, F-013, F-014, and F-015.
3. **Hardening and cleanup:** F-011 and the low-severity findings, after the runtime and product gaps above are resolved.
4. Resolve A-001 before choosing the final registration and deployment architecture.

## Verification performed

- Reviewed every one of the 86 tracked files at the audited commit, including generated lockfiles, shell scripts, workflows, Dockerfiles, Compose files, Symfony configuration/source, migrations, React source/tests, generated UI primitives, Nginx examples, and documentation.
- Repeated cross-file passes for security boundaries, authentication/session behavior, deployment architecture, configuration/documentation consistency, duplication, failure paths, and test coverage.
- Reviewed the exact locked dependency metadata and upstream Lexik JWT 3.2.0 key-generation behavior for F-012.
- Confirmed the Frontend and Stack smoke GitHub Actions succeeded on the audited commit. The latest Backend container workflow also succeeded on its most recent triggering commit immediately before it; the audited frontend-only commit did not trigger that path-filtered workflow.
- Existing CI success was treated as proof of the tested happy paths only, not as proof that untested production routing and failure paths are correct.
- A local checkout/test rerun was attempted, but the audit execution environment could not resolve GitHub for a clone/download. No local runtime result is claimed; dynamic evidence in this report comes from the repository's recorded GitHub Actions runs and source-level contract analysis.

## Scope boundary

This is a complete static audit of the tracked repository at the named commit plus a review of its recorded CI executions. It does not assess untracked deployment files, host Nginx configuration actually installed on a server, external secret storage, cloud/network controls, live database contents, or runtime infrastructure outside this repository.
