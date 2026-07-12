#!/usr/bin/env bash
# Freshness floor for CodeRabbit's pre-merge summary: the time GitHub last saw
# the given SHA BECOME the PR head. Shared by the gate step and the pre-arm
# re-check of the privileged auto-merge workflow (the re-check must recompute
# it — a branch force-pushed away and back to the same SHA between gate and
# arm would otherwise be compared against a stale floor).
#
# Usage: compute-head-seen-floor.sh <repository> <pr-number> <head-sha> [own-run-id] [event-name]
#   repository   owner/name
#   pr-number    the pull request number (for the force-push timeline lookup)
#   head-sha     the head commit SHA
#   own-run-id   this workflow run's id — its own check suite is created by
#                the triggering event itself (often AFTER the summary edit
#                that triggered it), so as the only suite for a head it would
#                poison the floor and wedge arming; it is excluded from part 1.
#   event-name   the triggering event (github.event_name) — on a pull_request
#                event the run's OWN suite was created by the push itself, so
#                it is a safe floor when no other suite exists (part 2).
#
# Floor construction (each part raises, never lowers — fail-closed):
#   1. earliest check-suite created_at for the SHA (excluding this run's own
#      suite) — when GitHub first saw the commit; commit metadata alone is NOT
#      a safe floor (pushing a previously-created commit object carries an old
#      committer date, and a pre-existing summary from the PREVIOUS head can
#      postdate it — a committer-date floor would let that stale summary pass);
#   2. when no other suite exists yet: on a pull_request-event run the own
#      suite's created_at IS push time and is used; on comment/review-driven
#      runs there is NO provable head-seen time, so the script FAILS (exit 1)
#      and the caller's gate fails closed — never a committer-date fallback;
#   3. raised to the newest head_ref_force_pushed time when one exists — a
#      branch that RETURNS to an earlier SHA re-uses that SHA's original check
#      suites, so without this a summary written for an intervening head would
#      pass as fresh.

set -euo pipefail

if [[ $# -lt 3 || $# -gt 5 ]]; then
  echo "usage: $0 <repository> <pr-number> <head-sha> [own-run-id] [event-name]" >&2
  exit 2
fi

repository="$1"
pr_number="$2"
head_sha="$3"
own_run_id="${4:-}"
event_name="${5:-}"

own_suite_id=""
if [[ -n "$own_run_id" ]]; then
  own_suite_id=$(gh api "repos/$repository/actions/runs/$own_run_id" --jq '.check_suite_id // empty')
fi

suites_json=$(gh api "repos/$repository/commits/$head_sha/check-suites" --paginate | jq -s '[.[].check_suites[]?]')
floor=$(jq -r --arg own "$own_suite_id"   '[.[] | select((.id | tostring) != $own) | .created_at | select(. != null)] | min // empty' <<<"$suites_json")
if [[ -z "$floor" && "$event_name" == "pull_request" && -n "$own_suite_id" ]]; then
  floor=$(jq -r --arg own "$own_suite_id"     '[.[] | select((.id | tostring) == $own) | .created_at | select(. != null)] | min // empty' <<<"$suites_json")
fi
if [[ -z "$floor" ]]; then
  echo "::error::cannot prove when $head_sha became the PR head (no usable check suite on a ${event_name:-non-pull_request} run) — failing closed." >&2
  exit 1
fi

last_force_push_at=$(gh api "repos/$repository/issues/$pr_number/timeline" --paginate |
  jq -rs '[.[][] | select(.event == "head_ref_force_pushed") | .created_at | select(. != null)] | max // empty')
if [[ -n "$last_force_push_at" && "$last_force_push_at" > "$floor" ]]; then
  floor="$last_force_push_at"
fi

printf '%s\n' "$floor"
