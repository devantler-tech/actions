#!/usr/bin/env bash

# Exercise the actual CI wiring step. A test file without a run command must
# fail even if its name occurs in comments, step metadata, or another filename.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

yq -r '.jobs.lint-ci-coverage-parity.steps[] | select(.name == "📋 Check ci.yaml test wiring is complete") | .run' \
  "$root/.github/workflows/ci.yaml" >"$work/guard.sh"
[[ -s "$work/guard.sh" ]] || fail 'CI wiring guard is missing'
mkdir -p "$work/repo/.github/workflows" "$work/repo/.github/tests" "$work/repo/fixture-action"
touch "$work/repo/fixture-action/action.yaml"
cat >"$work/base.yaml" <<'YAML'
jobs:
  tests:
    steps:
      - uses: ./fixture-action
      - run: echo baseline
  ci-required-checks:
    needs: [tests]
    steps:
      - name: 📊 Summarize workflow result
        env:
          JOB_RESULTS: ${{ needs.tests.result }}
        run: echo summary
YAML
ci="$work/repo/.github/workflows/ci.yaml"
cp "$work/base.yaml" "$ci"

run_guard() { (cd "$work/repo" && bash -euo pipefail "$work/guard.sh") >"$work/result" 2>&1; }
blocked() {
  if run_guard; then fail "$1: unwired test was accepted"; fi
  grep -qF '.github/tests/test-sentinel.sh' "$work/result" || fail "$1: missing script diagnostic"
  grep -qF 'run: bash' "$work/result" || fail "$1: missing remediation"
  echo "PASS: $1"
}

run_guard || fail 'empty test directory should be accepted'
touch "$work/repo/.github/tests/test-sentinel.sh"
blocked 'new test without a CI step'

