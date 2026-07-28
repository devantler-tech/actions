#!/usr/bin/env bash
# Revoke an untrusted pull-request event unless a newer trusted event from the
# same caller workflow and PR is positively proven. Every lookup or parse
# failure falls through to revocation; the only non-revocation exit is a
# trusted superseding run selected by find-trusted-superseding-pr-run.sh.
#
# Usage:
#   disarm-untrusted-event.sh \
#     <repository> <pr-number> <run-id> <event-head> \
#     <event-updated-at> <trusted-actors-json>

set -uo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: $0 <repository> <pr-number> <run-id> <event-head> <event-updated-at> <trusted-actors-json>" >&2
  exit 2
fi

repository="$1"
pr_number="$2"
run_id="$3"
event_head="$4"
event_updated_at="$5"
trusted_actors="$6"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1

revoke_fail_closed() {
  bash "$script_dir/disarm-auto-merge.sh" "$repository" "$pr_number"
}

if ! pr_json=$(gh pr view "$pr_number" --repo "$repository" --json headRefOid,updatedAt); then
  echo "::warning::PR #${pr_number}: live PR lookup failed; revoking fail-closed."
  revoke_fail_closed
  exit $?
fi
if ! live_head=$(jq -er '.headRefOid // empty' <<<"$pr_json") ||
  ! live_updated_at=$(jq -er '.updatedAt // empty' <<<"$pr_json"); then
  echo "::warning::PR #${pr_number}: live PR state was malformed; revoking fail-closed."
  revoke_fail_closed
  exit $?
fi

if [[ "$live_head" == "$event_head" && "$live_updated_at" == "$event_updated_at" ]]; then
  revoke_fail_closed
  exit $?
fi

if ! workflow_id=$(gh api "repos/$repository/actions/runs/$run_id" --jq .workflow_id); then
  echo "::warning::PR #${pr_number}: workflow identity lookup failed; revoking fail-closed."
  revoke_fail_closed
  exit $?
fi
if [[ ! "$workflow_id" =~ ^[0-9]+$ ]]; then
  echo "::warning::PR #${pr_number}: workflow identity lookup returned malformed data; revoking fail-closed."
  revoke_fail_closed
  exit $?
fi

if ! run_pages=$(
  gh api "repos/$repository/actions/runs" --method GET --paginate \
    -f event=pull_request -f per_page=100 -f created=">=${event_updated_at}" |
    jq -s .
); then
  echo "::warning::PR #${pr_number}: workflow run lookup failed; revoking fail-closed."
  revoke_fail_closed
  exit $?
fi

if latest_actor=$(
  bash "$script_dir/find-trusted-superseding-pr-run.sh" \
    "$run_id" "$workflow_id" "$pr_number" "$trusted_actors" <<<"$run_pages"
); then
  echo "::notice::PR #${pr_number}: rejected event was superseded by a newer trusted pull_request run from ${latest_actor}; skipping stale revocation."
  exit 0
fi

echo "::notice::PR #${pr_number}: no trusted same-workflow reauthorization was proven; revoking fail-closed."
revoke_fail_closed
