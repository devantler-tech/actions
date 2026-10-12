#!/usr/bin/env bash
# Immutable catalogue-owned data reader and disposable-service provisioner.
set -euo pipefail
export LC_ALL=C
image='postgres:17.11-bookworm@sha256:3645570cccdfa447589da9f57dd740faa29b30938e861289a5574b6ca6b03826'
fail() { printf 'go-postgresql-fixture: %s\n' "$*" >&2; exit 2; }
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
provision() {
  [[ "$#" == 3 ]] || fail 'provision needs normalized identities and a service identity'
  identities "$1" "$2"
  container="$3"
  [[ "$container" =~ ^[a-f0-9]{64}$ ]] || fail 'service identity is not bound'
  config="$(docker inspect "$container" --format '{{json .Config}}')" || fail 'service observation failed'
  jq -e --arg image "$image" --arg owner "$owner" 'type == "object"
    and .Image == $image and (.Env | type == "array")
    and ([.Env[] | select(startswith("POSTGRES_USER="))] == ["POSTGRES_USER=" + $owner])
    and ([.Env[] | select(startswith("POSTGRES_PASSWORD="))] == ["POSTGRES_PASSWORD=fixture-only"])
    and ([.Env[] | select(startswith("POSTGRES_DB="))] == ["POSTGRES_DB=postgres"])' <<<"$config" >/dev/null 2>&1 || fail 'service does not match the fixed fixture'
  # The service ID comes only from job.services, not consumer data. Execute in
  # that observed container; no consumer endpoint, credentials or SQL are read.
  docker exec -i --env PGPASSWORD=fixture-only "$container" \
    psql -X -U "$owner" -d postgres -v ON_ERROR_STOP=1 >/dev/null <<SQL
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
