#!/usr/bin/env bash
# Guards the bounded retry on validate-go-project.yaml's vulnerability scan (#1097).
#
# A job that hits its own timeout-minutes ends `cancelled`, and a cancelled required check is
# terminal: Dependabot never reruns it, auto-merge waits forever, and nothing notices. So the scan
# STEP carries its own deadline, with continue-on-error, and a classifier step decides from the
# elapsed time whether the attempt ran out of time. Only a timeout earns exactly one retry; any
# other failure (a reachable advisory, an operational error) fails the job immediately, so a real
# finding is never retried away. The job-level ceiling stays finite but sits above two attempts
# plus the post-job cache save, so it cannot pre-empt the retry and turn the run `cancelled` again.
#
# This script checks that structure on the given workflow and then drives the classifier's own
# run block through each case. test-govulncheck-timeout-retry-blocks.sh proves each structural
# assertion fires on a fixture that violates it, and the `[Test] Govulncheck - A Timed-Out Scan Is
# Retried Once` job in ci.yaml proves GitHub's step-timeout semantics against a real step that
# deliberately outlives its deadline.

set -euo pipefail

workflow="${1:-.github/workflows/validate-go-project.yaml}"
# Minutes of job time beyond two attempts: checkout/setup plus setup-go's post-job cache save,
# which measured 6m07s after a passing scan on ksail (#1097, 2026-09-06 comment).
overhead_minutes=10

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$workflow" ]] || fail "workflow not found: $workflow"

step() {
  # step <id> <yq path suffix> — one field of the govulncheck step with that id, or empty.
  yq -o=json -I=0 ".jobs.govulncheck.steps[] | select(.id == \"$1\") | $2" "$workflow"
}

step_index() {
  yq -r ".jobs.govulncheck.steps | to_entries[] | select(.value.id == \"$1\") | .key" "$workflow"
}

