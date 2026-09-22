#!/usr/bin/env bash
# Blocks-on-bad-input half of test-govulncheck-timeout-retry.sh (#1097). Each arm breaks one
# property of the vulnerability scan's bounded retry on a copy of validate-go-project.yaml and
# asserts the guard refuses it with that property's OWN message, so a fixture that fails for an
# unrelated reason cannot read as "caught". The pristine copy must pass first, or every refusal
# below could be an artefact of the sandbox.

set -euo pipefail

guard=".github/tests/test-govulncheck-timeout-retry.sh"
workflow=".github/workflows/validate-go-project.yaml"
scan='.jobs.govulncheck.steps[] | select(.id == "scan")'
classify='.jobs.govulncheck.steps[] | select(.id == "scan-timeout")'
retry='.jobs.govulncheck.steps[] | select((.if // "") | test("steps\.scan-timeout\.outputs\.retry"))'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

out="$(bash "$guard" "$workflow" 2>&1)" || fail "control — the real workflow does not pass the guard: ${out}"
echo "ok: control — the real workflow passes"

blocks() {
  # blocks <label> <yq mutation> <expected message fragment>
  local label="$1" mutation="$2" message="$3" fixture
  fixture="$work/$(tr -c '[:alnum:]' '-' <<<"$label").yaml"
  cp "$workflow" "$fixture"
  yq -i "$mutation" "$fixture"
  cmp -s "$workflow" "$fixture" && fail "${label} — the mutation changed nothing, so this arm proves nothing"
  if out="$(bash "$guard" "$fixture" 2>&1)"; then
    fail "${label} — the guard passed a broken retry: ${out}"
  fi
  grep -qF "$message" <<<"$out" || fail "${label} — refused for the wrong reason: ${out}"
  echo "ok: ${label}"
}

blocks "scan without continue-on-error" \
  "del(${scan} | .\"continue-on-error\")" \
  "must set continue-on-error: true"
blocks "retry step removed" \
  "del(${retry})" \
  "exactly one retry step"
blocks "retry pinned to a different action" \
  "(${retry}).uses = \"devantler/govulncheck-action@0000000000000000000000000000000000000000\"" \
  "same action pin as the scan step"
blocks "retry scanning something else" \
  "(${retry}).with.allow-file = \"\"" \
  "must match the scan step's exactly"
blocks "retry with a different deadline" \
  "(${retry}).\"timeout-minutes\" = 30" \
  "retry step's timeout-minutes must equal"
blocks "retry that tolerates failure" \
  "(${retry}).\"continue-on-error\" = true" \
  "must not set continue-on-error"
blocks "classifier with a drifted deadline" \
  "(${classify}).env.TIMEOUT_MINUTES = 30" \
  "TIMEOUT_MINUTES must equal"
blocks "classifier that only runs on failure" \
  "(${classify}).if = \"\${{ steps.scan.outcome == 'failure' }}\"" \
  "must run whenever the scan did not succeed"
blocks "classifier that retries every failure" \
  "(${classify}).run |= sub(\"elapsed >= TIMEOUT_MINUTES \\\\* 60\"; \"elapsed >= 0\")" \
  "must fail the job without a retry"
blocks "job ceiling below two attempts" \
  ".jobs.govulncheck.\"timeout-minutes\" = 57" \
  "pre-empts the retry"

echo "PASS: the timeout-retry guard refuses every broken retry for its own reason"
