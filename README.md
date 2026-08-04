# Symfony backend container

Backend-only Symfony container setup using:

- one multi-stage Dockerfile;
- one production-safe `compose.yaml`;
- Docker's automatic `compose.override.yaml` for development;
- explicit development and production PHP configuration;
- automated smoke, lifecycle and vulnerability tests.

No frontend or database service is included yet.

## Development

Start the development target:

```bash
docker compose up --build -d
```

Docker automatically merges `compose.override.yaml`, builds the `dev` target and mounts `./backend` into the container.

When `backend/` is empty, the development build prepares a Symfony 8.1 skeleton. The first container start copies that prepared project into `backend/` without downloading it again at runtime.

The development image includes Composer and Git. A hash marker is stored beside `vendor/`; when `composer.lock` changes, the next container start automatically runs `composer install` and updates the marker. This keeps the bind-mounted dependencies aligned with the lock file.

Check the service:

```bash
docker compose ps
docker compose exec backend php bin/console about
```

The backend listens only on:

```text
http://127.0.0.1:8000
```

The lightweight health endpoint executes through Apache and PHP:

```text
http://127.0.0.1:8000/healthz
```

A new Symfony skeleton has no homepage route, so HTTP 404 at `/` is expected.

Stop development:

```bash
docker compose down
```

## Production

Before building production, commit the Symfony application source and `backend/composer.lock`. Production intentionally refuses to resolve a new dependency graph or generate a new Symfony project.

Build and start only the production-safe base configuration:

```bash
docker compose -f compose.yaml up --build -d
```

The production image:

- installs only locked production dependencies;
- runs Symfony cache clear and warmup during the build;
- does not contain Composer, Git, compiler packages or development headers;
- keeps application source owned by `root`;
- grants the Apache worker write access only to Symfony's `var/` directory;
- enables production PHP defaults and explicit OPcache settings;
- suppresses PHP and Apache version disclosure and disables TRACE;
- has no source bind mount;
- exposes Apache only on host loopback;
- uses log rotation, an init process, graceful shutdown and `no-new-privileges`;
- uses a low-overhead Apache/PHP health check.

## Automated container tests

Run the same functional and lifecycle suites used by GitHub Actions:

```bash
sh tests/backend-smoke.sh
sh tests/backend-lifecycle.sh
```

The tests validate:

- Compose merging and production rejection of unlocked application source;
- development and production builds, startup, health and restarts;
- automatic development dependency reconciliation;
- Symfony boot, cache warmup, Composer validation and dependency audit;
- PHP extensions, environment-specific settings and OPcache behavior;
- Apache syntax, modules, headers, version suppression and TRACE blocking;
- root-owned production source with writable Symfony runtime directories;
- removal of Composer, Git, compilers, development headers and dev dependencies;
- production mounts, loopback exposure, init and `no-new-privileges`.

GitHub Actions also scans the final production image with Trivy and blocks fixable `HIGH` or `CRITICAL` operating-system and library vulnerabilities.

## Production boundary

The container foundation is tested for development and production operation. A real application still needs environment-specific configuration before deployment, including secrets, database credentials, trusted reverse proxies, CORS policy, database migrations, backups and an application-level readiness check for required external services.

## Future services

A future frontend container can join the `application` network and reach Symfony internally at:

```text
http://backend
```
