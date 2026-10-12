#!/usr/bin/env bash
# Check actual production wiring, including both independent disposable services.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
workflow="${2:-$root/.github/workflows/validate-go-project.yaml}"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
export FIXTURE_GUARD="\${{ needs.changes.outputs.fixture-enabled == 'true' }}"
export FIXTURE_IMAGE_BINDING="\${{ needs.changes.outputs.fixture-enabled == 'true' && 'postgres:17.11-bookworm@sha256:3645570cccdfa447589da9f57dd740faa29b30938e861289a5574b6ca6b03826' || '' }}"
export FIXTURE_OWNER_BINDING="\${{ needs.changes.outputs.fixture-owner }}"
export FIXTURE_NAMESPACE_BINDING="\${{ needs.changes.outputs.fixture-namespace }}"
export FIXTURE_DATABASE_BINDING="\${{ needs.changes.outputs.fixture-database }}"
export FIXTURE_SERVICE_BINDING="\${{ job.services.postgres.id }}"
export FIXTURE_REPOSITORY="\${{ job.workflow_repository }}" FIXTURE_REF="\${{ job.workflow_sha }}"
export FIXTURE_READER_GUARD="\${{ steps.fixture-mode.outputs.mode != 'disabled' }}"
export FIXTURE_DIRECT_BINDING="\${{ toJSON(inputs) == '{}' && contains(github.workflow_ref, '/.github/workflows/validate-go-project.yaml@') }}"
export FIXTURE_INPUT_BINDING="\${{ inputs.enable-postgresql-fixture }}"
[[ "$(yq '.on.workflow_call.inputs.enable-postgresql-fixture.default' "$workflow")" == false ]] || fail 'called fixture default is not off'
yq -e '[.jobs.changes.steps[] | select(.name == "Checkout immutable PostgreSQL fixture reader") | select(.if == strenv(FIXTURE_READER_GUARD) and .with.repository == strenv(FIXTURE_REPOSITORY) and .with.ref == strenv(FIXTURE_REF) and .with["persist-credentials"] == false and .with.path == ".devantler-tech-go-fixture" and .with["sparse-checkout"] == ".github/scripts/go-postgresql-fixture.sh")] | length == 1' "$workflow" >/dev/null || fail 'declaration reader origin is not immutable'
yq -e '[.jobs.changes.steps[] | select(.name == "Select PostgreSQL fixture mode") | select(.env.DIRECT_REQUIRED_RUN == strenv(FIXTURE_DIRECT_BINDING) and .env.FIXTURE_OPT_IN == strenv(FIXTURE_INPUT_BINDING) and .if == null and .["continue-on-error"] != true)] | length == 1' "$workflow" >/dev/null || fail 'direct/called admission binding changed'
for job in test coverage; do
  JOB="$job" yq -e '.jobs[strenv(JOB)].services.postgres.image == strenv(FIXTURE_IMAGE_BINDING)' "$workflow" >/dev/null || fail "$job has no normalized conditional fixture image"
  JOB="$job" yq -e '.jobs[strenv(JOB)].services.postgres.env.POSTGRES_USER == strenv(FIXTURE_OWNER_BINDING) and .jobs[strenv(JOB)].services.postgres.env.POSTGRES_PASSWORD == "fixture-only" and .jobs[strenv(JOB)].services.postgres.env.POSTGRES_DB == "postgres"' "$workflow" >/dev/null || fail "$job fixture identity is not bound"
  JOB="$job" yq -e '[.jobs[strenv(JOB)].steps[] | select(.name == "Prepare disposable PostgreSQL fixture") | select(.env.FIXTURE_SERVICE_ID == strenv(FIXTURE_SERVICE_BINDING) and .env.FIXTURE_NAMESPACE == strenv(FIXTURE_NAMESPACE_BINDING) and .env.FIXTURE_DATABASE == strenv(FIXTURE_DATABASE_BINDING) and .if == strenv(FIXTURE_GUARD) and .["working-directory"] == ".")] | length == 1' "$workflow" >/dev/null || fail "$job cannot bind provisioning to its own service"
  JOB="$job" yq -e '[.jobs[strenv(JOB)].steps[] | select(.name == "Prepare disposable PostgreSQL fixture") | select(.["continue-on-error"] == true)] | length == 0' "$workflow" >/dev/null || fail 'provision failure can be ignored'
  JOB="$job" yq -e '[.jobs[strenv(JOB)].steps[] | select(.name == "Checkout immutable PostgreSQL fixture provisioner") | select(.if == strenv(FIXTURE_GUARD) and .with.repository == strenv(FIXTURE_REPOSITORY) and .with.ref == strenv(FIXTURE_REF) and .with["persist-credentials"] == false and .with.path == ".devantler-tech-go-fixture" and .with["sparse-checkout"] == ".github/scripts/go-postgresql-fixture.sh")] | length == 1' "$workflow" >/dev/null || fail 'fixture helper origin is not immutable'
  JOB="$job" yq -o=json '.jobs[strenv(JOB)].services.postgres' "$workflow" | jq -e 'keys == ["env","image","options","ports"] and (.env | keys == ["POSTGRES_DB","POSTGRES_PASSWORD","POSTGRES_USER"]) and .ports == ["5432:5432"] and .options == "--health-cmd pg_isready --health-interval 10s --health-timeout 5s --health-retries 5"' >/dev/null || fail 'service accepts additional authority'
