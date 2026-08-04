#!/bin/sh
set -eu

PROJECT_NAME=symfony-backend-smoke
DEV_COMPOSE="docker compose -p $PROJECT_NAME"
PROD_COMPOSE="docker compose -p $PROJECT_NAME -f compose.yaml"

cleanup() {
    $DEV_COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

wait_for_http() {
    attempts=0
    while [ "$attempts" -lt 30 ]; do
        status="$(curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8000/ || true)"
        if [ "$status" = "404" ]; then
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    echo "Apache did not serve the Symfony skeleton." >&2
    return 1
}

$DEV_COMPOSE up -d --build
$DEV_COMPOSE exec -T backend php bin/console about --env=dev >/dev/null
wait_for_http
$DEV_COMPOSE down -v --remove-orphans

$PROD_COMPOSE up -d --build
$PROD_COMPOSE exec -T backend php bin/console about --env=prod >/dev/null
wait_for_http
$PROD_COMPOSE exec -T backend sh -lc '! command -v composer >/dev/null 2>&1'

printf '%s\n' 'Development and production smoke tests passed.'
