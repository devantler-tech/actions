#!/usr/bin/env bash
# Failing-input counterpart to test-ci-idtoken-boundary.sh. The fixture's offender
# names the push event inside a dead OR arm, so substring matching must not let it
# masquerade as a push-only job. The fixture's second job IS push-only and holds
# the same grant, so the expected message also proves the guard exempts it rather
# than rejecting every id-token grant it encounters.

set -euo pipefail

guard="${1:-.github/tests/test-ci-idtoken-boundary.sh}"
fixture="${2:-.github/tests/ci-idtoken-boundary-bad-fixture.yaml}"
expected="pull_request-eligible jobs grant id-token: write to PR-editable workflows: unsafe-dead-disjunct"

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

echo "PASS: OIDC boundary guard blocks a misleading event disjunct and exempts the push-only job"
