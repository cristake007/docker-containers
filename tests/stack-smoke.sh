#!/bin/sh
set -eu

# End-to-end proof that the dev and prod stacks actually work together, and
# that the checked-in nginx examples in deploy/nginx/ (not a stand-in
# config) are what's under test: log in as the env-seeded admin, probe the
# session, and log out again, over each stack's real nginx front door. The
# prod phase also proves the HTTP -> HTTPS redirect actually redirects
# (see AUDIT_FINDINGS.md F-003, F-013). Both phases also probe the API
# Platform entrypoint the way a real browser would -- see
# assert_api_entrypoint_ok below for why.

PROJECT_NAME=stack-smoke
COMPOSE="docker compose -p $PROJECT_NAME"
PROD_COMPOSE="docker compose -p $PROJECT_NAME -f compose.yaml"
NGINX_NAME=stack-smoke-nginx
WORKDIR="$(mktemp -d)"

cleanup() {
    exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        echo "--- stack-smoke.sh failing (exit $exit_code): backend logs ---" >&2
        $COMPOSE logs backend >&2 || true
    fi
    docker rm -f "$NGINX_NAME" >/dev/null 2>&1 || true
    $COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true
    rm -rf "$WORKDIR"
}
trap cleanup EXIT INT TERM

json_get() {
    # json_get <python-expression-on-`d`> reads stdin as JSON into `d`.
    python3 -c "import sys, json; d = json.load(sys.stdin); print($1)"
}

wait_for_http() {
    # Waits for the *expected* status, not just any response: nginx itself
    # comes up almost instantly and will happily return 502 while the
    # fastcgi backend behind it is still booting, which is not "ready".
    # The backend boots a cold Symfony console and validates/generates a
    # JWT keypair before it's reachable at all, so this budget is generous
    # on purpose.
    url="$1"
    expected_code="$2"
    attempts=0
    while [ "$attempts" -lt 90 ]; do
        code="$(curl -sk -o /dev/null -w '%{http_code}' "$url" || true)"
        if [ "$code" = "$expected_code" ]; then
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    echo "Timed out waiting for $url to return $expected_code (last saw $code)" >&2
    echo "--- nginx logs ---" >&2
    docker logs "$NGINX_NAME" >&2 || true
    return 1
}

run_nginx() {
    # $1: rendered/checked-in nginx server-block file to load as-is.
    docker rm -f "$NGINX_NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NGINX_NAME" --network host \
        -v "$1:/etc/nginx/conf.d/default.conf:ro" \
        -v "$WORKDIR/tls:/etc/nginx/tls:ro" \
        -v "$WORKDIR/dist:/srv/dist:ro" \
        nginx:alpine@sha256:4a73073bd557c65b759505da037898b61f1be6cbcc3c2c3aeac22d2a470c1752 >/dev/null
}

# Regression coverage for bugs that shipped in the checked-in nginx examples
# and only surfaced when a real browser hit them (see the conversation this
# was added from): a curl-only smoke test never exercises these failure
# modes, so they're asserted explicitly here.
BROWSER_ACCEPT='Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'

