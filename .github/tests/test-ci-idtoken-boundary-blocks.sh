#!/usr/bin/env bash
# Failing-input counterpart to test-ci-idtoken-boundary.sh. One case per way the
# guard has been observed to fail open:
#
#   1. a dead OR arm naming the push event, so substring matching must not read
#      the job as push-only;
#   2. the scalar `write-all` shorthand at JOB scope, which grants id-token
#      without the string ever appearing;
#   3. the same shorthand at WORKFLOW scope, inherited by a job that declares no
#      permissions at all;
#   4. a trailing top-level `||`, which short-circuits past a correct leading
#      push-only conjunct because `&&` binds tighter than `||`;
#   5. text after the closing `}}`, which makes the scalar a non-empty STRING
#      rather than the expression's boolean, so the job runs on every event.
#
# Each fixture also carries a job the guard must NOT flag (a genuinely push-only
# job, or `read-all`), so a failure here can never be explained by the guard
# having become indiscriminate.

set -euo pipefail

guard="${1:-.github/tests/test-ci-idtoken-boundary.sh}"
dir="${2:-.github/tests}"

status=0

# The offender list is reported space-separated on one line, so `$expected`
# remains a prefix of the output even when the guard also names the fixture's
# positive control. Matching the expected string alone therefore accepts
# `unsafe-scalar-write-all safe-scalar-read-all` — an indiscriminate guard the
# positive controls exist to catch. Each control is named here and asserted
# ABSENT, which is what makes the header's claim above true.
check() {
  local fixture=$1 expected=$2
  shift 2
  # bash 3.2 (the macOS system shell agents run this under) treats `("$@")` and
  # `"${arr[@]}"` as unbound when empty, so the no-control case is guarded
  # rather than expanded.
  local controls=() out rc=0 control
  if (($# > 0)); then controls=("$@"); fi

  if [[ ! -f "$fixture" ]]; then
    echo "::error::fixture $fixture is missing — the negative test cannot prove the gate bites"
    status=1
    return
  fi

  out="$(bash "$guard" "$fixture" 2>&1)" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    echo "::error file=$fixture::the guard PASSED a deliberately-bad fixture — it has stopped biting"
    status=1
    return
  fi

  if ! grep -qF "$expected" <<<"$out"; then
    echo "::error file=$fixture::the guard failed for the wrong reason; expected: $expected"
    while IFS= read -r line; do echo "    got: $line"; done <<<"$out"
    status=1
    return
  fi

  for control in ${controls[@]+"${controls[@]}"}; do
    if grep -qF "$control" <<<"$out"; then
      echo "::error file=$fixture::the guard also flagged positive control $control — it has become indiscriminate"
      while IFS= read -r line; do echo "    got: $line"; done <<<"$out"
      status=1
      return
    fi
  done

  echo "PASS: $(basename "$fixture")"
}

check "$dir/ci-idtoken-boundary-bad-fixture.yaml" \
  "pull_request-eligible jobs grant id-token: write to PR-editable workflows: unsafe-dead-disjunct" \
  safe-push-only

check "$dir/ci-idtoken-boundary-writeall-job-fixture.yaml" \
  "pull_request-eligible jobs grant id-token: write to PR-editable workflows: unsafe-scalar-write-all" \
  safe-scalar-read-all

# The workflow-scope fixture fails before any job is classified, so it carries
# no positive control to assert absent.
check "$dir/ci-idtoken-boundary-writeall-workflow-fixture.yaml" \
  "workflow-level permissions grant id-token: write"

check "$dir/ci-idtoken-boundary-trailing-or-fixture.yaml" \
  "pull_request-eligible jobs grant id-token: write to PR-editable workflows: unsafe-trailing-disjunct" \
  safe-push-only

check "$dir/ci-idtoken-boundary-mixed-interpolation-fixture.yaml" \
  "pull_request-eligible jobs grant id-token: write to PR-editable workflows: unsafe-mixed-interpolation" \
  safe-push-only

if [[ "$status" -eq 0 ]]; then
  echo "PASS: OIDC boundary guard blocks every known fail-open shape"
fi
exit "$status"
