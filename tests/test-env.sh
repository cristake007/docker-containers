#!/bin/sh

prepare_test_environment() {
    project_name="$1"
    repository_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
    test_runtime_directory="$repository_root/.test-runtime/$project_name"

    rm -rf "$test_runtime_directory"
    mkdir -p "$test_runtime_directory/secrets"
    sh "$repository_root/bin/setup-secrets" "$test_runtime_directory/secrets" >/dev/null

    export TEST_RUNTIME_DIRECTORY="$test_runtime_directory"
    export APP_SECRET_SECRET_FILE="$test_runtime_directory/secrets/app_secret"
    export DATABASE_PASSWORD_SECRET_FILE="$test_runtime_directory/secrets/database_password"
    export POSTGRES_DB="${POSTGRES_DB:-app_test}"
    export POSTGRES_USER="${POSTGRES_USER:-app_test}"
    export TRUSTED_PROXIES="${TRUSTED_PROXIES:-127.0.0.1,private_ranges}"
    export CORS_ALLOW_ORIGINS="${CORS_ALLOW_ORIGINS:-http://localhost:4200}"
    export BACKUP_PREFIX="${BACKUP_PREFIX:-app-test}"
}

remove_test_environment() {
    if [ -n "${TEST_RUNTIME_DIRECTORY:-}" ]; then
        rm -rf "$TEST_RUNTIME_DIRECTORY"
    fi
}
