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

# The workflow must actually consume the gate: the gates step runs the script,
# both privileged steps are conditioned on its armable output, and the arming
# step re-runs the script immediately before `gh pr merge --auto` (an enforced
# green run must not arm past a review that turned red mid-run).
if [[ "$(grep -c 'check-merge-gates.sh' "$workflow")" -lt 2 ]]; then
  echo "::error file=$workflow::auto-merge workflow must run check-merge-gates.sh in the gates step AND re-run it pre-arm in the Enable Auto-Merge step"
  status=1
fi

# Backward compatibility for workflow_call consumers: a called workflow's
# GITHUB_TOKEN permissions can only be downgraded by callers' grants, so the
# job must never request more than the legacy documented minimum (the
# enforced path's extra read scopes come from the gate-lookup App token).
job_permissions="$(yq -r '.jobs."auto-merge".permissions | keys | sort | join(",")' "$workflow")"
if [[ "$job_permissions" != "contents,pull-requests" ]]; then
  echo "::error file=$workflow::auto-merge job permissions must stay at the legacy caller minimum (contents, pull-requests); got: $job_permissions"
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

# The disarm step must fail CLOSED when the gate step itself failed (a lookup
# error), not silently inherit success() and leave a stale arming in place: it
# needs a status-check override plus an explicit outcome-failure branch.
disarm_condition="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.name == "🔒 Disarm auto-merge on failed gates")
   | .if // ""]
  | join("\n")' "$workflow")"
if [[ "$disarm_condition" != *"!cancelled()"* ||
  "$disarm_condition" != *"steps.gates.outcome == 'failure'"* ||
  "$disarm_condition" != *"steps.gate-token.outcome == 'failure'"* ]]; then
  echo "::error file=$workflow::the disarm step must run on gate-step AND gate-token-mint failure (!cancelled() + both outcome == 'failure' branches), not only on armable == 'false'"
  status=1
fi

# Deleted reviewer evidence (a removed pre-merge summary or Codex clean pass)
# must re-trigger the gate so an enforced arming does not outlive its proof.
issue_comment_types="$(yq -r '.on.issue_comment.types | join(",")' "$workflow")"
if [[ "$issue_comment_types" != *"deleted"* ]]; then
  echo "::error file=$workflow::issue_comment trigger must include the deleted type (evidence deletion is a disarm path); got: $issue_comment_types"
  status=1
fi

# A branch returning to an earlier SHA re-uses that SHA's original check
# suites, so the freshness floor must also consider the newest force-push
# time — otherwise a summary written for an intervening head passes as fresh.
# The floor lives in the shared compute-head-seen-floor.sh, and the workflow
# must consume it BOTH in the gate step and in the pre-arm re-check (reusing
# the gate step's floor would miss a force-push between gate and arm).
floor_script="${4:-.scripts/compute-head-seen-floor.sh}"
if ! grep -q 'head_ref_force_pushed' "$floor_script"; then
  echo "::error file=$floor_script::the head-seen freshness floor must be raised by the newest head_ref_force_pushed timeline event"
  status=1
fi
if [[ "$(grep -c 'compute-head-seen-floor.sh' "$workflow")" -lt 2 ]]; then
  echo "::error file=$workflow::the workflow must compute the freshness floor via compute-head-seen-floor.sh in the gate step AND recompute it in the pre-arm re-check"
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
