# Symfony PHP-FPM backend

Minimal Symfony 8.1 backend with separate development and production PHP-FPM images.

## Included

- committed Symfony skeleton in `backend/`;
- PHP 8.5 FPM;
- development image with Composer and Git;
- production image with locked `--no-dev` dependencies;
- one backend service;
- one smoke test for both targets.

There is no Apache, Nginx, database, frontend, migration service, backup service, CORS layer, or application-specific infrastructure.

PHP-FPM is not an HTTP server. The container exposes FastCGI port `9000` only to other containers on the Compose network and does not publish a host port. A reverse proxy or web server can be added separately when the complete application stack requires one.

## Development

```bash
docker compose up --build -d
```

Docker automatically applies `compose.override.yaml`, mounts `backend/`, and keeps `vendor/` and `var/` in Docker volumes.

Useful commands:

```bash
docker compose exec backend php bin/console about
docker compose exec backend composer require vendor/package
docker compose logs -f backend
```

After changing `composer.json` or `composer.lock`, update the development dependency volume:

```bash
docker compose run --rm backend composer install
```

Stop development:

```bash
docker compose down
```

## Production

```bash
docker compose -f compose.yaml up --build -d
```

The production image:

- runs PHP-FPM only;
- installs dependencies from the committed `backend/composer.lock`;
- excludes development dependencies;
- validates Composer metadata and platform requirements during the build;
- audits locked PHP dependencies during the build;
- uses authoritative Composer autoloading;
- clears the Symfony production cache during the build;
- contains neither Composer nor Git;
- keeps application source owned by `root` and Symfony's `var/` directory writable by `www-data`;
- publishes no host port.

Set real production environment variables outside the repository, including a secure `APP_SECRET` when the application uses features that require it.

## Test

```bash
sh tests/backend-smoke.sh
```

The smoke test builds both targets, verifies Symfony and PHP-FPM startup, checks the internal FastCGI socket, confirms that no host port is published, validates Composer dependencies, and confirms that Apache and Nginx are absent.
