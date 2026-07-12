#!/usr/bin/env bash
# Table-driven test for the fail-closed review/pre-merge gate the privileged
# auto-merge workflow runs before approving a trusted-bot PR. Enforced mode
# leaves arming to the maintenance agent after its live pentad check
# (actions#548). Each fixture is a (reviews.json, comments.json) pair plus the
# expected verdict; the gate must treat every missing, stale, mixed, failed,
# superseded, or unparseable state as NOT green.

set -euo pipefail

script="${1:-.scripts/check-merge-gates.sh}"
fixtures_dir="${2:-.github/tests/merge-gate-fixtures}"
workflow="${3:-.github/workflows/enable-auto-merge.yaml}"
readme="${6:-README.md}"

head_sha="$(printf 'a%.0s' {1..40})"
# The freshness floor supplied by the workflow: fixture summaries dated on or
# after it are fresh; earlier ones are stale.
head_seen_at="2026-07-11T09:00:00Z"
status=0

# The workflow must actually consume the gate: the gates step runs the script,
# and both privileged steps are conditioned on its armable output. Enforced
# runs deliberately do not auto-arm because mutable review evidence cannot be
# bound atomically to `gh pr merge`; the maintenance agent performs that final
# live pentad check.
if [[ "$(grep -c 'check-merge-gates.sh' "$workflow")" -lt 1 ]]; then
  echo "::error file=$workflow::auto-merge workflow must run check-merge-gates.sh in the gates step"
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

gate_contents_permission="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.id == "gate-token")
   | .with."permission-contents" // ""]
  | join("\n")' "$workflow")"
if [[ "$gate_contents_permission" != "read" ]]; then
  echo "::error file=$workflow::the enforced gate token needs Contents: read to resolve abbreviated Codex commit IDs uniquely"
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
# must re-trigger the gate so stale legacy arming is actively revoked.
issue_comment_types="$(yq -r '.on.issue_comment.types | join(",")' "$workflow")"
if [[ "$issue_comment_types" != *"deleted"* ]]; then
  echo "::error file=$workflow::issue_comment trigger must include the deleted type (evidence deletion is a disarm path); got: $issue_comment_types"
  status=1
fi

pull_request_review_types="$(yq -r '.on.pull_request_review.types | join(",")' "$workflow")"
if [[ "$pull_request_review_types" != *"edited"* ]]; then
  echo "::error file=$workflow::pull_request_review trigger must include the edited type so changed reviewer evidence re-evaluates the gate; got: $pull_request_review_types"
  status=1
fi

# Reusable workflows cannot schedule their callers. The caller-facing Usage
# block must therefore carry the same edited-review disarm trigger as the
# workflow itself; consumers copy this example when opting into enforcement.
readme_auto_merge="$(awk '
  /^### .*Enable Auto-Merge/ { in_section = 1 }
  in_section { print }
  in_section && /^### .*Publish App/ { exit }
' "$readme")"
documented_review_types="$(grep -A1 'pull_request_review:' <<<"$readme_auto_merge" | tail -n 1)"
if [[ "$documented_review_types" != *"edited"* ]]; then
  echo "::error file=$readme::the Enable Auto-Merge caller example must include pull_request_review: edited; got: $documented_review_types"
  status=1
fi

# Codex findings are submitted as pull-request reviews, not issue comments.
# The job must therefore re-evaluate for both supported reviewer bots; parsing
# Codex review objects is ineffective if their submitted event never runs it.
job_condition="$(yq -r '.jobs."auto-merge".if // ""' "$workflow")"
if [[ "$(grep -oF 'chatgpt-codex-connector[bot]' <<<"$job_condition" | wc -l | tr -d ' ')" -lt 2 ]]; then
  echo "::error file=$workflow::pull_request_review runs must include chatgpt-codex-connector[bot] so findings actively disarm"
  status=1
fi

