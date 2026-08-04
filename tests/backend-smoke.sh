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
    attempts=0

    while [ "$attempts" -lt 30 ]; do
        if $compose_command exec -T backend php -r '
            $socket = @fsockopen("127.0.0.1", 9000, $errorCode, $errorMessage, 1);
            exit(is_resource($socket) ? 0 : 1);
        ' >/dev/null 2>&1; then
            return 0
        fi

        attempts=$((attempts + 1))
        sleep 1
    done

    $compose_command logs backend >&2 || true
    echo "PHP-FPM did not become available on port 9000." >&2
    return 1
}

assert_no_published_ports() {
    compose_command="$1"
    container_id="$($compose_command ps -q backend)"

    if [ -n "$(docker port "$container_id")" ]; then
        echo "The PHP-FPM service must not publish a host port." >&2
        return 1
    fi
}

$DEV_COMPOSE config --quiet
$PROD_COMPOSE config --quiet

$DEV_COMPOSE up -d --build
wait_for_fpm "$DEV_COMPOSE"
assert_no_published_ports "$DEV_COMPOSE"
$DEV_COMPOSE exec -T backend sh -lc '
    set -eu
    test "$APP_ENV" = "dev"
    test "$APP_DEBUG" = "1"
    php-fpm -t
    php bin/console about --env=dev >/dev/null
    command -v composer >/dev/null
    command -v git >/dev/null
    ! command -v apache2 >/dev/null 2>&1
    ! command -v nginx >/dev/null 2>&1
    composer validate --strict --no-check-publish
    composer check-platform-reqs
    composer audit --locked --no-interaction
'
$DEV_COMPOSE down -v --remove-orphans

$PROD_COMPOSE up -d --build
wait_for_fpm "$PROD_COMPOSE"
assert_no_published_ports "$PROD_COMPOSE"
$PROD_COMPOSE exec -T backend sh -lc '
    set -eu
    test "$APP_ENV" = "prod"
    test "$APP_DEBUG" = "0"
    php-fpm -t
    php bin/console about --env=prod >/dev/null
    test "$(stat -c "%U" composer.json)" = "root"
    test "$(stat -c "%U" var)" = "www-data"
    ! command -v composer >/dev/null 2>&1
    ! command -v git >/dev/null 2>&1
    ! command -v apache2 >/dev/null 2>&1
    ! command -v nginx >/dev/null 2>&1
'

printf '%s\n' 'PHP-FPM development and production smoke tests passed.'
