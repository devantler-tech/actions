#!/usr/bin/env bash
# Exercise the shipped fixture reader and provisioning boundary without network access.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
helper="$root/.github/scripts/go-postgresql-fixture.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
git -C "$scratch" init -q
mkdir -p "$scratch/server"
fixture="$scratch/server/.go-test-fixture.json"
good='{"kind":"postgresql17","namespace":"fixture","database":"fixture_workflow_test"}'
run_reader() { (cd "$scratch" && bash "$helper" resolve server "$1"); }
write_tracked() { printf '%s\n' "$1" >"$fixture"; git -C "$scratch" add -- server/.go-test-fixture.json; }
[[ "$(run_reader optional)" == '{"enabled":false}' ]] || fail 'absent declaration is not disabled'
[[ "$(run_reader disabled)" == '{"enabled":false}' ]] || fail 'explicit disable is not inert'
rc=0
run_reader enabled >"$scratch/out" 2>"$scratch/error" || rc=$?
[[ "$rc" == 2 && ! -s "$scratch/out" ]] || fail 'enabled without a declaration did not fail closed'
write_tracked "$good"
result="$(run_reader enabled)"
jq -e '.enabled == true and .namespace == "fixture" and .database == "fixture_workflow_test" and .owner == "fixture_fixture_owner" and .runtime_env == "FIXTURE_TEST_DATABASE_URL" and .migration_env == "FIXTURE_TEST_MIGRATION_DATABASE_URL"' <<<"$result" >/dev/null || fail 'healthy declaration was not normalized'
[[ "$(run_reader optional)" == "$result" ]] || fail 'direct declaration differs from explicit enable'
for bad in \
  '{}' \
  '[]' \
  '{"kind":"postgresql16","namespace":"fixture","database":"fixture_workflow_test"}' \
  '{"kind":"postgresql17","namespace":true,"database":"fixture_workflow_test"}' \
  '{"kind":"postgresql17","namespace":"pg","database":"pg_workflow_test"}' \
  '{"kind":"postgresql17","namespace":"pg_fixture","database":"pg_fixture_workflow_test"}' \
  '{"kind":"postgresql17","namespace":"fixture;id","database":"fixture_workflow_test"}' \
  '{"kind":"postgresql17","namespace":"fixture","database":"production"}' \
  '{"kind":"postgresql17","namespace":"fixture","database":"other_workflow_test"}' \
  '{"kind":"postgresql17","namespace":"fixture","database":"fixture_workflow_test","url":"https://example.invalid"}' \
  '{"kind":"postgresql17","namespace":"fixture","namespace":"other","database":"other_workflow_test"}' \
  '{"kind":"postgresql17","namespace":"fixture","database":"fixture_workflow_test"} {}' \
  'not-json'; do
  write_tracked "$bad"
  [[ "$(run_reader disabled)" == '{"enabled":false}' ]] || fail 'explicit disable read a malformed declaration'
  rc=0
  run_reader enabled >"$scratch/out" 2>"$scratch/error" || rc=$?
  [[ "$rc" == 2 && ! -s "$scratch/out" ]] || fail 'invalid declaration published fixture outputs'
done
write_tracked "$good"
git -C "$scratch" rm --cached -q -- server/.go-test-fixture.json
rc=0
run_reader optional >"$scratch/out" 2>"$scratch/error" || rc=$?
[[ "$rc" == 2 && ! -s "$scratch/out" ]] || fail 'untracked declaration was admitted'
git -C "$scratch" add -- server/.go-test-fixture.json
rm "$fixture"
rc=0
run_reader optional >"$scratch/out" 2>"$scratch/error" || rc=$?
[[ "$rc" == 2 && ! -s "$scratch/out" ]] || fail 'missing tracked declaration was treated as absent'
printf '%s\n' "$good" >"$scratch/outside.json"
ln -s "$scratch/outside.json" "$fixture"
git -C "$scratch" add -- server/.go-test-fixture.json
rc=0
run_reader optional >"$scratch/out" 2>"$scratch/error" || rc=$?
[[ "$rc" == 2 && ! -s "$scratch/out" ]] || fail 'linked declaration was admitted'
rm "$fixture"
write_tracked "$good"
for module in /tmp ../server server/.. server/.git; do
  rc=0
  (cd "$scratch" && bash "$helper" resolve "$module" enabled) >"$scratch/out" 2>"$scratch/error" || rc=$?
  [[ "$rc" == 2 && ! -s "$scratch/out" ]] || fail 'unsafe module path was admitted'