# A branch returning to an earlier SHA re-uses that SHA's original check
# suites, so the freshness floor must also consider the newest force-push
# time — otherwise a summary written for an intervening head passes as fresh.
# The floor lives in the shared compute-head-seen-floor.sh, and the workflow
# must consume it in the gate step.
floor_script="${4:-.scripts/compute-head-seen-floor.sh}"
if ! grep -q 'head_ref_force_pushed' "$floor_script"; then
  echo "::error file=$floor_script::the head-seen freshness floor must be raised by the newest head_ref_force_pushed timeline event"
  status=1
fi
if [[ "$(grep -c 'compute-head-seen-floor.sh' "$workflow")" -lt 1 ]]; then
  echo "::error file=$workflow::the workflow must compute the freshness floor via compute-head-seen-floor.sh in the gate step"
  status=1
fi

# Commit metadata is never a safe floor: pushing a previously-created commit
# carries an old committer date, and a summary from the PREVIOUS head can
# postdate it. The floor script must fail closed instead of falling back.
if grep -q -- '--jq .commit.committer.date' "$floor_script"; then
  echo "::error file=$floor_script::the freshness floor must never fall back to the commit committer date (fail closed instead)"
  status=1
fi

# Revocation must cover BOTH arming shapes (autoMergeRequest + merge-queue
# entry) and fire from all three safety points: the red-gate disarm step,
# before an enforced approval (approval itself may satisfy a stale arming),
# and the enforced green handoff after approval.
disarm_script="${5:-.scripts/disarm-auto-merge.sh}"
if ! grep -q 'dequeuePullRequest' "$disarm_script"; then
  echo "::error file=$disarm_script::disarm must dequeue merge-queue entries (dequeuePullRequest), not only --disable-auto"
  status=1
fi
if [[ "$(grep -c 'disarm-auto-merge.sh' "$workflow")" -lt 3 ]]; then
  echo "::error file=$workflow::the workflow must revoke in the red-gate step, before enforced approval, and in the enforced green handoff"
  status=1
fi

# Mutable review/pre-merge evidence can turn red after any final snapshot and
# before `gh pr merge`; GitHub has no atomic merge primitive that binds those
# surfaces. Enforced mode must therefore take the issue's conservative
# fallback: always revoke stale arming and exit before the merge call, leaving
# arming to the maintenance agent's live pentad check. The step must still run
# after an approval failure so it can revoke a previous arming first.
pre_arm_run="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.name == "🔀 Enable Auto-Merge")
  | .run // ""]
  | join("\n")' "$workflow")"

approve_id="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.name == "✅ Approve PR")
   | .id // ""]
  | join("\n")' "$workflow")"
if [[ "$approve_id" != "approve" ]]; then
  echo "::error file=$workflow::Approve PR step must expose id=approve so enforced cleanup can observe approval failure"
  status=1
fi

approve_run="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.name == "✅ Approve PR")
   | .run // ""]
  | join("\n")' "$workflow")"
approve_disarm_line="$(grep -nF 'disarm-auto-merge.sh' <<<"$approve_run" | head -1 | cut -d: -f1 || true)"
# shellcheck disable=SC2016 # Match the literal workflow shell, not this test's variables.
approve_api_line="$(grep -nF 'gh api "repos/$REPOSITORY/pulls/$PR_NUMBER/reviews"' <<<"$approve_run" | head -1 | cut -d: -f1 || true)"
if [[ -z "$approve_disarm_line" || -z "$approve_api_line" || "$approve_disarm_line" -ge "$approve_api_line" ]]; then
  echo "::error file=$workflow::enforced approval must revoke stale auto-merge state BEFORE posting the approval"
  status=1
fi

enable_condition="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.name == "🔀 Enable Auto-Merge")
   | .if // ""]
  | join("\n")' "$workflow")"
if [[ "$enable_condition" != *"!cancelled()"* ||
  "$enable_condition" != *"steps.gates.outputs.armable == 'true'"* ]]; then
  echo "::error file=$workflow::Enable Auto-Merge must run after approval failure (!cancelled + armable) so enforced cleanup cannot be skipped"
  status=1
fi

if ! grep -Fq 'APPROVE_OUTCOME' <<<"$pre_arm_run"; then
  echo "::error file=$workflow::Enable Auto-Merge must check the Approve PR outcome after enforced cleanup"
  status=1
