# Symfony backend container

Backend-only Symfony container setup using:

- one multi-stage Dockerfile;
- one production-safe `compose.yaml`;
- Docker's automatic `compose.override.yaml` for development;
- explicit development and production PHP configuration;
- automated smoke tests for both images.

No frontend or database service is included yet.

## Development

Start the development target:

```bash
docker compose up --build -d
```

Docker automatically merges `compose.override.yaml`, builds the `dev` target and mounts `./backend` into the container.

When `backend/` is empty, the development build prepares a Symfony 8.1 skeleton. The first container start copies that prepared project into `backend/`. Composer does not download the project during container startup.

Check the service:

```bash
docker compose ps
docker compose exec backend php bin/console about
```

The backend listens only on:

```text
http://127.0.0.1:8000
```

The container health endpoint is:

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
- does not contain Composer, Git or compiler packages;
- keeps application source owned by `root`;
- grants the Apache worker write access only to Symfony's `var/` directory;
- enables production PHP defaults and explicit OPcache settings;
- suppresses PHP and Apache version disclosure;
- has no source bind mount;
- exposes Apache only on host loopback;
- uses log rotation, an init process and `no-new-privileges`.

## Automated container tests

Run the same development and production smoke suite used by GitHub Actions:

```bash
sh tests/backend-smoke.sh
```

The suite validates Compose merging, unlocked-production rejection, both image builds, container health, Symfony boot, Composer validation and audit, PHP extensions and settings, Apache configuration, HTTP headers, permissions, production dependency separation, removed build tools, mounts and container security options.

## Future services and application configuration

A future frontend container can join the `application` network and reach Symfony internally at:

```text
http://backend
```

Database credentials, Symfony secrets, trusted reverse proxies, CORS policy, database migrations and application-specific readiness checks must be added when those services and application requirements are introduced.
