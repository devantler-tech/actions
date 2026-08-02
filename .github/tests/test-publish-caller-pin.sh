#!/usr/bin/env bash

# Guards the caller-pin contract on the two publish workflows that mint keyless cosign
# certificates. The certificate's SAN records `github.job_workflow_ref`, and the cluster's
# image/artifact trust rules verify against it — so a caller that invokes these workflows by a
# branch or a moving tag can have a superseded revision mint a signature the cluster still
# trusts. The guard requires a 40-character commit SHA, the one ref form that cannot move.
#
# The behavioural half executes the guard script EXTRACTED FROM THE WORKFLOW, never a
# transcription of it, so the assertions cannot drift away from what actually ships.

set -euo pipefail

signing_workflows=(
  ".github/workflows/publish-app.yaml"
  ".github/workflows/publish-manifests.yaml"
)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

guard_name="🔒 Require a SHA-pinned caller"

for workflow in "${signing_workflows[@]}"; do
  [[ -f "$workflow" ]] || fail "missing workflow: $workflow"

  # Every workflow here mints a signature, which is what makes the pin load-bearing.
  mints_signature="$(yq -r \
    '[.jobs[].permissions // {} | select(has("id-token"))] | length' "$workflow")"
  [[ "$mints_signature" -ge 1 ]] ||
    fail "$workflow no longer requests id-token; re-check whether it still needs the caller pin"

  job="$(yq -r '.jobs | keys | .[0]' "$workflow")"

  guard_count="$(GUARD_NAME="$guard_name" yq -r \
    '[.jobs[].steps[] | select(.name == strenv(GUARD_NAME))] | length' "$workflow")"
  [[ "$guard_count" == "1" ]] ||
    fail "$workflow must contain exactly one '$guard_name' step; found: $guard_count"

  # The guard has to bind the context itself. Reading github.job_workflow_ref inline inside the
  # run: body would work too, but the env binding is what keeps it out of shell interpolation.
  guard_env="$(GUARD_NAME="$guard_name" yq -r \
    '.jobs[].steps[] | select(.name == strenv(GUARD_NAME)) | .env.JOB_WORKFLOW_REF // ""' "$workflow")"
  # shellcheck disable=SC2016 # GitHub expression compared literally.
  [[ "$guard_env" == '${{ github.job_workflow_ref }}' ]] ||
    fail "$workflow guard must bind JOB_WORKFLOW_REF to github.job_workflow_ref; got: $guard_env"

  # Ordering matters: the pin must be decided before the job does any work that could publish or
  # sign. Checkout is the first such step in both workflows.
  guard_index="$(GUARD_NAME="$guard_name" JOB="$job" yq -r \
    '.jobs[strenv(JOB)].steps | to_entries
       | map(select(.value.name == strenv(GUARD_NAME))) | .[0].key' "$workflow")"
  checkout_index="$(JOB="$job" yq -r \
    '.jobs[strenv(JOB)].steps | to_entries
       | map(select((.value.uses // "") | test("^actions/checkout@")))
       | .[0].key' "$workflow")"
  [[ "$checkout_index" != "null" ]] ||
    fail "$workflow has no actions/checkout step to order the guard against"
  [[ "$guard_index" -lt "$checkout_index" ]] ||
    fail "$workflow guard must run before checkout (guard=$guard_index checkout=$checkout_index)"

  # ---- behavioural half: run the shipped script against every ref shape ----
  script="$(GUARD_NAME="$guard_name" yq -r \
    '.jobs[].steps[] | select(.name == strenv(GUARD_NAME)) | .run' "$workflow")"
  [[ -n "$script" ]] || fail "$workflow guard has an empty run: body"

  run_guard() {
    JOB_WORKFLOW_REF="$1" bash -euo pipefail -c "$script" >/dev/null 2>&1
  }

  sha40="0123456789abcdef0123456789abcdef01234567"
  base="devantler-tech/actions/${workflow}"

  # Accepted: exactly the shape every real caller uses today.
  run_guard "${base}@${sha40}" ||
    fail "$workflow guard rejected a 40-hex SHA caller, which every real caller uses"

  # Rejected: everything that can move, plus every near-miss on the SHA shape.
  rejected=(
    "${base}@refs/heads/main"
    "${base}@refs/tags/v1.2.3"
    "${base}@refs/pull/12/merge"
    "${base}@v10"
    "${base}@main"
    "${base}@0123456789abcdef0123456789abcdef0123456"
    "${base}@0123456789ABCDEF0123456789ABCDEF01234567"
    "${base}@${sha40}extra"
    "${base}"
    ""
  )
  for ref in "${rejected[@]}"; do
    if run_guard "$ref"; then
      fail "$workflow guard ACCEPTED a caller it must reject: '${ref:-<empty>}'"
    fi
  done

  echo "$workflow: caller pin enforced ✅"
done
