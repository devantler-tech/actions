#!/usr/bin/env bash
set -euo pipefail

workflow=${1:-.github/workflows/ci.yaml}
exempt_job=ci-required-checks

fail() {
  printf 'ci harden-runner first-step guard: %s\n' "$1" >&2
  exit 1
}

[ -f "$workflow" ] || fail "workflow not found: $workflow"

exempt_job_type="$(JOB_ID="$exempt_job" yq -r '.jobs[strenv(JOB_ID)] | type' "$workflow")"
[ "$exempt_job_type" = "!!map" ] ||
  fail "$exempt_job must exist as an inline job"

exempt_job_uses="$(JOB_ID="$exempt_job" yq -r '.jobs[strenv(JOB_ID)].uses // ""' "$workflow")"
[ -z "$exempt_job_uses" ] ||
  fail "$exempt_job must not call a reusable workflow"

exempt_steps_type="$(JOB_ID="$exempt_job" yq -r '.jobs[strenv(JOB_ID)].steps | type' "$workflow")"
[ "$exempt_steps_type" = "!!seq" ] ||
  fail "$exempt_job must define inline steps as a sequence"

exempt_job_uses="$(JOB_ID="$exempt_job" yq -r '[.jobs[strenv(JOB_ID)].steps[]? | select(.uses != null)] | length' "$workflow")"
[ "$exempt_job_uses" = 0 ] ||
  fail "$exempt_job must remain action-free, got $exempt_job_uses uses steps"

jobs=()
while IFS= read -r job; do
  jobs+=("$job")
done < <(EXEMPT_JOB="$exempt_job" yq -r '.jobs
  | to_entries
  | .[]
  | select(.value.steps | type == "!!seq")
  | select(.key != strenv(EXEMPT_JOB))
  | .key' "$workflow")

[ "${#jobs[@]}" -gt 0 ] ||
  fail "no step-bearing jobs were found"

missing=()
for job in "${jobs[@]}"; do
  first_uses="$(
    JOB_ID="$job" yq -r '.jobs[strenv(JOB_ID)].steps[0].uses // ""' "$workflow"
  )"
  egress_policy="$(
    JOB_ID="$job" yq -r '.jobs[strenv(JOB_ID)].steps[0].with."egress-policy" // ""' "$workflow"
  )"

  if [[ ! "$first_uses" =~ ^step-security/harden-runner@[0-9a-f]{40}$ ]] ||
    [[ "$egress_policy" != audit ]]; then
    missing+=("$job")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  printf 'ci harden-runner first-step guard: %d of %d eligible step-bearing jobs do not start with SHA-pinned harden-runner in audit mode:\n' "${#missing[@]}" "${#jobs[@]}" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

printf 'ci harden-runner first-step guard: all %d eligible step-bearing jobs are hardened first\n' "${#jobs[@]}"
