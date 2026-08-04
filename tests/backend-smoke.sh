#!/bin/sh
set -eu

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-symfony-backend-smoke}"
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

trap cleanup EXIT INT TERM

printf '%s\n' 'Validating Compose configurations...'
$DEV_COMPOSE config --quiet
$PROD_COMPOSE config --quiet

$DEV_COMPOSE config | grep -q 'target: dev'
$PROD_COMPOSE config | grep -q 'target: prod'
$DEV_COMPOSE config | grep -q '/var/www/html'
if $PROD_COMPOSE config | grep -q '/var/www/html'; then
    echo "Production Compose configuration unexpectedly contains the development source mount." >&2
    exit 1
fi

if [ ! -f backend/composer.lock ]; then
    printf '%s\n' 'Verifying that production rejects unlocked application source...'
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

printf '%s\n' 'Building development image...'
$DEV_COMPOSE build backend

printf '%s\n' 'Starting and testing development container...'
$DEV_COMPOSE up -d backend
wait_for_health "$DEV_COMPOSE"

$DEV_COMPOSE exec -T backend sh -lc '
    set -eu

    test "$APP_ENV" = "dev"
    test "$APP_DEBUG" = "1"
    test -f composer.json
    test -f composer.lock
    test -f vendor/autoload.php

    php -r '\''exit(ini_get("display_errors") === "1" ? 0 : 1);'\''
    php -r '\''exit(ini_get("memory_limit") === "512M" ? 0 : 1);'\''
    php -r '\''exit(ini_get("opcache.validate_timestamps") === "1" ? 0 : 1);'\''
    php -r '\''foreach (["intl", "pdo_pgsql", "zip"] as $extension) { if (!extension_loaded($extension)) { fwrite(STDERR, "$extension is missing\n"); exit(1); } }'\''

    command -v composer >/dev/null
    command -v git >/dev/null
    composer validate --no-check-publish
    composer check-platform-reqs
    composer audit --locked --no-interaction
    php bin/console about --env=dev >/dev/null

    apache2ctl configtest
    apache2ctl -M 2>/dev/null | grep -q php_module
    apache2ctl -M 2>/dev/null | grep -q rewrite_module
    apache2ctl -M 2>/dev/null | grep -q headers_module

    php -r '\''$body = @file_get_contents("http://127.0.0.1/healthz"); exit($body === "ok\n" ? 0 : 1);'\''
'

$DEV_COMPOSE down -v --remove-orphans

printf '%s\n' 'Building production image...'
$PROD_COMPOSE build backend

printf '%s\n' 'Starting and testing production container...'
$PROD_COMPOSE up -d backend
wait_for_health "$PROD_COMPOSE"

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

    apache2ctl configtest
    apache2ctl -M 2>/dev/null | grep -q php_module
    apache2ctl -M 2>/dev/null | grep -q rewrite_module
    apache2ctl -M 2>/dev/null | grep -q headers_module
    grep -qx "ServerTokens Prod" /etc/apache2/conf-enabled/zz-container-hardening.conf
    grep -qx "ServerSignature Off" /etc/apache2/conf-enabled/zz-container-hardening.conf
    grep -qx "TraceEnable Off" /etc/apache2/conf-enabled/zz-container-hardening.conf

    php -r '\''
        $headers = get_headers("http://127.0.0.1/healthz", true);
        if (!is_array($headers) || !str_contains($headers[0], "200")) {
            fwrite(STDERR, "Health endpoint did not return HTTP 200.\n");
            exit(1);
        }
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

production_container="$($PROD_COMPOSE ps -q backend)"
mount_count="$(docker inspect --format '{{len .Mounts}}' "$production_container")"
[ "$mount_count" -eq 0 ]

host_ip="$(docker inspect --format '{{(index (index .NetworkSettings.Ports "80/tcp") 0).HostIp}}' "$production_container")"
[ "$host_ip" = "127.0.0.1" ]

security_options="$(docker inspect --format '{{json .HostConfig.SecurityOpt}}' "$production_container")"
printf '%s' "$security_options" | grep -q 'no-new-privileges'

init_enabled="$(docker inspect --format '{{.HostConfig.Init}}' "$production_container")"
[ "$init_enabled" = "true" ]

printf '%s\n' 'Development and production smoke tests passed.'
