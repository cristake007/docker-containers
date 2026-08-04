# Symfony backend container

Minimal Symfony 8.1 backend with separate development and production Docker targets.

## Included

- committed Symfony skeleton in `backend/`;
- PHP 8.5 with Apache;
- development image with Composer and Git;
- production image with locked `--no-dev` dependencies;
- one backend service;
- one small smoke test for both targets.

No database, frontend, migrations, backups, CORS layer, or generated application code is included.

## Development

```bash
docker compose up --build -d
```

Docker automatically applies `compose.override.yaml`, mounts `backend/`, and keeps `vendor/` and `var/` in Docker volumes.

The backend is available at `http://127.0.0.1:8000`. The Symfony skeleton has no homepage route, so HTTP 404 at `/` is expected.

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

The production image installs dependencies from the committed `backend/composer.lock`, excludes development packages, and does not contain Composer or Git.

Set real production environment variables outside the repository before deployment, including `APP_SECRET` when the application begins using features that require it.

## Test

```bash
sh tests/backend-smoke.sh
```

The smoke test starts both setups and verifies that Symfony boots in development and production.
