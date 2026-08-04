#!/bin/sh
set -eu

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$SCRIPT_DIRECTORY/test-env.sh"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-symfony-platform-diagnostic}"
COMPOSE="docker compose -p $PROJECT_NAME"

prepare_test_environment "$PROJECT_NAME"

cleanup() {
    $COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true
    remove_test_environment
}

trap cleanup EXIT INT TERM

if ! $COMPOSE up -d --build backend; then
    printf '%s\n' 'Platform startup failed. Container state:' >&2
    $COMPOSE ps -a >&2 || true
    printf '%s\n' 'Database, migration and backend logs:' >&2
    $COMPOSE logs --no-color database migrate backend >&2 || true
    exit 1
fi

printf '%s\n' 'Platform startup diagnostic passed.'
