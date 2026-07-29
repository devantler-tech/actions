#!/usr/bin/env bash
# Failing-input counterpart to test-ci-merge-group-isolation.sh. The fixture's
# pull-request predicate is a dead OR arm, so substring matching must not let it
# masquerade as a merge-group exclusion.

set -euo pipefail

guard="${1:-.github/tests/test-ci-merge-group-isolation.sh}"
fixture="${2:-.github/tests/ci-merge-group-isolation-bad-fixture.yaml}"
expected="jobs may execute merge-group-controlled code: unsafe-dead-disjunct"

if [[ ! -f "$fixture" ]]; then
  echo "::error::fixture $fixture is missing — the negative test cannot prove the gate bites"
  exit 1
fi

out="$(bash "$guard" "$fixture" 2>&1)" && rc=0 || rc=$?

if [[ "$rc" -eq 0 ]]; then
  echo "::error file=$fixture::the guard PASSED a deliberately-bad fixture — it has stopped biting"
  exit 1
fi

if ! grep -qF "$expected" <<<"$out"; then
  echo "::error file=$fixture::the guard failed for the wrong reason; expected: $expected"
  while IFS= read -r line; do echo "    got: $line"; done <<<"$out"
  exit 1
fi

echo "PASS: merge-group isolation guard blocks a misleading event disjunct"
