#!/usr/bin/env bash
# Table-driven test for the fail-closed review/pre-merge gate the privileged
# auto-merge workflow runs before approving or arming a trusted-bot PR
# (actions#548). Each fixture is a (reviews.json, comments.json) pair plus the
# expected verdict; the gate must treat every missing, stale, mixed, failed,
# superseded, or unparseable state as NOT green.

set -euo pipefail

script="${1:-.scripts/check-merge-gates.sh}"
fixtures_dir="${2:-.github/tests/merge-gate-fixtures}"
workflow="${3:-.github/workflows/enable-auto-merge.yaml}"

head_sha="$(printf 'a%.0s' {1..40})"
# The freshness floor the workflow derives from the head commit's committer
# date: fixture summaries dated on/after it are fresh, earlier ones stale.
head_committed_at="2026-07-11T09:00:00Z"
status=0

# The workflow must actually consume the gate: the gates step runs the script
# and both privileged steps are conditioned on its armable output.
if ! grep -q 'check-merge-gates.sh' "$workflow"; then
  echo "::error file=$workflow::auto-merge workflow does not run check-merge-gates.sh"
  status=1
fi

armable_conditions="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.name == "✅ Approve PR" or .name == "🔀 Enable Auto-Merge")
   | .if // ""]
  | join("\n")' "$workflow")"
if [[ "$(grep -c "steps.gates.outputs.armable == 'true'" <<<"$armable_conditions")" -ne 2 ]]; then
  echo "::error file=$workflow::Approve and Enable Auto-Merge steps must both be gated on steps.gates.outputs.armable"
  status=1
fi

while IFS= read -r fixture; do
  name="$(jq -r '.name' <<<"$fixture")"
  expect_green="$(jq -r '.expect_green' <<<"$fixture")"

  actual_green=false
  if bash "$script" "$head_sha" "$head_committed_at" \
    "$fixtures_dir/$name/reviews.json" \
    "$fixtures_dir/$name/comments.json" >/dev/null; then
    actual_green=true
  fi

  if [[ "$actual_green" != "$expect_green" ]]; then
    echo "::error file=$fixtures_dir/index.json::fixture '$name' expected green=$expect_green, got $actual_green"
    status=1
  else
    echo "fixture '$name': green=$actual_green"
  fi
done < <(jq -c '.[]' "$fixtures_dir/index.json")

exit "$status"
