#!/bin/sh
set -eu

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$SCRIPT_DIRECTORY/test-env.sh"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-symfony-backend-smoke}"
DEV_COMPOSE="docker compose -p $PROJECT_NAME"
PROD_COMPOSE="docker compose -p $PROJECT_NAME -f compose.yaml"
CURRENT_PHASE="initialization"
CURRENT_COMPOSE="$DEV_COMPOSE"

prepare_test_environment "$PROJECT_NAME"

set_phase() {
    CURRENT_PHASE="$1"
    CURRENT_COMPOSE="$2"
    printf 'Phase: %s\n' "$CURRENT_PHASE"
}

cleanup() {
    status=$?
    trap - EXIT INT TERM

    if [ "$status" -ne 0 ]; then
        printf '::error title=Platform smoke failure::Phase: %s\n' "$CURRENT_PHASE" >&2
        printf 'Smoke test failed during phase: %s\n' "$CURRENT_PHASE" >&2
        printf '%s\n' 'Container state:' >&2
        $CURRENT_COMPOSE ps -a >&2 || true
        printf '%s\n' 'Database, migration and backend logs:' >&2
        $CURRENT_COMPOSE logs --no-color database migrate backend >&2 || true
    fi

    $DEV_COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true
    remove_test_environment
    exit "$status"
}

wait_for_service_health() {
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
                $compose_command logs "$service" >&2 || true
                return 1
                ;;
        esac

        attempts=$((attempts + 1))
        sleep 2
    done

    $compose_command logs "$service" >&2 || true
    echo "$service did not become healthy." >&2
    return 1
}

assert_migration_completed() {
    compose_command="$1"
    migration_container="$($compose_command ps -a -q migrate)"

    test -n "$migration_container"
    test "$(docker inspect --format '{{.State.Status}}' "$migration_container")" = "exited"
    test "$(docker inspect --format '{{.State.ExitCode}}' "$migration_container")" = "0"
}

assert_http_contract() {
    compose_command="$1"

    $compose_command exec -T backend php -r '
        $healthHeaders = get_headers("http://127.0.0.1/healthz", true);
        $healthBody = file_get_contents("http://127.0.0.1/healthz");
        if ($healthBody !== "ok\n" || ($healthHeaders["X-Container-Health"] ?? null) !== "php") {
            fwrite(STDERR, "Container health endpoint failed.\n");
            exit(1);
        }

        $readyHeaders = get_headers("http://127.0.0.1/readyz", true);
        $readyBody = file_get_contents("http://127.0.0.1/readyz");
        if ($readyBody !== "ready\n" || ($readyHeaders["X-Application-Readiness"] ?? null) !== "database") {
            fwrite(STDERR, "Application readiness endpoint failed.\n");
            exit(1);
        }

        $allowedContext = stream_context_create(["http" => [
            "method" => "OPTIONS",
            "ignore_errors" => true,
            "header" => "Origin: http://localhost:4200\r\nAccess-Control-Request-Method: POST\r\nAccess-Control-Request-Headers: Authorization, Content-Type\r\n",
        ]]);
        @file_get_contents("http://127.0.0.1/readyz", false, $allowedContext);
        $allowedHeaders = $http_response_header ?? [];
        $allowedText = implode("\n", $allowedHeaders);
        if (!str_contains($allowedHeaders[0] ?? "", "204") || !str_contains($allowedText, "Access-Control-Allow-Origin: http://localhost:4200")) {
            fwrite(STDERR, "Allowed CORS preflight failed.\n");
            exit(1);
        }

        $deniedContext = stream_context_create(["http" => [
            "method" => "OPTIONS",
            "ignore_errors" => true,
            "header" => "Origin: https://untrusted.example\r\nAccess-Control-Request-Method: POST\r\n",
        ]]);
        @file_get_contents("http://127.0.0.1/readyz", false, $deniedContext);
        $deniedHeaders = $http_response_header ?? [];
        $deniedText = implode("\n", $deniedHeaders);
        if (!str_contains($deniedHeaders[0] ?? "", "403") || str_contains($deniedText, "Access-Control-Allow-Origin")) {
            fwrite(STDERR, "Denied CORS preflight was not blocked.\n");
            exit(1);
        }
    '
}

trap cleanup EXIT INT TERM

set_phase 'Compose configuration validation' "$DEV_COMPOSE"
$DEV_COMPOSE config --quiet
$PROD_COMPOSE config --quiet

$DEV_COMPOSE config | grep -q 'target: dev'
$PROD_COMPOSE config | grep -q 'target: prod'
$DEV_COMPOSE config | grep -q '/var/www/html'
$PROD_COMPOSE config | grep -q 'condition: service_completed_successfully'
$PROD_COMPOSE config | grep -q '/var/lib/postgresql'
if $PROD_COMPOSE config | grep -q '/var/www/html'; then
    echo "Production Compose configuration unexpectedly contains the development source mount." >&2
    exit 1
fi