fi
if ! grep -Fq 'enforced fallback leaves auto-arming to the maintenance agent' <<<"$pre_arm_run"; then
  echo "::error file=$workflow::enforced mode must document the conservative no-auto-arm fallback"
  status=1
fi
# shellcheck disable=SC2016 # Match the literal workflow shell, not this test's variables.
if ! grep -Fq 'bash .devantler-tech-actions/.scripts/disarm-auto-merge.sh "$REPOSITORY" "$PR_NUMBER"' <<<"$pre_arm_run"; then
  echo "::error file=$workflow::enforced green runs must revoke any stale auto-merge request before handing off"
  status=1
fi
if grep -Fq 'check-merge-gates.sh' <<<"$pre_arm_run" || grep -Fq 'GATE_TOKEN' <<<"$pre_arm_run"; then
  echo "::error file=$workflow::Enable Auto-Merge must not pretend a second mutable evidence snapshot makes auto-arming atomic"
  status=1
fi

handoff_line="$(grep -nF 'enforced fallback leaves auto-arming to the maintenance agent' <<<"$pre_arm_run" | head -1 | cut -d: -f1 || true)"
handoff_exit_line="$(awk -v start="$handoff_line" 'NR > start && /exit 0/ {print NR; exit}' <<<"$pre_arm_run")"
# shellcheck disable=SC2016 # Match the literal workflow shell, not this test's variables.
merge_line="$(grep -nF 'gh pr merge "$PR_NUMBER" --auto' <<<"$pre_arm_run" | head -1 | cut -d: -f1 || true)"
if [[ -z "$handoff_line" || -z "$handoff_exit_line" || -z "$merge_line" || "$handoff_exit_line" -ge "$merge_line" ]]; then
  echo "::error file=$workflow::enforced fallback must exit before the legacy default-off gh pr merge call"
  status=1
fi

# The head-seen floor must ignore check suites created for some other PR that
# happened to use the same commit SHA. Reusing the oldest cross-branch suite
# makes a stale summary look newer than the PR's adoption of the head.
floor_test_dir="$(mktemp -d)"
trap 'rm -rf "$floor_test_dir"' EXIT
mkdir -p "$floor_test_dir/bin"
cat >"$floor_test_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${2:-}" in
  repos/test/repo/commits/*/check-suites)
    cat <<'JSON'
{"check_suites":[
  {"id":1,"created_at":"2026-07-11T08:00:00Z","pull_requests":[{"number":999}]},
  {"id":2,"created_at":"2026-07-11T10:00:00Z","pull_requests":[{"number":42}]}
]}
JSON
    ;;
  repos/test/repo/issues/42/timeline)
    printf '[]\n'
    ;;
  repos/test/repo/commits/aaaaaaaaaa)
    if [[ "${MOCK_UNRESOLVABLE_PREFIX:-false}" == "true" ]]; then
      echo "ambiguous commit prefix" >&2
      exit 1
    fi
    printf '%s\n' "$(printf 'a%.0s' {1..40})"
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$floor_test_dir/bin/gh"
floor_result="$(PATH="$floor_test_dir/bin:$PATH" bash "$floor_script" \
  test/repo 42 "$head_sha" '' issue_comment)" || status=1
if [[ "$floor_result" != "2026-07-11T10:00:00Z" ]]; then
  echo "::error file=$floor_script::head-seen floor must use this PR's earliest suite; got '$floor_result'"
  status=1
fi

while IFS= read -r fixture; do
  name="$(jq -r '.name' <<<"$fixture")"
  expect_green="$(jq -r '.expect_green' <<<"$fixture")"

  actual_green=false
  mock_unresolvable_prefix=false
  if [[ "$name" == "codex-abbreviated-head-unresolvable" ]]; then
    mock_unresolvable_prefix=true
  fi
  if REPOSITORY=test/repo MOCK_UNRESOLVABLE_PREFIX="$mock_unresolvable_prefix" \
    PATH="$floor_test_dir/bin:$PATH" bash "$script" "$head_sha" "$head_seen_at" \
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
