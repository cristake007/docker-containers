#!/bin/sh
set -eu

# End-to-end proof that the dev stack actually works together: register two
# users, log in, create/query/update/delete a task via GraphQL, and confirm
# one user can never see or mutate another user's tasks. This is a
# functional test, not just a container-health check.

PROJECT_NAME=stack-smoke
COMPOSE="docker compose -p $PROJECT_NAME"
BASE_URL="http://127.0.0.1:18000"

cleanup() {
    $COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true
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
    # The backend boots a cold Symfony console and generates a JWT keypair
    # before it's reachable at all, so this budget is generous on purpose.
    url="$1"
    expected_code="$2"
    attempts=0
    while [ "$attempts" -lt 90 ]; do
        code="$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)"
        if [ "$code" = "$expected_code" ]; then
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    echo "Timed out waiting for $url to return $expected_code (last saw $code)" >&2
    echo "--- backend logs ---" >&2
    $COMPOSE logs backend >&2 || true
    echo "--- nginx logs ---" >&2
    docker logs stack-smoke-nginx >&2 || true
    echo "--- nginx config ---" >&2
    cat "$NGINX_CONF" >&2 || true
    echo "--- direct TCP check to backend port (bypassing nginx) ---" >&2
    nc -zv 127.0.0.1 "$BACKEND_PORT" 2>&1 >&2 || true
    return 1
}

$COMPOSE up -d --build

# A throwaway nginx stitches backend (fastcgi) + frontend (vite) into one
# origin, exactly like deploy/nginx/app.dev.conf.example, so cookies and
# CORS behave the same way they would for a real developer.
BACKEND_PORT="$($COMPOSE port backend 9000 | cut -d: -f2)"
FRONTEND_PORT="$($COMPOSE port frontend 5173 | cut -d: -f2)"

NGINX_CONF="$(mktemp)"
cat > "$NGINX_CONF" <<EOF
server {
    listen 18000;
    location / {
        proxy_pass http://127.0.0.1:$FRONTEND_PORT;
    }
    location /api {
        include fastcgi_params;
        fastcgi_pass 127.0.0.1:$BACKEND_PORT;
        fastcgi_param SCRIPT_FILENAME /var/www/html/public/index.php;
    }
}
EOF

docker rm -f stack-smoke-nginx >/dev/null 2>&1 || true
docker run -d --name stack-smoke-nginx --network host \
    -v "$NGINX_CONF:/etc/nginx/conf.d/default.conf:ro" \
    nginx:alpine >/dev/null

cleanup() {
    docker rm -f stack-smoke-nginx >/dev/null 2>&1 || true
    rm -f "$NGINX_CONF"
    $COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

wait_for_http "$BASE_URL/api/me" 401

ALICE_JAR="$(mktemp)"
BOB_JAR="$(mktemp)"
STAMP="$(date +%s)"

curl -sf -X POST "$BASE_URL/api/register" \
    -H 'Content-Type: application/ld+json' \
    -d "{\"email\":\"alice-$STAMP@example.com\",\"plainPassword\":\"correct-horse-battery\"}" >/dev/null

curl -sf -X POST "$BASE_URL/api/register" \
    -H 'Content-Type: application/ld+json' \
    -d "{\"email\":\"bob-$STAMP@example.com\",\"plainPassword\":\"correct-horse-battery\"}" >/dev/null

curl -sf -X POST "$BASE_URL/api/login" -c "$ALICE_JAR" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"alice-$STAMP@example.com\",\"password\":\"correct-horse-battery\"}" >/dev/null

curl -sf -X POST "$BASE_URL/api/login" -c "$BOB_JAR" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"bob-$STAMP@example.com\",\"password\":\"correct-horse-battery\"}" >/dev/null

ME_EMAIL="$(curl -sf "$BASE_URL/api/me" -b "$ALICE_JAR" | json_get "d['email']")"
[ "$ME_EMAIL" = "alice-$STAMP@example.com" ] || { echo "unexpected /api/me: $ME_EMAIL" >&2; exit 1; }

CREATE_RESPONSE="$(curl -sf -X POST "$BASE_URL/api/graphql" -b "$ALICE_JAR" \
    -H 'Content-Type: application/json' \
    -d '{"query":"mutation($title: String!) { createTask(input: {title: $title, done: false}) { task { id title done } } }","variables":{"title":"Alice task"}}')"
TASK_ID="$(printf '%s' "$CREATE_RESPONSE" | json_get "d['data']['createTask']['task']['id']")"
[ -n "$TASK_ID" ] || { echo "createTask did not return an id: $CREATE_RESPONSE" >&2; exit 1; }

ALICE_TASKS="$(curl -sf -X POST "$BASE_URL/api/graphql" -b "$ALICE_JAR" \
    -H 'Content-Type: application/json' \
    -d '{"query":"query { tasks { id title } }"}' | json_get "len(d['data']['tasks'])")"
[ "$ALICE_TASKS" = "1" ] || { echo "expected alice to see 1 task, saw $ALICE_TASKS" >&2; exit 1; }

BOB_TASKS="$(curl -sf -X POST "$BASE_URL/api/graphql" -b "$BOB_JAR" \
    -H 'Content-Type: application/json' \
    -d '{"query":"query { tasks { id title } }"}' | json_get "len(d['data']['tasks'])")"
[ "$BOB_TASKS" = "0" ] || { echo "expected bob to see 0 tasks (ownership leak!), saw $BOB_TASKS" >&2; exit 1; }

BOB_DELETE="$(curl -s -X POST "$BASE_URL/api/graphql" -b "$BOB_JAR" \
    -H 'Content-Type: application/json' \
    -d "{\"query\":\"mutation(\\\$id: ID!) { deleteTask(input: {id: \\\$id}) { task { id } } }\",\"variables\":{\"id\":\"$TASK_ID\"}}")"
case "$BOB_DELETE" in
    *"not found"*) ;;
    *)
        echo "expected bob's delete of alice's task to fail, got: $BOB_DELETE" >&2
        exit 1
        ;;
esac

UPDATE_RESPONSE="$(curl -sf -X POST "$BASE_URL/api/graphql" -b "$ALICE_JAR" \
    -H 'Content-Type: application/json' \
    -d "{\"query\":\"mutation(\\\$id: ID!, \\\$done: Boolean!) { updateTask(input: {id: \\\$id, done: \\\$done}) { task { id done } } }\",\"variables\":{\"id\":\"$TASK_ID\",\"done\":true}}")"
UPDATE_DONE="$(printf '%s' "$UPDATE_RESPONSE" | json_get "d['data']['updateTask']['task']['done']")"
[ "$UPDATE_DONE" = "True" ] || { echo "updateTask did not persist done=true: $UPDATE_RESPONSE" >&2; exit 1; }

curl -sf -X POST "$BASE_URL/api/graphql" -b "$ALICE_JAR" \
    -H 'Content-Type: application/json' \
    -d "{\"query\":\"mutation(\\\$id: ID!) { deleteTask(input: {id: \\\$id}) { task { id } } }\",\"variables\":{\"id\":\"$TASK_ID\"}}" >/dev/null

curl -sf -i -X POST "$BASE_URL/api/logout" -b "$ALICE_JAR" | grep -qi '^Set-Cookie: BEARER=deleted' \
    || { echo "logout did not clear the BEARER cookie" >&2; exit 1; }

printf '%s\n' 'Stack smoke test passed: register, login, per-user task isolation, and logout all work end-to-end.'