if [ ! -f backend/composer.lock ]; then
    set_phase 'Locked production source validation' "$PROD_COMPOSE"
    rejection_log="$(mktemp)"

    if $PROD_COMPOSE build backend >"$rejection_log" 2>&1; then
        cat "$rejection_log" >&2
        echo "Production build unexpectedly succeeded without backend/composer.lock." >&2
        rm -f "$rejection_log"
        exit 1
    fi

    if ! grep -q 'Production builds require committed Symfony source and backend/composer.lock.' "$rejection_log"; then
        cat "$rejection_log" >&2
        echo "Production build failed for an unexpected reason." >&2
        rm -f "$rejection_log"
        exit 1
    fi

    rm -f "$rejection_log"
fi

set_phase 'Development image build and startup' "$DEV_COMPOSE"
$DEV_COMPOSE up -d --build backend

set_phase 'Development health and migration checks' "$DEV_COMPOSE"
wait_for_service_health "$DEV_COMPOSE" database
wait_for_service_health "$DEV_COMPOSE" backend
assert_migration_completed "$DEV_COMPOSE"

set_phase 'Development HTTP and CORS contract' "$DEV_COMPOSE"
assert_http_contract "$DEV_COMPOSE"

set_phase 'Development runtime assertions' "$DEV_COMPOSE"
$DEV_COMPOSE exec -T backend sh -lc '
    set -eu

    test "$APP_ENV" = "dev"
    test "$APP_DEBUG" = "1"
    test -f composer.json
    test -f composer.lock
    test -f vendor/autoload.php
    test -f config/packages/container.yaml
    test -f config/packages/doctrine.yaml
    test -f migrations/Version20260804000000.php

    php -r '\''exit(ini_get("display_errors") === "1" ? 0 : 1);'\''
    php -r '\''exit(ini_get("memory_limit") === "512M" ? 0 : 1);'\''
    php -r '\''exit(ini_get("opcache.validate_timestamps") === "1" ? 0 : 1);'\''
    php -r '\''foreach (["intl", "pdo_pgsql", "zip"] as $extension) { if (!extension_loaded($extension)) { fwrite(STDERR, "$extension is missing\n"); exit(1); } }'\''

    command -v composer >/dev/null
    command -v git >/dev/null
    composer validate --no-check-publish
    composer check-platform-reqs
    composer audit --locked --no-interaction
    composer show --locked doctrine/doctrine-bundle >/dev/null
    composer show --locked doctrine/doctrine-migrations-bundle >/dev/null
    php bin/console about --env=dev >/dev/null
    php bin/console lint:container
    php bin/console lint:yaml config
    php bin/console doctrine:migrations:status --no-interaction >/dev/null

    apache2ctl configtest
    apache2ctl -M 2>/dev/null | grep -q php_module
    apache2ctl -M 2>/dev/null | grep -q rewrite_module
    apache2ctl -M 2>/dev/null | grep -q headers_module
'

set_phase 'Development database port binding' "$DEV_COMPOSE"
development_database_container="$($DEV_COMPOSE ps -q database)"
test -n "$development_database_container"
development_database_binding="$(docker inspect --format '{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostIp}}:{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}' "$development_database_container")"
test "$development_database_binding" = "127.0.0.1:5432"

$DEV_COMPOSE down -v --remove-orphans

set_phase 'Production image build and startup' "$PROD_COMPOSE"
$PROD_COMPOSE up -d --build backend

set_phase 'Production health and migration checks' "$PROD_COMPOSE"
wait_for_service_health "$PROD_COMPOSE" database
wait_for_service_health "$PROD_COMPOSE" backend
assert_migration_completed "$PROD_COMPOSE"

set_phase 'Production HTTP and CORS contract' "$PROD_COMPOSE"
assert_http_contract "$PROD_COMPOSE"

