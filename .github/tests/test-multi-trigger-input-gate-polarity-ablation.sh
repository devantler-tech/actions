#!/usr/bin/env bash

# Ablation for test-multi-trigger-input-gate-polarity.sh (#1028). That guard only protects the
# org-required direct run if it (a) sees a bare truthy read of a default:true input wherever an
# expression is evaluated -- not only in `if:` -- and (b) does not reject the null-safe explicit
# comparison written with the input on the right. Each property is proven here on a fixture, and
# every refusal is checked for the guard's OWN message naming the input, so a fixture that fails
# for an unrelated reason (a parse error, a vacuity refusal) cannot read as "caught".

set -euo pipefail

guard=".github/tests/test-multi-trigger-input-gate-polarity.sh"
real=".github/workflows/validate-go-project.yaml"
call_only=".github/workflows/lint.yaml"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_guard() {
  bash "$guard" "$1" 2>&1
}

expect_pass() {
  local label="$1" fixture="$2" out
  out="$(run_guard "$fixture")" || fail "${label} — the guard refused a safe workflow: ${out}"
  grep -qF 'PASS:' <<<"$out" || fail "${label} — the guard exited 0 without printing PASS: ${out}"
  echo "ok: ${label}"
}

expect_flagged() {
  local label="$1" fixture="$2" out
  if out="$(run_guard "$fixture")"; then
    fail "${label} — the guard passed a bare truthy read: ${out}"
  fi
  grep -qF "input 'apply-fixes' (default: true) is read as a bare truthy value" <<<"$out" ||
    fail "${label} — the guard failed, but not for the bare read under test: ${out}"
  echo "ok: ${label}"
}

expect_refused() {
  local label="$1" fixture="$2" message="$3" out
  if out="$(run_guard "$fixture")"; then
    fail "${label} — the guard passed a workflow it must refuse: ${out}"
  fi
  grep -qF "$message" <<<"$out" || fail "${label} — refused for the wrong reason: ${out}"
  echo "ok: ${label}"
}

# A multi-trigger workflow with one default:true input and one innocuous job-level `if:`, so the
# guard's non-vacuity checks are satisfied and each fixture differs ONLY in the step under test.
fixture() {
  local path="$work/$1.yaml"
  cat >"$path" <<'YAML'
name: fixture
on:
  workflow_call:
    inputs:
      apply-fixes:
        type: boolean
        default: true
  pull_request:
permissions: {}
jobs:
  job:
    if: ${{ always() }}
    runs-on: ubuntu-latest
    steps:
YAML
  cat >>"$path"
  echo "$path"
}

# Controls: the real org-required workflow passes, and the guard still refuses to assert anything
# about a workflow_call-only file (lint.yaml, where a bare read is correct because defaults apply).
expect_pass "control — the real ${real} passes" "$real"
expect_refused "control — a workflow_call-only workflow is refused as vacuous" "$call_only" "is workflow_call-only"

# The exact env shape lint.yaml uses, lifted from lint.yaml itself so the fixture cannot drift from
# the pattern the guard exists to stop. Asserted non-empty, or every env arm below is a no-op.
lint_shape="$(yq -r '[.jobs[].steps[]?.env.APPLY_FIXES | select(. != null)] | .[0] // ""' "$call_only")"
[[ "$lint_shape" == *'inputs.apply-fixes &&'* ]] ||
  fail "lint.yaml no longer carries the APPLY_FIXES bare-read shape (got '${lint_shape}'); re-derive this fixture"

env_fixture="$(fixture env <<YAML
      - env:
          APPLY_FIXES: ${lint_shape}
        run: echo "\$APPLY_FIXES"
YAML
)"
expect_flagged "env — lint.yaml's APPLY_FIXES shape in a multi-trigger workflow is flagged" "$env_fixture"

expect_flagged "with — a bare read passed as an action input is flagged" "$(fixture with <<'YAML'
      - uses: ./some-action
        with:
          enabled: ${{ inputs.apply-fixes }}
YAML
)"

expect_flagged "run — a bare read interpolated into a run block is flagged" "$(fixture run <<'YAML'
      - run: |
          echo "starting"
          if [ "${{ inputs.apply-fixes }}" = "true" ]; then echo fixing; fi
YAML
)"

expect_flagged "if — a multi-line step if: with a bare read across the line break is flagged" "$(fixture if <<'YAML'
      - if: >-
          github.event_name == 'pull_request' &&
          inputs.apply-fixes
        run: echo fixing
YAML
)"

# One explicit comparison must not excuse a second, bare read in the same expression.
expect_flagged "mixed — a bare read beside a right-operand comparison is still flagged" "$(fixture mixed <<'YAML'
      - if: ${{ true == inputs.apply-fixes || inputs.apply-fixes }}
        run: echo fixing
YAML
)"

# cancel-in-progress is a boolean gate; only the concurrency GROUP (an identity key) is skipped.
expect_flagged "concurrency — a bare read in cancel-in-progress is flagged" "$(fixture cancel <<'YAML'
      - run: echo ok
concurrency:
  group: fixture
  cancel-in-progress: ${{ inputs.apply-fixes }}
YAML
)"

# Explicit comparisons are null-safe with the input on either side of the operator.
expect_pass "right operand — X == inputs.NAME and X != inputs.NAME are accepted" "$(fixture right-operand <<'YAML'
      - if: ${{ true == inputs.apply-fixes }}
        env:
          MODE: ${{ 'false' != inputs.apply-fixes && 'all' || 'none' }}
        run: echo "$MODE"
      - if: inputs.apply-fixes == true || inputs.apply-fixes == 'true'
        run: echo fixing
YAML
)"

expect_pass "concurrency — an input interpolated into a group key is accepted" "$(fixture group <<'YAML'
      - run: echo ok
concurrency:
  group: fixture-${{ inputs.apply-fixes }}
  cancel-in-progress: true
YAML
)"

# Non-vacuity: a multi-trigger workflow with nothing to scan is refused, never passed.
no_expressions="$work/no-expressions.yaml"
cat >"$no_expressions" <<'YAML'
name: fixture
on:
  workflow_call:
    inputs:
      apply-fixes:
        type: boolean
        default: true
  pull_request:
permissions: {}
jobs:
  job:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YAML
expect_refused "vacuity — a workflow with no expressions is refused" "$no_expressions" "no expressions found"

echo "PASS: the multi-trigger input-gate guard sees bare reads in every expression and accepts right-operand comparisons"
