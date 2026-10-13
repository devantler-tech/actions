#!/usr/bin/env bash
# Exercise recovery of a real, cleanly stopped disposable PostgreSQL service.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
scratch="$(mktemp -d)"
name="go-fixture-recovery-${scratch##*/}"
container=''
# Remove the acknowledged service and its recorded anonymous volume; preserve
# the original failure and reject incomplete cleanup observations.
cleanup() {
  result=$?
  trap - EXIT
  if [[ -n "$container" ]]; then
    volumes="$(docker inspect "$container" --format '{{range .Mounts}}{{if and (eq .Type "volume") (eq .Destination "/var/lib/postgresql/data")}}{{.Name}}{{"\n"}}{{end}}{{end}}')" || result=1
    # This fixed image/create call owns exactly one anonymous data volume.
    [[ "${volumes:-}" =~ ^[a-f0-9]{64}$ ]] || result=1
    docker rm --force --volumes "$container" >/dev/null || result=1
    remaining="$(docker ps --all --no-trunc --filter "id=$container" --format '{{.ID}}')" || result=1
    [[ -z "${remaining:-}" ]] || result=1
    while IFS= read -r volume; do
      [[ -n "$volume" ]] || continue
      [[ "$volume" =~ ^[a-f0-9]{64}$ ]] || { result=1; continue; }
      remaining="$(docker volume ls --filter "name=$volume" --format '{{.Name}}')" || result=1
      [[ -z "${remaining:-}" ]] || result=1
    done <<<"${volumes:-}"
  fi
  rm -rf "$scratch"
  exit "$result"
}
trap cleanup EXIT
image='postgres:17.11-bookworm@sha256:3645570cccdfa447589da9f57dd740faa29b30938e861289a5574b6ca6b03826'
container="$(docker create --name "$name" --publish 127.0.0.1:55444:5432 \
  --env POSTGRES_USER=ci_fixture_fixture_owner --env POSTGRES_PASSWORD=fixture-only \
  --env POSTGRES_DB=postgres "$image")"
[[ "$container" =~ ^[a-f0-9]{64}$ ]] || { echo 'FAIL: unbound native service' >&2; exit 1; }
docker start "$container" >/dev/null
ready=false
for attempt in {1..30}; do
  if docker exec "$container" pg_isready -h 127.0.0.1 -p 5432 -U ci_fixture_fixture_owner -d postgres -t 1 >/dev/null; then
    ready=true
    break
  fi
  [[ "$attempt" == 30 ]] || sleep 2
done
[[ "$ready" == true ]] || { echo 'FAIL: initial native service never became ready' >&2; exit 1; }
# Model the clean service interruption observed during runner initialization.
docker stop --time 20 "$container" >/dev/null
state="$(docker inspect "$container" --format '{{json .State}}')"
jq -e '.Status == "exited" and .Running == false and .ExitCode == 0' <<<"$state" >/dev/null
bash "$root/.github/scripts/go-postgresql-fixture.sh" provision ci_fixture ci_fixture_workflow_test "$container" >"$scratch/env"
[[ "$(docker inspect "$container" --format '{{.State.Running}}')" == true ]] || { echo 'FAIL: native service was not recovered' >&2; exit 1; }
while IFS='=' read -r key value; do
  case "$key" in
    CI_FIXTURE_TEST_DATABASE_URL|CI_FIXTURE_TEST_MIGRATION_DATABASE_URL)
      # The production provisioner uses the service job's fixed port. This local
      # regression uses its own loopback port accepted by the native Go fixture.
      export "$key=${value/127.0.0.1:5432/127.0.0.1:55444}"
      ;;
    *) echo 'FAIL: unexpected fixture output' >&2; exit 1 ;;
  esac
done <"$scratch/env"
cd "$root/.github/tests/go-postgresql-fixture"
go test -count=1 -race -timeout=90s ./...
echo 'PASS: stopped native service recovered; real database and restricted-role tests passed'
