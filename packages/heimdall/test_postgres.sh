#!/usr/bin/env bash
set -euo pipefail

# Opt-in: runs tests/cases/heimdall.d6 against a live PostgreSQL server in a
# throwaway podman container. test.sh covers SQLite on every run.
diamond="${DIAMOND_BIN:-diamond}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
if ! command -v podman >/dev/null 2>&1; then
    echo "podman not found -- skipping the live heimdall PostgreSQL test" >&2
    exit 0
fi
test_project="$(mktemp -d)"
container="diamond-heimdall-postgres-test"
cleanup() { podman stop "$container" >/dev/null 2>&1 || true; }
trap 'cleanup; cd /; rm -rf "$test_project"' EXIT
"$root/tools/install_local_cuts.sh" "$test_project" >/dev/null
cd "$test_project"

podman rm -f "$container" >/dev/null 2>&1 || true
podman run --rm -d --name "$container" -e POSTGRES_PASSWORD=diamondtest -e POSTGRES_DB=heimdall_test \
    -p "127.0.0.1::5432" docker.io/library/postgres:16-alpine >/dev/null
port="$(podman port "$container" 5432/tcp | head -n1 | sed "s/.*://")"
ready=false
for _ in $(seq 1 60); do
    if podman exec "$container" psql -h 127.0.0.1 -U postgres -d heimdall_test -c "SELECT 1" >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 1
done
if [[ "$ready" != true ]]; then
    echo "postgres did not become ready" >&2
    exit 1
fi
sleep 2
export DIAMOND_PG_TEST_CONNINFO="host=127.0.0.1 port=${port} dbname=heimdall_test user=postgres password=diamondtest"
"$diamond" "$root/tests/cases/heimdall.d6"
echo "heimdall PostgreSQL test passed"
