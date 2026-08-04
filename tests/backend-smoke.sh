#!/bin/sh
set -eu

PROJECT_NAME=symfony-backend-smoke
DEV_COMPOSE="docker compose -p $PROJECT_NAME"
PROD_COMPOSE="docker compose -p $PROJECT_NAME -f compose.yaml"

cleanup() {
    $DEV_COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

wait_for_fpm() {
    compose_command="$1"
    port="$($compose_command port backend 9000 | cut -d: -f2)"
    attempts=0

    while [ "$attempts" -lt 30 ]; do
        if nc -z 127.0.0.1 "$port" 2>/dev/null; then
            return 0
        fi

        attempts=$((attempts + 1))
        sleep 1
    done

    $compose_command logs backend >&2 || true
    echo "PHP-FPM did not become available on 127.0.0.1:$port." >&2
    return 1
}

assert_loopback_only_port() {
    compose_command="$1"
    service="$2"
    container_id="$($compose_command ps -q "$service")"
    published="$(docker port "$container_id")"

    case "$published" in
        *"9000/tcp -> 127.0.0.1:9000"*) ;;
        *)
            echo "$service must publish 9000 on 127.0.0.1 only, got: $published" >&2
            return 1
            ;;
    esac
    case "$published" in
        *"0.0.0.0"*|*"[::]"*)
            echo "$service must not publish 9000 on a non-loopback address, got: $published" >&2
            return 1
            ;;
    esac
}

# Real (test-only) secrets for the prod run: prod refuses to boot with the
# placeholder values from the committed root .env (see entrypoint.sh), so
# reusing them here would be testing the wrong thing.
export APP_SECRET=ci-smoke-test-app-secret
export JWT_PASSPHRASE=ci-smoke-test-jwt-passphrase
export POSTGRES_PASSWORD=ci-smoke-test-postgres-password
export CORS_ALLOW_ORIGIN='^https://ci-smoke-test\.example$'

$DEV_COMPOSE config --quiet
$PROD_COMPOSE config --quiet

assert_prod_rejects_placeholder_secrets() {
    output="$(APP_SECRET=dev-insecure-app-secret-do-not-use-in-prod $PROD_COMPOSE up backend 2>&1 || true)"
    $PROD_COMPOSE rm -f backend >/dev/null 2>&1 || true
    case "$output" in
        *"Refusing to start"*) ;;
        *)
            echo "prod backend must refuse to start with a placeholder APP_SECRET" >&2
            printf '%s\n' "$output" >&2
            return 1
            ;;
    esac
}

$DEV_COMPOSE up -d --build backend db
wait_for_fpm "$DEV_COMPOSE"
$DEV_COMPOSE exec -T backend sh -lc '
    set -eu
    test "$APP_ENV" = "dev"
    test "$APP_DEBUG" = "1"
    php-fpm -t
    php -m | grep -qi pdo_pgsql
    php -m | grep -qi intl
    php bin/console about --env=dev >/dev/null
    php bin/console doctrine:migrations:migrate --no-interaction --env=dev >/dev/null
    php bin/console doctrine:schema:validate --env=dev
    command -v composer >/dev/null
    command -v git >/dev/null
    ! command -v apache2 >/dev/null 2>&1
    ! command -v nginx >/dev/null 2>&1
    composer validate --strict --no-check-publish
    composer check-platform-reqs
    composer audit --locked --no-interaction
'
$DEV_COMPOSE down -v --remove-orphans

$PROD_COMPOSE up -d --build db
assert_prod_rejects_placeholder_secrets
$PROD_COMPOSE up -d --build
wait_for_fpm "$PROD_COMPOSE"
assert_loopback_only_port "$PROD_COMPOSE" backend
$PROD_COMPOSE exec -T backend sh -lc '
    set -eu
    test "$APP_ENV" = "prod"
    test "$APP_DEBUG" = "0"
    php-fpm -t
    php -m | grep -qi pdo_pgsql
    php -m | grep -qi intl
    php bin/console about --env=prod >/dev/null
    php bin/console doctrine:migrations:migrate --no-interaction --env=prod >/dev/null
    php bin/console doctrine:schema:validate --env=prod
    test "$(stat -c "%U" composer.json)" = "root"
    test "$(stat -c "%U" var)" = "www-data"
    test "$(stat -c "%U" config/jwt)" = "www-data"
    ! command -v composer >/dev/null 2>&1
    ! command -v git >/dev/null 2>&1
    ! command -v apache2 >/dev/null 2>&1
    ! command -v nginx >/dev/null 2>&1
'

printf '%s\n' 'PHP-FPM development and production smoke tests passed.'