done
mkdir "$scratch/git-bin"
real_git="$(command -v git)"
export FIXTURE_REAL_GIT="$real_git"
cat >"$scratch/git-bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == ls-files ]]; then
  case "$GIT_FIXTURE_KIND" in
    failed) exit 51 ;;
    partial) "$FIXTURE_REAL_GIT" "$@"; exit 51 ;;
    unterminated)
      line="$("$FIXTURE_REAL_GIT" ls-files --stage -- server/.go-test-fixture.json)"
      printf '%s' "$line"
      exit 0 ;;
    *) exit 98 ;;
  esac
fi
exec "$FIXTURE_REAL_GIT" "$@"
GIT
chmod +x "$scratch/git-bin/git"
for GIT_FIXTURE_KIND in failed partial unterminated; do
  export GIT_FIXTURE_KIND
  rc=0
  PATH="$scratch/git-bin:$PATH" run_reader optional >"$scratch/out" 2>"$scratch/error" || rc=$?
  [[ "$rc" == 2 && ! -s "$scratch/out" ]] || fail 'incomplete Git observation published fixture outputs'
done
mkdir "$scratch/bin"
cat >"$scratch/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  inspect)
    [[ "$*" == "inspect ${FIXTURE_ID} --format {{json .Config}}" ]] || exit 98
    [[ "${INSPECT_FAIL:-0}" == 0 ]] || exit 23
    printf '{"Image":"%s","Env":["POSTGRES_USER=fixture_fixture_owner","POSTGRES_PASSWORD=fixture-only","POSTGRES_DB=postgres"]}\n' "$FIXTURE_IMAGE"
    ;;
  exec)
    if [[ "$*" == "exec ${FIXTURE_ID} pg_isready -h 127.0.0.1 -p 5432 -U fixture_fixture_owner -d postgres -t 1" ]]; then
      count=0
      [[ ! -f "$FIXTURE_READY_CALLS" ]] || count="$(<"$FIXTURE_READY_CALLS")"
      count=$((count + 1))
      printf '%s\n' "$count" >"$FIXTURE_READY_CALLS"
      [[ "${READY_ERROR:-0}" == 0 ]] || exit "$READY_ERROR"
      [[ "$count" -gt "${READY_AFTER:-0}" ]] || exit 1
      exit 0
    fi
    [[ "$*" == "exec -i --env PGPASSWORD=fixture-only ${FIXTURE_ID} psql -X -h 127.0.0.1 -p 5432 -U fixture_fixture_owner -d postgres -v ON_ERROR_STOP=1" ]] || exit 98
    printf 'sql\n' >>"$FIXTURE_SQL_CALLS"
    cat >"$FIXTURE_SQL"
    [[ "${PROVISION_FAIL:-0}" == 0 ]] || exit 23
    ;;
  *) exit 98 ;;
