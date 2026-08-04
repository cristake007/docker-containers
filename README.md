# Symfony backend container

Backend-only Docker setup using one multi-stage Dockerfile, one production-safe Compose file, and Docker's automatic development override.

## Development

```bash
docker compose up --build -d
```

Docker automatically merges `compose.override.yaml` and builds the `dev` target. During the image build, Composer prepares a Symfony 8.1 skeleton. On the first container start, that prepared application is copied into the bind-mounted `./backend` directory without accessing Packagist at runtime.

Check the container:

```bash
docker compose ps
docker compose exec backend php bin/console about
```

The backend is available on `http://127.0.0.1:8000`. A new Symfony skeleton has no homepage route, so an HTTP 404 at `/` is expected until a route is added.

Stop development:

```bash
docker compose down
```

## Production

After the generated Symfony source and Composer lock file are committed, build only the production-safe base configuration:

```bash
docker compose -f compose.yaml up --build -d
```

This builds the `prod` target without the development source bind mount.

## Future frontend container

A future frontend service can join the `application` network and reach Symfony internally at:

```text
http://backend
```