# Remove only the new production check: the same unwired fixture must pass the
# older action/workflow/result checks, proving the failure above is specific.
awk '
  /^# \(3\) shell test ->/ { skip=1 }
  /^if \[\[ "\$status" -eq 0/ { skip=0 }
  !skip { print }
' "$work/guard.sh" >"$work/ablated.sh"
if ! (cd "$work/repo" && bash -euo pipefail "$work/ablated.sh") >"$work/result" 2>&1; then
  fail 'ablation still rejected the otherwise-valid unwired fixture'
fi
echo 'PASS: removing the script check restores the silent gap'

# Real run commands, including arguments and conventional quoting, satisfy the
# contract. These are distinct from mentioning a filename somewhere in YAML.
for command in 'bash .github/tests/test-sentinel.sh' 'bash "./.github/tests/test-sentinel.sh" fixture.yaml' "bash '.github/tests/test-sentinel.sh'" './.github/tests/test-sentinel.sh'; do
  COMMAND="$command" yq '.jobs.tests.steps += [{"run": strenv(COMMAND)}]' "$work/base.yaml" >"$ci"
  run_guard || fail "valid invocation rejected: $command"
done
echo 'PASS: direct and bash invocations with quoting and arguments'

COMMAND=$'# Regression gate\nbash .github/tests/test-sentinel.sh\n' yq '.jobs.tests.steps += [{"run": strenv(COMMAND)}]' "$work/base.yaml" >"$ci"
run_guard || fail 'comments and blank lines around an invocation were rejected'
echo 'PASS: comments around a dedicated invocation'

# These are literal GitHub expressions, not shell interpolation.
# shellcheck disable=SC2016
for condition in 'false' '${{ false }}' '${{ github.event_name == "never" }}'; do
  CONDITION="$condition" yq '.jobs.tests.steps += [{"if": strenv(CONDITION), "run": "bash .github/tests/test-sentinel.sh"}]' "$work/base.yaml" >"$ci"
  blocked "conditional test step: $condition"
done
yq '.jobs.tests.steps += [{"if": false, "run": "bash .github/tests/test-sentinel.sh"}]' "$work/base.yaml" >"$ci"
blocked 'boolean false test step'

# A job condition skips all of its otherwise-unconditional steps. The repository
# intentionally omits tests on merge groups and release-only runs; only that exact
# scheduling gate, or no job gate, is part of the supported wiring contract.
# shellcheck disable=SC2016
for condition in 'false' '${{ false }}' '${{ github.event_name == "never" }}'; do
  CONDITION="$condition" yq '.jobs.tests.if = strenv(CONDITION) | .jobs.tests.steps += [{"run": "bash .github/tests/test-sentinel.sh"}]' "$work/base.yaml" >"$ci"
  blocked "conditional test job: $condition"
done
yq '.jobs.tests.if = false | .jobs.tests.steps += [{"run": "bash .github/tests/test-sentinel.sh"}]' "$work/base.yaml" >"$ci"
blocked 'boolean false test job'
CONDITION="\${{ github.event_name != 'merge_group' && !startsWith(github.head_ref, 'release-please--') && !startsWith(github.event.head_commit.message, 'chore(main): release ') }}" \
  yq '.jobs.tests.if = strenv(CONDITION) | .jobs.tests.steps += [{"run": "bash .github/tests/test-sentinel.sh"}]' "$work/base.yaml" >"$ci"
run_guard || fail 'supported CI event scheduling gate rejected'
echo 'PASS: supported merge-group and release scheduling exclusions'

# shellcheck disable=SC2016
for scope in step job; do
  for tolerate in true '"true"' '"${{ true }}"'; do
    TOLERATE="$tolerate" yq '.jobs.tests.steps += [{"run": "bash .github/tests/test-sentinel.sh"}]' "$work/base.yaml" >"$ci"
    if [[ "$scope" == step ]]; then
      TOLERATE="$tolerate" yq -i '.jobs.tests.steps[-1].continue-on-error = env(TOLERATE)' "$ci"
    else
      TOLERATE="$tolerate" yq -i '.jobs.tests.continue-on-error = env(TOLERATE)' "$ci"
    fi
    blocked "$scope suppresses failure: $tolerate"
  done
done
yq '.jobs.tests.continue-on-error = false | .jobs.tests.needs = [] | .jobs.tests.steps += [{"continue-on-error": false, "run": "bash .github/tests/test-sentinel.sh"}]' "$work/base.yaml" >"$ci"
run_guard || { cat "$work/result"; fail 'explicit false failure tolerance or empty dependencies rejected'; }
echo 'PASS: explicit false failure tolerance and empty dependencies'

for dependency in '"prerequisite"' '["prerequisite"]'; do
  DEPENDENCY="$dependency" yq '.jobs.prerequisite = {"if": false, "steps": [{"run": "echo skipped"}]} | .jobs.tests.needs = env(DEPENDENCY) | .jobs.tests.steps += [{"run": "bash .github/tests/test-sentinel.sh"}]' "$work/base.yaml" >"$ci"
  blocked "test depends on skipped prerequisite: $dependency"
done
# Removing only the prerequisite filter must restore this precise silent gap.
sed '/has("needs")/d' "$work/guard.sh" >"$work/no-prerequisite-check.sh"
if ! (cd "$work/repo" && bash -euo pipefail "$work/no-prerequisite-check.sh") >"$work/result" 2>&1; then
  fail 'prerequisite-filter ablation did not restore the skipped-job gap'
fi
echo 'PASS: removing prerequisite detection restores the skipped-job gap'

for command in 'bash .github/tests/test-sentinel.sh || true' 'bash .github/tests/test-sentinel.sh; true' 'bash .github/tests/test-sentinel.sh | cat' 'bash .github/tests/test-sentinel.sh &'; do
  COMMAND="$command" yq '.jobs.tests.steps += [{"run": strenv(COMMAND)}]' "$work/base.yaml" >"$ci"
  blocked "shell control operator: $command"
done

cp "$work/base.yaml" "$ci"
blocked 'deleted CI step'
for command in '# bash .github/tests/test-sentinel.sh' 'echo bash .github/tests/test-sentinel.sh' 'bash .github/tests/test-sentinel.sh.backup'; do
  COMMAND="$command" yq '.jobs.tests.steps += [{"name": "bash .github/tests/test-sentinel.sh", "run": strenv(COMMAND)}]' "$work/base.yaml" >"$ci"
  blocked "non-invocation: $command"
done

# A shell-looking line inside data or an uncalled function does not execute the
# test. Dedicated invocation steps keep the wiring contract statically decidable.
for command in \
  $'cat <<\'EOF\'\nbash .github/tests/test-sentinel.sh\nEOF' \
  $'echo "\nbash .github/tests/test-sentinel.sh\n"' \
  $'unused() {\nbash .github/tests/test-sentinel.sh\n}'; do
  COMMAND="$command" yq '.jobs.tests.steps += [{"run": strenv(COMMAND)}]' "$work/base.yaml" >"$ci"
  blocked "unexecuted multiline mention: $command"
done

# Helpers do not use the test-* entrypoint convention and need no exemption list.
rm "$work/repo/.github/tests/test-sentinel.sh"
touch "$work/repo/.github/tests/helper.sh"
cp "$work/base.yaml" "$ci"
run_guard || fail 'helper naming convention rejected'
echo 'PASS: helper filename needs no test step'

printf 'jobs: [invalid\n' >"$ci"
if run_guard; then fail 'malformed workflow was accepted'; fi
echo 'PASS: YAML read failure is not a clean wiring result'

echo 'PASS: CI refuses missing shell-test invocations'
