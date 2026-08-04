#!/bin/sh
set -eu

# The committed root .env ships obviously-fake secrets so `docker compose up`
# works with zero setup in dev. Refuse to boot in prod if those exact
# placeholder values are still in effect, so a forgotten override fails
# loudly instead of silently running with known, public secrets.
if [ "${APP_ENV:-}" = "prod" ]; then
    for pair in \
        "APP_SECRET:dev-insecure-app-secret-do-not-use-in-prod" \
        "JWT_PASSPHRASE:dev-insecure-jwt-passphrase-do-not-use-in-prod"
    do
        name=${pair%%:*}
        placeholder=${pair#*:}
        eval "value=\${$name:-}"
        if [ "$value" = "$placeholder" ]; then
            echo "Refusing to start: $name still has its committed dev placeholder value. Set a real secret (see .env)." >&2
            exit 1
        fi
    done
    case "${DATABASE_URL:-}" in
        *dev-insecure-postgres-password-do-not-use-in-prod*)
            echo "Refusing to start: DATABASE_URL still embeds the dev placeholder Postgres password. Set a real secret (see .env)." >&2
            exit 1
            ;;
    esac
fi

JWT_DIR="/var/www/html/config/jwt"

if [ -n "${JWT_PASSPHRASE:-}" ] && { [ ! -f "$JWT_DIR/private.pem" ] || [ ! -f "$JWT_DIR/public.pem" ]; }; then
    mkdir -p "$JWT_DIR"
    php bin/console lexik:jwt:generate-keypair --skip-if-exists --no-interaction
    chown www-data:www-data "$JWT_DIR"/*.pem
    chmod 600 "$JWT_DIR/private.pem"
    chmod 644 "$JWT_DIR/public.pem"
fi

exec "$@"
