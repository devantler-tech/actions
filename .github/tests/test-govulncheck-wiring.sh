#!/usr/bin/env bash
# Keep hosted allowlist/strict fixtures on the production implementation, whose
# scanner pin is now declared once inside the shared internal action.
set -euo pipefail
workflow="${1:-.github/workflows/validate-go-project.yaml}"
ci="${2:-.github/workflows/ci.yaml}"
fail() { echo "FAIL: $*" >&2; exit 1; }
gate="$(yq -r '.jobs.govulncheck.steps[] | select(.id == "scan") | .uses' "$workflow")"
[[ "$gate" == './.devantler-tech-actions/.github/actions/govulncheck' ]] || fail 'scan must use the shared internal implementation'
for job in test-govulncheck-allowlist-honored test-govulncheck-strict-blocks; do
  uses="$(yq -r ".jobs.\"$job\".steps[] | select(.with.\"work-dir\" != null) | .uses" "$ci")"
  [[ "$uses" == "${gate/.devantler-tech-actions\//}" ]] || fail "$job does not exercise the production scanner"
done
checkout="$(yq -o=json '[.jobs.govulncheck.steps[] | select(.with.path == ".devantler-tech-actions")]' "$workflow")"
jq -e '
  length == 1 and
  .[0].with.repository == "${{ job.workflow_repository }}" and
  .[0].with.ref == "${{ job.workflow_sha }}" and
  .[0].with["persist-credentials"] == false
' <<<"$checkout" >/dev/null || fail 'scanner checkout must use the workflow repository and exact commit without persisted credentials'
echo 'PASS: hosted fixtures exercise the exact implementation used by callers'

if (($# == 0)); then
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  blocks() {
    local label="$1" mutation="$2" expected="$3" out
    cp "$workflow" "$work/workflow.yaml"
    yq -i "$mutation" "$work/workflow.yaml"
    if out="$(bash "$0" "$work/workflow.yaml" "$ci" 2>&1)"; then
      fail "$label: accepted broken wiring"
    fi
    [[ "$out" == *"$expected"* ]] || fail "$label: wrong refusal: $out"
    echo "PASS: rejects $label"
  }
  blocks 'a different production scanner' \
    '(.jobs.govulncheck.steps[] | select(.id == "scan")).uses = "./another-action"' \
    'scan must use the shared internal implementation'
  blocks 'missing implementation checkout' \
    'del(.jobs.govulncheck.steps[] | select(.with.path == ".devantler-tech-actions"))' \
    'scanner checkout must use the workflow repository and exact commit'
  blocks 'mutable implementation checkout' \
    '(.jobs.govulncheck.steps[] | select(.with.path == ".devantler-tech-actions")).with.ref = "main"' \
    'scanner checkout must use the workflow repository and exact commit'
fi