esac
DOCKER
chmod +x "$scratch/bin/docker"
cat >"$scratch/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
[[ "$*" == 2 ]] || exit 98
printf 'wait\n' >>"$FIXTURE_WAIT_CALLS"
SLEEP
chmod +x "$scratch/bin/sleep"
export PATH="$scratch/bin:$PATH" FIXTURE_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export FIXTURE_SQL="$scratch/sql" FIXTURE_IMAGE='postgres:17.11-bookworm@sha256:3645570cccdfa447589da9f57dd740faa29b30938e861289a5574b6ca6b03826'
export FIXTURE_READY_CALLS="$scratch/ready-calls" FIXTURE_SQL_CALLS="$scratch/sql-calls" FIXTURE_WAIT_CALLS="$scratch/wait-calls"
export READY_AFTER=2 READY_ERROR=0
bash "$helper" provision fixture fixture_workflow_test "$FIXTURE_ID" >"$scratch/env"
[[ "$(<"$FIXTURE_READY_CALLS")" == 3 && "$(wc -l <"$FIXTURE_SQL_CALLS" | tr -d '[:space:]')" == 1 && "$(wc -l <"$FIXTURE_WAIT_CALLS" | tr -d '[:space:]')" == 2 ]] || fail 'restarting service was not awaited before its single SQL batch'
grep -Fx 'FIXTURE_TEST_DATABASE_URL=postgres://fixture_runtime:fixture-only@127.0.0.1:5432/fixture_workflow_test?sslmode=disable' "$scratch/env" >/dev/null || fail 'runtime URL was not fixed and local'
grep -Fx 'FIXTURE_TEST_MIGRATION_DATABASE_URL=postgres://fixture_migrator:fixture-only@127.0.0.1:5432/fixture_workflow_test?sslmode=disable' "$scratch/env" >/dev/null || fail 'migration URL was not fixed and local'
grep -F 'NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS' "$FIXTURE_SQL" >/dev/null || fail 'restricted-role contract missing'
grep -F 'REVOKE CREATE ON SCHEMA public FROM PUBLIC' "$FIXTURE_SQL" >/dev/null || fail 'runtime schema authority expanded'
grep -F 'GRANT USAGE ON SCHEMA public TO fixture_runtime' "$FIXTURE_SQL" >/dev/null || fail 'runtime cannot use migrated schema'
for failure in inspect provision image stopped rejecting readiness-command; do
  export INSPECT_FAIL=0 PROVISION_FAIL=0 READY_AFTER=0 READY_ERROR=0
  rm -f "$FIXTURE_READY_CALLS" "$FIXTURE_SQL_CALLS" "$FIXTURE_WAIT_CALLS"
  saved_image="$FIXTURE_IMAGE"
  case "$failure" in inspect) INSPECT_FAIL=1 ;; provision) PROVISION_FAIL=1 ;; image) FIXTURE_IMAGE=postgres:latest ;; stopped) READY_ERROR=1 ;; rejecting) READY_ERROR=2 ;; readiness-command) READY_ERROR=3 ;; esac
  rc=0
  bash "$helper" provision fixture fixture_workflow_test "$FIXTURE_ID" >"$scratch/env" 2>"$scratch/error" || rc=$?
  [[ "$rc" != 0 && ! -s "$scratch/env" ]] || fail 'failed or unproven provisioning published URLs'
  case "$failure" in
    stopped|rejecting)
      [[ "$(<"$FIXTURE_READY_CALLS")" == 30 && "$(wc -l <"$FIXTURE_WAIT_CALLS" | tr -d '[:space:]')" == 29 && ! -e "$FIXTURE_SQL_CALLS" ]] || fail 'unready service exceeded its wait bound or received SQL'
      ;;
    readiness-command) [[ "$(<"$FIXTURE_READY_CALLS")" == 1 && ! -e "$FIXTURE_WAIT_CALLS" && ! -e "$FIXTURE_SQL_CALLS" ]] || fail 'readiness command failure was retried or received SQL' ;;
    provision) [[ "$(wc -l <"$FIXTURE_SQL_CALLS" | tr -d '[:space:]')" == 1 ]] || fail 'failed SQL batch was retried' ;;
  esac
  FIXTURE_IMAGE="$saved_image"
done
export INSPECT_FAIL=0 PROVISION_FAIL=0 READY_ERROR=0
for id in missing --privileged aa; do
  rc=0
  bash "$helper" provision fixture fixture_workflow_test "$id" >"$scratch/env" 2>"$scratch/error" || rc=$?
  [[ "$rc" == 2 && ! -s "$scratch/env" ]] || fail 'unbound container identity was admitted'
done
printf 'PASS: PostgreSQL declarations, bounded TCP recovery, single SQL batch and failure boundaries\n'