done
GO_ADMISSION="\${{ (github.repository == 'devantler-tech/actions' && inputs.working-directory == '.github/tests/go-postgresql-fixture') && 'true' || steps.filter.outputs.go }}" yq -e '.jobs.changes.outputs.go == strenv(GO_ADMISSION)' "$workflow" >/dev/null || fail 'native fixture can skip workflow-only corrections'
yq -o=json '.jobs | {"test":.test.permissions,"coverage":.coverage.permissions}' "$workflow" | jq -e '.test == {"contents":"read"} and .coverage == {"contents":"read","code-quality":"write"}' >/dev/null || fail 'fixture test workers gained repository-write authority'
[[ "${1:-}" != --inspect ]] || exit 0
# This legacy native caller exercises its own production interface. The static
# grants are the existing callee ceiling, not new worker or service authority.
caller="$root/.github/workflows/ci.yaml"
yq -e '.jobs.test-validate-go-postgresql-fixture.uses == "./.github/workflows/validate-go-project.yaml" and .jobs.test-validate-go-postgresql-fixture.with["working-directory"] == ".github/tests/go-postgresql-fixture" and .jobs.test-validate-go-postgresql-fixture.with["enable-postgresql-fixture"] == true and .jobs.test-validate-go-postgresql-fixture.with["apply-signed-fixes"] == false and .jobs.test-validate-go-postgresql-fixture.secrets == null and .jobs.test-validate-go-postgresql-fixture["continue-on-error"] == null' "$caller" >/dev/null || fail 'native legacy caller changed its source, mode or credential boundary'
yq -e '.jobs.ci-required-checks.needs | contains(["test-validate-go-postgresql-fixture"])' "$caller" >/dev/null || fail 'native fixture result is not required'
yq -e '[.jobs.ci-required-checks.steps[] | .env.JOB_RESULTS // "" | select(contains("needs.test-validate-go-postgresql-fixture.result"))] | length == 1' "$caller" >/dev/null || fail 'native fixture result is absent from the reducer'
step() { JOB="$1" STEP="$2" yq -r '.jobs[strenv(JOB)].steps[] | select(.name == strenv(STEP)) | .run' "$workflow"; }
step changes 'Select PostgreSQL fixture mode' >"$scratch/mode.sh"
git -C "$scratch" init -q
mkdir "$scratch/server"
declaration="$scratch/server/.go-test-fixture.json"
for state in absent valid malformed untracked linked removed; do
  git -C "$scratch" rm --cached -q --ignore-unmatch -- server/.go-test-fixture.json
  rm -f "$declaration"
  case "$state" in
    valid|untracked|removed) printf '%s\n' '{"kind":"postgresql17","namespace":"fixture","database":"fixture_workflow_test"}' >"$declaration" ;;
    malformed) printf 'not-json\n' >"$declaration" ;;
    linked) ln -s "$scratch/nonexistent" "$declaration" ;;
  esac
  if [[ "$state" == valid || "$state" == malformed || "$state" == removed ]]; then git -C "$scratch" add -- server/.go-test-fixture.json; fi
  [[ "$state" != removed ]] || rm "$declaration"
  for direct in false true; do
    for opt in '' false true; do
      export FIXTURE_MODULE=server FIXTURE_OPT_IN="$opt" DIRECT_REQUIRED_RUN="$direct" GITHUB_OUTPUT="$scratch/output"
      : >"$GITHUB_OUTPUT"
      (cd "$scratch" && bash "$scratch/mode.sh")
      expected=disabled
      if [[ "$opt" == true ]]; then expected=enabled
      elif [[ "$direct" == true && "$state" != absent ]]; then expected=optional; fi
      [[ "$(<"$GITHUB_OUTPUT")" == "mode=$expected" ]] || fail "actual fixture admission changed: $state/$direct/$opt"
      rc=0
      (cd "$scratch" && bash "$root/.github/scripts/go-postgresql-fixture.sh" resolve server "$expected") >"$scratch/result" 2>"$scratch/error" || rc=$?
      if [[ "$expected" == disabled ]]; then [[ "$rc" == 0 && "$(<"$scratch/result")" == '{"enabled":false}' ]] || fail 'called disable inspected consumer data'
      elif [[ "$state" == valid ]]; then [[ "$rc" == 0 ]] || fail 'valid tracked opt-in failed'
      else [[ "$rc" != 0 && ! -s "$scratch/result" ]] || fail 'invalid admitted data published fixture outputs'; fi
    done
  done
