#!/bin/sh
set -eu

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$SCRIPT_DIRECTORY/test-env.sh"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-symfony-database-backup}"
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
    attempts=0

    while [ "$attempts" -lt 90 ]; do
        status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id")"
        case "$status" in
            healthy)
                return 0
                ;;
            unhealthy|exited|dead)
                $compose_command logs "$service" >&2 || true
                return 1
                ;;
        esac
        attempts=$((attempts + 1))
        sleep 2
    done

    echo "$service did not become healthy." >&2
    return 1
}

trap cleanup EXIT INT TERM

if [ ! -f backend/composer.lock ]; then
    printf '%s\n' 'Bootstrapping the development application for backup tests...'
    $DEV_COMPOSE up -d --build backend
    wait_for_health "$DEV_COMPOSE" database
    wait_for_health "$DEV_COMPOSE" backend
    $DEV_COMPOSE down -v --remove-orphans
fi

printf '%s\n' 'Starting production database and backup service...'
$PROD_COMPOSE up -d --build database-backup
wait_for_health "$PROD_COMPOSE" database

migration_container="$($PROD_COMPOSE ps -a -q migrate)"
test -n "$migration_container"
test "$(docker inspect --format '{{.State.ExitCode}}' "$migration_container")" = "0"

backup_container="$($PROD_COMPOSE ps -q database-backup)"
test -n "$backup_container"
test "$(docker inspect --format '{{.Config.User}}' "$backup_container")" = "postgres"
test "$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$backup_container")" = "true"
printf '%s' "$(docker inspect --format '{{json .HostConfig.SecurityOpt}}' "$backup_container")" | grep -q 'no-new-privileges'

$PROD_COMPOSE exec -T database psql \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --set=ON_ERROR_STOP=1 \
    --command="INSERT INTO application_metadata (metadata_key, metadata_value) VALUES ('backup_probe', 'round-trip-ok') ON CONFLICT (metadata_key) DO UPDATE SET metadata_value = EXCLUDED.metadata_value, updated_at = CURRENT_TIMESTAMP"

printf '%s\n' 'Creating and verifying an on-demand backup...'
$PROD_COMPOSE exec -T database-backup backup-entrypoint backup-once
backup_file="$($PROD_COMPOSE exec -T database-backup sh -lc 'ls -1t /backups/*.dump | head -n 1')"
test -n "$backup_file"
$PROD_COMPOSE exec -T database-backup backup-entrypoint verify-backup "$backup_file"
test "$($PROD_COMPOSE exec -T database-backup stat -c '%a' "$backup_file")" = "600"

printf '%s\n' 'Verifying that restore requires explicit confirmation...'
if $PROD_COMPOSE run --rm \
    -e DATABASE_NAME=restore_verify \
    database-backup restore-backup "$backup_file" >/dev/null 2>&1; then
    echo "Restore unexpectedly ran without RESTORE_CONFIRM." >&2
    exit 1
fi

$PROD_COMPOSE exec -T database psql \
    --username="$POSTGRES_USER" \
    --dbname=postgres \
    --set=ON_ERROR_STOP=1 \
    --command='DROP DATABASE IF EXISTS restore_verify WITH (FORCE)'
$PROD_COMPOSE exec -T database psql \
    --username="$POSTGRES_USER" \
    --dbname=postgres \
    --set=ON_ERROR_STOP=1 \
    --command='CREATE DATABASE restore_verify'

printf '%s\n' 'Restoring the backup into an isolated verification database...'
$PROD_COMPOSE run --rm \
    -e DATABASE_NAME=restore_verify \
    -e RESTORE_CONFIRM=restore_verify \
    database-backup restore-backup "$backup_file"

restored_value="$($PROD_COMPOSE exec -T database psql \
    --username="$POSTGRES_USER" \
    --dbname=restore_verify \
    --tuples-only \
    --no-align \
    --set=ON_ERROR_STOP=1 \
    --command="SELECT metadata_value FROM application_metadata WHERE metadata_key = 'backup_probe'")"
test "$restored_value" = "round-trip-ok"

$PROD_COMPOSE exec -T database psql \
    --username="$POSTGRES_USER" \
    --dbname=postgres \
    --set=ON_ERROR_STOP=1 \
    --command='DROP DATABASE restore_verify WITH (FORCE)'

printf '%s\n' 'Database backup and restore tests passed.'
