#!/usr/bin/env bash
# Immutable catalogue-owned data reader and disposable-service provisioner.
set -euo pipefail
export LC_ALL=C
image='postgres:17.11-bookworm@sha256:3645570cccdfa447589da9f57dd740faa29b30938e861289a5574b6ca6b03826'
# Refuse invalid or unproven fixture data without publishing connection URLs.
fail() { printf 'go-postgresql-fixture: %s\n' "$*" >&2; exit 2; }
# Validate the closed identity grammar and derive the fixed role and env names.
identities() {
  namespace="$1"; database="$2"
  [[ "$namespace" =~ ^[a-z][a-z0-9_]{0,31}$ ]] || fail 'invalid fixture namespace'
  [[ "$namespace" != pg && "$namespace" != pg_* ]] || fail 'fixture namespace uses PostgreSQL reserved roles'
  [[ "$database" =~ ^[a-z][a-z0-9_]{0,47}_test$ && "$database" == "${namespace}_"* ]] || fail 'invalid fixture database'
  owner="${namespace}_fixture_owner"
  migrator="${namespace}_migrator"
  runtime="${namespace}_runtime"
  prefix="$(printf '%s' "$namespace" | tr '[:lower:]' '[:upper:]')"
}
# Normalize one tracked declaration; an explicit disabled mode reads no file.
resolve() {
  [[ "$#" == 2 ]] || fail 'resolve needs a module and mode'
  module="$1"; mode="$2"
  case "$mode" in
    disabled) printf '{"enabled":false}\n'; return ;;
    optional|enabled) ;;
    *) fail 'invalid fixture mode' ;;
  esac
  top="$(git rev-parse --show-toplevel)" || fail 'cannot read repository identity'
  [[ "$(pwd -P)" == "$(cd "$top" && pwd -P)" ]] || fail 'reader must run at the repository root'
  if [[ "$module" != . ]]; then
    [[ "$module" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] || fail 'unsafe module path'
    IFS=/ read -r -a parts <<<"$module"
    current="$top"
    for part in "${parts[@]}"; do
      [[ "$part" != . && "$part" != .. && "$part" != .git ]] || fail 'unsafe module path'
      current="$current/$part"
      [[ ! -L "$current" && -d "$current" ]] || fail 'module path is linked or absent'
    done
    file="$module/.go-test-fixture.json"
  else
    file=.go-test-fixture.json
  fi
  inventory="$(mktemp)"
  trap 'rm -f -- "$inventory"' EXIT
  git ls-files --stage -z -- "$file" >"$inventory" || fail 'cannot read declaration inventory'
  records=0; record=''
  while IFS= read -r -d '' record; do
    records=$((records + 1))
    [[ "$records" == 1 && "$record" == *$'\t'* ]] || fail 'declaration inventory is conflicted'
    metadata="${record%%$'\t'*}"
    indexed_path="${record#*$'\t'}"
    [[ "$metadata" =~ ^100644\ ([a-f0-9]{40}|[a-f0-9]{64})\ 0$ && "$indexed_path" == "$file" ]] || fail 'declaration inventory is unsafe'
  done <"$inventory"
  [[ -z "$record" ]] || fail 'declaration inventory has an unterminated record'
  if [[ "$records" == 0 ]]; then
    [[ ! -e "$file" && ! -L "$file" ]] || fail 'declaration is not tracked'
    [[ "$mode" == optional ]] || fail 'enabled fixture declaration is absent'
    printf '{"enabled":false}\n'
    return
  fi
  [[ -f "$file" && -r "$file" && ! -L "$file" ]] || fail 'tracked declaration is absent or linked'
  bytes="$(wc -c <"$file" | tr -d '[:space:]')"
  [[ "$bytes" =~ ^[0-9]+$ && "$bytes" -le 4096 ]] || fail 'declaration exceeds its bound'
  jq -se 'length == 1 and (.[0] | type == "object"
    and keys == ["database","kind","namespace"]
    and .kind == "postgresql17"
    and (.namespace | type == "string")
    and (.database | type == "string"))' "$file" >/dev/null 2>&1 || fail 'invalid fixture declaration'
  # Ordinary JSON readers silently keep the last duplicate key. Count decoded
  # streaming paths too, so duplicates (including escaped spellings) are refused.
  jq --stream -se '[.[] | select(length == 2) | .[0]] | sort == [["database"],["kind"],["namespace"]]' "$file" >/dev/null 2>&1 || fail 'duplicate or nested fixture fields'
  identities "$(jq -r .namespace "$file")" "$(jq -r .database "$file")"
  jq -nc --arg namespace "$namespace" --arg database "$database" --arg image "$image" \
    --arg owner "$owner" --arg migrator "$migrator" --arg runtime "$runtime" \
    --arg runtime_env "${prefix}_TEST_DATABASE_URL" --arg migration_env "${prefix}_TEST_MIGRATION_DATABASE_URL" \
    '{enabled:true, namespace:$namespace, database:$database, image:$image,
      owner:$owner, migrator:$migrator, runtime:$runtime,
      runtime_env:$runtime_env, migration_env:$migration_env}'
}
# Admit complete observations of the fixed service, recover one clean stop and
# publish local fixture URLs only after one successful SQL batch.
provision() {
  [[ "$#" == 3 ]] || fail 'provision needs normalized identities and a service identity'
  identities "$1" "$2"
  container="$3"
  [[ "$container" =~ ^[a-f0-9]{64}$ ]] || fail 'service identity is not bound'
  config="$(docker inspect "$container" --format '{{json .Config}}')" || fail 'service observation failed'
  jq -se --arg image "$image" --arg owner "$owner" '
    if length != 1 then error("ambiguous service configuration") else .[0] end |
    type == "object"
    and .Image == $image and (.Env | type == "array")
    and ([.Env[] | select(startswith("POSTGRES_USER="))] == ["POSTGRES_USER=" + $owner])
    and ([.Env[] | select(startswith("POSTGRES_PASSWORD="))] == ["POSTGRES_PASSWORD=fixture-only"])
    and ([.Env[] | select(startswith("POSTGRES_DB="))] == ["POSTGRES_DB=postgres"])' <<<"$config" >/dev/null 2>&1 || fail 'service does not match the fixed fixture'
  # The service ID comes only from job.services, not consumer data. Execute in
  # that observed container; no consumer endpoint, credentials or SQL are read.
  # Runner hardening can restart Docker after its initial service health check.
  # Recover a cleanly stopped, still-bound service once, before any SQL. Never
  # restart an unhealthy/failed service or replay a partially executed batch.
  state="$(docker inspect "$container" --format '{{json .State}}')" || fail 'service state observation failed'
  lifecycle="$(jq -ser '
    if length != 1 then error("ambiguous service state") else .[0] end |
    if type != "object" or .Error != "" or .ExitCode != 0
      or .Paused != false or .Restarting != false
      or .OOMKilled != false or .Dead != false then error("unsafe service state")
    elif .Status == "running" and .Running == true then "running"
    elif .Status == "exited" and .Running == false then "stopped"
    else error("unsafe service state") end' <<<"$state")" || fail 'service state is not safe for provisioning'
  if [[ "$lifecycle" == stopped ]]; then
    started="$(docker start "$container")" || fail 'bound service start failed'
    [[ "$started" == "$container" ]] || fail 'service start identity differs'
  fi
  # Wait for the final TCP server in that same container before issuing SQL;
  # the image's temporary initialization server only accepts Unix connections.
  ready=false
  for attempt in {1..30}; do
    rc=0
    docker exec "$container" pg_isready -h 127.0.0.1 -p 5432 -U "$owner" -d postgres -t 1 >/dev/null 2>&1 || rc=$?
    case "$rc" in
      0) ready=true; break ;;
      1|2) ;; # Restarting/stopped container, or server not accepting connections.
      *) fail 'service readiness command failed' ;;
    esac
    [[ "$attempt" == 30 ]] || sleep 2
  done
  [[ "$ready" == true ]] || fail 'service did not become TCP-ready within its bounded wait'
  # Execute this batch once: retrying partially created roles is unsafe.
  docker exec -i --env PGPASSWORD=fixture-only "$container" \
    psql -X -h 127.0.0.1 -p 5432 -U "$owner" -d postgres -v ON_ERROR_STOP=1 >/dev/null <<SQL
CREATE ROLE $migrator LOGIN PASSWORD 'fixture-only' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
CREATE ROLE $runtime LOGIN PASSWORD 'fixture-only' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
CREATE DATABASE $database OWNER $migrator;
\connect $database
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO $runtime;
SQL
  # Publish only after complete provisioning. These are test-only local URLs,
  # with separately restricted roles; a caller cannot supply an arbitrary env key.
  printf '%s_TEST_DATABASE_URL=postgres://%s:fixture-only@127.0.0.1:5432/%s?sslmode=disable\n' "$prefix" "$runtime" "$database"
  printf '%s_TEST_MIGRATION_DATABASE_URL=postgres://%s:fixture-only@127.0.0.1:5432/%s?sslmode=disable\n' "$prefix" "$migrator" "$database"
}
command="${1:-}"
shift || true
case "$command" in
  resolve) resolve "$@" ;;
  provision) provision "$@" ;;
  *) fail 'expected resolve or provision' ;;
esac