assert_api_entrypoint_ok() {
    base_url="$1"
    curl_extra="$2"
    # "dev": Swagger UI/GraphiQL must actually render, assets included.
    # "prod": browsing must not crash, but must not render either --
    # both UIs are disabled there on purpose (see api_platform.yaml).
    docs_mode="$3"

    # Without `fastcgi_param SCRIPT_NAME /index.php;`, Symfony computes the
    # wrong base URL for the API Platform entrypoint (the one route with two
    # optional path segments), nginx redirects bare /api to /api/, and
    # Symfony's own trailing-slash canonicalization redirects /api/ right
    # back -- an infinite loop a browser shows as ERR_TOO_MANY_REDIRECTS.
    # Every other route has a fixed path and never exposes this, so testing
    # only /api/me (as earlier versions of this script did) misses it
    # entirely.
    code="$(curl -s $curl_extra -o /dev/null -w '%{http_code}' "$base_url/api")"
    [ "$code" = "200" ] || {
        echo "expected GET $base_url/api to return 200 (the entrypoint document), got $code -- possible SCRIPT_NAME redirect-loop regression" >&2
        exit 1
    }

    # A real browser's default Accept header always includes a */* fallback,
    # so this must never crash regardless of docs_mode.
    swagger_body="$(curl -s $curl_extra -w '\n%{http_code}' -H "$BROWSER_ACCEPT" "$base_url/api")"
    swagger_code="$(printf '%s' "$swagger_body" | tail -1)"
    [ "$swagger_code" = "200" ] || {
        echo "expected a browser-Accept GET $base_url/api to return 200, got $swagger_code -- possible SwaggerUI/docs_formats regression" >&2
        exit 1
    }

    graphiql_body="$(curl -s $curl_extra -w '\n%{http_code}' -H "$BROWSER_ACCEPT" "$base_url/api/graphql")"
    graphiql_code="$(printf '%s' "$graphiql_body" | tail -1)"
    [ "$graphiql_code" = "200" ] || {
        echo "expected a browser-Accept GET $base_url/api/graphql to return 200, got $graphiql_code -- possible GraphiQL regression" >&2
        exit 1
    }

    if [ "$docs_mode" = "dev" ]; then
        printf '%s' "$swagger_body" | grep -qi 'swagger' \
            || { echo "expected Swagger UI to actually render in dev at $base_url/api" >&2; exit 1; }
        printf '%s' "$graphiql_body" | grep -qi 'graphiql' \
            || { echo "expected GraphiQL to actually render in dev at $base_url/api/graphql" >&2; exit 1; }

        code="$(curl -s $curl_extra -o /dev/null -w '%{http_code}' "$base_url/bundles/apiplatform/swagger-ui/swagger-ui-bundle.js")"
        [ "$code" = "200" ] || { echo "Swagger UI's own JS asset did not load (got $code) -- possible assets:install/nginx alias regression" >&2; exit 1; }

        code="$(curl -s $curl_extra -o /dev/null -w '%{http_code}' "$base_url/bundles/apiplatform/init-graphiql.js")"
        [ "$code" = "200" ] || { echo "GraphiQL's own JS asset did not load (got $code) -- possible assets:install/nginx alias regression" >&2; exit 1; }
    else
        printf '%s' "$swagger_body" | grep -qi 'swagger' \
            && { echo "Swagger UI rendered in prod -- it must stay disabled there (see api_platform.yaml when@prod)" >&2; exit 1; }
        printf '%s' "$graphiql_body" | grep -qi 'graphiql' \
            && { echo "GraphiQL rendered in prod -- it must stay disabled there (see api_platform.yaml when@prod)" >&2; exit 1; }
    fi
}

# Real (test-only) values: prod refuses to boot with the placeholder values
# from the committed root .env (see entrypoint.sh and
# App\Command\BootstrapAdminCommand), so reusing them here would be testing
# the wrong thing. The same values are used for the dev phase too -- dev
# doesn't enforce the strength policy, so there's no reason to keep two sets.
export APP_SECRET='stack-smoke-test-app-secret-32-characters-plus'
export JWT_PASSPHRASE='stack-smoke-test-jwt-passphrase-32-characters-plus'
export POSTGRES_PASSWORD='stack-smoke-test-postgres-password-32-chars-plus'
export ADMIN_EMAIL='Admin@Stack-Smoke.Test'
export ADMIN_PASSWORD='stack-smoke-test-admin-password'
export CORS_ALLOW_ORIGIN='^https://stack-smoke\.test$'

$COMPOSE config --quiet
$PROD_COMPOSE config --quiet

mkdir -p "$WORKDIR/tls" "$WORKDIR/dist"

# --- Dev phase -------------------------------------------------------------
# Uses deploy/nginx/app.dev.conf.example completely unmodified: it hardcodes
# 127.0.0.1:5173 / 127.0.0.1:9000, which is exactly what compose.yaml +
# compose.override.yaml publish, so no templating is needed to exercise the
# real, checked-in file.

$COMPOSE up -d --build
$COMPOSE exec -T backend php bin/console doctrine:migrations:migrate --no-interaction
$COMPOSE exec -T backend php bin/console app:bootstrap-admin --no-interaction

run_nginx "$(pwd)/deploy/nginx/app.dev.conf.example"

wait_for_http "http://127.0.0.1/api/me" 200
assert_api_entrypoint_ok "http://127.0.0.1" "" "dev"

DEV_JAR="$WORKDIR/dev-cookies.txt"

ANONYMOUS_AUTHENTICATED="$(curl -sf http://127.0.0.1/api/me | json_get "d['authenticated']")"
[ "$ANONYMOUS_AUTHENTICATED" = "False" ] \
    || { echo "anonymous /api/me unexpectedly reported authenticated: $ANONYMOUS_AUTHENTICATED" >&2; exit 1; }

# Logging in with different casing than ADMIN_EMAIL proves email lookup is
# case-insensitive end to end (see AUDIT_FINDINGS.md F-004).
curl -sf -X POST http://127.0.0.1/api/login -c "$DEV_JAR" \
    -H 'Content-Type: application/json' \
    -d '{"email":"admin@stack-smoke.test","password":"stack-smoke-test-admin-password"}' >/dev/null