retry_index="$(
  yq -r '.jobs.govulncheck.steps | to_entries[]
    | select((.value.if // "") | test("steps\.scan-timeout\.outputs\.retry"))
    | .key' "$workflow"
)"

# ── structure ────────────────────────────────────────────────────────────────────────────────
for id in scan-clock scan scan-timeout; do
  [[ -n "$(step_index "$id")" ]] || fail "govulncheck has no step with id '$id'; the timeout retry cannot work without it"
done
[[ -n "$retry_index" && "$(grep -c . <<<"$retry_index")" -eq 1 ]] ||
  fail "govulncheck must have exactly one retry step gated on steps.scan-timeout.outputs.retry; found: '${retry_index}'"

clock_i="$(step_index scan-clock)"
scan_i="$(step_index scan)"
classify_i="$(step_index scan-timeout)"
((clock_i < scan_i && scan_i < classify_i && classify_i < retry_index)) ||
  fail "govulncheck steps must run clock → scan → classifier → retry; got indices ${clock_i}, ${scan_i}, ${classify_i}, ${retry_index}"

# shellcheck disable=SC2016 # the literal command text the step must contain, never an expansion
grep -qF 'started=$(date +%s)' <<<"$(step scan-clock '.run')" ||
  fail "the scan-clock step must record the attempt's start as started=\$(date +%s)"

[[ "$(step scan '."continue-on-error"')" == "true" ]] ||
  fail "the scan step must set continue-on-error: true, or its timeout fails the job before the classifier can retry it"

attempt_timeout="$(step scan '."timeout-minutes"')"
if [[ ! "$attempt_timeout" =~ ^[0-9]+$ ]] || ((attempt_timeout == 0)); then
  fail "the scan step must carry a literal step-level timeout-minutes; got '${attempt_timeout}'"
fi

retry_step() {
  yq -o=json -I=0 ".jobs.govulncheck.steps[${retry_index}] | $1" "$workflow"
}

[[ "$(retry_step '.uses')" == "$(step scan '.uses')" ]] ||
  fail "the retry step must use the same action pin as the scan step"
[[ "$(retry_step '.with')" == "$(step scan '.with')" ]] ||
  fail "the retry step's with: must match the scan step's exactly, so a retry scans the same thing"
[[ "$(retry_step '."timeout-minutes"')" == "$attempt_timeout" ]] ||
  fail "the retry step's timeout-minutes must equal the scan step's (${attempt_timeout})"
[[ "$(retry_step '."continue-on-error" // false')" == "false" ]] ||
  fail "the retry step must not set continue-on-error: a second timeout or any failure has to fail the check"

classify_if="$(step scan-timeout '.if // ""')"
grep -qE "steps\.scan\.outcome[[:space:]]*!=[[:space:]]*'success'" <<<"$classify_if" ||
  fail "the classifier must run whenever the scan did not succeed (if: steps.scan.outcome != 'success'); got ${classify_if}"
[[ "$(step scan-timeout '.env.TIMEOUT_MINUTES')" == "$attempt_timeout" ]] ||
  fail "the classifier's TIMEOUT_MINUTES must equal the scan step's timeout-minutes (${attempt_timeout})"
grep -qF 'steps.scan-clock.outputs.started' <<<"$(step scan-timeout '.env.STARTED')" ||
  fail "the classifier's STARTED must come from steps.scan-clock.outputs.started"

job_timeout="$(yq -r '.jobs.govulncheck."timeout-minutes" // ""' "$workflow")"
[[ "$job_timeout" =~ ^[0-9]+$ ]] ||
  fail "govulncheck must keep a finite, literal job timeout-minutes; got '${job_timeout}'"
((job_timeout >= 2 * attempt_timeout + overhead_minutes)) ||
  fail "govulncheck's job timeout-minutes (${job_timeout}) must be >= two attempts (2 × ${attempt_timeout}) + ${overhead_minutes} min overhead, or the job cap pre-empts the retry and the run ends cancelled again"

echo "ok: structure — clock, scan (${attempt_timeout}m, continue-on-error), classifier, one retry; job cap ${job_timeout}m"

# ── classifier behaviour ─────────────────────────────────────────────────────────────────────
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
yq -r '.jobs.govulncheck.steps[] | select(.id == "scan-timeout") | .run' "$workflow" >"$work/classify.sh"

classify() {
  # classify <outcome> <started> <timeout-minutes> → sets rc, out, retry
  : >"$work/output"
  rc=0
  out="$(OUTCOME="$1" STARTED="$2" TIMEOUT_MINUTES="$3" GITHUB_OUTPUT="$work/output" bash "$work/classify.sh" 2>&1)" || rc=$?
  retry="$(sed -n 's/^retry=//p' "$work/output")"
}

now="$(date +%s)"

classify failure "$((now - 60 - 5))" 1
[[ "$rc" -eq 0 && "$retry" == "true" ]] ||
  fail "a scan that outlived its deadline must be retried (exit 0, retry=true); got rc=${rc} retry='${retry}': ${out}"
grep -qF '::warning::' <<<"$out" || fail "a retried timeout must leave a visible ::warning:: annotation: ${out}"
echo "ok: a scan that ran out of time is retried once, with a warning"

classify failure "$((now - 30))" 1
[[ "$rc" -ne 0 && -z "$retry" ]] ||
  fail "a scan that failed before its deadline (a finding) must fail the job without a retry; got rc=${rc} retry='${retry}': ${out}"
grep -qF '::error::' <<<"$out" || fail "a non-timeout failure must say why it is not retried: ${out}"
echo "ok: a scan that failed before its deadline fails the job and is not retried"

classify failure "" 1
[[ "$rc" -ne 0 && -z "$retry" ]] ||
  fail "an unreadable start time must fail closed, never retry or pass; got rc=${rc} retry='${retry}': ${out}"
classify failure "$now" "abc"
[[ "$rc" -ne 0 && -z "$retry" ]] ||
  fail "an unreadable deadline must fail closed, never retry or pass; got rc=${rc} retry='${retry}': ${out}"
echo "ok: an unreadable start or deadline fails closed"

echo "PASS: the vulnerability scan retries exactly once on a timeout and never on a finding"
