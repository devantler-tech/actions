#!/usr/bin/env bash
# Failing-input counterpart to test-govulncheck-main-coverage.sh, per the repo convention
# that a gating self-test carries BOTH a passes-on-good-input and a blocks-on-bad-input
# test (AGENTS.md, "Failure-mode coverage for gating workflows").
#
# The guard it exercises is a *gate*: its job is to fail when the govulncheck trigger
# conditions would leave a default branch unscanned. A happy-path test alone cannot catch
# a guard that has silently stopped biting — and this guard is unusually easy to make
# vacuous, because its checks are structural string analysis over an expression. A
# regression in `defun`/`strip_groups` (say, one that makes `$top_level` always empty)
# would leave every assertion trivially satisfied and the positive test still green.
#
# Each fixture in ./govulncheck-main-coverage-fixture/ is a deliberately-bad workflow
# reproducing ONE way the trigger can be wrong. Asserting the *expected message* rather
# than merely a non-zero exit is what stops an operational error (a typo'd path, a missing
# yq) from false-passing as "the gate bit".
#
# The fixtures live outside .github/workflows/ so no real gate ever scans them.

set -euo pipefail

guard="${1:-.github/tests/test-govulncheck-main-coverage.sh}"
fixtures="${2:-.github/tests/govulncheck-main-coverage-fixture}"

status=0

# fixture file : substring the guard MUST report for it
expect_event_gated="restricts by 'github.event_name =='"
expect_no_default="has no default-branch clause"
expect_and_ed="AND-s the path filter"
expect_top_ref="AND-s a top-level ref predicate"
expect_allowlist="omits '\*\*/.govulncheck-allow.txt'"

check() {
  local fixture="$1" expected="$2" out rc
  local path="$fixtures/$fixture"

  if [[ ! -f "$path" ]]; then
    echo "::error::fixture $path is missing — the negative test cannot prove the gate bites"
    status=1
    return
  fi

  out="$(bash "$guard" "$path" 2>&1)" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    echo "::error file=$path::the guard PASSED a deliberately-bad fixture — it has stopped biting. Expected it to report: $expected"
    status=1
  elif ! grep -qE "$expected" <<<"$out"; then
    echo "::error file=$path::the guard failed, but not for the expected reason. Expected a message matching: $expected"
    while IFS= read -r line; do echo "    got: $line"; done <<<"$out"
    status=1
  else
    echo "blocks $fixture ✅"
  fi
}

check event-gated.yaml              "$expect_event_gated"
check no-default-branch-clause.yaml "$expect_no_default"
check default-branch-and-ed.yaml    "$expect_and_ed"
check top-level-ref-predicate.yaml  "$expect_top_ref"
check missing-allowlist-entries.yaml "$expect_allowlist"

# Sanity: the guard must still PASS the real workflow. Without this, deleting every check
# from the guard would make the five assertions above fail loudly — but a guard that
# rejects everything is just as broken as one that accepts everything, and this is the
# cheapest place to notice.
real=".github/workflows/validate-go-project.yaml"
if [[ -f "$real" ]]; then
  if bash "$guard" "$real" >/dev/null 2>&1; then
    echo "passes the real workflow ✅"
  else
    echo "::error file=$real::the guard REJECTS the real workflow; the negative fixtures above prove nothing about a gate that fails everything"
    status=1
  fi
fi

if [[ "$status" -eq 0 ]]; then
  echo "govulncheck trigger guard blocks every bad-input fixture and passes the real workflow ✅"
fi

exit "$status"