done
export FIXTURE_MODULE='' FIXTURE_OPT_IN=true DIRECT_REQUIRED_RUN=true GITHUB_OUTPUT="$scratch/output"
: >"$GITHUB_OUTPUT"
(cd "$scratch" && bash "$scratch/mode.sh")
[[ "$(<"$GITHUB_OUTPUT")" == mode=disabled ]] || fail 'no selected module was admitted'

# Execute the declaration-to-output wrapper, including a partial failed helper.
step changes 'Resolve PostgreSQL fixture declaration' >"$scratch/resolve.sh"
export GITHUB_WORKSPACE="$scratch/reader-workspace" FIXTURE_MODULE=server FIXTURE_MODE=enabled
for failure in 0 23; do
  mkdir -p "$GITHUB_WORKSPACE/.devantler-tech-go-fixture/.github/scripts"
  cat >"$GITHUB_WORKSPACE/.devantler-tech-go-fixture/.github/scripts/go-postgresql-fixture.sh" <<'READER'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'resolve server enabled' ]] || exit 98
printf '%s\n' '{"enabled":true,"owner":"fixture_fixture_owner","namespace":"fixture","database":"fixture_workflow_test"}'
exit "$FIXTURE_FAIL"
READER
  export FIXTURE_FAIL="$failure" GITHUB_OUTPUT="$scratch/reader-output"
  : >"$GITHUB_OUTPUT"
  rc=0
  bash "$scratch/resolve.sh" >"$scratch/out" 2>"$scratch/error" || rc=$?
  [[ ! -e "$GITHUB_WORKSPACE/.devantler-tech-go-fixture" ]] || fail 'reader checkout survived into consumer jobs'
  if [[ "$failure" == 0 ]]; then
    [[ "$rc" == 0 && "$(<"$GITHUB_OUTPUT")" == "$(printf 'enabled=true\nowner=fixture_fixture_owner\nnamespace=fixture\ndatabase=fixture_workflow_test')" ]] || fail 'resolved identities did not reach job outputs'
  else [[ "$rc" == 23 && ! -s "$GITHUB_OUTPUT" ]] || fail 'partial failed reader published outputs'; fi
done

# Run the actual reservation and provision blocks; failures cannot export partial URLs.
for job in test coverage; do
  step "$job" 'Reserve PostgreSQL fixture helper path' >"$scratch/reserve.sh"
  step "$job" 'Prepare disposable PostgreSQL fixture' >"$scratch/provision.sh"
  export GITHUB_WORKSPACE="$scratch/workspace" GITHUB_ENV="$scratch/env"
  mkdir -p "$GITHUB_WORKSPACE"
  helper_dir="$GITHUB_WORKSPACE/.devantler-tech-go-fixture"
  for occupied in file link directory; do
    case "$occupied" in file) : >"$helper_dir" ;; link) ln -s "$scratch/nonexistent" "$helper_dir" ;; directory) mkdir "$helper_dir" ;; esac
    if bash "$scratch/reserve.sh"; then fail 'occupied helper path was admitted'; fi
    if [[ "$occupied" == directory ]]; then rmdir "$helper_dir"; else rm "$helper_dir"; fi
  done
  bash "$scratch/reserve.sh"
  for failure in 0 23; do
    mkdir -p "$helper_dir/.github/scripts"
    cat >"$helper_dir/.github/scripts/go-postgresql-fixture.sh" <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == "provision fixture fixture_workflow_test ${FIXTURE_SERVICE_ID}" ]] || exit 98