ME_EMAIL="$(curl -sf http://127.0.0.1/api/me -b "$DEV_JAR" | json_get "d['email']")"
[ "$ME_EMAIL" = "admin@stack-smoke.test" ] || { echo "unexpected /api/me: $ME_EMAIL" >&2; exit 1; }

curl -sf -i -X POST http://127.0.0.1/api/logout -b "$DEV_JAR" | grep -qi '^Set-Cookie: BEARER=deleted' \
    || { echo "logout did not clear the BEARER cookie" >&2; exit 1; }

docker rm -f "$NGINX_NAME" >/dev/null 2>&1 || true
$COMPOSE down -v --remove-orphans

echo 'Dev phase passed: app.dev.conf.example, login, per-request session, and logout all work end-to-end.'

# --- Prod phase --------------------------------------------------------------
# Builds the real static frontend export and a self-signed cert, then
# exercises deploy/nginx/app.prod.conf.example with only its placeholder
# `root` and TLS paths filled in -- everything else (including `listen 80`
# doing a bare redirect, and `listen 443 ssl` serving the app) is the
# checked-in file, unmodified.

docker build -f docker/frontend/Dockerfile --target export \
    --output "type=local,dest=$WORKDIR/dist" .

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -keyout "$WORKDIR/tls/privkey.pem" -out "$WORKDIR/tls/fullchain.pem" \
    -subj "/CN=stack-smoke.test" >/dev/null 2>&1

sed \
    -e 's@your-domain.example@stack-smoke.test@g' \
    -e 's@/path/to/docker-containers/frontend/dist@/srv/dist@' \
    deploy/nginx/app.prod.conf.example \
    | sed \
        -e 's@^    # ssl_certificate \+.*@    ssl_certificate /etc/nginx/tls/fullchain.pem;@' \
        -e 's@^    # ssl_certificate_key \+.*@    ssl_certificate_key /etc/nginx/tls/privkey.pem;@' \
    > "$WORKDIR/app.prod.conf"
grep -q '^    ssl_certificate /etc/nginx/tls/fullchain.pem;$' "$WORKDIR/app.prod.conf" \
    || { echo "failed to enable ssl_certificate in the rendered prod nginx config" >&2; cat "$WORKDIR/app.prod.conf" >&2; exit 1; }

$PROD_COMPOSE up -d --build
$PROD_COMPOSE exec -T backend php bin/console doctrine:migrations:migrate --no-interaction
$PROD_COMPOSE exec -T backend php bin/console app:bootstrap-admin --no-interaction

run_nginx "$WORKDIR/app.prod.conf"

wait_for_http "https://127.0.0.1/api/me" 200
assert_api_entrypoint_ok "https://127.0.0.1" "-k" "prod"

# The plain-HTTP listener must redirect, never serve the app (see
# AUDIT_FINDINGS.md F-003).
REDIRECT_LOCATION="$(curl -s -o /dev/null -w '%{redirect_url}' http://127.0.0.1/anything)"
case "$REDIRECT_LOCATION" in
    https://stack-smoke.test/anything) ;;
    *)
        echo "expected plain HTTP to redirect to https://stack-smoke.test/anything, got: $REDIRECT_LOCATION" >&2
        exit 1
        ;;
esac

PROD_JAR="$WORKDIR/prod-cookies.txt"

curl -skf https://127.0.0.1/ | grep -qi '<div id="root">' \
    || { echo "prod nginx did not serve the built frontend at /" >&2; exit 1; }

curl -skf -X POST https://127.0.0.1/api/login -c "$PROD_JAR" \
    -H 'Content-Type: application/json' \
    -d '{"email":"admin@stack-smoke.test","password":"stack-smoke-test-admin-password"}' >/dev/null

grep -q 'BEARER.*Secure' "$PROD_JAR" \
    || { echo "prod BEARER cookie was not marked Secure (JWT_COOKIE_SECURE)" >&2; cat "$PROD_JAR" >&2; exit 1; }

ME_AUTHENTICATED="$(curl -skf https://127.0.0.1/api/me -b "$PROD_JAR" | json_get "d['authenticated']")"
[ "$ME_AUTHENTICATED" = "True" ] || { echo "expected prod /api/me to report authenticated" >&2; exit 1; }

curl -skf -i -X POST https://127.0.0.1/api/logout -b "$PROD_JAR" | grep -qi '^Set-Cookie: BEARER=deleted' \
    || { echo "prod logout did not clear the BEARER cookie" >&2; exit 1; }

printf '%s\n' 'Stack smoke test passed: dev and prod nginx examples, the API entrypoint (with dev schema browsing / prod lockdown), login, case-insensitive email, per-request session, HTTP->HTTPS redirect, and logout all work end-to-end.'
