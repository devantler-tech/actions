#!/usr/bin/env bash

# Exercise aggregate-job-checks' actual run block against every class of job result it can be
# handed, asserting the exit status AND which message was printed (#1098). Three failure paths
# exist and must stay distinguishable, because each points the reader at a different remedy:
#
#   * failure / cancelled  -> a job genuinely failed; fix or re-run it;
#   * abandoned            -> GitHub gave up on a job (a runner/infrastructure outcome, not in the
#                             four documented needs.<job>.result values, but emitted in practice:
#                             devantler-tech/ksail#6655); re-run it;
#   * anything else        -> a malformed `job-results` input; fix the calling workflow.
#
# An exit status alone cannot tell those apart, so every case checks the message too.

set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
action="$root/aggregate-job-checks/action.yaml"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

yq -r '.runs.steps[] | select(.run != null) | .run' "$action" >"$work/aggregate.sh"
[[ -s "$work/aggregate.sh" ]] || {
  echo "FAIL: no run block extracted from $action" >&2
  exit 1
}

check_name="Fixture Check"
passed_msg="✅ ${check_name} — all jobs succeeded or were skipped."
failed_msg="❌ ${check_name} — at least one job failed or was cancelled."
abandoned_msg="❌ ${check_name} — at least one job was abandoned by GitHub"
unknown_prefix="❌ ${check_name} — unknown job result:"

failures=0

# check <label> <job-results> <expected-exit> <must-contain...> -- <must-not-contain...>
check() {
  local label="$1" results="$2" want_rc="$3" out rc=0 needle
  shift 3
  out="$(JOB_RESULTS="$results" CHECK_NAME="$check_name" bash "$work/aggregate.sh" 2>&1)" || rc=$?
  if [[ "$rc" != "$want_rc" ]]; then
    echo "FAIL: ${label} — exit ${rc}, want ${want_rc}; output: ${out}" >&2
    failures=$((failures + 1))
    return
  fi
  local mode=want
  for needle in "$@"; do
    if [[ "$needle" == "--" ]]; then
      mode=reject
      continue
    fi
    if [[ "$mode" == want && "$out" != *"$needle"* ]]; then
      echo "FAIL: ${label} — missing '${needle}'; output: ${out}" >&2
      failures=$((failures + 1))
      return
    fi
    if [[ "$mode" == reject && "$out" == *"$needle"* ]]; then
      echo "FAIL: ${label} — unexpected '${needle}'; output: ${out}" >&2
      failures=$((failures + 1))
      return
    fi
  done
  echo "ok: ${label}"
}

# Passing classes.
check "empty input passes" "" 0 "$passed_msg" -- "❌"
check "success and skipped pass" "success skipped success" 0 "$passed_msg" -- "❌"

# failure / cancelled: the job-failed message, never the abandoned or malformed-input one.
check "a failed job fails" "success failure skipped" 1 "$failed_msg" -- "$abandoned_msg" "$unknown_prefix"
check "a cancelled job fails" "success cancelled" 1 "$failed_msg" -- "$abandoned_msg" "$unknown_prefix"

# abandoned: fails (passing it would be the unsafe direction) with its own message and remedy.
check "an abandoned job fails as abandoned" "success abandoned skipped" 1 \
  "$abandoned_msg" "Re-run" -- "$unknown_prefix" "$failed_msg" "$passed_msg"
check "abandoned beside a real failure reports both" "abandoned failure" 1 \
  "$abandoned_msg" "$failed_msg" -- "$unknown_prefix"

# Anything else: the unchanged malformed-input message, even when an abandoned job is also
# present, so a broken `job-results` input can never be mistaken for a GitHub-side outcome.
check "an unrecognised value fails as malformed input" "success unknown-status" 1 \
  "${unknown_prefix} 'unknown-status'. Allowed values: success, failure, cancelled, skipped." -- "$abandoned_msg" "$failed_msg"
check "an unrecognised value outranks an abandoned job" "abandoned bogus" 1 \
  "${unknown_prefix} 'bogus'." -- "$abandoned_msg"
check "a glob is reported literally, never expanded" "*" 1 "${unknown_prefix} '*'." -- "$abandoned_msg"

[[ "$failures" -eq 0 ]] || {
  echo "FAIL: ${failures} aggregate-job-checks case(s) failed" >&2
  exit 1
}
echo "PASS: aggregate-job-checks classifies every job result and reports it distinctly"