printf 'FIXTURE_TEST_DATABASE_URL=fictional\n'
exit "$FIXTURE_FAIL"
HELPER
    export FIXTURE_NAMESPACE=fixture FIXTURE_DATABASE=fixture_workflow_test FIXTURE_SERVICE_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa FIXTURE_FAIL="$failure"
    : >"$GITHUB_ENV"
    rc=0
    bash "$scratch/provision.sh" >"$scratch/out" 2>"$scratch/error" || rc=$?
    [[ ! -e "$helper_dir" ]] || fail 'provisioner checkout survived into consumer tests'
    if [[ "$failure" == 0 ]]; then [[ "$rc" == 0 && "$(<"$GITHUB_ENV")" == FIXTURE_TEST_DATABASE_URL=fictional ]] || fail 'successful provision outputs absent'
    else [[ "$rc" == 23 && ! -s "$GITHUB_ENV" ]] || fail 'partial failed provisioning published environment'; fi
  done
done

# Execute both shipped test-command branches and their failure propagation.
# This frozen legacy workflow has no disk-measurement input. Both ambient values
# must remain inert rather than importing an unrelated maintained capability.
mkdir -p "$scratch/bin" "$scratch/runner"
cat >"$scratch/bin/go" <<'GO'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FIXTURE_COMMAND_LOG"
exit "$FIXTURE_COMMAND_RC"
GO
chmod +x "$scratch/bin/go"
cat >"$scratch/runner/measure-go-disk.sh" <<'MEASURE'
#!/usr/bin/env bash
printf 'measure=%s\n' "$1" >>"$FIXTURE_COMMAND_LOG"
shift
exec "$@"
MEASURE
export PATH="$scratch/bin:$PATH" RUNNER_TEMP="$scratch/runner" FIXTURE_COMMAND_LOG="$scratch/commands"
for job in test coverage; do
  if [[ "$job" == test ]]; then name='🧪 Test'; base='test ./...'
  else name='📄 Generate coverage'; base='test -race -coverprofile=coverage.txt -covermode=atomic ./...'; fi
  step "$job" "$name" >"$scratch/command.sh"
  for enabled in '' false true; do
    for measurement in false true; do
      for failure in 0 7; do
        export FIXTURE_ENABLED="$enabled" MEASURE_DISK_USAGE="$measurement" FIXTURE_COMMAND_RC="$failure"
        : >"$FIXTURE_COMMAND_LOG"
        rc=0
        bash "$scratch/command.sh" || rc=$?
        expected="$base"
        [[ "$enabled" != true ]] || expected="test -count=1 ${base#test }"
        [[ "$rc" == "$failure" && "$(<"$FIXTURE_COMMAND_LOG")" == "$expected" ]] || fail 'test scope/cache/measurement/failure routing changed'
      done
    done
  done
done
for mutation in \
  '.on.workflow_call.inputs.enable-postgresql-fixture.default = true' \
  '.jobs.test.services.postgres.image = "postgres:latest"' \
  '.jobs.coverage.services.postgres.volumes = ["/:/host"]' \
  '.jobs.test.permissions.contents = "write"' \
  '.jobs.changes.outputs.go = "false"' \
  '(.jobs.changes.steps[] | select(.name == "Checkout immutable PostgreSQL fixture reader").with.ref) = "main"' \
  '(.jobs.changes.steps[] | select(.name == "Checkout immutable PostgreSQL fixture reader").with.repository) = "untrusted/fixture"' \
  '(.jobs.changes.steps[] | select(.name == "Checkout immutable PostgreSQL fixture reader").with.persist-credentials) = true' \
  '(.jobs.changes.steps[] | select(.name == "Checkout immutable PostgreSQL fixture reader").with.path) = "server"' \
  '(.jobs.test.steps[] | select(.name == "Checkout immutable PostgreSQL fixture provisioner").with.ref) = "main"' \
  '(.jobs.coverage.steps[] | select(.name == "Checkout immutable PostgreSQL fixture provisioner").with.persist-credentials) = true' \
  '(.jobs.test.steps[] | select(.name == "Prepare disposable PostgreSQL fixture").if) = "always()"' \
  '(.jobs.coverage.steps[] | select(.name == "Prepare disposable PostgreSQL fixture").continue-on-error) = true'; do
  yq "$mutation" "$workflow" >"$scratch/mutated.yaml"
  if bash "$0" --inspect "$scratch/mutated.yaml" >"$scratch/out" 2>"$scratch/error"; then fail "mutated workflow was admitted: $mutation"; fi
done
printf 'PASS: actual admission, immutable services, reader/provision cleanup, uncached legacy routing and thirteen workflow refusals\n'
