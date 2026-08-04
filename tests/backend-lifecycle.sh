#!/bin/sh
set -eu

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$SCRIPT_DIRECTORY/test-env.sh"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-symfony-backend-lifecycle}"
DEV_COMPOSE="docker compose -p $PROJECT_NAME"
PROD_COMPOSE="docker compose -p $PROJECT_NAME -f compose.yaml"

prepare_test_environment "$PROJECT_NAME"

cleanup() {
    $DEV_COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true
    remove_test_environment
}

wait_for_health() {
    compose_command="$1"
    service="$2"
    container_id="$($compose_command ps -q "$service")"

    if [ -z "$container_id" ]; then
        echo "$service container was not created." >&2
        return 1
    fi

    attempts=0
    while [ "$attempts" -lt 90 ]; do
        status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id")"

        case "$status" in
            healthy)
                return 0
                ;;
            unhealthy|exited|dead)
                if [ "$service" != "backend" ] || [ "$status" != "unhealthy" ]; then
                    $compose_command logs "$service" >&2 || true
                    return 1
                fi
                ;;
        esac

        attempts=$((attempts + 1))
        sleep 2
    done

    $compose_command logs "$service" >&2 || true
    echo "$service did not become healthy." >&2
    return 1
}

wait_for_unhealthy() {
    compose_command="$1"
    service="$2"
    container_id="$($compose_command ps -q "$service")"
    attempts=0

    while [ "$attempts" -lt 45 ]; do
        status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id")"
        if [ "$status" = "unhealthy" ]; then
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 2
    done

    echo "$service did not report its dependency failure." >&2
    return 1
}

assert_php_health_and_readiness() {
    compose_command="$1"

    $compose_command exec -T backend php -r '
        $healthHeaders = get_headers("http://127.0.0.1/healthz", true);
        $healthBody = file_get_contents("http://127.0.0.1/healthz");
        if ($healthBody !== "ok\n" || ($healthHeaders["X-Container-Health"] ?? null) !== "php") {
            fwrite(STDERR, "The health endpoint did not execute through PHP.\n");
            exit(1);
        }

        $readyHeaders = get_headers("http://127.0.0.1/readyz", true);
        $readyBody = file_get_contents("http://127.0.0.1/readyz");
        if ($readyBody !== "ready\n" || ($readyHeaders["X-Application-Readiness"] ?? null) !== "database") {
            fwrite(STDERR, "The database-backed readiness endpoint failed.\n");
            exit(1);
        }
    '
}

trap cleanup EXIT INT TERM

printf '%s\n' 'Starting development lifecycle test...'
$DEV_COMPOSE up -d --build backend
wait_for_health "$DEV_COMPOSE" database
wait_for_health "$DEV_COMPOSE" backend
assert_php_health_and_readiness "$DEV_COMPOSE"

$DEV_COMPOSE exec -T backend sh -lc '
    set -eu
    expected="$(sha256sum composer.lock | cut -d " " -f 1)"
    actual="$(cat vendor/.composer-lock.sha256)"
    test "$expected" = "$actual"
    printf "%s\n" stale-lock-marker > vendor/.composer-lock.sha256
'

printf '%s\n' 'Restarting development with a stale dependency marker...'
$DEV_COMPOSE restart backend
wait_for_health "$DEV_COMPOSE" backend
assert_php_health_and_readiness "$DEV_COMPOSE"

$DEV_COMPOSE exec -T backend sh -lc '
    set -eu
    expected="$(sha256sum composer.lock | cut -d " " -f 1)"
    actual="$(cat vendor/.composer-lock.sha256)"
    test "$expected" = "$actual"
'

$DEV_COMPOSE logs backend | grep -q 'Synchronizing development dependencies with composer.lock...'

printf '%s\n' 'Testing readiness during a database outage...'
$DEV_COMPOSE stop database
wait_for_unhealthy "$DEV_COMPOSE" backend
$DEV_COMPOSE start database
wait_for_health "$DEV_COMPOSE" database
wait_for_health "$DEV_COMPOSE" backend
assert_php_health_and_readiness "$DEV_COMPOSE"

$DEV_COMPOSE down -v --remove-orphans

printf '%s\n' 'Starting production lifecycle test...'
$PROD_COMPOSE up -d --build backend
wait_for_health "$PROD_COMPOSE" database
wait_for_health "$PROD_COMPOSE" backend
assert_php_health_and_readiness "$PROD_COMPOSE"
$PROD_COMPOSE exec -T backend test ! -e vendor/.composer-lock.sha256

printf '%s\n' 'Restarting production container...'
$PROD_COMPOSE restart backend
wait_for_health "$PROD_COMPOSE" backend
assert_php_health_and_readiness "$PROD_COMPOSE"
$PROD_COMPOSE exec -T backend php bin/console about --env=prod >/dev/null
$PROD_COMPOSE exec -T backend php bin/console doctrine:migrations:status --no-interaction >/dev/null

printf '%s\n' 'Development and production lifecycle tests passed.'
