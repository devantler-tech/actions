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

cp "$work/base.yaml" "$ci"
blocked 'deleted CI step'
for command in '# bash .github/tests/test-sentinel.sh' 'echo bash .github/tests/test-sentinel.sh' 'bash .github/tests/test-sentinel.sh.backup'; do
  COMMAND="$command" yq '.jobs.tests.steps += [{"name": "bash .github/tests/test-sentinel.sh", "run": strenv(COMMAND)}]' "$work/base.yaml" >"$ci"
  blocked "non-invocation: $command"
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
