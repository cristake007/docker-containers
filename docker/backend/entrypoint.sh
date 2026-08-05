#!/bin/sh
set -eu

# The committed root .env ships obviously-fake secrets so `docker compose up`
# works with zero setup in dev. Refuse to boot in prod if those secrets are
# missing, weak, or still the committed placeholder, so a forgotten or
# incomplete override fails loudly instead of silently running with an
# empty or known, public secret.
#
# Minimum-strength policy: cryptographic secrets need at least 32 characters
# (matches the length produced by `php -r 'echo bin2hex(random_bytes(16));'`,
# the generator documented in .env). ADMIN_PASSWORD is a human-typed login
# password, not a generated secret, so it only needs to clear the same
# 8-character floor BootstrapAdminCommand enforces.
if [ "${APP_ENV:-}" = "prod" ]; then
    for pair in \
        "APP_SECRET:dev-insecure-app-secret-do-not-use-in-prod:32" \
        "JWT_PASSPHRASE:dev-insecure-jwt-passphrase-do-not-use-in-prod:32" \
        "POSTGRES_PASSWORD:dev-insecure-postgres-password-do-not-use-in-prod:32" \
        "ADMIN_PASSWORD:dev-insecure-admin-password-do-not-use-in-prod:8"
    do
        name=${pair%%:*}
        rest=${pair#*:}
        placeholder=${rest%:*}
        min_len=${rest##*:}
        eval "value=\${$name:-}"
        if [ -z "$value" ]; then
            echo "Refusing to start: $name is empty. Set a real secret (see .env)." >&2
            exit 1
        fi
        if [ "$value" = "$placeholder" ]; then
            echo "Refusing to start: $name still has its committed dev placeholder value. Set a real secret (see .env)." >&2
            exit 1
        fi
        value_len=$(printf '%s' "$value" | wc -c)
        if [ "$value_len" -lt "$min_len" ]; then
            echo "Refusing to start: $name is shorter than the required $min_len characters. Generate a stronger secret (see .env)." >&2
            exit 1
        fi
    done
    if [ -z "${ADMIN_EMAIL:-}" ]; then
        echo "Refusing to start: ADMIN_EMAIL is empty. Set the admin login email (see .env)." >&2
        exit 1
    fi
fi

JWT_DIR="/var/www/html/config/jwt"
JWT_PRIVATE="$JWT_DIR/private.pem"
JWT_PUBLIC="$JWT_DIR/public.pem"

# Keypair handling is deliberately atomic and validated, not a bare
# "generate if missing" check: `lexik:jwt:generate-keypair --skip-if-exists`
# treats either file's mere presence as "the pair already exists" and
# leaves the other half missing, and neither that command nor a plain
# existence check confirms the files are actually a usable, matching pair
# for the configured passphrase. See AUDIT_FINDINGS.md F-012.
if [ -f "$JWT_PRIVATE" ] && [ -f "$JWT_PUBLIC" ]; then
    if [ -z "${JWT_PASSPHRASE:-}" ]; then
        echo "Refusing to start: $JWT_PRIVATE and $JWT_PUBLIC exist but JWT_PASSPHRASE is not set, so they cannot be validated." >&2
        exit 1
    fi
    if ! openssl pkey -in "$JWT_PRIVATE" -passin env:JWT_PASSPHRASE -noout -check >/dev/null 2>&1; then
        echo "Refusing to start: $JWT_PRIVATE does not decrypt with the configured JWT_PASSPHRASE, or is not a valid key." >&2
        exit 1
    fi
    derived_public="$(mktemp)"
    openssl pkey -in "$JWT_PRIVATE" -passin env:JWT_PASSPHRASE -pubout -out "$derived_public" 2>/dev/null
    keys_match=0
    cmp -s "$derived_public" "$JWT_PUBLIC" || keys_match=1
    rm -f "$derived_public"
    if [ "$keys_match" -ne 0 ]; then
        echo "Refusing to start: $JWT_PUBLIC does not match $JWT_PRIVATE. The keypair is inconsistent (mismatched restore? interrupted rotation?)." >&2
        exit 1
    fi
elif [ -f "$JWT_PRIVATE" ] || [ -f "$JWT_PUBLIC" ]; then
    echo "Refusing to start: only one of $JWT_PRIVATE / $JWT_PUBLIC exists. Restore the missing file from backup, or delete the remaining one and restart this container to generate a fresh pair." >&2
    exit 1
else
    if [ -z "${JWT_PASSPHRASE:-}" ]; then
        echo "Refusing to start: $JWT_PRIVATE and $JWT_PUBLIC do not exist and JWT_PASSPHRASE is not set to generate them." >&2
        exit 1
    fi
    mkdir -p "$JWT_DIR"
    php bin/console lexik:jwt:generate-keypair --no-interaction
    chown www-data:www-data "$JWT_PRIVATE" "$JWT_PUBLIC"
    chmod 600 "$JWT_PRIVATE"
    chmod 644 "$JWT_PUBLIC"
fi

exec "$@"
