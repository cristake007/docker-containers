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
