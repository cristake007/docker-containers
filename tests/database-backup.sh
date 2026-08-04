#!/bin/sh
set -eu

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$SCRIPT_DIRECTORY/test-env.sh"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-symfony-database-backup}"
DEV_COMPOSE="docker compose -p $PROJECT_NAME"
PROD_COMPOSE="docker compose -p $PROJECT_NAME -f compose.yaml"
CURRENT_PHASE="initialization"

prepare_test_environment "$PROJECT_NAME"

set_phase() {
    CURRENT_PHASE="$1"
    printf 'Phase: %s\n' "$CURRENT_PHASE"
}

cleanup() {
    status=$?
    trap - EXIT INT TERM

    if [ "$status" -ne 0 ]; then
        printf '::error title=Database backup failure::Phase: %s\n' "$CURRENT_PHASE" >&2
        printf 'Backup test failed during phase: %s\n' "$CURRENT_PHASE" >&2
        $PROD_COMPOSE ps -a >&2 || true
        $PROD_COMPOSE logs --no-color database migrate database-backup >&2 || true

        backup_container="$($PROD_COMPOSE ps -a -q database-backup 2>/dev/null || true)"
        if [ -n "$backup_container" ]; then
            docker inspect --format 'status={{.State.Status}} exit={{.State.ExitCode}} restarts={{.RestartCount}} error={{.State.Error}}' "$backup_container" >&2 || true
        fi
    fi

    $DEV_COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true
    remove_test_environment
    exit "$status"
}

wait_for_health() {
    compose_command="$1"
    service="$2"
    container_id="$($compose_command ps -q "$service")"
    attempts=0

    if [ -z "$container_id" ]; then
        echo "$service container was not created." >&2
        return 1
    fi

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

wait_for_backup_scheduler() {
    container_id="$1"
    attempts=0

    while [ "$attempts" -lt 60 ]; do
        status="$(docker inspect --format '{{.State.Status}}' "$container_id")"
        restart_count="$(docker inspect --format '{{.RestartCount}}' "$container_id")"

        case "$status" in
            running)
                if [ "$restart_count" -ne 0 ]; then
                    echo "Backup scheduler restarted during startup." >&2
                    return 1
                fi

                if docker exec -u postgres "$container_id" sh -lc 'test -r /run/app-secrets/database_password && ls /backups/*.dump >/dev/null 2>&1'; then
                    return 0
                fi
                ;;
            restarting|exited|dead)
                docker logs "$container_id" >&2 || true
                return 1
                ;;
        esac

        attempts=$((attempts + 1))
        sleep 1
    done

    docker logs "$container_id" >&2 || true
    echo "Backup scheduler did not become ready." >&2
    return 1
}

trap cleanup EXIT INT TERM

if [ ! -f backend/composer.lock ]; then
    set_phase 'Development application bootstrap'
    $DEV_COMPOSE up -d --build backend
    wait_for_health "$DEV_COMPOSE" database
    wait_for_health "$DEV_COMPOSE" backend
    $DEV_COMPOSE down -v --remove-orphans
fi

set_phase 'Production backup platform startup'
$PROD_COMPOSE up -d --build database-backup
wait_for_health "$PROD_COMPOSE" database

migration_container="$($PROD_COMPOSE ps -a -q migrate)"
test -n "$migration_container"
test "$(docker inspect --format '{{.State.ExitCode}}' "$migration_container")" = "0"

backup_container="$($PROD_COMPOSE ps -q database-backup)"
test -n "$backup_container"
wait_for_backup_scheduler "$backup_container"

test "$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$backup_container")" = "true"
test "$(docker inspect --format '{{.RestartCount}}' "$backup_container")" = "0"
printf '%s' "$(docker inspect --format '{{json .HostConfig.SecurityOpt}}' "$backup_container")" | grep -q 'no-new-privileges'

docker exec -u postgres "$backup_container" sh -lc '
    set -eu
    test "$(stat -c "%a:%U:%G" /run/app-secrets/database_password)" = "640:root:postgres"
    test -r /run/app-secrets/database_password
'

docker top "$backup_container" -eo user,args | grep -Eq '^postgres[[:space:]].*(backup-entrypoint backup-loop|sleep)'

set_phase 'Database probe insertion'
$PROD_COMPOSE exec -T database psql \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --set=ON_ERROR_STOP=1 \
    --command="INSERT INTO application_metadata (metadata_key, metadata_value) VALUES ('backup_probe', 'round-trip-ok') ON CONFLICT (metadata_key) DO UPDATE SET metadata_value = EXCLUDED.metadata_value, updated_at = CURRENT_TIMESTAMP"

set_phase 'On-demand backup creation and verification'
before_count="$($PROD_COMPOSE exec -T database-backup sh -lc 'find /backups -maxdepth 1 -type f -name "*.dump" | wc -l')"
$PROD_COMPOSE run --rm database-backup backup-once
after_count="$($PROD_COMPOSE exec -T database-backup sh -lc 'find /backups -maxdepth 1 -type f -name "*.dump" | wc -l')"
test "$after_count" -eq $((before_count + 1))

backup_file="$($PROD_COMPOSE exec -T database-backup sh -lc 'ls -1t /backups/*.dump | head -n 1')"
test -n "$backup_file"
$PROD_COMPOSE run --rm database-backup verify-backup "$backup_file"
test "$($PROD_COMPOSE exec -T database-backup stat -c '%a' "$backup_file")" = "600"
test "$($PROD_COMPOSE exec -T database-backup stat -c '%a' "${backup_file}.sha256")" = "600"
test "$(docker inspect --format '{{.State.Status}}' "$backup_container")" = "running"
test "$(docker inspect --format '{{.RestartCount}}' "$backup_container")" = "0"

set_phase 'Restore confirmation guard'
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

set_phase 'Isolated backup restore'
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