set_phase 'Production runtime assertions' "$PROD_COMPOSE"
$PROD_COMPOSE exec -T backend sh -lc '
    set -eu

    test "$APP_ENV" = "prod"
    test "$APP_DEBUG" = "0"
    test -f composer.json
    test -f composer.lock
    test -f vendor/autoload.php
    test -d var/cache/prod

    php -r '\''exit(ini_get("display_errors") === "" ? 0 : 1);'\''
    php -r '\''exit(ini_get("expose_php") === "" ? 0 : 1);'\''
    php -r '\''exit(ini_get("memory_limit") === "256M" ? 0 : 1);'\''
    php -r '\''exit(ini_get("opcache.validate_timestamps") === "0" ? 0 : 1);'\''
    php -r '\''foreach (["intl", "pdo_pgsql", "zip"] as $extension) { if (!extension_loaded($extension)) { fwrite(STDERR, "$extension is missing\n"); exit(1); } }'\''

    for command in composer git cc gcc g++ make autoconf; do
        if command -v "$command" >/dev/null 2>&1; then
            echo "$command must not be present in the production image." >&2
            exit 1
        fi
    done

    for package in autoconf dpkg-dev g++ gcc libc6-dev libicu-dev libpq-dev libzip-dev make pkg-config re2c; do
        if dpkg-query -W -f='\''${db:Status-Abbrev}'\'' "$package" 2>/dev/null | grep -q "^ii"; then
            echo "$package must not be installed in the production image." >&2
            exit 1
        fi
    done

    php -r '\''
        $lock = json_decode(file_get_contents("composer.lock"), true, 512, JSON_THROW_ON_ERROR);
        $installed = require "vendor/composer/installed.php";
        $versions = $installed["versions"] ?? $installed[0]["versions"] ?? [];
        foreach ($lock["packages-dev"] ?? [] as $package) {
            if (isset($versions[$package["name"]])) {
                fwrite(STDERR, "Development package installed in production: ".$package["name"]."\n");
                exit(1);
            }
        }
    '\''

    test "$(stat -c "%U" composer.json)" = "root"
    test "$(stat -c "%U" public/index.php)" = "root"
    test "$(stat -c "%U" var/cache)" = "www-data"
    su -s /bin/sh www-data -c '\''test ! -w composer.json && test ! -w public/index.php'\''
    su -s /bin/sh www-data -c '\''touch var/cache/container-smoke-test && rm var/cache/container-smoke-test'\''

    php bin/console about --env=prod >/dev/null
    php bin/console doctrine:migrations:status --no-interaction >/dev/null

    apache2ctl configtest
    apache2ctl -M 2>/dev/null | grep -q php_module
    apache2ctl -M 2>/dev/null | grep -q rewrite_module
    apache2ctl -M 2>/dev/null | grep -q headers_module
    grep -qx "ServerTokens Prod" /etc/apache2/conf-enabled/zz-container-hardening.conf
    grep -qx "ServerSignature Off" /etc/apache2/conf-enabled/zz-container-hardening.conf
    grep -qx "TraceEnable Off" /etc/apache2/conf-enabled/zz-container-hardening.conf

    php -r '\''
        $headers = get_headers("http://127.0.0.1/healthz", true);
        foreach ($headers as $name => $value) {
            if (is_string($name) && strcasecmp($name, "Server") === 0) {
                $server = is_array($value) ? end($value) : $value;
                if ($server !== "Apache") {
                    fwrite(STDERR, "Apache version information is exposed: ".$server."\n");
                    exit(1);
                }
            }
        }
    '\''

    php -r '\''
        $headers = get_headers("http://127.0.0.1/index.php", true);
        foreach ($headers ?: [] as $name => $value) {
            if (is_string($name) && strcasecmp($name, "X-Powered-By") === 0) {
                fwrite(STDERR, "X-Powered-By must not be exposed in production.\n");
                exit(1);
            }
        }
    '\''

    php -r '\''
        $context = stream_context_create(["http" => ["method" => "TRACE", "ignore_errors" => true]]);
        @file_get_contents("http://127.0.0.1/", false, $context);
        $status = $http_response_header[0] ?? "";
        if (!str_contains($status, "405")) {
            fwrite(STDERR, "Apache TRACE requests are not disabled.\n");
            exit(1);
        }
    '\''
'

set_phase 'Production container isolation assertions' "$PROD_COMPOSE"
production_container="$($PROD_COMPOSE ps -q backend)"
database_container="$($PROD_COMPOSE ps -q database)"

mount_destinations="$(docker inspect --format '{{range .Mounts}}{{println .Destination}}{{end}}' "$production_container")"
if printf '%s\n' "$mount_destinations" | grep -qx '/var/www/html'; then
    echo "Production backend has a source mount." >&2
    exit 1
fi
printf '%s\n' "$mount_destinations" | grep -qx '/run/secrets/app_secret'
printf '%s\n' "$mount_destinations" | grep -qx '/run/secrets/database_password'

host_ip="$(docker inspect --format '{{(index (index .NetworkSettings.Ports "80/tcp") 0).HostIp}}' "$production_container")"
test "$host_ip" = "127.0.0.1"

if docker port "$database_container" 5432/tcp >/dev/null 2>&1; then
    echo "Production PostgreSQL is publicly mapped." >&2
    exit 1
fi

database_network="${PROJECT_NAME}_database"
test "$(docker network inspect --format '{{.Internal}}' "$database_network")" = "true"

for container_id in "$production_container" "$database_container"; do
    security_options="$(docker inspect --format '{{json .HostConfig.SecurityOpt}}' "$container_id")"
    printf '%s' "$security_options" | grep -q 'no-new-privileges'
    test "$(docker inspect --format '{{.HostConfig.Init}}' "$container_id")" = "true"
done

app_secret="$(cat "$APP_SECRET_SECRET_FILE")"
database_password="$(cat "$DATABASE_PASSWORD_SECRET_FILE")"
for container_id in "$production_container" "$database_container"; do
    configured_environment="$(docker inspect --format '{{json .Config.Env}}' "$container_id")"
    if printf '%s' "$configured_environment" | grep -Fq "$app_secret"; then
        echo "Application secret leaked into container environment configuration." >&2
        exit 1
    fi
    if printf '%s' "$configured_environment" | grep -Fq "$database_password"; then
        echo "Database password leaked into container environment configuration." >&2
        exit 1
    fi
done

printf '%s\n' 'Development and production smoke tests passed.'
