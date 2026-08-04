#!/bin/sh
set -eu

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-symfony-backend-lifecycle}"
DEV_COMPOSE="docker compose -p $PROJECT_NAME"
PROD_COMPOSE="docker compose -p $PROJECT_NAME -f compose.yaml"

cleanup() {
    $DEV_COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true
}

wait_for_health() {
    compose_command="$1"
    container_id="$($compose_command ps -q backend)"

    if [ -z "$container_id" ]; then
        echo "Backend container was not created." >&2
        return 1
    fi

    attempts=0
    while [ "$attempts" -lt 60 ]; do
        status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id")"

        case "$status" in
            healthy)
                return 0
                ;;
            unhealthy|exited|dead)
                $compose_command logs backend >&2 || true
                return 1
                ;;
        esac

        attempts=$((attempts + 1))
        sleep 2
    done

    $compose_command logs backend >&2 || true
    echo "Backend did not become healthy." >&2
    return 1
}

assert_php_health_endpoint() {
    compose_command="$1"

    $compose_command exec -T backend php -r '
        $headers = get_headers("http://127.0.0.1/healthz", true);
        $body = file_get_contents("http://127.0.0.1/healthz");
        $marker = is_array($headers) ? ($headers["X-Container-Health"] ?? null) : null;

        if ($body !== "ok\n" || $marker !== "php") {
            fwrite(STDERR, "The health endpoint did not execute through PHP.\n");
            exit(1);
        }
    '
}

trap cleanup EXIT INT TERM

printf '%s\n' 'Starting development lifecycle test...'
$DEV_COMPOSE up -d --build backend
wait_for_health "$DEV_COMPOSE"
assert_php_health_endpoint "$DEV_COMPOSE"

$DEV_COMPOSE exec -T backend sh -lc '
    set -eu
    expected="$(sha256sum composer.lock | cut -d " " -f 1)"
    actual="$(cat vendor/.composer-lock.sha256)"
    test "$expected" = "$actual"
    printf "%s\n" stale-lock-marker > vendor/.composer-lock.sha256
'

printf '%s\n' 'Restarting development with a stale dependency marker...'
$DEV_COMPOSE restart backend
wait_for_health "$DEV_COMPOSE"
assert_php_health_endpoint "$DEV_COMPOSE"

$DEV_COMPOSE exec -T backend sh -lc '
    set -eu
    expected="$(sha256sum composer.lock | cut -d " " -f 1)"
    actual="$(cat vendor/.composer-lock.sha256)"
    test "$expected" = "$actual"
'

$DEV_COMPOSE logs backend | grep -q 'Synchronizing development dependencies with composer.lock...'
$DEV_COMPOSE down -v --remove-orphans

printf '%s\n' 'Starting production lifecycle test...'
$PROD_COMPOSE up -d --build backend
wait_for_health "$PROD_COMPOSE"
assert_php_health_endpoint "$PROD_COMPOSE"
$PROD_COMPOSE exec -T backend test ! -e vendor/.composer-lock.sha256

printf '%s\n' 'Restarting production container...'
$PROD_COMPOSE restart backend
wait_for_health "$PROD_COMPOSE"
assert_php_health_endpoint "$PROD_COMPOSE"
$PROD_COMPOSE exec -T backend php bin/console about --env=prod >/dev/null

printf '%s\n' 'Development and production lifecycle tests passed.'
