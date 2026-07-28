#!/usr/bin/env bash
# Revoke any pending auto-merge for a pull request — BOTH arming shapes:
#   - a classic autoMergeRequest (disable with `gh pr merge --disable-auto`);
#   - a merge-queue entry (on merge-queue repos `--auto` ENQUEUES once
#     requirements are met and autoMergeRequest reads null, so a red gate
#     must DEQUEUE the entry or it merges from the queue regardless).
# Shared by the red-gate disarm step and the enforced-mode approval/handoff
# cleanup in the privileged auto-merge workflow. Prints what it revoked;
# exits 0 when nothing was pending. Fail-closed callers treat any error as a
# failed disarm.
#
# When an optional rejected-event timestamp is supplied, a newer auto-merge or
# merge-queue authorization is preserved. Callers using that mode must
# serialize this read/decision/mutation with the arming path.
#
# Usage: disarm-auto-merge.sh <repository> <pr-number> [rejected-run-created-at]

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <repository> <pr-number> [rejected-run-created-at]" >&2
  exit 2
fi

repository="$1"
pr_number="$2"
rejected_run_created_at="${3-}"
owner="${repository%%/*}"
name="${repository#*/}"

# shellcheck disable=SC2016  # GraphQL $variables, not shell expansion
state="$(gh api graphql \
  -f query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){id isInMergeQueue autoMergeRequest{enabledAt} mergeQueueEntry{enqueuedAt}}}}' \
  -f owner="$owner" -f name="$name" -F number="$pr_number" \
  --jq '.data.repository.pullRequest | "\(.id) \(.autoMergeRequest != null) \(.isInMergeQueue) \(.autoMergeRequest.enabledAt // "null") \(.mergeQueueEntry.enqueuedAt // "null")"')"
read -r pr_id armed queued auto_merge_enabled_at queue_enqueued_at <<<"$state"

if [[ -n "$rejected_run_created_at" ]]; then
  timestamps_valid=true
  if ! jq -en --arg value "$rejected_run_created_at" '$value | fromdateiso8601' >/dev/null 2>&1; then
    timestamps_valid=false
  fi
  for authorization_time in "$auto_merge_enabled_at" "$queue_enqueued_at"; do
    if [[ "$authorization_time" != "null" ]] &&
      ! jq -en --arg value "$authorization_time" '$value | fromdateiso8601' >/dev/null 2>&1; then
      timestamps_valid=false
    fi
  done

  if [[ "$timestamps_valid" == "true" ]] &&
    { [[ "$auto_merge_enabled_at" != "null" && "$auto_merge_enabled_at" > "$rejected_run_created_at" ]] ||
      [[ "$queue_enqueued_at" != "null" && "$queue_enqueued_at" > "$rejected_run_created_at" ]]; }; then
    echo "::notice::PR #${pr_number}: rejected event predates the current newer authorization; skipping stale revocation."
    exit 0
  fi
fi

if [[ "$armed" == "true" ]]; then
  gh pr merge "$pr_number" --disable-auto --repo "$repository"
  echo "::warning::Auto-merge DISARMED for PR #${pr_number}: fail-closed review-gate policy requires live maintenance-agent arming."
fi

if [[ "$queued" == "true" ]]; then
  # shellcheck disable=SC2016  # GraphQL $variables, not shell expansion
  gh api graphql \
    -f query='mutation($id:ID!){dequeuePullRequest(input:{id:$id}){clientMutationId}}' \
    -f id="$pr_id" >/dev/null
  echo "::warning::PR #${pr_number} DEQUEUED from the merge queue: fail-closed review-gate policy requires live maintenance-agent arming."
fi

if [[ "$armed" != "true" && "$queued" != "true" ]]; then
  echo "PR #${pr_number}: no pending auto-merge or merge-queue entry to revoke."
fi
